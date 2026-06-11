#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

GO_BIN=/Users/chenmeijun/harmony-tools/ohos_golang_go/bin/go \
GOROOT=/Users/chenmeijun/harmony-tools/ohos_golang_go \
GO_TARGET_OS=openharmony \
GO_TARGET_ARCH=arm64 \
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
bash tools/build-mihomo-adapter.sh
