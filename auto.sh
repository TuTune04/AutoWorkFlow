#!/bin/bash
# auto.sh — Claude lên plan & review, coding agent (mặc định Antigravity CLI `agy`) viết code.
#
# Cách dùng:
#   ./auto.sh "mô tả dự án"   chưa có PLAN.md: Claude viết plan rồi chạy
#   ./auto.sh                 đã có PLAN.md: chạy (hoặc chạy tiếp) theo plan
#   ./auto.sh --check         chỉ kiểm tra công cụ, PLAN.md và git rồi thoát
#   ./auto.sh --new-branch    ép tạo branch auto/* mới thay vì làm tiếp branch auto/* hiện tại
#
# Biến cấu hình: đặt trong .autowf.env ở gốc repo, hoặc qua env (env được ưu tiên hơn file):
#   CODER=agy              coding agent: agy | gemini | ...
#   FALLBACK_CODER=        agent dự phòng khi CODER lỗi đăng nhập/quyền (ví dụ: gemini)
#   PLAN_MODEL=opus        model Claude viết PLAN.md
#   REVIEW_MODEL=sonnet    model Claude review
#   MAX_TRIES=3            số vòng sửa tối đa mỗi task
#   MAX_WAIT_HOURS=6       tổng thời gian tối đa chờ khi Claude chạm giới hạn sử dụng
#   AGY_ALLOWED_CMDS=...   danh sách lệnh nhắc agy dùng (phải khớp allowlist trong ~/.gemini/config/config.json)
# Ví dụ:
#   REVIEW_MODEL=haiku ./auto.sh
#   CODER=gemini ./auto.sh
#   FALLBACK_CODER=gemini MAX_TRIES=5 ./auto.sh
#
# Chạy tiếp: task đã có commit "Task N" trên branch hiện tại được bỏ qua.
# Mỗi lần chạy ghi tóm tắt vào .auto-logs/summary.md.

set -euo pipefail

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

NEW_BRANCH=0
CHECK_ONLY=0
DESC=""
for arg in "$@"; do
  case "$arg" in
    --new-branch) NEW_BRANCH=1 ;;
    --check)      CHECK_ONLY=1 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "❌ Cờ không hợp lệ: $arg"; usage; exit 1 ;;
    *)            DESC="${DESC:+$DESC }$arg" ;;
  esac
done

notify()   { osascript -e "display notification \"$1\" with title \"auto.sh\"" 2>/dev/null || true; }
need()     { command -v "$1" >/dev/null || { echo "❌ Thiếu '$1'. $2"; exit 1; }; }
fmt_time() { date -r "$1" '+%H:%M %d/%m' 2>/dev/null || date -d "@$1" '+%H:%M %d/%m'; }
fmt_dur()  { printf '%dh%02dm%02ds' $(($1 / 3600)) $(($1 % 3600 / 60)) $(($1 % 60)); }

need git "Cài: xcode-select --install"
# Luôn làm việc ở gốc repo (nếu đang ở trong một repo)
if ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then cd "$ROOT"; fi

# ---- Cấu hình: mặc định < .autowf.env < biến môi trường ----
CONFIG_VARS="CODER FALLBACK_CODER PLAN_MODEL REVIEW_MODEL MAX_TRIES MAX_WAIT_HOURS AGY_ALLOWED_CMDS"
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
# Chỉ dùng khi test: thay thời gian chờ hạn mức bằng số giây này
AUTOWF_TEST_WAIT_SECS="${AUTOWF_TEST_WAIT_SECS:-}"

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

# ---- --check ----
if [ "$CHECK_ONLY" -eq 1 ]; then
  OK=1
  for c in claude "$CODER" ${FALLBACK_CODER:+"$FALLBACK_CODER"}; do
    if command -v "$c" >/dev/null; then echo "✅ Đã cài $c"; else echo "❌ Chưa cài $c"; OK=0; fi
  done
  if load_plan; then echo "✅ PLAN.md hợp lệ: $TOTAL task, TEST_CMD: $TEST_CMD"
  else echo "❌ PLAN.md: $PLAN_ERR"; OK=0; fi
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if [ -z "$(git status --porcelain)" ]; then echo "✅ Git sạch (branch $(git branch --show-current))"
    else echo "❌ Git còn thay đổi chưa commit:"; git status --short; OK=0; fi
  else
    echo "⚠️  Chưa phải git repo — auto.sh sẽ git init khi chạy"
  fi
  [ "$OK" -eq 1 ] && { echo "👍 Sẵn sàng chạy"; exit 0; }
  exit 1
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
if [ -n "$(git status --porcelain)" ]; then
  echo "⛔ Repo còn thay đổi chưa commit — auto.sh không tự commit hộ. Hãy commit hoặc stash rồi chạy lại:"
  git status --short
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
touch .gitignore
for line in "$LOG_DIR/" "REVIEW.md"; do
  grep -qxF "$line" .gitignore || echo "$line" >> .gitignore
done
git rm -q --cached --ignore-unmatch REVIEW.md >/dev/null
if [ -n "$(git status --porcelain)" ]; then
  git add -A && git commit -qm "auto.sh: ignore $LOG_DIR/ and REVIEW.md"
fi

# ---- Tóm tắt cuối mỗi lần chạy ----
RUN_START=$(date +%s)
STOP_REASON=""
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

stop() {  # stop <exit code> <lý do>
  STOP_REASON="$2"
  echo "⛔ $2"
  notify "$2"
  exit "$1"
}

# ---- Claude: tự chờ khi chạm giới hạn sử dụng ----
is_usage_limit() {  # <file output> <exit code>
  if [ "$2" -ne 0 ]; then grep -qiE "$LIMIT_RE" "$1"
  else head -n1 "$1" | grep -qiE "$LIMIT_RE"   # thành công thì chỉ xét dòng đầu (dòng PASS/FAIL)
  fi
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

# ---- Coding agent ----
AGY_RULES="Command rules (mandatory; any other command is auto-denied and ends your run): only use $AGY_ALLOWED_CMDS; run exactly ONE command per call, never chain commands with ; && || | or \$(...); do not use cd, rm, cat or echo. Create/edit files with the file-writing tool and read files with the file-reading tool."

run_coder() {  # <agent> <prompt> <file log>
  case "$1" in
    agy)    agy -p "$2 $AGY_RULES" ;;
    gemini) gemini -p "$2" --yolo ;;
    *)      "$1" -p "$2" ;;
  esac < /dev/null > "$3" 2>&1 || true
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
  [ -f PLAN.md ] || stop 1 "Claude không tạo được PLAN.md, xem $LOG_DIR/plan.log"
  git add -A && git commit -qm "PLAN.md"
fi

load_plan || stop 1 "PLAN.md không hợp lệ: $PLAN_ERR"
echo "📋 $TOTAL task — lệnh test: $TEST_CMD"
# Chỉ tính "Task N" commit sau lần sửa PLAN.md gần nhất (task của plan cũ đã merge không được tính)
PLAN_COMMIT=$(git log -1 --format=%H -- PLAN.md)
DONE_SUBJECTS=""
[ -z "$PLAN_COMMIT" ] || DONE_SUBJECTS=$(git log --format=%s "$PLAN_COMMIT"..HEAD)

# ---- Bước 2: vòng lặp code → test → review ----
ACTIVE_CODER="$CODER"
for N in $(seq 1 "$TOTAL"); do
  if grep -qxF "Task $N" <<< "$DONE_SUBJECTS"; then
    T_STATUS[N]="SKIP (đã commit trước đó)"
    echo "⏭️  Bỏ qua Task $N (đã có commit trên branch này)"
    continue
  fi

  T_BEGIN[N]=$(date +%s); T_STATUS[N]="FAIL"; T_TRIES[N]=0
  rm -f REVIEW.md
  PREV_SIG=""
  PROMPT="Read PLAN.md and implement ONLY Task $N. Do not work on other tasks and do not modify PLAN.md. When the code is done, run: $TEST_CMD and fix things until it passes. Write a short English summary of what you did to PROGRESS.md."

  for TRY in $(seq 1 "$MAX_TRIES"); do
    T_TRIES[N]=$TRY
    echo "▶️  Task $N/$TOTAL — lần $TRY ($ACTIVE_CODER)"
    CODE_LOG="$LOG_DIR/task$N-try$TRY-code.log"
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

    # Cầu dao (a): agent không đổi file nào
    if [ -z "$(git status --porcelain)" ]; then
      T_END[N]=$(date +%s)
      stop 2 "Cầu dao: agent không thay đổi file nào ở Task $N (lần $TRY) — thường do bị từ chối quyền hoặc chưa đăng nhập. Xem $CODE_LOG"
    fi

    # Script tự chạy test, không tin lời báo cáo của agent
    if TEST_OUT=$(bash -c "$TEST_CMD" 2>&1); then TEST_OK=1; else TEST_OK=0; fi
    printf '%s\n' "$TEST_OUT" > "$LOG_DIR/task$N-try$TRY-test.log"
    TEST_OUT=$(printf '%s\n' "$TEST_OUT" | tail -n 60)

    # Cầu dao (b): lỗi test giống hệt vòng trước
    if [ "$TEST_OK" -eq 0 ]; then
      SIG=$(test_signature "$TEST_OUT")
      if [ -n "$PREV_SIG" ] && [ "$SIG" = "$PREV_SIG" ]; then
        T_END[N]=$(date +%s)
        stop 2 "Cầu dao: lỗi test ở Task $N lần $TRY giống hệt lần trước — agent đang lặp lại, dừng sớm. Xem $LOG_DIR/task$N-try$TRY-test.log"
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
      || { T_END[N]=$(date +%s); stop 4 "Không gọi được Claude để review Task $N, xem $REVIEW_OUT"; }

    VERDICT=$(cat "$REVIEW_OUT")
    FIRST=$(printf '%s' "${VERDICT%%$'\n'*}" | tr -d '[:space:]*#')

    if [ "$FIRST" = "PASS" ] && [ "$TEST_OK" -eq 1 ]; then
      rm -f REVIEW.md
      git add -A && git commit -qm "Task $N" --allow-empty
      T_END[N]=$(date +%s); T_STATUS[N]="PASS"
      echo "✅ Task $N đạt"
      break
    fi

    printf '%s\n' "$VERDICT" | tail -n +2 > REVIEW.md
    if [ "$TEST_OK" -eq 0 ]; then printf '\n- Tests are FAILING (last lines):\n%s\n' "$TEST_OUT" >> REVIEW.md; fi
    echo "❌ Task $N chưa đạt (xem REVIEW.md)"

    if [ "$TRY" -eq "$MAX_TRIES" ]; then
      T_END[N]=$(date +%s)
      stop 1 "Task $N thất bại sau $MAX_TRIES lần. Xem REVIEW.md và $LOG_DIR/"
    fi
    PROMPT="Task $N is not done yet. Read REVIEW.md and PLAN.md, fix exactly the issues listed for Task $N, and do not work on other tasks. Re-run: $TEST_CMD. Update PROGRESS.md."
  done
done

STOP_REASON="Hoàn thành cả $TOTAL task"
notify "Xong cả $TOTAL task 🎉"
echo "🎉 Xong $TOTAL task trên branch $BRANCH. Log ở $LOG_DIR/"
echo "   Gộp vào nhánh chính:  git checkout main && git merge $BRANCH"
