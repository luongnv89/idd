#!/usr/bin/env bash
# pr-review stand-in: re-run the proof for a bug fix (issue #556).
#
# PR #12 fixes bug #42 and its Decision Record cites a regression test. The
# review must not take that line's word. *Bug proof* in
# references/verification-checks.md re-runs the cited test: red at base (the
# merge-base, with the head's copy of the test, in a scratch worktree) and
# green at head (the PR checkout). The *Merge floor* in SKILL.md Step 7 needs
# `red→green` on a bug PR, so an auto run leaves open a PR whose test is
# already green at base, or whose Reproduction says `not reproduced`.
#
# This subject builds a real git fixture and runs the procedure on it:
#   - the PR read from GitHub cites a test that passes at base → left open;
#   - a true red→green proof meets the floor;
#   - `not reproduced`, a missing Reproduction line, a cited path outside the
#     diff or an unsafe path, a test red at head, and a base red from an
#     import rather than the test's assertion all leave the PR open;
#   - a non-bug issue has no proof to run;
#   - the `sensitivity not verified` row is reported;
#   - every base run leaves `git worktree list` and the PR checkout unchanged.
#
# Criteria are modelled as all `pass`, so each floor decision isolates the
# proof clause. Each outcome is emitted as a file case.json asserts with
# `file-exists`.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

export IDD_AUTO_MODE=1
gh auth status >/dev/null
gh pr view 12 --json number,title,body,state,files > "$EVAL_OUT/pr-view.json"
gh issue view 42 --json number,title,body,labels > "$EVAL_OUT/issue.json"

EVAL_OUT="$EVAL_OUT" python3 - <<'PY'
import json
import os
import re
import shutil
import subprocess
import tempfile

out = os.environ["EVAL_OUT"]
pr = json.load(open(os.path.join(out, "pr-view.json"), encoding="utf-8"))
issue = json.load(open(os.path.join(out, "issue.json"), encoding="utf-8"))
assert pr["state"] == "OPEN", pr["state"]
with open(os.path.join(out, "pr-body.md"), "w", encoding="utf-8") as fh:
    fh.write(pr["body"])

repo = tempfile.mkdtemp(prefix="bugproof-")
GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="eval", GIT_AUTHOR_EMAIL="eval@harness.local",
               GIT_COMMITTER_NAME="eval", GIT_COMMITTER_EMAIL="eval@harness.local")


def git(*args, cwd=repo):
    return subprocess.run(["git", *args], cwd=cwd, env=GIT_ENV, check=True,
                          capture_output=True, text=True).stdout.strip()


def write(rel, text):
    path = os.path.join(repo, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


BUGGY = "import re\n\ndef slugify(s):\n    return re.sub(r'[^a-z]+', '-', s.lower())\n"
FIXED = "import re\n\ndef slugify(s):\n    return re.sub(r'[^a-z0-9]+', '-', s.lower())\n"
TEST = ("import sys\nsys.path.insert(0, 'src')\nfrom slug import slugify\n"
        "assert slugify({arg!r}) == {want!r}, slugify({arg!r})\n")

git("init", "-q", "-b", "main")
write("src/slug.py", BUGGY)
git("add", "-A")
git("commit", "-qm", "chore(init): slug fixture (#1)")


def branch(name, test_arg, test_want, fixed=True):
    """A PR head off main: the fix (or not) plus a regression test."""
    git("checkout", "-q", "-b", name, "main")
    write("src/slug.py", FIXED if fixed else BUGGY)
    write("tests/test_slug.py", TEST.format(arg=test_arg, want=test_want))
    git("add", "-A")
    git("commit", "-qm", f"fix(slug): {name} (#42)")
    git("checkout", "-q", "main")
    return git("rev-parse", name)


# The PR read from GitHub: its test only checks lowercasing, true at base too.
heads = {
    "weak": branch("fix/42-weak-test", "Room", "room"),
    "strong": branch("fix/42-keep-digits", "Room 101", "room-101"),
    "unfixed": branch("fix/42-unfixed", "Room 101", "room-101", fixed=False),
}
# A head whose test imports a helper only the PR adds: red at base, but from
# the import, not the assertion.
git("checkout", "-q", "-b", "fix/42-new-helper", "main")
write("src/slug.py", FIXED)
write("src/helper.py", "WANT = 'room-101'\n")
write("tests/test_slug.py", "import sys\nsys.path.insert(0, 'src')\nfrom helper import WANT\n"
      "from slug import slugify\nassert slugify('Room 101') == WANT\n")
git("add", "-A")
git("commit", "-qm", "fix(slug): add helper (#42)")
git("checkout", "-q", "main")
heads["helper"] = git("rev-parse", "fix/42-new-helper")

REPRO = re.compile(r"^- \*\*Reproduction:\*\*(?P<rest>.*)$", re.M)
CITED = re.compile(r"regression test `(?P<path>[^`]+)`")
SAFE = re.compile(r"^(?!-)(?!.*(?:^|/)\.\.(?:/|$))[A-Za-z0-9._/-]+$")


def is_bug(snapshot):
    labels = {label["name"].lower() for label in snapshot.get("labels", [])}
    m = re.search(r"^## Type\s*\n+\s*(\w+)", snapshot.get("body", ""), re.M)
    return "bug" in labels or bool(m and m.group(1).lower() == "bug")


def runner(path):
    """Built from the repo's own runner, never from the PR body."""
    if path.endswith(".py"):
        return ["python3", path]
    if path.endswith(".sh"):
        return ["bash", path]
    return None


def run(cmd, cwd):
    try:
        done = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=60,
                              env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        return done.returncode, done.stderr
    except subprocess.TimeoutExpired:
        return None, ""


def bug_proof(snapshot, body, files, head, base="main"):
    """verification-checks.md *Bug proof*: one verdict, nothing run on doubt."""
    if not is_bug(snapshot):
        return "n/a", []
    m = REPRO.search(body)
    if not m or "not reproduced" in m["rest"]:
        return "not reproduced", []
    cited = CITED.search(m["rest"])
    if not cited:
        return "manual", []
    path = cited["path"]
    if not SAFE.match(path) or path not in files:
        return "unproven: cited test not in the diff", []
    cmd = runner(path)
    if cmd is None:
        return "unproven: no runner", []
    git("checkout", "-q", "--detach", head)
    head_exit, _ = run(cmd, repo)
    base_exit, base_err = None, ""
    scratch = tempfile.mkdtemp(prefix="bugproof-base-")
    wt = os.path.join(scratch, "wt")
    try:
        git("worktree", "add", "-q", "--detach", wt, git("merge-base", base, head))
        git("--literal-pathspecs", "checkout", head, "--", path, cwd=wt)
        base_exit, base_err = run(cmd, wt)
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", wt], cwd=repo,
                       capture_output=True)
        shutil.rmtree(scratch, ignore_errors=True)
    runs = [("base", base_exit), ("head", head_exit)]
    if head_exit is None or base_exit is None:
        return "unproven: timeout", runs
    if head_exit != 0:
        return "red at head", runs
    if base_exit == 0:
        return "green at base", runs
    if "AssertionError" not in base_err:
        return "unproven: base red is not the test's assertion", runs
    return "red→green", runs


def merge_floor(proof):
    """SKILL.md Step 7 *Merge floor*, criteria all `pass`: the proof clause."""
    if proof in ("n/a", "red→green"):
        return "met"
    return f"unmet: bug proof {proof}"


def decide(floor, auto):
    if floor == "met":
        return "merged"
    return "left_open" if auto else "ask"


def body_with(repro):
    return REPRO.sub(lambda _: f"- **Reproduction:**{repro}", pr["body"])


files = {f["path"] for f in pr["files"]}
not_bug = dict(issue, labels=[], body=issue["body"].replace("bug (high", "improvement (high"))
CITE = " `python3 tests/test_slug.py` confirmed red → regression test `{}`"

# scenario, issue snapshot, PR body, head, auto
SCENARIOS = [
    ("auto-fixture-green-at-base", issue, pr["body"], heads["weak"], True),
    ("auto-red-green", issue, pr["body"], heads["strong"], True),
    ("auto-not-reproduced", issue,
     body_with(" not reproduced — needs a real device (criterion marked unverified)"),
     heads["strong"], True),
    ("auto-no-reproduction-line", issue, REPRO.sub("", pr["body"]), heads["strong"], True),
    ("auto-path-not-in-diff", issue, body_with(CITE.format("tests/other.py")), heads["strong"], True),
    ("auto-unsafe-path", issue, body_with(CITE.format("../tests/test_slug.py")), heads["strong"], True),
    ("auto-red-at-head", issue, pr["body"], heads["unfixed"], True),
    ("auto-base-red-from-import", issue, pr["body"], heads["helper"], True),
    ("auto-not-a-bug", not_bug, pr["body"], heads["weak"], True),
    ("interactive-fixture-green-at-base", issue, pr["body"], heads["weak"], False),
]

decisions = {}
for name, snapshot, body, head, auto in SCENARIOS:
    proof, runs = bug_proof(snapshot, body, files, head)
    # The base run never touches the PR checkout and leaves no worktree.
    listed = git("worktree", "list", "--porcelain").count("worktree ")
    assert listed == 1, (name, listed)
    assert git("status", "--porcelain") == "", name
    if runs:
        assert git("rev-parse", "HEAD") == head, name
    floor = merge_floor(proof)
    decision = decide(floor, auto)
    decisions[name] = {"bug_proof": proof, "runs": runs, "merge_floor": floor,
                       "decision": decision}
    slug = proof.split(":")[0].replace("→", "-").replace(" ", "-").replace("/", "")
    for fname in (f"proof-{name}-{slug}.txt", f"floor-{name}-{decision}.txt"):
        with open(os.path.join(out, fname), "w", encoding="utf-8") as fh:
            fh.write(f"bug_proof={proof} runs={runs} merge_floor={floor} -> {decision}\n")

with open(os.path.join(out, "worktrees-clean.txt"), "w", encoding="utf-8") as fh:
    fh.write("git worktree list: 1 entry after every base run\n")
with open(os.path.join(out, "proof-decisions.json"), "w", encoding="utf-8") as fh:
    json.dump(decisions, fh, indent=2, sort_keys=True, ensure_ascii=False)
    fh.write("\n")

# Sensitivity rows: every `sensitivity not verified` Evidence cell is reported.
ROW = re.compile(r"^\|\s*(?P<crit>[^|]+?)\s*\|\s*(?:pass|fail|unverified)\s*\|\s*(?P<ev>[^|]*?)\s*\|\s*$")
not_verified = [(m["crit"], m["ev"].split("sensitivity not verified:", 1)[1].strip())
                for m in map(ROW.match, pr["body"].splitlines())
                if m and "sensitivity not verified:" in m["ev"]]
assert not_verified == [("Letters are lowercased", "no hunk to mutate")], not_verified
with open(os.path.join(out, "sensitivity-not-verified-1.txt"), "w", encoding="utf-8") as fh:
    fh.write("".join(f"{c}: {r}\n" for c, r in not_verified))

fixture = decisions["auto-fixture-green-at-base"]
reason = fixture["merge_floor"].split(": ", 1)[1]
crit, why = not_verified[0]
report = (
    f"Result: PASS — PR #{pr['number']} left open; merge floor unmet ({reason})\n"
    f"Evidence: bug proof: green at base — tests/test_slug.py exited 0 at base and at head; "
    f"merge floor: {fixture['merge_floor']}\n"
    f"Merge: ○ not attempted (merge floor unmet: {reason})\n"
    f"Uncertainty: sensitivity not verified — {crit}: {why}\n"
    "Decision: No approval needed.\n"
    "Next action: add a regression test that fails without the fix, then re-run "
    f"/issue-pr-review {pr['number']}\n"
)
lines = report.splitlines()
assert lines[0].startswith("Result: PASS") and "left open" in lines[0], lines[0]
assert "ready to merge" not in report and "MERGED" not in report
for label in ("Evidence: ", "Uncertainty: ", "Decision: ", "Next action: "):
    assert sum(line.startswith(label) for line in lines) == 1, label
with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write(report)

shutil.rmtree(repo, ignore_errors=True)
print("  ○ proof decisions: " + ", ".join(
    f"{k}={v['bug_proof']}/{v['decision']}" for k, v in sorted(decisions.items())))
PY
