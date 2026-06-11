# Fix: Mobile Data Routing Loop (bind-interface=vpn-tun)

## Context

On HarmonyOS mobile data, the mihomo VPN adapter enters a routing loop because `detectActiveInterface()` incorrectly detects `vpn-tun` (the VPN TUN interface) instead of the physical interface `rmnet0`. This causes `bind-interface=vpn-tun` in the mihomo config, making all proxy traffic loop back into the TUN. Result: 0 successful proxy connections, 1791 dial errors.

WiFi works correctly because `protectProcessNet()` reliably exempts the process from VPN routing on WiFi but not on mobile data.

## Approach: Three-Layer Fallback Detection

Modify only `tools/mihomo-adapter-go/main.go` to add a robust interface detection chain:

```
Layer 1: UDP Dial (existing) → validate result is physical interface
Layer 2: Parse /proc/net/route → find default route, exclude TUN/ANC
Layer 3: Enumerate physical interfaces → rmnet0 > wlan0 > wlan1 > eth0
```

## Changes to `tools/mihomo-adapter-go/main.go`

### 1. Add imports: `bufio`, `strconv`

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
- Graceful failure if file unreadable (common on HarmonyOS)

### 6. New function: `detectPhysicalInterfaceByProbe() string`
Enumerate `net.Interfaces()`:
- Filter: must be UP + RUNNING + have IPv4 address + pass `isPhysicalInterfaceCandidate()`
- Priority: `rmnet0` > `wlan0` > `wlan1` > `eth0` > any other candidate

### 7. New function: `detectActiveInterfaceWithFallback() string`
Orchestrate the three layers with logging at each stage.

### 8. Modify `readRuntimeConfig()` (line 306)
Change `detectActiveInterface()` call to `detectActiveInterfaceWithFallback()`.

## Build & Deploy

```bash
bash tools/build-so.sh
# Then rebuild HAP via DevEco Studio and deploy to device
```

## Verification

1. Deploy to device on mobile data
2. Start VPN, check log:
   ```
   hdc shell cat /data/app/el2/100/base/com.ccsh.app/haps/entry/files/mihomo_runtime.yaml.log | grep iface
   ```
   Expected: `bind-interface=rmnet0` (not `vpn-tun`)
3. Check resolved config: `bind-interface: rmnet0`
4. Check health checks: should show `alive: true` with reasonable delay values
5. Check no `context deadline exceeded` errors in dial logs
6. Test WiFi to confirm no regression: `bind-interface=wlan0`
