# Docker Build For Mihomo Adapter

Docker 可以用来构建 `libmihomo_adapter.so`，但镜像里必须同时具备：

1. Linux 版 OpenHarmony/HarmonyOS Native SDK。
2. 支持 `GOOS=ohos GOARCH=arm64` 的 Go 工具链。

普通官方 Go 镜像通常不支持 `ohos/arm64`，只能验证失败路径，不能产出真实 HarmonyOS Go shared library。

如果只是想实验性产出 arm64 ELF `.so`，可以用 `GO_TARGET_OS=linux`。这条路线能避开官方 Go 没有 `ohos` target 的限制，但 Go runtime target 仍是 `linux`，不是 `ohos`，必须真机验证：

```bash
GO_TARGET_OS=linux \
GO_TARGET_ARCH=arm64 \
OHOS_SDK_DIR=/path/to/command-line-tools/sdk \
tools/docker-build-mihomo-adapter.sh
```

## Build Image

如果你有支持 `ohos/arm64` 的 Go tarball：

```bash
docker build \
  --platform linux/amd64 \
  -f docker/mihomo-adapter/Dockerfile \
  --build-arg GO_TARBALL_URL=https://example.com/go-ohos-linux-amd64.tar.gz \
  -t harmony-mihomo-adapter .
```

如果你的基础镜像已经内置了该 Go 工具链，可以不传 `GO_TARBALL_URL`，但容器里的 `go tool dist list` 必须包含 `ohos/arm64`。

如果 Go tarball 已经下载到本机，更推荐直接用仓库脚本注入容器：

```bash
GO_TARBALL_FILE=/path/to/go-ohos-linux-amd64.tar.gz \
OHOS_SDK_DIR=/path/to/command-line-tools/sdk \
tools/docker-build-mihomo-adapter.sh
```

## Run

把 Linux 版 OHOS SDK 挂载到 `/opt/ohos-sdk`：

```bash
docker run --rm \
  --platform linux/amd64 \
  -v "$PWD:/workspace" \
  -v "/path/to/linux-ohos-sdk:/opt/ohos-sdk:ro" \
  harmony-mihomo-adapter
```

Linux(x86) Command Line Tools 需要在 `linux/amd64` 容器里运行。本仓库脚本默认使用 `DOCKER_PLATFORM=linux/amd64`。

也可以直接把下载好的 Linux Command Line Tools 压缩包交给仓库脚本，脚本会自动解压并定位 SDK：

```bash
OHOS_SDK_ARCHIVE=/path/to/command-line-tools-linux-x86-6.1.1.280.zip \
tools/docker-build-mihomo-adapter.sh
```

如果已经解压好了，则传 SDK 目录：

```bash
OHOS_SDK_DIR=/path/to/command-line-tools/sdk \
tools/docker-build-mihomo-adapter.sh
```

成功后应生成：

```text
entry/libs/arm64-v8a/libmihomo_adapter.so
```

然后重新构建 HAP。`entry/src/main/cpp/CMakeLists.txt` 会检测这个预编译库并跳过 C++ stub。

## Important

不要把 macOS 版 DevEco Studio SDK 直接挂进 Linux 容器用于执行 clang。macOS SDK 里的 clang 是 Darwin 可执行文件，Linux 容器无法运行。容器里需要 Linux 版 SDK/toolchain。
