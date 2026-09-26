#!/bin/bash
# auto.sh — Claude lên plan & review, Gemini CLI (hoặc Antigravity CLI) viết code.
# Cách dùng:   ./auto.sh "mô tả dự án"
# Tuỳ chọn:    CODER=agy MAX_TRIES=5 ./auto.sh "..."
# Nếu PLAN.md đã có sẵn thì bỏ qua bước lập plan và làm tiếp theo plan đó.

set -euo pipefail

CODER="${CODER:-agy}"         # Antigravity CLI (quyền lấy từ ~/.gemini/config/config.json)
MAX_TRIES="${MAX_TRIES:-3}"   # số vòng sửa tối đa cho mỗi task
LOG_DIR=".auto-logs"

notify() { osascript -e "display notification \"$1\" with title \"auto.sh\"" 2>/dev/null || true; }
need()   { command -v "$1" >/dev/null || { echo "❌ Thiếu '$1'. $2"; exit 1; }; }

need git    "Cài: xcode-select --install"
need claude "Cài: curl -fsSL https://claude.ai/install.sh | bash"
need "$CODER" "Cài Antigravity CLI (agy) trước"

if [ ! -f PLAN.md ] && [ $# -lt 1 ]; then
  echo "Cách dùng: ./auto.sh \"mô tả dự án\""; exit 1
fi
mkdir -p "$LOG_DIR"
grep -qx "$LOG_DIR/" .gitignore 2>/dev/null || echo "$LOG_DIR/" >> .gitignore
grep -qx "REVIEW.md" .gitignore 2>/dev/null || echo "REVIEW.md" >> .gitignore
git rm -q --cached --ignore-unmatch REVIEW.md 2>/dev/null || true

# ---- Git: làm trên branch riêng để dễ bỏ nếu kết quả tệ ----
[ -d .git ] || git init -q
git add -A && git commit -qm "Trước khi chạy auto.sh" --allow-empty
BRANCH="auto/$(date +%Y%m%d-%H%M%S)"
git checkout -qb "$BRANCH"
echo "🌿 Đang làm trên branch $BRANCH"

# ---- Bước 1: Claude viết plan ----
if [ ! -f PLAN.md ]; then
  echo "🧠 Claude đang viết PLAN.md..."
  claude -p "Viết file PLAN.md cho dự án sau: $1

Yêu cầu định dạng BẮT BUỘC:
- Có một dòng bắt đầu bằng 'TEST_CMD: ' theo sau là MỘT lệnh shell chạy toàn bộ test (ví dụ: TEST_CMD: npm test).
- Mỗi task là một heading dạng '## Task N: tên task' (N từ 1, liên tục).
- Mỗi task nhỏ, làm xong trong một lần chạy agent; ghi rõ file tạo/sửa và acceptance criteria kiểm chứng được bằng test.
- Task 1 là dựng khung dự án và cấu hình test để TEST_CMD chạy được.
- Viết để một coding agent khác làm theo mà không cần hỏi lại." \
    --permission-mode acceptEdits --allowedTools "Read,Write,Glob,Grep" \
    > "$LOG_DIR/plan.log" 2>&1
  [ -f PLAN.md ] || { echo "❌ Claude không tạo được PLAN.md, xem $LOG_DIR/plan.log"; exit 1; }
  git add -A && git commit -qm "PLAN.md"
fi

TEST_CMD=$(grep -m1 '^TEST_CMD:' PLAN.md | sed 's/^TEST_CMD:[[:space:]]*//' || true)
TEST_CMD="${TEST_CMD:-echo 'Chưa có lệnh test'}"
TOTAL=$(grep -cE '^## Task [0-9]+' PLAN.md || true)
[ "$TOTAL" -gt 0 ] || { echo "❌ PLAN.md không có heading '## Task N'"; exit 1; }
echo "📋 $TOTAL task — lệnh test: $TEST_CMD"

# ---- Bước 2: vòng lặp code → test → review ----
# agy headless tự từ chối mọi lệnh ngoài allowlist trong ~/.gemini/config/config.json và dừng luôn cả lượt
RULES="Quy tắc chạy lệnh (bắt buộc, lệnh vi phạm sẽ bị từ chối và bạn bị dừng): chỉ dùng git, python3, .venv/bin/python, .venv/bin/pip, ls, mkdir, which; mỗi lần chỉ chạy MỘT lệnh, không nối lệnh bằng ; && || | hay \$(...); không dùng cd, rm, cat, echo. Tạo/sửa file bằng công cụ ghi file, đọc file bằng công cụ đọc file."
for N in $(seq 1 "$TOTAL"); do
  PROMPT="Đọc PLAN.md và làm DUY NHẤT Task $N. Không làm các task khác, không sửa PLAN.md. Sau khi code xong chạy: $TEST_CMD và sửa cho đến khi pass. Ghi tóm tắt việc đã làm vào PROGRESS.md. $RULES"

  for TRY in $(seq 1 "$MAX_TRIES"); do
    echo "▶️  Task $N/$TOTAL — lần $TRY"
    "$CODER" -p "$PROMPT" < /dev/null > "$LOG_DIR/task$N-try$TRY-code.log" 2>&1 || true

    # Dừng sớm nếu agent không đổi file nào (thường do bị từ chối quyền / lỗi đăng nhập)
    if [ -z "$(git status --porcelain)" ]; then
      notify "Agent không đổi file nào ở Task $N"
      echo "⛔ Agent không thay đổi file nào (Task $N, lần $TRY). Xem $LOG_DIR/task$N-try$TRY-code.log"
      exit 2
    fi

    # Script tự chạy test, không tin lời báo cáo của agent
    if TEST_OUT=$(bash -c "$TEST_CMD" 2>&1); then TEST_OK=1; else TEST_OK=0; fi
    TEST_OUT=$(echo "$TEST_OUT" | tail -n 80)

    git add -A
    DIFF=$(git diff --cached HEAD | head -c 60000)

    echo "🔍 Claude đang review..."
    VERDICT=$( {
      echo "=== PLAN.md ==="; cat PLAN.md
      echo; echo "=== KẾT QUẢ TEST (lệnh: $TEST_CMD, pass=$TEST_OK) ==="; echo "$TEST_OUT"
      echo; echo "=== GIT DIFF CỦA TASK $N ==="; echo "$DIFF"
    } | claude -p "Bạn là reviewer nghiêm khắc. Review Task $N theo acceptance criteria trong PLAN.md, dựa trên kết quả test và diff ở trên. Kiểm tra cả bug, lỗ hổng bảo mật, edge case và chỗ lệch khỏi plan.
Dòng ĐẦU TIÊN chỉ ghi đúng một từ: PASS hoặc FAIL.
Nếu FAIL, các dòng sau là checklist lỗi cụ thể (file, vị trí, cách sửa) để coding agent làm theo." 2>&1 || echo "FAIL
Không gọi được Claude để review.")

    echo "$VERDICT" > "$LOG_DIR/task$N-try$TRY-review.md"
    FIRST=$(echo "$VERDICT" | head -n1 | tr -d '[:space:]*#')

    if [ "$FIRST" = "PASS" ] && [ "$TEST_OK" -eq 1 ]; then
      rm -f REVIEW.md
      git add -A && git commit -qm "Task $N" --allow-empty
      echo "✅ Task $N đạt"
      break
    fi

    echo "$VERDICT" | tail -n +2 > REVIEW.md
    [ "$TEST_OK" -eq 0 ] && printf '\n- Test đang FAIL:\n%s\n' "$TEST_OUT" >> REVIEW.md
    echo "❌ Task $N chưa đạt (xem REVIEW.md)"

    if [ "$TRY" -eq "$MAX_TRIES" ]; then
      notify "Task $N thất bại sau $MAX_TRIES lần, cần bạn xem"
      echo "⛔ Dừng tại Task $N. Xem REVIEW.md và $LOG_DIR/"
      exit 1
    fi
    PROMPT="Task $N chưa đạt. Đọc REVIEW.md và PLAN.md, sửa đúng các lỗi được liệt kê cho Task $N, không làm task khác. Chạy lại: $TEST_CMD. $RULES"
  done
done

notify "Xong cả $TOTAL task 🎉"
echo "🎉 Xong $TOTAL task trên branch $BRANCH. Log ở $LOG_DIR/"
echo "   Gộp vào nhánh chính:  git checkout main && git merge $BRANCH"
