#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: tools/verify-mihomo-adapter.sh /path/to/libmihomo_adapter.so" >&2
  exit 1
fi

SOURCE_SO="$1"
REQUIRED_SYMBOLS=(
  StartMihomoAdapter
  StopMihomoAdapter
)

if [[ ! -f "$SOURCE_SO" ]]; then
  echo "Adapter not found: $SOURCE_SO" >&2
  exit 1
fi

if ! command -v file >/dev/null 2>&1; then
  echo "'file' command is required to verify native library format." >&2
  exit 1
fi

FILE_INFO="$(file "$SOURCE_SO")"
echo "$FILE_INFO"

if [[ "$FILE_INFO" != *"ELF"* ]]; then
  echo "Adapter is not an ELF shared library: $SOURCE_SO" >&2
  exit 1
fi

if [[ "$FILE_INFO" != *"shared object"* ]]; then
  echo "Adapter is not a shared object: $SOURCE_SO" >&2
  exit 1
fi

if [[ "$FILE_INFO" != *"ARM aarch64"* && "$FILE_INFO" != *"AArch64"* && "$FILE_INFO" != *"ARM64"* ]]; then
  echo "Adapter is not arm64/aarch64. HarmonyOS NEXT phone builds need arm64-v8a." >&2
  exit 1
fi

candidate_readelf_paths() {
  local sdk_dir
  for sdk_dir in "${DEVECO_SDK_HOME:-}" "${OHOS_SDK_HOME:-}" "${OHOS_SDK_DIR:-}" "/Applications/DevEco-Studio.app/Contents/sdk"; do
    if [[ -n "$sdk_dir" && -d "$sdk_dir" ]]; then
      find "$sdk_dir" -name llvm-readelf 2>/dev/null
    fi
  done
  command -v llvm-readelf 2>/dev/null || true
  command -v readelf 2>/dev/null || true
}

find_working_readelf() {
  local tool
  while IFS= read -r tool; do
    [[ -n "$tool" ]] || continue
    if "$tool" --version >/dev/null 2>&1; then
      echo "$tool"
      return 0
    fi
  done < <(candidate_readelf_paths)
  return 1
}

SYMBOL_TEXT=""
if READELF_BIN="$(find_working_readelf)"; then
  echo "Using readelf: $READELF_BIN"
  SYMBOL_TEXT="$("$READELF_BIN" --dyn-syms --wide "$SOURCE_SO")"
else
  echo "Warning: no working llvm-readelf/readelf found; falling back to strings-based symbol check." >&2
  SYMBOL_TEXT="$(strings "$SOURCE_SO")"
fi

for symbol in "${REQUIRED_SYMBOLS[@]}"; do
  if ! grep -Eq "(^|[[:space:]])${symbol}(@|$|[[:space:]])" <<<"$SYMBOL_TEXT"; then
    echo "Missing required C ABI symbol: $symbol" >&2
    exit 1
  fi
done

echo "Adapter verification passed: $SOURCE_SO"
