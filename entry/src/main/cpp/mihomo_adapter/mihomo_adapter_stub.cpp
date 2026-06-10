#include "mihomo_adapter_api.h"

#include <mutex>
#include <string>

namespace {
std::mutex g_state_mutex;
std::string g_config_path;
int g_tun_fd = -1;
std::string g_stats_cache;
constexpr int kStubStartError = -100;
} // namespace

extern "C" int MihomoSetConfigPath(const char* path)
{
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_config_path = path == nullptr ? "" : path;
    return g_config_path.empty() ? -1 : 0;
}

extern "C" int MihomoSetTunFd(int fd)
{
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_tun_fd = fd;
    return g_tun_fd < 0 ? -1 : 0;
}

extern "C" int MihomoStart()
{
    // Stub only: proves adapter loading and ABI calls work. It must not claim real proxy support.
    return kStubStartError;
}

extern "C" int MihomoStop()
{
    return 0;
}

extern "C" const char* MihomoGetStats()
{
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_stats_cache = "adapterKind=stub; configPath=" + g_config_path +
        "; tunFd=" + std::to_string(g_tun_fd) +
        "; startError=-100; message=real mihomo core is not linked yet";
    return g_stats_cache.c_str();
}
