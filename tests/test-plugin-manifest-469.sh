#!/usr/bin/env bash
# test-plugin-manifest-469.sh — the repo root as a Claude Code plugin and its
# own marketplace (issue #469).
#
# The plugin ships the committed skills/ tree at the tagged release, so what
# can drift is the manifests, not the skills. These checks guard that drift.
#
# Structural checks (always run — python3 stdlib only, no network, no git):
#   S1  .claude-plugin/plugin.json and marketplace.json parse as JSON objects
#   S2  plugin name == marketplace name == the single entry's name == `idd`
#   S3  the entry's source is `github` + repo `luongnv89/idd`
#   S4  entry ref == "v" + entry version, and entry version == plugin version
#   S5  plugin version == the first `## vX.Y.Z` heading in CHANGELOG.md
#   S6  plugin version == the README version badge
#   S7  no root plugin component (agents/, commands/, hooks/, .mcp.json,
#       .lsp.json, settings.json) and no component-path key in plugin.json,
#       so the plugin ships skills and nothing else
#   S8  skills/ holds exactly the skill directories under src/skills/ (so the
#       internal idd-doctor never ships)
#
# Host checks (need the `claude` CLI; each call runs with a throwaway HOME):
#   C1  `claude plugin validate --json` on plugin.json: success, no errors;
#       the only warning allowed is the root-CLAUDE.md one
#   C2  `claude plugin validate --strict` on marketplace.json exits 0
#   C3  `claude --plugin-dir <root> plugin details idd` reports the plugin
#       version and exactly the src/skills/ names as skills, and zero agents,
#       hooks, MCP servers and LSP servers
#
# Usage: bash tests/test-plugin-manifest-469.sh
# Without `claude` on PATH the host checks are skipped with a ○ line. Set
# IDD_PLUGIN_REQUIRE_CLI=1 (CI does) to turn that skip into a failure.
# Returns: exit 0 if all tests pass, exit 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_JSON="$REPO_ROOT/.claude-plugin/plugin.json"
MARKET_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  ○ skipped — $1"; SKIP=$((SKIP + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/plugin-469.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"

# Expected skill names, one per line, sorted: the public skill sources.
EXPECTED_SKILLS="$(cd "$REPO_ROOT/src/skills" && for d in */; do printf '%s\n' "${d%/}"; done | LC_ALL=C sort)"

echo "◆ Claude Code Plugin Manifest Tests (issue #469)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── S1–S7: one python3 pass prints `PASS|<msg>` / `FAIL|<msg>` lines ─────────
structural="$(python3 - "$REPO_ROOT" <<'PY'
import json, os, re, sys

root = sys.argv[1]
out = []
def check(ok, msg):
    out.append(("PASS|" if ok else "FAIL|") + msg)

def load(rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as exc:
        check(False, f"S1: {rel} does not parse ({exc.__class__.__name__})")
        return None
    ok = isinstance(data, dict)
    check(ok, f"S1: {rel} parses as a JSON object")
    return data if ok else None

plugin = load(".claude-plugin/plugin.json")
market = load(".claude-plugin/marketplace.json")
if plugin is None or market is None:
    print("\n".join(out)); sys.exit(0)

entries = market.get("plugins")
entry = entries[0] if isinstance(entries, list) and len(entries) == 1 and isinstance(entries[0], dict) else {}
check(bool(entry), "S2: marketplace lists exactly one plugin entry")

names = (plugin.get("name"), market.get("name"), entry.get("name"))
check(names == ("idd", "idd", "idd"),
      f"S2: plugin, marketplace and entry are all named idd (got {names})")

src = entry.get("source")
src = src if isinstance(src, dict) else {}
check(src.get("source") == "github" and src.get("repo") == "luongnv89/idd",
      f"S3: entry source is github luongnv89/idd (got {src.get('source')!r} {src.get('repo')!r})")

pv, ev, ref = plugin.get("version"), entry.get("version"), src.get("ref")
semver = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
check(isinstance(pv, str) and bool(semver.match(pv)), f"S4: plugin.json version is X.Y.Z (got {pv!r})")
check(ev == pv, f"S4: entry version matches plugin.json (entry {ev!r}, plugin {pv!r})")
check(isinstance(ev, str) and ref == "v" + ev, f"S4: entry ref is v+version (ref {ref!r}, version {ev!r})")

changelog = None
with open(os.path.join(root, "CHANGELOG.md"), encoding="utf-8") as f:
    for line in f:
        m = re.match(r"^## v([0-9]+\.[0-9]+\.[0-9]+)\b", line)
        if m:
            changelog = m.group(1)
            break
check(changelog == pv, f"S5: plugin version matches first CHANGELOG release heading (CHANGELOG {changelog!r}, plugin {pv!r})")

with open(os.path.join(root, "README.md"), encoding="utf-8") as f:
    badge = re.search(r"img\.shields\.io/badge/version-([0-9]+\.[0-9]+\.[0-9]+)-", f.read())
badge = badge.group(1) if badge else None
check(badge == pv, f"S6: plugin version matches README version badge (badge {badge!r}, plugin {pv!r})")

components = ["agents", "commands", "hooks", ".mcp.json", ".lsp.json", "settings.json"]
present = [c for c in components if os.path.lexists(os.path.join(root, c))]
check(not present, f"S7: no plugin component at repo root (found {present})")
keys = ["skills", "agents", "commands", "hooks", "mcpServers", "lspServers", "outputStyles"]
bad = [k for k in keys if k in plugin]
check(not bad, f"S7: plugin.json declares no component paths (found {bad})")

print("\n".join(out))
PY
)"
if [ -z "$structural" ]; then
  fail "S1–S7: structural checker produced no output"
fi
while IFS='|' read -r verdict msg; do
  [ -n "$verdict" ] || continue
  if [ "$verdict" = "PASS" ]; then pass "$msg"; else fail "$msg"; fi
done <<< "$structural"

# ── S8: skills/ == src/skills/ ───────────────────────────────────────────────
actual_skills="$(cd "$REPO_ROOT/skills" 2>/dev/null && for d in */; do printf '%s\n' "${d%/}"; done | LC_ALL=C sort)"
if [ -n "$EXPECTED_SKILLS" ] && [ "$actual_skills" = "$EXPECTED_SKILLS" ]; then
  pass "S8: skills/ ships exactly the src/skills/ set ($(printf '%s\n' "$EXPECTED_SKILLS" | wc -l | tr -d ' ') skills)"
else
  fail "S8: skills/ ($(echo $actual_skills)) differs from src/skills/ ($(echo $EXPECTED_SKILLS))"
fi

# ── C1–C3: host validation through the claude CLI ────────────────────────────
run_claude() {
  HOME="$TMP/home" DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude "$@"
}

if ! command -v claude >/dev/null 2>&1; then
  if [ "${IDD_PLUGIN_REQUIRE_CLI:-}" = "1" ]; then
    fail "C1–C3: claude CLI not on PATH and IDD_PLUGIN_REQUIRE_CLI=1"
  else
    skip "C1–C3: claude CLI not on PATH (set IDD_PLUGIN_REQUIRE_CLI=1 to require it)"
  fi
else
  # C1 — plugin manifest plus the skills it discovers.
  if run_claude plugin validate --json "$PLUGIN_JSON" >"$TMP/c1.json" 2>"$TMP/c1.err"; then c1_rc=0; else c1_rc=$?; fi
  c1="$(python3 - "$TMP/c1.json" "$c1_rc" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
except (OSError, ValueError):
    print("FAIL|C1: validate --json output is not JSON (exit %s)" % sys.argv[2]); sys.exit(0)
problems = []
if sys.argv[2] != "0":
    problems.append("exit " + sys.argv[2])
if d.get("success") is not True:
    problems.append("success is not true")
m = d.get("manifest") or {}
if m.get("type") != "plugin":
    problems.append("manifest type %r" % m.get("type"))
problems += ["manifest error: " + e.get("message", "?") for e in m.get("errors") or []]
problems += ["manifest warning: " + w.get("message", "?") for w in m.get("warnings") or []]
for c in d.get("contents") or []:
    name = c.get("file", "?")
    problems += ["%s error: %s" % (name, e.get("message", "?")) for e in c.get("errors") or []]
    problems += ["%s warning: %s" % (name, w.get("message", "?")) for w in c.get("warnings") or []
                 if "CLAUDE.md at the plugin root" not in w.get("message", "")]
if problems:
    print("FAIL|C1: plugin validate reported: " + "; ".join(problems))
else:
    print("PASS|C1: claude plugin validate passes plugin.json and its skills")
PY
)"
  while IFS='|' read -r verdict msg; do
    [ -n "$verdict" ] || continue
    if [ "$verdict" = "PASS" ]; then pass "$msg"; else fail "$msg"; fi
  done <<< "$c1"
  [ "$c1_rc" -eq 0 ] || sed -n '1,10p' "$TMP/c1.err" | sed 's/^/      /'

  # C2 — marketplace manifest, warnings treated as errors.
  if run_claude plugin validate --strict "$MARKET_JSON" >"$TMP/c2.log" 2>&1; then
    pass "C2: claude plugin validate --strict passes marketplace.json"
  else
    fail "C2: claude plugin validate --strict rejects marketplace.json"
    sed -n '1,20p' "$TMP/c2.log" | sed 's/^/      /'
  fi

  # C3 — the component inventory the plugin actually ships.
  if run_claude --plugin-dir "$REPO_ROOT" plugin details idd >"$TMP/c3.log" 2>&1; then
    c3="$(python3 - "$TMP/c3.log" "$PLUGIN_JSON" "$EXPECTED_SKILLS" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
version = json.load(open(sys.argv[2], encoding="utf-8")).get("version")
expected = sorted(s for s in sys.argv[3].split("\n") if s)
out = []
first = text.strip().splitlines()[0] if text.strip() else ""
out.append(("PASS|" if first == "idd %s" % version else "FAIL|")
           + "C3: plugin details names idd %s (got %r)" % (version, first))
m = re.search(r"^\s*Skills \((\d+)\)\s+(.*)$", text, re.M)
got = sorted(s.strip() for s in m.group(2).split(",")) if m else None
ok = m is not None and got == expected and int(m.group(1)) == len(expected)
out.append(("PASS|" if ok else "FAIL|")
           + "C3: plugin ships exactly the %d src/skills/ skills (got %s)" % (len(expected), got))
for label in ("Agents", "Hooks", "MCP servers", "LSP servers"):
    c = re.search(r"^\s*%s \((\d+)\)" % re.escape(label), text, re.M)
    n = c.group(1) if c else None
    out.append(("PASS|" if n == "0" else "FAIL|")
               + "C3: plugin ships %s (0) (got %s)" % (label, n))
print("\n".join(out))
PY
)"
    while IFS='|' read -r verdict msg; do
      [ -n "$verdict" ] || continue
      if [ "$verdict" = "PASS" ]; then pass "$msg"; else fail "$msg"; fi
    done <<< "$c3"
  else
    fail "C3: claude --plugin-dir plugin details idd failed"
    sed -n '1,20p' "$TMP/c3.log" | sed 's/^/      /'
  fi
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Claude Code plugin package is out of sync or invalid"
  exit 1
fi
if [ "$SKIP" -gt 0 ]; then
  echo "  ⚠ host checks skipped — structural coverage only"
fi
echo "  ✓ Claude Code plugin package is valid and matches the release (#469)"
exit 0
