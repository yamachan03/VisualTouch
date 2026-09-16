#!/bin/bash
# Developer ID で署名 → 公証 → ステープル → 配布用 zip を作る
#
# 初回だけ、公証用の資格情報をキーチェーンに保存しておく:
#   xcrun notarytool store-credentials VisualTouch \
#       --apple-id <Apple ID のメール> --team-id 7JSPUB92B6 --password <App 用パスワード>
#   （App 用パスワードは https://account.apple.com → サインインとセキュリティ → App 用パスワード で発行）
#
# 署名だけ試したいとき: SKIP_NOTARIZE=1 ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${IDENTITY:-Developer ID Application: Yoichi Yamane (7JSPUB92B6)}"
PROFILE="${NOTARY_PROFILE:-VisualTouch}"
APP="VisualTouch.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
ZIP="VisualTouch-${VERSION}.zip"

./build.sh

echo "Developer ID で署名中..."
# 内側の実行ファイルから順に署名する。--options runtime は公証の必須条件
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/MacOS/vtouch"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

pack() {
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
}
pack

if [ "${SKIP_NOTARIZE:-}" = "1" ]; then
    echo "公証をスキップしました（署名のみ）: $ZIP"
    exit 0
fi

echo "公証を申請中（数分かかります）..."
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "公証チケットをアプリに添付中..."
xcrun stapler staple "$APP"
pack   # ステープル済みの状態で zip を作り直す

echo "Gatekeeper の判定:"
spctl -a -vv -t exec "$APP"
echo "配布用: $(pwd)/$ZIP"
