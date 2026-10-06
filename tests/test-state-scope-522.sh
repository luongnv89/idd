#!/usr/bin/env bash
# test-state-scope-522.sh — validated run-state transitions and a pre-pass
# scoped to approved paths (#522).
#
# AC1: Illegal/evidence-free transitions fail atomically.
#   S1  every checkpoint sequence /auto-pilot documents still writes (exit 0):
#       sequential review/fix/merge/cleanup/triage, the parallel lane
#       lifecycle through log_pending/logged/completed, failed and
#       blocked_dirty lanes, resume back-edges, the resume copy of a draining
#       lane into `current`, and phase-less borrowed_skills patches.
#   S2  illegal edges, unknown phases and new records that start past their
#       start phase exit 3 with the state file byte-identical, the lock
#       heartbeat untouched, and the same refusal under --dry-run.
#   S3  evidence-free phases (no pr, no branch, no telemetry.run_log) exit 3,
#       byte-identical.
#   S4  the prose names the rule beside the checkpoint procedure.
#
# AC2: Formatting/staging touches only approved paths, preserving unrelated
#      dirty files.
#   P1  the pre-pass blocks from prepass-tests-ci-mechanics.md, executed in a
#       scratch repo with a fake `gh`: only approved paths are formatted,
#       staged and committed; already-dirty PR files, unrelated dirty,
#       untracked and pre-staged files survive untouched; spill-over is
#       reported and left unstaged; a `-x.js` path is never an option.
#   P2  the prose: no tree-wide formatter, no `git add -A`, a --staged scan.
#
# Usage: bash tests/test-state-scope-522.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

# No `set -e`: assertions report and continue.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "0" ]; then pass "$1"; else fail "$1"; fi; }

STATE="$REPO_ROOT/src/shared/scripts/gi-state.py"
PREPASS="$REPO_ROOT/src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"
PR_SKILL="$REPO_ROOT/src/skills/issue-pr-review/SKILL.source.md"
PHASE0="$REPO_ROOT/src/skills/auto-pilot/references/phases/phase-0-lock-resume.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "◆ Validated state and scoped pre-pass (issue #522)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── S1–S3: transitions, driven through the real CLI ─────────
python3 - "$STATE" "$TMP" <<'PY'
import hashlib, json, os, socket, subprocess, sys

STATE, ROOT = sys.argv[1], sys.argv[2]
results = []
counter = [0]

def new_dir():
    counter[0] += 1
    d = os.path.join(ROOT, f"s{counter[0]}")
    os.makedirs(d)
    run(d, "--init", {"run_id": "r522", "mode": "balanced", "queue": [42, 45]})
    return d

def run(d, mode, payload, *extra):
    proc = subprocess.run(
        [sys.executable, STATE, mode, "--dir", d, *extra],
        input=json.dumps(payload), capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr

def digest(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()

def sequence(name, patches):
    d = new_dir()
    for i, patch in enumerate(patches):
        code, _, err = run(d, "--update", patch)
        if code != 0:
            results.append((False, f"S1: {name} — step {i + 1} refused: {err.strip()}"))
            return d
    results.append((True, f"S1: documented sequence writes: {name}"))
    return d

def refused(name, setup, patch, needle):
    d = new_dir()
    for p in setup:
        code, _, err = run(d, "--update", p)
        if code != 0:
            results.append((False, f"{name} — setup refused: {err.strip()}"))
            return
    state = os.path.join(d, "run-state.json")
    lock = os.path.join(d, "run.lock")
    with open(lock, "w") as fh:
        json.dump({"run_id": "r522", "pid": 4242, "host": socket.gethostname(),
                   "started_at": "2000-01-01T00:00:00Z",
                   "heartbeat": "2000-01-01T00:00:00Z"}, fh)
    before, lock_before = digest(state), digest(lock)
    code, out, err = run(d, "--update", patch, "--pid", "4242")
    dry_code, dry_out, _ = run(d, "--update", patch, "--dry-run")
    ok = (
        code == 3 and dry_code == 3 and out == "" and dry_out == ""
        and digest(state) == before and digest(lock) == lock_before
        and needle in err
        and sorted(os.listdir(d)) == ["run-state.json", "run.lock"]
    )
    detail = "" if ok else f" (exit {code}/{dry_code}, stderr: {err.strip()!r})"
    results.append((ok, f"{name}{detail}"))

PR = {"issue": 42, "title": "t", "branch": "fix/42-a", "pr": 87, "phase": "review"}
REVIEW = {"phase": "review", "current": PR}
LANES = {"phase": "resolve", "lanes": [
    {"issue": 42, "branch": "feat/42-a", "phase": "planned", "lane_id": "r522:42",
     "event_id": "r522:42", "base_sha": "0" * 40},
    {"issue": 45, "branch": "fix/45-b", "phase": "planned", "lane_id": "r522:45",
     "event_id": "r522:45", "base_sha": "0" * 40}]}
RUN_LOG = {"run_log": {"issue": 42, "outcome": "merged"}}
BORROW = {"borrowed_skills": [{"name": "frontend-design", "origin": "borrowed"}]}

# ── S1: every documented sequence remains legal ──
sequence("sequential review → merge → cleanup(merged) → triage", [
    REVIEW,
    {"phase": "merge", "current": {"phase": "merge"}},
    {"phase": "cleanup", "current": {"phase": "cleanup", "outcome": "merged"}},
    {"phase": "triage", "current": None,
     "processed": [{"issue": 42, "outcome": "merged", "pr": 87}]},
    {"phase": "review", "current": dict(PR, issue=45, branch="fix/45-b", pr=88)},
])
sequence("review → fix → review → merge, then fix → cleanup(left_open)", [
    REVIEW,
    {"phase": "fix", "current": {"phase": "fix"}},
    {"phase": "review", "current": {"phase": "review"}},
    {"phase": "fix", "current": {"phase": "fix"}},
    {"phase": "cleanup", "current": {"phase": "cleanup", "outcome": "left_open"}},
    {"phase": "triage", "current": None, "skip_list": [42]},
])
sequence("failed resolve and resume to the top of the loop", [
    {"phase": "triage", "processed": [{"issue": 42, "outcome": "failed", "pr": None}],
     "skip_list": [42]},
    {"phase": "triage"},
])
sequence("parallel lane lifecycle through completed, sibling failed", [
    LANES,
    {"lanes": [{"issue": 42, "phase": "resolve"}, {"issue": 45, "phase": "resolve"}]},
    {"lanes": [{"issue": 42, "branch": "feat/42-a", "pr": 87, "phase": "returned",
                "telemetry": {"status": "success"}},
               {"issue": 45, "phase": "failed", "telemetry": {"status": "failure"}}]},
    {"phase": "review", "current": dict(PR, branch="feat/42-a"),
     "lanes": [{"issue": 42, "phase": "review"}]},
    {"phase": "merge", "current": {"phase": "merge"},
     "lanes": [{"issue": 42, "phase": "merge"}]},
    {"phase": "cleanup", "current": {"phase": "cleanup", "outcome": "merged"},
     "lanes": [{"issue": 42, "phase": "cleanup", "outcome": "merged"}]},
    {"lanes": [{"issue": 42, "phase": "log_pending", "telemetry": RUN_LOG}]},
    {"lanes": [{"issue": 42, "phase": "logged"}]},
    {"phase": "resolve", "current": None,
     "processed": [{"issue": 42, "outcome": "merged", "pr": 87}],
     "lanes": [{"issue": 42, "phase": "completed"}]},
    {"phase": "cleanup", "current": {"issue": 45, "branch": "fix/45-b",
                                     "phase": "cleanup", "outcome": "failed"},
     "lanes": [{"issue": 45, "phase": "cleanup"}]},
    {"lanes": [{"issue": 45, "phase": "log_pending",
                "telemetry": {"run_log": {"issue": 45, "outcome": "failed"}}}]},
    {"lanes": [{"issue": 45, "phase": "logged"}]},
    {"phase": "triage", "current": None, "lanes": [{"issue": 45, "phase": "failed"}]},
    {"lanes": []},
])
sequence("failed lane logs without cleanup; blocked_dirty lane logs too", [
    LANES,
    {"lanes": [{"issue": 42, "phase": "failed"}, {"issue": 45, "phase": "resolve"}]},
    {"lanes": [{"issue": 42, "phase": "log_pending", "telemetry": RUN_LOG}]},
    {"lanes": [{"issue": 42, "phase": "logged"}]},
    {"lanes": [{"issue": 42, "phase": "failed"}, {"issue": 45, "phase": "blocked_dirty"}]},
    {"lanes": [{"issue": 45, "phase": "log_pending",
                "telemetry": {"run_log": {"issue": 45, "outcome": "failed"}}}]},
    {"lanes": [{"issue": 45, "phase": "logged"}]},
    {"lanes": [{"issue": 45, "phase": "blocked_dirty"}]},
])
sequence("resume back-edges toward more verification", [
    LANES,
    {"lanes": [{"issue": 42, "phase": "resolve"}]},
    {"lanes": [{"issue": 42, "pr": 87, "phase": "returned"}]},
    {"lanes": [{"issue": 42, "phase": "resolve"}]},
    {"lanes": [{"issue": 42, "phase": "resolve"}]},
    {"lanes": [{"issue": 42, "pr": 87, "phase": "returned"}]},
    {"phase": "review", "current": dict(PR, branch="feat/42-a"),
     "lanes": [{"issue": 42, "phase": "review"}]},
    {"phase": "merge", "current": {"phase": "merge"},
     "lanes": [{"issue": 42, "phase": "merge"}]},
    {"phase": "review", "current": {"phase": "review"},
     "lanes": [{"issue": 42, "phase": "returned"}]},
])
sequence("planned lane straight to returned when its PR is found", [
    LANES,
    {"lanes": [{"issue": 45, "pr": 88, "phase": "returned"}]},
])
sequence("resume copies a draining lane into a fresh current", [
    LANES,
    {"lanes": [{"issue": 42, "phase": "resolve"}]},
    {"lanes": [{"issue": 42, "pr": 87, "phase": "returned"}]},
    {"phase": "review", "current": dict(PR, branch="feat/42-a"),
     "lanes": [{"issue": 42, "phase": "review"}]},
    {"phase": "merge", "current": {"phase": "merge"},
     "lanes": [{"issue": 42, "phase": "merge"}]},
    {"current": None},
    {"current": dict(PR, branch="feat/42-a", phase="merge")},
])
sequence("phase-less borrowed_skills patches at any phase", [
    BORROW, REVIEW, BORROW, {"borrowed_skills": []},
])

# ── S2: illegal edges, atomically ──
refused("S2: init → merge (no review) exits 3, nothing written",
        [], {"phase": "merge", "current": PR}, "illegal transition init → merge")
refused("S2: triage → fix exits 3, nothing written",
        [{"phase": "triage"}], {"phase": "fix", "current": PR},
        "illegal transition triage → fix")
refused("S2: an unknown phase name exits 3, nothing written",
        [], {"phase": "checkpoint"}, "'checkpoint' is not a known phase")
refused("S2: current.phase resolve → merge exits 3, nothing written",
        [{"phase": "triage", "current": {"issue": 42, "branch": "fix/42-a",
                                         "phase": "resolve"}}],
        {"current": {"pr": 87, "phase": "merge"}},
        "illegal transition resolve → merge")
refused("S2: a fresh current at merge with no lane there exits 3",
        [], {"current": PR | {"phase": "merge"}}, "cannot start at 'merge'")
refused("S2: a new lane cannot start at completed",
        [], {"lanes": [{"issue": 42, "branch": "feat/42-a", "phase": "completed",
                        "telemetry": RUN_LOG}]}, "cannot start at 'completed'")
refused("S2: lane cleanup → completed (skipping logged) exits 3",
        [LANES, {"lanes": [{"issue": 42, "phase": "resolve"}]},
         {"lanes": [{"issue": 42, "pr": 87, "phase": "returned"}]},
         {"lanes": [{"issue": 42, "phase": "review"}]},
         {"lanes": [{"issue": 42, "phase": "merge"}]},
         {"lanes": [{"issue": 42, "phase": "cleanup", "telemetry": RUN_LOG}]}],
        {"lanes": [{"issue": 42, "phase": "completed"}]},
        "illegal transition cleanup → completed")
refused("S2: a completed lane is terminal",
        [LANES, {"lanes": [{"issue": 42, "phase": "failed"}]},
         {"lanes": [{"issue": 42, "phase": "log_pending", "telemetry": RUN_LOG}]},
         {"lanes": [{"issue": 42, "phase": "logged"}]},
         {"lanes": [{"issue": 42, "phase": "completed"}]}],
        {"lanes": [{"issue": 42, "phase": "resolve"}]},
        "illegal transition completed → resolve")
refused("S2: a phase cannot be cleared to null",
        [], {"phase": None}, "cannot be cleared")
refused("S2: one bad lane refuses the whole patch (siblings unwritten)",
        [LANES], {"lanes": [{"issue": 42, "phase": "resolve"},
                            {"issue": 45, "phase": "merge", "pr": 88}]},
        "illegal transition planned → merge")

# A hand-edited state whose phase is outside the vocabulary accepts no edge.
d = new_dir()
path = os.path.join(d, "run-state.json")
with open(path) as fh:
    doc = json.load(fh)
doc["phase"] = "research"
with open(path, "w") as fh:
    json.dump(doc, fh)
before = digest(path)
code, _, err = run(d, "--update", {"phase": "triage"})
results.append((code == 3 and digest(path) == before and "not a known phase" in err,
                "S2: a recorded off-vocabulary phase accepts no transition"))
# A non-string recorded phase is the same refusal, never a traceback.
for where in ("top-level", "current"):
    d = new_dir()
    path = os.path.join(d, "run-state.json")
    with open(path) as fh:
        doc = json.load(fh)
    if where == "top-level":
        doc["phase"] = ["review"]
        patch = {"phase": "triage"}
    else:
        doc["current"] = {"issue": 42, "pr": 87, "phase": ["merge"]}
        patch = {"current": {"phase": "review"}}
    with open(path, "w") as fh:
        json.dump(doc, fh)
    before = digest(path)
    code, _, err = run(d, "--update", patch)
    results.append((code == 3 and digest(path) == before and "Traceback" not in err,
                    f"S2: a non-string recorded {where} phase exits 3, no traceback"))

# ── S3: evidence-free phases ──
refused("S3: top-level review without current.pr exits 3",
        [], {"phase": "review", "current": {"issue": 42, "branch": "fix/42-a",
                                            "phase": "review", "pr": None}},
        "requires an integer pr")
refused("S3: top-level merge with current cleared exits 3",
        [REVIEW], {"phase": "merge", "current": None}, "requires current.pr")
refused("S3: a returned lane without its PR exits 3",
        [LANES, {"lanes": [{"issue": 42, "phase": "resolve"}]}],
        {"lanes": [{"issue": 42, "phase": "returned"}]}, "requires an integer pr")
refused("S3: a planned lane without a branch exits 3",
        [], {"lanes": [{"issue": 42, "phase": "planned"}]}, "requires a branch")
refused("S3: log_pending without telemetry.run_log exits 3",
        [LANES, {"lanes": [{"issue": 42, "phase": "failed",
                            "telemetry": {"status": "failure"}}]}],
        {"lanes": [{"issue": 42, "phase": "log_pending"}]},
        "requires telemetry.run_log")
refused("S3: a merged cleanup without its PR exits 3",
        [{"phase": "triage", "current": {"issue": 42, "branch": "fix/42-a",
                                         "phase": "resolve"}}],
        {"phase": "resolve", "current": {"phase": "cleanup", "outcome": "merged"}},
        "requires an integer pr")
refused("S3: dropping the PR from a reviewing lane exits 3",
        [LANES, {"lanes": [{"issue": 42, "phase": "resolve"}]},
         {"lanes": [{"issue": 42, "pr": 87, "phase": "returned"}]}],
        {"lanes": [{"issue": 42, "pr": None}]}, "requires an integer pr")

for ok, label in results:
    print(("  ✓ " if ok else "  ✗ ") + label)
sys.exit(0 if all(ok for ok, _ in results) else 1)
PY
s_status=$?
if [ "$s_status" = "0" ]; then pass "S1–S3: transition checks all held"; else fail "S1–S3: a transition check failed (see above)"; fi

# ── S4: the prose names the rule ─────────────────────────────
grep -q 'Phases are validated transitions, not free labels' "$PHASE0"
check "S4: phase-0 states that phases are validated transitions" "$?"
grep -q 'A refused patch exits 3 and writes nothing' "$PHASE0"
check "S4: phase-0 states a refused patch writes nothing" "$?"
grep -q 'transition table per record' "$STATE"
check "S4: gi-state.py's docstring documents the transition tables" "$?"

# ── P1: the pre-pass blocks, executed ────────────────────────
BLOCKS="$TMP/blocks"
mkdir -p "$BLOCKS"
python3 - "$PREPASS" "$BLOCKS" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"^```bash\n(.*?)^```", text, flags=re.S | re.M)
want = {
    "baseline": 'scope="$(mktemp -d)"',
    "stage": '"$scope/dirty-after"',
    "commit": "git --literal-pathspecs commit --only",
}
found = {}
for block in blocks:
    for name, marker in want.items():
        if marker in block:
            found[name] = block
missing = sorted(set(want) - set(found))
if missing:
    print("missing blocks: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
for name, block in found.items():
    if name == "baseline":
        block = block.replace("{N}", "7")
    if name == "commit":
        # Push needs a remote; everything else runs as documented.
        block = "\n".join(l for l in block.splitlines() if not l.startswith("git push"))
    open(f"{sys.argv[2]}/{name}.sh", "w", encoding="utf-8").write(block)
PY
check "P1: the baseline, stage and commit blocks were located" "$?"

REPO="$TMP/repo"
OUTSIDE="$TMP/outside.txt"
BIN="$TMP/bin"
mkdir -p "$REPO" "$BIN"
cat > "$BIN/gh" <<'GH'
#!/bin/sh
# Fake `gh pr view 7 --json files`; gone.js is deleted on disk, link.js a symlink.
printf '%s' '{"files":[{"path":"a.js"},{"path":"b.js"},{"path":"-x.js"},{"path":"sp ace.js"},{"path":"gone.js"},{"path":"link.js"}]}'
GH
chmod +x "$BIN/gh"
# Fake formatter: records each argument and appends a marker to the file.
cat > "$BIN/fakefmt" <<'FMT'
#!/bin/sh
for f in "$@"; do
  printf '%s\n' "$f" >> "$FMT_LOG"
  printf '// fmt\n' >> "$f"
done
FMT
chmod +x "$BIN/fakefmt"

(
  cd "$REPO" || exit 1
  git init -q -b main
  git config user.email t@example.com
  git config user.name t
  for f in a.js b.js c.js d.js e.js -x.js "sp ace.js"; do printf 'base\n' > "./$f"; done
  printf 'outside\n' > "$OUTSIDE"
  ln -s "$OUTSIDE" link.js
  git add -A && git commit -qm base
  printf 'user edit\n' >> b.js          # a PR file the operator is editing
  printf 'user edit\n' >> c.js          # unrelated dirty file
  printf 'staged edit\n' >> e.js && git add e.js   # unrelated staged entry
  printf 'scratch\n' > scratch.txt      # unrelated untracked file
) >/dev/null 2>&1

export FMT_LOG="$TMP/fmt.log"
(
  cd "$REPO" || exit 1
  export PATH="$BIN:$PATH"
  # shellcheck disable=SC1091
  . "$BLOCKS/baseline.sh"
  xargs -0 -r fakefmt < "$scope/approved-args"
  printf '// spill\n' >> d.js           # a formatter reaching outside the list
  . "$BLOCKS/stage.sh"
  . "$BLOCKS/commit.sh"
) >"$TMP/prepass.out" 2>"$TMP/prepass.err"
check "P1: the documented pre-pass blocks run to completion" "$?"

committed="$(git -C "$REPO" show --name-only --format= HEAD | LC_ALL=C sort | tr '\n' '|')"
[ "$committed" = "-x.js|a.js|sp ace.js|" ]
check "P1: the auto-fix commit holds exactly the approved changed paths (got $committed)" "$?"
[ "$(git -C "$REPO" log -1 --format=%s)" = "style: auto-fix lint and format issues" ]
check "P1: the commit carries the documented message" "$?"
grep -qx './-x.js' "$FMT_LOG" && ! grep -q '^-' "$FMT_LOG"
check "P1: every formatter argument is ./-prefixed, so -x.js is never an option" "$?"
[ "$(LC_ALL=C sort "$FMT_LOG" | tr '\n' '|')" = "./-x.js|./a.js|./sp ace.js|" ]
check "P1: the formatter received only the approved paths — never a dirty, missing, symlinked or unrelated one" "$?"
[ "$(cat "$OUTSIDE")" = "outside" ]
check "P1: a PR symlink's target outside the repo is never formatted" "$?"
[ "$(tail -n1 "$REPO/b.js")" = "user edit" ] && git -C "$REPO" diff --quiet HEAD~1 HEAD -- b.js
check "P1: an already-dirty PR file keeps the operator's edit, unformatted and uncommitted" "$?"
grep -q 'skipping already-dirty PR file b.js' "$TMP/prepass.err"
check "P1: the already-dirty PR file is reported" "$?"
[ "$(git -C "$REPO" status --porcelain=v1 -- c.js)" = " M c.js" ]
check "P1: an unrelated dirty file stays dirty and unstaged" "$?"
[ "$(git -C "$REPO" status --porcelain=v1 -- e.js)" = "M  e.js" ]
check "P1: an unrelated pre-staged entry stays staged and uncommitted" "$?"
[ "$(git -C "$REPO" status --porcelain=v1 -- scratch.txt)" = "?? scratch.txt" ]
check "P1: an untracked file stays untracked" "$?"
[ "$(git -C "$REPO" status --porcelain=v1 -- d.js)" = " M d.js" ] \
  && grep -q 'out-of-scope change left unstaged: d.js' "$TMP/prepass.err"
check "P1: formatter spill-over is reported and left unstaged" "$?"

# ── P2: the prose ────────────────────────────────────────────
python3 - "$PREPASS" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
section = text.split("## Step 2 — Script Pre-pass detection", 1)[1].split("## Step 4", 1)[0]
blocks = "\n".join(re.findall(r"^```bash\n(.*?)^```", section, flags=re.S | re.M))
bad = [p for p in (r"git add -A", r"git add \.", r"git commit -a\b") if re.search(p, blocks)]
table = [l for l in section.splitlines() if l.startswith("| ") and "`" in l]
tree = [l for l in table if re.search(r"(fix|write|black|isort|-w|format) \.`|cargo fmt|find \. ", l)]
sys.exit(1 if bad or tree else 0)
PY
check "P2: no pre-pass block stages tree-wide and no formatter runs on the whole tree" "$?"
grep -q 'gi-secscan.py --staged --policy-ref' "$PREPASS" && ! grep -q 'gi-secscan.py --working-tree' "$PREPASS"
check "P2: the auto-fix scan reads the staged set" "$?"
grep -q 'gi-secscan.py --staged --policy-ref' "$PR_SKILL" && grep -q 'Never `git add -A`' "$PR_SKILL"
check "P2: SKILL.source.md Step 2 restates scoped staging and the --staged scan" "$?"
grep -q 'approved paths' "$PR_SKILL"
check "P2: SKILL.source.md Step 2 scopes the auto-fix to approved paths" "$?"

echo ""
echo "  Results: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ]
