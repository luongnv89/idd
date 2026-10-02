#!/usr/bin/env bash
# test-plugin-manifest-469.sh — the Claude Code plugin and its self-hosted
# marketplace (issues #469, #492).
#
# Layout (issue #492): the repo root is the marketplace only
# (.claude-plugin/marketplace.json). The plugin root is the committed skills/
# tree: its manifest is authored once at src/plugin/plugin.json and the build
# emits it byte-identical to skills/.claude-plugin/plugin.json. The marketplace
# entry installs skills/ through a `git-subdir` source pinned to the release
# tag, so a plugin install copies the built skills and never the rest of the
# repo (src/, tests/, docs/, the website, the root CLAUDE.md).
#
# Structural checks (always run — python3 stdlib only, no network):
#   S1  src/plugin/plugin.json, skills/.claude-plugin/plugin.json and
#       .claude-plugin/marketplace.json parse as JSON objects
#   S2  plugin name == marketplace name == the single entry's name == `idd`
#   S3  the entry's source is `git-subdir`, url `luongnv89/idd`, path `skills`,
#       and the entry declares `"skills": "./"` (so a tag whose skills/ has no
#       manifest still loads every skill)
#   S4  entry ref == "v" + entry version, and entry version == plugin version
#   S5  plugin version == the first `## vX.Y.Z` heading in CHANGELOG.md
#   S6  plugin version == the README version badge
#   S7  the manifest's only component key is `"skills": "./"`, the entry
#       description matches the manifest's, no plugin component (agents/,
#       commands/, hooks/, .mcp.json, .lsp.json, settings.json) sits in the
#       plugin root, and the repo root carries no plugin.json — the root is
#       not a plugin, so its CLAUDE.md never reaches `plugin validate`
#   S8  skills/ holds exactly the skill directories under src/skills/ (so the
#       internal idd-doctor never ships)
#   S9  skills/ holds nothing else: the skill directories, .claude-plugin/
#       with plugin.json and icon.png only, and README.md — the whole install payload
#   S10 the emitted manifest is byte-identical to src/plugin/plugin.json and
#       committed (one hand-kept copy, never a second)
#   S12 skills/.claude-plugin/icon.png (the directory listing icon) is a
#       square PNG, 512-2048 px per side, under 2 MB
#   S11 skills/README.md is byte-identical to src/plugin/README.md and has the
#       40 words outside code blocks the Claude plugin directory requires
#
# Host checks (need the `claude` CLI; each call runs with a throwaway HOME
# and CLAUDE_CONFIG_DIR, so the user's real plugin config is never touched):
#   C1  `claude plugin validate --json` on skills/.claude-plugin/plugin.json:
#       success, no errors and no warnings
#   C2  `claude plugin validate --strict` on marketplace.json exits 0
#   C3  `claude --plugin-dir skills plugin details idd` reports the plugin
#       version and exactly the src/skills/ names as skills, and zero agents,
#       hooks, MCP servers and LSP servers
#   C4  end-to-end install: a throwaway git repo holding this skills/ tree
#       plus decoy root files is tagged and installed through the real
#       marketplace entry (only its url swapped to file://); the plugin cache
#       holds the skills, the manifest and the plugin README, none of the
#       decoys, and the
#       installed plugin lists every skill
#
# Usage: bash tests/test-plugin-manifest-469.sh
# Without `claude` on PATH the host checks are skipped with a ○ line. Set
# IDD_PLUGIN_REQUIRE_CLI=1 (CI does) to turn that skip into a failure.
# Returns: exit 0 if all tests pass, exit 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_ROOT="$REPO_ROOT/skills"
SOURCE_JSON="$REPO_ROOT/src/plugin/plugin.json"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKET_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  ○ skipped — $1"; SKIP=$((SKIP + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/plugin-469.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.claude"

# Expected skill names, one per line, sorted: the public skill sources.
EXPECTED_SKILLS="$(cd "$REPO_ROOT/src/skills" && for d in */; do printf '%s\n' "${d%/}"; done | LC_ALL=C sort)"

echo "◆ Claude Code Plugin Manifest Tests (issues #469, #492)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── S1–S7, S9: one python3 pass prints `PASS|<msg>` / `FAIL|<msg>` lines ─────
structural="$(python3 - "$REPO_ROOT" "$EXPECTED_SKILLS" <<'PY'
import json, os, re, sys

root = sys.argv[1]
expected = sorted(s for s in sys.argv[2].split("\n") if s)
plugin_root = os.path.join(root, "skills")
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

source = load("src/plugin/plugin.json")
plugin = load("skills/.claude-plugin/plugin.json")
market = load(".claude-plugin/marketplace.json")
if source is None or plugin is None or market is None:
    print("\n".join(out)); sys.exit(0)

entries = market.get("plugins")
entry = entries[0] if isinstance(entries, list) and len(entries) == 1 and isinstance(entries[0], dict) else {}
check(bool(entry), "S2: marketplace lists exactly one plugin entry")

names = (plugin.get("name"), market.get("name"), entry.get("name"))
check(names == ("idd", "idd", "idd"),
      f"S2: plugin, marketplace and entry are all named idd (got {names})")

src = entry.get("source")
src = src if isinstance(src, dict) else {}
got_src = (src.get("source"), src.get("url"), src.get("path"))
check(got_src == ("git-subdir", "luongnv89/idd", "skills"),
      f"S3: entry source is git-subdir luongnv89/idd path skills (got {got_src})")
check(entry.get("skills") == "./",
      f"S3: entry declares skills \"./\" (got {entry.get('skills')!r})")

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

keys = ["skills", "agents", "commands", "hooks", "mcpServers", "lspServers", "outputStyles"]
declared = {k: plugin[k] for k in keys if k in plugin}
check(declared == {"skills": "./"},
      f"S7: plugin.json declares only skills \"./\" as a component path (got {declared})")
check(entry.get("description") == plugin.get("description"),
      "S7: marketplace entry description matches plugin.json")
components = ["agents", "commands", "hooks", ".mcp.json", ".lsp.json", "settings.json"]
present = [c for c in components if os.path.lexists(os.path.join(plugin_root, c))]
check(not present, f"S7: no plugin component in the plugin root skills/ (found {present})")
check(not os.path.lexists(os.path.join(root, ".claude-plugin", "plugin.json")),
      "S7: the repo root carries no .claude-plugin/plugin.json (the root is a marketplace, not a plugin)")

top = sorted(os.listdir(plugin_root)) if os.path.isdir(plugin_root) else []
want = sorted(expected + [".claude-plugin", "README.md"])
check(top == want, f"S9: skills/ holds only the skills, .claude-plugin/ and README.md (extra {sorted(set(top) - set(want))}, missing {sorted(set(want) - set(top))})")
manifest_dir = os.path.join(plugin_root, ".claude-plugin")
inside = sorted(os.listdir(manifest_dir)) if os.path.isdir(manifest_dir) else []
check(inside == ["icon.png", "plugin.json"], f"S9: skills/.claude-plugin/ holds plugin.json and icon.png only (got {inside})")
# The Claude plugin directory takes the listing icon from .claude-plugin/icon.png:
# a square PNG, 512-2048 px per side, under 2 MB.
icon = os.path.join(manifest_dir, "icon.png")
dims = None
if os.path.isfile(icon):
    with open(icon, "rb") as f:
        head = f.read(24)
    if head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
        dims = (int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"))
ok_icon = bool(dims) and dims[0] == dims[1] and 512 <= dims[0] <= 2048 and os.path.getsize(icon) < 2 * 1024 * 1024
check(ok_icon, f"S12: skills/.claude-plugin/icon.png is a square 512-2048 px PNG under 2 MB (got {dims})")

print("\n".join(out))
PY
)"
if [ -z "$structural" ]; then
  fail "S1–S9: structural checker produced no output"
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

# ── S10: one hand-kept manifest — the emitted copy matches it and is committed ─
if [ -f "$SOURCE_JSON" ] && [ -f "$PLUGIN_JSON" ] && cmp -s "$SOURCE_JSON" "$PLUGIN_JSON"; then
  pass "S10: skills/.claude-plugin/plugin.json is byte-identical to src/plugin/plugin.json"
else
  fail "S10: skills/.claude-plugin/plugin.json differs from src/plugin/plugin.json — run ./scripts/build.sh"
fi
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$REPO_ROOT" ls-files --error-unmatch skills/.claude-plugin/plugin.json >/dev/null 2>&1; then
    pass "S10: skills/.claude-plugin/plugin.json is committed with the skills/ tree"
  else
    fail "S10: skills/.claude-plugin/plugin.json is not tracked — commit the rebuilt skills/"
  fi
else
  skip "S10: not a git work tree — tracked-manifest check needs git"
fi

# ── S11: the plugin README (directory listing) is emitted from its source ────
SOURCE_README="$REPO_ROOT/src/plugin/README.md"
PLUGIN_README="$REPO_ROOT/skills/README.md"
if [ -f "$SOURCE_README" ] && [ -f "$PLUGIN_README" ] && cmp -s "$SOURCE_README" "$PLUGIN_README"; then
  pass "S11: skills/README.md is byte-identical to src/plugin/README.md"
else
  fail "S11: skills/README.md differs from src/plugin/README.md — run ./scripts/build.sh"
fi
# The Claude plugin directory blocks a README under 40 words outside code blocks.
readme_words="$(awk '/^```/{f=!f; next} !f' "$SOURCE_README" 2>/dev/null | wc -w | tr -d ' ')"
if [ "${readme_words:-0}" -ge 40 ]; then
  pass "S11: the plugin README has $readme_words words outside code blocks (directory minimum 40)"
else
  fail "S11: the plugin README has ${readme_words:-0} words outside code blocks; the plugin directory requires 40"
fi

# ── C1–C4: host validation through the claude CLI ────────────────────────────
run_claude() {
  HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/home/.claude" DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude "$@"
}

if ! command -v claude >/dev/null 2>&1; then
  if [ "${IDD_PLUGIN_REQUIRE_CLI:-}" = "1" ]; then
    fail "C1–C4: claude CLI not on PATH and IDD_PLUGIN_REQUIRE_CLI=1"
  else
    skip "C1–C4: claude CLI not on PATH (set IDD_PLUGIN_REQUIRE_CLI=1 to require it)"
  fi
else
  # C1 — plugin manifest plus the skills it discovers.
  if run_claude plugin validate --json "$PLUGIN_JSON" >"$TMP/c1.json" 2>"$TMP/c1.err"; then c1_rc=0; else c1_rc=$?; fi
  c1="$(python3 - "$TMP/c1.json" "$c1_rc" <<'PY'
import json, sys
# Type-safe on purpose: a changed validate --json shape must print a FAIL line,
# never raise and leave stdout empty.
def items(v):
    return v if isinstance(v, list) else []
def text(x):
    return str(x.get("message", "?")) if isinstance(x, dict) else str(x)
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
except (OSError, ValueError):
    print("FAIL|C1: validate --json output is not JSON (exit %s)" % sys.argv[2]); sys.exit(0)
if not isinstance(d, dict):
    print("FAIL|C1: validate --json output is a %s, not an object (exit %s)" % (type(d).__name__, sys.argv[2])); sys.exit(0)
problems = []
if sys.argv[2] != "0":
    problems.append("exit " + sys.argv[2])
if d.get("success") is not True:
    problems.append("success is not true")
m = d.get("manifest")
m = m if isinstance(m, dict) else {}
if m.get("type") != "plugin":
    problems.append("manifest type %r" % m.get("type"))
problems += ["manifest error: " + text(e) for e in items(m.get("errors"))]
problems += ["manifest warning: " + text(w) for w in items(m.get("warnings"))]
for c in items(d.get("contents")):
    if not isinstance(c, dict):
        problems.append("contents item is a %s, not an object" % type(c).__name__)
        continue
    name = str(c.get("file", "?"))
    problems += ["%s error: %s" % (name, text(e)) for e in items(c.get("errors"))]
    problems += ["%s warning: %s" % (name, text(w)) for w in items(c.get("warnings"))]
if problems:
    print("FAIL|C1: plugin validate reported: " + "; ".join(problems))
else:
    print("PASS|C1: claude plugin validate passes plugin.json and its skills with no warnings")
PY
)"
  [ -n "$c1" ] || fail "C1: validate output could not be parsed (exit $c1_rc)"
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
  if run_claude --plugin-dir "$PLUGIN_ROOT" plugin details idd >"$TMP/c3.log" 2>&1; then
    c3="$(python3 - "$TMP/c3.log" "$PLUGIN_JSON" "$EXPECTED_SKILLS" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
try:
    plugin = json.load(open(sys.argv[2], encoding="utf-8"))
except (OSError, ValueError):
    plugin = None
version = plugin.get("version") if isinstance(plugin, dict) else None
expected = sorted(s for s in sys.argv[3].split("\n") if s)
out = []
first = text.strip().splitlines()[0] if text.strip() else ""
# With a displayName the CLI prints "<displayName> (idd) <version>".
display = plugin.get("displayName") if isinstance(plugin, dict) else None
want_first = ("%s (idd) %s" % (display, version)) if display else ("idd %s" % version)
out.append(("PASS|" if first == want_first else "FAIL|")
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
    [ -n "$c3" ] || fail "C3: plugin details output could not be parsed"
    while IFS='|' read -r verdict msg; do
      [ -n "$verdict" ] || continue
      if [ "$verdict" = "PASS" ]; then pass "$msg"; else fail "$msg"; fi
    done <<< "$c3"
  else
    fail "C3: claude --plugin-dir skills plugin details idd failed"
    sed -n '1,20p' "$TMP/c3.log" | sed 's/^/      /'
  fi

  # C4 — end-to-end install through the real marketplace entry (issue #492).
  # A throwaway repo stands in for the tagged release: this skills/ tree plus
  # decoy root files a whole-repo install would carry. Only the entry's url is
  # swapped (to file://); its source type, path, ref and skills key are real.
  C4="$TMP/c4"
  mkdir -p "$C4/repo" "$C4/market/.claude-plugin" "$C4/home/.claude"
  c4_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PLUGIN_JSON" 2>/dev/null || true)"
  if [ -z "$c4_version" ]; then
    fail "C4: no plugin version to tag (skills/.claude-plugin/plugin.json unreadable)"
  elif ! (
      cp -R "$PLUGIN_ROOT" "$C4/repo/skills" &&
      cd "$C4/repo" &&
      mkdir -p src tests docs &&
      printf 'decoy\n' > CLAUDE.md && printf 'decoy\n' > README.md &&
      printf 'decoy\n' > landing.html && printf 'decoy\n' > src/decoy.md &&
      printf 'decoy\n' > tests/decoy.sh && printf 'decoy\n' > docs/decoy.md &&
      git init -q &&
      git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c maintenance.auto=false \
        add -A &&
      git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c maintenance.auto=false \
        commit -qm "release fixture" &&
      git -c tag.gpgsign=false tag "v$c4_version"
    ) >"$TMP/c4-git.log" 2>&1; then
    fail "C4: could not build the throwaway release repo"
    sed -n '1,10p' "$TMP/c4-git.log" | sed 's/^/      /'
  elif ! python3 - "$MARKET_JSON" "$C4/market/.claude-plugin/marketplace.json" "file://$C4/repo" <<'PY'
import json, sys
market = json.load(open(sys.argv[1], encoding="utf-8"))
market["plugins"][0]["source"]["url"] = sys.argv[3]
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump(market, f, indent=2)
PY
  then
    fail "C4: could not write the throwaway marketplace"
  else
    run_c4() {
      HOME="$C4/home" CLAUDE_CONFIG_DIR="$C4/home/.claude" DISABLE_AUTOUPDATER=1 \
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 claude "$@"
    }
    if run_c4 plugin marketplace add "$C4/market" >"$TMP/c4.log" 2>&1 &&
       run_c4 plugin install idd@idd >>"$TMP/c4.log" 2>&1; then
      run_c4 plugin details idd@idd >"$TMP/c4-details.log" 2>&1 || true
      c4="$(python3 - "$C4/home/.claude/plugins/cache/idd/idd/$c4_version" "$PLUGIN_JSON" "$EXPECTED_SKILLS" "$TMP/c4-details.log" <<'PY'
import filecmp, os, re, sys
cache, manifest, expected, details = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
expected = sorted(s for s in expected.split("\n") if s)
out = []
if not os.path.isdir(cache):
    print("FAIL|C4: no plugin cache at %s" % cache); sys.exit(0)
# The CLI adds its own bookkeeping dot-entries (e.g. .in_use); the payload is
# every other entry, plus the shipped .claude-plugin/.
names = sorted(os.listdir(cache))
payload = sorted(n for n in names if not n.startswith(".") or n == ".claude-plugin")
want = sorted(expected + [".claude-plugin", "README.md"])
out.append(("PASS|" if payload == want else "FAIL|")
           + "C4: the plugin cache holds only the skills, .claude-plugin/ and README.md (got %s)" % payload)
leaked = [n for n in ("CLAUDE.md", "landing.html", "src", "tests", "docs") if n in names]
out.append(("PASS|" if not leaked else "FAIL|")
           + "C4: no repo-root file reaches the plugin cache (leaked %s)" % leaked)
plugin_readme = os.path.join(os.path.dirname(os.path.dirname(manifest)), "README.md")
cached_readme = os.path.join(cache, "README.md")
same_readme = os.path.isfile(cached_readme) and filecmp.cmp(cached_readme, plugin_readme, shallow=False)
out.append(("PASS|" if same_readme else "FAIL|")
           + "C4: the cached README.md is the plugin README, not the repo-root README")
shipped = os.path.join(cache, ".claude-plugin", "plugin.json")
same = os.path.isfile(shipped) and filecmp.cmp(shipped, manifest, shallow=False)
out.append(("PASS|" if same else "FAIL|")
           + "C4: the cached manifest is the emitted skills/.claude-plugin/plugin.json")
text = open(details, encoding="utf-8").read()
m = re.search(r"^\s*Skills \((\d+)\)\s+(.*)$", text, re.M)
got = sorted(s.strip() for s in m.group(2).split(",")) if m else None
out.append(("PASS|" if got == expected else "FAIL|")
           + "C4: the installed plugin loads exactly the %d src/skills/ skills (got %s)" % (len(expected), got))
print("\n".join(out))
PY
)"
      [ -n "$c4" ] || fail "C4: install result could not be parsed"
      while IFS='|' read -r verdict msg; do
        [ -n "$verdict" ] || continue
        if [ "$verdict" = "PASS" ]; then pass "$msg"; else fail "$msg"; fi
      done <<< "$c4"
    else
      fail "C4: claude plugin marketplace add / install from the throwaway release failed"
      sed -n '1,20p' "$TMP/c4.log" | sed 's/^/      /'
    fi
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
echo "  ✓ Claude Code plugin package is valid and matches the release (#469, #492)"
exit 0
