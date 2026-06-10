#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
if [[ -n "${OHOS_SDK_HOME:-}" ]]; then
  SDK_HOME="$OHOS_SDK_HOME"
fi
GO_BIN="${GO_BIN:-go}"
GO_TARGET_OS="${GO_TARGET_OS:-ohos}"
GO_TARGET_ARCH="${GO_TARGET_ARCH:-arm64}"
OUT_DIR="$ROOT_DIR/entry/libs/arm64-v8a"
OUT_SO="$OUT_DIR/libmihomo_adapter.so"
OHOS_CC="$SDK_HOME/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang"
OHOS_CXX="$SDK_HOME/default/openharmony/native/llvm/bin/aarch64-unknown-linux-ohos-clang++"

if [[ ! -x "$OHOS_CC" || ! -x "$OHOS_CXX" ]]; then
  OHOS_CC="$SDK_HOME/native/llvm/bin/aarch64-unknown-linux-ohos-clang"
  OHOS_CXX="$SDK_HOME/native/llvm/bin/aarch64-unknown-linux-ohos-clang++"
fi

if ! command -v "$GO_BIN" >/dev/null 2>&1; then
  echo "Go toolchain not found. Set GO_BIN or install Go." >&2
  exit 1
fi

if ! "$GO_BIN" tool dist list | grep -F -x "$GO_TARGET_OS/$GO_TARGET_ARCH" >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Current Go toolchain does not support the requested target.

This machine can compile the C++ VPN bridge, but it cannot yet build a real
HarmonyOS Go c-shared mihomo adapter. Use one of these paths:

1. Install a HarmonyOS/OpenHarmony-capable Go toolchain that supports ohos/arm64.
2. Build libmihomo_adapter.so in a separate environment and install it with:
   tools/install-mihomo-adapter.sh /path/to/libmihomo_adapter.so
3. For experiment only, try GO_TARGET_OS=linux with the OHOS clang toolchain.
   This may produce an arm64 ELF .so, but it is not guaranteed to run correctly
   on HarmonyOS because the Go runtime target remains linux, not ohos.
MSG
  echo "Requested target: $GO_TARGET_OS/$GO_TARGET_ARCH" >&2
  exit 2
fi

if [[ "$GO_TARGET_OS" != "ohos" ]]; then
  cat >&2 <<MSG
Warning: building adapter with GOOS=$GO_TARGET_OS GOARCH=$GO_TARGET_ARCH.
This is an experiment to produce a loadable arm64 ELF .so. Runtime behavior on
HarmonyOS NEXT still needs real-device validation.
MSG
fi

if [[ ! -x "$OHOS_CC" || ! -x "$OHOS_CXX" ]]; then
  echo "OHOS clang toolchain not found under: $SDK_HOME" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
(
  cd "$ROOT_DIR/tools/mihomo-adapter-go"
  GOOS="$GO_TARGET_OS" \
  GOARCH="$GO_TARGET_ARCH" \
  CGO_ENABLED=1 \
  CC="$OHOS_CC" \
  CXX="$OHOS_CXX" \
  "$GO_BIN" build -tags "cmfa,with_gvisor" -buildmode=c-shared -o "$OUT_SO" .
)

echo "Built $OUT_SO"
