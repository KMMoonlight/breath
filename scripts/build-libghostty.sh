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

XCFRAMEWORK="${VENDOR_DIR}/GhosttyKit.xcframework"
XCFRAMEWORK_PLIST="${XCFRAMEWORK}/Info.plist"
LIBRARY_INDEX=0
while library_identifier=$(
  /usr/libexec/PlistBuddy \
    -c "Print :AvailableLibraries:${LIBRARY_INDEX}:LibraryIdentifier" \
    "${XCFRAMEWORK_PLIST}" 2>/dev/null
); do
  if [[ "${library_identifier}" == macos-* ]]; then
    library_path=$(
      /usr/libexec/PlistBuddy \
        -c "Print :AvailableLibraries:${LIBRARY_INDEX}:LibraryPath" \
        "${XCFRAMEWORK_PLIST}"
    )
    if [[ "${library_path:t}" != lib* ]]; then
      swiftpm_library_path="lib${library_path:t}"
      /bin/mv \
        "${XCFRAMEWORK}/${library_identifier}/${library_path}" \
        "${XCFRAMEWORK}/${library_identifier}/${swiftpm_library_path}"
      /usr/libexec/PlistBuddy \
        -c "Set :AvailableLibraries:${LIBRARY_INDEX}:BinaryPath ${swiftpm_library_path}" \
        -c "Set :AvailableLibraries:${LIBRARY_INDEX}:LibraryPath ${swiftpm_library_path}" \
        "${XCFRAMEWORK_PLIST}"
    fi
  fi
  (( LIBRARY_INDEX += 1 ))
done

GHOSTTY_ARCHIVES=("${VENDOR_DIR}"/GhosttyKit.xcframework/macos-*/*.a(N))
if (( ${#GHOSTTY_ARCHIVES} != 1 )); then
  print -u2 "Expected one macOS Ghostty archive; found ${#GHOSTTY_ARCHIVES}"
  exit 1
fi

normalize_archive_members() {
  local archive="$1"
  local ext_object_count
  ext_object_count=$(
    /usr/bin/ar -t "${archive}" \
      | /usr/bin/awk '$0 == "ext.o" { count += 1 } END { print count + 0 }'
  )
  if (( ext_object_count == 2 )); then
    # dsymutil resolves archive members by basename, so Ghostty's two ext.o
    # members must have unique names even though the linker handles them safely.
    local normalize_dir
    normalize_dir=$(mktemp -d "${TMPDIR:-/tmp}/breath-ghostty-archive.XXXXXX")
    (
      cd "${normalize_dir}"
      /usr/bin/ar -x "${archive}" ext.o
      /bin/chmod u+rw ext.o
      /bin/mv ext.o macos_text_ext.o
      /usr/bin/ar -d "${archive}" ext.o
      /usr/bin/ar -q "${archive}" macos_text_ext.o
      /usr/bin/ranlib "${archive}"
    )
    rm -rf "${normalize_dir}"
  elif (( ext_object_count != 1 )); then
    print -u2 "Unexpected ext.o member count in Ghostty archive: ${ext_object_count}"
    exit 1
  fi
}

GHOSTTY_ARCHIVE="${GHOSTTY_ARCHIVES[1]}"
ARCHITECTURES=("${(@s: :)$(/usr/bin/lipo -archs "${GHOSTTY_ARCHIVE}")}")
if (( ${#ARCHITECTURES} == 1 )); then
  normalize_archive_members "${GHOSTTY_ARCHIVE}"
else
  FAT_NORMALIZE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/breath-ghostty-fat-archive.XXXXXX")
  THIN_ARCHIVES=()
  for architecture in "${ARCHITECTURES[@]}"; do
    thin_archive="${FAT_NORMALIZE_DIR}/${architecture}.a"
    /usr/bin/lipo "${GHOSTTY_ARCHIVE}" \
      -thin "${architecture}" \
      -output "${thin_archive}"
    normalize_archive_members "${thin_archive}"
    THIN_ARCHIVES+=("${thin_archive}")
  done
  /usr/bin/lipo -create "${THIN_ARCHIVES[@]}" \
    -output "${FAT_NORMALIZE_DIR}/ghostty-internal.a"
  /bin/mv -f "${FAT_NORMALIZE_DIR}/ghostty-internal.a" "${GHOSTTY_ARCHIVE}"
  rm -rf "${FAT_NORMALIZE_DIR}"
fi

print "Built GhosttyKit.xcframework from ${REVISION}"
