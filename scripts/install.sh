#!/usr/bin/env bash
# install.sh — install IDD skills and/or plugin from a working tree.
#
# One-line install for users with a fresh clone of the repository who do
# not have `asm` (the recommended primary install tool — see README → Install).
# This is a thin wrapper around the supported install layouts:
#
#   - Standalone path: copy each `dist/skills/<name>/` to ~/.claude/skills/<name>/
#   - Plugin path:     copy `dist/plugin/` to ~/.claude/plugins/idd/
#                      (requires a fresh build — `dist/plugin/` is gitignored)
#
# Idempotent: re-running cleans the destination directory first, so no
# duplicate files or stale references are left behind.
#
# Usage:
#   ./scripts/install.sh                # install standalone skills (default)
#   ./scripts/install.sh --plugin       # install plugin tree
#   ./scripts/install.sh --all          # install both standalone + plugin
#   ./scripts/install.sh --skill <n>    # install one named skill (standalone)
#   ./scripts/install.sh --target <dir> # override Claude install root (default: ~/.claude)
#   ./scripts/install.sh --dry-run      # show what would be installed
#   ./scripts/install.sh --help         # this help text
#
# Exit codes:
#   0  success
#   1  bad arguments / missing source / copy failure
#
# References:
#   README → Install      docs/DEVELOPMENT.md → Local Setup

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults and helpers
# ---------------------------------------------------------------------------

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
DIST_SKILLS="$ROOT/dist/skills"
DIST_PLUGIN="$ROOT/dist/plugin"
TARGET="${HOME}/.claude"
MODE="standalone"   # standalone | plugin | all
ONLY_SKILL=""
DRY_RUN=0

usage() {
  cat <<EOF
install.sh — install IDD skills/plugin from this working tree.

USAGE
  ./scripts/install.sh [--plugin | --all] [--skill <name>] [--target <dir>] [--dry-run]
  ./scripts/install.sh --help

OPTIONS
  --plugin           Install plugin tree to <target>/plugins/idd/
                     (requires running ./scripts/build.sh first to populate dist/plugin/)
  --all              Install both standalone skills and the plugin tree
  --skill <name>     Standalone install of a single named skill (e.g. issue-resolver)
  --target <dir>     Override Claude root (default: \$HOME/.claude)
  --dry-run          Print actions without copying
  --help             Show this help

EXAMPLES
  ./scripts/install.sh                          # all standalone skills
  ./scripts/install.sh --skill issue-resolver   # one skill
  ./scripts/install.sh --plugin                 # plugin only (run build.sh first)
  ./scripts/install.sh --all                    # everything
EOF
}

log()  { printf '%s\n' "$*"; }
info() { log "○ $*"; }
ok()   { log "✓ $*"; }
err()  { log "✗ $*" >&2; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  (dry-run) $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin)    MODE="plugin"; shift ;;
    --all)       MODE="all"; shift ;;
    --skill)
      [ $# -ge 2 ] || { err "--skill requires a name"; exit 1; }
      ONLY_SKILL="$2"; shift 2 ;;
    --target)
      [ $# -ge 2 ] || { err "--target requires a directory"; exit 1; }
      TARGET="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           err "Unknown argument: $1"; usage >&2; exit 1 ;;
  esac
done

SKILLS_DEST="$TARGET/skills"
PLUGIN_DEST="$TARGET/plugins/idd"

# ---------------------------------------------------------------------------
# Source presence checks
# ---------------------------------------------------------------------------

ensure_skills_src() {
  if [ ! -d "$DIST_SKILLS" ]; then
    err "dist/skills/ not found at $DIST_SKILLS"
    err "  This is committed in the repository — re-clone or run ./scripts/build.sh"
    exit 1
  fi
  if [ -n "$ONLY_SKILL" ] && [ ! -d "$DIST_SKILLS/$ONLY_SKILL" ]; then
    err "skill '$ONLY_SKILL' not found under dist/skills/"
    err "  Available:"
    for d in "$DIST_SKILLS"/*/; do
      [ -d "$d" ] && err "    - $(basename "$d")"
    done
    exit 1
  fi
}

ensure_plugin_src() {
  if [ ! -d "$DIST_PLUGIN" ]; then
    err "dist/plugin/ not found at $DIST_PLUGIN"
    err "  Run: ./scripts/build.sh"
    err "  (dist/plugin/ is gitignored — built fresh each time)"
    exit 1
  fi
  if [ ! -f "$DIST_PLUGIN/.claude-plugin/plugin.json" ]; then
    err "dist/plugin/ is missing .claude-plugin/plugin.json — re-run ./scripts/build.sh"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Install actions
# ---------------------------------------------------------------------------

install_one_skill() {
  local name="$1"
  local src="$DIST_SKILLS/$name"
  local dst="$SKILLS_DEST/$name"
  run mkdir -p "$SKILLS_DEST"
  if [ -d "$dst" ]; then
    run rm -rf "$dst"
  fi
  run cp -R "$src" "$dst"
  ok "skill installed: $name -> $dst"
}

install_standalone() {
  ensure_skills_src
  info "installing standalone skills to $SKILLS_DEST"
  if [ -n "$ONLY_SKILL" ]; then
    install_one_skill "$ONLY_SKILL"
    return
  fi
  for d in "$DIST_SKILLS"/*/; do
    [ -d "$d" ] || continue
    install_one_skill "$(basename "$d")"
  done
}

install_plugin() {
  ensure_plugin_src
  info "installing plugin tree to $PLUGIN_DEST"
  run mkdir -p "$(dirname "$PLUGIN_DEST")"
  if [ -d "$PLUGIN_DEST" ]; then
    run rm -rf "$PLUGIN_DEST"
  fi
  run cp -R "$DIST_PLUGIN/" "$PLUGIN_DEST/"
  ok "plugin installed: $PLUGIN_DEST"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "$MODE" in
  standalone) install_standalone ;;
  plugin)     install_plugin ;;
  all)
    install_standalone
    install_plugin
    ;;
  *) err "internal error: unknown MODE=$MODE"; exit 1 ;;
esac

log ""
ok  "done — restart Claude Code to load the new skills/plugin"
