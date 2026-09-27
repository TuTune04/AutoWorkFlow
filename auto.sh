#!/bin/bash
# auto.sh — Claude lên plan & review, coding agent (mặc định Antigravity CLI `agy`) viết code.
#
# Cách dùng:
#   ./auto.sh "mô tả dự án"   chưa có PLAN.md: Claude viết plan rồi chạy
#   ./auto.sh                 đã có PLAN.md: chạy (hoặc chạy tiếp) theo plan
#   ./auto.sh --check         chỉ kiểm tra công cụ, PLAN.md, git và git hook rồi thoát
#   ./auto.sh --new-branch    ép tạo branch auto/* mới thay vì làm tiếp branch auto/* hiện tại
#   ./auto.sh --preflight     chỉ kiểm tra quyền của agent (đăng nhập, từng lệnh, ghi file) và git hook rồi thoát
#   ./auto.sh --adopt N       nhận Task N đã làm/kiểm tra bằng tay: chạy TEST_CMD rồi commit thay đổi (hoặc
#                             đổi tên commit HEAD) thành "Task N: <tiêu đề>" để lần chạy sau bỏ qua
#
# Biến cấu hình: đặt trong .autowf.env ở gốc repo, hoặc qua env (env được ưu tiên hơn file):
#   CODER=agy              coding agent: agy | gemini | ...
#   FALLBACK_CODER=        agent dự phòng khi CODER lỗi đăng nhập/quyền (ví dụ: gemini)
#   PLAN_MODEL=opus        model Claude viết PLAN.md
#   REVIEW_MODEL=sonnet    model Claude review
#   MAX_TRIES=3            số vòng sửa tối đa mỗi task
#   MAX_WAIT_HOURS=6       tổng thời gian tối đa chờ khi Claude chạm giới hạn sử dụng
#   AGY_ALLOWED_CMDS=...   danh sách lệnh nhắc agy dùng (phải khớp allowlist trong ~/.gemini/config/config.json)
#   AGY_ALLOW_MCP=         MCP tool agy được dùng, dạng "server/tool" (ví dụ "flutter_dart-mcp-server/dtd");
#                          rỗng = nhắc agent không dùng MCP, chỉ dùng lệnh CLI
# Ví dụ:
#   REVIEW_MODEL=haiku ./auto.sh
#   CODER=gemini ./auto.sh
#   FALLBACK_CODER=gemini MAX_TRIES=5 ./auto.sh
#
# Chạy tiếp: task đã có commit "Task N" / "Task N: ..." trên branch hiện tại được bỏ qua.
# Có .venv/bin và chưa kích hoạt venv nào thì tự thêm .venv/bin vào đầu PATH.
# Preflight quyền tự chạy trước vòng lặp task; bỏ qua nếu CODER, AGY_ALLOWED_CMDS, TEST_CMD và
# ~/.gemini/config/config.json không đổi kể từ lần đạt trước (.auto-logs/preflight.ok).
# Trước vòng lặp task (và trong --preflight) luôn thử commit trong worktree tạm để chắc git hook
# (pre-commit, husky...) qua được với PATH hiện tại. Task PASS mà hook từ chối commit (sau khi đã
# add lại file hook tự sửa) thì output hook vào REVIEW.md và tính là một vòng FAIL.
# Mã thoát: 1 lỗi/task FAIL, 2 cầu dao, 3 quá MAX_WAIT_HOURS, 4 không review được,
# 5 preflight (quyền hoặc git hook) chưa đạt.
# Mỗi lần chạy ghi tiến độ vào .auto-logs/run.log và tóm tắt vào .auto-logs/summary.md.

set -euo pipefail

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

NEW_BRANCH=0
CHECK_ONLY=0
PREFLIGHT_ONLY=0
ADOPT=""
DESC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --new-branch) NEW_BRANCH=1 ;;
    --check)      CHECK_ONLY=1 ;;
    --preflight)  PREFLIGHT_ONLY=1 ;;
    --adopt=*)    ADOPT="${1#--adopt=}"; [ -n "$ADOPT" ] || ADOPT=x ;;
    --adopt)      ADOPT="${2:-x}"; if [ $# -gt 1 ]; then shift; fi ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "❌ Cờ không hợp lệ: $1"; usage; exit 1 ;;
    *)            DESC="${DESC:+$DESC }$1" ;;
  esac
  shift
done

notify()   { osascript -e "display notification \"$1\" with title \"auto.sh\"" 2>/dev/null || true; }
need()     { command -v "$1" >/dev/null || { echo "❌ Thiếu '$1'. $2"; exit 1; }; }
fmt_time() { date -r "$1" '+%H:%M %d/%m' 2>/dev/null || date -d "@$1" '+%H:%M %d/%m'; }
fmt_dur()  { printf '%dh%02dm%02ds' $(($1 / 3600)) $(($1 % 3600 / 60)) $(($1 % 60)); }

need git "Cài: xcode-select --install"
# Luôn làm việc ở gốc repo (nếu đang ở trong một repo)
if ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then cd "$ROOT"; fi
# Tự dùng .venv của repo: hook `language: system` và TEST_CMD gọi ruff/mypy/pytest... từ PATH
if [ -d .venv/bin ] && [ -z "${VIRTUAL_ENV:-}" ]; then
  case ":$PATH:" in
    *":$PWD/.venv/bin:"*) ;;
    *) export PATH="$PWD/.venv/bin:$PATH" VIRTUAL_ENV="$PWD/.venv"
       echo "🐍 Tự kích hoạt .venv (thêm $PWD/.venv/bin vào đầu PATH)" ;;
  esac
fi

# ---- Cấu hình: mặc định < .autowf.env < biến môi trường ----
CONFIG_VARS="CODER FALLBACK_CODER PLAN_MODEL REVIEW_MODEL MAX_TRIES MAX_WAIT_HOURS AGY_ALLOWED_CMDS AGY_ALLOW_MCP"
if [ -f .autowf.env ]; then
  ENV_OVERRIDES=""
  for v in $CONFIG_VARS; do
    if [ -n "${!v+x}" ]; then ENV_OVERRIDES+="$v=$(printf '%q' "${!v}")"$'\n'; fi
  done
  # shellcheck disable=SC1091
  . ./.autowf.env
  eval "$ENV_OVERRIDES"
fi
CODER="${CODER:-agy}"
FALLBACK_CODER="${FALLBACK_CODER:-}"
PLAN_MODEL="${PLAN_MODEL:-opus}"
REVIEW_MODEL="${REVIEW_MODEL:-sonnet}"
MAX_TRIES="${MAX_TRIES:-3}"
MAX_WAIT_HOURS="${MAX_WAIT_HOURS:-6}"
AGY_ALLOWED_CMDS="${AGY_ALLOWED_CMDS:-git, python3, .venv/bin/python, .venv/bin/pip, ls, mkdir, which}"
AGY_ALLOW_MCP="${AGY_ALLOW_MCP:-}"
# Chỉ dùng khi test: thay thời gian chờ hạn mức bằng số giây này
AUTOWF_TEST_WAIT_SECS="${AUTOWF_TEST_WAIT_SECS:-}"
AGY_CONFIG="${AGY_CONFIG:-$HOME/.gemini/config/config.json}"
AGY_CONV_DIR="${AGY_CONV_DIR:-$HOME/.gemini/antigravity-cli/conversations}"

LOG_DIR=".auto-logs"
LIMIT_RE='usage limit|limit reached|rate limit|resets'
CODER_AUTH_RE='auto-denied|cannot prompt|permission denied|not logged in|login required|please (log|sign) ?in|auth method|unauthenticated|authentication (failed|required)'
DIFF_EXCLUDES=(
  ':(exclude,glob)**/.venv/**' ':(exclude,glob)**/node_modules/**' ':(exclude,glob)**/__pycache__/**'
  ':(exclude,glob)**/.pytest_cache/**' ':(exclude,glob)**/dist/**' ':(exclude,glob)**/build/**'
  ':(exclude,glob)**/*.lock' ':(exclude,glob)**/package-lock.json' ':(exclude,glob)**/pnpm-lock.yaml'
  ':(exclude,glob)**/go.sum' ':(exclude,glob)**/*.pyc'
)

# ---- PLAN.md ----
# Đặt TEST_CMD, TOTAL. Trả về 1 và đặt PLAN_ERR nếu PLAN.md không hợp lệ.
load_plan() {
  local nums expect
  PLAN_ERR=""
  [ -f PLAN.md ] || { PLAN_ERR="chưa có PLAN.md"; return 1; }
  TEST_CMD=$(grep -m1 '^TEST_CMD:' PLAN.md | sed 's/^TEST_CMD:[[:space:]]*//' || true)
  [ -n "$TEST_CMD" ] || { PLAN_ERR="thiếu dòng 'TEST_CMD: <lệnh>'"; return 1; }
  nums=$(grep -oE '^## Task [0-9]+' PLAN.md | awk '{ printf "%s ", $3 }' || true)
  TOTAL=$(printf '%s' "$nums" | wc -w | tr -d ' ')
  [ "$TOTAL" -gt 0 ] || { PLAN_ERR="không có heading '## Task N'"; return 1; }
  expect=$(seq 1 "$TOTAL" | awk '{ printf "%s ", $1 }')
  [ "$nums" = "$expect" ] || { PLAN_ERR="heading '## Task N' không liên tục từ 1 (thấy: $nums)"; return 1; }
}

# In phần tổng quan của PLAN.md (trước '## Task 1') và đúng phần của Task N.
# In rỗng nếu không tìm thấy heading của Task N.
plan_excerpt() {
  awk -v n="$1" '
    /^## Task [0-9]+/ { intro = 0; match($0, /^## Task [0-9]+/); cur = substr($0, 9, RLENGTH - 8) + 0 }
    NR == 1 { intro = 1 }
    intro { head = head $0 "\n"; next }
    cur == n { body = body $0 "\n" }
    END { if (body != "") printf "%s%s", head, body }
  ' PLAN.md
}

# Commit message của Task N: "Task N: <tiêu đề trong PLAN.md>" (hoặc "Task N" nếu heading không có tiêu đề)
task_msg() {
  local t
  t=$(grep -m1 -E "^## Task $1:" PLAN.md 2>/dev/null | sed -E "s/^## Task $1:[[:space:]]*//; s/[[:space:]]+$//" || true)
  if [ -n "$t" ]; then printf 'Task %s: %s' "$1" "$t"; else printf 'Task %s' "$1"; fi
}
# Task N đã có commit sau lần sửa PLAN.md gần nhất (DONE_SUBJECTS); nhận cả "Task N" lẫn "Task N: ..."
task_done() { grep -qE "^Task $1(:|\$)" <<< "$DONE_SUBJECTS"; }
load_done_subjects() {
  PLAN_COMMIT=$(git log -1 --format=%H -- PLAN.md)
  DONE_SUBJECTS=""
  [ -z "$PLAN_COMMIT" ] || DONE_SUBJECTS=$(git log --format=%s "$PLAN_COMMIT"..HEAD)
}

parse_reset_time() {  # <file output> <now> → in epoch lúc reset; trả về 1 nếu không đọc được
  local t h m since target
  t=$(grep -oE '\|[0-9]{10}' "$1" | head -n1 | tr -d '|' || true)
  if [ -n "$t" ] && [ "$t" -gt "$2" ]; then echo "$t"; return 0; fi
  t=$(grep -oiE 'resets( at)? [0-9]{1,2}(:[0-9]{2})? ?(am|pm)?' "$1" | head -n1 | tr 'A-Z' 'a-z' || true)
  [ -n "$t" ] || return 1
  t=$(printf '%s' "$t" | sed -E 's/^resets( at)? //')
  h=$(printf '%s' "$t" | sed -E 's/^([0-9]+).*/\1/')
  m=$(printf '%s' "$t" | sed -nE 's/^[0-9]+:([0-9]{2}).*/\1/p')
  h=$((10#$h)); m=$((10#${m:-0}))
  case "$t" in
    *pm) [ "$h" -lt 12 ] && h=$((h + 12)) ;;
    *am) [ "$h" -eq 12 ] && h=0 ;;
  esac
  [ "$h" -lt 24 ] && [ "$m" -lt 60 ] || return 1
  since=$((10#$(date +%H) * 3600 + 10#$(date +%M) * 60 + 10#$(date +%S)))
  target=$(($2 - since + h * 3600 + m * 60))
  [ "$target" -gt "$2" ] || target=$((target + 86400))
  echo "$target"
}

# ---- Coding agent ----
AGY_RULES="Command rules (mandatory; any other command is auto-denied and ends your run): only use $AGY_ALLOWED_CMDS; run exactly ONE command per call, never chain commands with ; && || | or \$(...); do not use cd, rm, cat or echo. Create/edit files with the file-writing tool and read files with the file-reading tool."
if [ -z "$AGY_ALLOW_MCP" ]; then
  AGY_RULES+=" Do not use MCP tools; use CLI commands only (e.g. flutter test, flutter analyze, dart format)."
else
  AGY_RULES+=" The only MCP tools you may use are: $AGY_ALLOW_MCP. For everything else use CLI commands."
fi
CODER_RC=0

# Agent chỉ được sửa file; script tự test, review và commit "Task N".
GIT_RULE="Do not run git commands that change the index, history or branch (git add, commit, stash, reset, checkout, switch, restore, rebase, merge, cherry-pick, push); the script stages and commits for you. Read-only git commands (status, diff, log, show) are fine."

snapshot_git() {  # ghi lại trạng thái git trước khi agent chạy
  HEAD_BEFORE=$(git rev-parse HEAD)
  STASH_BEFORE=$(git stash list | wc -l | tr -d ' ')
}

undo_agent_git() {  # <file log> — agent tự commit: đưa thay đổi về cây làm việc; đổi branch/viết lại lịch sử/stash: dừng
  local cur stash_now subjects
  cur=$(git symbolic-ref -q --short HEAD || echo "(detached HEAD)")
  if [ "$cur" != "$BRANCH" ]; then
    T_END[N]=$(date +%s)
    stop 2 "Agent đã rời branch $BRANCH (đang ở $cur) ở Task $N lần $TRY" \
      "Log: $1
Cách xử lý: xem git status / git log, quay về bằng: git checkout $BRANCH (commit hoặc stash thay đổi dở nếu có), rồi chạy lại."
  fi
  if [ "$(git rev-parse HEAD)" != "$HEAD_BEFORE" ]; then
    if git merge-base --is-ancestor "$HEAD_BEFORE" HEAD; then
      subjects=$(git log --format='%h %s' "$HEAD_BEFORE..HEAD" | tr '\n' ';')
      echo "[auto.sh] agent tự commit ($subjects) → git reset --soft $HEAD_BEFORE để test/review/commit như thường" >> "$1"
      echo "⚠️  Agent tự commit ở Task $N ($subjects) — đưa thay đổi về lại cây làm việc"
      git reset -q --soft "$HEAD_BEFORE"
    else
      T_END[N]=$(date +%s)
      stop 2 "Agent đã viết lại lịch sử git ở Task $N lần $TRY (HEAD trước đó $HEAD_BEFORE không còn trên branch)" \
        "Log: $1
Cách xử lý: tìm lại commit cũ bằng git reflog, đưa branch $BRANCH về đúng chỗ rồi chạy lại."
    fi
  fi
  stash_now=$(git stash list | wc -l | tr -d ' ')
  if [ "$stash_now" -gt "$STASH_BEFORE" ]; then
    T_END[N]=$(date +%s)
    stop 2 "Agent đã git stash thay đổi ở Task $N lần $TRY" \
      "Log: $1
Cách xử lý: git stash list; lấy lại bằng git stash pop (nếu đúng là thay đổi của Task $N), rồi chạy lại."
  fi
}

run_coder() {  # <agent> <prompt> <file log>; mã thoát của agent lưu ở CODER_RC
  CODER_RC=0
  touch "$LOG_DIR/.coder-start"
  case "$1" in
    agy)    agy -p "$2 $AGY_RULES" ;;
    gemini) gemini -p "$2" --yolo ;;
    *)      "$1" -p "$2" ;;
  esac < /dev/null > "$3" 2>&1 || CODER_RC=$?
}

ask_coder() {  # <prompt> <file log> — gọi CODER với đúng prompt này (không kèm quy tắc), dùng cho preflight
  CODER_RC=0
  touch "$LOG_DIR/.coder-start"
  case "$CODER" in
    gemini) gemini -p "$1" --yolo ;;
    *)      "$CODER" -p "$1" ;;
  esac < /dev/null > "$2" 2>&1 || CODER_RC=$?
}

allowed_cmds() { printf '%s\n' "$AGY_ALLOWED_CMDS" | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | { grep -v '^$' || true; }; }
first_exe()    { local w; for w in $1; do case "$w" in *=*) ;; *) echo "$w"; return 0 ;; esac; done; }
# Quy tắc hẹp cho agy: chỉ lệnh này, không cho nối lệnh khác bằng ; & | ` $
cmd_rule()     { printf 'command(regex:^%s( [^;&|`$]*)?$)' "$(printf '%s' "$1" | sed 's/[].[\*^$()+?{}|]/\\&/g')"; }

# Lệnh gần nhất agy chạy (từ conversation mới hơn lần gọi agent cuối), rỗng nếu không tìm được
agy_last_command() {
  local db
  command -v sqlite3 >/dev/null || return 0
  db=$(agy_new_conversation)
  [ -n "$db" ] || return 0
  sqlite3 "$db" "select step_payload from steps order by idx desc limit 4" 2>/dev/null | strings \
    | grep -oE '"CommandLine":"[^"]*"' | head -n1 | sed -E 's/^"CommandLine":"//; s/"$//; s/\\u003e/>/g; s/\\u003c/</g; s/\\u0026/\&/g' || true
}

# Conversation agy mới nhất được ghi sau lần gọi agent cuối, rỗng nếu không có
agy_new_conversation() {
  local db
  db=$(find "$AGY_CONV_DIR" -name '*.db' -newer "$LOG_DIR/.coder-start" 2>/dev/null | head -n1 || true)
  [ -z "$db" ] || ls -t "$AGY_CONV_DIR"/*.db 2>/dev/null | head -n1 || true
}

mcp_items() { printf '%s\n' "$AGY_ALLOW_MCP" | tr ', ' '\n\n' | { grep -v '^$' || true; }; }

# "server/tool" của lời gọi MCP bị từ chối: tìm trong log (mcp(...) hoặc cặp server/tool),
# không có thì tra conversation agy mới nhất; rỗng nếu không tìm được
mcp_denied_target() {
  local f="$1" t srv tl db payload
  t=$(grep -oE 'mcp\([^)<>[:space:]]+/[^)<>[:space:]]+\)' "$f" 2>/dev/null | head -n1 | sed -E 's/^mcp\((.*)\)$/\1/' || true)
  if [ -z "$t" ]; then  # "... tool dtd on server flutter_dart-mcp-server"
    t=$(grep -oiE 'tool[ :=]+"?[A-Za-z0-9_.-]+"? (on|from|of) (the )?server[ :=]+"?[A-Za-z0-9_.-]+' "$f" 2>/dev/null | head -n1 \
      | sed -E 's/^[Tt][Oo][Oo][Ll][ :=]+"?([A-Za-z0-9_.-]+)"? [A-Za-z]+ ([Tt][Hh][Ee] )?[Ss][Ee][Rr][Vv][Ee][Rr][ :=]+"?([A-Za-z0-9_.-]+)$/\3\/\1/' || true)
  fi
  if [ -z "$t" ]; then  # "MCP flutter_dart-mcp-server/dtd"
    t=$(grep -oiE '(^|[[:space:]])mcp[[:space:]:]+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$f" 2>/dev/null | head -n1 | sed -E 's/^.*[[:space:]:]//' || true)
  fi
  if [ -z "$t" ]; then
    srv=$(grep -oiE '"?server_?name"?[:=] ?"?[A-Za-z0-9_.-]+' "$f" 2>/dev/null | head -n1 | sed -E 's/.*[:=] ?"?//' || true)
    tl=$(grep -oiE '"?tool_?name"?[:=] ?"?[A-Za-z0-9_.-]+' "$f" 2>/dev/null | head -n1 | sed -E 's/.*[:=] ?"?//' || true)
    [ -z "$srv" ] || [ -z "$tl" ] || t="$srv/$tl"
  fi
  if [ -z "$t" ] && command -v sqlite3 >/dev/null; then
    db=$(agy_new_conversation)
    if [ -n "$db" ]; then
      payload=$(sqlite3 "$db" "select step_payload from steps order by idx desc limit 4" 2>/dev/null | strings || true)
      srv=$(printf '%s\n' "$payload" | grep -oE '"ServerName":"[^"]*"' | head -n1 | sed -E 's/^"ServerName":"//; s/"$//' || true)
      tl=$(printf '%s\n' "$payload" | grep -oE '"ToolName":"[^"]*"' | head -n1 | sed -E 's/^"ToolName":"//; s/"$//' || true)
      [ -z "$srv" ] || [ -z "$tl" ] || t="$srv/$tl"
    fi
  fi
  printf '%s' "$t"
}

DIAG_AUTH_RE='not logged in|login required|please (log|sign) ?in|auth method|unauthenticated|authentication (failed|required)|reauthenticate|token (has )?expired|invalid_grant'
DIAG_PERM_RE='auto-denied|cannot prompt|permission denied|not allowed by|denied by (policy|permission)|soft-denying'
DIAG_MCP_RE='"mcp" permission|CallMcpTool|mcp tool|mcp\([^)<>[:space:]]+/'
DIAG_QUOTA_RE='quota|resource.?exhausted|too many requests|(status|code|error) 429|rate.?limit|usage limit|limit reached'
DIAG_TIMEOUT_RE='timed? ?out|deadline exceeded'
DIAG_CRASH_RE='panic:|segmentation fault|fatal error|traceback \(most recent|core dumped|unexpected error'

# diagnose_agent_log <file log> [exit code] → in "LOẠI|dòng bằng chứng"
# LOẠI: AUTH | PERMISSION | QUOTA | TIMEOUT | CRASH | NO_ACTION | UNKNOWN
diagnose_agent_log() {
  local f="$1" rc="${2:-0}" pair type re line
  for pair in "AUTH:$DIAG_AUTH_RE" "PERMISSION:$DIAG_PERM_RE" "QUOTA:$DIAG_QUOTA_RE" "TIMEOUT:$DIAG_TIMEOUT_RE" "CRASH:$DIAG_CRASH_RE"; do
    type="${pair%%:*}"; re="${pair#*:}"
    line=$(grep -iE -m1 "$re" "$f" 2>/dev/null | cut -c1-240 || true)
    if [ -n "$line" ]; then echo "$type|$line"; return 0; fi
  done
  line=$({ grep -v '^[[:space:]]*$' "$f" 2>/dev/null || true; } | tail -n1 | cut -c1-240)
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 142 ]; then echo "TIMEOUT|exit code $rc${line:+ — $line}"
  elif [ "$rc" -ne 0 ]; then echo "CRASH|exit code $rc${line:+ — $line}"
  elif [ -n "$line" ]; then echo "NO_ACTION|$line"
  else echo "UNKNOWN|"
  fi
}

# diag_advice <LOẠI> <bằng chứng> <file log> → cách xử lý cụ thể
diag_advice() {
  local type="$1" ev="$2" log="$3" tool cmd now at target
  case "$type" in
    AUTH) echo "Đăng nhập lại: mở Terminal, chạy \`$ACTIVE_CODER\` và làm theo hướng dẫn đăng nhập, rồi chạy lại auto.sh." ;;
    PERMISSION)
      tool=$(printf '%s' "$ev" | sed -nE 's/.*required the "([A-Za-z_]+)" permission.*/\1/p')
      cmd=""; [ "$tool" = write_file ] || [ "$tool" = mcp ] || cmd=$(agy_last_command)
      if [ "$tool" = mcp ] || grep -qiE "$DIAG_MCP_RE" "$log" 2>/dev/null; then
        target=$(mcp_denied_target "$log")
        echo "Công cụ MCP bị từ chối: ${target:-(không rõ server/tool)}"
        if [ -z "$AGY_ALLOW_MCP" ]; then
          echo "AGY_ALLOW_MCP đang rỗng → nên nhắc agent KHÔNG dùng MCP (ghi rõ trong phần Overview của PLAN.md: chỉ dùng lệnh CLI như flutter test, flutter analyze, dart format) thay vì cấp thêm quyền."
          echo "Chỉ khi dự án thật sự cần MCP này: thêm AGY_ALLOW_MCP=\"${target:-<server>/<tool>}\" vào .autowf.env và quy tắc mcp(${target:-<server>/<tool>}) vào userSettings.globalPermissionGrants.allow ($AGY_CONFIG)."
        else
          echo "Thêm vào userSettings.globalPermissionGrants.allow ($AGY_CONFIG): mcp(${target:-<server>/<tool>})"
          if [ -n "$target" ] && ! grep -qxF "$target" <<< "$(mcp_items)"; then
            echo "và thêm '$target' vào AGY_ALLOW_MCP trong .autowf.env (hoặc nhắc agent không dùng MCP này)."
          fi
        fi
      elif [ "$tool" = write_file ]; then
        echo "Thêm vào userSettings.globalPermissionGrants.allow ($AGY_CONFIG): write_file($(pwd -P))"
      elif [ -n "$cmd" ]; then
        echo "Lệnh bị từ chối: $cmd"
        case "$cmd" in *';'*|*'&&'*|*'|'*|*'$('*) echo "Lệnh này nối nhiều lệnh — quy tắc hẹp không cho phép; hãy nhắc agent chạy từng lệnh một." ;; esac
        echo "Thêm vào userSettings.globalPermissionGrants.allow ($AGY_CONFIG): $(cmd_rule "$(first_exe "$cmd")")"
        echo "và thêm '$(first_exe "$cmd")' vào AGY_ALLOWED_CMDS trong .autowf.env."
      else
        echo "Chạy \`auto.sh --preflight\` để biết quy tắc nào còn thiếu (dạng $(cmd_rule '<lệnh>'))."
      fi ;;
    QUOTA)
      now=$(date +%s)
      if at=$(parse_reset_time "$log" "$now"); then echo "Hết hạn mức phía agent: chờ tới $(fmt_time "$at") rồi chạy lại auto.sh (hoặc đặt FALLBACK_CODER)."
      else echo "Hết hạn mức phía agent: chờ khoảng 60 phút rồi chạy lại auto.sh (hoặc đặt FALLBACK_CODER=gemini)."; fi ;;
    TIMEOUT)   echo "Agent chạy quá thời gian: chia Task này nhỏ hơn trong PLAN.md hoặc chạy lại auto.sh." ;;
    CRASH)     echo "Agent thoát bất thường: xem log, thử cập nhật agent (\`$ACTIVE_CODER update\`) rồi chạy lại auto.sh." ;;
    NO_ACTION) echo "Agent chạy xong nhưng không sửa file nào: đọc log xem nó hiểu sai gì, làm rõ Task trong PLAN.md rồi chạy lại." ;;
    *)         echo "Không rõ nguyên nhân: xem $log." ;;
  esac
}

# ---- Preflight quyền ----
preflight_hash() {
  local h="shasum -a 256"; command -v shasum >/dev/null || h=sha256sum
  { printf '%s\n' "$CODER" "$AGY_ALLOWED_CMDS" "$AGY_ALLOW_MCP" "${TEST_CMD:-}"; cat "$AGY_CONFIG" 2>/dev/null || true; } | $h | cut -d' ' -f1
}
preflight_cached() { [ -f "$LOG_DIR/preflight.ok" ] && grep -qxF "hash=$(preflight_hash)" "$LOG_DIR/preflight.ok"; }

probe_cmd() {  # lệnh vô hại để thử quyền của một lệnh
  case "$1" in
    git)   echo "git status --short" ;;
    ls)    echo "ls" ;;
    mkdir) echo "mkdir -p $LOG_DIR" ;;
    which) echo "which git" ;;
    *)     echo "$1 --version" ;;
  esac
}

# Thư mục môi trường không track cần có trong worktree tạm (in đường dẫn tương đối, mỗi dòng một thư mục)
env_dirs() {
  find . -name .git -prune -o -type d \( -name node_modules -o -name .venv -o -name venv \) -prune -print 2>/dev/null || true
  if [ -d .husky/_ ]; then echo .husky/_; fi
}

# Commit của auto.sh phải qua được git hook với PATH hiện tại (hook `language: system` gọi ruff/mypy...
# từ PATH). Chạy trong worktree tạm để không đụng cây làm việc: `pre-commit run --all-files` (nếu dùng
# pre-commit) rồi thử commit "Task 1: ...". In ✅/❌; trả về 1 và đặt HOOK_REPORT nếu chưa đạt.
check_commit_hooks() {
  local hooks_dir h found="" wt d rc=0 log="$LOG_DIR/preflight-hooks.log" advice links="" missing
  HOOK_REPORT=""
  mkdir -p "$LOG_DIR"
  hooks_dir=$(git rev-parse --git-path hooks 2>/dev/null) || return 0
  for h in pre-commit commit-msg; do
    if [ -x "$hooks_dir/$h" ]; then found+="${found:+, }$h"; fi
  done
  if [ -z "$found" ]; then
    if [ -f .pre-commit-config.yaml ]; then
      echo "  ⚠️  Có .pre-commit-config.yaml nhưng hook chưa được cài (pre-commit install) — commit sẽ không chạy hook"
    else
      echo "  ✅ Không có git hook pre-commit/commit-msg"
    fi
    return 0
  fi
  if ! git rev-parse -q --verify HEAD >/dev/null; then
    echo "  ⚠️  Có git hook ($found) nhưng repo chưa có commit nào — bỏ qua kiểm tra hook"
    return 0
  fi

  wt=$(mktemp -d "${TMPDIR:-/tmp}/autowf-hooks.XXXXXX")
  if ! git worktree add -q --detach "$wt" HEAD >/dev/null 2>&1; then
    rm -rf "$wt"
    echo "  ⚠️  Có git hook ($found) nhưng không tạo được worktree tạm — bỏ qua kiểm tra hook"
    return 0
  fi
  # Môi trường không track chỉ có ở cây chính: node_modules/.venv/venv ở mọi cấp (vd. frontend/node_modules), husky
  while IFS= read -r d; do
    d="${d#./}"
    if [ ! -e "$wt/$d" ] && [ -d "$(dirname "$wt/$d")" ]; then ln -s "$PWD/$d" "$wt/$d"; links+="$wt/$d"$'\n'; fi
  done < <(env_dirs)
  : > "$log"
  if [ -f .pre-commit-config.yaml ] && command -v pre-commit >/dev/null; then
    echo "\$ pre-commit run --all-files" >> "$log"
    if ! (cd "$wt" && pre-commit run --all-files) >> "$log" 2>&1; then
      echo "[auto.sh] chạy lại sau khi hook tự sửa file" >> "$log"
      (cd "$wt" && pre-commit run --all-files) >> "$log" 2>&1 || rc=1
    fi
  fi
  if [ "$rc" -eq 0 ]; then
    echo "\$ git commit --allow-empty -m '$(task_msg 1)'" >> "$log"
    (cd "$wt" && git commit -q --allow-empty -m "$(task_msg 1)") >> "$log" 2>&1 || rc=1
  fi
  while IFS= read -r d; do
    if [ -n "$d" ] && [ -L "$d" ]; then rm -f "$d"; fi
  done <<< "$links"
  git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
  git worktree prune

  if [ "$rc" -eq 0 ]; then
    echo "  ✅ Git hook ($found) — commit thử qua được với PATH hiện tại"
    return 0
  fi
  missing=$({ grep -oE '[^ :/]+: (command )?not found' "$log" || true; } | sed -E 's/: (command )?not found//' | sort -u | paste -sd ' ' -)
  if grep -qiE 'node_modules|Cannot find module' "$log"; then
    advice="Thiếu dependency JS (node_modules) cho hook${missing:+ — không thấy: $missing}. Chạy npm/pnpm install trong thư mục có package.json tương ứng (vd. frontend/) ở cây chính rồi chạy lại autowf --preflight"
  elif [ -n "$missing" ] || grep -qiE 'executable .*not found|not found in PATH' "$log"; then
    advice="Hook gọi công cụ không có trong PATH${missing:+: $missing}. Công cụ JS: kiểm tra node_modules/.bin (npm/pnpm install); công cụ Python: cài vào .venv (autowf tự thêm .venv/bin vào PATH) hoặc kích hoạt môi trường chứa nó; rồi chạy lại autowf --preflight"
  else
    advice="Sửa các lỗi hook báo ở trên (có thể là lỗi lint sẵn có trên HEAD) rồi commit, hoặc chỉnh cấu hình hook; kiểm tra lại: autowf --preflight"
  fi
  echo "  ❌ Git hook ($found) — commit thử bị từ chối, commit của auto.sh cũng sẽ fail (log: $log)"
  { grep -v '^[[:space:]]*$' "$log" || true; } | tail -n 8 | sed 's/^/     /'
  echo "     → $advice"
  HOOK_REPORT="❌ Git hook ($found) từ chối commit thử (log: $log)"$'\n'"$({ grep -v '^[[:space:]]*$' "$log" || true; } | tail -n 8)"$'\n'"Cách xử lý: $advice"
  return 1
}

# git add + commit; hook (vd. pre-commit tự format) sửa file làm commit fail thì add lại và thử thêm 1 lần.
# Output của git/hook ghi vào <file log>.
commit_task() {  # <message> <file log>
  git add -A
  git commit -qm "$1" --allow-empty > "$2" 2>&1 && return 0
  echo "[auto.sh] commit bị từ chối — add lại file hook đã sửa và thử lại" >> "$2"
  git add -A
  git commit -qm "$1" --allow-empty >> "$2" 2>&1
}

# In bảng ✅/❌; trả về 1 nếu có mục ❌ (quy tắc cần thêm để ở PREFLIGHT_REPORT)
run_preflight() {
  local ok=1 rules="" fails="" c probe log d name exe
  mkdir -p "$LOG_DIR"
  echo "🔎 Preflight quyền cho $CODER (log: $LOG_DIR/preflight-*.log)"

  log="$LOG_DIR/preflight-auth.log"
  ask_coder "Reply with the single word OK. Do not run any commands or tools." "$log"
  d=$(diagnose_agent_log "$log" "$CODER_RC")
  if [ "${d%%|*}" = NO_ACTION ]; then
    echo "  ✅ Đăng nhập $CODER"
  else
    echo "  ❌ Đăng nhập $CODER — ${d%%|*}: ${d#*|}"
    ACTIVE_CODER="$CODER"
    PREFLIGHT_REPORT="❌ Đăng nhập $CODER — ${d%%|*}: ${d#*|}"$'\n'"Cách xử lý: $(diag_advice "${d%%|*}" "${d#*|}" "$log")"
    echo "  ⏭️  Bỏ qua các mục còn lại"
    return 1
  fi

  if [ "$CODER" = agy ]; then
    while IFS= read -r c; do
      probe=$(probe_cmd "$c")
      name=$(printf '%s' "$c" | tr -c 'A-Za-z0-9_-' '_')
      log="$LOG_DIR/preflight-$name.log"
      ask_coder "Run exactly this one command and nothing else: $probe" "$log"
      if grep -qiE "$DIAG_PERM_RE" "$log"; then
        echo "  ❌ Lệnh $c ($probe) — BỊ TỪ CHỐI"
        fails+="❌ Lệnh $c — BỊ TỪ CHỐI (log: $log)"$'\n'; rules+="$(cmd_rule "$c")"$'\n'; ok=0
      else
        echo "  ✅ Lệnh $c ($probe) — ĐẠT"
      fi
    done < <(allowed_cmds)

    # MCP được phép: quy tắc mcp(server/tool) phải có sẵn trong config.json
    while IFS= read -r c; do
      if grep -qF "\"mcp($c)\"" "$AGY_CONFIG" 2>/dev/null; then
        echo "  ✅ MCP $c — có quy tắc trong config.json"
      else
        echo "  ❌ MCP $c — chưa có quy tắc mcp($c) trong config.json"
        fails+="❌ MCP $c — chưa có quy tắc trong $AGY_CONFIG"$'\n'; rules+="mcp($c)"$'\n'; ok=0
      fi
    done < <(mcp_items)
  fi

  log="$LOG_DIR/preflight-write.log"
  rm -f .autowf-probe.txt
  ask_coder "Create a file named .autowf-probe.txt in the current directory containing the word ok. Do not run any shell commands." "$log"
  if [ -f .autowf-probe.txt ]; then
    rm -f .autowf-probe.txt
    echo "  ✅ Ghi file (.autowf-probe.txt)"
  else
    echo "  ❌ Ghi file (.autowf-probe.txt) — agent không tạo được file"
    fails+="❌ Ghi file — agent không tạo được .autowf-probe.txt (log: $log)"$'\n'; ok=0
    [ "$CODER" != agy ] || rules+="write_file($(pwd -P))"$'\n'
  fi

  if [ "$CODER" = agy ]; then
    if [ -z "${TEST_CMD:-}" ]; then
      echo "  ⚠️  Chưa có TEST_CMD (PLAN.md) — bỏ qua kiểm tra lệnh test"
    else
      exe=$(first_exe "$TEST_CMD")
      if grep -qxF "$exe" <<< "$(allowed_cmds)"; then
        echo "  ✅ TEST_CMD bắt đầu bằng '$exe' (có trong AGY_ALLOWED_CMDS)"
      else
        echo "  ❌ TEST_CMD bắt đầu bằng '$exe' nhưng '$exe' không có trong AGY_ALLOWED_CMDS"
        fails+="❌ TEST_CMD dùng '$exe' không có trong AGY_ALLOWED_CMDS → thêm '$exe' vào AGY_ALLOWED_CMDS (.autowf.env)"$'\n'
        rules+="$(cmd_rule "$exe")"$'\n'; ok=0
      fi
    fi
  fi

  if [ "$ok" -eq 1 ]; then
    { echo "hash=$(preflight_hash)"; echo "date=$(date '+%Y-%m-%d %H:%M:%S')"; echo "coder=$CODER"; } > "$LOG_DIR/preflight.ok"
    echo "✅ Preflight đạt (đã lưu $LOG_DIR/preflight.ok)"
    return 0
  fi
  rm -f "$LOG_DIR/preflight.ok"
  PREFLIGHT_REPORT="$fails"
  if [ -n "$rules" ]; then
    echo "❌ Preflight chưa đạt. Thêm các quy tắc sau vào userSettings.globalPermissionGrants.allow trong $AGY_CONFIG:"
    printf '%s' "$rules" | sed 's/^/     /'
    PREFLIGHT_REPORT+="Quy tắc cần thêm vào userSettings.globalPermissionGrants.allow ($AGY_CONFIG):"$'\n'"$rules"
  else
    echo "❌ Preflight chưa đạt."
  fi
  return 1
}

# ---- --check ----
if [ "$CHECK_ONLY" -eq 1 ]; then
  OK=1
  for c in claude "$CODER" ${FALLBACK_CODER:+"$FALLBACK_CODER"}; do
    if command -v "$c" >/dev/null; then echo "✅ Đã cài $c"; else echo "❌ Chưa cài $c"; OK=0; fi
  done
  if load_plan; then echo "✅ PLAN.md hợp lệ: $TOTAL task, TEST_CMD: $TEST_CMD"
  else echo "❌ PLAN.md: $PLAN_ERR"; OK=0; fi
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -z "$(git status --porcelain -- . ":(exclude)$LOG_DIR")" ]; then echo "✅ Git sạch (branch $(git branch --show-current))"
    else echo "❌ Git còn thay đổi chưa commit:"; git status --short -- . ":(exclude)$LOG_DIR"; OK=0; fi
  else
    echo "⚠️  Chưa phải git repo — auto.sh sẽ git init khi chạy"
  fi
  if preflight_cached; then echo "✅ Preflight quyền đã đạt với cấu hình hiện tại"
  else echo "ℹ️  Preflight quyền chưa chạy với cấu hình hiện tại (sẽ tự chạy, hoặc: auto.sh --preflight)"; fi
  if git rev-parse --git-dir >/dev/null 2>&1; then
    echo "🔎 Git hook (log: $LOG_DIR/preflight-hooks.log)"
    check_commit_hooks || OK=0
  fi
  [ "$OK" -eq 1 ] && { echo "👍 Sẵn sàng chạy"; exit 0; }
  exit 1
fi

# ---- --preflight: chỉ kiểm tra quyền rồi thoát ----
if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
  need "$CODER" "Cài coding agent '$CODER' trước (mặc định: Antigravity CLI agy)"
  ACTIVE_CODER="$CODER"
  load_plan || TEST_CMD=""
  RC=0
  run_preflight || RC=5
  echo "🔎 Git hook (log: $LOG_DIR/preflight-hooks.log)"
  check_commit_hooks || RC=5
  exit "$RC"
fi

# ---- --adopt N: nhận Task N đã được người làm/kiểm tra ----
# Chạy TEST_CMD; cây còn thay đổi thì commit chúng thành "Task N: <tiêu đề>", cây sạch thì đổi tên
# commit HEAD (chưa push, chưa phải commit Task nào) thành tên đó — để lần chạy sau bỏ qua Task N.
if [ -n "$ADOPT" ]; then
  load_plan || { echo "❌ PLAN.md: $PLAN_ERR"; exit 1; }
  case "$ADOPT" in *[!0-9]*) ADOPT=0 ;; esac
  if [ "$ADOPT" -lt 1 ] || [ "$ADOPT" -gt "$TOTAL" ]; then echo "❌ --adopt cần số task từ 1 đến $TOTAL"; exit 1; fi
  git rev-parse -q --verify HEAD >/dev/null || { echo "❌ Repo chưa có commit nào"; exit 1; }
  load_done_subjects
  MSG=$(task_msg "$ADOPT")
  if task_done "$ADOPT"; then echo "ℹ️  Task $ADOPT đã có commit sau lần sửa PLAN.md gần nhất — không cần làm gì"; exit 0; fi
  mkdir -p "$LOG_DIR"
  LOG="$LOG_DIR/adopt-task$ADOPT.log"
  DIRTY=$(git status --porcelain -- . ":(exclude)$LOG_DIR")
  if [ -z "$DIRTY" ]; then
    OLD=$(git log -1 --format=%s)
    if [ "$(git rev-parse HEAD)" = "$PLAN_COMMIT" ]; then echo "❌ Cây sạch và HEAD là commit sửa PLAN.md — không có gì để nhận là Task $ADOPT"; exit 1; fi
    if grep -qE '^Task [0-9]+(:|$)' <<< "$OLD"; then echo "❌ HEAD đã là commit của task khác ('$OLD') — không đổi tên"; exit 1; fi
    if [ -n "$(git branch -r --contains HEAD 2>/dev/null)" ]; then echo "❌ HEAD đã được push — không đổi tên commit"; exit 1; fi
  fi
  echo "🧪 Chạy TEST_CMD: $TEST_CMD (log: $LOG)"
  [ -z "$DIRTY" ] || git add -A   # giống pipeline: hook trong TEST_CMD thấy cả file mới
  if ! bash -c "$TEST_CMD" > "$LOG" 2>&1; then
    echo "❌ TEST_CMD thất bại — không commit. Dòng cuối:"
    { grep -v '^[[:space:]]*$' "$LOG" || true; } | tail -n 15 | sed 's/^/   /'
    exit 1
  fi
  if [ -n "$DIRTY" ]; then
    commit_task "$MSG" "$LOG_DIR/adopt-task$ADOPT-commit.log" || {
      echo "❌ git commit bị từ chối (log: $LOG_DIR/adopt-task$ADOPT-commit.log):"
      tail -n 15 "$LOG_DIR/adopt-task$ADOPT-commit.log" | sed 's/^/   /'; exit 1; }
    echo "✅ Đã commit: $(git log -1 --format='%h %s')"
  else
    git commit -q --amend -m "$MSG"
    echo "✅ Đổi tên HEAD '$OLD' → $(git log -1 --format='%h %s')"
  fi
  exit 0
fi

need claude "Cài: curl -fsSL https://claude.ai/install.sh | bash"
need "$CODER" "Cài coding agent '$CODER' trước (mặc định: Antigravity CLI agy)"
if [ -n "$FALLBACK_CODER" ] && ! command -v "$FALLBACK_CODER" >/dev/null; then
  echo "⚠️  FALLBACK_CODER='$FALLBACK_CODER' chưa cài — sẽ không có agent dự phòng"
  FALLBACK_CODER=""
fi
if [ ! -f PLAN.md ] && [ -z "$DESC" ]; then usage; exit 1; fi

# ---- Git: không init lại repo có sẵn, không tự commit thay đổi của người dùng ----
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  git init -q
  git add -A && git commit -qm "Before auto.sh" --allow-empty
fi
git rev-parse -q --verify HEAD >/dev/null || git commit -qm "Initial commit (auto.sh)" --allow-empty
if [ -n "$(git status --porcelain -- . ":(exclude)$LOG_DIR")" ]; then
  echo "⛔ Repo còn thay đổi chưa commit — auto.sh không tự commit hộ. Hãy commit hoặc stash rồi chạy lại:"
  git status --short -- . ":(exclude)$LOG_DIR"
  echo "   (Bỏ phần dở của lần chạy trước: git stash -u   hoặc   git checkout -- . && git clean -fd)"
  exit 1
fi

CURRENT=$(git branch --show-current)
if [ "$NEW_BRANCH" -eq 0 ] && [[ "$CURRENT" == auto/* ]]; then
  BRANCH="$CURRENT"
  echo "🌿 Làm tiếp trên branch $BRANCH"
else
  BRANCH="auto/$(date +%Y%m%d-%H%M%S)"
  i=2; base="$BRANCH"
  while git show-ref -q --verify "refs/heads/$BRANCH"; do BRANCH="$base-$i"; i=$((i + 1)); done
  git checkout -qb "$BRANCH"
  echo "🌿 Đang làm trên branch mới $BRANCH"
fi

mkdir -p "$LOG_DIR"
# Ghi mọi thứ in ra Terminal vào run.log (tee bỏ qua Ctrl-C để kịp ghi dòng cuối)
exec > >(trap '' INT; exec tee -a "$LOG_DIR/run.log") 2>&1
echo "===== auto.sh bắt đầu $(date '+%Y-%m-%d %H:%M:%S') trên branch $BRANCH ====="
touch .gitignore
for line in "$LOG_DIR/" "REVIEW.md"; do
  grep -qxF "$line" .gitignore || echo "$line" >> .gitignore
done
git rm -q --cached --ignore-unmatch REVIEW.md >/dev/null
if [ -n "$(git status --porcelain)" ]; then
  # Commit dọn dẹp chỉ đụng .gitignore: bỏ qua hook để lỗi hook được báo rõ ở bước kiểm tra hook bên dưới
  git add -A && git commit -qm "auto.sh: ignore $LOG_DIR/ and REVIEW.md" --no-verify
fi

# ---- Tóm tắt cuối mỗi lần chạy ----
RUN_START=$(date +%s)
STOP_REASON=""
STOP_DETAILS=""
PREFLIGHT_REPORT=""
TOTAL=0
WAIT_COUNT=0
WAITED_SECS=0
FALLBACK_NOTE=""
T_STATUS=(); T_TRIES=(); T_BEGIN=(); T_END=()

write_summary() {
  local rc=$? n end
  if [ -z "$STOP_REASON" ]; then
    if [ "$rc" -eq 0 ]; then STOP_REASON="Hoàn thành"; else STOP_REASON="Lỗi không mong đợi (exit $rc), xem $LOG_DIR/run.log"; fi
  fi
  {
    echo "# auto.sh — tóm tắt lần chạy"
    echo
    echo "- Bắt đầu: $(fmt_time "$RUN_START"), tổng thời gian: $(fmt_dur $(($(date +%s) - RUN_START)))"
    echo "- Branch: $BRANCH"
    echo "- Coding agent: $CODER${FALLBACK_NOTE:+ — $FALLBACK_NOTE}; review: $REVIEW_MODEL"
    echo "- Số lần chờ hạn mức Claude: $WAIT_COUNT (tổng $(fmt_dur "$WAITED_SECS"))"
    echo "- Kết thúc: $STOP_REASON"
    if [ "$rc" -ne 0 ]; then
      echo
      echo "## Nguyên nhân"
      echo
      echo "$STOP_REASON"
      if [ -n "$STOP_DETAILS" ]; then echo; echo '```'; printf '%s\n' "$STOP_DETAILS"; echo '```'; fi
    fi
    # seq trên macOS với `seq 1 0` in ra "1 0", nên chỉ in bảng khi đã đọc được plan
    if [ "$TOTAL" -gt 0 ]; then
      echo
      echo "| Task | Kết quả | Số vòng | Thời gian |"
      echo "|---|---|---|---|"
      for n in $(seq 1 "$TOTAL"); do
        if [ -n "${T_BEGIN[$n]:-}" ]; then
          end="${T_END[$n]:-$(date +%s)}"
          echo "| $n | ${T_STATUS[$n]:-?} | ${T_TRIES[$n]:-0} | $(fmt_dur $((end - T_BEGIN[n]))) |"
        else
          echo "| $n | ${T_STATUS[$n]:-chưa chạy} | - | - |"
        fi
      done
    fi
  } > "$LOG_DIR/summary.md"
  echo "📝 Tóm tắt: $LOG_DIR/summary.md"
}
trap write_summary EXIT
trap 'STOP_REASON="Bị ngắt (Ctrl-C/TERM)"; exit 130' INT TERM

stop() {  # stop <exit code> <lý do> [chi tiết nhiều dòng]
  STOP_REASON="$2"
  STOP_DETAILS="${3:-}"
  echo "⛔ $2"
  if [ -n "$STOP_DETAILS" ]; then printf '%s\n' "$STOP_DETAILS" | sed 's/^/   /'; fi
  notify "$2"
  exit "$1"
}

# ---- Claude: tự chờ khi chạm giới hạn sử dụng ----
is_usage_limit() {  # <file output> <exit code>
  if [ "$2" -ne 0 ]; then grep -qiE "$LIMIT_RE" "$1"
  else head -n1 "$1" | grep -qiE "$LIMIT_RE"   # thành công thì chỉ xét dòng đầu (dòng PASS/FAIL)
  fi
}

# claude_call <file stdin> <file output> <tham số cho claude...>
# Chạm giới hạn sử dụng thì ngủ tới giờ reset rồi thử lại; không tính là một lần FAIL của task.
claude_call() {
  local in="$1" out="$2" rc now reset_at wait_s msg
  shift 2
  while true; do
    rc=0
    claude "$@" < "$in" > "$out" 2>&1 || rc=$?
    is_usage_limit "$out" "$rc" || return "$rc"

    now=$(date +%s)
    if reset_at=$(parse_reset_time "$out" "$now"); then
      wait_s=$((reset_at - now + 120)); msg="reset lúc $(fmt_time "$reset_at") + 2 phút"
    else
      wait_s=1800; msg="không đọc được giờ reset, chờ 30 phút"
    fi
    if [ -n "$AUTOWF_TEST_WAIT_SECS" ]; then
      msg="$msg — TEST: chỉ chờ ${AUTOWF_TEST_WAIT_SECS}s"; wait_s="$AUTOWF_TEST_WAIT_SECS"
    fi
    if [ $((WAITED_SECS + wait_s)) -gt $((MAX_WAIT_HOURS * 3600)) ]; then
      stop 3 "Claude chạm giới hạn sử dụng; chờ thêm sẽ vượt MAX_WAIT_HOURS=${MAX_WAIT_HOURS}h ($msg)"
    fi
    WAIT_COUNT=$((WAIT_COUNT + 1)); WAITED_SECS=$((WAITED_SECS + wait_s))
    echo "⏳ Claude chạm giới hạn sử dụng ($msg). Sẽ chạy lại lúc $(fmt_time $((now + wait_s)))."
    notify "Claude hết hạn mức, chạy lại lúc $(fmt_time $((now + wait_s)))"
    sleep "$wait_s"
  done
}

# Test bị lỗi: lấy vài dòng lỗi cuối, bỏ số dòng / đường dẫn tạm / thời gian để so giữa các vòng
test_signature() {
  printf '%s\n' "$1" | { grep -v '^[[:space:]]*$' || true; } | tail -n 5 | sed -E \
    -e 's#(/private)?/(tmp|var/folders)/[^[:space:]:"]*#<tmp>#g' \
    -e 's/(line |:)[0-9]+/\1N/g' -e 's/0x[0-9a-fA-F]+/0xN/g' -e 's/ in [0-9.]+s/ in Ns/g'
}

# ---- Bước 1: Claude viết plan ----
if [ ! -f PLAN.md ]; then
  echo "🧠 Claude ($PLAN_MODEL) đang viết PLAN.md..."
  claude_call /dev/null "$LOG_DIR/plan.log" -p "Write a PLAN.md file for the following project: $DESC

MANDATORY format:
- Write the whole plan in English.
- Include one line starting with 'TEST_CMD: ' followed by ONE shell command that runs the full test suite (e.g. TEST_CMD: npm test).
- Start with a short project overview (stack, layout, conventions) before '## Task 1'; reviewers only see that overview plus one task.
- Each task is a heading '## Task N: <title>' (N starts at 1, consecutive).
- Each task is small enough for one agent run; list the files to create/modify and acceptance criteria verifiable by tests.
- Task 1 sets up the project skeleton and test configuration so TEST_CMD runs.
- Write it so another coding agent can follow it without asking questions." \
    --model "$PLAN_MODEL" --permission-mode acceptEdits --allowedTools "Read,Write,Glob,Grep" || true
  [ -f PLAN.md ] || stop 1 "Claude không tạo được PLAN.md, xem $LOG_DIR/plan.log" "$(tail -n 5 "$LOG_DIR/plan.log" 2>/dev/null || true)"
  git add -A && git commit -qm "PLAN.md"
fi

load_plan || stop 1 "PLAN.md không hợp lệ: $PLAN_ERR"
echo "📋 $TOTAL task — lệnh test: $TEST_CMD"
# Chỉ tính "Task N" commit sau lần sửa PLAN.md gần nhất (task của plan cũ đã merge không được tính)
load_done_subjects

# ---- Preflight quyền (bỏ qua nếu cấu hình không đổi kể từ lần đạt trước) ----
ACTIVE_CODER="$CODER"
if preflight_cached; then
  echo "✅ Preflight: bỏ qua (cấu hình quyền không đổi kể từ lần đạt trước; ép chạy lại: auto.sh --preflight)"
else
  run_preflight || stop 5 "Preflight quyền chưa đạt — chưa chạy task nào" "$PREFLIGHT_REPORT"
fi
# Hook phụ thuộc PATH của Terminal đang chạy, nên kiểm tra mỗi lần chạy (không cache)
echo "🔎 Git hook (log: $LOG_DIR/preflight-hooks.log)"
check_commit_hooks || stop 5 "Git hook từ chối commit thử — commit của auto.sh sẽ fail; chưa chạy task nào" "$HOOK_REPORT"

# ---- Bước 2: vòng lặp code → test → review ----
for N in $(seq 1 "$TOTAL"); do
  if task_done "$N"; then
    T_STATUS[N]="SKIP (đã commit trước đó)"
    echo "⏭️  Bỏ qua Task $N (đã có commit trên branch này)"
    continue
  fi

  T_BEGIN[N]=$(date +%s); T_STATUS[N]="FAIL"; T_TRIES[N]=0
  rm -f REVIEW.md
  PREV_SIG=""
  PROMPT="Read PLAN.md and implement ONLY Task $N. Do not work on other tasks and do not modify PLAN.md. When the code is done, run: $TEST_CMD and fix things until it passes. Write a short English summary of what you did to PROGRESS.md. $GIT_RULE"

  for TRY in $(seq 1 "$MAX_TRIES"); do
    T_TRIES[N]=$TRY
    echo "▶️  Task $N/$TOTAL — lần $TRY ($ACTIVE_CODER)"
    CODE_LOG="$LOG_DIR/task$N-try$TRY-code.log"
    snapshot_git
    run_coder "$ACTIVE_CODER" "$PROMPT" "$CODE_LOG"

    # Agent dự phòng khi agent chính lỗi đăng nhập/quyền
    if [ -n "$FALLBACK_CODER" ] && [ "$ACTIVE_CODER" != "$FALLBACK_CODER" ] && grep -qiE "$CODER_AUTH_RE" "$CODE_LOG"; then
      echo "[auto.sh] $ACTIVE_CODER lỗi đăng nhập/quyền → chạy lại Task $N bằng $FALLBACK_CODER" >> "$CODE_LOG"
      echo "⚠️  $ACTIVE_CODER lỗi đăng nhập/quyền (xem $CODE_LOG) → chuyển sang agent dự phòng $FALLBACK_CODER"
      notify "$ACTIVE_CODER lỗi đăng nhập/quyền, chuyển sang $FALLBACK_CODER"
      FALLBACK_NOTE="chuyển sang $FALLBACK_CODER từ Task $N lần $TRY do $ACTIVE_CODER lỗi đăng nhập/quyền"
      ACTIVE_CODER="$FALLBACK_CODER"
      CODE_LOG="$LOG_DIR/task$N-try$TRY-code-$ACTIVE_CODER.log"
      run_coder "$ACTIVE_CODER" "$PROMPT" "$CODE_LOG"
    fi

    undo_agent_git "$CODE_LOG"

    # Cầu dao (a): agent không đổi file nào
    if [ -z "$(git status --porcelain)" ]; then
      T_END[N]=$(date +%s)
      DIAG=$(diagnose_agent_log "$CODE_LOG" "$CODER_RC")
      DIAG_TYPE="${DIAG%%|*}"; DIAG_EV="${DIAG#*|}"
      stop 2 "Cầu dao: agent không thay đổi file nào ở Task $N (lần $TRY) — lỗi $DIAG_TYPE" \
        "Loại lỗi: $DIAG_TYPE
Bằng chứng: ${DIAG_EV:-(log trống)}
Log: $CODE_LOG (exit code $CODER_RC)
Cách xử lý: $(diag_advice "$DIAG_TYPE" "$DIAG_EV" "$CODE_LOG")"
    fi

    # Script tự chạy test, không tin lời báo cáo của agent. Stage trước để hook trong TEST_CMD
    # (vd. `pre-commit run`, chỉ xét file đã stage) thấy cả file mới — giống lúc commit.
    git add -A
    if TEST_OUT=$(bash -c "$TEST_CMD" 2>&1); then TEST_OK=1; else TEST_OK=0; fi
    printf '%s\n' "$TEST_OUT" > "$LOG_DIR/task$N-try$TRY-test.log"
    TEST_OUT=$(printf '%s\n' "$TEST_OUT" | tail -n 60)

    # Cầu dao (b): lỗi test giống hệt vòng trước
    if [ "$TEST_OK" -eq 0 ]; then
      SIG=$(test_signature "$TEST_OUT")
      if [ -n "$PREV_SIG" ] && [ "$SIG" = "$PREV_SIG" ]; then
        T_END[N]=$(date +%s)
        stop 2 "Cầu dao: lỗi test ở Task $N lần $TRY giống hệt lần trước — agent đang lặp lại, dừng sớm" \
          "5 dòng lỗi test lặp lại:
$(printf '%s\n' "$TEST_OUT" | { grep -v '^[[:space:]]*$' || true; } | tail -n 5)
Log: $LOG_DIR/task$N-try$TRY-test.log (lần trước: $LOG_DIR/task$N-try$((TRY - 1))-test.log)"
      fi
      PREV_SIG="$SIG"
    else
      PREV_SIG=""
    fi

    git add -A
    DIFF=$(git diff --cached HEAD -- . "${DIFF_EXCLUDES[@]}" | head -c 40000 || true)
    PLAN_PART=$(plan_excerpt "$N")
    [ -n "$PLAN_PART" ] || PLAN_PART=$(cat PLAN.md)

    REVIEW_IN="$LOG_DIR/task$N-try$TRY-review-input.txt"
    REVIEW_OUT="$LOG_DIR/task$N-try$TRY-review.md"
    {
      echo "=== PLAN.md (overview + Task $N) ==="; echo "$PLAN_PART"
      echo; echo "=== TEST RESULTS (command: $TEST_CMD, pass=$TEST_OK, last 60 lines) ==="; echo "$TEST_OUT"
      echo; echo "=== GIT DIFF FOR TASK $N ==="; echo "$DIFF"
    } > "$REVIEW_IN"

    echo "🔍 Claude ($REVIEW_MODEL) đang review..."
    claude_call "$REVIEW_IN" "$REVIEW_OUT" -p --model "$REVIEW_MODEL" "You are a strict code reviewer. Review Task $N against its acceptance criteria in the PLAN.md excerpt above, using the test results and the diff. Check for bugs, security issues, edge cases and deviations from the plan.
Answer BRIEFLY, in English. The FIRST line must be exactly one word: PASS or FAIL.
If FAIL: at most 10 checklist items, ONE line each, formatted '- file:location — problem — fix'. Do not paste long code." \
      || { T_END[N]=$(date +%s); stop 4 "Không gọi được Claude để review Task $N, xem $REVIEW_OUT" "$(head -n 5 "$REVIEW_OUT" 2>/dev/null || true)"; }

    VERDICT=$(cat "$REVIEW_OUT")
    FIRST=$(printf '%s' "${VERDICT%%$'\n'*}" | tr -d '[:space:]*#')
    # Reviewer đôi khi đặt PASS/FAIL ở dòng cuối thay vì dòng đầu
    if [ "$FIRST" != "PASS" ] && [ "$FIRST" != "FAIL" ]; then
      FIRST=$(printf '%s\n' "$VERDICT" | { grep -v '^[[:space:]]*$' || true; } | tail -n 1 | tr -d '[:space:]*#')
    fi

    if [ "$FIRST" = "PASS" ] && [ "$TEST_OK" -eq 1 ]; then
      rm -f REVIEW.md
      COMMIT_LOG="$LOG_DIR/task$N-try$TRY-commit.log"
      if commit_task "$(task_msg "$N")" "$COMMIT_LOG"; then
        T_END[N]=$(date +%s); T_STATUS[N]="PASS"
        echo "✅ Task $N đạt"
        break
      fi
      # Hook từ chối commit (kể cả sau khi đã add lại file hook tự sửa) → coi như một vòng FAIL
      {
        echo "- git commit was rejected by the repository's git hooks (pre-commit etc.). Fix every problem the hooks report below, then re-run: $TEST_CMD"
        echo; echo "Hook output (last lines):"
        { grep -v '^[[:space:]]*$' "$COMMIT_LOG" || true; } | tail -n 40
      } > REVIEW.md
      echo "❌ Task $N: review PASS nhưng git hook từ chối commit (xem REVIEW.md, $COMMIT_LOG)"
    else
      printf '%s\n' "$VERDICT" | tail -n +2 > REVIEW.md
      if [ "$TEST_OK" -eq 0 ]; then printf '\n- Tests are FAILING (last lines):\n%s\n' "$TEST_OUT" >> REVIEW.md; fi
      echo "❌ Task $N chưa đạt (xem REVIEW.md)"
    fi

    if [ "$TRY" -eq "$MAX_TRIES" ]; then
      T_END[N]=$(date +%s)
      stop 1 "Task $N thất bại sau $MAX_TRIES lần. Xem REVIEW.md và $LOG_DIR/" \
        "Lỗi còn lại theo review/test lần cuối (REVIEW.md):
$(head -n 12 REVIEW.md 2>/dev/null || true)"
    fi
    PROMPT="Task $N is not done yet. Read REVIEW.md and PLAN.md, fix exactly the issues listed for Task $N, and do not work on other tasks. Re-run: $TEST_CMD. Update PROGRESS.md. $GIT_RULE"
  done
done

STOP_REASON="Hoàn thành cả $TOTAL task"
notify "Xong cả $TOTAL task 🎉"
echo "🎉 Xong $TOTAL task trên branch $BRANCH. Log ở $LOG_DIR/"
echo "   Gộp vào nhánh chính:  git checkout main && git merge $BRANCH"
