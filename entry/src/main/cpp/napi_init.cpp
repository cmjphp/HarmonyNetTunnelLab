#include "napi/native_api.h"
#include "native/vpn_core.h"

#include <vector>

static napi_value StartCore(napi_env env, napi_callback_info info)
{
    napi_value result;
    napi_create_int32(env, harmony_vpn_poc::StartCore(), &result);
    return result;
}

static napi_value StopCore(napi_env env, napi_callback_info info)
{
    napi_value result;
    napi_create_int32(env, harmony_vpn_poc::StopCore(), &result);
    return result;
}

static napi_value SetTunFd(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t fd = -1;
    if (argc >= 1) {
        napi_get_value_int32(env, args[0], &fd);
    }

    napi_value result;
    napi_create_int32(env, harmony_vpn_poc::SetTunFd(fd), &result);
    return result;
}

static napi_value SetConfig(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = { nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::vector<char> config(1, '\0');
    if (argc >= 1) {
        size_t length = 0;
        napi_get_value_string_utf8(env, args[0], nullptr, 0, &length);
        config.resize(length + 1);
        napi_get_value_string_utf8(env, args[0], config.data(), config.size(), &length);
    }

    napi_value result;
    napi_create_int32(env, harmony_vpn_poc::SetConfig(config.data()), &result);
    return result;
}

static napi_value GetStats(napi_env env, napi_callback_info info)
{
    const char* stats = harmony_vpn_poc::GetStats();
    napi_value result;
    napi_create_string_utf8(env, stats, NAPI_AUTO_LENGTH, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"startCore", nullptr, StartCore, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopCore", nullptr, StopCore, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setTunFd", nullptr, SetTunFd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setConfig", nullptr, SetConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getStats", nullptr, GetStats, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
EXTERN_C_END

static napi_module vpn_core_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "vpn_core",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterVpnCoreModule()
{
    napi_module_register(&vpn_core_module);
}
