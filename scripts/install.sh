#!/usr/bin/env bash
# install.sh — install IDD skills and/or plugin from a working tree.
#
# One-line install for users with a fresh clone of the repository who do
# not have `asm` (the recommended primary install tool — see README → Install).
# This is a thin wrapper around the supported install layouts:
#
#   - Standalone path: copy each `dist/skills/<name>/` to ~/.claude/skills/<name>/
#                      copy `dist/agents/*.md` to ~/.claude/agents/
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
#   ./scripts/install.sh --agents-only  # install Claude Code agents only
#   ./scripts/install.sh --skill <n>    # install one named skill (standalone)
#   ./scripts/install.sh --target <dir> # override Claude install root (default: ~/.claude)
#   ./scripts/install.sh --uninstall    # remove installed standalone skills + managed agents
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
DIST_AGENTS="$ROOT/dist/agents"
DIST_PLUGIN="$ROOT/dist/plugin"
TARGET="${HOME}/.claude"
MODE="standalone"   # standalone | agents | plugin | all
ACTION="install"    # install | uninstall
ONLY_SKILL=""
DRY_RUN=0
INSTALL_AGENTS=1
FORCE_AGENTS=0

usage() {
  cat <<EOF
install.sh — install IDD skills/plugin from this working tree.

USAGE
  ./scripts/install.sh [--plugin | --all | --agents-only] [--skill <name>] [--target <dir>] [--dry-run]
  ./scripts/install.sh --uninstall [--plugin | --all] [--skill <name>] [--target <dir>] [--dry-run]
  ./scripts/install.sh --help

OPTIONS
  --plugin           Install plugin tree to <target>/plugins/idd/
                     (requires running ./scripts/build.sh first to populate dist/plugin/)
  --all              Install both standalone skills and the plugin tree
  --agents-only      Install shared Claude Code agents to <target>/agents/
  --skill <name>     Standalone install of a single named skill (e.g. issue-resolver)
  --target <dir>     Override Claude root (default: \$HOME/.claude)
  --no-agents        Install standalone skills without updating shared agents
  --force-agents     Back up and replace unmanaged agent files with the same names
  --uninstall        Remove installed files instead of installing them
  --dry-run          Print actions without copying
  --help             Show this help

EXAMPLES
  ./scripts/install.sh                          # all standalone skills
  ./scripts/install.sh --skill issue-resolver   # one skill
  ./scripts/install.sh --agents-only             # agents only
  ./scripts/install.sh --plugin                 # plugin only (run build.sh first)
  ./scripts/install.sh --all                    # everything
  ./scripts/install.sh --uninstall              # remove standalone skills + managed agents
EOF
}

log()  { printf '%s\n' "$*"; }
info() { log "○ $*"; }
ok()   { log "✓ $*"; }
warn() { log "⚠ $*"; }
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
    --agents-only) MODE="agents"; shift ;;
    --skill)
      [ $# -ge 2 ] || { err "--skill requires a name"; exit 1; }
      ONLY_SKILL="$2"; shift 2 ;;
    --target)
      [ $# -ge 2 ] || { err "--target requires a directory"; exit 1; }
      TARGET="$2"; shift 2 ;;
    --no-agents) INSTALL_AGENTS=0; shift ;;
    --force-agents) FORCE_AGENTS=1; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           err "Unknown argument: $1"; usage >&2; exit 1 ;;
  esac
done

SKILLS_DEST="$TARGET/skills"
AGENTS_DEST="$TARGET/agents"
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

ensure_agents_src() {
  if [ ! -d "$DIST_AGENTS" ]; then
    err "dist/agents/ not found at $DIST_AGENTS"
    err "  Run: ./scripts/build.sh"
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

is_idd_managed_agent() {
  local path="$1"
  [ -f "$path" ] || return 1
  grep -q 'Managed by IDD installer' "$path" 2>/dev/null || \
    grep -q 'Generated from /src/shared/agents/' "$path" 2>/dev/null
}

install_one_agent() {
  local src="$1"
  local file
  file="$(basename "$src")"
  local name="${file%.md}"
  local dst="$AGENTS_DEST/$file"

  run mkdir -p "$AGENTS_DEST"
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      ok "agent current: $name -> $dst"
      return
    fi

    if is_idd_managed_agent "$dst"; then
      info "updating managed agent: $name"
    elif [ "$FORCE_AGENTS" -eq 1 ]; then
      local backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
      warn "backing up unmanaged agent before replace: $backup"
      run cp "$dst" "$backup"
    else
      warn "agent exists and is not IDD-managed; skipped: $dst"
      warn "  Re-run with --force-agents to back it up and replace it."
      return
    fi
  fi

  run cp "$src" "$dst"
  ok "agent installed: $name -> $dst"
}

cleanup_stale_agents() {
  if [ ! -d "$AGENTS_DEST" ]; then
    return 0
  fi
  for f in "$AGENTS_DEST"/*.md; do
    [ -f "$f" ] || continue
    is_idd_managed_agent "$f" || continue
    if [ ! -f "$DIST_AGENTS/$(basename "$f")" ]; then
      run rm -f "$f"
      ok "stale managed agent removed: $(basename "$f" .md)"
    fi
  done
}

install_agents() {
  ensure_agents_src
  info "installing shared Claude Code agents to $AGENTS_DEST"
  cleanup_stale_agents
  for f in "$DIST_AGENTS"/*.md; do
    [ -f "$f" ] || continue
    install_one_agent "$f"
  done
}

install_standalone() {
  ensure_skills_src
  info "installing standalone skills to $SKILLS_DEST"
  if [ -n "$ONLY_SKILL" ]; then
    install_one_skill "$ONLY_SKILL"
    if [ "$INSTALL_AGENTS" -eq 1 ]; then
      install_agents
    fi
    return
  fi
  for d in "$DIST_SKILLS"/*/; do
    [ -d "$d" ] || continue
    install_one_skill "$(basename "$d")"
  done
  if [ "$INSTALL_AGENTS" -eq 1 ]; then
    install_agents
  fi
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

remove_path() {
  local label="$1"
  local path="$2"
  if [ -e "$path" ]; then
    run rm -rf "$path"
    ok "$label removed: $path"
  else
    info "$label not installed: $path"
  fi
}

uninstall_agents() {
  ensure_agents_src
  if [ ! -d "$AGENTS_DEST" ]; then
    info "agents not installed: $AGENTS_DEST"
    return
  fi
  info "removing IDD-managed agents from $AGENTS_DEST"
  for src in "$DIST_AGENTS"/*.md; do
    [ -f "$src" ] || continue
    local dst="$AGENTS_DEST/$(basename "$src")"
    if [ ! -f "$dst" ]; then
      info "agent not installed: $(basename "$src" .md)"
    elif is_idd_managed_agent "$dst"; then
      run rm -f "$dst"
      ok "agent removed: $(basename "$src" .md)"
    else
      warn "left unmanaged agent untouched: $dst"
    fi
  done
  cleanup_stale_agents
}

uninstall_standalone() {
  ensure_skills_src
  if [ -n "$ONLY_SKILL" ]; then
    remove_path "skill" "$SKILLS_DEST/$ONLY_SKILL"
    info "agents left installed because --skill targets one skill only"
    return
  fi
  for d in "$DIST_SKILLS"/*/; do
    [ -d "$d" ] || continue
    remove_path "skill" "$SKILLS_DEST/$(basename "$d")"
  done
  if [ "$INSTALL_AGENTS" -eq 1 ]; then
    uninstall_agents
  fi
}

uninstall_plugin() {
  remove_path "plugin" "$PLUGIN_DEST"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "$ACTION:$MODE" in
  install:standalone) install_standalone ;;
  install:agents)     install_agents ;;
  install:plugin)     install_plugin ;;
  install:all)
    install_standalone
    install_plugin
    ;;
  uninstall:standalone) uninstall_standalone ;;
  uninstall:agents)     uninstall_agents ;;
  uninstall:plugin)     uninstall_plugin ;;
  uninstall:all)
    uninstall_standalone
    uninstall_plugin
    ;;
  *) err "internal error: unknown ACTION=$ACTION MODE=$MODE"; exit 1 ;;
esac

log ""
if [ "$ACTION" = "install" ]; then
  ok "done — restart Claude Code to load the new skills/agents/plugin"
else
  ok "done — restart Claude Code to unload removed skills/agents/plugin"
fi
