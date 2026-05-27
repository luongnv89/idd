#!/usr/bin/env bash
# install.sh — install IDD skills and/or plugin from a working tree.
#
# One-line install for users with a fresh clone of the repository who do
# not have `asm` (the recommended primary install tool — see README → Install).
# This is a thin wrapper around the supported install layouts:
#
#   - Standalone path: copy each `dist/skills/<name>/` to <tool>/skills/<name>/
#                      copy `dist/agents/*.md` to <tool>/agents/ (Claude + agents only)
#   - Plugin path:     copy `dist/plugin/` to ~/.claude/plugins/idd/ (Claude only)
#                      (requires a fresh build — `dist/plugin/` is gitignored)
#
# Each `dist/skills/<name>/` is a self-contained SKILL.md tree (the shared
# agents are bundled inside it at references/agents/), so it works on any
# SKILL.md-compatible tool. The standalone path therefore supports multiple
# tools. The shared-agents and plugin layouts are Claude Code concepts and
# only apply to the Claude target (and the universal `agents` target).
#
# Supported tools (--tool / --tools):
#   claude       ~/.claude/skills            + agents ~/.claude/agents       (default)
#   agents       ~/.agents/skills            + agents ~/.agents/agents
#   codex        ~/.codex/skills
#   opencode     ~/.config/opencode/skills
#   pi           ~/.pi/skills
#   openclaw     ~/.openclaw/skills
#   hermes       ~/.hermes/skills
#   antigravity  ~/.antigravity/skills
#   windsurf     ~/.windsurf/rules
#
# Idempotent: re-running cleans the destination directory first, so no
# duplicate files or stale references are left behind.
#
# Usage:
#   ./scripts/install.sh                  # interactive tool picker on a TTY;
#                                         # defaults to Claude when non-interactive
#   ./scripts/install.sh --tool codex     # install standalone skills for one tool (skips picker)
#   ./scripts/install.sh --tools all      # install standalone skills for every supported tool
#   ./scripts/install.sh --plugin         # install plugin tree (Claude only)
#   ./scripts/install.sh --all            # install both standalone + plugin (Claude)
#   ./scripts/install.sh --agents-only    # install shared agents only (Claude/agents)
#   ./scripts/install.sh --skill <n>      # install one named skill (standalone)
#   ./scripts/install.sh --target <dir>   # override Claude install root (default: ~/.claude)
#   ./scripts/install.sh --uninstall      # remove installed standalone skills + managed agents
#   ./scripts/install.sh --dry-run        # show what would be installed
#   ./scripts/install.sh --help           # this help text
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
TARGET_SET=0        # 1 once --target is given (only valid for the claude tool)
TOOLS=""            # space-separated list of selected tools; empty = default (claude)

# All supported tools, in display order. Paths mirror `asm config show`.
ALL_TOOLS="claude agents codex opencode pi openclaw hermes antigravity windsurf"

# Skills destination directory for a tool. For claude this honors --target;
# every other tool uses its fixed convention under $HOME.
tool_skills_dest() {
  case "$1" in
    claude)      printf '%s\n' "$TARGET/skills" ;;
    agents)      printf '%s\n' "${HOME}/.agents/skills" ;;
    codex)       printf '%s\n' "${HOME}/.codex/skills" ;;
    opencode)    printf '%s\n' "${HOME}/.config/opencode/skills" ;;
    pi)          printf '%s\n' "${HOME}/.pi/skills" ;;
    openclaw)    printf '%s\n' "${HOME}/.openclaw/skills" ;;
    hermes)      printf '%s\n' "${HOME}/.hermes/skills" ;;
    antigravity) printf '%s\n' "${HOME}/.antigravity/skills" ;;
    windsurf)    printf '%s\n' "${HOME}/.windsurf/rules" ;;
    *)           return 1 ;;
  esac
}

# Shared-agents destination for a tool, or empty if the tool has no agents
# layout. Shared agents are a Claude Code concept; the universal `agents`
# tool mirrors it. Other tools bundle the agents inside each skill instead.
# NOTE: ~/.agents/agents is an IDD-owned convention (asm tracks only
# ~/.agents/skills). cleanup_stale_agents treats every IDD-marked .md there
# as managed, so only IDD should write to this directory.
tool_agents_dest() {
  case "$1" in
    claude) printf '%s\n' "$TARGET/agents" ;;
    agents) printf '%s\n' "${HOME}/.agents/agents" ;;
    *)      printf '%s\n' "" ;;
  esac
}

is_valid_tool() {
  case " $ALL_TOOLS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Append a tool to TOOLS if not already present.
add_tool() {
  is_valid_tool "$1" || { err "unknown tool: $1"; err "  Supported: $ALL_TOOLS"; exit 1; }
  case " $TOOLS " in *" $1 "*) return 0 ;; esac
  TOOLS="${TOOLS:+$TOOLS }$1"
}

usage() {
  cat <<EOF
install.sh — install IDD skills/plugin from this working tree.

USAGE
  ./scripts/install.sh [--tool <name> | --tools <list|all>] [--skill <name>] [--target <dir>] [--dry-run]
  ./scripts/install.sh [--plugin | --all | --agents-only] [--skill <name>] [--target <dir>] [--dry-run]
  ./scripts/install.sh --uninstall [...same flags...]
  ./scripts/install.sh --help

OPTIONS
  --tool <name>      Install standalone skills for one tool (repeatable). Default: claude
  --tools <list>     Comma-separated tools, or "all" for every supported tool
                     (note: "--tools all" = every tool; "--all" = Claude skills+plugin)
  --plugin           Install plugin tree to <target>/plugins/idd/ (Claude only)
                     (requires running ./scripts/build.sh first to populate dist/plugin/)
  --all              Install both standalone skills and the plugin tree (Claude)
  --agents-only      Install shared agents to <target>/agents/ (Claude/agents only)
  --skill <name>     Standalone install of a single named skill (e.g. issue-resolver)
  --target <dir>     Override Claude root (default: \$HOME/.claude; claude tool only)
  --no-agents        Install standalone skills without updating shared agents
  --force-agents     Back up and replace unmanaged agent files with the same names
  --uninstall        Remove installed files instead of installing them
  --dry-run          Print actions without copying
  --help             Show this help

SUPPORTED TOOLS
  claude (default), agents, codex, opencode, pi, openclaw, hermes, antigravity, windsurf
  Shared agents install only for claude and agents; every other tool gets
  self-contained skills (the agents are bundled inside each skill).

EXAMPLES
  ./scripts/install.sh                          # interactive tool picker (TTY); Claude if non-interactive
  ./scripts/install.sh --tool codex             # all skills for Codex (skips the picker)
  ./scripts/install.sh --tools claude,codex,pi  # several tools at once
  ./scripts/install.sh --tools all              # every supported tool
  ./scripts/install.sh --skill issue-resolver --tool opencode   # one skill, one tool
  ./scripts/install.sh --agents-only            # shared agents only (Claude)
  ./scripts/install.sh --plugin                 # plugin only (run build.sh first)
  ./scripts/install.sh --all                    # everything (Claude)
  ./scripts/install.sh --tools all --uninstall  # remove skills from every tool
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

# Human-readable label for a tool (matches `asm config show` labels).
tool_label() {
  case "$1" in
    claude)      printf '%s\n' "Claude Code" ;;
    agents)      printf '%s\n' "Agents (universal ~/.agents)" ;;
    codex)       printf '%s\n' "Codex CLI" ;;
    opencode)    printf '%s\n' "OpenCode" ;;
    pi)          printf '%s\n' "Pi" ;;
    openclaw)    printf '%s\n' "OpenClaw" ;;
    hermes)      printf '%s\n' "Hermes" ;;
    antigravity) printf '%s\n' "Google Antigravity" ;;
    windsurf)    printf '%s\n' "Windsurf" ;;
    *)           printf '%s\n' "$1" ;;
  esac
}

# Interactively prompt for one or more tools, populating TOOLS. Falls back to
# the default (claude) on empty input. Reads from /dev/tty so it works even
# when the script is piped (e.g. curl | bash) as long as a terminal exists.
prompt_for_tools() {
  local -a tool_arr
  read -r -a tool_arr <<< "$ALL_TOOLS"

  {
    log ""
    log "◆ Select the tool(s) to install IDD skills for:"
    log "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
    local i=1
    for t in "${tool_arr[@]}"; do
      local suffix=""
      [ "$t" = "claude" ] && suffix="  (default)"
      printf '  %d) %-12s %s%s\n' "$i" "$t" "$(tool_label "$t")" "$suffix"
      i=$((i + 1))
    done
    log "  a) all of the above"
    log ""
    log "  Enter numbers (e.g. 1 3 4 or 1,3,4), 'a' for all, or press Enter for Claude Code."
  } >&2

  # Read the reply from stdin when it is a terminal (also lets tests feed a
  # here-string); otherwise read from /dev/tty so a piped `curl | bash` still
  # gets an interactive prompt.
  local reply
  printf '  > ' >&2
  if [ -t 0 ] || [ "${IDD_FORCE_PROMPT:-0}" = "1" ]; then
    read -r reply || reply=""
  else
    read -r reply </dev/tty || reply=""
  fi

  # Empty -> default to claude.
  if [ -z "$(printf '%s' "$reply" | tr -d '[:space:]')" ]; then
    add_tool "claude"
    return
  fi

  # 'a'/'all' -> every tool.
  case "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    a|all) for t in "${tool_arr[@]}"; do add_tool "$t"; done; return ;;
  esac

  # Otherwise parse space/comma-separated numbers.
  local cleaned
  cleaned="$(printf '%s' "$reply" | tr ',' ' ')"
  local token
  for token in $cleaned; do
    case "$token" in
      ''|*[!0-9]*)
        err "invalid selection: '$token' — enter list numbers, 'a', or Enter"; exit 1 ;;
    esac
    if [ "$token" -lt 1 ] || [ "$token" -gt "${#tool_arr[@]}" ]; then
      err "selection out of range: '$token' (valid: 1-${#tool_arr[@]})"; exit 1
    fi
    add_tool "${tool_arr[$((token - 1))]}"
  done
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin)    MODE="plugin"; shift ;;
    --all)       MODE="all"; shift ;;
    --agents-only) MODE="agents"; shift ;;
    --tool)
      [ $# -ge 2 ] || { err "--tool requires a name"; exit 1; }
      add_tool "$2"; shift 2 ;;
    --tools)
      [ $# -ge 2 ] || { err "--tools requires a comma-separated list or 'all'"; exit 1; }
      [ -n "$(printf '%s' "$2" | tr -d '[:space:]')" ] || \
        { err "--tools requires a non-empty list or 'all'"; exit 1; }
      if [ "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" = "all" ]; then
        for t in $ALL_TOOLS; do add_tool "$t"; done
      else
        IFS=',' read -r -a _tools <<< "$2"
        for t in "${_tools[@]+"${_tools[@]}"}"; do
          t="$(printf '%s' "$t" | tr -d '[:space:]')"
          [ -n "$t" ] && add_tool "$t"
        done
      fi
      shift 2 ;;
    --skill)
      [ $# -ge 2 ] || { err "--skill requires a name"; exit 1; }
      ONLY_SKILL="$2"; shift 2 ;;
    --target)
      [ $# -ge 2 ] || { err "--target requires a directory"; exit 1; }
      TARGET="$2"; TARGET_SET=1; shift 2 ;;
    --no-agents) INSTALL_AGENTS=0; shift ;;
    --force-agents) FORCE_AGENTS=1; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           err "Unknown argument: $1"; usage >&2; exit 1 ;;
  esac
done

# Resolve the tool selection when none was given on the command line.
# For a standalone install on an interactive terminal, prompt the user to
# pick one or more tools. Otherwise (non-TTY, or plugin/agents-only modes
# which are Claude-scoped) fall back to the Claude default silently.
# IDD_FORCE_PROMPT=1 forces the prompt regardless of TTY (used by tests).
if [ -z "$TOOLS" ]; then
  if [ "$MODE" = "standalone" ] && \
     { [ "${IDD_FORCE_PROMPT:-0}" = "1" ] || { [ -t 0 ] && [ -r /dev/tty ]; }; }; then
    prompt_for_tools
  fi
  [ -n "$TOOLS" ] || TOOLS="claude"
fi

# --target only makes sense for the claude tool (other tools use fixed paths).
if [ "$TARGET_SET" -eq 1 ]; then
  case " $TOOLS " in
    *" claude "*) : ;;
    *) err "--target only applies to the claude tool; selected: $TOOLS"; exit 1 ;;
  esac
fi

# Plugin and shared-agents layouts are Claude Code concepts. Reject them when a
# tool without an agents/plugin layout is selected (everything except claude
# and agents; the plugin tree is claude-only).
case "$MODE" in
  plugin|all)
    case " $TOOLS " in
      *" claude "*) : ;;
      *) err "--plugin / --all install the Claude plugin tree and only apply to the claude tool"; exit 1 ;;
    esac ;;
  agents)
    for t in $TOOLS; do
      [ -n "$(tool_agents_dest "$t")" ] || {
        err "--agents-only does not apply to '$t' (no shared-agents layout); use claude or agents"; exit 1; }
    done ;;
esac

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
  local skills_dest="$2"
  local src="$DIST_SKILLS/$name"
  local dst="$skills_dest/$name"
  run mkdir -p "$skills_dest"
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
  local agents_dest="$2"
  local file
  file="$(basename "$src")"
  local name="${file%.md}"
  local dst="$agents_dest/$file"

  run mkdir -p "$agents_dest"
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
  local agents_dest="$1"
  if [ ! -d "$agents_dest" ]; then
    return 0
  fi
  for f in "$agents_dest"/*.md; do
    [ -f "$f" ] || continue
    is_idd_managed_agent "$f" || continue
    if [ ! -f "$DIST_AGENTS/$(basename "$f")" ]; then
      run rm -f "$f"
      ok "stale managed agent removed: $(basename "$f" .md)"
    fi
  done
}

install_agents() {
  local agents_dest="$1"
  ensure_agents_src
  info "installing shared agents to $agents_dest"
  cleanup_stale_agents "$agents_dest"
  for f in "$DIST_AGENTS"/*.md; do
    [ -f "$f" ] || continue
    install_one_agent "$f" "$agents_dest"
  done
}

# Install standalone skills (and, where applicable, shared agents) for one tool.
install_standalone_tool() {
  local tool="$1"
  local skills_dest agents_dest
  skills_dest="$(tool_skills_dest "$tool")"
  agents_dest="$(tool_agents_dest "$tool")"

  info "[$tool] installing standalone skills to $skills_dest"
  if [ -n "$ONLY_SKILL" ]; then
    install_one_skill "$ONLY_SKILL" "$skills_dest"
  else
    for d in "$DIST_SKILLS"/*/; do
      [ -d "$d" ] || continue
      install_one_skill "$(basename "$d")" "$skills_dest"
    done
  fi

  # Shared agents only for tools that have an agents layout (claude, agents).
  if [ "$INSTALL_AGENTS" -eq 1 ] && [ -n "$agents_dest" ]; then
    install_agents "$agents_dest"
  fi
}

install_standalone() {
  ensure_skills_src
  for tool in $TOOLS; do
    install_standalone_tool "$tool"
  done
}

install_plugin() {
  # Plugin tree is a Claude Code concept — always installs under $TARGET.
  local plugin_dest="$TARGET/plugins/idd"
  ensure_plugin_src
  info "installing plugin tree to $plugin_dest"
  run mkdir -p "$(dirname "$plugin_dest")"
  if [ -d "$plugin_dest" ]; then
    run rm -rf "$plugin_dest"
  fi
  run cp -R "$DIST_PLUGIN/" "$plugin_dest/"
  ok "plugin installed: $plugin_dest"
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
  local agents_dest="$1"
  ensure_agents_src
  if [ ! -d "$agents_dest" ]; then
    info "agents not installed: $agents_dest"
    return
  fi
  info "removing IDD-managed agents from $agents_dest"
  for src in "$DIST_AGENTS"/*.md; do
    [ -f "$src" ] || continue
    local dst="$agents_dest/$(basename "$src")"
    if [ ! -f "$dst" ]; then
      info "agent not installed: $(basename "$src" .md)"
    elif is_idd_managed_agent "$dst"; then
      run rm -f "$dst"
      ok "agent removed: $(basename "$src" .md)"
    else
      warn "left unmanaged agent untouched: $dst"
    fi
  done
  cleanup_stale_agents "$agents_dest"
}

# Remove standalone skills (and, where applicable, shared agents) for one tool.
uninstall_standalone_tool() {
  local tool="$1"
  local skills_dest agents_dest
  skills_dest="$(tool_skills_dest "$tool")"
  agents_dest="$(tool_agents_dest "$tool")"

  if [ -n "$ONLY_SKILL" ]; then
    remove_path "[$tool] skill" "$skills_dest/$ONLY_SKILL"
    [ -n "$agents_dest" ] && info "[$tool] agents left installed because --skill targets one skill only"
    return
  fi
  for d in "$DIST_SKILLS"/*/; do
    [ -d "$d" ] || continue
    remove_path "[$tool] skill" "$skills_dest/$(basename "$d")"
  done
  if [ "$INSTALL_AGENTS" -eq 1 ] && [ -n "$agents_dest" ]; then
    uninstall_agents "$agents_dest"
  fi
}

uninstall_standalone() {
  ensure_skills_src
  for tool in $TOOLS; do
    uninstall_standalone_tool "$tool"
  done
}

uninstall_plugin() {
  remove_path "plugin" "$TARGET/plugins/idd"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

case "$ACTION:$MODE" in
  install:standalone) install_standalone ;;
  install:agents)
    ensure_agents_src
    for tool in $TOOLS; do
      install_agents "$(tool_agents_dest "$tool")"
    done ;;
  install:plugin)     install_plugin ;;
  install:all)
    install_standalone
    install_plugin
    ;;
  uninstall:standalone) uninstall_standalone ;;
  uninstall:agents)
    for tool in $TOOLS; do
      uninstall_agents "$(tool_agents_dest "$tool")"
    done ;;
  uninstall:plugin)     uninstall_plugin ;;
  uninstall:all)
    uninstall_standalone
    uninstall_plugin
    ;;
  *) err "internal error: unknown ACTION=$ACTION MODE=$MODE"; exit 1 ;;
esac

log ""
if [ "$ACTION" = "install" ]; then
  ok "done — restart your agent tool(s) to load the new skills/agents/plugin"
else
  ok "done — restart your agent tool(s) to unload removed skills/agents/plugin"
fi
