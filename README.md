# autowf — một agent lên plan, một agent viết code, một agent review

**autowf** là một skill (cho Claude Code, Codex hoặc Antigravity) kèm theo script `auto.sh`. Nó tự động làm một dự án phần mềm theo từng task:

1. **Planner** (mặc định Claude Opus 5.5) viết `PLAN.md`: chia dự án thành các task nhỏ, mỗi task có tiêu chí nghiệm thu kiểm chứng được bằng test.
2. **Coder** (mặc định Codex CLI) viết code cho từng task.
3. Script **tự chạy test**, không tin lời báo cáo của agent.
4. **Reviewer** (mặc định Claude Sonnet 5.5) review diff và kết quả test, trả về PASS hoặc FAIL. Khi FAIL, coder sửa theo `REVIEW.md` rồi test và review lại.
5. Khi PASS, script commit `Task N: <tiêu đề>` và chuyển sang task tiếp theo.

Mỗi harness (công cụ bạn dùng để gọi skill) có một bản skill riêng, với bộ agent và hướng dẫn hợp với nó. Tất cả dùng chung một script lõi:

| Harness | Thư mục skill | Plan | Code | Review | Khi nào dùng |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Claude Code | `.claude/skills/autowf/` | Claude Opus 5.5 | Codex | Claude Sonnet 5.5 | Có gói Claude trả phí, cần chất lượng cao nhất |
| Codex, Antigravity | `.agents/skills/autowf/` | Codex | Antigravity (`agy`, Gemini) | Codex (`luna`) | Không trả phí Claude, dùng hạn mức miễn phí |

```
core/auto.sh                      # script lõi dùng chung (một bản duy nhất)
.claude/skills/autowf/            # skill cho Claude Code: SKILL.md + defaults.env (bộ agent) + scripts/auto.sh → core
.agents/skills/autowf/            # skill cho Codex và Antigravity (cả hai đều đọc .agents/skills)
versions/v1/autowf/               # v1: bản Claude Code đầu tiên, giữ nguyên
```

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
- **Commit chỉ mang tên người viết:** mọi commit dùng tác giả trong `GIT_USER_NAME`/`GIT_USER_EMAIL` (nếu đặt) hoặc `git config user.name/user.email`, không có `Co-Authored-By` của Claude, ChatGPT/Codex, Copilot hay công cụ nào khác. Script dừng nếu chưa đặt tác giả hoặc tác giả trông như AI/bot, cố định tác giả cho cả lần chạy (agent đổi `git config` cũng không ảnh hưởng), và tự bỏ trailer `Co-authored-by` / dòng "Generated with ..." mà hook hay công cụ ngoài chèn vào.
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
- **Đổi agent từng vai trò:** `PLANNER`, `CODER`, `REVIEWER` nhận `claude`, `codex`, `gemini` hoặc `agy`; model qua `PLAN_MODEL`, `CODER_MODEL`, `REVIEW_MODEL`. Đặt trong `.autowf.env` của repo dự án để ghi đè bộ agent của skill (`defaults.env`). Reviewer chỉ được đọc: nếu nó sửa file thì thay đổi bị bỏ. Có thể đặt agent dự phòng `FALLBACK_CODER` khi coder lỗi đăng nhập.
- **Tác giả commit:** `GIT_USER_NAME` / `GIT_USER_EMAIL` đặt tác giả cho mọi commit; để trống thì dùng `git config`.

---

## Cài đặt

### 1. Yêu cầu

- `git` và `bash`, trên Linux hoặc macOS.
- Các agent mà bản skill của bạn dùng, đã đăng nhập: bản Claude Code cần `claude` + `codex`; bản Codex/Antigravity cần `codex` + `agy`.
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

### 2. Cài skill — chọn phiên bản và harness

| | v1 | v2 |
| :--- | :--- | :--- |
| Harness | Chỉ Claude Code | Claude Code, Codex hoặc Antigravity |
| Agent | Cố định: Claude Opus plan, Codex code, Claude Sonnet review | Theo harness (bảng ở đầu trang); đổi được từng vai trò qua `.autowf.env` |
| Tác giả commit | `git config` | `GIT_USER_NAME`/`GIT_USER_EMAIL` hoặc `git config`; không bao giờ có `Co-authored-by` của AI |
| Hỏi người dùng | Duyệt plan | Tối đa hai lần: xin cài agent thiếu, duyệt plan (bỏ được) |
| Khi nào chọn | Muốn ổn định, ít thành phần, ít lỗi hơn | Dùng Codex/Antigravity, không có gói Claude trả phí, hoặc muốn trộn agent |

```bash
./install.sh                          # hỏi chọn phiên bản và harness
./install.sh 1                        # v1 cho Claude Code → ~/.claude/skills/autowf
./install.sh 2 claude                 # v2 cho Claude Code → ~/.claude/skills/autowf
./install.sh 2 codex                  # v2 cho Codex → ~/.agents/skills/autowf
./install.sh 2 antigravity            # v2 cho Antigravity → ~/.gemini/antigravity-cli/skills/autowf (CLI)
                                      #                       và ~/.gemini/config/skills/autowf (IDE / 2.0)
./install.sh 2 claude codex           # nhiều harness cùng lúc
./install.sh 2 codex --project ../du-an-cua-toi   # chỉ cho một repo → ../du-an-cua-toi/.agents/skills/autowf
```

Bản đang cài (nếu có) được giữ lại thành `autowf.bak-<thời gian>`. Phiên bản đang cài ghi trong file `VERSION`
của skill. Nhờ Claude Code cài ("cài skill autowf") thì Claude sẽ hỏi bạn chọn phiên bản và harness.

Trong chính repo này, Claude Code, Codex và Antigravity đều dùng sẵn v2, không cần cài.

### 3. Kiểm tra

Chạy trong repo dự án đích:

```bash
~/.claude/skills/autowf/scripts/auto.sh --check       # bản Claude Code (bản Codex: ~/.agents/skills/autowf/...)
```

---

## Cách dùng

### Qua skill (khuyên dùng)

```
/autowf Ứng dụng todo dòng lệnh bằng Python, lưu JSON, test bằng pytest     # Claude Code, Antigravity CLI
$autowf Ứng dụng todo dòng lệnh bằng Python, lưu JSON, test bằng pytest     # Codex
```

Agent điều phối sẽ:
1. Kiểm tra các agent cần dùng và trạng thái git; chỉ hỏi khi phải cài agent còn thiếu.
2. Để planner viết `PLAN.md`, tóm tắt các task rồi hỏi một câu: chạy luôn hay sửa (nói "chạy luôn" từ đầu thì bỏ qua bước này).
3. Chạy pipeline ở chế độ nền và báo kết quả. Khi gặp plan-gap, Claude hỏi bạn quyết, ghi quyết định vào PLAN.md rồi chạy tiếp.

Nếu repo đã có `PLAN.md`, chỉ cần gõ `/autowf` để chạy hoặc chạy tiếp.

### Chạy script trực tiếp

```bash
./auto.sh --plan-only "mô tả dự án"   # planner viết + commit PLAN.md rồi dừng để bạn duyệt
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

Đặt biến trong file `.autowf.env` ở gốc repo đích, hoặc qua biến môi trường. Thứ tự ưu tiên: mặc định của script < `defaults.env` của skill < `.autowf.env` < biến môi trường.

| Biến | Mặc định | Ý nghĩa |
| :--- | :--- | :--- |
| `PLANNER` | theo skill | Agent viết PLAN.md: `claude` \| `codex` \| `gemini` \| `agy` |
| `CODER` | theo skill | Coding agent: `codex` \| `claude` \| `agy` \| `gemini` |
| `REVIEWER` | theo skill | Agent review: `claude` \| `codex` \| `gemini` \| `agy` |
| `PLAN_MODEL` / `CODER_MODEL` / `REVIEW_MODEL` | theo skill | Model của từng vai trò; rỗng = mặc định của agent. Đổi agent của một vai trò mà không đặt model thì model mặc định của vai trò đó bị bỏ |
| `GIT_USER_NAME` / `GIT_USER_EMAIL` | *(rỗng)* | Tác giả mọi commit; rỗng = `git config user.name/email`. Không được trông như AI/bot |
| `FALLBACK_CODER` | *(rỗng)* | Agent dự phòng khi `CODER` lỗi đăng nhập/quyền |
| `CODEX_MODEL` | *(rỗng)* | Model của Codex khi làm coder (biến cũ, dùng khi `CODER_MODEL` rỗng) |
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
CODER=claude
GIT_USER_NAME="Nguyen Van A"
GIT_USER_EMAIL=a@example.com
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
| `1` | Task FAIL sau khi hết số vòng sửa (xem `REVIEW.md` và `.auto-logs/task<N>-*`), hoặc chưa có tác giả commit hợp lệ |
| `2` | Cầu dao: agent không sửa file, rời branch, viết lại lịch sử, lệnh bị từ chối liên tục… |
| `3` | Chờ hết hạn mức quá `MAX_WAIT_HOURS` |
| `4` | Không gọi được reviewer |
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
