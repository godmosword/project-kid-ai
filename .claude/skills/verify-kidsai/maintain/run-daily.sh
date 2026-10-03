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

OSASCRIPT="${KIDSAI_OSASCRIPT:-/usr/bin/osascript}"  # 測試時換成 /usr/bin/true，不跳通知
LOCK_STALE_MINUTES=180  # 和 maintain run 的 LOCK_STALE（3 小時）一致

fail() {
  echo "$(date '+%F %T') bootstrap 失敗：$1" >&2
  "$OSASCRIPT" -e "display notification \"blocked：bootstrap $1\" with title \"KidsAI 每日維護\"" >/dev/null 2>&1
  exit 5
}

mkdir -p "$ROOT" || fail "建不了 $ROOT"
# 鎖裡的 PID 還活著、而且真的是每日維護（命令列有 control-kidsai）：不要動它的 clone。
#   3 小時內＝還在跑，跳過；超過 3 小時＝卡住了（agent 90 分鐘就逾時），通知人來處理，也不動 clone。
# PID 活著但不是每日維護：重開機後 PID 被別的程序拿去用，當成舊鎖，交給 maintain run 回收並補紀錄。
if [ -f "$ROOT/.lock/owner.json" ]; then
  pid=$(grep -o '"pid": *[0-9]*' "$ROOT/.lock/owner.json" | grep -o '[0-9]*$')
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q 'control-kidsai'; then
    if [ -z "$(find "$ROOT/.lock/owner.json" -mmin +"$LOCK_STALE_MINUTES" 2>/dev/null)" ]; then
      echo "$(date '+%F %T') skip：上一次每日維護還在跑（PID ${pid}）"
      exit 0
    fi
    fail "上一次每日維護卡住超過 3 小時（PID ${pid}），請手動結束它"
  fi
fi
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
