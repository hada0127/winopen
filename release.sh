#!/bin/bash
# 릴리스 ZIP 을 만든다: 유니버설 → Developer ID 서명 → Apple 공증 → 스테이플 → dist/
#   WINOPEN_TEAM_ID=<팀 ID> WINOPEN_SIGN_ID="Apple Development: …" ./release.sh
# Xcode 에 그 팀의 계정이 로그인돼 있어야 한다(Developer ID 서명·공증을 Xcode 가 처리).
# WINOPEN_NOTARIZE=0 이면 공증 없이 ad-hoc 서명 ZIP 만 만든다.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
NAME="윈도우경로열기"
APPN="$NAME.app"
rm -rf dist && mkdir dist
ZIP="dist/WinOpen-$VERSION-universal.zip"

if [ "${WINOPEN_NOTARIZE:-1}" = 0 ]; then
  WINOPEN_BUILD_ONLY=1 WINOPEN_UNIVERSAL=1 WINOPEN_SIGN_ID=- ./build.sh
  OUT="build/$APPN"
else
  : "${WINOPEN_TEAM_ID:?WINOPEN_TEAM_ID 가 필요해}" "${WINOPEN_SIGN_ID:?WINOPEN_SIGN_ID 가 필요해}"
  WINOPEN_BUILD_ONLY=1 WINOPEN_UNIVERSAL=1 ./build.sh
  # 공증 조건: 하드닝 런타임 + 보안 타임스탬프
  codesign --force --options runtime --timestamp --entitlements entitlements.plist \
    --sign "$WINOPEN_SIGN_ID" "build/$APPN"

  ARCHIVE=build/WinOpen.xcarchive
  rm -rf "$ARCHIVE" build/export build/notarized
  mkdir -p "$ARCHIVE/Products/Applications"
  cp -R "build/$APPN" "$ARCHIVE/Products/Applications/"
  cat > "$ARCHIVE/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ApplicationProperties</key><dict>
    <key>ApplicationPath</key><string>Applications/$APPN</string>
    <key>Architectures</key><array><string>arm64</string><string>x86_64</string></array>
    <key>CFBundleIdentifier</key><string>io.github.hada0127.winopen</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>SigningIdentity</key><string>$WINOPEN_SIGN_ID</string>
    <key>Team</key><string>$WINOPEN_TEAM_ID</string>
  </dict>
  <key>ArchiveVersion</key><integer>2</integer>
  <key>CreationDate</key><date>$(date -u +%Y-%m-%dT%H:%M:%SZ)</date>
  <key>Name</key><string>WinOpen</string>
  <key>SchemeName</key><string>WinOpen</string>
</dict></plist>
EOF
  cat > build/export.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$WINOPEN_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>upload</string>
</dict></plist>
EOF
  # Developer ID 로 다시 서명해 공증에 올린다
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/export.plist \
    -exportPath build/export -allowProvisioningUpdates
  # 공증이 끝날 때까지 기다렸다가 스테이플된 앱을 받는다(최대 약 20분)
  for _ in $(seq 1 80); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath build/notarized >/dev/null 2>&1; then break; fi
    sleep 15
  done
  OUT="build/notarized/$APPN"
  [ -d "$OUT" ] || { echo "공증 결과를 받지 못했어" >&2; exit 1; }
  xcrun stapler validate "$OUT"
  spctl -a -vv -t exec "$OUT"
fi

ditto -c -k --keepParent "$OUT" "$ZIP"
cp winopen "dist/winopen"
(cd dist && shasum -a 256 "$(basename "$ZIP")" winopen > SHA256SUMS)
cat dist/SHA256SUMS
