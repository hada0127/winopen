#!/bin/bash
# 빌드 후 ~/Applications/윈도우경로열기.app 에 설치하고 다시 띄운다.
set -euo pipefail
cd "$(dirname "$0")"
NAME="윈도우경로열기"
APP="/Applications/$NAME.app"
BUILD=build/$NAME.app

rm -rf build && mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"
swiftc -O -target "$(uname -m)-apple-macosx13.0" -o "$BUILD/Contents/MacOS/WinOpen" main.swift -framework AppKit -framework ServiceManagement
cp winopen "$BUILD/Contents/Resources/winopen" && chmod +x "$BUILD/Contents/Resources/winopen"
cat > "$BUILD/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.hada0127.winopen</string>
  <key>CFBundleExecutable</key><string>WinOpen</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>파인더 새 탭으로 폴더를 열고, 지금 열린 폴더·선택 항목의 경로를 읽어 즐겨찾기에 넣거나 윈도우 경로로 복사합니다.</string>
</dict></plist>
EOF
# 서명: 키체인에 Apple Development 인증서가 있으면 그걸로(다시 빌드해도 손쉬운 사용·자동화 권한이 유지된다).
# 없으면 ad-hoc — 빌드할 때마다 권한을 다시 줘야 한다. WINOPEN_SIGN_ID 로 직접 지정 가능.
SIGN_ID=${WINOPEN_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')}
codesign --force --sign "${SIGN_ID:--}" "$BUILD"
echo "서명: ${SIGN_ID:-ad-hoc}"

pkill -x WinOpen 2>/dev/null || true
rm -rf "$APP" && cp -R "$BUILD" "$APP"
rm -rf "$HOME/Applications/$NAME.app"   # 예전 설치 위치 정리
if [ -d "$HOME/bin" ]; then
  cp winopen "$HOME/bin/winopen" && chmod +x "$HOME/bin/winopen" || echo "경고: ~/bin/winopen 복사 실패" >&2
fi
open "$APP"
echo "설치: $APP"
