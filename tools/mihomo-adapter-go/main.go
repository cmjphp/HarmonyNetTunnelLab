package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
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

// unresolvedProxyDomains stores proxy server domains that failed pre-resolve
// before mihomo started. They will be resolved post-start when protectProcessNet
// is effective, then injected via mihomo's REST API.
var unresolvedProxyDomains []string

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

// rawDNSResolve sends a DNS A-record query via raw UDP socket and parses the response.
// This bypasses Go's net.Resolver which has issues on HarmonyOS with VPN TUN active.
// Uses the same net.Dial mechanism as the connectivity test (protected by protectProcessNet).
func rawDNSResolve(dialer *net.Dialer, domain string) string {
	dnsServers := []string{"223.5.5.5:53", "119.29.29.29:53", "8.8.8.8:53"}
	for _, server := range dnsServers {
		ip := rawDNSQuery(dialer, server, domain)
		if ip != "" {
			return ip
		}
	}
	return ""
}

// rawDNSQuery sends a single DNS A-record query to the specified server and returns
// the first IPv4 address from the answer section, or "" on failure.
func rawDNSQuery(dialer *net.Dialer, server string, domain string) string {
	conn, err := dialer.Dial("udp", server)
	if err != nil {
		return ""
	}
	defer conn.Close()

	// Build DNS query packet
	query := buildDNSQuery(domain)
	conn.SetWriteDeadline(time.Now().Add(3 * time.Second))
	if _, err := conn.Write(query); err != nil {
		return ""
	}

	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	buf := make([]byte, 512)
	n, err := conn.Read(buf)
	if err != nil || n < 12 {
		return ""
	}
	return parseDNSResponse(buf[:n], domain)
}

// buildDNSQuery constructs a minimal DNS A-record query for the given domain.
func buildDNSQuery(domain string) []byte {
	var buf []byte
	// Transaction ID (random-ish)
	buf = append(buf, 0xAB, 0xCD)
	// Flags: standard query, recursion desired
	buf = append(buf, 0x01, 0x00)
	// Questions: 1
	buf = append(buf, 0x00, 0x01)
	// Answer/Authority/Additional: 0
	buf = append(buf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
	// QNAME: encode domain as DNS labels
	for _, label := range strings.Split(domain, ".") {
		buf = append(buf, byte(len(label)))
		buf = append(buf, []byte(label)...)
	}
	buf = append(buf, 0x00) // root label
	// QTYPE: A (1)
	buf = append(buf, 0x00, 0x01)
	// QCLASS: IN (1)
	buf = append(buf, 0x00, 0x01)
	return buf
}

// parseDNSResponse extracts the first A-record IP from a DNS response.
func parseDNSResponse(data []byte, domain string) string {
	if len(data) < 12 {
		return ""
	}
	// Check response code (bits 0-3 of byte 3)
	if data[3]&0x0F != 0 {
		return ""
	}
	anCount := int(data[6])<<8 | int(data[7])
	if anCount == 0 {
		return ""
	}
	// Skip question section
	pos := 12
	qdCount := int(data[4])<<8 | int(data[5])
	for i := 0; i < qdCount; i++ {
		// Skip QNAME
		for pos < len(data) {
			labelLen := int(data[pos])
			if labelLen == 0 {
				pos++
				break
			}
			if labelLen&0xC0 == 0xC0 {
				pos += 2 // compressed pointer
				break
			}
			pos += 1 + labelLen
		}
		pos += 4 // QTYPE + QCLASS
	}
	// Parse answer section
	for i := 0; i < anCount && pos < len(data); i++ {
		// Skip NAME (may be compressed)
		if pos >= len(data) {
			break
		}
		if data[pos]&0xC0 == 0xC0 {
			pos += 2
		} else {
			for pos < len(data) {
				if data[pos] == 0 {
					pos++
					break
				}
				pos += 1 + int(data[pos])
			}
		}
		if pos+10 > len(data) {
			break
		}
		rType := int(data[pos])<<8 | int(data[pos+1])
		rdLen := int(data[pos+8])<<8 | int(data[pos+9])
		pos += 10
		if rType == 1 && rdLen == 4 && pos+4 <= len(data) {
			// A record: 4 bytes IPv4
			return fmt.Sprintf("%d.%d.%d.%d", data[pos], data[pos+1], data[pos+2], data[pos+3])
		}
		pos += rdLen
	}
	return ""
}

// isNonPhysicalInterface returns true if the interface name belongs to a VPN TUN,
// ANC virtual interface, or internal modem sub-interface that must never be used
// as mihomo's interface-name (which uses SO_BINDTODEVICE on Linux/GOOS).
func isNonPhysicalInterface(name string) bool {
	// VPN / tunnel interfaces
	for _, prefix := range []string{"vpn", "tun", "tap"} {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	// HarmonyOS ANC virtual interfaces (ancormnet0, anco-wlan1, etc.)
	if strings.HasPrefix(name, "anco") || strings.HasPrefix(name, "anc") {
		return true
	}
	// Internal modem sub-interfaces: rmnet_ims00, rmnet_tun00, rmnet_emc0,
	// rmnet_mbs, rmnet_d2d, rmnet_r_ims00, etc.
	// NOTE: the underscore is critical — "rmnet0" (no underscore) is the
	// physical mobile-data interface and must NOT be rejected.
	if strings.HasPrefix(name, "rmnet_") {
		return true
	}
	// Loopback, P2P, dummy, IP tunnels
	for _, prefix := range []string{"lo", "p2p", "dummy", "sit", "gre", "ip6tnl", "Hisilicon"} {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	// Internal bridge / container interfaces (ifb0, ifb1, hw_sate_vnet, ip_vti0, CPU0)
	for _, prefix := range []string{"ifb", "hw_sate", "ip_vti", "ip6_vti", "CPU"} {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	return false
}

// isPhysicalInterfaceCandidate returns true if the interface name looks like a
// physical network interface we want to bind mihomo's outbound sockets to.
func isPhysicalInterfaceCandidate(name string) bool {
	if isNonPhysicalInterface(name) {
		return false
	}
	// Accept rmnetN, wlanN, ethN patterns (N is at least one digit).
	for _, prefix := range []string{"rmnet", "wlan", "eth"} {
		if strings.HasPrefix(name, prefix) && len(name) > len(prefix) {
			c := name[len(prefix)]
			if c >= '0' && c <= '9' {
				return true
			}
		}
	}
	// Accept any remaining interface that is not classified as non-physical
	// and has a non-empty name.
	if name != "" && !isNonPhysicalInterface(name) {
		return true
	}
	return false
}

// interfacePriority returns a sort-priority for physical interface candidates.
// Lower is better.  Returns 99 for unknown interfaces.
func interfacePriority(name string) int {
	switch {
	case strings.HasPrefix(name, "rmnet"):
		return 1
	case name == "wlan0":
		return 2
	case strings.HasPrefix(name, "wlan"):
		return 3
	case strings.HasPrefix(name, "eth"):
		return 4
	default:
		return 99
	}
}

// hasIPv4Addr reports whether the interface has at least one non-loopback IPv4 address.
func hasIPv4Addr(iface net.Interface) bool {
	addrs, err := iface.Addrs()
	if err != nil {
		return false
	}
	for _, addr := range addrs {
		var ip net.IP
		switch v := addr.(type) {
		case *net.IPNet:
			ip = v.IP
		case *net.IPAddr:
			ip = v.IP
		}
		if ip == nil {
			continue
		}
		if ip.IsLoopback() {
			continue
		}
		if ip.To4() != nil {
			return true
		}
	}
	return false
}

// detectInterfaceFromProcRoute parses /proc/net/route to find the physical
// interface that carries the default route (Destination=00000000, Mask=00000000).
// It excludes non-physical interfaces and picks the entry with the lowest metric.
// Returns "" on any failure (the file is often unavailable in HarmonyOS sandboxes).
func detectInterfaceFromProcRoute() string {
	f, err := os.Open("/proc/net/route")
	if err != nil {
		fmt.Fprintf(os.Stderr, "[iface-route] cannot open /proc/net/route: %v\n", err)
		return ""
	}
	defer f.Close()

	type routeEntry struct {
		iface  string
		metric int
	}
	var candidates []routeEntry

	scanner := bufio.NewScanner(f)
	header := true
	for scanner.Scan() {
		if header {
			header = false
			continue
		}
		fields := strings.Fields(scanner.Text())
		if len(fields) < 8 {
			continue
		}
		ifaceName := fields[0]
		destHex := fields[1]
		maskHex := fields[7]
		metricHex := fields[6]

		// Default route: Destination=00000000, Mask=00000000
		if destHex != "00000000" || maskHex != "00000000" {
			continue
		}
		if isNonPhysicalInterface(ifaceName) {
			fmt.Fprintf(os.Stderr, "[iface-route] skip non-physical default route: %s\n", ifaceName)
			continue
		}
		metric, _ := strconv.ParseUint(metricHex, 16, 32)
		candidates = append(candidates, routeEntry{iface: ifaceName, metric: int(metric)})
	}

	if len(candidates) == 0 {
		fmt.Fprintf(os.Stderr, "[iface-route] no physical default route found in /proc/net/route\n")
		return ""
	}

	// Pick lowest metric.
	best := candidates[0]
	for _, c := range candidates[1:] {
		if c.metric < best.metric {
			best = c
		}
	}
	fmt.Fprintf(os.Stderr, "[iface-route] default route via %s (metric=%d)\n", best.iface, best.metric)
	return best.iface
}

// detectPhysicalInterfaceByProbe enumerates all network interfaces and picks the
// best physical candidate by priority (rmnet0 > wlan0 > wlan1 > eth0 > ...).
// Used as the last-resort fallback when UDP dial and /proc/net/route both fail.
func detectPhysicalInterfaceByProbe() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[iface-probe] failed to list interfaces: %v\n", err)
		return ""
	}

	type candidate struct {
		name     string
		priority int
	}
	var wlanCandidates []candidate
	var otherCandidates []candidate

	for _, iface := range ifaces {
		if !isPhysicalInterfaceCandidate(iface.Name) {
			continue
		}
		if iface.Flags&net.FlagUp == 0 {
			fmt.Fprintf(os.Stderr, "[iface-probe] skip %s: not up (flags=%v)\n", iface.Name, iface.Flags)
			continue
		}
		// On HarmonyOS, wlan0 is "up|broadcast|multicast" (no running flag)
		// when WiFi is active. rmnet0 is always "up|running" even on WiFi.
		// So for wlan interfaces, only require FlagUp + IPv4 address as a
		// connectivity signal. For other interfaces (rmnet, eth), still
		// require FlagRunning to filter out dormant ones.
		isWlan := strings.HasPrefix(iface.Name, "wlan")
		if !isWlan && iface.Flags&net.FlagRunning == 0 {
			fmt.Fprintf(os.Stderr, "[iface-probe] skip %s: not running (flags=%v)\n", iface.Name, iface.Flags)
			continue
		}
		if !hasIPv4Addr(iface) {
			fmt.Fprintf(os.Stderr, "[iface-probe] skip %s: no IPv4 addr\n", iface.Name)
			continue
		}
		p := interfacePriority(iface.Name)
		fmt.Fprintf(os.Stderr, "[iface-probe] candidate %s priority=%d flags=%v\n", iface.Name, p, iface.Flags)
		c := candidate{name: iface.Name, priority: p}
		if isWlan {
			wlanCandidates = append(wlanCandidates, c)
		} else {
			otherCandidates = append(otherCandidates, c)
		}
	}

	// When WiFi is active, wlan has an IPv4 address and should be preferred:
	// binding to rmnet while WiFi carries traffic → "network is unreachable".
	if len(wlanCandidates) > 0 {
		best := wlanCandidates[0]
		for _, c := range wlanCandidates[1:] {
			if c.priority < best.priority {
				best = c
			}
		}
		fmt.Fprintf(os.Stderr, "[iface-probe] selected %s (wlan preferred, priority=%d)\n", best.name, best.priority)
		return best.name
	}

	if len(otherCandidates) == 0 {
		fmt.Fprintf(os.Stderr, "[iface-probe] no suitable physical interface found\n")
		return ""
	}

	best := otherCandidates[0]
	for _, c := range otherCandidates[1:] {
		if c.priority < best.priority {
			best = c
		}
	}
	fmt.Fprintf(os.Stderr, "[iface-probe] selected %s (priority=%d)\n", best.name, best.priority)
	return best.name
}

// detectActiveInterface finds the physical network interface name (e.g. "rmnet0", "wlan0")
// by dialing a public IP and checking which local interface handles the route.
// The TUN may already be active when this is called; if the result is a non-physical
// interface (e.g. vpn-tun), it is rejected and "" is returned.
func detectActiveInterface() string {
	// Dial a public IP to discover which interface the kernel uses for outbound traffic.
	conn, err := net.DialTimeout("udp", "8.8.8.8:53", 3*time.Second)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[iface-detect] failed to dial 8.8.8.8:53: %v\n", err)
		return ""
	}
	defer conn.Close()

	localAddr := conn.LocalAddr().(*net.UDPAddr)
	localIP := localAddr.IP

	// Find the interface that owns this local IP.
	ifaces, err := net.Interfaces()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[iface-detect] failed to list interfaces: %v\n", err)
		return ""
	}

	for _, iface := range ifaces {
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip != nil && ip.Equal(localIP) {
				// Validate: reject VPN / ANC / non-physical interfaces.
				if isNonPhysicalInterface(iface.Name) {
					fmt.Fprintf(os.Stderr, "[iface-detect] REJECT: %s is not a physical interface (matched IP %s)\n", iface.Name, localIP.String())
					return ""
				}
				fmt.Fprintf(os.Stderr, "[iface-detect] detected %s via %s\n", iface.Name, localIP.String())
				return iface.Name
			}
		}
	}

	fmt.Fprintf(os.Stderr, "[iface-detect] no interface found for %s\n", localIP.String())
	return ""
}

// detectActiveInterfaceWithFallback runs a three-layer detection chain to find
// the physical network interface for mihomo's interface-name setting:
//
//	Layer 1: UDP dial + IP-to-interface match (existing method, with validation)
//	Layer 2: Parse /proc/net/route for the default route
//	Layer 3: Enumerate physical interfaces by name pattern and flags
//
// Returns "" if all layers fail (interface-name will not be set, which is safe).
func detectActiveInterfaceWithFallback() string {
	// Layer 1: UDP dial (works reliably on WiFi when protectProcessNet is effective).
	if name := detectActiveInterface(); name != "" {
		fmt.Fprintf(os.Stderr, "[iface-result] Layer 1 (udp dial): %s\n", name)
		return name
	}
	fmt.Fprintf(os.Stderr, "[iface-result] Layer 1 failed, trying Layer 2\n")

	// Layer 2: /proc/net/route (works when the kernel routing table is visible).
	if name := detectInterfaceFromProcRoute(); name != "" {
		fmt.Fprintf(os.Stderr, "[iface-result] Layer 2 (proc route): %s\n", name)
		return name
	}
	fmt.Fprintf(os.Stderr, "[iface-result] Layer 2 failed, trying Layer 3\n")

	// Layer 3: Enumerate physical interfaces (always works as long as interfaces exist).
	if name := detectPhysicalInterfaceByProbe(); name != "" {
		fmt.Fprintf(os.Stderr, "[iface-result] Layer 3 (probe): %s\n", name)
		return name
	}

	fmt.Fprintf(os.Stderr, "[iface-result] WARN: all detection layers failed, interface-name will not be set\n")
	return ""
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

	// Detect the active physical network interface and bind outbound traffic to it.
	// protectProcessNet() only protects simple Go net.Dial sockets; mihomo's
	// internal dialer (with SO_REUSEADDR etc.) is NOT covered, causing DNS and
	// proxy connections to be captured by the VPN TUN default route.
	// SO_BINDTODEVICE forces all outbound sockets to the physical NIC (rmnet0/wlan0),
	// bypassing the VPN routing entirely.
	detectedIface := detectActiveInterfaceWithFallback()
	if detectedIface != "" {
		root["interface-name"] = detectedIface
		fmt.Fprintf(os.Stderr, "[iface-detect] interface-name=%s (protectProcessNet insufficient for mihomo internal sockets)\n", detectedIface)
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
	// Merge proxy server domains into the existing fake-ip-filter.
	// The subscription config may already have a fake-ip-filter list — we must
	// append any proxy domains that are not already covered by existing entries,
	// otherwise mihomo assigns fake IPs (198.18.0.x) to proxy servers and all
	// outbound connections fail.
	if existingFilter, exists := dns["fake-ip-filter"]; exists {
		if existingList, ok := existingFilter.([]any); ok {
			// Build a set of existing entries for dedup
			seen := make(map[string]bool, len(existingList))
			for _, item := range existingList {
				if s, ok := item.(string); ok {
					seen[s] = true
				}
			}
			// Append only new entries not already present
			for _, entry := range filterList {
				if !seen[entry] {
					existingList = append(existingList, entry)
					seen[entry] = true
				}
			}
			dns["fake-ip-filter"] = existingList
		}
	} else {
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

	// Save unresolved domains for post-start resolution.
	// On HarmonyOS, DNS fails before mihomo starts because the VPN TUN is active
	// but mihomo's TUN handler hasn't started reading yet, so DNS packets are stuck.
	// After mihomo starts, Go net.Dial works (protectProcessNet is effective).
	unresolvedProxyDomains = nil
	for _, domain := range proxyDomains {
		if _, resolved := resolvedHosts[domain]; !resolved {
			unresolvedProxyDomains = append(unresolvedProxyDomains, domain)
		}
	}
	if len(unresolvedProxyDomains) > 0 {
		fmt.Fprintf(os.Stderr, "[pre-resolve] %d domains unresolved, will resolve post-start: %v\n",
			len(unresolvedProxyDomains), unresolvedProxyDomains)
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
	// Also resolves proxy domains that failed pre-resolve (DNS works after mihomo starts).
	go func() {
		time.Sleep(2 * time.Second) // Wait for TUN to be fully active

		// Post-start DNS resolution: on HarmonyOS, raw net.Dial works after mihomo
		// starts (protectProcessNet is effective), but net.Resolver's DNS client
		// fails. Use raw UDP sockets to send DNS queries directly.
		if len(unresolvedProxyDomains) > 0 {
			resolved := make(map[string]string)
			dnsDialer := net.Dialer{Timeout: 5 * time.Second}
			for _, domain := range unresolvedProxyDomains {
				ip := rawDNSResolve(&dnsDialer, domain)
				if ip != "" {
					resolved[domain] = ip
					fmt.Fprintf(os.Stderr, "[post-resolve] %s -> %s\n", domain, ip)
				} else {
					fmt.Fprintf(os.Stderr, "[post-resolve] FAIL: %s\n", domain)
				}
			}

			if len(resolved) > 0 {
				hostsMap := make(map[string]string)
				for domain, ip := range resolved {
					hostsMap[domain] = ip
				}
				patchBody, _ := json.Marshal(map[string]any{"hosts": hostsMap})
				req, err := http.NewRequest("PATCH", "http://127.0.0.1:9090/configs", bytes.NewReader(patchBody))
				if err == nil {
					req.Header.Set("Content-Type", "application/json")
					client := &http.Client{Timeout: 3 * time.Second}
					resp, err := client.Do(req)
					if err == nil {
						resp.Body.Close()
						fmt.Fprintf(os.Stderr, "[post-resolve] patched mihomo hosts: %d entries (status %d)\n", len(resolved), resp.StatusCode)
					} else {
						fmt.Fprintf(os.Stderr, "[post-resolve] WARN: failed to patch mihomo: %v\n", err)
					}
				}
			}
			unresolvedProxyDomains = nil
		}

		testDialer := net.Dialer{Timeout: 5 * time.Second}

		if proxyAddr != "" {
			// Test 1: TCP to proxy
			conn, err := testDialer.Dial("tcp", proxyAddr)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: tcp connect to proxy %s: %v\n", proxyAddr, err)
			} else {
				fmt.Fprintf(os.Stderr, "[connectivity-test] OK: tcp connect to proxy %s\n", proxyAddr)
				conn.Close()
			}

			// Test 1b: UDP to proxy (hysteria2 uses QUIC/UDP)
			udpConn, err := testDialer.Dial("udp", proxyAddr)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: udp dial to proxy %s: %v\n", proxyAddr, err)
			} else {
				fmt.Fprintf(os.Stderr, "[connectivity-test] OK: udp dial to proxy %s\n", proxyAddr)
				udpConn.Close()
			}
		}

		// Test 2: TCP to public DNS
		conn2, err := testDialer.Dial("tcp", "8.8.8.8:53")
		if err != nil {
			fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: tcp connect to 8.8.8.8:53: %v\n", err)
		} else {
			fmt.Fprintf(os.Stderr, "[connectivity-test] OK: tcp connect to 8.8.8.8:53\n")
			conn2.Close()
		}

		// Test 2b: UDP to public DNS
		udpDns, err := testDialer.Dial("udp", "8.8.8.8:53")
		if err != nil {
			fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: udp dial to 8.8.8.8:53: %v\n", err)
		} else {
			fmt.Fprintf(os.Stderr, "[connectivity-test] OK: udp dial to 8.8.8.8:53\n")
			udpDns.Close()
		}

		// Test 3: UDP round-trip (send DNS query, expect response)
		udpSend, err := net.Dial("udp", "223.5.5.5:53")
		if err != nil {
			fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: udp dial to 223.5.5.5:53: %v\n", err)
		} else {
			dnsQuery := []byte{
				0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
				0x00, 0x00, 0x00, 0x00, 0x03, 0x77, 0x77, 0x77,
				0x05, 0x62, 0x61, 0x69, 0x64, 0x75, 0x03, 0x63,
				0x6f, 0x6d, 0x00, 0x00, 0x01, 0x00, 0x01,
			}
			udpSend.SetWriteDeadline(time.Now().Add(3 * time.Second))
			_, err := udpSend.Write(dnsQuery)
			if err != nil {
				fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: udp write to 223.5.5.5:53: %v\n", err)
			} else {
				udpSend.SetReadDeadline(time.Now().Add(3 * time.Second))
				buf := make([]byte, 512)
				n, err := udpSend.Read(buf)
				if err != nil {
					fmt.Fprintf(os.Stderr, "[connectivity-test] FAIL: udp read from 223.5.5.5:53: %v\n", err)
				} else {
					fmt.Fprintf(os.Stderr, "[connectivity-test] OK: udp round-trip to 223.5.5.5:53 (recv %d bytes)\n", n)
				}
			}
			udpSend.Close()
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
