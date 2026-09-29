---
name: autowf
description: Chạy pipeline tự động viết phần mềm theo từng task — Claude Opus 5.5 viết PLAN.md, Codex CLI viết code cho từng task, Claude Sonnet 5.5 review diff + kết quả test rồi commit "Task N". Dùng khi người dùng muốn "lên plan rồi để agent code", "chạy autowf/auto.sh", "Opus plan, Codex code, Sonnet review", hoặc chạy tiếp/dừng một pipeline autowf.
argument-hint: "[mô tả dự án | continue | stop | check]"
---

# autowf — Opus lên plan, Codex code, Sonnet review

Toàn bộ pipeline nằm trong `scripts/auto.sh` cạnh file SKILL.md này (gọi nó là `SCRIPT`, dùng đường dẫn
tuyệt đối từ "Base directory" của skill). Script tự làm mọi thứ: tạo branch `auto/*`, gọi
`claude -p --model claude-opus-5-5` viết plan, gọi `codex exec` cho từng task, tự chạy `TEST_CMD`, gọi
`claude -p --model claude-sonnet-5-5` review, sửa lại tối đa `MAX_TRIES` vòng, rồi commit `Task N: <tiêu đề>`.

**Vai trò của bạn (phiên Claude hiện tại) chỉ là điều phối:** chạy script, trình plan cho người dùng duyệt,
theo dõi, và xử lý khi script dừng. Không tự viết PLAN.md hay code thay cho Opus/Codex, và không tự commit
thay cho script (trừ khi ghi quyết định của người dùng vào PLAN.md như bước 4).

Đối số người dùng truyền vào skill: `$ARGUMENTS`

## 1. Kiểm tra môi trường

Chạy ở gốc repo đích (không phải thư mục skill):

- `command -v claude codex` — thiếu thì báo người dùng cách cài, **không tự cài khi chưa được đồng ý**:
  - Claude CLI: `curl -fsSL https://claude.ai/install.sh | bash` (hoặc `npm i -g @anthropic-ai/claude-code`), rồi đăng nhập.
  - Codex CLI: `npm i -g @openai/codex`, rồi `codex login` (người dùng tự chạy vì cần trình duyệt; gợi ý `! codex login`).
- `codex login status` phải báo đã đăng nhập.
- `git status --porcelain` phải sạch — script từ chối chạy khi còn thay đổi chưa commit. Nếu không sạch,
  hỏi người dùng muốn commit hay stash; không tự quyết.
- Có thể chạy `SCRIPT --check` để kiểm tra tổng thể (công cụ, PLAN.md, git hook).

## 2. Viết plan (chỉ khi chưa có PLAN.md)

Cần mô tả dự án: lấy từ `$ARGUMENTS`; nếu trống thì hỏi người dùng. Chạy (timeout 10 phút):

```bash
SCRIPT --plan-only "<mô tả dự án>"
```

Script để Opus 5.5 viết PLAN.md, commit rồi thoát. Sau đó đọc PLAN.md và trình bày ngắn cho người dùng:
`TEST_CMD`, danh sách `## Task N`, và những giả định đáng chú ý. Hỏi người dùng duyệt hay muốn sửa.
Nếu sửa: sửa PLAN.md theo ý họ, giữ đúng định dạng (dòng `TEST_CMD: ...`, heading `## Task N: <tiêu đề>`
đánh số liên tục từ 1), rồi `git commit -am "PLAN.md: <thay đổi>"`.

Đã có PLAN.md thì bỏ qua bước này (task đã có commit "Task N" sẽ được bỏ qua — chạy tiếp được).

## 3. Chạy pipeline

Pipeline có thể chạy hàng giờ, nên chạy **nền** (Bash với `run_in_background: true`):

```bash
SCRIPT
```

Không polling liên tục — bạn sẽ được báo khi lệnh kết thúc. Khi người dùng hỏi tiến độ, đọc
`.auto-logs/run.log` (tail) hoặc `git log --oneline` để xem các commit "Task N".
Người dùng muốn dừng: `SCRIPT --stop-after` (dừng sau khi task hiện tại xong; huỷ: `--no-stop-after`).

## 4. Khi script kết thúc

Đọc `.auto-logs/summary.md` và báo kết quả theo mã thoát:

| Mã | Ý nghĩa | Việc cần làm |
|---|---|---|
| 0 | Xong hết (hoặc dừng theo `--stop-after`) | Tóm tắt các task, nits trong `.auto-logs/nits.md`, branch `auto/*` để người dùng merge |
| 1 | Task FAIL sau khi hết số vòng sửa | Trình `REVIEW.md` + log `.auto-logs/task<N>-*`; đề xuất: làm rõ/chia nhỏ task trong PLAN.md, hoặc sửa tay rồi `SCRIPT --adopt N` |
| 2 | Cầu dao (agent không sửa file, rời branch, lệnh bị từ chối...) | Trình thông báo lỗi và "Cách xử lý" script in ra |
| 3 | Chờ hết hạn mức quá `MAX_WAIT_HOURS` | Báo giờ reset; chạy lại sau |
| 4 | Không gọi được Claude để review | Kiểm tra `claude` đăng nhập / mạng |
| 5 | Preflight chưa đạt (đăng nhập Codex, ghi file, git hook) | Trình báo cáo; thường là cần `codex login` hoặc sửa hook |
| 6 | Dịch vụ trong `REQUIRE_CMD` chưa chạy | Nhờ người dùng bật dịch vụ |
| 7 | plan-gap: PLAN.md thiếu một quyết định | Trình các lựa chọn reviewer nêu, **hỏi người dùng quyết**, ghi quyết định vào đúng phần Task đó trong PLAN.md (không đổi heading), commit, rồi chạy lại bước 3 |

Sau khi xử lý xong, chạy lại `SCRIPT` — task đã commit được bỏ qua.

## Cấu hình

Đặt trong `.autowf.env` ở gốc repo đích hoặc qua biến môi trường (env ưu tiên hơn file). Hay dùng:

- `PLAN_MODEL` (mặc định `claude-opus-5-5`), `REVIEW_MODEL` (mặc định `claude-sonnet-5-5`)
- `CODER` (mặc định `codex`; cũng hỗ trợ `agy`, `gemini`), `FALLBACK_CODER`
- `CODEX_MODEL` (rỗng = mặc định của Codex), `CODEX_SANDBOX` (`workspace-write` | `danger-full-access`),
  `CODEX_NETWORK` (1 = cho Codex dùng mạng trong sandbox, cần để cài package), `CODEX_ARGS`
  (vd. `--dangerously-bypass-approvals-and-sandbox` khi sandbox Linux của Codex không chạy được trong container —
  chỉ đề xuất, để người dùng tự quyết vì nó bỏ mọi giới hạn)
- `MAX_TRIES` (3), `MAX_EXTRA_TRIES` (2), `MAX_WAIT_HOURS` (6), `REQUIRE_CMD`, `NTFY_TOPIC`

Xem đủ bằng `SCRIPT --help`.
