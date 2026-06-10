# Mihomo Adapter ABI

`libvpn_core.so` 会在运行时通过 `dlopen("libmihomo_adapter.so")` 加载真正的 mihomo 适配层。

当前工程保留一个可选同名 stub：`mihomo_adapter_stub.cpp`。它只用于验证 HAP 打包、`dlopen`、C ABI 调用、配置路径传递和 TUN fd 传递。它的 `MihomoStart()` 固定返回 `-100`，因此不会假装真实代理成功。CMake 默认不再构建 stub，只有显式打开 `BUILD_BUNDLED_MIHOMO_STUB` 时才会使用它。

当前 `tools/mihomo-adapter-go` 已实现实验性 Go c-shared adapter：导入 `github.com/metacubex/mihomo`，读取 ArkTS 生成的 `mihomo_runtime.yaml`，注入 `tun.file-descriptor`，并通过 `hub.Parse` / `executor.Shutdown` 管理 mihomo 生命周期。

适配库需要导出以下 C ABI：

```cpp
extern "C" int MihomoSetConfigPath(const char* path);
extern "C" int MihomoSetTunFd(int fd);
extern "C" int MihomoStart();
extern "C" int MihomoStop();
extern "C" const char* MihomoGetStats();
```

约定：

- `MihomoSetConfigPath` 接收 ArkTS 生成的 `mihomo_runtime.yaml` 沙箱路径。
- `MihomoSetTunFd` 接收 `VpnConnection.create()` 返回的 TUN fd。
- `MihomoStart` 返回 `0` 表示启动成功，返回 `1` 表示已经启动，其他值表示失败。
- `MihomoStop` 返回 `0` 表示停止成功。
- `MihomoGetStats` 返回 adapter 内部状态文本，方便 UI 和日志确认真实 core 是否运行。

安装/替换适配库有两种方式：

1. 使用 `tools/build-mihomo-adapter.sh` 构建 `tools/mihomo-adapter-go`。
2. 或者把真实适配库放入工程可打包的 native lib 目录，例如：

```text
entry/libs/arm64-v8a/libmihomo_adapter.so
```

本仓库已提供两个辅助脚本：

```bash
tools/build-mihomo-adapter.sh
tools/verify-mihomo-adapter.sh /path/to/libmihomo_adapter.so
tools/install-mihomo-adapter.sh /path/to/libmihomo_adapter.so
```

`tools/build-mihomo-adapter.sh` 会先检查本机 Go 是否支持 `GOOS=ohos GOARCH=arm64`。如果当前 Go 不支持 `ohos/arm64`，脚本会失败并提示需要 HarmonyOS/OpenHarmony-capable Go toolchain，或者使用外部环境构建好 `libmihomo_adapter.so` 后再通过 `install-mihomo-adapter.sh` 安装。

当前本机已验证可通过实验路径生成 arm64 ELF `.so`：

```bash
OHOS_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
GO_TARGET_OS=linux \
GO_TARGET_ARCH=arm64 \
tools/build-mihomo-adapter.sh
```

这会生成 `entry/libs/arm64-v8a/libmihomo_adapter.so`。注意它的 Go runtime target 是 `linux`，不是官方 `ohos`，所以最终是否稳定可用需要以 HarmonyOS NEXT 真机验证为准。

`tools/verify-mihomo-adapter.sh` 会检查 `.so` 是否为 arm64 ELF shared object，并确认导出了 `MihomoSetConfigPath`、`MihomoSetTunFd`、`MihomoStart`、`MihomoStop`、`MihomoGetStats`。`install-mihomo-adapter.sh` 会先执行这个校验，通过后才复制到 `entry/libs/arm64-v8a/`。

如果 `entry/libs/arm64-v8a/libmihomo_adapter.so` 已存在，CMake 会使用这个预编译库；stub target 默认关闭，避免真实库被同名 stub 覆盖。

如果真机 Core 状态中出现 `adapterKind=stub` 和 `startError=-100`，说明 adapter 加载链路已经打通，但当前仍是 stub，不具备真实代理能力。

如果真机日志中出现 `dlopen libmihomo_adapter.so failed`，说明 HAP 没有包含 `libmihomo_adapter.so`，或库名/ABI 不匹配。
