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
    -Demit-themes=true \
    -Doptimize=ReleaseFast
)

/usr/bin/env swift \
  "${ROOT}/scripts/generate-ghostty-theme-catalog.swift" \
  "${SOURCE_DIR}/zig-out/share/ghostty/themes" \
  "${ROOT}/Sources/BreathCore/GhosttyThemeCatalog.swift"

mkdir -p "${VENDOR_DIR}"
rm -rf "${VENDOR_DIR}/GhosttyKit.xcframework"
ditto "${SOURCE_DIR}/macos/GhosttyKit.xcframework" "${VENDOR_DIR}/GhosttyKit.xcframework"

GHOSTTY_FRAMEWORK="${VENDOR_DIR}/GhosttyKit.xcframework"
GHOSTTY_INFO_PLIST="${GHOSTTY_FRAMEWORK}/Info.plist"
MACOS_LIBRARY_INDEX=""
for INDEX in {0..15}; do
  PLATFORM=$(
    /usr/libexec/PlistBuddy \
      -c "Print :AvailableLibraries:${INDEX}:SupportedPlatform" \
      "${GHOSTTY_INFO_PLIST}" 2>/dev/null
  ) || break
  if [[ "${PLATFORM}" == "macos" ]]; then
    MACOS_LIBRARY_INDEX="${INDEX}"
    break
  fi
done
if [[ -z "${MACOS_LIBRARY_INDEX}" ]]; then
  print -u2 "Missing macOS library entry in ${GHOSTTY_INFO_PLIST}"
  exit 1
fi

GHOSTTY_LIBRARY_IDENTIFIER=$(
  /usr/libexec/PlistBuddy \
    -c "Print :AvailableLibraries:${MACOS_LIBRARY_INDEX}:LibraryIdentifier" \
    "${GHOSTTY_INFO_PLIST}"
)
GHOSTTY_LIBRARY_PATH=$(
  /usr/libexec/PlistBuddy \
    -c "Print :AvailableLibraries:${MACOS_LIBRARY_INDEX}:LibraryPath" \
    "${GHOSTTY_INFO_PLIST}"
)
GHOSTTY_LIBRARY_DIR="${GHOSTTY_FRAMEWORK}/${GHOSTTY_LIBRARY_IDENTIFIER}"
GHOSTTY_ARCHIVE="${GHOSTTY_LIBRARY_DIR}/libghostty-internal.a"
if [[ "${GHOSTTY_LIBRARY_PATH}" != "libghostty-internal.a" ]]; then
  /bin/mv "${GHOSTTY_LIBRARY_DIR}/${GHOSTTY_LIBRARY_PATH}" "${GHOSTTY_ARCHIVE}"
  /usr/libexec/PlistBuddy \
    -c "Set :AvailableLibraries:${MACOS_LIBRARY_INDEX}:BinaryPath libghostty-internal.a" \
    -c "Set :AvailableLibraries:${MACOS_LIBRARY_INDEX}:LibraryPath libghostty-internal.a" \
    "${GHOSTTY_INFO_PLIST}"
fi
if [[ ! -f "${GHOSTTY_ARCHIVE}" ]]; then
  print -u2 "Missing macOS Ghostty archive: ${GHOSTTY_ARCHIVE}"
  exit 1
fi
/usr/bin/plutil -lint "${GHOSTTY_INFO_PLIST}" >/dev/null

# dsymutil resolves archive members by basename, so Ghostty's two ext.o
# members must have unique names even though the linker handles them safely.
# The macOS XCFramework library is universal, so normalize each architecture
# independently before combining the slices again.
NORMALIZE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/breath-ghostty-archive.XXXXXX")
NORMALIZED_SLICES=()
for ARCH in arm64 x86_64; do
  THIN_ARCHIVE="${NORMALIZE_DIR}/ghostty-${ARCH}.a"
  /usr/bin/lipo "${GHOSTTY_ARCHIVE}" -thin "${ARCH}" -output "${THIN_ARCHIVE}"

  EXT_OBJECT_COUNT=$(/usr/bin/ar -t "${THIN_ARCHIVE}" | /usr/bin/awk '$0 == "ext.o" { count += 1 } END { print count + 0 }')
  if (( EXT_OBJECT_COUNT == 2 )); then
    SLICE_DIR="${NORMALIZE_DIR}/${ARCH}"
    mkdir -p "${SLICE_DIR}"
    (
      cd "${SLICE_DIR}"
      /usr/bin/ar -x "${THIN_ARCHIVE}" ext.o
      /bin/chmod u+rw ext.o
      /bin/mv ext.o macos_text_ext.o
      /usr/bin/ar -d "${THIN_ARCHIVE}" ext.o
      /usr/bin/ar -q "${THIN_ARCHIVE}" macos_text_ext.o
      /usr/bin/ranlib "${THIN_ARCHIVE}"
    )
  elif (( EXT_OBJECT_COUNT != 1 )); then
    print -u2 "Unexpected ext.o member count in Ghostty ${ARCH} archive: ${EXT_OBJECT_COUNT}"
    rm -rf "${NORMALIZE_DIR}"
    exit 1
  fi

  NORMALIZED_SLICES+=("${THIN_ARCHIVE}")
done

/usr/bin/lipo -create "${NORMALIZED_SLICES[@]}" -output "${NORMALIZE_DIR}/ghostty-internal.a"
/bin/mv "${NORMALIZE_DIR}/ghostty-internal.a" "${GHOSTTY_ARCHIVE}"
rm -rf "${NORMALIZE_DIR}"

# SwiftPM caches the evaluated manifest without tracking the framework path.
# Invalidate that cache after the ignored local artifact appears.
/usr/bin/touch "${ROOT}/Package.swift"

print "Built GhosttyKit.xcframework from ${REVISION}"
