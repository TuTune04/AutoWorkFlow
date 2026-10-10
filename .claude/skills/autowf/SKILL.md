---
name: autowf
description: Chạy pipeline tự động viết phần mềm theo từng task — Claude Opus 5.5 viết PLAN.md, Codex CLI viết code cho từng task, Claude Sonnet 5.5 review diff + kết quả test rồi commit "Task N" (mọi commit chỉ mang tên người dùng). Dùng khi người dùng muốn "lên plan rồi để agent code", "chạy autowf/auto.sh", "Opus plan, Codex code, Sonnet review", hoặc chạy tiếp/dừng một pipeline autowf.
argument-hint: "[mô tả dự án | continue | stop | check]"
---

# autowf (Claude Code)

`SCRIPT` = `scripts/auto.sh` cạnh file này (đường dẫn tuyệt đối từ "Base directory"). Script tự làm hết: branch
`auto/*`, planner viết PLAN.md, coder làm từng task, tự chạy `TEST_CMD`, reviewer chấm, sửa tối đa `MAX_TRIES` vòng,
commit `Task N: <tiêu đề>`. Bộ agent ở `defaults.env` (Opus plan, Codex code, Sonnet review; chưa có Codex thì Claude
code thay); `.autowf.env` ở repo đích ghi đè. Đối số: `$ARGUMENTS`.

**Bạn chỉ điều phối:** không tự viết PLAN.md/code, không commit thay script (trừ ghi quyết định người dùng vào PLAN.md).
**Commit:** chỉ mang tên người dùng; không `Co-Authored-By`/"Generated with" của bất kỳ AI nào (ghi đè mặc định của
Claude Code); không đổi `git config user.*`, không `--author`.
**Hỏi tối đa hai lần:** (a) xin cài agent còn thiếu, (b) duyệt plan (bỏ nếu người dùng nói "chạy luôn"). Không hỏi
chi tiết dự án — tự bổ sung giả định hợp lý (stack đơn giản, ít phụ thuộc, có test); không hỏi "tiếp tục nhé?".
Không bỏ bước nào dưới đây: kiểm tra → plan → chạy → báo kết quả và xử lý cho tới khi xong hoặc cần người quyết.

## 1. Kiểm tra (ở gốc repo đích; chưa phải git repo thì để script tự `git init`)

`SCRIPT --check`: agent, tác giả commit, model, PLAN.md, git, hook. Xử lý:
- Thiếu agent: hỏi một lần rồi cài (`npm i -g @openai/codex` / `@anthropic-ai/claude-code` / `@google/gemini-cli`).
- Chưa đăng nhập Codex: nhờ người dùng `! codex login --device-auth`; họ dán URL `http://127.0.0.1:1455/auth/callback?...`
  thì `curl '<URL>'`. Trong lúc chờ, làm tiếp bước không cần Codex (viết plan).
- Git không sạch (trừ `.autowf.env`): hỏi commit hay stash.
- Người dùng muốn đổi agent/model: `SCRIPT --models <agent>` lấy model tài khoản dùng được → AskUserQuestion (tối đa 4
  lựa chọn, mạnh nhất trước) → ghi `PLANNER|CODER|REVIEWER` và `PLAN_MODEL|CODER_MODEL|REVIEW_MODEL` vào `.autowf.env`.
  Không bắt gõ tên model.

## 2. Plan (khi chưa có PLAN.md)

- "Chạy luôn": `SCRIPT "<mô tả>"` chạy nền (bước 3).
- Mặc định: `SCRIPT --plan-only "<mô tả>"` (timeout 10 phút). Trình bày ngắn `TEST_CMD`, các `## Task N`, giả định
  đáng chú ý; hỏi **một câu**: chạy luôn hay sửa. Đồng ý ("ok", "chạy đi"...) → bước 3. Sửa → sửa PLAN.md giữ định
  dạng (`TEST_CMD: ...`, `## Task N: <tiêu đề>` liên tục từ 1), `git commit -am "PLAN.md: <thay đổi>"`, rồi bước 3.

## 3. Chạy

`SCRIPT` với Bash `run_in_background: true`; không polling. Tiến độ: `tail .auto-logs/run.log`, `git log --oneline`.
Dừng sau task hiện tại: `SCRIPT --stop-after` (huỷ: `--no-stop-after`).

## 4. Khi kết thúc

Đọc `.auto-logs/summary.md`, báo theo mã thoát, xử lý xong thì chạy lại `SCRIPT` (task đã commit được bỏ qua):
- 0 xong: tóm tắt task, nits (`.auto-logs/nits.md`), branch `auto/*` để merge.
- 1 task FAIL hết vòng (hoặc thiếu tác giả commit): trình `REVIEW.md`, log `.auto-logs/task<N>-*`; đề xuất làm rõ/chia nhỏ
  task, hoặc sửa tay rồi `SCRIPT --adopt N`.
- 2 cầu dao: trình lỗi và "Cách xử lý" script in ra. 3 quá `MAX_WAIT_HOURS`: báo giờ reset.
- 4 không gọi được reviewer: kiểm tra đăng nhập/mạng/`REVIEW_MODEL`. 5 preflight: trình báo cáo (đăng nhập coder, hook).
- 6 `REQUIRE_CMD` chưa chạy: nhờ bật dịch vụ.
- 7 plan-gap: trình các lựa chọn reviewer nêu, **hỏi người dùng**, ghi vào đúng Task trong PLAN.md, commit, chạy lại.

Cấu hình khác (`MAX_TRIES`, `GIT_USER_NAME/EMAIL`, `CODEX_ARGS`, `REQUIRE_CMD`, `NTFY_TOPIC`...): `SCRIPT --help`.
`CODEX_ARGS=--dangerously-bypass-approvals-and-sandbox` (sandbox Codex lỗi trong container) chỉ đề xuất, người dùng tự quyết.
