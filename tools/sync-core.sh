#!/bin/bash
# sync-core.sh — chép core/auto.sh vào scripts/auto.sh của mọi skill (file thật, không symlink: trình cài skill của
# harness — vd. skill-installer của Codex — chỉ chép thư mục skill, symlink sẽ hỏng).
#   tools/sync-core.sh           chép
#   tools/sync-core.sh --check   chỉ kiểm tra, trả về 1 nếu có bản lệch (dùng trước khi commit)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
rc=0
for d in "$ROOT"/.claude/skills/autowf "$ROOT"/.agents/skills/autowf; do
  dst="$d/scripts/auto.sh"
  if [ "${1:-}" = --check ]; then
    if [ -L "$dst" ] || ! cmp -s "$ROOT/core/auto.sh" "$dst"; then echo "❌ ${dst#$ROOT/} khác core/auto.sh — chạy tools/sync-core.sh"; rc=1; fi
  else
    rm -f "$dst"; cp "$ROOT/core/auto.sh" "$dst"; chmod +x "$dst"; echo "✅ ${dst#$ROOT/}"
  fi
done
exit "$rc"
