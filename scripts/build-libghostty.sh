#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
REVISION="55a3e33ab26a23d75b274b23c7f76d837db00578"
SOURCE_DIR="${ROOT}/.build/libghostty-source"
VENDOR_DIR="${ROOT}/Vendor"
ZIG_BIN="${ZIG_BIN:-$(command -v zig 2>/dev/null || true)}"
METAL_TOOLCHAIN="${METAL_TOOLCHAIN:-}"

if [[ ! -x "${ZIG_BIN}" ]]; then
  print -u2 "Zig 0.15 is required. Install it with: brew install zig@0.15"
  exit 1
fi
if [[ "$("${ZIG_BIN}" version)" != 0.15.* ]]; then
  print -u2 "Zig 0.15 is required; found $("${ZIG_BIN}" version)"
  exit 1
fi

if [[ -z "${METAL_TOOLCHAIN}" ]]; then
  TOOLCHAIN_INFO=$(find \
    /var/run/com.apple.security.cryptexd/mnt \
    /Library/Developer/Toolchains \
    "${HOME}/Library/Developer/Toolchains" \
    -path '*/Metal.xctoolchain/ToolchainInfo.plist' \
    -print -quit 2>/dev/null || true)
  if [[ -z "${TOOLCHAIN_INFO}" ]]; then
    print -u2 "Apple Metal Toolchain is required. Run: xcodebuild -downloadComponent MetalToolchain"
    exit 1
  fi
  METAL_TOOLCHAIN=$(/usr/libexec/PlistBuddy -c 'Print :Identifier' "${TOOLCHAIN_INFO}")
fi

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  git clone --filter=blob:none https://github.com/ghostty-org/ghostty.git "${SOURCE_DIR}"
fi

git -C "${SOURCE_DIR}" fetch --depth 1 origin "${REVISION}"
git -C "${SOURCE_DIR}" checkout --detach "${REVISION}"

(
  cd "${SOURCE_DIR}"
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
)

mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/GhosttyKit.xcframework"
ditto "${SOURCE_DIR}/macos/GhosttyKit.xcframework" "${VENDOR_DIR}/GhosttyKit.xcframework"

GHOSTTY_ARCHIVE="${VENDOR_DIR}/GhosttyKit.xcframework/macos-arm64/libghostty-internal-fat.a"
EXT_OBJECT_COUNT=$(/usr/bin/ar -t "${GHOSTTY_ARCHIVE}" | /usr/bin/awk '$0 == "ext.o" { count += 1 } END { print count + 0 }')
if (( EXT_OBJECT_COUNT == 2 )); then
  # dsymutil resolves archive members by basename, so Ghostty's two ext.o
  # members must have unique names even though the linker handles them safely.
  NORMALIZE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/breath-ghostty-archive.XXXXXX")
  (
    cd "${NORMALIZE_DIR}"
    /usr/bin/ar -x "${GHOSTTY_ARCHIVE}" ext.o
    /bin/chmod u+rw ext.o
    /bin/mv ext.o macos_text_ext.o
    /usr/bin/ar -d "${GHOSTTY_ARCHIVE}" ext.o
    /usr/bin/ar -q "${GHOSTTY_ARCHIVE}" macos_text_ext.o
    /usr/bin/ranlib "${GHOSTTY_ARCHIVE}"
  )
  rm -rf "${NORMALIZE_DIR}"
elif (( EXT_OBJECT_COUNT != 1 )); then
  print -u2 "Unexpected ext.o member count in Ghostty archive: ${EXT_OBJECT_COUNT}"
  exit 1
fi

print "Built GhosttyKit.xcframework from ${REVISION}"
