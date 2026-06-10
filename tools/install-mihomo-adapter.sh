#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: tools/install-mihomo-adapter.sh /path/to/libmihomo_adapter.so" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SO="$1"
TARGET_DIR="$ROOT_DIR/entry/libs/arm64-v8a"
TARGET_SO="$TARGET_DIR/libmihomo_adapter.so"

if [[ ! -f "$SOURCE_SO" ]]; then
  echo "Adapter not found: $SOURCE_SO" >&2
  exit 1
fi

"$ROOT_DIR/tools/verify-mihomo-adapter.sh" "$SOURCE_SO"

mkdir -p "$TARGET_DIR"
cp "$SOURCE_SO" "$TARGET_SO"
echo "Installed $TARGET_SO"
echo "Rebuild the HAP. CMake will detect the prebuilt adapter and skip the C++ stub."
