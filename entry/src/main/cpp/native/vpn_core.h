#ifndef HARMONY_VPN_MIHOMO_POC_VPN_CORE_H
#define HARMONY_VPN_MIHOMO_POC_VPN_CORE_H

namespace harmony_vpn_poc {

int StartCore();
int StopCore();
int SetTunFd(int fd);
int SetConfig(const char* config);
const char* GetStats();

} // namespace harmony_vpn_poc

#endif // HARMONY_VPN_MIHOMO_POC_VPN_CORE_H
