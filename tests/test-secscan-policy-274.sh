#!/usr/bin/env bash
# test-secscan-policy-274.sh — who supplies the scan policy (issue #274)
#
# #272 closed the byte-source class: the scan reads the bytes that ship. This
# suite covers the class one layer up — the scan reads the right bytes, and is
# then *told to admit all of them*.
#
#   `security.allow_pattern` suppresses SCANNING, not findings: a matching path
#   is skipped before any rule runs. `.gitissue.yml` is repository data, and
#   /issue-pr-review runs with the pull request's branch checked out, so the
#   artifact under review supplies the policy governing its own review. A branch
#   committing `allow_pattern: "."` makes the gate report `verdict: clean` with
#   `scanned: 0` over a live key.
#
# Two things follow, and both are asserted here rather than assumed:
#
#   1. `scanned > 0` is NOT the test. Phase A3 commits a *narrow* pattern naming
#      only the secret-bearing file: `scanned` stays healthy and the secret
#      still ships. Only the policy's provenance rules that out, which is why
#      the fix is `--policy-ref` and not a threshold.
#   2. `skipped == 0` is NOT the test either. Under `--policy-ref` a skip is
#      authorized by the trusted ref — the allow-list feature working as
#      designed — so requiring zero would break every repo that uses it.
#   3. Naming the trusted ref is not the same as reaching it. A short
#      `origin/<branch>` is a *search*, and git tries `refs/heads/<ref>` before
#      `refs/remotes/<ref>`; `gh pr checkout` materialises the pull request's
#      attacker-chosen head-ref name as a local branch. A11 builds that
#      collision, so a PR branch literally named `origin/main` cannot re-supply
#      its own policy while `policy_source` still reports the ref the caller
#      asked for.
#
# Phase B covers the related `refs/replace` defect: `--no-replace-objects` is a
# git TOP-LEVEL option. Written the way the issue's AC #3 literally spells it —
# `git cat-file --no-replace-objects` — git answers `error: unknown option`,
# every read raises Unavailable, and the gate degrades to prose on every run.
# B4 asserts that rejection directly, so the placement can never regress to the
# form that disables the gate while appearing to harden it.
#
# Phase C is what makes the rest worth anything: it reverse-applies each fix to
# a scratch copy of the script and requires the matching cell to FAIL. A cell
# that passes against the unfixed code proves nothing.
#
# Phase D asserts the caller-side prose, because the script's default is
# deliberately unchanged: every existing call site still resolves policy from
# the work tree unless it passes the flag. A skill that never asks for the
# trusted ref is not protected by it.
#
# Usage: bash tests/test-secscan-policy-274.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export IDD_REPO_ROOT="$REPO_ROOT"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ gi-secscan policy provenance and replace-object hardening (issue #274)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT

python3 - > "$RESULTS" <<'PY'
"""Policy provenance, replace-object hardening, and their non-vacuity proofs."""

import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.environ["IDD_REPO_ROOT"]
SCRIPT = os.path.join(ROOT, "src", "shared", "scripts", "gi-secscan.py")

# A throwaway repository still reads the invoking user's global git config — an
# `init.defaultBranch`, a hook path, a `core.quotePath` — and a contract that
# only holds under one developer's config is not a contract.
os.environ["GIT_CONFIG_GLOBAL"] = os.devnull
os.environ["GIT_CONFIG_SYSTEM"] = os.devnull
os.environ["GIT_TERMINAL_PROMPT"] = "0"

# Split so this file never contains a literal the gate itself would flag.
SECRET = b"AWS_KEY=" + b"AKIA" + b"IOSFODNN7EXAMPLE\n"

OUT = []


def emit(ok, label):
    OUT.append(("PASS" if ok else "FAIL") + "|" + label)


def git(args, cwd):
    subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True
    )


def run(args, cwd, script=SCRIPT):
    """Run the scan and return (exit code, parsed verdict or None)."""
    proc = subprocess.run(
        [sys.executable, script, *args, "--quiet"],
        cwd=cwd,
        capture_output=True,
        check=False,
    )
    try:
        return proc.returncode, json.loads(proc.stdout.decode())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return proc.returncode, None


def build_repo(allow_pattern):
    """A repo whose feature branch carries a secret and, optionally, a config
    granting itself permission to ship it. `main` never carries that config —
    it is the trusted side.
    """
    repo = tempfile.mkdtemp()
    git(["init", "-q", "-b", "main", "."], repo)
    git(["config", "user.email", "t@example.invalid"], repo)
    git(["config", "user.name", "t"], repo)
    with open(os.path.join(repo, "readme.md"), "wb") as handle:
        handle.write(b"base\n")
    git(["add", "-A"], repo)
    git(["commit", "-qm", "base"], repo)
    git(["checkout", "-q", "-b", "feature"], repo)
    if allow_pattern is not None:
        with open(os.path.join(repo, ".gitissue.yml"), "w", encoding="utf-8") as handle:
            handle.write('security:\n  allow_pattern: "%s"\n' % allow_pattern)
    with open(os.path.join(repo, "leak.txt"), "wb") as handle:
        handle.write(SECRET)
    git(["add", "-A"], repo)
    git(["commit", "-qm", "work"], repo)
    return repo


# ── Phase A: the artifact under review must not supply its own policy ────────

# A1/A2 are one fixture read two ways: the same branch, the same secret, the
# only difference being where `security.*` came from.
repo = build_repo(".")
code, verdict = run(["--range", "main"], repo)
emit(
    code == 0 and verdict["scanned"] == 0 and verdict["verdict"] == "clean",
    "A1: the unfixed default is reproduced — a branch's own allow_pattern "
    f"yields clean/exit 0 with scanned 0 (exit {code})",
)
code, verdict = run(["--range", "main", "--policy-ref", "main"], repo)
emit(
    code == 1 and verdict["verdict"] == "block",
    f"A2: --policy-ref reads the base ref's policy and blocks (exit {code}, "
    "expected 1)",
)
emit(
    verdict is not None and verdict.get("policy_source") == "ref:main",
    "A2: policy_source names the ref that was actually used",
)
shutil.rmtree(repo, ignore_errors=True)

# A3: the narrow variant. This is the cell that rules out `scanned > 0` as the
# fix — the count is healthy and the secret still ships.
repo = build_repo(r"^leak\\.txt$")
code, verdict = run(["--range", "main"], repo)
emit(
    code == 0 and verdict["scanned"] > 0 and verdict["verdict"] == "clean",
    "A3: a NARROW allow_pattern passes with scanned > 0 — a threshold on "
    f"scanned would not have caught it (scanned {verdict['scanned']})",
)
code, verdict = run(["--range", "main", "--policy-ref", "main"], repo)
emit(
    code == 1 and verdict["verdict"] == "block",
    f"A3: --policy-ref blocks the narrow variant too (exit {code}, expected 1)",
)

# A4: a trusted ref that carries no .gitissue.yml falls back to the BUILT-IN
# defaults, never to the branch's file. Falling back would hand the decision
# straight back to the artifact.
code, verdict = run(["--range", "main", "--policy-ref", "main"], repo)
emit(
    code == 1 and verdict["skipped"] == 0,
    "A4: a ref with no .gitissue.yml uses built-in defaults, not the branch's "
    f"file (skipped {verdict['skipped']}, expected 0)",
)

# A5: a ref that does not resolve is exit 4 — the documented degrade — never a
# silent pass. A policy that could not be read permitted nothing.
code, _ = run(["--range", "main", "--policy-ref", "refs/heads/absent"], repo)
emit(code == 4, f"A5: an unresolvable --policy-ref exits 4, never 0 (exit {code})")

# A6: --policy-ref names *the* policy source. Merging a second one would let the
# branch's file back in through the side door.
for extra in (["--no-config"], ["--config", ".gitissue.yml"], ["--config-json", "{}"]):
    code, _ = run(["--range", "main", "--policy-ref", "main", *extra], repo)
    emit(code == 2, f"A6: --policy-ref conflicts with {extra[0]} (exit {code}, expected 2)")

# A7: policy_source is reported on every path, so a caller can always assert it.
code, verdict = run(["--range", "main", "--no-config"], repo)
emit(
    verdict is not None and verdict.get("policy_source") == "defaults",
    "A7: policy_source is 'defaults' when no config is consulted",
)
code, verdict = run(["--range", "main"], repo)
emit(
    verdict is not None
    and str(verdict.get("policy_source", "")).startswith("file:"),
    "A7: policy_source is 'file:<path>' on the unchanged default path",
)

# A8: presence, not truthiness. An empty value must be a usage error, never a
# silent fall-through to the work tree — an orchestrator rendering an unset
# spawn variable into the flag would otherwise re-open the exact #274 hole.
code, verdict = run(["--range", "main", "--policy-ref", ""], repo)
emit(
    code == 2,
    f"A8: an empty --policy-ref is a usage error, not a fall-back to the "
    f"branch's own config (exit {code}, expected 2)",
)

# A9: a value starting with `-` reaches git in an option position. Same guard
# `--range` already carries; argv injection does not need a shell.
code, _ = run(["--range", "main", "--policy-ref=-p"], repo)
emit(code == 2, f"A9: --policy-ref rejects an option-shaped revision (exit {code})")
shutil.rmtree(repo, ignore_errors=True)

# A10: the trusted ref carries `.gitissue.yml` as a TREE, not a blob. "Exists
# but unreadable" must be exit 4 like every other byte source in this script —
# collapsing it into "the ref has no config" would silently drop the trusted
# ref's real security.* (its extra secret patterns included) while the verdict
# still claimed policy_source: ref:<REF>.
repo = tempfile.mkdtemp()
git(["init", "-q", "-b", "main", "."], repo)
git(["config", "user.email", "t@example.invalid"], repo)
git(["config", "user.name", "t"], repo)
os.makedirs(os.path.join(repo, ".gitissue.yml"))
with open(os.path.join(repo, ".gitissue.yml", "inner"), "wb") as handle:
    handle.write(b"x\n")
git(["add", "-A"], repo)
git(["commit", "-qm", "base"], repo)
git(["checkout", "-q", "-b", "feature"], repo)
with open(os.path.join(repo, "leak.txt"), "wb") as handle:
    handle.write(SECRET)
git(["add", "-A"], repo)
git(["commit", "-qm", "work"], repo)
code, _ = run(["--range", "main", "--policy-ref", "main"], repo)
emit(
    code == 4,
    "A10: a .gitissue.yml that exists as a tree is exit 4, not a silent "
    f"defaults answer (exit {code}, expected 4)",
)
shutil.rmtree(repo, ignore_errors=True)


def build_shadow_repo():
    """A repo where the SHORT policy ref `origin/main` names two different refs.

    `refs/remotes/origin/main` is the clean reviewing side. `refs/heads/origin/main`
    is the artifact: /issue-pr-review Step 1 runs `gh pr checkout`, which
    materialises the pull request's own — attacker-chosen — `headRefName` as a
    *local branch*, and gitrevisions consults `refs/heads/<ref>` before
    `refs/remotes/<ref>`. So a PR branch literally named `origin/main` wins the
    lookup and hands its own narrow `allow_pattern` back as the trusted policy.
    """
    repo = build_repo(r"^leak\\.txt$")
    base = subprocess.run(
        ["git", "rev-parse", "main"], cwd=repo, capture_output=True, text=True,
        check=True,
    ).stdout.strip()
    git(["update-ref", "refs/remotes/origin/main", base], repo)
    git(["branch", "origin/main", "feature"], repo)
    return repo


# A11: the narrow-pattern variant again, reached through ref ambiguity instead
# of through the work tree. Every one of the four documented pass legs held —
# exit 0, `policy_source` exactly the ref the caller named, verdict not block,
# and `scanned` healthy — while the key shipped. Exit code only: on Unavailable
# the script returns 4 *before* printing its JSON, so there is no verdict to
# read and subscripting one would take the whole suite down with a TypeError.
repo = build_shadow_repo()
code, _ = run(
    ["--range", "refs/remotes/origin/main", "--policy-ref", "origin/main"], repo
)
emit(
    code == 4,
    "A11: a local branch shadowing the short remote policy ref is exit 4, never "
    f"a clean scan under the artifact's own allow_pattern (exit {code}, "
    "expected 4)",
)
# The other half: with no shadowing branch the very same short form must still
# resolve. A check that fails closed on every ordinary repo is not a fix.
git(["checkout", "-q", "main"], repo)
git(["branch", "-D", "origin/main"], repo)
git(["checkout", "-q", "feature"], repo)
code, verdict = run(
    ["--range", "refs/remotes/origin/main", "--policy-ref", "origin/main"], repo
)
named = verdict.get("policy_source") if verdict else None
emit(
    code == 1 and named == "ref:origin/main",
    "A11: with no shadowing branch the same short ref still resolves and blocks "
    f"(exit {code}, expected 1; policy_source {named})",
)
shutil.rmtree(repo, ignore_errors=True)


# ── Phase B: refs/replace must not redirect the bytes the gate reads ─────────


def build_replace_repo(level):
    """A repo with a `refs/replace` entry hiding the secret.

    `blob` remaps the object the scan reads; `commit` remaps the object the scan
    *enumerates*, which is the half `git rev-list` / `git diff-tree` decide.
    """
    repo = tempfile.mkdtemp()
    git(["init", "-q", "-b", "main", "."], repo)
    git(["config", "user.email", "t@example.invalid"], repo)
    git(["config", "user.name", "t"], repo)
    with open(os.path.join(repo, "readme.md"), "wb") as handle:
        handle.write(b"base\n")
    git(["add", "-A"], repo)
    git(["commit", "-qm", "base"], repo)
    base = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True,
        check=True,
    ).stdout.strip()
    with open(os.path.join(repo, "leak.txt"), "wb") as handle:
        handle.write(SECRET)
    git(["add", "-A"], repo)
    if level == "blob":
        secret_oid = subprocess.run(
            ["git", "rev-parse", ":leak.txt"], cwd=repo, capture_output=True,
            text=True, check=True,
        ).stdout.strip()
        clean_oid = subprocess.run(
            ["git", "hash-object", "-w", "--stdin"], cwd=repo, input="nothing\n",
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        git(["replace", secret_oid, clean_oid], repo)
        return repo, base, ["--staged"]
    git(["commit", "-qm", "secret"], repo)
    secret_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True,
        check=True,
    ).stdout.strip()
    git(["checkout", "-q", "-b", "decoy", base], repo)
    with open(os.path.join(repo, "other.txt"), "wb") as handle:
        handle.write(b"clean\n")
    git(["add", "-A"], repo)
    git(["commit", "-qm", "clean"], repo)
    clean_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True,
        check=True,
    ).stdout.strip()
    git(["checkout", "-q", "main"], repo)
    git(["replace", secret_commit, clean_commit], repo)
    return repo, base, ["--range", base]


REPLACE_REPOS = {}
for level in ("blob", "commit"):
    repo, base, mode = build_replace_repo(level)
    REPLACE_REPOS[level] = (repo, mode)
    code, verdict = run(mode, repo)
    emit(
        code == 1 and verdict["verdict"] == "block",
        f"B1/{level}: a refs/replace entry cannot hide the secret from the "
        f"scan (exit {code}, expected 1)",
    )

# B4: the placement trap, asserted directly. `--no-replace-objects` after the
# subcommand is rejected by git, which the script would surface as exit 4 — the
# gate silently degrading to prose on every run.
probe = subprocess.run(
    ["git", "cat-file", "--no-replace-objects", "-p", "HEAD"],
    cwd=REPLACE_REPOS["commit"][0], capture_output=True, check=False,
)
emit(
    probe.returncode != 0 and b"unknown option" in probe.stderr,
    "B4: `git cat-file --no-replace-objects` — the AC's literal wording — is "
    "rejected by git, so the flag must stay a TOP-LEVEL option",
)


# ── Phase C: non-vacuity — reverse-apply each fix, require the cell to fail ──

SCRATCH = tempfile.mkdtemp()
source = open(SCRIPT, encoding="utf-8").read()

# C1: strip the top-level flag from every git invocation. B1 must go clean.
reverted = os.path.join(SCRATCH, "no_hardening.py")
with open(reverted, "w", encoding="utf-8") as handle:
    handle.write(source.replace('"git", "--no-replace-objects", ', '"git", '))
emit(
    source != open(reverted, encoding="utf-8").read(),
    "C1: the --no-replace-objects fix is present to reverse-apply",
)
for level, (repo, mode) in REPLACE_REPOS.items():
    code, verdict = run(mode, repo, script=reverted)
    emit(
        code == 0 and verdict["verdict"] != "block",
        f"C1/{level}: reverse-applying --no-replace-objects makes B1/{level} "
        f"fail — the replaced object is scanned instead (exit {code})",
    )
for repo, _ in REPLACE_REPOS.values():
    shutil.rmtree(repo, ignore_errors=True)

# C2: make --policy-ref fall back to the work tree instead of standing alone.
# A2 must go clean, which is precisely the hole #274 reports.
FALLBACK_ANCHOR = "        values, source = read_policy_ref(args.policy_ref)"
emit(
    FALLBACK_ANCHOR in source,
    "C2: the --policy-ref resolution is present to reverse-apply",
)
reverted = os.path.join(SCRATCH, "policy_fallback.py")
with open(reverted, "w", encoding="utf-8") as handle:
    handle.write(
        source.replace(
            FALLBACK_ANCHOR,
            "        values, source = read_policy_ref(args.policy_ref)\n"
            "        found = find_config(None)\n"
            "        if found is not None:\n"
            "            values.update(read_security_config(found))",
        )
    )
repo = build_repo(".")
code, verdict = run(["--range", "main", "--policy-ref", "main"], repo, script=reverted)
emit(
    code == 0 and verdict["verdict"] == "clean",
    "C2: reverse-applying --policy-ref's exclusivity makes A2 fail — the "
    f"branch's own config governs its review again (exit {code})",
)
shutil.rmtree(repo, ignore_errors=True)

# C3: revert the presence test to a truthiness test. A8 must then stop being a
# usage error and become a scan governed by the branch's own config — the #274
# defect reached by supplying nothing rather than by supplying a ref.
TRUTHY_ANCHOR = "    if args.policy_ref is not None:"
GUARD_ANCHOR = "    if args.policy_ref is not None and ("
emit(
    TRUTHY_ANCHOR in source,
    "C3: the presence test is present to reverse-apply",
)
# Both substitutions are guarded, not just the first: an unguarded `.replace`
# whose anchor has drifted is a silent no-op, and the cell would then be
# asserting against unmodified source while still reporting a pass.
emit(
    GUARD_ANCHOR in source,
    "C3: the conflict guard's presence test is present to reverse-apply",
)
reverted = os.path.join(SCRATCH, "policy_truthy.py")
with open(reverted, "w", encoding="utf-8") as handle:
    handle.write(
        source.replace(TRUTHY_ANCHOR, "    if args.policy_ref:").replace(
            GUARD_ANCHOR, "    if args.policy_ref and ("
        )
    )
repo = build_repo(".")
code, verdict = run(["--range", "main", "--policy-ref", ""], repo, script=reverted)
emit(
    code == 0
    and verdict["verdict"] == "clean"
    and str(verdict["policy_source"]).startswith("file:"),
    "C3: reverse-applying the presence test makes A8 fail — an empty ref falls "
    f"back to the branch's own config (exit {code})",
)
shutil.rmtree(repo, ignore_errors=True)

# C4: drop the ambiguity check. A11 must then go clean/exit 0 — the shadowing
# local branch wins the short-ref lookup again and re-supplies its own narrow
# allow_pattern, with `policy_source` still naming the ref the caller asked for.
AMBIGUITY_ANCHOR = "    _reject_ambiguous_ref(ref)\n"
emit(
    AMBIGUITY_ANCHOR in source,
    "C4: the policy-ref ambiguity check is present to reverse-apply",
)
reverted = os.path.join(SCRATCH, "policy_ambiguous.py")
with open(reverted, "w", encoding="utf-8") as handle:
    handle.write(source.replace(AMBIGUITY_ANCHOR, "", 1))
repo = build_shadow_repo()
code, verdict = run(
    ["--range", "refs/remotes/origin/main", "--policy-ref", "origin/main"],
    repo,
    script=reverted,
)
emit(
    code == 0
    and verdict is not None
    and verdict["verdict"] == "clean"
    and verdict.get("policy_source") == "ref:origin/main",
    "C4: reverse-applying the ambiguity check makes A11 fail — the PR's own "
    f"branch shadows the trusted remote ref and governs its review (exit {code})",
)
shutil.rmtree(repo, ignore_errors=True)
shutil.rmtree(SCRATCH, ignore_errors=True)


# ── Phase D: the callers must actually ask for the trusted policy ────────────

# The script's default is deliberately unchanged, so a call site that never
# passes the flag is not protected by it. Each entry is (file, required
# substrings). A missing substring fails the cell by construction — that is the
# whole non-vacuity argument for a prose assertion.
CALLERS = {
    os.path.join("src", "skills", "issue-pr-review", "SKILL.source.md"): [
        "--policy-ref",
        "policy_source",
        "scanned",
        "skipped",
    ],
    os.path.join(
        "src", "skills", "issue-pr-review", "references",
        "prepass-tests-ci-mechanics.md",
    ): ["--policy-ref", "policy_source", "scanned", "skipped"],
    os.path.join("src", "skills", "issue-resolver", "SKILL.source.md"): [
        "--policy-ref",
        "policy_source",
        "scanned",
        "skipped",
    ],
    os.path.join("src", "shared", "agents", "fixer.md"): [
        "secscan_policy_ref",
        "policy_source",
        "scanned",
        "skipped",
    ],
    # The implementer runs the gate per commit on a branch it built from an
    # untrusted issue body. `pipeline-steps.md` binds `secscan_policy_ref` for
    # it, so the agent must actually consume the variable — a binding with no
    # consumer reads as protection that is not there.
    os.path.join("src", "shared", "agents", "implementer.md"): [
        "secscan_policy_ref",
        "policy_source",
        "scanned",
        "skipped",
    ],
    os.path.join("docs", "pre-commit-security.md"): [
        "--policy-ref",
        "policy_source",
        "scanned",
        "skipped",
    ],
}
for rel, needles in CALLERS.items():
    text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    missing = [n for n in needles if n not in text]
    emit(
        not missing,
        f"D: {rel} states the policy-ref and scanned/skipped pass condition"
        + (f" (missing: {', '.join(missing)})" if missing else ""),
    )

# The two orchestrators must BIND the fixer's ref, or the agent variable is
# never set and the agent silently takes the unprotected path.
# Proximity, not mere presence. Each of these files enumerates the spawn
# variables an agent receives; `secscan_script` is the anchor that marks the
# enumeration. A `secscan_policy_ref` mention anywhere else in the file — a
# rationale paragraph, a changelog-style note — would satisfy a bare substring
# check while the variable is never actually bound, and the agent would take
# the unprotected path with the prose in `fixer.md`/`implementer.md`
# unreachable. Requiring the two within one window ties the mention to the
# binding site. The resolver binds at two spawn sites — the implementer in
# steps/step-3-implement.md and the fixer in steps/step-4-qa.md (one file each
# since #323) — so `expected` records how many windows must contain both.
BINDERS = {
    os.path.join(
        "src", "skills", "issue-pr-review", "references", "review-loop-mechanics.md"
    ): 1,
    os.path.join(
        "src", "skills", "issue-resolver", "references", "steps", "step-3-implement.md"
    ): 1,
    os.path.join(
        "src", "skills", "issue-resolver", "references", "steps", "step-4-qa.md"
    ): 1,
    os.path.join("src", "skills", "issue-resolver", "SKILL.source.md"): 1,
}
WINDOW = 1200
for rel, expected in BINDERS.items():
    text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
    paired = 0
    start = text.find("secscan_script")
    while start != -1:
        if "secscan_policy_ref" in text[start : start + WINDOW]:
            paired += 1
        start = text.find("secscan_script", start + 1)
    emit(
        paired >= expected,
        f"D: {rel} binds secscan_policy_ref beside secscan_script at "
        f"{expected} spawn site(s) (found {paired})",
    )

print("\n".join(OUT))
PY

while IFS='|' read -r verdict label; do
  [ -n "${verdict:-}" ] || continue
  if [ "$verdict" = "PASS" ]; then
    pass "$label"
  elif [ "$verdict" = "SKIP" ]; then
    echo "  ○ $label"
  else
    fail "$label"
  fi
done < "$RESULTS"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ The scan policy can still come from the artifact under review"
  exit 1
fi
echo "  ✓ Scan policy comes from the reviewing side, and replace objects cannot redirect it"
