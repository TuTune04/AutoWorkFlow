---
name: autowf
description: Chạy pipeline tự động viết phần mềm theo từng task, không cần gói Claude trả phí — Codex viết PLAN.md, Antigravity (agy, Gemini) viết code cho từng task (chưa có agy thì Codex viết), Codex review diff + kết quả test rồi commit "Task N" (mọi commit chỉ mang tên người dùng). Dùng khi người dùng muốn "lên plan rồi để agent code", "chạy autowf/auto.sh", hoặc chạy tiếp/dừng một pipeline autowf. Không dùng cho việc sửa code thông thường trong một lần.
---

# autowf (Codex / Antigravity)

`SCRIPT` = `scripts/auto.sh` cạnh file này (đường dẫn tuyệt đối của thư mục chứa SKILL.md). Script tự làm hết: branch
`auto/*`, planner viết PLAN.md, coder làm từng task, tự chạy `TEST_CMD`, reviewer chấm, sửa tối đa `MAX_TRIES` vòng,
commit `Task N: <tiêu đề>`. Bộ agent ở `defaults.env` (Codex plan, agy code — chưa có agy thì Codex code —, Codex
review model `luna`, tự quy ra model luna mới nhất); `.autowf.env` ở repo đích ghi đè.

**Bạn chỉ điều phối:** không tự viết PLAN.md/code, không commit thay script (trừ ghi quyết định người dùng vào PLAN.md).
**Commit:** chỉ mang tên người dùng; không `Co-Authored-By`/"Generated with" của bất kỳ AI nào; không đổi
`git config user.*`, không `--author`.
**Hỏi tối đa hai lần**, mỗi lần một câu bằng văn bản: (a) xin cài agent còn thiếu, (b) duyệt plan (bỏ nếu người dùng
nói "chạy luôn"). Không hỏi chi tiết dự án — tự bổ sung giả định hợp lý; không hỏi "tiếp tục nhé?".
Không bỏ bước nào dưới đây: kiểm tra → plan → chạy → báo kết quả và xử lý cho tới khi xong hoặc cần người quyết.

**Chạy SCRIPT:** nó gọi lồng `codex exec`/`agy -p` (cần mạng, ghi `~/.codex`, `~/.gemini`) → Codex: xin quyền chạy ngoài
sandbox cho lệnh SCRIPT; Antigravity: lệnh SCRIPT phải được cho phép. Lệnh ngắn (`--check`, `--plan-only`,
`--preflight`, `--models`, `--stop-after`) chạy và chờ. Pipeline chạy lâu: `mkdir -p .auto-logs && setsid nohup SCRIPT >
.auto-logs/pipeline.out 2>&1 < /dev/null &`, ~30 giây sau đọc `.auto-logs/run.log`; tiến trình bị harness dừng thì đưa
người dùng đúng một lệnh chạy trong terminal: `cd <repo đích> && SCRIPT`.

## 1. Kiểm tra (ở gốc repo đích; chưa phải git repo thì để script tự `git init`)

`SCRIPT --check`: agent, tác giả commit, model, PLAN.md, git, hook. Xử lý:
- Thiếu agent bắt buộc (planner/reviewer): hỏi một lần rồi cài (`npm i -g @openai/codex` / `@google/gemini-cli`;
  `agy` người dùng tự cài — không bắt buộc, đã có Codex dự phòng).
- Chưa đăng nhập Codex: nhờ người dùng `codex login` (container: `codex login --device-auth`); họ dán URL
  `http://127.0.0.1:1455/auth/callback?...` thì `curl '<URL>'`.
- Git không sạch (trừ `.autowf.env`): hỏi commit hay stash.
- Người dùng muốn đổi agent/model: `SCRIPT --models <agent>` lấy model tài khoản dùng được → đưa danh sách đánh số
  (mạnh nhất trước) để chọn bằng số → ghi `PLANNER|CODER|REVIEWER`, `PLAN_MODEL|CODER_MODEL|REVIEW_MODEL` vào
  `.autowf.env`. Không bắt gõ tên model.

## 2. Plan (khi chưa có PLAN.md)

- "Chạy luôn": `SCRIPT "<mô tả>"` theo cách chạy pipeline ở trên.
- Mặc định: `SCRIPT --plan-only "<mô tả>"`, rồi `SCRIPT --preflight` (nếu coder là agy: lệnh của `TEST_CMD` script tự
  cho phép, chỉ quy tắc trong config của agy — `$AGY_CONFIG`, mặc định `~/.gemini/config/config.json` — cần người dùng
  đồng ý). Trình bày ngắn `TEST_CMD`, các `## Task N`, giả định đáng chú ý và quy tắc quyền còn thiếu (nếu có); hỏi
  **một câu** gộp: chạy luôn (kèm thêm quy tắc) hay sửa. Đồng ý → thêm quy tắc vào `globalPermissionGrants.allow`, bước 3.
  Sửa → sửa PLAN.md giữ định dạng (`TEST_CMD: ...`, `## Task N: <tiêu đề>` liên tục từ 1),
  `git commit -am "PLAN.md: <thay đổi>"`, rồi bước 3.

## 3. Chạy

Chạy `SCRIPT` theo cách chạy pipeline ở trên. Tiến độ: `tail .auto-logs/run.log`, `git log --oneline`.
Dừng sau task hiện tại: `SCRIPT --stop-after` (huỷ: `--no-stop-after`).

## 4. Khi kết thúc

Đọc `.auto-logs/summary.md` (mã thoát cuối `.auto-logs/pipeline.out`), báo theo mã, xử lý xong thì chạy lại `SCRIPT`:
- 0 xong: tóm tắt task, nits (`.auto-logs/nits.md`), branch `auto/*` để merge.
- 1 task FAIL hết vòng (hoặc thiếu tác giả commit): trình `REVIEW.md`, log `.auto-logs/task<N>-*`; đề xuất làm rõ/chia nhỏ
  task, hoặc sửa tay rồi `SCRIPT --adopt N`.
- 2 cầu dao: trình lỗi và "Cách xử lý" script in ra. 3 quá `MAX_WAIT_HOURS`: báo giờ reset.
- 4 không gọi được reviewer: kiểm tra đăng nhập/mạng/`REVIEW_MODEL`.
- 5 preflight: trình báo cáo và quy tắc cần thêm vào config của agy; được đồng ý thì thêm rồi chạy lại.
- 6 `REQUIRE_CMD` chưa chạy: nhờ bật dịch vụ.
- 7 plan-gap: trình các lựa chọn reviewer nêu, **hỏi người dùng**, ghi vào đúng Task trong PLAN.md, commit, chạy lại.

Cấu hình khác (`MAX_TRIES`, `GIT_USER_NAME/EMAIL`, `AGY_ALLOWED_CMDS`, `REQUIRE_CMD`, `NTFY_TOPIC`...): `SCRIPT --help`.
