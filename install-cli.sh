#!/bin/bash
# アプリに同梱した vtouch を /usr/local/bin にコピーする
set -euo pipefail
cd "$(dirname "$0")"

SRC="$(pwd)/VisualTouch.app/Contents/MacOS/vtouch"
DEST="/usr/local/bin/vtouch"

[ -x "$SRC" ] || { echo "vtouch がありません。先に ./build.sh を実行してください" >&2; exit 1; }

if mkdir -p /usr/local/bin 2>/dev/null && cp "$SRC" "$DEST" 2>/dev/null; then
    :
else
    echo "/usr/local/bin への書き込みに管理者権限が必要です"
    sudo mkdir -p /usr/local/bin
    sudo cp "$SRC" "$DEST"
fi
chmod 755 "$DEST" 2>/dev/null || sudo chmod 755 "$DEST"
echo "インストール完了: $DEST"
"$DEST" --version
