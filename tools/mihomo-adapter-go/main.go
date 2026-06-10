package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/config"
	CN "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v3"
)

var (
	stateMu    sync.Mutex
	configPath string
	tunFd      = -1
	running    bool
	lastError  string
	startedAt  string
	statsText  = "adapterKind=mihomo-go-direct; running=false; message=adapter initialized"
)

func setStatsLocked(extra string) {
	parts := []string{
		"adapterKind=mihomo-go-direct",
		"running=" + boolText(running),
		fmt.Sprintf("tunFd=%d", tunFd),
		"configPath=" + configPath,
		"goos=" + runtime.GOOS,
		"goarch=" + runtime.GOARCH,
		"goVersion=" + runtime.Version(),
	}
	if startedAt != "" {
		parts = append(parts, "startedAt="+startedAt)
	}
	if lastError != "" {
		parts = append(parts, "error="+sanitize(lastError))
	}
	if extra != "" {
		parts = append(parts, extra)
	}
	statsText = strings.Join(parts, "; ")

	// Write to stats file so parent can read
	if configPath != "" {
		statsFile := configPath + ".stats"
		os.WriteFile(statsFile, []byte(statsText), 0644)
	}
}

func boolText(value bool) string {
	if value {
		return "true"
	}
	return "false"
}

func sanitize(value string) string {
	return strings.NewReplacer("\n", " ", "\r", " ", ";", ",").Replace(value)
}

func isGeodataRule(rule string) bool {
	upper := strings.ToUpper(strings.TrimSpace(rule))
	return strings.HasPrefix(upper, "GEOIP,") ||
		strings.HasPrefix(upper, "SRC-GEOIP,") ||
		strings.HasPrefix(upper, "GEOSITE,") ||
		strings.HasPrefix(upper, "RULE-SET,")
}

func filterGeodataRules(root map[string]any) int {
	rules, ok := root["rules"].([]any)
	if !ok || len(rules) == 0 {
		return 0
	}

	// Track whether we need to inject a cn-domain fallback rule.
	// GEOIP,CN requires MMDB which may not be available at startup,
	// so we convert it to a DOMAIN-SUFFIX rule that does not need MMDB.
	var cnFallback string // e.g. "DOMAIN-SUFFIX,cn,DIRECT"
	hasCnDomain := false

	filtered := make([]any, 0, len(rules))
	removed := 0
	for _, item := range rules {
		rule, ok := item.(string)
		if !ok {
			filtered = append(filtered, item)
			continue
		}

		upper := strings.ToUpper(strings.TrimSpace(rule))

		// Check whether a DOMAIN-SUFFIX,cn rule already exists
		if strings.HasPrefix(upper, "DOMAIN-SUFFIX,CN,") {
			hasCnDomain = true
		}

		// Convert GEOIP,CN → DOMAIN-SUFFIX,cn (no MMDB required)
		if strings.HasPrefix(upper, "GEOIP,CN,") {
			parts := strings.SplitN(rule, ",", 3)
			if len(parts) >= 3 {
				target := strings.TrimSpace(parts[2])
				cnFallback = fmt.Sprintf("DOMAIN-SUFFIX,cn,%s", target)
			}
			removed++
			continue
		}

		if isGeodataRule(rule) {
			removed++
			continue
		}

		filtered = append(filtered, item)
	}

	// Inject cn-suffix rule right before MATCH (or append if no MATCH found),
	// but only when we converted a GEOIP,CN rule and no DOMAIN-SUFFIX,cn exists yet.
	if cnFallback != "" && !hasCnDomain {
		inserted := false
		result := make([]any, 0, len(filtered)+1)
		for _, item := range filtered {
			rule, isStr := item.(string)
			if !inserted && isStr && strings.HasPrefix(strings.ToUpper(strings.TrimSpace(rule)), "MATCH,") {
				result = append(result, cnFallback)
				inserted = true
			}
			result = append(result, item)
		}
		if !inserted {
			result = append(result, cnFallback)
		}
		filtered = result
		fmt.Fprintf(os.Stderr, "[config] injected %s as GEOIP,CN fallback (no MMDB available)\n", cnFallback)
	}

	root["rules"] = filtered
	return removed
}

// injectHarmonyOSDirectRules adds DIRECT rules for HarmonyOS/Huawei system
// domains that are hosted on .com / .net TLDs and would otherwise fall through
// to MATCH (proxy).  Without GEOIP MMDB we cannot rely on GeoIP-based routing.
func injectHarmonyOSDirectRules(root map[string]any) int {
	rules, ok := root["rules"].([]any)
	if !ok || len(rules) == 0 {
		return 0
	}

	// HarmonyOS system domains that MUST go DIRECT.
	// These are Huawei/HarmonyOS cloud services on .com TLDs which are not
	// covered by generic DOMAIN-SUFFIX,cn or country-specific subscription rules.
	harmonyDirect := []string{
		// Huawei cloud / application services
		"DOMAIN-SUFFIX,dbankcloud.com,DIRECT",
		"DOMAIN-SUFFIX,dbankcloud.cn,DIRECT",
		"DOMAIN-SUFFIX,droiyou.com,DIRECT",
		"DOMAIN-SUFFIX,droiyou.cn,DIRECT",
		"DOMAIN-SUFFIX,vmall.com,DIRECT",
		"DOMAIN-SUFFIX,honor.com,DIRECT",
		"DOMAIN-SUFFIX,hicloud.com,DIRECT",
		"DOMAIN-SUFFIX,hicloud.cn,DIRECT",
		// Common Chinese IP-check / location services
		"DOMAIN-SUFFIX,ip138.com,DIRECT",
		"DOMAIN-SUFFIX,ipchaxun.net,DIRECT",
		"DOMAIN-SUFFIX,ip.cn,DIRECT",
		"DOMAIN-SUFFIX,ipip.net,DIRECT",
	}

	// Build a set of existing domains so we don't add duplicates.
	existing := make(map[string]bool)
	for _, item := range rules {
		if r, ok := item.(string); ok {
			existing[strings.ToUpper(strings.TrimSpace(r))] = true
		}
	}

	injected := 0
	result := make([]any, 0, len(rules)+len(harmonyDirect))
	for _, item := range rules {
		rule, isStr := item.(string)
		// Insert HarmonyOS rules right before MATCH (last rule).
		if isStr && strings.HasPrefix(strings.ToUpper(strings.TrimSpace(rule)), "MATCH,") {
			for _, hr := range harmonyDirect {
				if !existing[strings.ToUpper(hr)] {
					result = append(result, hr)
					fmt.Fprintf(os.Stderr, "[config] injected %s for HarmonyOS system traffic\n", hr)
					injected++
				}
			}
		}
		result = append(result, item)
	}

	if injected > 0 {
		fmt.Fprintf(os.Stderr, "[config] injected %d HarmonyOS system direct rules\n", injected)
	}
	root["rules"] = result
	return injected
}

func initResolverGuard() {
	net.DefaultResolver.PreferGo = true
	net.DefaultResolver.Dial = func(ctx context.Context, network string, address string) (net.Conn, error) {
		return nil, fmt.Errorf("unexpected net.DefaultResolver Dial: %s %s", network, address)
	}
}

func readRuntimeConfig(path string, fd int) ([]byte, string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, "", fmt.Errorf("read config failed: %w", err)
	}

	var root map[string]any
	if err := yaml.Unmarshal(content, &root); err != nil {
		return nil, "", fmt.Errorf("parse yaml failed: %w", err)
	}
	if root == nil {
		root = make(map[string]any)
	}

	tun, ok := root["tun"].(map[string]any)
	if !ok || tun == nil {
		tun = make(map[string]any)
		root["tun"] = tun
	}
	tun["enable"] = true
	// Do NOT override the stack - let the yaml config decide (system stack is required for HarmonyOS
	// because gVisor calls unix.Fstat on the VPN fd which is blocked by the HarmonyOS SELinux sandbox).
	// The profile should use stack: system or stack: mixed.
	tun["auto-route"] = false
	tun["auto-detect-interface"] = false
	tun["mtu"] = 1400
	tun["file-descriptor"] = fd
	if _, exists := tun["dns-hijack"]; !exists {
		tun["dns-hijack"] = []string{"0.0.0.0:53"}
	}

	dns, ok := root["dns"].(map[string]any)
	if !ok || dns == nil {
		dns = make(map[string]any)
		root["dns"] = dns
	}
	dns["enable"] = true
	dns["enhanced-mode"] = "fake-ip"
	dns["fake-ip-range"] = "198.18.0.1/16"
	fallbackFilter, ok := dns["fallback-filter"].(map[string]any)
	if !ok || fallbackFilter == nil {
		fallbackFilter = make(map[string]any)
		dns["fallback-filter"] = fallbackFilter
	}
	// Mihomo defaults dns.fallback-filter.geoip to true. On HarmonyOS the VPN
	// TUN is already active while hub.Parse runs, so an automatic MMDB download
	// can route into the not-yet-started TUN and deadlock startup.
	fallbackFilter["geoip"] = false
	removedGeodataRules := filterGeodataRules(root)
	injectHarmonyOSDirectRules(root)

	// Build fake-ip-filter to prevent proxy server domains from getting fake-ip addresses
	filterList := []string{
		"*.apple.com", "*.icloud.com", "*.cdn-apple.com",
		"dns.msftncsi.com", "www.msftncsi.com", "www.msftconnecttest.com",
		"+.ntp.org.cn", "localhost",
	}
	// Extract proxy server domains (non-IP) and add to filter
	var proxyDomains []string
	if proxies, ok := root["proxies"].([]any); ok {
		for _, p := range proxies {
			if proxy, ok := p.(map[string]any); ok {
				if server, ok := proxy["server"].(string); ok && server != "" {
					if net.ParseIP(server) == nil {
						proxyDomains = append(proxyDomains, server)
						filterList = append(filterList, server)
					}
				}
			}
		}
	}
	if _, exists := dns["fake-ip-filter"]; !exists {
		dns["fake-ip-filter"] = filterList
	}

	// Pre-resolve proxy server domains before TUN takes over.
	// This prevents a DNS deadlock where mihomo's DNS queries to upstream
	// nameservers are routed through the TUN and intercepted by its own dns-hijack.
	//
	// Resolution strategy (ordered by compatibility):
	//  1. System DNS via C library (cgo) — works in HarmonyOS sandbox before VPN
	//  2. Direct upstream UDP DNS (223.5.5.5, 119.29.29.29, 8.8.8.8) — fallback
	resolvedHosts := make(map[string]string)
	if len(proxyDomains) > 0 {
		// Phase 1: System DNS (works on HarmonyOS via platform sandbox resolver)
		sysCtx, sysCancel := context.WithTimeout(context.Background(), 6*time.Second)
		for _, domain := range proxyDomains {
			if _, exists := resolvedHosts[domain]; exists {
				continue
			}
			ips, err := net.DefaultResolver.LookupIPAddr(sysCtx, domain)
			if err == nil && len(ips) > 0 {
				ip := ips[0].IP.String()
				resolvedHosts[domain] = ip
				fmt.Fprintf(os.Stderr, "[pre-resolve] %s -> %s (system dns)\n", domain, ip)
			}
		}
		sysCancel()

		// Phase 2: Direct upstream DNS for any domains not yet resolved
		unresolved := make([]string, 0)
		for _, domain := range proxyDomains {
			if _, exists := resolvedHosts[domain]; !exists {
				unresolved = append(unresolved, domain)
			}
		}
		if len(unresolved) > 0 {
			resolver := &net.Resolver{
				PreferGo: true,
				Dial: func(ctx context.Context, network string, address string) (net.Conn, error) {
					d := net.Dialer{Timeout: 3 * time.Second}
					if strings.HasSuffix(address, ":53") || strings.Contains(address, "53") {
						for _, ns := range []string{"223.5.5.5:53", "119.29.29.29:53", "8.8.8.8:53"} {
							conn, err := d.DialContext(ctx, "udp", ns)
							if err == nil {
								return conn, nil
							}
						}
					}
					return d.DialContext(ctx, network, address)
				},
			}
			directCtx, directCancel := context.WithTimeout(context.Background(), 5*time.Second)
			for _, domain := range unresolved {
				ips, err := resolver.LookupIPAddr(directCtx, domain)
				if err != nil || len(ips) == 0 {
					fmt.Fprintf(os.Stderr, "[pre-resolve] WARN: failed to resolve %s: %v (will resolve via mihomo DNS after TUN starts)\n", domain, err)
					continue
				}
				ip := ips[0].IP.String()
				resolvedHosts[domain] = ip
				fmt.Fprintf(os.Stderr, "[pre-resolve] %s -> %s (direct dns)\n", domain, ip)
			}
			directCancel()
		}
	}

	// Replace proxy server domain with resolved IP in proxy configs
	if len(resolvedHosts) > 0 {
		if proxies, ok := root["proxies"].([]any); ok {
			for _, p := range proxies {
				if proxy, ok := p.(map[string]any); ok {
					if server, ok := proxy["server"].(string); ok {
						if ip, found := resolvedHosts[server]; found {
							proxy["server"] = ip
						}
					}
				}
			}
		}
		// Add resolved IPs to hosts section to prevent any further DNS lookups
		hosts, ok := root["hosts"].(map[string]any)
		if !ok || hosts == nil {
			hosts = make(map[string]any)
			root["hosts"] = hosts
		}
		for domain, ip := range resolvedHosts {
			hosts[domain] = ip
		}
	}

	// Extract proxy server address for connectivity test
	var proxyAddr string
	if proxies, ok := root["proxies"].([]any); ok && len(proxies) > 0 {
		if proxy, ok := proxies[0].(map[string]any); ok {
			if server, ok := proxy["server"].(string); ok {
				if port, ok := proxy["port"]; ok {
					proxyAddr = fmt.Sprintf("%s:%v", server, port)
				}
			}
		}
	}

	output, err := yaml.Marshal(root)
	if err != nil {
		return nil, "", fmt.Errorf("write runtime yaml failed: %w", err)
	}
	_ = os.WriteFile(path+".resolved", output, 0644)
	if removedGeodataRules > 0 {
		fmt.Fprintf(os.Stderr, "[config] filtered %d geodata rules for HarmonyOS startup safety\n", removedGeodataRules)
	}
	return output, proxyAddr, nil
}

func startMihomoLocked() int {
	if running {
		setStatsLocked("message=already running")
		return 1
	}
	if configPath == "" {
		lastError = "config path is empty"
		setStatsLocked("startError=-1")
		return -1
	}
	if tunFd < 0 {
		lastError = "tun fd is invalid"
		setStatsLocked("startError=-2")
		return -2
	}

	initResolverGuard()

	homeDir := filepath.Dir(configPath)
	CN.SetHomeDir(homeDir)
	CN.SetConfig(configPath)

	// Setup explicitly to write logs
	logFile, err := os.OpenFile(configPath+".log", os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err == nil {
		if err := syscall.Dup3(int(logFile.Fd()), 1, 0); err != nil {
			fmt.Fprintf(logFile, "Dup3 stdout failed: %v\n", err)
		}
		if err := syscall.Dup3(int(logFile.Fd()), 2, 0); err != nil {
			fmt.Fprintf(logFile, "Dup3 stderr failed: %v\n", err)
		}
		os.Stdout = logFile
		os.Stderr = logFile
		logrus.SetOutput(logFile)
		log.SetLevel(log.DEBUG)
		fmt.Fprintln(logFile, ">>> Mihomo adapter starting... <<<")
		logFile.Sync()
	} else {
		setStatsLocked("message=Failed to open log: " + sanitize(err.Error()))
	}

	if err := config.Init(homeDir); err != nil {
		lastError = err.Error()
		setStatsLocked("startError=-3")
		return -3
	}

	configBytes, proxyAddr, err := readRuntimeConfig(configPath, tunFd)
	if err != nil {
		lastError = err.Error()
		setStatsLocked("startError=-4")
		return -4
	}
	setStatsLocked(fmt.Sprintf("message=runtime config resolved; proxyAddr=%s; runtimeConfigBytes=%d", proxyAddr, len(configBytes)))

	if err := hub.Parse(configBytes); err != nil {
		lastError = err.Error()
		setStatsLocked("startError=-5")
		return -5
	}

	// Test outbound connectivity AFTER mihomo starts (TUN is active).
	// This verifies protectProcessNet() is working for outbound sockets.
	go func() {
		time.Sleep(2 * time.Second) // Wait for TUN to be fully active
		testDialer := net.Dialer{Timeout: 5 * time.Second}

		if proxyAddr != "" {
			conn, err := testDialer.Dial("tcp", proxyAddr)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: tcp connect to proxy %s: %v\n", proxyAddr, err)
			} else {
				fmt.Fprintf(os.Stderr, "[connectivity-test] OK: tcp connect to proxy %s\n", proxyAddr)
				conn.Close()
			}
		}

		// Test 2: connect to public DNS
		conn2, err := testDialer.Dial("tcp", "8.8.8.8:53")
		if err != nil {
			fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: tcp connect to 8.8.8.8:53: %v\n", err)
		} else {
			fmt.Fprintf(os.Stderr, "[connectivity-test] OK: tcp connect to 8.8.8.8:53\n")
			conn2.Close()
		}
	}()

	running = true
	lastError = ""
	startedAt = time.Now().Format("15:04:05")
	setStatsLocked("message=mihomo started")
	return 0
}

//export StartMihomoAdapter
func StartMihomoAdapter(cfgPath *C.char, fd C.int) C.int {
	stateMu.Lock()
	configPath = C.GoString(cfgPath)
	tunFd = int(fd)

	if configPath != "" {
		setStatsLocked("message=starting")
	}

	res := startMihomoLocked()
	stateMu.Unlock()

	return C.int(res)
}

//export StopMihomoAdapter
func StopMihomoAdapter() {
	stateMu.Lock()
	if running {
		executor.Shutdown()
	}
	running = false
	setStatsLocked("message=mihomo stopped")
	stateMu.Unlock()
}

func main() {
	// Empty main required for buildmode=c-shared
}
