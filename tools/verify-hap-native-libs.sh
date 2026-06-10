#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: tools/verify-hap-native-libs.sh [path/to/entry-default-signed.hap]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HAP_PATH="${1:-$ROOT_DIR/entry/build/default/outputs/default/entry-default-signed.hap}"
ADAPTER_IN_HAP="libs/arm64-v8a/libmihomo_adapter.so"
VPN_CORE_IN_HAP="libs/arm64-v8a/libvpn_core.so"
PREBUILT_ADAPTER="$ROOT_DIR/entry/libs/arm64-v8a/libmihomo_adapter.so"

if [[ ! -f "$HAP_PATH" ]]; then
  echo "HAP not found: $HAP_PATH" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "'unzip' command is required to inspect HAP files." >&2
  exit 1
fi

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    LC_ALL=C LANG=C shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    LC_ALL=C LANG=C sha256sum "$path" | awk '{print $1}'
  else
    echo "sha256-unavailable"
  fi
}

echo "Inspecting HAP: $HAP_PATH"

if ! unzip -l "$HAP_PATH" "$VPN_CORE_IN_HAP" >/dev/null 2>&1; then
  echo "Missing $VPN_CORE_IN_HAP in HAP." >&2
  exit 1
fi

if ! unzip -l "$HAP_PATH" "$ADAPTER_IN_HAP" >/dev/null 2>&1; then
  echo "Missing $ADAPTER_IN_HAP in HAP." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unzip -q "$HAP_PATH" "$ADAPTER_IN_HAP" -d "$TMP_DIR"
EXTRACTED_ADAPTER="$TMP_DIR/$ADAPTER_IN_HAP"

"$ROOT_DIR/tools/verify-mihomo-adapter.sh" "$EXTRACTED_ADAPTER"

HAP_SHA="$(sha256_file "$EXTRACTED_ADAPTER")"
echo "HAP adapter sha256: $HAP_SHA"

if LC_ALL=C LANG=C strings "$EXTRACTED_ADAPTER" | grep -q "adapterKind=stub"; then
  echo "Warning: HAP adapter looks like the bundled stub. It will not provide real proxy traffic."
else
  echo "HAP adapter does not contain the known stub marker."
fi

if [[ -f "$PREBUILT_ADAPTER" ]]; then
  PREBUILT_SHA="$(sha256_file "$PREBUILT_ADAPTER")"
  echo "Prebuilt adapter sha256: $PREBUILT_SHA"
  if [[ "$HAP_SHA" != "$PREBUILT_SHA" ]]; then
    echo "Notice: HAP adapter sha256 differs from entry/libs prebuilt adapter. This is expected when the build strips native libraries."
    echo "        ABI and stub-marker checks above are the authoritative checks for this script."
  else
    echo "HAP adapter matches entry/libs prebuilt adapter."
  fi
else
  echo "No entry/libs prebuilt adapter found; HAP likely contains the C++ stub built by CMake."
fi

echo "HAP native library verification passed."
