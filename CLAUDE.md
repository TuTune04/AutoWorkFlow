# AutoWorkFlow

Repo chứa skill **autowf** cho Claude Code, có hai phiên bản:

- **v1** — `versions/v1/autowf/`: Claude Opus plan, Codex code, Claude Sonnet review (cố định). Ít thành phần, ổn định.
- **v2** — `.claude/skills/autowf/`: profile (`premium` / `free` / tự chọn agent cho từng vai trò), tác giả commit
  tuỳ chỉnh, không có `Co-authored-by` của AI. Repo này dùng sẵn v2.

## Khi người dùng yêu cầu cài skill autowf

1. Nếu người dùng chưa nói rõ phiên bản, hỏi **một lần** bằng AskUserQuestion: v1 hay v2 (tóm tắt khác biệt ở
   trên), và cài cho mọi dự án (`~/.claude/skills`) hay chỉ một repo (`--project <đường dẫn>`).
2. Chạy `./install.sh <1|2> [--project <đường dẫn>]` ở gốc repo này. Không chép tay, không cài vào chính repo này.
3. Báo đường dẫn đã cài và lệnh kiểm tra `<đường dẫn>/scripts/auto.sh --check`.

## Commit trong repo này

Commit chỉ mang tác giả là người dùng; không thêm `Co-Authored-By` hay dòng "Generated with" của bất kỳ AI nào.
Không sửa `versions/v1/` — đó là bản v1 đã phát hành; thay đổi mới làm ở v2.
