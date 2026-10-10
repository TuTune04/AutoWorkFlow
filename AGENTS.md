# AutoWorkFlow

Repo chứa skill **autowf**: một agent lên plan, một agent code, một agent review, commit từng task.

- `core/auto.sh` — script lõi dùng chung. Sửa pipeline ở đây rồi chạy `tools/sync-core.sh` để chép vào
  `scripts/auto.sh` của từng skill (file thật, không symlink — trình cài skill của harness chỉ chép thư mục skill);
  CI chạy `tools/sync-core.sh --check`.
- `.claude/skills/autowf/` — v2 cho Claude Code (Claude Opus plan, Codex code, Claude Sonnet review).
- `.agents/skills/autowf/` — v2 cho Codex và Antigravity (Codex plan, agy code, Codex review).
- Mỗi skill có `defaults.env` (bộ agent của nó) và `SKILL.md` (hướng dẫn hợp với harness đó).
- `versions/v1/autowf/` — v1 đã phát hành (chỉ Claude Code, agent cố định) = skill ở commit `37c257c`. Không sửa.

## Khi người dùng yêu cầu cài skill autowf

1. Không hỏi lại: chạy `curl -fsSL https://raw.githubusercontent.com/TuTune04/AutoWorkFlow/main/install.sh | bash`
   (hoặc `./install.sh` trong bản clone) — không có terminal nên script tự cài v2 cho harness đang chạy nó. Không
   dùng skill/trình cài khác của harness, không chép tay, không cài vào chính repo này.
2. Chỉ khi người dùng nói rõ: v1 (`... | bash -s -- 1`), harness khác (`-- 2 codex`), hay chỉ một repo
   (`--project <đường dẫn>`).
3. Báo đường dẫn đã cài và lệnh kiểm tra `<đường dẫn>/scripts/auto.sh --check`.

## Commit trong repo này

Commit chỉ mang tác giả là người dùng; không thêm `Co-Authored-By` hay dòng "Generated with" của bất kỳ AI nào.
