#ifndef HARMONY_VPN_MIHOMO_POC_MIHOMO_ADAPTER_H
#define HARMONY_VPN_MIHOMO_POC_MIHOMO_ADAPTER_H

#include <string>

namespace harmony_vpn_poc {

class MihomoAdapter {
public:
    int Start(const std::string& configPath, int tunFd);
    int Stop();
    std::string Stats() const;
    bool IsRunning() const;

    void SetNativeLibraryDir(const std::string& path);

private:
    using StartMihomoAdapterFn = int (*)(char*, int);
    using StopMihomoAdapterFn = void (*)();

    bool LoadAdapter();

    std::string native_library_dir_;
    void* lib_handle_ = nullptr;
    StartMihomoAdapterFn start_fn_ = nullptr;
    StopMihomoAdapterFn stop_fn_ = nullptr;
    bool running_ = false;
    mutable std::string last_error_;
    std::string config_path_;
};

} // namespace harmony_vpn_poc

#endif // HARMONY_VPN_MIHOMO_POC_MIHOMO_ADAPTER_H
