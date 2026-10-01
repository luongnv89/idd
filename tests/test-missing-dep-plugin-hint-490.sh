#!/usr/bin/env bash
# test-missing-dep-plugin-hint-490.sh — every "Missing bundled dependency" fix
# block names the Claude Code plugin path next to the asm path (issue #490).
#
#  AC1. Every public skill's `✗ Missing bundled dependency: {missing_file}`
#       block gives the plugin reinstall and update commands.
#  AC2. The standalone `asm install … --skill <skill>` line is unchanged.
#  AC3. This test fails when a block omits the plugin path.
#
# The plugin id (`<plugin>@<marketplace>`) and the `marketplace add` target are
# derived from .claude-plugin/marketplace.json, so a rename there fails this
# test until every block follows. Each assertion is scoped to the fenced block
# that opens on the error line — never the whole file, because auto-pilot's
# missing-skill block (#488) already carries a Plugin: line of its own.
# idd-doctor (src/internal-skills/) is repo-internal, not shipped in the
# plugin, and is out of scope.
#
# Usage: bash tests/test-missing-dep-plugin-hint-490.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "◆ Plugin path in missing-dependency fix hints (issue #490)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
passed = failed = 0


def check(ok, label):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ✓ {label}")
    else:
        failed += 1
        print(f"  ✗ {label}")


# ── Plugin identity, from the marketplace manifest ─────────────────────────
market = json.loads((root / ".claude-plugin/marketplace.json").read_text())
plugin = market["plugins"][0]
plugin_id = f'{plugin["name"]}@{market["name"]}'
# The `marketplace add` target is this repo in owner/repo form: a `github`
# source names it as `repo`, a `git-subdir` source (issue #492) as `url`.
repo = plugin["source"].get("repo") or plugin["source"]["url"]
want_add = f"Plugin:  claude plugin marketplace add {repo}"
want_install = f"claude plugin install {plugin_id}"
want_update = f"claude plugin update {plugin_id}"

ANCHOR = "✗ Missing bundled dependency: {missing_file}"


def blocks(tree):
    """Yield (skill, path, lines) for each fenced block opening on ANCHOR."""
    for path in sorted(tree.rglob("*.md")):
        skill = path.relative_to(tree).parts[0]
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if line.strip() != ANCHOR:
                continue
            span = []
            for nxt in lines[i:]:
                if nxt.startswith("```"):
                    break
                span.append(nxt)
            yield skill, path, span


def check_tree(tree, label):
    found = list(blocks(tree))
    by_skill = {}
    for skill, path, span in found:
        by_skill.setdefault(skill, []).append((path, span))
        rel = path.relative_to(root)
        text = "\n".join(span)
        want_asm = (
            f"  To fix:  asm install https://github.com/luongnv89/idd --skill {skill}"
        )
        check(want_asm in span, f"{rel}: asm line unchanged (--skill {skill})")
        check(f"  {want_add}" in span, f"{rel}: names `marketplace add {repo}`")
        check(want_install in text, f"{rel}: names `{want_install}`")
        check(want_update in text, f"{rel}: names `{want_update}`")
        long = [ln for ln in span if len(ln) > 80]
        check(not long, f"{rel}: block lines stay within 80 columns")
    skills = sorted(
        p.parent.name for p in tree.glob("*/SKILL*.md") if p.parent.parent == tree
    )
    for skill in skills:
        check(skill in by_skill, f"{label}: {skill} has a missing-dependency block")
    return found


src = check_tree(root / "src/skills", "src")
check(len(src) == 7, f"src: exactly 7 missing-dependency blocks (found {len(src)})")

built = root / "skills"
if built.is_dir():
    out = check_tree(built, "skills")
    check(len(out) == 7, f"skills: exactly 7 built blocks (found {len(out)})")

print()
if failed:
    print(f"  ✗ Missing-dependency plugin hint tests failed ({passed} passed, {failed} failed)")
    sys.exit(1)
print(f"  ✓ All missing-dependency plugin hint checks passed ({passed})")
PY
