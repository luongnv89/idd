#!/usr/bin/env bash
# verify_flattened_skills.sh — URL-aware self-containment check for flattened skills.
#
# Usage:
#   ./scripts/verify_flattened_skills.sh <skills-root>
#   ./scripts/verify_flattened_skills.sh /path/to/dist/skills
#   ./scripts/verify_flattened_skills.sh /path/to/repo/skills
#
# Exit 0 when every skill under <skills-root> passes; exit 1 on any failure.
# Mirrors semantics in tests/test-flattened-self-contained.sh.

set -euo pipefail

SKILLS_ROOT="${1:-}"
if [[ -z "$SKILLS_ROOT" || ! -d "$SKILLS_ROOT" ]]; then
  printf '✗ usage: %s <skills-root>\n' "$(basename "$0")" >&2
  exit 1
fi

SKILLS_ROOT="$(cd -- "$SKILLS_ROOT" && pwd)"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
SRC_SKILLS="$ROOT/src/skills"

scan_file() {
  python3 - "$1" "$2" <<'PY'
import re
import sys
from pathlib import Path

filepath = Path(sys.argv[1])
skill_dir = Path(sys.argv[2])
text = filepath.read_text(encoding="utf-8", errors="replace")

URL_RE = re.compile(r"https?://[^\s<>'\"\)]+")
SHARED_AGENT_RE = re.compile(r"(?<![\w/])shared/agents/([a-z][a-z0-9-]+\.md)")
RUNTIME_DOC_RE = re.compile(r"(?<![\w/])docs/([a-z][a-z0-9-]+\.md)")
BARE_SKILL_PATH_RE = re.compile(r"(?<![\w/])skills/([a-z][a-z0-9-]+)/SKILL\.md")
SKILL_TOKEN_RE = re.compile(r"\{\{skill:([a-z][a-z0-9-]*)\}\}")
SHARED_SCRIPT_RE = re.compile(r"(?<![\w/])shared/scripts/([a-z][a-z0-9-]+\.py)")
LOCAL_SCRIPT_RE = re.compile(r"(?<![\w/])references/scripts/([a-z][a-z0-9-]+\.py)")

masked = URL_RE.sub(lambda m: " " * len(m.group(0)), text)
errors = []

for m in SHARED_AGENT_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"unresolved 'shared/agents/{m.group(1)}' at line {line_no}")

for m in RUNTIME_DOC_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"unresolved 'docs/{m.group(1)}' at line {line_no}")

for m in SHARED_SCRIPT_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"unresolved 'shared/scripts/{m.group(1)}' at line {line_no}")

for m in BARE_SKILL_PATH_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"bare 'skills/{m.group(1)}/SKILL.md' at line {line_no}")

for m in SKILL_TOKEN_RE.finditer(masked):
    line_no = masked[: m.start()].count("\n") + 1
    errors.append(f"unresolved '{{{{skill:{m.group(1)}}}}}' token at line {line_no}")

LOCAL_AGENT_RE = re.compile(r"(?<![\w/])references/agents/([a-z][a-z0-9-]+\.md)")
LOCAL_DOC_RE = re.compile(r"(?<![\w/])references/docs/([a-z][a-z0-9-]+\.md)")

for m in LOCAL_AGENT_RE.finditer(masked):
    target = skill_dir / "references" / "agents" / m.group(1)
    if not target.is_file():
        line_no = masked[: m.start()].count("\n") + 1
        errors.append(f"missing referenced agent file '{target.name}' at line {line_no}")

for m in LOCAL_DOC_RE.finditer(masked):
    target = skill_dir / "references" / "docs" / m.group(1)
    if not target.is_file():
        line_no = masked[: m.start()].count("\n") + 1
        errors.append(f"missing referenced doc file '{target.name}' at line {line_no}")

for m in LOCAL_SCRIPT_RE.finditer(masked):
    target = skill_dir / "references" / "scripts" / m.group(1)
    if not target.is_file():
        line_no = masked[: m.start()].count("\n") + 1
        errors.append(f"missing referenced script file '{target.name}' at line {line_no}")

if errors:
    print(f"FAIL: {filepath}")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
sys.exit(0)
PY
}

failures=0

# Every public src skill must appear in the build output.
if [[ -d "$SRC_SKILLS" ]]; then
  for src_skill_dir in "$SRC_SKILLS"/*/; do
    [[ -d "$src_skill_dir" ]] || continue
    name="$(basename "$src_skill_dir")"
    if [[ ! -f "$SKILLS_ROOT/$name/SKILL.md" ]]; then
      printf '✗ missing public skill output: %s/SKILL.md\n' "$name" >&2
      failures=$((failures + 1))
    fi
  done
fi

for skill_dir in "$SKILLS_ROOT"/*/; do
  [[ -d "$skill_dir" ]] || continue
  name="$(basename "$skill_dir")"
  if [[ ! -f "$skill_dir/SKILL.md" ]]; then
    printf '✗ %s: SKILL.md missing\n' "$name" >&2
    failures=$((failures + 1))
    continue
  fi
  errors_in_skill=0
  while IFS= read -r f; do
    if ! scan_file "$f" "$skill_dir"; then
      errors_in_skill=$((errors_in_skill + 1))
    fi
  done < <(find "$skill_dir" -type f \( \
      -name "*.md" -o -name "*.txt" -o -name "*.yml" \
      -o -name "*.yaml" -o -name "*.json" -o -name "*.toml" \
      -o -name "*.py" -o -name "*.sh" \
    \))
  if [[ "$errors_in_skill" -gt 0 ]]; then
    printf '✗ %s: %s file(s) with unresolved references\n' "$name" "$errors_in_skill" >&2
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
exit 0