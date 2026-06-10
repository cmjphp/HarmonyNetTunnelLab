#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-harmony-mihomo-adapter}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
OHOS_SDK_DIR="${OHOS_SDK_DIR:-}"
OHOS_SDK_ARCHIVE="${OHOS_SDK_ARCHIVE:-}"
GO_TARBALL_URL="${GO_TARBALL_URL:-}"
GO_TARBALL_FILE="${GO_TARBALL_FILE:-}"
GO_TARGET_OS="${GO_TARGET_OS:-ohos}"
GO_TARGET_ARCH="${GO_TARGET_ARCH:-arm64}"
CACHE_DIR="$ROOT_DIR/.cache/ohos-sdk-linux"

find_sdk_dir() {
  local search_root="$1"
  local clang_path
  clang_path="$(find "$search_root" -type f -name aarch64-unknown-linux-ohos-clang 2>/dev/null | head -n 1 || true)"
  if [[ -z "$clang_path" ]]; then
    return 1
  fi
  local native_dir
  native_dir="$(cd "$(dirname "$clang_path")/../../.." && pwd)"
  if [[ "$(basename "$native_dir")" == "native" ]]; then
    cd "$native_dir/.." && pwd
    return 0
  fi
  return 1
}

prepare_sdk_from_archive() {
  local archive="$1"
  if [[ ! -f "$archive" ]]; then
    echo "OHOS_SDK_ARCHIVE does not exist: $archive" >&2
    exit 1
  fi
  rm -rf "$CACHE_DIR"
  mkdir -p "$CACHE_DIR"
  case "$archive" in
    *.zip)
      unzip -q "$archive" -d "$CACHE_DIR"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$CACHE_DIR"
      ;;
    *.tar.xz)
      tar -xJf "$archive" -C "$CACHE_DIR"
      ;;
    *)
      echo "Unsupported OHOS_SDK_ARCHIVE format: $archive" >&2
      exit 1
      ;;
  esac
  if ! OHOS_SDK_DIR="$(find_sdk_dir "$CACHE_DIR")"; then
    echo "Could not locate OHOS SDK native clang in archive: $archive" >&2
    exit 1
  fi
  export OHOS_SDK_DIR
  echo "Detected OHOS_SDK_DIR=$OHOS_SDK_DIR"
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not in PATH." >&2
  exit 1
fi

if [[ -n "$OHOS_SDK_ARCHIVE" ]]; then
  prepare_sdk_from_archive "$OHOS_SDK_ARCHIVE"
fi

if [[ -z "$OHOS_SDK_DIR" ]]; then
  cat >&2 <<'MSG'
OHOS_SDK_DIR or OHOS_SDK_ARCHIVE is required.

It must point to a Linux OpenHarmony/HarmonyOS Native SDK directory/archive,
not the macOS DevEco Studio SDK under /Applications.

Examples:
  OHOS_SDK_DIR=/path/to/linux-ohos-sdk tools/docker-build-mihomo-adapter.sh
  OHOS_SDK_ARCHIVE=/path/to/command-line-tools-linux-x86.zip tools/docker-build-mihomo-adapter.sh
MSG
  exit 1
fi

if [[ ! -d "$OHOS_SDK_DIR" ]]; then
  echo "OHOS_SDK_DIR does not exist: $OHOS_SDK_DIR" >&2
  exit 1
fi

if [[ -n "$GO_TARBALL_FILE" && ! -f "$GO_TARBALL_FILE" ]]; then
  echo "GO_TARBALL_FILE does not exist: $GO_TARBALL_FILE" >&2
  exit 1
fi

if ! find "$OHOS_SDK_DIR" -type f -name aarch64-unknown-linux-ohos-clang | grep -q .; then
  echo "OHOS_SDK_DIR does not contain aarch64-unknown-linux-ohos-clang: $OHOS_SDK_DIR" >&2
  exit 1
fi

docker build \
  --platform "$DOCKER_PLATFORM" \
  -f "$ROOT_DIR/docker/mihomo-adapter/Dockerfile" \
  --build-arg "GO_TARBALL_URL=$GO_TARBALL_URL" \
  -t "$IMAGE_NAME" \
  "$ROOT_DIR"

DOCKER_RUN_ARGS=(
  --rm
  --platform "$DOCKER_PLATFORM"
  -v "$ROOT_DIR:/workspace"
  -v "$OHOS_SDK_DIR:/opt/ohos-sdk:ro"
  -e "GO_TARGET_OS=$GO_TARGET_OS"
  -e "GO_TARGET_ARCH=$GO_TARGET_ARCH"
)

DOCKER_CMD='bash tools/build-mihomo-adapter.sh'
if [[ -n "$GO_TARBALL_FILE" ]]; then
  DOCKER_RUN_ARGS+=(-v "$GO_TARBALL_FILE:/tmp/go-ohos.tar.gz:ro")
  DOCKER_CMD='rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go-ohos.tar.gz && bash tools/build-mihomo-adapter.sh'
fi

docker run "${DOCKER_RUN_ARGS[@]}" "$IMAGE_NAME" bash -lc "$DOCKER_CMD"
