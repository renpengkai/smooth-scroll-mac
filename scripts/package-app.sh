#!/usr/bin/env bash
# 构建 release 二进制并组装成 dist/SmoothScroll.app + zip。需要在装有 Xcode 的 macOS 上运行 (即 GitHub Actions)。
#   VERSION  CFBundleShortVersionString, 默认 0.1.0
#   BUILD    CFBundleVersion, 默认 1
set -euo pipefail

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
ARCH="arm64"
NAME="SmoothScroll"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --arch "$ARCH"
BIN_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"

DIST="$ROOT/dist"
APP="$DIST/$NAME.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN_DIR/$NAME" "$APP/Contents/MacOS/$NAME"
# 去掉调试符号和本地符号, 可执行文件只保留动态链接需要的符号
strip -S -x "$APP/Contents/MacOS/$NAME"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    "$ROOT/Packaging/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ad-hoc 签名: Apple Silicon 要求可执行文件至少有签名才能运行
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

ZIP="$DIST/$NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "== size =="
du -sh "$APP"
ls -l "$APP/Contents/MacOS/$NAME" "$ZIP"
file "$APP/Contents/MacOS/$NAME"
# sdk 决定是否启用液态玻璃 (需 26+), minos 决定最低可运行系统
vtool -show-build "$APP/Contents/MacOS/$NAME"
