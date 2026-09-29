#!/bin/bash
# KidsAI 每日維護的 bootstrap：launchd 每天 03:17 執行。
# control-kidsai maintain install 會把本檔複製到 ~/kidsai-maintain/bin/，並在 plist 設好 PATH、KIDSAI_PYTHON、KIDSAI_MAINTAIN_REF。
# 只做三件事：確保專用 clone 存在、切到要維護的版本、交給 clone 裡的 control-kidsai maintain run（鎖、防護、PR 都在那裡）。
set -u

ROOT="$HOME/kidsai-maintain"
CLONE="$ROOT/project-kid-ai"
REPO_URL="https://github.com/godmosword/project-kid-ai.git"
REF="${KIDSAI_MAINTAIN_REF:-origin/main}"
PYTHON="${KIDSAI_PYTHON:-/usr/bin/python3}"

fail() {
  echo "$(date '+%F %T') bootstrap 失敗：$1" >&2
  /usr/bin/osascript -e "display notification \"blocked：bootstrap $1\" with title \"KidsAI 每日維護\"" >/dev/null 2>&1
  exit 5
}

mkdir -p "$ROOT" || fail "建不了 $ROOT"
if [ ! -d "$CLONE/.git" ]; then
  git clone -q "$REPO_URL" "$CLONE" || fail "git clone"
fi
git -C "$CLONE" fetch -q origin || fail "git fetch"
git -C "$CLONE" checkout -q -f --detach "$REF" || fail "切換到 $REF"

ARGS=(maintain run --ref "$REF")
if [ "${KIDSAI_MAINTAIN_NO_PUSH:-}" = "1" ]; then
  ARGS+=(--no-push)
fi
# caffeinate：跑的期間 Mac 不閒置睡眠（模擬器睡著會讓 UI 測試逾時）
exec /usr/bin/caffeinate -i "$PYTHON" "$CLONE/.claude/skills/verify-kidsai/control-kidsai" "${ARGS[@]}"
