#!/bin/bash
# 릴리스 ZIP 을 만든다: 유니버설 · ad-hoc 서명(개인 인증서 정보가 들어가지 않게) → dist/
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
WINOPEN_BUILD_ONLY=1 WINOPEN_UNIVERSAL=1 WINOPEN_SIGN_ID=- ./build.sh
rm -rf dist && mkdir dist
ZIP="dist/WinOpen-$VERSION-universal.zip"
ditto -c -k --keepParent "build/윈도우경로열기.app" "$ZIP"
cp winopen "dist/winopen"
(cd dist && shasum -a 256 "$(basename "$ZIP")" winopen > SHA256SUMS)
cat dist/SHA256SUMS
