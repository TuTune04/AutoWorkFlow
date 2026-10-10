#!/bin/bash
# install.sh — cài skill autowf cho Claude Code, chọn một trong hai phiên bản.
#
# Cách dùng:
#   ./install.sh            hỏi chọn phiên bản (cần terminal tương tác)
#   ./install.sh 1          cài v1: Opus plan, Codex code, Sonnet review cố định — ít thành phần, ổn định
#   ./install.sh 2          cài v2: profile (premium/free/tự chọn agent cho từng vai trò), tác giả commit tuỳ chỉnh
#   ./install.sh 2 --project DIR   cài vào DIR/.claude/skills/autowf (chỉ repo đó) thay vì ~/.claude/skills/autowf
#
# Bản đang cài (nếu có) được đổi tên thành autowf.bak-<thời gian> trước khi chép bản mới.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
VERSION=""
DEST_BASE="$HOME/.claude/skills"

while [ $# -gt 0 ]; do
  case "$1" in
    1|v1)       VERSION=1 ;;
    2|v2)       VERSION=2 ;;
    --project)  DEST_BASE="$(cd "${2:?--project cần đường dẫn}" && pwd)/.claude/skills"; shift ;;
    -h|--help)  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "❌ Tham số không hợp lệ: $1 (dùng 1, 2 hoặc --project DIR)"; exit 1 ;;
  esac
  shift
done

if [ -z "$VERSION" ]; then
  if [ ! -t 0 ]; then
    echo "❌ Chưa chọn phiên bản. Chạy: ./install.sh 1   hoặc   ./install.sh 2"; exit 1
  fi
  echo "Chọn phiên bản skill autowf:"
  echo "  1) v1 — Claude Opus plan, Codex code, Claude Sonnet review (cố định). Ít thành phần, ít lỗi hơn."
  echo "  2) v2 — Chọn profile (premium / free / tự chọn agent cho plan, code, review), đặt tác giả commit,"
  echo "          không bao giờ có Co-authored-by của AI. Linh hoạt hơn, mới hơn."
  read -r -p "Phiên bản [1/2]: " VERSION
  case "$VERSION" in 1|2) ;; *) echo "❌ Chỉ chọn 1 hoặc 2"; exit 1 ;; esac
fi

case "$VERSION" in
  1) SRC="$ROOT/versions/v1/autowf" ;;
  2) SRC="$ROOT/.claude/skills/autowf" ;;
esac
[ -f "$SRC/SKILL.md" ] || { echo "❌ Không thấy skill v$VERSION ở $SRC"; exit 1; }

DEST="$DEST_BASE/autowf"
# Repo nguồn đã có v2 ở .claude/skills/autowf: cài đè vào đó sẽ mất mã nguồn v2
if [ "$(mkdir -p "$DEST_BASE" && cd "$DEST_BASE" && pwd -P)" = "$(cd "$ROOT/.claude/skills" && pwd -P)" ]; then
  echo "❌ Không cài vào chính repo nguồn ($ROOT) — repo này đã dùng sẵn v2. Chọn --project <repo khác> hoặc bỏ --project."
  exit 1
fi
if [ -e "$DEST" ]; then
  OLD=$(cat "$DEST/VERSION" 2>/dev/null || echo "?")
  BAK="$DEST.bak-$(date +%Y%m%d-%H%M%S)"
  mv "$DEST" "$BAK"
  echo "📦 Bản cũ (v$OLD) đã chuyển sang $BAK"
fi
cp -R "$SRC" "$DEST"
chmod +x "$DEST/scripts/auto.sh"
echo "✅ Đã cài autowf v$VERSION vào $DEST"
echo "   Kiểm tra trong repo dự án: $DEST/scripts/auto.sh --check"
echo "   Dùng trong Claude Code: /autowf <mô tả dự án>"
