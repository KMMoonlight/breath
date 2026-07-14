#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
REVISION="55a3e33ab26a23d75b274b23c7f76d837db00578"
SOURCE_DIR="${ROOT}/.build/libghostty-source"
VENDOR_DIR="${ROOT}/Vendor"
ZIG_BIN="${ZIG_BIN:-/opt/homebrew/opt/zig@0.15/bin/zig}"
METAL_TOOLCHAIN="${METAL_TOOLCHAIN:-com.apple.dt.toolchain.Metal.32023.864}"

if [[ ! -x "${ZIG_BIN}" ]]; then
  print -u2 "Zig 0.15 is required. Install it with: brew install zig@0.15"
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  git clone --filter=blob:none https://github.com/ghostty-org/ghostty.git "${SOURCE_DIR}"
fi

git -C "${SOURCE_DIR}" fetch --depth 1 origin "${REVISION}"
git -C "${SOURCE_DIR}" checkout --detach "${REVISION}"

env \
  TOOLCHAINS="${METAL_TOOLCHAIN}" \
  PATH="${ZIG_BIN:h}:/opt/homebrew/bin:/usr/bin:/bin" \
  ZIG_GLOBAL_CACHE_DIR="${ROOT}/.build/zig-cache" \
  "${ZIG_BIN}" build \
  -Demit-lib-vt=false \
  -Dapp-runtime=none \
  -Demit-xcframework=true \
  -Demit-macos-app=false \
  -Dxcframework-target=universal \
  -Dsentry=false \
  -Di18n=false \
  -Demit-docs=false \
  -Demit-terminfo=false \
  -Demit-themes=false \
  -Doptimize=ReleaseFast

mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/GhosttyKit.xcframework"
ditto "${SOURCE_DIR}/macos/GhosttyKit.xcframework" "${VENDOR_DIR}/GhosttyKit.xcframework"
print "Built GhosttyKit.xcframework from ${REVISION}"

