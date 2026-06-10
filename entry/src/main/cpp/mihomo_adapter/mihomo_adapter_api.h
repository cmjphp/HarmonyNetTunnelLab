#ifndef HARMONY_VPN_MIHOMO_POC_MIHOMO_ADAPTER_API_H
#define HARMONY_VPN_MIHOMO_POC_MIHOMO_ADAPTER_API_H

#ifdef __cplusplus
extern "C" {
#endif

int MihomoSetConfigPath(const char* path);
int MihomoSetTunFd(int fd);
int MihomoStart();
int MihomoStop();
const char* MihomoGetStats();

#ifdef __cplusplus
}
#endif

#endif // HARMONY_VPN_MIHOMO_POC_MIHOMO_ADAPTER_API_H
