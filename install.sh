#!/bin/bash
# install.sh — cài skill autowf, chọn phiên bản và harness (công cụ sẽ điều phối pipeline).
#
# Cài bằng một lệnh, không cần clone repo (tham số giống hệt bên dưới, đặt sau "bash -s --"):
#   curl -fsSL https://raw.githubusercontent.com/TuTune04/AutoWorkFlow/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/TuTune04/AutoWorkFlow/main/install.sh | bash -s -- 2 codex
#
# Cách dùng:
#   ./install.sh                        hỏi chọn (cần terminal tương tác)
#   ./install.sh 1                      v1 cho Claude Code: Opus plan, Codex code, Sonnet review — ít thành phần, ổn định
#   ./install.sh 2 claude               v2 cho Claude Code: như v1 + đổi agent từng vai trò, tác giả commit, hỏi ít hơn
#   ./install.sh 2 codex                v2 cho Codex CLI: Codex plan, agy code, Codex review (không cần gói Claude)
#   ./install.sh 2 antigravity          v2 cho Antigravity: cùng bộ agent với bản codex
#   ./install.sh 2 claude codex         cài cho nhiều harness cùng lúc
#   ... --project DIR                   chỉ cài cho repo DIR (DIR/.claude/skills hoặc DIR/.agents/skills)
#
# Nơi cài (mặc định cho mọi dự án): claude → ~/.claude/skills/autowf; codex → ~/.agents/skills/autowf;
# antigravity → ~/.gemini/antigravity-cli/skills/autowf (CLI) và ~/.gemini/config/skills/autowf (IDE / 2.0).
# Với --project: claude → DIR/.claude/skills/autowf; codex và antigravity → DIR/.agents/skills/autowf (dùng chung).
# Bản đang cài (nếu có) được đổi tên thành autowf.bak-<thời gian> trước khi chép bản mới.

set -euo pipefail

usage() { cat <<'USAGE'
Cài skill autowf.
  install.sh                        hỏi chọn phiên bản và harness
  install.sh 1                      v1 cho Claude Code (Opus plan, Codex code, Sonnet review cố định)
  install.sh 2 claude|codex|antigravity [...]   v2 cho một hoặc nhiều harness
  install.sh ... --project DIR      chỉ cài cho repo DIR
Cài không cần clone:
  curl -fsSL https://raw.githubusercontent.com/TuTune04/AutoWorkFlow/main/install.sh | bash -s -- 2 codex
Biến: AUTOWF_REPO (mặc định TuTune04/AutoWorkFlow), AUTOWF_REF (branch/tag, mặc định main)
USAGE
}

# Nguồn skill: chạy từ bản clone thì dùng luôn; chạy qua "curl | bash" (không có file repo bên cạnh) thì tải
# bản nén của repo từ GitHub về thư mục tạm.
AUTOWF_REPO="${AUTOWF_REPO:-TuTune04/AutoWorkFlow}"
AUTOWF_REF="${AUTOWF_REF:-main}"
ROOT=""
if [ -f "${BASH_SOURCE[0]:-}" ]; then ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); fi
SRC_TMP=""
fetch_source() {
  command -v curl >/dev/null || { echo "❌ Cần curl để tải autowf"; exit 1; }
  SRC_TMP=$(mktemp -d)
  trap 'rm -rf "$SRC_TMP"' EXIT
  echo "⬇️  Tải $AUTOWF_REPO@$AUTOWF_REF ..."
  curl -fsSL "https://codeload.github.com/$AUTOWF_REPO/tar.gz/$AUTOWF_REF" | tar -xz -C "$SRC_TMP" \
    || { echo "❌ Không tải được https://github.com/$AUTOWF_REPO (ref $AUTOWF_REF)"; exit 1; }
  ROOT=$(find "$SRC_TMP" -mindepth 1 -maxdepth 1 -type d | head -n1)
}
VERSION=""
HARNESSES=""
PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    1|v1)        VERSION=1 ;;
    2|v2)        VERSION=2 ;;
    claude|codex|antigravity) HARNESSES+=" $1" ;;
    agy)         HARNESSES+=" antigravity" ;;
    --project)   PROJECT="$(cd "${2:?--project cần đường dẫn}" && pwd)"; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "❌ Tham số không hợp lệ: $1 (xem ./install.sh --help)"; exit 1 ;;
  esac
  shift
done

# Hỏi qua terminal: "curl | bash" chiếm stdin cho nội dung script, nên đọc từ /dev/tty
TTY=""
if [ -t 0 ]; then TTY=/dev/stdin; elif (: < /dev/tty) 2>/dev/null; then TTY=/dev/tty; fi
need_tty() {
  [ -n "$TTY" ] && return 0
  echo "❌ Thiếu lựa chọn và không có terminal để hỏi. Ghi rõ, vd.: install.sh 1   hoặc   install.sh 2 codex" >&2
  echo "   (qua curl: ... | bash -s -- 2 codex)" >&2
  exit 1
}
ask() {  # <câu hỏi> → in câu trả lời
  local a; need_tty
  printf '%s' "$1" > /dev/tty 2>/dev/null || printf '%s' "$1" >&2
  read -r a < "$TTY"; printf '%s' "$a"
}

if [ -z "$VERSION" ]; then
  need_tty
  echo "Chọn phiên bản skill autowf:"
  echo "  1) v1 — chỉ Claude Code. Claude Opus plan, Codex code, Claude Sonnet review (cố định). Ít thành phần, ít lỗi hơn."
  echo "  2) v2 — Claude Code, Codex hoặc Antigravity. Đổi được agent từng vai trò, đặt tác giả commit, hỏi ít hơn."
  VERSION=$(ask "Phiên bản [1/2]: ")
  case "$VERSION" in 1|2) ;; *) echo "❌ Chỉ chọn 1 hoặc 2"; exit 1 ;; esac
fi
if [ "$VERSION" = 1 ]; then
  case "$HARNESSES" in ""|" claude") HARNESSES=" claude" ;; *) echo "❌ v1 chỉ có cho Claude Code"; exit 1 ;; esac
elif [ -z "$HARNESSES" ]; then
  need_tty
  echo "Cài v2 cho harness nào (công cụ bạn dùng để gọi /autowf)? Có thể chọn nhiều, cách nhau bởi dấu cách:"
  echo "  claude       Claude Code — Claude Opus plan, Codex code, Claude Sonnet review"
  echo "  codex        Codex CLI — Codex plan, agy code, Codex review (không cần gói Claude)"
  echo "  antigravity  Antigravity — cùng bộ agent với codex"
  HARNESSES=" $(ask "Harness [claude/codex/antigravity]: ")"
  for h in $HARNESSES; do
    case "$h" in claude|codex|antigravity) ;; agy) ;; *) echo "❌ Không có harness '$h'"; exit 1 ;; esac
  done
  HARNESSES=${HARNESSES//agy/antigravity}
fi

if [ -z "$ROOT" ] || [ ! -d "$ROOT/core" ] || [ ! -d "$ROOT/versions/v1" ]; then fetch_source; fi

# Đích cài của mỗi harness (mỗi dòng một thư mục skills)
dest_bases() {  # <harness>
  if [ -n "$PROJECT" ]; then
    case "$1" in claude) echo "$PROJECT/.claude/skills" ;; *) echo "$PROJECT/.agents/skills" ;; esac
    return
  fi
  case "$1" in
    claude)      echo "$HOME/.claude/skills" ;;
    codex)       echo "$HOME/.agents/skills" ;;
    antigravity) echo "$HOME/.gemini/antigravity-cli/skills"; echo "$HOME/.gemini/config/skills" ;;
  esac
}
source_of() {  # <harness>
  if [ "$VERSION" = 1 ]; then echo "$ROOT/versions/v1/autowf"; return; fi
  case "$1" in claude) echo "$ROOT/.claude/skills/autowf" ;; *) echo "$ROOT/.agents/skills/autowf" ;; esac
}

install_one() {  # <nguồn> <thư mục skills>
  local src="$1" base="$2" dest old bak real_base
  mkdir -p "$base"
  real_base=$(cd "$base" && pwd -P)
  # Repo nguồn chứa sẵn v2 ở .claude/skills và .agents/skills: cài đè sẽ mất mã nguồn
  if [ "$real_base" = "$(cd "$ROOT" && pwd -P)/.claude/skills" ] || [ "$real_base" = "$(cd "$ROOT" && pwd -P)/.agents/skills" ]; then
    echo "❌ Không cài vào chính repo nguồn ($ROOT) — repo này đã dùng sẵn v2. Chọn --project <repo khác> hoặc bỏ --project."
    exit 1
  fi
  dest="$base/autowf"
  if [ -e "$dest" ]; then
    old=$(cat "$dest/VERSION" 2>/dev/null || echo "?")
    bak="$dest.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$dest" "$bak"
    echo "📦 Bản cũ (v$old) ở $dest đã chuyển sang $bak"
  fi
  cp -RL "$src" "$dest"   # -L: scripts/auto.sh trong repo là symlink tới core/auto.sh
  chmod +x "$dest/scripts/auto.sh"
  echo "✅ Đã cài autowf v$VERSION vào $dest"
  INSTALLED="$dest"
}

DONE=" "
for h in $HARNESSES; do
  src=$(source_of "$h")
  [ -f "$src/SKILL.md" ] || { echo "❌ Không thấy skill ở $src"; exit 1; }
  while IFS= read -r base; do
    case "$DONE" in *" $base "*) continue ;; esac   # codex + antigravity với --project dùng chung .agents/skills
    install_one "$src" "$base"
    DONE+="$base "
  done < <(dest_bases "$h")
done
echo "   Kiểm tra trong repo dự án: $INSTALLED/scripts/auto.sh --check"
echo "   Gọi skill: Claude Code /autowf · Codex \$autowf · Antigravity CLI /autowf"
