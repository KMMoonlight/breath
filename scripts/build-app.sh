#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION_VALUE="${VERSION:-0.0.0}"
OUTPUT_VALUE="${OUTPUT_DIR:-${ROOT}/dist}"
REBUILD_GHOSTTY=0
OPEN_AFTER_BUILD=0

usage() {
    cat <<'EOF'
一键生成可在本机运行的 Breath Universal .app 和 .zip。

用法：
  ./scripts/build-app.sh [选项]

选项：
  --version <x.y.z>    设置应用版本，默认 0.0.0
  --output <目录>      设置输出目录，默认 ./dist
  --rebuild-ghostty    即使本地已有 GhosttyKit，也重新构建
  --open               打包完成后打开 Breath
  -h, --help           显示帮助

环境变量：
  VERSION              与 --version 相同
  OUTPUT_DIR           与 --output 相同
  BUILD_NUMBER         覆盖自动生成的构建号
EOF
}

fail() {
    print -u2 "错误：$1"
    exit 2
}

while (( $# > 0 )); do
    case "$1" in
        --version)
            (( $# >= 2 )) || fail "--version 需要一个 x.y.z 参数"
            VERSION_VALUE="$2"
            shift 2
            ;;
        --output)
            (( $# >= 2 )) || fail "--output 需要一个目录参数"
            OUTPUT_VALUE="$2"
            shift 2
            ;;
        --rebuild-ghostty)
            REBUILD_GHOSTTY=1
            shift
            ;;
        --open)
            OPEN_AFTER_BUILD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "未知参数：$1"
            ;;
    esac
done

if [[ ! "$VERSION_VALUE" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    fail "版本号必须使用 x.y.z 格式，例如 0.1.0"
fi

if [[ "$OUTPUT_VALUE" != /* ]]; then
    OUTPUT_VALUE="${ROOT}/${OUTPUT_VALUE}"
fi

GHOSTTY_FRAMEWORK="${ROOT}/Vendor/GhosttyKit.xcframework"
if (( REBUILD_GHOSTTY )) || [[ ! -d "$GHOSTTY_FRAMEWORK" ]]; then
    print "正在构建固定版本的 GhosttyKit…"
    "${ROOT}/scripts/build-libghostty.sh"
else
    print "复用现有 GhosttyKit：${GHOSTTY_FRAMEWORK}"
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
    BUILD_NUMBER_VALUE="$BUILD_NUMBER"
elif git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BUILD_NUMBER_VALUE=$(git -C "$ROOT" rev-list --count HEAD)
else
    BUILD_NUMBER_VALUE=1
fi

print "正在打包 Breath ${VERSION_VALUE}…"
env \
    VERSION="$VERSION_VALUE" \
    BUILD_NUMBER="$BUILD_NUMBER_VALUE" \
    OUTPUT_DIR="$OUTPUT_VALUE" \
    OVERWRITE=1 \
    LOCAL_BUILD=1 \
    SPARKLE_FEED_URL="https://invalid.example/appcast.xml" \
    SPARKLE_PUBLIC_KEY="local-build" \
    CODE_SIGN_IDENTITY="" \
    NOTARIZE=0 \
    "${ROOT}/scripts/package-app.sh"

APP="${OUTPUT_VALUE}/Breath-${VERSION_VALUE}.app"
ARCHIVE="${OUTPUT_VALUE}/Breath-${VERSION_VALUE}.zip"

print
print "打包完成："
print "  ${APP}"
print "  ${ARCHIVE}"

if (( OPEN_AFTER_BUILD )); then
    open "$APP"
fi
