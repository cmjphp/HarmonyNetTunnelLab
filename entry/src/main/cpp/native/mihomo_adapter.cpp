#include "mihomo_adapter.h"

#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <dlfcn.h>
#include <fstream>
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "MihomoAdapter"

namespace harmony_vpn_poc {
namespace {
using StartMihomoAdapterFn = int (*)(char*, int);
using StopMihomoAdapterFn = void (*)();
}

void MihomoAdapter::SetNativeLibraryDir(const std::string& path) {
    native_library_dir_ = path;
}

bool MihomoAdapter::LoadAdapter()
{
    if (lib_handle_ != nullptr && start_fn_ != nullptr && stop_fn_ != nullptr) {
        return true;
    }

    const std::string lib_name = "libmihomo_adapter.so";
    if (!native_library_dir_.empty()) {
        const std::string full_path = native_library_dir_ + "/" + lib_name;
        lib_handle_ = dlopen(full_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    }
    if (lib_handle_ == nullptr) {
        lib_handle_ = dlopen(lib_name.c_str(), RTLD_NOW | RTLD_LOCAL);
    }
    if (lib_handle_ == nullptr) {
        const char* error = dlerror();
        last_error_ = std::string("dlopen libmihomo_adapter.so failed: ") + (error == nullptr ? "unknown" : error);
        return false;
    }

    start_fn_ = reinterpret_cast<StartMihomoAdapterFn>(dlsym(lib_handle_, "StartMihomoAdapter"));
    stop_fn_ = reinterpret_cast<StopMihomoAdapterFn>(dlsym(lib_handle_, "StopMihomoAdapter"));
    if (start_fn_ == nullptr || stop_fn_ == nullptr) {
        const char* error = dlerror();
        last_error_ = std::string("dlsym libmihomo_adapter.so failed: ") + (error == nullptr ? "missing StartMihomoAdapter/StopMihomoAdapter" : error);
        dlclose(lib_handle_);
        lib_handle_ = nullptr;
        start_fn_ = nullptr;
        stop_fn_ = nullptr;
        return false;
    }

    last_error_.clear();
    return true;
}

int MihomoAdapter::Start(const std::string& configPath, int tunFd)
{
    if (running_) {
        return 1;
    }
    
    config_path_ = configPath;

    if (configPath.empty()) {
        last_error_ = "mihomo config path is empty";
        return -3;
    }
    if (tunFd < 0) {
        last_error_ = "tun fd is invalid";
        return -4;
    }

    if (!LoadAdapter()) {
        return -5;
    }

    char* cfg = strdup(configPath.c_str());
    int res = start_fn_(cfg, tunFd);
    free(cfg);

    if (res < 0) {
        last_error_ = "Go StartMihomoAdapter returned error: " + std::to_string(res);
        return res;
    }

    running_ = true;
    last_error_.clear();
    return 0;
}

int MihomoAdapter::Stop()
{
    if (!running_) {
        return 0;
    }
    
    if (stop_fn_ != nullptr) {
        stop_fn_();
    }
    
    running_ = false;
    return 0;
}

std::string MihomoAdapter::Stats() const
{
    std::string stats = "adapterKind=go-dlopen; adapterLoaded=" +
        std::string(lib_handle_ == nullptr ? "false" : "true") +
        "; running=" + std::string(running_ ? "true" : "false");
    
    if (!config_path_.empty()) {
        std::string statsFile = config_path_ + ".stats";
        std::ifstream ifs(statsFile);
        if (ifs.is_open()) {
            std::string content((std::istreambuf_iterator<char>(ifs)), std::istreambuf_iterator<char>());
            if (!content.empty()) {
                stats += "; " + content;
            }
        }
    }

    if (!last_error_.empty()) {
        stats += "; mihomoError=" + last_error_;
    }
    return stats;
}

bool MihomoAdapter::IsRunning() const
{
    return running_;
}

} // namespace harmony_vpn_poc
