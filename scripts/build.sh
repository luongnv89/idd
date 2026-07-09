#!/usr/bin/env bash
# build.sh — build dist outputs, verify flattened skills, then update skills/.
#
# Workflow (local and CI):
#   1. Compile all skills (and agents) under <out>/ — does not touch skills/
#   2. Verify <out>/skills/ is complete and self-contained
#   3. On success only, replace repo-root skills/ from <out>/skills/
#
# Usage:
#   ./scripts/build.sh                 # out=dist/, then promote skills/
#   ./scripts/build.sh --out /tmp/a    # build only (no promote; custom out)
#   ./scripts/build.sh --no-promote-skills
#   ./scripts/build.sh --quiet         # minimal stdout on success
#   ./scripts/build.sh -v              # verbose build.py output
#
# Exit codes:
#   0  success
#   1  preflight, build, verify, or promote failure

set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "$0" ]]; then
  printf '✗ scripts/build.sh must be executed, not sourced\n' >&2
  return 2 2>/dev/null || exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_PY="$SCRIPT_DIR/build.py"
VERIFY_SH="$SCRIPT_DIR/verify_flattened_skills.sh"
ROOT_SKILLS="$ROOT/skills"
CANONICAL_DIST="$ROOT/dist"

_log() { printf '%s\n' "$*"; }
info() { _log "○ $*"; }
ok()   { _log "✓ $*"; }
warn() { _log "⚠ $*"; }
err()  { _log "✗ $*" >&2; }
die()  { err "$1"; exit "${2:-1}"; }

BUILD_QUIET=0
PROMOTE_SKILLS=1
PY_ARGS=()

filter_args() {
  PY_ARGS=()
  PROMOTE_SKILLS=1
  local i=1
  while [[ $i -le $# ]]; do
    local arg="${!i}"
    case "$arg" in
      --quiet|-q)
        BUILD_QUIET=1
        ;;
      --no-promote-skills)
        PROMOTE_SKILLS=0
        ;;
      *)
        PY_ARGS+=("$arg")
        ;;
    esac
    i=$((i + 1))
  done
}

has_verbose_flag() {
  local a
  for a in ${1+"$@"}; do
    case "$a" in
      -v|--verbose) return 0 ;;
    esac
  done
  return 1
}

py_invoke() {
  local extra=()
  if [[ $# -gt 0 ]]; then
    extra=("$@")
  fi
  if [[ ${#extra[@]} -eq 0 && ${#PY_ARGS[@]} -eq 0 ]]; then
    python3 "$BUILD_PY"
  elif [[ ${#extra[@]} -eq 0 ]]; then
    python3 "$BUILD_PY" "${PY_ARGS[@]}"
  elif [[ ${#PY_ARGS[@]} -eq 0 ]]; then
    python3 "$BUILD_PY" "${extra[@]}"
  else
    python3 "$BUILD_PY" "${extra[@]}" "${PY_ARGS[@]}"
  fi
}

resolve_out_dir() {
  local out="dist"
  local i=0
  while [[ $i -lt ${#PY_ARGS[@]} ]]; do
    local arg="${PY_ARGS[$i]}"
    case "$arg" in
      --out=*)
        out="${arg#--out=}"
        ;;
      --out)
        local next=$((i + 1))
        if [[ $next -lt ${#PY_ARGS[@]} ]]; then
          out="${PY_ARGS[$next]}"
        fi
        ;;
    esac
    i=$((i + 1))
  done
  if [[ "$out" != /* ]]; then
    printf '%s\n' "$ROOT/$out"
  else
    printf '%s\n' "$out"
  fi
}

should_promote_skills() {
  [[ "$PROMOTE_SKILLS" -eq 1 ]] || return 1
  local out_dir
  out_dir="$(resolve_out_dir)"
  [[ "$out_dir" == "$CANONICAL_DIST" ]] || return 1
  return 0
}

preflight() {
  if [[ ! -f "$BUILD_PY" ]]; then
    die "build driver missing: $BUILD_PY" 1
  fi
  if [[ ! -x "$VERIFY_SH" && ! -f "$VERIFY_SH" ]]; then
    die "verify script missing: $VERIFY_SH" 1
  fi
  chmod +x "$VERIFY_SH" 2>/dev/null || true

  if ! command -v python3 >/dev/null 2>&1; then
    err "python3 not found on PATH"
    err "  Fix: install Python 3.11+"
    exit 1
  fi

  local py_major py_minor
  py_major="$(python3 -c 'import sys; print(sys.version_info.major)' 2>/dev/null || echo "0")"
  py_minor="$(python3 -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo "0")"
  if [[ "$py_major" -lt 3 ]] || { [[ "$py_major" -eq 3 ]] && [[ "$py_minor" -lt 11 ]]; }; then
    err "Python 3.11+ required"
    exit 1
  fi

  local src_dir="$ROOT/src"
  local i=0
  while [[ $i -lt ${#PY_ARGS[@]} ]]; do
    local arg="${PY_ARGS[$i]}"
    case "$arg" in
      --src=*)
        src_dir="${arg#--src=}"
        break
        ;;
      --src)
        local next=$((i + 1))
        if [[ $next -lt ${#PY_ARGS[@]} ]]; then
          src_dir="${PY_ARGS[$next]}"
        fi
        break
        ;;
    esac
    i=$((i + 1))
  done
  if [[ ! -d "$src_dir" ]]; then
    err "source tree not found: $src_dir"
    exit 1
  fi
}

run_compile() {
  local verbose_args=()
  if ! has_verbose_flag ${PY_ARGS[@]+"${PY_ARGS[@]}"}; then
    verbose_args=(-v)
  fi

  # Never let build.py overwrite skills/; promote only after verify (step 3).
  local compile_args=(--no-root-skills)

  local out_dir
  out_dir="$(resolve_out_dir)"
  local skills_out="$out_dir/skills"

  if [[ "$BUILD_QUIET" -eq 0 ]]; then
    _log "◆ IDD build"
    _log "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
    info "step 1/3: compile skills → $skills_out"
  fi

  local log_file="" status=0
  if [[ "$BUILD_QUIET" -eq 1 ]]; then
    log_file="$(mktemp "${TMPDIR:-/tmp}/idd-build.XXXXXX")"
    # Capture status in the else branch: an if with a false condition and no
    # else returns 0, so `status=$?` after a bare if/then/fi would read the
    # if's success, not py_invoke's failure (silently swallowing build aborts).
    if py_invoke ${verbose_args[@]+"${verbose_args[@]}"} "${compile_args[@]}" >"$log_file" 2>&1; then
      rm -f "$log_file"
      return 0
    else
      status=$?
      err "compile failed (exit $status)"
      sed 's/^/  /' "$log_file" >&2
      rm -f "$log_file"
      return "$status"
    fi
  fi

  if py_invoke ${verbose_args[@]+"${verbose_args[@]}"} "${compile_args[@]}"; then
    return 0
  else
    status=$?
    err "compile failed (exit $status)"
    return "$status"
  fi
}

run_verify() {
  local out_dir
  out_dir="$(resolve_out_dir)"
  local skills_out="$out_dir/skills"

  if [[ "$BUILD_QUIET" -eq 0 ]]; then
    info "step 2/3: verify flattened skills"
  fi

  if [[ ! -d "$skills_out" ]]; then
    err "verify failed: $skills_out not found"
    return 1
  fi

  local log_file="" status=0
  if [[ "$BUILD_QUIET" -eq 1 ]]; then
    log_file="$(mktemp "${TMPDIR:-/tmp}/idd-verify.XXXXXX")"
    # Capture status in the else branch (see run_compile): a false if with no
    # else returns 0, which would mask verify failures otherwise.
    if bash "$VERIFY_SH" "$skills_out" >"$log_file" 2>&1; then
      rm -f "$log_file"
      if [[ "$BUILD_QUIET" -eq 0 ]]; then ok "skills verification passed"; fi
      return 0
    else
      status=$?
      err "skills verification failed"
      sed 's/^/  /' "$log_file" >&2
      rm -f "$log_file"
      err "  skills/ was not updated (previous tree unchanged)"
      return "$status"
    fi
  fi

  if bash "$VERIFY_SH" "$skills_out"; then
    ok "skills verification passed"
    return 0
  else
    status=$?
    err "skills verification failed"
    err "  skills/ was not updated (previous tree unchanged)"
    return "$status"
  fi
}

run_promote() {
  if ! should_promote_skills; then
    if [[ "$BUILD_QUIET" -eq 0 ]]; then
      info "step 3/3: skip promote (custom --out or --no-promote-skills)"
    fi
    return 0
  fi

  local out_dir
  out_dir="$(resolve_out_dir)"
  local skills_out="$out_dir/skills"

  if [[ "$BUILD_QUIET" -eq 0 ]]; then
    info "step 3/3: update skills/ from verified build"
  fi

  if [[ ! -d "$skills_out" ]]; then
    err "promote failed: $skills_out missing"
    return 1
  fi

  rm -rf "$ROOT_SKILLS"
  cp -R "$skills_out" "$ROOT_SKILLS"

  if [[ "$BUILD_QUIET" -eq 0 ]]; then
    ok "skills/ updated → $ROOT_SKILLS"
    _log "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
    ok "build finished"
  fi
  return 0
}

main() {
  filter_args "$@"
  preflight
  run_compile || exit 1
  run_verify || exit 1
  run_promote || exit 1
}

main "$@"