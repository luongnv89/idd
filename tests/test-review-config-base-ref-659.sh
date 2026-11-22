#!/usr/bin/env bash
# test-review-config-base-ref-659.sh — who supplies the review gates (issue #659)
#
# /issue-pr-review checks out the pull request's branch before it reviews it,
# so a gate read from the working tree's `.idd.yml` is a gate the PR sets for
# its own review: commit `review.run_tests: false` and the tests never run.
# The fix reads the gates from the default branch's tip by full object id
# (`gi-config.py --ref <oid>`) and reports what the PR tried to change
# (`--compare-ref`) as a non-blocking finding.
#
# Every cell is a named test obligation of the sensitive-change gate. Where a
# cell guards a script or a shipped shell block, a phase-M cell reverse-applies
# that guard to a scratch copy and requires the cell to FAIL: a cell that passes
# against the unguarded code proves nothing.
#
#   PAC5  a PR-branch `review.run_tests: false` does not switch tests off
#   P6    a ref with no config is the defaults; legacy name; exit 2/3/4 contract
#   P8    --compare-ref names every added/removed/changed key, any section
#   P9    an unreadable compare side is a finding, never a failure
#   P10   a local branch named `origin/main` cannot shadow the base
#   P11   a missing remote ref cannot fall through to `refs/heads/refs/...`
#   P16   the Step 2 pointer and the comparison run in --review-only too
#   P17   the compare call is paired with its "could not be compared" form
#   P18   the shipped resolution block fails closed to the defaults
#   P19   Configuration reads the base, says so, and never reads the work tree
#   P20   the comparison starts at the merge base
#   P21   the finding is report-level, non-blocking, and not a PARTIAL cause
#   P22   under --ref the schema is never found by walking the work tree
#
# Usage: bash tests/test-review-config-base-ref-659.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export IDD_REPO_ROOT="$REPO_ROOT"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Review gates come from the default branch (issue #659)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT

python3 - > "$RESULTS" <<'PY'
"""Base-branch review gates, the config-change finding, and their mutations."""

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = os.environ["IDD_REPO_ROOT"]
SRC = os.path.join(ROOT, "src", "shared", "scripts", "gi-config.py")
SCHEMA = os.path.join(ROOT, "docs", "config-schema.md")
BUILT_SKILL = os.path.join(ROOT, "skills", "issue-pr-review")
BUILT = os.path.join(BUILT_SKILL, "references", "scripts", "gi-config.py")
REAL_GIT = shutil.which("git")

# A throwaway repository still reads the invoking user's global git config.
os.environ["GIT_CONFIG_GLOBAL"] = os.devnull
os.environ["GIT_CONFIG_SYSTEM"] = os.devnull
os.environ["GIT_TERMINAL_PROMPT"] = "0"
for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
    os.environ.pop(name, None)

SCRATCH = tempfile.mkdtemp(prefix="idd-659-")
OUT = []


def emit(ok, label):
    OUT.append(("PASS" if ok else "FAIL") + "|" + label)


def git(args, cwd):
    return subprocess.run(
        ["git", "-c", "user.email=t@example.invalid", "-c", "user.name=t", *args],
        cwd=cwd, check=True, capture_output=True, text=True,
    ).stdout.strip()


def write(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def commit_file(repo, name, text, message):
    write(os.path.join(repo, name), text)
    git(["add", name], repo)
    git(["commit", "-q", "-m", message], repo)


def run_cfg(args, cwd, script=SRC, schema=SCHEMA):
    """Run gi-config; return (exit code, parsed payload or None, stderr)."""
    argv = [sys.executable, script, *args]
    if schema is not None:
        argv += ["--schema", schema]
    proc = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, check=False)
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        payload = None
    return proc.returncode, payload, proc.stderr


def new_repo(label):
    repo = os.path.join(SCRATCH, label)
    os.makedirs(repo)
    git(["init", "-q", "-b", "main", "."], repo)
    return repo


BASE_CFG = "review:\n  max_cycles: 4\n"
HOSTILE_CFG = "review:\n  max_cycles: 99\n  run_tests: false\n"


def pr_repo(label, base_cfg=BASE_CFG):
    """main carries the trusted config; the checked-out PR branch a hostile one.

    `origin` is a real bare remote, so `refs/remotes/origin/main` exists the
    way `git fetch` makes it.
    """
    bare = os.path.join(SCRATCH, label + ".git")
    git(["init", "-q", "--bare", bare], SCRATCH)
    repo = new_repo(label)
    if base_cfg is None:
        commit_file(repo, "README.md", "base\n", "base")
    else:
        commit_file(repo, ".idd.yml", base_cfg, "base config")
    git(["remote", "add", "origin", bare], repo)
    git(["push", "-q", "origin", "main"], repo)
    git(["fetch", "-q", "origin"], repo)
    base_oid = git(["rev-parse", "main"], repo)
    git(["checkout", "-q", "-b", "fix/1-pr"], repo)
    commit_file(repo, ".idd.yml", HOSTILE_CFG, "pr sets its own gates")
    return repo, base_oid


MUTANTS = os.path.join(SCRATCH, "mutants")
os.makedirs(MUTANTS)


def mutant(source_path, anchor, replacement, name):
    """A scratch copy with one guard reverse-applied, or None if the anchor drifted."""
    text = open(source_path, encoding="utf-8").read()
    if anchor not in text:
        return None
    path = os.path.join(MUTANTS, name)
    write(path, text.replace(anchor, replacement, 1))
    return path


def check_mutant(cell, label, source_path, anchor, replacement):
    """The cell must FAIL against the mutant — a guard it does not need is not tested."""
    path = mutant(source_path, anchor, replacement, label.split(":")[0] + ".py")
    emit(path is not None, f"{label}: the guard is present to reverse-apply")
    if path is not None:
        ok, detail = cell(path)
        emit(not ok, f"{label}: reverse-applying the guard makes the cell fail ({detail})")


# ── PAC5: a PR-branch edit to review.run_tests does not switch tests off ─────


def cell_pac5(script, schema=SCHEMA):
    repo, base_oid = pr_repo("pac5-" + os.path.basename(script).replace(".", "-") + str(len(OUT)))
    code, payload, _ = run_cfg(["--ref", base_oid], repo, script, schema)
    ref_value = payload["config"].get("review.run_tests") if payload else None
    code_n, payload_n, _ = run_cfg([], repo, script, schema)
    plain_value = payload_n["config"].get("review.run_tests") if payload_n else None
    ok = (
        code == 0
        and ref_value is True
        and payload["config"].get("review.max_cycles") == 4
        and payload.get("config_source") == f"ref:{base_oid}"
        and payload.get("config_file") == ".idd.yml"
        and code_n == 0
        and plain_value is False
    )
    return ok, f"--ref run_tests={ref_value} exit {code}; no-ref control run_tests={plain_value}"


ok, detail = cell_pac5(SRC)
emit(ok, f"PAC5: src gi-config --ref <base_oid> keeps review.run_tests true while the PR branch says false ({detail})")
ok, detail = cell_pac5(BUILT, schema=None)
emit(ok, f"PAC5: built gi-config (bundled schema) --ref <base_oid> keeps tests on ({detail})")
check_mutant(
    cell_pac5,
    "PAC5-M: read the work tree under --ref",
    SRC,
    "    data, name = read_ref_config(oid)\n    if name == LEGACY_CONFIG_NAME:",
    "    data, name = Path(DEFAULT_CONFIG_NAME).read_bytes(), DEFAULT_CONFIG_NAME\n    if name == LEGACY_CONFIG_NAME:",
)

# ── Payload shape: no --ref keeps exactly three keys ─────────────────────────

repo, base_oid = pr_repo("shape")
code, payload, _ = run_cfg([], repo)
emit(
    code == 0 and payload is not None and set(payload) == {"config", "config_file", "first_run"},
    f"PAYLOAD: without --ref the payload is exactly config, config_file, first_run (got {sorted(payload or {})})",
)
code, payload, _ = run_cfg(["--ref", base_oid], repo)
emit(
    code == 0 and payload is not None
    and set(payload) == {"config", "config_file", "config_source", "first_run"},
    f"PAYLOAD: --ref adds only config_source (got {sorted(payload or {})})",
)
code, payload, _ = run_cfg(["--ref", base_oid, "--compare-ref", "HEAD"], repo)
emit(
    code == 0 and payload is not None
    and set(payload) == {"changed_keys", "compare_error", "config", "config_file", "config_source", "first_run"},
    f"PAYLOAD: --compare-ref adds changed_keys and compare_error (got {sorted(payload or {})})",
)

# ── P6: no config at the ref is the defaults; legacy; the exit contract ──────

empty_dir = os.path.join(SCRATCH, "defaults-dir")
os.makedirs(empty_dir)
_, defaults_payload, _ = run_cfg([], empty_dir)
DEFAULTS = defaults_payload["config"]


def cell_p6_defaults(script):
    repo, base_oid = pr_repo("p6-" + str(len(OUT)), base_cfg=None)
    code, payload, _ = run_cfg(["--ref", base_oid], repo, script)
    ok = (
        code == 0
        and payload is not None
        and payload.get("config_source") == f"ref:{base_oid}"
        and payload.get("config_file") is None
        and payload.get("first_run") is True
        and payload.get("config") == DEFAULTS
    )
    got = payload["config"].get("review.run_tests") if payload else None
    return ok, f"exit {code}, run_tests={got}, config_file={payload and payload.get('config_file')!r}"


ok, detail = cell_p6_defaults(SRC)
emit(ok, f"P6: a base with no .idd.yml yields ref:<REF>, config_file null, the defaults — the work tree's hostile file ignored ({detail})")
check_mutant(
    cell_p6_defaults,
    "P6-M: fall back to the work tree when the ref has no config",
    SRC,
    "    overrides = {} if data is None else parse_user_config(data, f\"{args.ref}:{name}\")",
    "    overrides = load_user_config(Path(DEFAULT_CONFIG_NAME)) if data is None else parse_user_config(data, f\"{args.ref}:{name}\")",
)

repo = new_repo("p6-legacy")
commit_file(repo, ".gitissue.yml", "review:\n  max_cycles: 7\n", "legacy config")
legacy_oid = git(["rev-parse", "HEAD"], repo)
code, payload, err = run_cfg(["--ref", legacy_oid], repo)
emit(
    code == 0 and payload["config"]["review.max_cycles"] == 7
    and payload["config_file"] == ".gitissue.yml" and "legacy .gitissue.yml found" in err,
    f"P6: the legacy .gitissue.yml is read when .idd.yml is absent at the ref, with a ⚠ line (exit {code})",
)
commit_file(repo, ".idd.yml", "review:\n  max_cycles: 5\n", "new config")
both_oid = git(["rev-parse", "HEAD"], repo)
code, payload, _ = run_cfg(["--ref", both_oid], repo)
emit(
    code == 0 and payload["config"]["review.max_cycles"] == 5 and payload["config_file"] == ".idd.yml",
    f"P6: with both names at the ref, .idd.yml wins and the legacy file is not read (exit {code})",
)

repo = new_repo("p6-invalid")
commit_file(repo, ".idd.yml", "review:\n  max_cycles: three\n", "invalid base config")
code, payload, err = run_cfg(["--ref", git(["rev-parse", "HEAD"], repo)], repo)
emit(
    code == 3 and payload is None and "review.max_cycles" in err,
    f"P6: an invalid config at the ref is exit 3 naming the key (exit {code})",
)

for bad in ("", "-x", "--help"):
    code, _, err = run_cfg([f"--ref={bad}"], repo)
    emit(code == 2, f"P6: --ref={bad!r} is a usage error, exit 2 (exit {code})")
code, _, _ = run_cfg(["--compare-ref", "HEAD"], repo)
emit(code == 2, f"P6: --compare-ref without --ref is exit 2 (exit {code})")
code, _, _ = run_cfg(["--ref", "HEAD", "--config", "other.yml"], repo)
emit(code == 2, f"P6: --config with --ref is exit 2 (exit {code})")
code, payload, _ = run_cfg(["--ref", "0" * 40], repo)
emit(code == 4 and payload is None, f"P6: a 40-hex id naming no commit is exit 4 (exit {code})")
code, _, _ = run_cfg(["--ref", "no-such-branch"], repo)
emit(code == 4, f"P6: a name that does not resolve is exit 4 (exit {code})")
tree_repo = new_repo("p6-tree")
commit_file(tree_repo, ".idd.yml/inner", "x\n", "config path is a tree")
code, _, err = run_cfg(["--ref", git(["rev-parse", "HEAD"], tree_repo)], tree_repo)
emit(code == 4 and "could not be read" in err, f"P6: a present but unreadable .idd.yml at the ref is exit 4, not the defaults (exit {code})")

# ── P8: every added / removed / changed key, any section, any checkout ───────

P8_BASE = "review:\n  max_cycles: 4\n  soft_pass: true\nissue:\n  auto_normalize: true\n"
P8_HEAD = (
    "review:\n  max_cycles: 4\n  run_tests: true\n"
    "issue:\n  auto_normalize: false\nresolver:\n  plan_approval: human\n"
)
P8_EXPECTED = ["issue.auto_normalize", "resolver.plan_approval", "review.run_tests", "review.soft_pass"]


def cell_p8(script):
    repo = new_repo("p8-" + str(len(OUT)))
    commit_file(repo, ".idd.yml", P8_BASE, "base")
    base_oid = git(["rev-parse", "HEAD"], repo)
    git(["checkout", "-q", "-b", "pr"], repo)
    commit_file(repo, ".idd.yml", P8_HEAD, "pr")
    head_oid = git(["rev-parse", "HEAD"], repo)
    # Work tree on a third branch, with uncommitted edits on top.
    git(["checkout", "-q", "-b", "elsewhere", base_oid], repo)
    commit_file(repo, ".idd.yml", "review:\n  max_cycles: 2\n", "elsewhere")
    write(os.path.join(repo, ".idd.yml"), "review:\n  max_cycles: 1\n  check_ci: false\n")
    code, payload, _ = run_cfg(["--ref", base_oid, "--compare-ref", head_oid], repo, script)
    keys = payload.get("changed_keys") if payload else None
    ok = code == 0 and keys == P8_EXPECTED and payload.get("compare_error") is None
    return ok, f"exit {code}, changed_keys={keys}"


ok, detail = cell_p8(SRC)
emit(ok, f"P8: --compare-ref names the added, removed and changed keys, a resolver.* key and an explicit default included, whatever is checked out ({detail})")
check_mutant(
    cell_p8,
    "P8-M: forget keys the PR removed",
    SRC,
    "        for key in set(base) | set(other)\n",
    "        for key in set(other)\n",
)

repo = new_repo("p8-types")
commit_file(repo, ".idd.yml", "review:\n  run_tests: true\n", "base")
b = git(["rev-parse", "HEAD"], repo)
commit_file(repo, ".idd.yml", "review:\n  run_tests: 1\n", "bool to int")
code, payload, _ = run_cfg(["--ref", b, "--compare-ref", "HEAD"], repo)
emit(
    code == 0 and payload["changed_keys"] == ["review.run_tests"],
    f"P8: true → 1 is a change, though Python's True == 1 (changed_keys={payload and payload.get('changed_keys')})",
)

# ── P9: an unreadable compare side is a finding, never a failure ─────────────


def cell_p9(script):
    repo = new_repo("p9-" + str(len(OUT)))
    commit_file(repo, ".idd.yml", BASE_CFG, "base")
    base_oid = git(["rev-parse", "HEAD"], repo)
    commit_file(repo, ".idd.yml", "review: [unclosed\n", "invalid pr config")
    head_oid = git(["rev-parse", "HEAD"], repo)
    code, payload, _ = run_cfg(["--ref", base_oid, "--compare-ref", head_oid], repo, script)
    ok = (
        code == 0
        and payload is not None
        and payload["config"].get("review.max_cycles") == 4
        and payload.get("changed_keys") is None
        and isinstance(payload.get("compare_error"), str)
        and payload["compare_error"] != ""
    )
    return ok, f"exit {code}, compare_error={payload and payload.get('compare_error')!r}"


ok, detail = cell_p9(SRC)
emit(ok, f"P9: an invalid PR-branch config keeps exit 0 and the base config, changed_keys null, compare_error set ({detail})")
check_mutant(
    cell_p9,
    "P9-M: let a compare-side failure escape",
    SRC,
    "    except (Unavailable, ConfigError) as exc:\n        return None, str(exc)",
    "    except KeyError as exc:\n        return None, str(exc)",
)
repo = new_repo("p9-unresolved")
commit_file(repo, ".idd.yml", BASE_CFG, "base")
code, payload, _ = run_cfg(["--ref", "HEAD", "--compare-ref", "no-such-ref"], repo)
emit(
    code == 0 and payload["changed_keys"] is None and "no-such-ref" in payload["compare_error"],
    f"P9: an unresolvable compare ref is compare_error, exit 0 (exit {code})",
)

# ── P10: a local branch named origin/main cannot shadow the base ─────────────


def shadow_repo(label):
    repo, base_oid = pr_repo(label)
    # `gh pr checkout` materialises the PR's chosen head name as a local branch.
    git(["branch", "origin/main", "fix/1-pr"], repo)
    return repo, base_oid


def cell_p10(script):
    repo, _ = shadow_repo("p10-" + str(len(OUT)))
    code_full, payload, _ = run_cfg(["--ref", "refs/remotes/origin/main"], repo, script)
    code_short, payload_short, _ = run_cfg(["--ref", "origin/main"], repo, script)
    full_value = payload["config"].get("review.run_tests") if payload else None
    ok = code_full == 0 and full_value is True and code_short == 4 and payload_short is None
    return ok, f"refs/remotes/origin/main exit {code_full} run_tests={full_value}; origin/main exit {code_short}"


ok, detail = cell_p10(SRC)
emit(ok, f"P10: the fully-qualified remote ref returns the base values; the ambiguous short name exits 4 ({detail})")
check_mutant(
    cell_p10,
    "P10-M: drop the short-name ambiguity check",
    SRC,
    "        if len(found) > 1:\n",
    "        if False:\n",
)

# ── Shims for running the shipped shell blocks ────────────────────────────────

SHIMS = os.path.join(SCRATCH, "shims")
NOPY = os.path.join(SCRATCH, "nopython")
os.makedirs(SHIMS)
os.makedirs(NOPY)
write(os.path.join(SHIMS, "git"), f"""#!/bin/sh
# Log every argv (one record per line, args split by \\037), then defer to git.
for a in "$@"; do printf '%s\\037' "$a"; done >> "$SHIM_LOG"; printf '\\n' >> "$SHIM_LOG"
if [ "$SHIM_MODE" = nofetch ] && [ "$1" = fetch ]; then exit 0; fi
if [ "$SHIM_MODE" = badoid ] && [ "$1" = rev-parse ]; then
  case "$*" in *refs/remotes/origin/*) echo deadbeef; exit 0 ;; esac
fi
exec {REAL_GIT} "$@"
""")
write(os.path.join(SHIMS, "gh"), "#!/bin/sh\nprintf '%s\\n' \"$FAKE_BASE\"\n")
write(os.path.join(NOPY, "python3"), "#!/bin/sh\nexit 127\n")
for f in (os.path.join(SHIMS, "git"), os.path.join(SHIMS, "gh"), os.path.join(NOPY, "python3")):
    os.chmod(f, 0o755)


def fenced_block(path, must_contain):
    """The first ```bash block in `path` that contains `must_contain`."""
    text = open(path, encoding="utf-8").read()
    for body in re.findall(r"^```bash\n(.*?)^```", text, re.MULTILINE | re.DOTALL):
        if must_contain in body:
            return body
    return None


MECH_LOOP = os.path.join(BUILT_SKILL, "references", "review-loop-mechanics.md")
RESOLUTION = fenced_block(MECH_LOOP, 'gi-config.py --ref "$base_oid"')
emit(RESOLUTION is not None, "P18: the built review-loop-mechanics.md ships the fenced resolution block")
RESOLUTION = RESOLUTION or ""
emit(
    "references/scripts/gi-config.py" in RESOLUTION,
    "P18: the shipped block calls the bundled script by its skill-relative path",
)


def run_block(block, repo, mode="", base="main", no_python=False, prefix=""):
    """Run a shipped block under bash; return (stdout+stderr, logged git argv lists)."""
    log = os.path.join(SCRATCH, f"git-{len(OUT)}-{mode or 'plain'}.log")
    open(log, "w").close()
    script = prefix + block.replace("references/scripts/gi-config.py", BUILT)
    path = SHIMS + os.pathsep + (NOPY + os.pathsep if no_python else "") + os.environ["PATH"]
    env = {**os.environ, "PATH": path, "SHIM_LOG": log, "SHIM_MODE": mode, "FAKE_BASE": base}
    proc = subprocess.run(["bash", "-c", script], cwd=repo, env=env, capture_output=True, text=True, check=False)
    calls = [line.split("\x1f")[:-1] for line in open(log, encoding="utf-8").read().splitlines()]
    return proc.stdout + proc.stderr, calls


def reads_work_tree_config(calls):
    """Any git call naming the index or a config path without a full commit id."""
    for argv in calls:
        for arg in argv:
            if arg.endswith((".idd.yml", ".gitissue.yml")) and ":" in arg:
                oid = arg.split(":", 1)[0]
                if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", oid):
                    return True
    return False


def hostile_checkout(label, **kw):
    repo, base_oid = pr_repo(label, **kw)
    write(os.path.join(repo, ".idd.yml"), HOSTILE_CFG)
    git(["add", ".idd.yml"], repo)
    return repo, base_oid


DEFAULTS_LINE = "⚠ Review settings: built-in defaults (base branch unreadable)"


def hostile(out):
    """The PR branch's values reached the output (a bare "99" could be part of an id)."""
    return '"review.max_cycles": 99' in out or "max_cycles: 99" in out


def cell_p18(block):
    results = []
    # (a) the remote ref is missing: the fetch "succeeds" but creates nothing.
    repo, _ = hostile_checkout("p18a-" + str(len(OUT)))
    git(["update-ref", "-d", "refs/remotes/origin/main"], repo)
    results.append(("missing remote ref", *run_block(block, repo, mode="nofetch")))
    # (b) base_oid is not a full hex id.
    repo, _ = hostile_checkout("p18b-" + str(len(OUT)))
    results.append(("non-hex base_oid", *run_block(block, repo, mode="badoid")))
    # (c) no default branch name at all.
    repo, _ = hostile_checkout("p18c-" + str(len(OUT)))
    results.append(("empty base", *run_block(block, repo, base="")))
    bad = []
    for name, out, calls in results:
        if DEFAULTS_LINE not in out or hostile(out) or reads_work_tree_config(calls):
            bad.append(name)
    return not bad, "failed: " + ", ".join(bad) if bad else "all three select the defaults"


ok, detail = cell_p18(RESOLUTION)
emit(ok, f"P18: missing remote ref, non-hex or empty base_oid → built-in defaults; the staged hostile .idd.yml is never read ({detail})")
p18_mutant = RESOLUTION.replace('if ! is_oid "$base_oid"; then', "if false; then", 1)
emit(p18_mutant != RESOLUTION, "P18-M: the oid check is present to reverse-apply")
ok, detail = cell_p18(p18_mutant)
emit(not ok, f"P18-M: without the oid check the block reads the index's hostile config ({detail})")

# Controls: the block's happy path and its by-hand degrade both read the base.
repo, base_oid = hostile_checkout("p18-ok")
out, calls = run_block(RESOLUTION, repo)
emit(
    f"○ Review settings: origin/main @ {base_oid} (.idd.yml)" in out
    and '"review.run_tests": true' in out and '"review.max_cycles": 4' in out
    and not hostile(out) and not reads_work_tree_config(calls),
    "P18: with the base readable the block prints the base config and the settings line with the full id",
)
out, calls = run_block(RESOLUTION, repo, no_python=True)
emit(
    "⚠ gi-config unavailable — reading .idd.yml by hand" in out
    and "max_cycles: 4" in out and not hostile(out)
    and f"○ Review settings: origin/main @ {base_oid} (.idd.yml)" in out
    and not reads_work_tree_config(calls),
    "P18: with no python3 the by-hand read prints the base blob, never the work tree's",
)
repo, base_oid = hostile_checkout("p18-nocfg", base_cfg=None)
out, _ = run_block(RESOLUTION, repo)
emit(
    f"○ Review settings: origin/main @ {base_oid} (defaults — no .idd.yml at the base)" in out
    and '"review.run_tests": true' in out and not hostile(out),
    "P18/AC4: a base with no .idd.yml runs on the defaults and says so",
)

# ── P11: a deleted remote ref cannot fall through to refs/heads/refs/... ─────


def p11_repo(label):
    repo, base_oid = pr_repo(label)
    git(["update-ref", "-d", "refs/remotes/origin/main"], repo)
    git(["branch", "refs/remotes/origin/main", "fix/1-pr"], repo)
    return repo, base_oid


def cell_p11(script):
    repo, _ = p11_repo("p11-" + str(len(OUT)))
    code, payload, _ = run_cfg(["--ref", "refs/remotes/origin/main"], repo, script)
    value = payload["config"].get("review.run_tests") if payload else None
    return code == 4 and payload is None, f"exit {code}, run_tests={value}"


ok, detail = cell_p11(SRC)
emit(ok, f"P11: --ref refs/remotes/origin/main with only a local refs/heads/refs/remotes/origin/main exits 4 ({detail})")
check_mutant(
    cell_p11,
    "P11-M: drop the exact for-each-ref check",
    SRC,
    "        if listed.returncode != 0 or names.count(ref) != 1:\n",
    "        if False:\n",
)
repo, _ = p11_repo("p11-block")
out, calls = run_block(RESOLUTION, repo, mode="nofetch")
emit(
    DEFAULTS_LINE in out and not hostile(out) and not reads_work_tree_config(calls),
    "P11: the shipped show-ref resolution fails closed to the defaults, never the hostile branch's values",
)
p11_block_mutant = RESOLUTION.replace(
    '&& git show-ref --verify --quiet "refs/remotes/origin/${base}"', "&& true", 1
)
emit(p11_block_mutant != RESOLUTION, "P11-M: the show-ref check is present to reverse-apply")
out, _ = run_block(p11_block_mutant, repo, mode="nofetch")
emit(
    DEFAULTS_LINE not in out and '"review.max_cycles": 99' in out,
    "P11-M: without the show-ref check the block resolves the local refs/heads/refs/remotes/origin/main and uses its values",
)

# ── P20: the comparison starts at the merge base ─────────────────────────────

repo = new_repo("p20")
commit_file(repo, ".idd.yml", "review:\n  max_cycles: 4\n  soft_pass: true\n", "base")
git(["checkout", "-q", "-b", "pr"], repo)
commit_file(repo, ".idd.yml", "review:\n  max_cycles: 5\n  soft_pass: true\n", "pr changes max_cycles")
p20_head = git(["rev-parse", "HEAD"], repo)
git(["checkout", "-q", "main"], repo)
commit_file(repo, ".idd.yml", "review:\n  max_cycles: 4\n  soft_pass: false\n", "main changes soft_pass")
p20_base = git(["rev-parse", "HEAD"], repo)
git(["checkout", "-q", "pr"], repo)
p20_mb = git(["merge-base", p20_base, p20_head], repo)
code, payload, _ = run_cfg(["--ref", p20_mb, "--compare-ref", p20_head], repo)
emit(
    code == 0 and payload["changed_keys"] == ["review.max_cycles"],
    f"P20: from the merge base only the PR's key is named (changed_keys={payload and payload.get('changed_keys')})",
)
code, payload, _ = run_cfg(["--ref", p20_base, "--compare-ref", p20_head], repo)
emit(
    code == 0 and payload["changed_keys"] == ["review.max_cycles", "review.soft_pass"],
    "P20: control — from the base tip the base branch's own change would be blamed on the PR",
)

MECH_PREPASS = os.path.join(BUILT_SKILL, "references", "prepass-tests-ci-mechanics.md")
COMPARE = fenced_block(MECH_PREPASS, "--compare-ref")
emit(COMPARE is not None, "P20: the built prepass-tests-ci-mechanics.md ships the fenced comparison block")
COMPARE = COMPARE or ""
prefix = f"base_oid={p20_base}\nhead_oid={p20_head}\n"


def cell_p20(block):
    out, _ = run_block(block, repo, prefix=prefix)
    match = re.search(r'"changed_keys": (\[[^\]]*\]|null)', out)
    keys = json.loads(match.group(1)) if match else "missing"
    return keys == ["review.max_cycles"] and ".idd.yml" in out, f"changed_keys={keys}"


ok, detail = cell_p20(COMPARE)
emit(ok, f"P20: the shipped comparison block names only the PR's key ({detail})")
p20_mutant = COMPARE.replace('--ref "$mb_oid" --compare-ref', '--ref "$base_oid" --compare-ref', 1)
emit(p20_mutant != COMPARE, "P20-M: the merge-base ref is present to reverse-apply")
ok, detail = cell_p20(p20_mutant)
emit(not ok, f"P20-M: comparing from the base tip blames the base branch's change on the PR ({detail})")
out, _ = run_block(COMPARE, repo, prefix="base_oid=deadbeef\nhead_oid=" + p20_head + "\n")
emit('"changed_keys"' not in out, "P20: a base_oid that fails is_oid runs no comparison")

# ── P22: under --ref the schema never comes from the work tree ───────────────


def cell_p22(script):
    repo, base_oid = pr_repo("p22-" + str(len(OUT)))
    hostile = open(SCHEMA, encoding="utf-8").read().replace("  max_cycles: 3\n", "  max_cycles: 42\n", 1)
    write(os.path.join(repo, "docs", "config-schema.md"), hostile)
    code, payload, _ = run_cfg(["--ref", base_oid], repo, script, schema=None)
    code_s, payload_s, _ = run_cfg(
        ["--ref", base_oid, "--key", "review.max_cycles"], repo, script,
        schema=os.path.join(repo, "docs", "config-schema.md"),
    )
    ok = code == 4 and payload is None and code_s == 0
    return ok, f"no --schema exit {code}; explicit --schema exit {code_s}"


ok, detail = cell_p22(SRC)
emit(ok, f"P22: src gi-config --ref beside a hostile docs/config-schema.md and no --schema exits 4; --schema is honoured ({detail})")
check_mutant(
    cell_p22,
    "P22-M: let --ref walk up from the working directory",
    SRC,
    "find_schema(args.schema, allow_walk=False)",
    "find_schema(args.schema, allow_walk=True)",
)

# ── Prose: P16, P17, P19, P21 (src and built) ────────────────────────────────


def section(text, heading_re, level):
    """Body from the heading matching `heading_re` to the next heading of `level` or higher."""
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if re.match(heading_re, l)), None)
    if start is None:
        return None
    end = len(lines)
    in_fence = False
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("```"):
            in_fence = not in_fence
        if not in_fence and re.match(r"^#{1,%d} " % level, lines[i]):
            end = i
            break
    return "\n".join(lines[start:end])


def read(rel):
    return open(os.path.join(ROOT, rel), encoding="utf-8").read()


PAIRS = {
    "skill": ("src/skills/issue-pr-review/SKILL.source.md", "skills/issue-pr-review/SKILL.md"),
    "loop": (
        "src/skills/issue-pr-review/references/review-loop-mechanics.md",
        "skills/issue-pr-review/references/review-loop-mechanics.md",
    ),
    "prepass": (
        "src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md",
        "skills/issue-pr-review/references/prepass-tests-ci-mechanics.md",
    ),
    "report": (
        "src/skills/issue-pr-review/references/report-templates.md",
        "skills/issue-pr-review/references/report-templates.md",
    ),
}

for side in (0, 1):
    label = "src" if side == 0 else "built"
    skill = read(PAIRS["skill"][side])
    step2 = section(skill, r"^## Step 2 ", 2) or ""
    paragraphs = step2.split("\n\n")
    pointer = next((i for i, p in enumerate(paragraphs) if "--compare-ref" in p), None)
    otherwise = next((i for i, p in enumerate(paragraphs) if "Otherwise:" in p), None)
    autofix = step2.find("### Commit auto-fixes")
    emit(
        pointer is not None and otherwise is not None and pointer < otherwise
        and "Otherwise:" not in paragraphs[pointer]
        and not re.match(r"^\s*\d+\.", paragraphs[pointer])
        and "--review-only" in paragraphs[pointer]
        and 0 <= step2.find("--compare-ref") < autofix,
        f"P16: ({label}) the Step 2 comparison pointer is its own paragraph before 'Otherwise:', outside the numbered list and *Commit auto-fixes*, and names --review-only",
    )
    prepass = read(PAIRS["prepass"][side])
    autofix_sec = section(prepass, r"^### Commit auto-fixes", 3) or ""
    compare_sec = section(prepass, r"^### Config-change comparison", 3) or ""
    emit(
        compare_sec and "--compare-ref" in compare_sec and "--compare-ref" not in autofix_sec
        and "--review-only" in compare_sec,
        f"P16: ({label}) the comparison lives outside the *Commit auto-fixes* section --review-only skips",
    )
    emit(
        "could not be compared" in compare_sec
        and 'git diff "$mb_oid" "$head_oid" -- .idd.yml .gitissue.yml' in compare_sec
        and "`base_oid` replaces `mb_oid`" in compare_sec,
        f"P17/P20: ({label}) the --compare-ref call is paired with the 'could not be compared' finding and the by-hand merge-base diff",
    )
    emit(
        "neither an unevaluated check nor a `PARTIAL` cause" in compare_sec
        and "never blocks the merge" in compare_sec,
        f"P21: ({label}) the comparison section says the finding never blocks and is not a PARTIAL cause",
    )

    config = section(skill, r"^## Configuration", 2) or ""
    calls = re.findall(r"gi-config\.py[^`\n]*", config)
    emit(
        bool(calls) and all(c.startswith('gi-config.py --ref "$base_oid"') for c in calls),
        f"P19: ({label}) every gi-config call in Configuration passes --ref \"$base_oid\" ({calls})",
    )
    emit(
        'git show "${base_oid}:.idd.yml"' in config and "read it yourself" not in config
        and "Never the working tree's file" in config,
        f"P19: ({label}) the by-hand fallback reads the base blob, never the working tree",
    )
    emit(
        "○ Review settings: origin/<base> @ <base_oid>" in config
        and "⚠ Review settings: built-in defaults (base branch unreadable)" in config
        and "--review-only" in config,
        f"P19: ({label}) Configuration prints where the settings came from, in every mode",
    )
    loop = read(PAIRS["loop"][side])
    emit(
        "from the working directory" not in (section(loop, r"^## Config keys", 2) or "x from the working directory")
        and 'gi-config.py --ref "$base_oid"' in loop,
        f"P19: ({label}) review-loop-mechanics.md no longer says gi-config reads .idd.yml from the working directory",
    )
    report = read(PAIRS["report"][side])
    emit(
        len(re.findall(r"Evidence: +settings origin/\{base\} @ \{base_sha7\}", report)) >= 2,
        f"P19: ({label}) the report templates' Evidence rows name where the settings came from",
    )
    partial = re.search(r"- `PARTIAL`(.*?)- `WARN", report, re.DOTALL)
    emit(
        "report-level finding, non-blocking" in report
        and "outside the soft-pass and strict note count" in report
        and partial is not None and "Config-change finding" in partial.group(1),
        f"P21: ({label}) the report template labels the finding non-blocking, outside the note count, and the PARTIAL bullet excludes it",
    )

# Every gi-config call anywhere in the skill reads the base, never the work tree.
loose = []
for base_dir in ("src/skills/issue-pr-review", "skills/issue-pr-review"):
    for dirpath, _, files in os.walk(os.path.join(ROOT, base_dir)):
        if "scripts" in dirpath.split(os.sep):
            continue
        for name in files:
            if not name.endswith(".md"):
                continue
            text = open(os.path.join(dirpath, name), encoding="utf-8").read()
            for call in re.findall(r"python3 [^\s`]*gi-config\.py[^`\n]*", text):
                if "--ref" not in call:
                    loose.append(f"{os.path.relpath(os.path.join(dirpath, name), ROOT)}: {call}")
emit(not loose, f"P19: no issue-pr-review file calls gi-config without --ref{' — ' + '; '.join(loose) if loose else ''}")

shutil.rmtree(SCRATCH, ignore_errors=True)
print("\n".join(OUT))
PY

while IFS='|' read -r verdict label; do
  [ -n "${verdict:-}" ] || continue
  if [ "$verdict" = "PASS" ]; then
    pass "$label"
  else
    fail "$label"
  fi
done < "$RESULTS"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ] || [ "$PASS" -eq 0 ]; then
  echo "  ✗ The PR under review can still set the gates that judge it"
  exit 1
fi
echo "  ✓ Review gates come from the default branch, and config changes are reported"
