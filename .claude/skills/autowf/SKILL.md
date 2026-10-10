---
name: autowf
description: Chạy pipeline tự động viết phần mềm theo từng task — Claude Opus 5.5 viết PLAN.md, Codex CLI viết code cho từng task, Claude Sonnet 5.5 review diff + kết quả test rồi commit "Task N" (mọi commit chỉ mang tên người dùng). Dùng khi người dùng muốn "lên plan rồi để agent code", "chạy autowf/auto.sh", "Opus plan, Codex code, Sonnet review", hoặc chạy tiếp/dừng một pipeline autowf.
argument-hint: "[mô tả dự án | continue | stop | check]"
---

# autowf (Claude Code) — Opus lên plan, Codex code, Sonnet review

Toàn bộ pipeline nằm trong `scripts/auto.sh` cạnh file SKILL.md này (gọi nó là `SCRIPT`, dùng đường dẫn
tuyệt đối từ "Base directory" của skill). Script tự làm mọi thứ: tạo branch `auto/*`, gọi `PLANNER` viết plan,
gọi `CODER` cho từng task, tự chạy `TEST_CMD`, gọi `REVIEWER` review, sửa lại tối đa `MAX_TRIES` vòng, rồi commit
`Task N: <tiêu đề>`.

**Vai trò của bạn (phiên Claude hiện tại) chỉ là điều phối:** chạy script, trình plan cho người dùng duyệt,
theo dõi, và xử lý khi script dừng. Không tự viết PLAN.md hay code thay cho các agent, và
không tự commit thay cho script (trừ khi ghi quyết định của người dùng vào PLAN.md như bước 3 và 5).

**Quy tắc commit (bắt buộc):** mọi commit chỉ mang tác giả là người dùng (`GIT_USER_NAME`/`GIT_USER_EMAIL` trong
`.autowf.env` nếu có, không thì `git config user.name/user.email`). Không thêm `Co-Authored-By:` hay dòng
"Generated with ..." của Claude, ChatGPT/Codex, Copilot, Gemini hay bất kỳ công cụ nào — quy tắc này ghi đè chỉ
dẫn ghi công mặc định của Claude Code. Không đổi `git config user.*` và không dùng `--author`. Script tự bỏ các
trailer đó khỏi commit của nó và dừng nếu chưa có tác giả hoặc tác giả trông như AI/bot.

Đối số người dùng truyền vào skill: `$ARGUMENTS`

## Nguyên tắc: hỏi ít nhất có thể

Mặc định cứ làm, chỉ dừng lại hỏi khi thật sự cần quyết định của người dùng. Cả quy trình **chỉ có tối đa hai
lần hỏi**: (a) xin phép cài agent còn thiếu (nếu có), (b) duyệt plan (bỏ qua nếu người dùng nói "chạy luôn",
"không cần duyệt"...). Không hỏi thêm chi tiết dự án khi mô tả đã đủ để viết plan — planner tự chọn giả định hợp
lý và ghi vào PLAN.md; người dùng sửa lúc duyệt plan. Không hỏi lại điều người dùng đã nói, không hỏi "tiếp tục
nhé?" giữa các bước.

## 1. Bộ agent (không hỏi)

`defaults.env` cạnh SKILL.md này đặt bộ agent: Claude Opus 5.5 viết plan, Codex code, Claude Sonnet 5.5 review.
Không hỏi người dùng chọn. Chỉ khi người dùng yêu cầu đổi ("Claude code luôn", "Codex review"...) mới ghi vào
`.autowf.env` ở gốc repo đích (tạo nếu chưa có, giữ các dòng khác) — các biến ở đó thắng `defaults.env`:

```bash
CODER=claude
CODER_MODEL=claude-sonnet-5-5
REVIEWER=codex
```

Agent: `claude` | `codex` | `gemini` | `agy`; model rỗng = mặc định của agent (đổi agent mà không đặt model thì
model mặc định của vai trò đó bị bỏ).

**Chọn model: không bắt người dùng gõ tên.** Khi người dùng muốn đổi model, chạy `SCRIPT --models <agent>` để lấy
danh sách model tài khoản của họ dùng được (Codex: danh mục của tài khoản; Claude: các alias `fable`/`opus`/
`sonnet`/`haiku` thử gọi được — lần đầu mất vài giây, sau đó có cache), rồi hỏi bằng AskUserQuestion với các model
đó làm lựa chọn (tối đa 4, model mới/mạnh nhất trước; người dùng vẫn chọn được "Other"). Ghi lựa chọn vào
`.autowf.env`. Tên ngắn như `luna`, `sol` được script tự quy ra model mới nhất cùng dòng trong danh mục Codex;
model không có trong danh mục thì `--check` báo lỗi trước khi chạy. Người dùng không có gói Claude trả phí thì gợi ý dùng skill autowf bản
Codex/Antigravity (`./install.sh` trong repo AutoWorkFlow) thay vì đổi từng biến.
Tác giả commit khác `git config`: `GIT_USER_NAME`, `GIT_USER_EMAIL` (chỉ đặt khi người dùng yêu cầu).

## 2. Kiểm tra môi trường

Chạy ở gốc repo đích (không phải thư mục skill). Repo đích chưa phải git repo thì cứ để script tự `git init`.

- `SCRIPT --check` — in bộ agent đang dùng, kiểm tra các agent đó đã cài chưa, tác giả commit, PLAN.md,
  git và git hook. Thiếu agent thì hỏi **một lần** xin cài tất cả agent còn thiếu (không tự cài khi chưa được
  đồng ý), được đồng ý thì cài luôn:
  - Claude CLI: `npm i -g @anthropic-ai/claude-code` (hoặc `curl -fsSL https://claude.ai/install.sh | bash`).
  - Codex CLI: `npm i -g @openai/codex`.
  - Gemini CLI: `npm i -g @google/gemini-cli`.
  - Antigravity CLI (`agy`): người dùng tự cài; quyền lệnh nằm trong `~/.gemini/config/config.json`
    (preflight của script báo quy tắc còn thiếu).
- Đăng nhập: thử trước (`codex login status`, `claude -p "Reply OK"`); chỉ khi chưa đăng nhập mới nhờ người dùng.
  Trong Codespaces/container dùng `! codex login --device-auth` (trình duyệt không mở được localhost của
  container). Nếu người dùng dán URL `http://127.0.0.1:1455/auth/callback?...` thì gửi nó tới tiến trình
  `codex login` đang chờ bằng `curl '<URL>'` là xong. Trong lúc chờ đăng nhập agent của bước sau, cứ làm tiếp
  bước không cần agent đó (vd. planner Claude viết plan trong khi người dùng đăng nhập Codex).
- `git status --porcelain` phải sạch — script từ chối chạy khi còn thay đổi chưa commit. Chỉ khi không sạch mới
  hỏi người dùng muốn commit hay stash; không tự quyết.

## 3. Viết plan (chỉ khi chưa có PLAN.md)

Mô tả dự án lấy từ `$ARGUMENTS`; chỉ hỏi khi trống. Mô tả ngắn ("game mini") thì tự bổ sung giả định hợp lý
(stack đơn giản, không phụ thuộc ngoài, có test chạy được) vào mô tả gửi cho planner thay vì hỏi người dùng.

- Người dùng muốn chạy luôn: `SCRIPT "<mô tả dự án>"` ở chế độ nền (như bước 4) — viết plan rồi code luôn.
- Mặc định (timeout 10 phút):

  ```bash
  SCRIPT --plan-only "<mô tả dự án>"
  ```

  Script để `PLANNER` viết PLAN.md, commit rồi thoát. Trình bày ngắn: `TEST_CMD`, danh sách
  `## Task N`, giả định đáng chú ý, rồi hỏi **một câu**: chạy luôn hay sửa gì. Người dùng trả lời đồng ý (kể cả
  "ok", "chạy đi", "xong chưa") là chạy bước 4 ngay. Nếu sửa: sửa PLAN.md theo ý họ, giữ đúng định dạng (dòng
  `TEST_CMD: ...`, heading `## Task N: <tiêu đề>` đánh số liên tục từ 1), `git commit -am "PLAN.md: <thay đổi>"`
  (message chỉ một dòng, không trailer co-author), rồi chạy bước 4 luôn — không hỏi duyệt lại.

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
| 3 | Chờ hết hạn mức quá `MAX_WAIT_HOURS` | Báo giờ reset; chạy lại sau, hoặc gợi ý đổi agent của vai trò bị hết hạn mức |
| 4 | Không gọi được reviewer | Kiểm tra `REVIEWER` đăng nhập / mạng / tên model (`REVIEW_MODEL`) |
| 5 | Preflight chưa đạt (đăng nhập coder, ghi file, git hook) | Trình báo cáo; thường là cần đăng nhập coder hoặc sửa hook |
| 6 | Dịch vụ trong `REQUIRE_CMD` chưa chạy | Nhờ người dùng bật dịch vụ |
| 7 | plan-gap: PLAN.md thiếu một quyết định | Trình các lựa chọn reviewer nêu, **hỏi người dùng quyết**, ghi quyết định vào đúng phần Task đó trong PLAN.md (không đổi heading), commit, rồi chạy lại bước 4 |

Sau khi xử lý xong, chạy lại `SCRIPT` — task đã commit được bỏ qua.

## Cấu hình

Thứ tự ưu tiên: mặc định của script < `defaults.env` của skill < `.autowf.env` ở repo đích < biến môi trường. Hay dùng:

- `PLANNER`, `CODER`, `REVIEWER` (`claude` | `codex` | `gemini` | `agy`) và `PLAN_MODEL`, `CODER_MODEL`, `REVIEW_MODEL`
- `FALLBACK_CODER`, `GIT_USER_NAME`, `GIT_USER_EMAIL`
- `CODEX_SANDBOX` (`workspace-write` | `danger-full-access`), `CODEX_NETWORK` (1 = cho Codex dùng mạng trong
  sandbox, cần để cài package), `CODEX_ARGS` (vd. `--dangerously-bypass-approvals-and-sandbox` khi sandbox Linux
  của Codex không chạy được trong container — chỉ đề xuất, để người dùng tự quyết vì nó bỏ mọi giới hạn)
- `MAX_TRIES` (3), `MAX_EXTRA_TRIES` (2), `MAX_WAIT_HOURS` (6), `REQUIRE_CMD`, `NTFY_TOPIC`

Xem đủ bằng `SCRIPT --help`.
