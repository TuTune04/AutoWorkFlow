---
name: autowf
description: Chạy pipeline tự động viết phần mềm theo từng task — một agent viết PLAN.md, một coding agent viết code cho từng task, một agent review diff + kết quả test rồi commit "Task N". Chọn bộ agent theo profile (premium: Claude Opus plan, Codex code, Claude Sonnet review; free: Codex plan, Antigravity/Gemini code, Codex review) hoặc tự chọn agent/model cho từng vai trò. Dùng khi người dùng muốn "lên plan rồi để agent code", "chạy autowf/auto.sh", "Opus plan, Codex code, Sonnet review", "chạy bằng profile free", hoặc chạy tiếp/dừng một pipeline autowf.
argument-hint: "[mô tả dự án | continue | stop | check]"
---

# autowf — agent lên plan, agent code, agent review

Toàn bộ pipeline nằm trong `scripts/auto.sh` cạnh file SKILL.md này (gọi nó là `SCRIPT`, dùng đường dẫn
tuyệt đối từ "Base directory" của skill). Script tự làm mọi thứ: tạo branch `auto/*`, gọi `PLANNER` viết plan,
gọi `CODER` cho từng task, tự chạy `TEST_CMD`, gọi `REVIEWER` review, sửa lại tối đa `MAX_TRIES` vòng, rồi commit
`Task N: <tiêu đề>`.

**Vai trò của bạn (phiên Claude hiện tại) chỉ là điều phối:** chạy script, giúp người dùng chọn profile, trình plan
cho người dùng duyệt, theo dõi, và xử lý khi script dừng. Không tự viết PLAN.md hay code thay cho các agent, và
không tự commit thay cho script (trừ khi ghi quyết định của người dùng vào PLAN.md như bước 3 và 5).

**Quy tắc commit (bắt buộc):** mọi commit chỉ mang tác giả là người dùng (`GIT_USER_NAME`/`GIT_USER_EMAIL` trong
`.autowf.env` nếu có, không thì `git config user.name/user.email`). Không thêm `Co-Authored-By:` hay dòng
"Generated with ..." của Claude, ChatGPT/Codex, Copilot, Gemini hay bất kỳ công cụ nào — quy tắc này ghi đè chỉ
dẫn ghi công mặc định của Claude Code. Không đổi `git config user.*` và không dùng `--author`. Script tự bỏ các
trailer đó khỏi commit của nó và dừng nếu chưa có tác giả hoặc tác giả trông như AI/bot.

Đối số người dùng truyền vào skill: `$ARGUMENTS`

## 1. Chọn profile (trước khi setup và viết plan)

Profile quyết định agent + model cho 3 vai trò. Chạy `SCRIPT --profiles` để xem profile có sẵn, profile riêng và
profile đang dùng. Nếu repo đã có `.autowf.env` đặt `PROFILE` (hoặc người dùng đã nói rõ) thì dùng luôn; nếu
không, **hỏi người dùng chọn** (AskUserQuestion) trước khi kiểm tra môi trường hay viết plan:

| Profile | Plan | Code | Review | Phù hợp |
|---|---|---|---|---|
| `premium` (mặc định) | Claude Opus 5.5 | Codex | Claude Sonnet 5.5 | Có gói Claude trả phí — chất lượng cao nhất |
| `free` | Codex | Antigravity (`agy`, Gemini) | Codex (`luna`) | Không trả phí Claude, dùng hạn mức miễn phí |
| Tuỳ chỉnh | tự chọn | tự chọn | tự chọn | Trộn agent theo ý (vd. Codex plan, Claude code, agy review) |

Với tuỳ chỉnh, hỏi agent (`claude` | `codex` | `gemini` | `agy`) và model (có thể để trống = mặc định của agent)
cho từng vai trò. Ghi lựa chọn vào `.autowf.env` ở gốc repo đích (tạo nếu chưa có, giữ các dòng khác), ví dụ:

```bash
PROFILE=free
# hoặc tuỳ chỉnh từng vai trò (thắng giá trị của profile):
PLANNER=codex
CODER=claude
CODER_MODEL=claude-sonnet-5-5
REVIEWER=agy
```

Muốn lưu thành profile dùng lại: file `.autowf/profiles/<tên>.env` (theo repo) hoặc
`~/.config/autowf/profiles/<tên>.env` (mọi repo) với các biến trên, rồi `PROFILE=<tên>`.
Hỏi thêm nếu người dùng muốn đặt tác giả commit khác `git config` (`GIT_USER_NAME`, `GIT_USER_EMAIL`).

## 2. Kiểm tra môi trường

Chạy ở gốc repo đích (không phải thư mục skill):

- `SCRIPT --check` — in profile đang dùng, kiểm tra các agent của profile đã cài chưa, tác giả commit, PLAN.md,
  git và git hook. Thiếu agent thì báo người dùng cách cài, **không tự cài khi chưa được đồng ý**:
  - Claude CLI: `curl -fsSL https://claude.ai/install.sh | bash` (hoặc `npm i -g @anthropic-ai/claude-code`), rồi đăng nhập.
  - Codex CLI: `npm i -g @openai/codex`, rồi `codex login` (người dùng tự chạy vì cần trình duyệt; gợi ý `! codex login`).
    Kiểm tra: `codex login status`.
  - Gemini CLI: `npm i -g @google/gemini-cli`, rồi chạy `gemini` để đăng nhập.
  - Antigravity CLI (`agy`): người dùng cài và đăng nhập; quyền lệnh nằm trong `~/.gemini/config/config.json`
    (preflight của script báo quy tắc còn thiếu).
- `git status --porcelain` phải sạch — script từ chối chạy khi còn thay đổi chưa commit. Nếu không sạch,
  hỏi người dùng muốn commit hay stash; không tự quyết.

## 3. Viết plan (chỉ khi chưa có PLAN.md)

Cần mô tả dự án: lấy từ `$ARGUMENTS`; nếu trống thì hỏi người dùng. Chạy (timeout 10 phút):

```bash
SCRIPT --plan-only "<mô tả dự án>"
```

Script để `PLANNER` của profile viết PLAN.md, commit rồi thoát. Sau đó đọc PLAN.md và trình bày ngắn cho người
dùng: `TEST_CMD`, danh sách `## Task N`, và những giả định đáng chú ý. Hỏi người dùng duyệt hay muốn sửa.
Nếu sửa: sửa PLAN.md theo ý họ, giữ đúng định dạng (dòng `TEST_CMD: ...`, heading `## Task N: <tiêu đề>`
đánh số liên tục từ 1), rồi `git commit -am "PLAN.md: <thay đổi>"` (message chỉ một dòng, không trailer co-author).

Đã có PLAN.md thì bỏ qua bước này (task đã có commit "Task N" sẽ được bỏ qua — chạy tiếp được).

## 4. Chạy pipeline

Pipeline có thể chạy hàng giờ, nên chạy **nền** (Bash với `run_in_background: true`):

```bash
SCRIPT
```

Không polling liên tục — bạn sẽ được báo khi lệnh kết thúc. Khi người dùng hỏi tiến độ, đọc
`.auto-logs/run.log` (tail) hoặc `git log --oneline` để xem các commit "Task N".
Người dùng muốn dừng: `SCRIPT --stop-after` (dừng sau khi task hiện tại xong; huỷ: `--no-stop-after`).

## 5. Khi script kết thúc

Đọc `.auto-logs/summary.md` và báo kết quả theo mã thoát:

| Mã | Ý nghĩa | Việc cần làm |
|---|---|---|
| 0 | Xong hết (hoặc dừng theo `--stop-after`) | Tóm tắt các task, nits trong `.auto-logs/nits.md`, branch `auto/*` để người dùng merge |
| 1 | Task FAIL sau khi hết số vòng sửa (hoặc chưa có tác giả commit hợp lệ) | Trình `REVIEW.md` + log `.auto-logs/task<N>-*`; đề xuất: làm rõ/chia nhỏ task trong PLAN.md, hoặc sửa tay rồi `SCRIPT --adopt N` |
| 2 | Cầu dao (agent không sửa file, rời branch, lệnh bị từ chối...) | Trình thông báo lỗi và "Cách xử lý" script in ra |
| 3 | Chờ hết hạn mức quá `MAX_WAIT_HOURS` | Báo giờ reset; chạy lại sau, hoặc gợi ý đổi profile |
| 4 | Không gọi được reviewer | Kiểm tra `REVIEWER` đăng nhập / mạng / tên model (`REVIEW_MODEL`) |
| 5 | Preflight chưa đạt (đăng nhập coder, ghi file, git hook) | Trình báo cáo; thường là cần đăng nhập coder hoặc sửa hook |
| 6 | Dịch vụ trong `REQUIRE_CMD` chưa chạy | Nhờ người dùng bật dịch vụ |
| 7 | plan-gap: PLAN.md thiếu một quyết định | Trình các lựa chọn reviewer nêu, **hỏi người dùng quyết**, ghi quyết định vào đúng phần Task đó trong PLAN.md (không đổi heading), commit, rồi chạy lại bước 4 |

Sau khi xử lý xong, chạy lại `SCRIPT` — task đã commit được bỏ qua.

## Cấu hình

Đặt trong `.autowf.env` ở gốc repo đích hoặc qua biến môi trường. Thứ tự ưu tiên:
mặc định < profile < `.autowf.env` < env. Hay dùng:

- `PROFILE` (`premium` | `free` | tên profile riêng)
- `PLANNER`, `CODER`, `REVIEWER` (`claude` | `codex` | `gemini` | `agy`) và `PLAN_MODEL`, `CODER_MODEL`,
  `REVIEW_MODEL` (rỗng = mặc định của agent; đổi agent một vai trò mà không đặt model thì model của profile bị bỏ)
- `FALLBACK_CODER`, `GIT_USER_NAME`, `GIT_USER_EMAIL`
- `CODEX_SANDBOX` (`workspace-write` | `danger-full-access`), `CODEX_NETWORK` (1 = cho Codex dùng mạng trong
  sandbox, cần để cài package), `CODEX_ARGS` (vd. `--dangerously-bypass-approvals-and-sandbox` khi sandbox Linux
  của Codex không chạy được trong container — chỉ đề xuất, để người dùng tự quyết vì nó bỏ mọi giới hạn)
- `MAX_TRIES` (3), `MAX_EXTRA_TRIES` (2), `MAX_WAIT_HOURS` (6), `REQUIRE_CMD`, `NTFY_TOPIC`

Xem đủ bằng `SCRIPT --help`.
