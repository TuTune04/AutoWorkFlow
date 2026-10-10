# AutoWorkFlow

Repo chứa skill **autowf**: một agent lên plan, một agent code, một agent review, commit từng task.

- `core/auto.sh` — script lõi dùng chung. Sửa pipeline ở đây; các skill trỏ tới nó qua symlink `scripts/auto.sh`.
- `.claude/skills/autowf/` — v2 cho Claude Code (Claude Opus plan, Codex code, Claude Sonnet review).
- `.agents/skills/autowf/` — v2 cho Codex và Antigravity (Codex plan, agy code, Codex review).
- Mỗi skill có `defaults.env` (bộ agent của nó) và `SKILL.md` (hướng dẫn hợp với harness đó).
- `versions/v1/autowf/` — v1 đã phát hành (chỉ Claude Code, agent cố định). Không sửa.

## Khi người dùng yêu cầu cài skill autowf

1. Nếu người dùng chưa nói rõ, hỏi **một lần** gộp mọi lựa chọn: phiên bản (v1: chỉ Claude Code, ít thành phần,
   ổn định; v2: Claude Code / Codex / Antigravity, đổi được agent, hỏi ít hơn), harness (với v2), và cài cho mọi
   dự án hay chỉ một repo (`--project <đường dẫn>`).
2. Chạy `./install.sh <1|2> [claude] [codex] [antigravity] [--project <đường dẫn>]` ở gốc repo này. Không chép tay,
   không cài vào chính repo này.
3. Báo đường dẫn đã cài và lệnh kiểm tra `<đường dẫn>/scripts/auto.sh --check`.

## Commit trong repo này

Commit chỉ mang tác giả là người dùng; không thêm `Co-Authored-By` hay dòng "Generated with" của bất kỳ AI nào.
