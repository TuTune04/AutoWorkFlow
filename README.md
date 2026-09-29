# autowf — Opus lên plan, Codex viết code, Sonnet review

**autowf** là một skill cho Claude Code kèm theo script `auto.sh`. Nó tự động làm một dự án phần mềm theo từng task:

1. **Claude Opus 5.5** viết `PLAN.md`: chia dự án thành các task nhỏ, mỗi task có tiêu chí nghiệm thu kiểm chứng được bằng test.
2. **Codex CLI** viết code cho từng task.
3. Script **tự chạy test**, không tin lời báo cáo của agent.
4. **Claude Sonnet 5.5** review diff và kết quả test, trả về PASS hoặc FAIL. Khi FAIL, Codex sửa theo `REVIEW.md` rồi test và review lại.
5. Khi PASS, script commit `Task N: <tiêu đề>` và chuyển sang task tiếp theo.

Mọi thứ chạy trên một branch `auto/*` riêng, nên nhánh chính không bị đụng tới cho đến khi bạn merge.

---

## Tính năng

**Luồng làm việc**
- **Duyệt plan trước khi code:** `--plan-only` chỉ viết và commit `PLAN.md`, để bạn đọc và sửa trước khi Codex bắt đầu.
- **Chạy tiếp được:** task đã có commit `Task N` sẽ được bỏ qua, nên chạy lại `auto.sh` là làm tiếp từ chỗ dừng.
- **Dừng gọn:** chạy `auto.sh --stop-after` từ một terminal khác thì pipeline dừng ngay sau khi task hiện tại xong.
- **Nhận task làm tay:** sau khi bạn tự làm một task, `auto.sh --adopt N` chạy test rồi commit nó thành `Task N`.
- **Số vòng sửa có giới hạn:** tối đa `MAX_TRIES` vòng sửa cho mỗi task. Nếu vòng cuối vẫn đang tiến triển, script cho thêm tối đa `MAX_EXTRA_TRIES` vòng.
- **Hỏi lại khi plan thiếu:** khi PLAN.md thiếu một quyết định, reviewer báo *plan-gap* và pipeline dừng để người quyết, không để agent tự đoán.

**An toàn**
- **Bảo vệ lịch sử git:** agent tự commit thì thay đổi được đưa về lại cây làm việc. Agent đổi branch, viết lại lịch sử hoặc stash thì pipeline dừng.
- **Giữ nguyên plan đã duyệt:** agent sửa `PLAN.md` thì file bị khôi phục về bản đã duyệt.
- **Preflight:** trước khi chạy, script kiểm tra agent đã đăng nhập, ghi được file, và git hook (pre-commit, husky…) cho commit qua.
- **Cầu dao:** pipeline dừng khi agent không sửa file nào hoặc liên tục chạy lệnh bị từ chối. Script phân loại lỗi (AUTH, PERMISSION, QUOTA, TIMEOUT, CRASH…) và in cách xử lý.

**Chạy lâu không cần trông**
- **Tự chờ hết hạn mức:** khi Claude hoặc Codex chạm usage limit, script đọc giờ reset rồi ngủ tới lúc đó, tối đa `MAX_WAIT_HOURS`.
- **Tự thử lại khi lỗi mạng:** thử lại sau 1, 2 rồi 4 phút.
- **Chờ dịch vụ ngoài:** nếu test cần dịch vụ như database, đặt lệnh kiểm tra vào `REQUIRE_CMD`; script chờ dịch vụ sẵn sàng mà không tính là một lần thử.
- **Thông báo:** trên macOS và lên điện thoại qua [ntfy](https://ntfy.sh) khi dừng, khi xong hoặc khi phải chờ.
- **Nhật ký:** tiến độ ghi vào `.auto-logs/run.log`, tóm tắt vào `.auto-logs/summary.md`. Góp ý không chặn của reviewer được gom vào `.auto-logs/nits.md`, còn tóm tắt từng task được nối vào `PROGRESS.md`.

**Linh hoạt**
- **Đổi coding agent:** `CODER=codex` (mặc định), `agy` hoặc `gemini`. Có thể đặt agent dự phòng `FALLBACK_CODER` khi agent chính lỗi đăng nhập.
- **Đổi model:** model viết plan và model review chỉnh được qua `PLAN_MODEL` và `REVIEW_MODEL`.

---

## Cài đặt

### 1. Yêu cầu

- `git` và `bash`, trên Linux hoặc macOS.
- **Claude Code CLI** (`claude`), đã đăng nhập:
  ```bash
  curl -fsSL https://claude.ai/install.sh | bash   # hoặc: npm i -g @anthropic-ai/claude-code
  claude                                           # đăng nhập lần đầu
  ```
- **Codex CLI** (`codex`), đã đăng nhập:
  ```bash
  npm i -g @openai/codex
  codex login
  codex login status                               # kiểm tra
  ```

### 2. Cài skill

Skill nằm ở `.claude/skills/autowf/`, gồm `SKILL.md` và `scripts/auto.sh`.

- **Chỉ dùng trong repo này:** không cần làm gì thêm. Claude Code tự nhận skill trong `.claude/skills/`.
- **Dùng cho mọi dự án:** chép skill vào thư mục skill của người dùng.
  ```bash
  cp -r .claude/skills/autowf ~/.claude/skills/
  ```

### 3. Kiểm tra

Chạy trong repo dự án đích:

```bash
~/.claude/skills/autowf/scripts/auto.sh --check       # hoặc ./auto.sh --check trong repo này
```

---

## Cách dùng

### Qua Claude Code (khuyên dùng)

```
/autowf Ứng dụng todo dòng lệnh bằng Python, lưu JSON, test bằng pytest
```

Claude sẽ:
1. Kiểm tra `claude`, `codex` và trạng thái git.
2. Để Opus 5.5 viết `PLAN.md`, tóm tắt các task rồi chờ bạn duyệt hoặc sửa.
3. Chạy pipeline ở chế độ nền và báo kết quả. Khi gặp plan-gap, Claude hỏi bạn quyết, ghi quyết định vào PLAN.md rồi chạy tiếp.

Nếu repo đã có `PLAN.md`, chỉ cần gõ `/autowf` để chạy hoặc chạy tiếp.

### Chạy script trực tiếp

```bash
./auto.sh --plan-only "mô tả dự án"   # Opus viết + commit PLAN.md rồi dừng để bạn duyệt
./auto.sh                             # chạy (hoặc chạy tiếp) theo PLAN.md
./auto.sh "mô tả dự án"               # viết plan rồi chạy luôn, không dừng để duyệt
./auto.sh --stop-after                # (từ terminal khác) dừng sau task hiện tại; huỷ: --no-stop-after
./auto.sh --adopt 3                   # nhận Task 3 bạn đã làm tay
./auto.sh --preflight                 # chỉ kiểm tra quyền của agent và git hook
./auto.sh --new-branch                # tạo branch auto/* mới thay vì làm tiếp branch hiện tại
./auto.sh --notify-test               # gửi thử thông báo
./auto.sh --help                      # xem đầy đủ
```

Repo phải sạch, tức không còn thay đổi chưa commit, trước khi chạy. Khi xong, merge branch `auto/*` vào nhánh chính.

### Định dạng PLAN.md

```markdown
TEST_CMD: .venv/bin/python -m pytest -q

## Tổng quan
Stack, cấu trúc thư mục, quy ước… (reviewer chỉ thấy phần này + đúng task đang review)

## Task 1: Dựng khung dự án và cấu hình test
File tạo/sửa, đặc tả, acceptance criteria…

## Task 2: ...
```

- **`TEST_CMD`:** đúng một dòng, là lệnh chạy toàn bộ test.
- **Heading task:** dạng `## Task N: <tiêu đề>`, đánh số liên tục từ 1.
- **Sửa nội dung một task,** chẳng hạn để ghi quyết định cho plan-gap, không làm các task đã commit bị làm lại. Còn **đổi danh sách heading** thì được coi là plan mới.

---

## Cấu hình

Đặt biến trong file `.autowf.env` ở gốc repo đích, hoặc qua biến môi trường. Biến môi trường được ưu tiên hơn file.

| Biến | Mặc định | Ý nghĩa |
| :--- | :--- | :--- |
| `PLAN_MODEL` | `claude-opus-5-5` | Model Claude viết PLAN.md |
| `REVIEW_MODEL` | `claude-sonnet-5-5` | Model Claude review |
| `CODER` | `codex` | Coding agent: `codex` \| `agy` \| `gemini` |
| `FALLBACK_CODER` | *(rỗng)* | Agent dự phòng khi `CODER` lỗi đăng nhập/quyền |
| `CODEX_MODEL` | *(rỗng)* | Model của Codex; rỗng = mặc định của Codex CLI |
| `CODEX_SANDBOX` | `workspace-write` | Sandbox của `codex exec`: `workspace-write` \| `danger-full-access` |
| `CODEX_NETWORK` | `1` | Cho Codex dùng mạng trong sandbox (cài package); `0` = chặn |
| `CODEX_ARGS` | *(rỗng)* | Tham số thêm cho `codex exec` |
| `MAX_TRIES` | `3` | Số vòng sửa tối đa mỗi task |
| `MAX_EXTRA_TRIES` | `2` | Số vòng thêm khi vòng cuối còn tiến triển |
| `MAX_WAIT_HOURS` | `6` | Tổng thời gian tối đa chờ hết hạn mức |
| `DIFF_LIMIT` | `120000` | Số byte diff tối đa gửi cho reviewer |
| `REQUIRE_CMD` | *(rỗng)* | Lệnh kiểm tra dịch vụ ngoài, vd. `docker compose exec -T postgres pg_isready` |
| `REQUIRE_WAIT_MINS` | `30` | Thời gian tối đa chờ dịch vụ |
| `NTFY_TOPIC` / `NTFY_SERVER` | *(rỗng)* / `https://ntfy.sh` | Gửi thông báo lên điện thoại (đặt trong shell profile, đừng commit topic) |

Ví dụ `.autowf.env`:

```bash
MAX_TRIES=5
FALLBACK_CODER=gemini
REQUIRE_CMD="docker compose exec -T postgres pg_isready"
```

> **Codex trong container:** sandbox Linux của Codex có thể không chạy được trong Docker hoặc Codespaces. Nếu log báo lỗi sandbox, bạn có thể đặt `CODEX_ARGS="--dangerously-bypass-approvals-and-sandbox"`. Cờ này **bỏ mọi giới hạn** của Codex, nên chỉ dùng trong môi trường cô lập.

---

## Mã thoát

| Mã | Ý nghĩa |
| :--- | :--- |
| `0` | Xong hết các task, hoặc đã dừng theo `--stop-after` |
| `1` | Task FAIL sau khi hết số vòng sửa; xem `REVIEW.md` và `.auto-logs/task<N>-*` |
| `2` | Cầu dao: agent không sửa file, rời branch, viết lại lịch sử, lệnh bị từ chối liên tục… |
| `3` | Chờ hết hạn mức quá `MAX_WAIT_HOURS` |
| `4` | Không gọi được Claude để review |
| `5` | Preflight chưa đạt (đăng nhập, quyền ghi file, git hook) |
| `6` | Dịch vụ trong `REQUIRE_CMD` không sẵn sàng |
| `7` | plan-gap: PLAN.md thiếu một quyết định, cần người quyết |

---

## Dự án mẫu: `todo-cli`

Mã nguồn trong `todo/` và `tests/` là một ứng dụng todo dòng lệnh do chính pipeline này làm ra, theo `PLAN.md` (7 task) và `PROGRESS.md`. Ứng dụng viết bằng Python ≥ 3.10, chỉ dùng thư viện chuẩn, lưu dữ liệu vào file JSON bằng cách ghi nguyên tử.

```bash
python3 -m venv .venv && .venv/bin/python -m pip install -q "pytest>=7"
.venv/bin/python -m todo add Mua sữa          # add | list [--pending|--done] | done | undone | edit | delete | clear
.venv/bin/python -m todo list
.venv/bin/python -m pytest -q
```

File dữ liệu được chọn theo thứ tự: `--file PATH`, rồi biến môi trường `TODO_FILE`, cuối cùng là `~/.todo.json`.
