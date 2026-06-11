# Fix: Mobile Data Routing Loop & WiFi Interface Selection

## Context

On HarmonyOS mobile data, the mihomo VPN adapter enters a routing loop because `detectActiveInterface()` incorrectly detects `vpn-tun` (the VPN TUN interface) instead of the physical interface `rmnet0`. This causes all proxy traffic to loop back into the TUN. Result: 0 successful proxy connections, 1791 dial errors.

WiFi was initially assumed to work correctly via `protectProcessNet()`, but subsequent testing revealed two additional bugs that affected both mobile data and WiFi (see Bug #2 and Bug #3 below).

## Root Cause Analysis

Three bugs were identified during device testing:

**Bug #1 — vpn-tun misdetected as physical interface:** `detectActiveInterface()` uses UDP dial to discover the outbound interface. When the VPN TUN is active, the dial returns `vpn-tun` instead of the physical interface. On mobile data this caused a routing loop.

**Bug #2 — Wrong YAML key (`bind-interface` vs `interface-name`):** The Go adapter wrote `bind-interface: rmnet0` to the mihomo config, but mihomo only recognizes `interface-name`. The unknown key was silently ignored, so `SO_BINDTODEVICE` was never applied and all outbound traffic was captured by the VPN TUN regardless of interface detection. This was the actual root cause — even with correct detection, the binding had no effect.

**Bug #3 — WiFi interface not selected:** `detectPhysicalInterfaceByProbe()` required both `FlagUp` and `FlagRunning`. On HarmonyOS, `wlan0` shows `up|broadcast|multicast` (no `running` flag) when WiFi is active, while `rmnet0` is always `up|running` with an IPv4 address. This caused rmnet0 to be selected on WiFi, resulting in `network is unreachable` errors.

## Approach: Three-Layer Fallback Detection

Modify `tools/mihomo-adapter-go/main.go` to add a robust interface detection chain:

```
Layer 1: UDP Dial (existing) → validate result is physical interface
Layer 2: Parse /proc/net/route → find default route, exclude TUN/ANC
Layer 3: Enumerate physical interfaces → WiFi-aware priority selection
```

## Changes to `tools/mihomo-adapter-go/main.go`

### 1. Add imports: `bufio`, `strconv`, `net/http`, `encoding/json`

### 2. New function: `isNonPhysicalInterface(name string) bool`
Reject interface names matching VPN/ANC/internal patterns:
- Prefixes: `vpn`, `tun`, `tap`, `anco`, `anc`, `p2p`, `lo`, `dummy`, `sit`, `gre`, `ip6tnl`
- Prefix `rmnet_` (with underscore) — catches `rmnet_ims00`, `rmnet_tun00`, etc.
- Must NOT match `rmnet0` (no underscore)

### 3. New function: `isPhysicalInterfaceCandidate(name string) bool`
Positive check for `rmnet`+digit, `wlan`+digit, `eth`+digit patterns.

### 4. Modify `detectActiveInterface()` (line ~261)
After matching interface name to IP, check `isNonPhysicalInterface()`. If true, log rejection and return empty string instead of the VPN interface name.

### 5. New function: `detectInterfaceFromProcRoute() string`
Parse `/proc/net/route`:
- Find entries where Destination=00000000 AND Mask=00000000 (default route)
- Exclude non-physical interfaces
- Return the interface with lowest metric
- Graceful failure if file unreadable (common on HarmonyOS — `permission denied`)

### 6. New function: `detectPhysicalInterfaceByProbe() string`
Enumerate `net.Interfaces()` with WiFi-aware selection:
- For **wlan** interfaces: only require `FlagUp` + IPv4 address (HarmonyOS doesn't set `FlagRunning` on active WiFi)
- For **other** interfaces (rmnet, eth): require both `FlagUp` and `FlagRunning`
- When wlan candidates exist (WiFi connected with IP), prefer wlan over rmnet
- Otherwise fall back to rmnet/eth by priority: `rmnet0` > `wlan0` > `wlan1` > `eth0`

This fixes Bug #3: binding to rmnet while WiFi carries traffic causes `network is unreachable` because rmnet has no active data route.

### 7. New function: `detectActiveInterfaceWithFallback() string`
Orchestrate the three layers with stderr logging at each stage.

### 8. Modify `readRuntimeConfig()` (line ~306)
- Change `detectActiveInterface()` call to `detectActiveInterfaceWithFallback()`
- **Write `interface-name` (not `bind-interface`)** to the mihomo YAML config — this fixes Bug #2, ensuring mihomo applies `SO_BINDTODEVICE` to all outbound sockets

### 9. Post-start DNS resolution (new goroutine)
After mihomo starts, resolve proxy server domains that failed pre-resolve:
- Wait 2 seconds for `protectProcessNet` to become effective
- Use `rawDNSResolve()` (raw UDP DNS query) to bypass Go's `net.Resolver` issues with VPN TUN
- PATCH `http://127.0.0.1:9090/configs` via mihomo REST API to inject resolved hosts
- Add resolved domains to `fake-ip-filter` to prevent fake IP assignment

### 10. New functions: `rawDNSResolve()`, `rawDNSQuery()`, `buildDNSQuery()`, `parseDNSResponse()`
Raw UDP DNS implementation that constructs DNS packets manually, bypassing the system resolver which routes through the VPN TUN.

### 11. New function: `filterGeodataRules()`
Convert `GEOIP,CN` rules to `DOMAIN-SUFFIX,cn` to avoid MMDB download dependency on HarmonyOS (where the download would route through the not-yet-started TUN and deadlock).

### 12. New function: `injectHarmonyOSDirectRules()`
Inject DIRECT rules for HarmonyOS/Huawei system domains (dbankcloud, hicloud, vmall, etc.) to prevent system traffic from being proxied.

## Changes to `entry/src/main/ets/vpn/VpnAbility.ets`

### protectProcessNet retry schedule
Changed from single 2-second delay to multiple retries at `[1000, 3000, 6000, 10000]` ms after mihomo start. Mihomo creates sockets continuously for health checks, DNS resolution, and proxy connections — multiple retries ensure new sockets are covered.

## Changes to `entry/src/main/ets/core/MihomoProfileStore.ets`

Removed hardcoded `interface-name: wlan0` from both `mergeRawWithLocalSettings()` and `buildSelectedNodeConfig()`. Interface is now dynamically detected by the Go layer.

## Build & Deploy

```bash
# Build .so
bash tools/build-so.sh

# Build HAP (requires DevEco SDK)
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
OHOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  --mode module -p product=default -p module=entry@default \
  assembleHap --no-daemon --no-parallel

# Deploy to device
hdc -t <serial> shell "aa force-stop com.ccsh.app"
hdc -t <serial> app install -r entry/build/default/outputs/default/entry-default-signed.hap
```

## Verification Results (device 7DZ9K26527002261)

### Mobile Data
```
[iface-detect] REJECT: vpn-tun is not a physical interface
[iface-probe] candidate rmnet0 priority=1 flags=up|running
[iface-probe] skip wlan0: no IPv4 addr
[iface-probe] selected rmnet0 (priority=1)
[iface-detect] interface-name=rmnet0
```
- 0 `context deadline exceeded` errors
- All proxies `alive: true` (日本专线 ~402ms, 新加坡 ~394ms, 美国 ~809ms)
- DNS resolving correctly via `223.5.5.5` and `119.29.29.29`

### WiFi
```
[iface-probe] skip rmnet0: not up (flags=0)
[iface-probe] candidate wlan0 priority=2 flags=up|broadcast|multicast|running
[iface-probe] selected wlan0 (wlan preferred, priority=2)
[iface-detect] interface-name=wlan0
```
- 0 `network is unreachable` errors
- All proxies `alive: true`
- Traffic flowing through proxy normally

### Key Insight: HarmonyOS Interface Flags
| Interface | Mobile Data | WiFi |
|-----------|------------|------|
| rmnet0 | `up\|running` (active) | `flags=0` (down) |
| wlan0 | `up\|broadcast\|multicast` (no IP) | `up\|broadcast\|multicast\|running` |
| wlan1 | varies | varies |

The detection logic must account for HarmonyOS-specific flag behavior: wlan0 may lack `FlagRunning` when WiFi is active, and rmnet interfaces always show `up|running` when any mobile data is available.
