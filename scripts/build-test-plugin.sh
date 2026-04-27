#!/usr/bin/env bash
# build-test-plugin.sh — scaffold dist/test-plugin/ for §6.0 cross-skill experiments.
#
# Throwaway scaffold for refactor-plan-v10 §6.0 (issue #52). Removed in PR 3 once
# scripts/build.py is the source of truth.
#
# What it does:
#   1. Computes the transitive closure of shared/agents/* and docs/* references
#      starting from {issue-creator, issue-resolver, auto-pilot}.
#   2. Flattens those skills into dist/test-plugin/skills/<name>/ with their
#      references/, templates/, README.md, SKILL.md preserved.
#   3. Copies referenced shared/agents/*.md to dist/test-plugin/shared/agents/.
#   4. Copies referenced docs/*.md to dist/test-plugin/docs/.
#   5. Writes a hand-curated minimal .claude-plugin/plugin.json (slug: idd-test).
#   6. Drops Experiment C's prompt file at
#      dist/test-plugin/skills/auto-pilot/references/c-test.md.
#
# Not what it does:
#   - It does NOT rewrite cross-skill, shared-agent, or runtime-doc references
#     inside the copied files. That rewriting is the production build's job
#     (#56), and getting it right here would prejudge the §6.0 experiment.
#     Experiments B and C measure runtime resolution of the *plugin-layout*
#     paths, which is what we deliver — content rewriting is orthogonal.
#
# Compatible with stock macOS bash 3.2 — no mapfile, no associative arrays.

set -eu

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
SRC="$ROOT/src"
OUT="$ROOT/dist/test-plugin"
SKILLS_TO_INCLUDE="issue-creator issue-resolver auto-pilot"

if [ ! -d "$SRC/skills" ]; then
  echo "✗ $SRC/skills not found — run from repo root with src/ tree" >&2
  exit 1
fi

echo "● Building test plugin scaffold at $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/.claude-plugin" "$OUT/skills" "$OUT/shared/agents" "$OUT/docs"

# --- Copy seed skills ---------------------------------------------------------
for skill in $SKILLS_TO_INCLUDE; do
  src_dir="$SRC/skills/$skill"
  if [ ! -d "$src_dir" ]; then
    echo "✗ src/skills/$skill not found" >&2
    exit 1
  fi
  cp -R "$src_dir" "$OUT/skills/$skill"
  echo "  ✓ skill: $skill"
done

# --- Compute transitive closure of shared/agents and docs references ----------
# A reference is any token matching shared/agents/<name>.md or docs/<name>.md
# inside a markdown file. We BFS over agents (agents may reference docs and
# other agents) until no new files are discovered.
#
# Visited tracking uses sentinel files in a tempdir (bash 3.2 has no
# associative arrays).

state_dir="$(mktemp -d)"
trap 'rm -rf "$state_dir"' EXIT
mkdir -p "$state_dir/agents" "$state_dir/docs" "$state_dir/queue"

agent_count=0
doc_count=0
queue_id=0

# Initial scan target: everything under the included skills.
new_files_list="$state_dir/queue/0"
find "$OUT/skills" -type f -name '*.md' > "$new_files_list"

while [ -s "$new_files_list" ]; do
  # Extract refs from the current batch of files. xargs -0 isn't needed since
  # find produces newline-separated paths and we're feeding to grep.
  refs="$(xargs grep -hoE '(shared/agents|docs)/[a-z][a-z0-9-]+\.md' < "$new_files_list" 2>/dev/null \
            | sort -u || true)"

  queue_id=$((queue_id + 1))
  next_files_list="$state_dir/queue/$queue_id"
  : > "$next_files_list"

  # IFS=newline so refs with no embedded spaces work. printf '%s\n' / read -r is
  # the standard portable idiom.
  if [ -n "$refs" ]; then
    printf '%s\n' "$refs" | while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      case "$ref" in
        shared/agents/*)
          name="${ref#shared/agents/}"
          if [ ! -e "$state_dir/agents/$name" ] && [ -f "$SRC/shared/agents/$name" ]; then
            : > "$state_dir/agents/$name"
            cp "$SRC/shared/agents/$name" "$OUT/shared/agents/$name"
            echo "$OUT/shared/agents/$name" >> "$next_files_list"
            echo "  ✓ agent: $name"
          fi
          ;;
        docs/*)
          name="${ref#docs/}"
          if [ ! -e "$state_dir/docs/$name" ] && [ -f "$SRC/docs/$name" ]; then
            : > "$state_dir/docs/$name"
            cp "$SRC/docs/$name" "$OUT/docs/$name"
            # Docs may reference other docs; rescanning them is cheap and
            # correct.
            echo "$OUT/docs/$name" >> "$next_files_list"
            echo "  ✓ doc: $name"
          fi
          ;;
      esac
    done
  fi

  new_files_list="$next_files_list"
done

agent_count="$(ls "$state_dir/agents" 2>/dev/null | wc -l | tr -d ' ')"
doc_count="$(ls "$state_dir/docs" 2>/dev/null | wc -l | tr -d ' ')"

# --- Write minimal plugin.json ------------------------------------------------
# Hand-curated; matches the layout that the production build will emit. Slug
# `idd-test` so an installed test plugin doesn't collide with `idd`.
cat > "$OUT/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "IDD Test Plugin",
  "slug": "idd-test",
  "description": "Throwaway scaffold for refactor-plan-v10 §6.0 cross-skill invocation experiments. Not a release artifact.",
  "version": "0.0.0-experiment",
  "skills": [
    "issue-creator",
    "issue-resolver",
    "auto-pilot"
  ]
}
JSON

# --- Drop Experiment C's prompt file -----------------------------------------
# Lives at dist/test-plugin/skills/auto-pilot/references/c-test.md so a parent
# subagent reading it from that path resolves ../../issue-creator/SKILL.md
# (two up reaches dist/test-plugin/skills/, then into issue-creator/) and
# ../../../docs/...  (three up reaches dist/test-plugin/, then docs/).
mkdir -p "$OUT/skills/auto-pilot/references"
cat > "$OUT/skills/auto-pilot/references/c-test.md" <<'EOF'
Read these files and report the first heading from each:
1. ../../issue-creator/SKILL.md
2. ../../../docs/naming-conventions.md
3. ../../../shared/agents/codebase-researcher.md
EOF

# --- Print install instructions -----------------------------------------------
plugin_dir="${CLAUDE_PLUGIN_DIR:-$HOME/.claude/plugins}"
cat <<EOF

✓ Test plugin scaffold built at: $OUT
  Skills:  3 ($SKILLS_TO_INCLUDE)
  Agents:  $agent_count
  Docs:    $doc_count

Install (one of):

  # symlink (preferred — survives rebuilds)
  ln -sfn "$OUT" "$plugin_dir/idd-test"

  # or copy
  cp -R "$OUT" "$plugin_dir/idd-test"

Restart Claude Code. Then follow docs/experiments/cross-skill-invocation.md to
run Experiments B and C (3× each per the flake protocol). Experiment A does
not need the plugin installed.
EOF
