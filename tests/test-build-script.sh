#!/usr/bin/env bash
# test-build-script.sh — Validate scripts/build.sh produces expected outputs
# (issue #58, §9 of refactor-plan-v10.md; updated for #106).
#
# Asserts:
#   - All public skills (src/skills/<name>/) appear in root skills/<name>/
#   - Every shared source agent is emitted as a standalone Claude Code agent
#   - Internal skills (src/internal-skills/) and deprecated skills
#     (src/deprecated-skills/) without a distribute flag are excluded.
#   - Every shared script (src/shared/scripts/) ships into at least one skill,
#     byte-identically, executable, and runnable (issue #251).
#   - Every tests/*.sh is invoked by a GitHub Actions workflow, or is listed in
#     this file's EXCLUDED array with a written reason (T9, issue #275).
#
# T9 lives here, in an already-wired test, on purpose: a standalone
# tests/test-ci-wiring.sh would itself need wiring, which is the failure mode it
# exists to catch.
#
# Usage: bash tests/test-build-script.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
SRC_SKILLS="$REPO_ROOT/src/skills"
SRC_AGENTS="$REPO_ROOT/src/shared/agents"
SRC_SCRIPTS="$REPO_ROOT/src/shared/scripts"
ROOT_SKILLS="$REPO_ROOT/skills"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# Portable mode read: GNU `stat -c` and BSD `stat -f` disagree, python3 does not.
mode_of() {
  python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}

echo "◆ Build Script Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: build.sh exists and is executable
# ───────────────────────────────────────────────────────────
if [ -x "$BUILD_SH" ]; then
  pass "T1: scripts/build.sh exists and is executable"
else
  fail "T1: scripts/build.sh missing or not executable"
  echo "  Build aborted — cannot continue."
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: build runs cleanly into a temp out dir
# ───────────────────────────────────────────────────────────
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT
if "$BUILD_SH" --out "$TMP_OUT" >/dev/null 2>&1; then
  pass "T2: build.sh --out <tmp> exits 0"
else
  fail "T2: build.sh --out <tmp> failed"
  echo "  Build aborted — cannot continue."
  exit 1
fi

# Also build into the canonical dist/ for the rest of the tests
if "$BUILD_SH" >/dev/null 2>&1; then
  pass "T2.1: build.sh (default out=dist/) exits 0"
else
  fail "T2.1: build.sh failed against default out"
fi

quiet_log="$TMP_OUT/quiet.log"
if "$BUILD_SH" --out "$TMP_OUT/quiet-build" --quiet >"$quiet_log" 2>&1 \
   && [ ! -s "$quiet_log" ]; then
  pass "T2.2: quiet build succeeds without output"
else
  fail "T2.2: quiet build failed or emitted output"
fi

capture_sites="$(grep -c 'capture_logged' "$BUILD_SH" || true)"
if grep -q '^capture_logged() {' "$BUILD_SH" && [ "$capture_sites" -eq 3 ]; then
  pass "T2.3: quiet compile and verify share capture_logged"
else
  fail "T2.3: capture_logged is not the single quiet capture path"
fi

# ───────────────────────────────────────────────────────────
# T3: every public src skill is present in root skills/
# ───────────────────────────────────────────────────────────
for src_skill_dir in "$SRC_SKILLS"/*/; do
  name="$(basename "$src_skill_dir")"
  if [ -f "$ROOT_SKILLS/$name/SKILL.md" ]; then
    pass "T3: skills/$name/SKILL.md present"
  else
    fail "T3: skills/$name/SKILL.md missing"
  fi
done

# ───────────────────────────────────────────────────────────
# T5: every shared source agent is emitted as a standalone Claude Code agent
#      in the built dist/agents/ (agent outputs are gitignored, not committed)
# ───────────────────────────────────────────────────────────
TMP_AGENTS="$(mktemp -d)"
"$BUILD_SH" --out "$TMP_AGENTS" >/dev/null 2>&1
for src_agent in "$SRC_AGENTS"/*.md; do
  [ -f "$src_agent" ] || continue
  name="$(basename "$src_agent")"
  stem="${name%.md}"
  dist_agent="$TMP_AGENTS/agents/$name"
  if [ -f "$dist_agent" ] && \
     grep -q "^name: $stem$" "$dist_agent" && \
     grep -q '^description: ' "$dist_agent" && \
     grep -q 'Managed by IDD installer' "$dist_agent"; then
    pass "T5: dist/agents/$name generated with Claude Code frontmatter"
  else
    fail "T5: dist/agents/$name missing or malformed"
  fi
done
rm -rf "$TMP_AGENTS"

# ───────────────────────────────────────────────────────────
# T5b: every shared source agent is emitted for pi-subagents in .pi/agents/
# ───────────────────────────────────────────────────────────
PI_AGENTS="$REPO_ROOT/.pi/agents"
for src_agent in "$SRC_AGENTS"/*.md; do
  [ -f "$src_agent" ] || continue
  name="$(basename "$src_agent")"
  pi_agent="$PI_AGENTS/$name"
  if [ -f "$pi_agent" ] && \
     grep -q '^display_name: ' "$pi_agent" && \
     grep -q 'Managed by IDD installer (pi-subagents)' "$pi_agent" && \
     ! grep -q 'display_name:.*—' "$pi_agent" && \
     ! grep -q 'display_name:.*\\u2014' "$pi_agent"; then
    pass "T5b: .pi/agents/$name generated (role-only display_name)"
  else
    fail "T5b: .pi/agents/$name missing or still has persona display_name"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: internal-skills excluded from generated outputs
# ───────────────────────────────────────────────────────────
if [ -d "$REPO_ROOT/src/internal-skills" ]; then
  for internal_dir in "$REPO_ROOT/src/internal-skills"/*/; do
    [ -d "$internal_dir" ] || continue
    name="$(basename "$internal_dir")"
    if [ ! -d "$ROOT_SKILLS/$name" ]; then
      pass "T6: internal skill '$name' correctly excluded from generated outputs"
    else
      fail "T6: internal skill '$name' leaked into generated outputs"
    fi
  done
fi

# T6.1: local-only internal package and driver/wrapper boundaries (#434).
# All destructive/mutated builds use a copied checkout, never user installations.
if PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO_ROOT" <<'PY_INTERNAL'
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

repo = Path(sys.argv[1])

def run(root, *args, ok=True, env=None):
    result = subprocess.run(args, cwd=root, text=True, capture_output=True,
                            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1", **(env or {})})
    assert (result.returncode == 0) == ok, (
        f"command {args} exited {result.returncode}; expected {'success' if ok else 'rejection'}\n"
        + result.stdout + result.stderr)
    return result.stdout + result.stderr

def digest(root):
    return [(str(p.relative_to(root)), p.read_bytes(), p.stat().st_mode & 0o777)
            for p in sorted(root.rglob("*")) if p.is_file()]

internal = repo / "internal-skills"
assert (internal / "idd-doctor/SKILL.md").is_file(), "actual doctor artifact missing"
for name in (repo / "src/internal-skills").iterdir():
    if not (name / "SKILL.source.md").is_file():
        continue
    assert (internal / name.name / "SKILL.md").is_file()
    for path in (repo / "skills", repo / "dist"):
        assert not list(path.rglob(name.name)), f"internal package leaked into {path}"
assert not (internal / ".claude-plugin").exists(), "internal plugin manifest leaked"
run(repo, "bash", "scripts/verify_flattened_skills.sh", str(internal),
    "src/internal-skills", "internal")
for script in (internal / "idd-doctor/references/scripts").glob("*.py"):
    source = repo / "src/shared/scripts" / script.name
    assert script.read_bytes() == source.read_bytes(), "internal script bytes changed"
    assert script.stat().st_mode & 0o777 == source.stat().st_mode & 0o777, "internal script mode changed"
assert (internal / "idd-doctor/references/scripts/gi-runlog.py").is_file()
print("  ✓ T6.1: actual internal package complete, scripts byte/mode identical, no public/dist/plugin leak")

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / "checkout"
    root.mkdir()
    for directory in ("src", "docs", "scripts"):
        shutil.copytree(repo / directory, root / directory,
                        ignore=shutil.ignore_patterns("__pycache__"))
    # An internal-only fixture exercises all three existing closure kinds.
    (root / "src/internal-skills/metadata").mkdir()
    specimen = root / "src/internal-skills/specimen"
    specimen.mkdir()
    (specimen / "SKILL.source.md").write_text(
        "---\nname: specimen\n---\n# Specimen\n"
        "shared/agents/codebase-researcher.md\n"
        "docs/config-schema.md\nshared/scripts/gi-config.py\n")
    driver = str(root / "scripts/build.py")
    wrapper = str(root / "scripts/build.sh")
    dest = root / "internal-skills"
    out = root / "dist"
    run(root, "python3", driver)  # safe canonical default
    assert (dest / "idd-doctor/SKILL.md").is_file(), "driver canonical default missing"
    assert not (dest / "metadata").exists(), "ordinary internal directory emitted as a skill"
    for bundled in ("agents/codebase-researcher.md", "docs/config-schema.md", "scripts/gi-config.py"):
        assert (dest / "specimen/references" / bundled).is_file(), f"internal closure lost {bundled}"
    # Sentinels prove no canonical promotion happened, even if bytes regenerate identically.
    sentinels = (root / "skills/.isolation-sentinel", dest / ".isolation-sentinel")
    for sentinel in sentinels:
        sentinel.write_text("leave canonical tree untouched")
    before = (digest(root / "skills"), digest(dest))
    run(root, "python3", driver, "--out", str(root / "custom"), "--no-root-skills")
    assert before == (digest(root / "skills"), digest(dest)), "custom driver changed canonical trees"
    run(root, "python3", driver, "--no-root-skills")
    assert before == (digest(root / "skills"), digest(dest)), "no-root driver changed canonical trees"
    for args in (("--out", str(root / "custom")), ("--no-promote-skills",)):
        run(root, "bash", wrapper, *args)
        assert before == (digest(root / "skills"), digest(dest)), "wrapper isolation failed"
    for args in (("--internal-out", str(dest)), (f"--internal-out={dest}",),
                 ("--internal-o", str(dest))):
        run(root, "bash", wrapper, "--out", str(root / "custom"), *args, ok=False)
        assert before == (digest(root / "skills"), digest(dest)), "wrapper option overrode staging"
    print("  ✓ T6.2: canonical driver default, custom/no-root/no-promote isolation, wrapper override rejected")

    # Reject equality, ancestor, descendant, and symlink alias before cleanup.
    alias = root / "alias"
    alias.symlink_to(root / "src", target_is_directory=True)
    for unsafe in (root, root / "src", root / "src/nested", root / "skills",
                   root / "skills/nested", out, out / "nested", alias / "nested",
                   root / "custom", root / "scripts", root / "docs", root / "tests",
                   root / ".git"):
        log = run(root, "python3", driver, "--out", str(root / "custom"),
                  "--no-root-skills", "--internal-out", str(unsafe), ok=False)
        assert "unsafe internal output" in log, log
        assert before == (digest(root / "skills"), digest(dest))
    print("  ✓ T6.3: unsafe overlaps (including symlinks) rejected before destructive cleanup")

    for sentinel in sentinels:
        sentinel.unlink()
    before = (digest(root / "skills"), digest(dest))
    separate = Path(tmp) / "inspection"
    run(root, "python3", driver, "--out", str(root / "custom"),
        "--no-root-skills", "--internal-out", str(separate))
    assert (separate / "idd-doctor/SKILL.md").is_file(), "explicit driver output missing"
    (separate / "obsolete/references").mkdir(parents=True)
    (separate / "idd-doctor/references/stale.md").write_text("stale")
    run(root, "python3", driver, "--out", str(root / "custom"),
        "--no-root-skills", "--internal-out", str(separate))
    assert not (separate / "obsolete").exists(), "obsolete internal skill survived cleanup"
    assert not (separate / "idd-doctor/references/stale.md").exists(), "stale internal reference survived cleanup"
    assert digest(dest) == digest(separate), "internal output nondeterministic"
    print("  ✓ T6.4: retained explicit output, stale cleanup and internal bytes/modes deterministic")

    # Corrupt emission *after* driver scans to exercise wrapper verification.
    pipeline = root / "scripts/build/pipeline.py"
    original = pipeline.read_text()
    for relative, expected in (("SKILL.md", "missing internal skill output"),
                               ("references/run-stats.md", "missing referenced")):
        pipeline.write_text(original.replace(
            "    _scan_dist_skills(destination)",
            "    _scan_dist_skills(destination)\n"
            f"    (destination / 'idd-doctor/{relative}').unlink()"))
        log = run(root, "bash", wrapper, "--quiet", ok=False)
        assert expected in log, log
        assert before == (digest(root / "skills"), digest(dest)), "verification failure promoted a canonical tree"
    pipeline.write_text(original)
    run(root, "bash", wrapper, "--quiet")
    print("  ✓ T6.5: missing emitted SKILL/ref fails verification, BOTH canonical trees protected")

    # Fail only the selected canonical promotion command, not compilation or cleanup.
    shim_dir = Path(tmp) / "promotion-shims"
    shim_dir.mkdir()
    for command, target, quiet in (("cp", dest, False), ("rm", dest, False),
                                   ("cp", root / "skills", False),
                                   ("rm", root / "skills", False), ("cp", dest, True)):
        real_command = shutil.which(command)
        assert real_command, f"{command} unavailable for promotion fixture"
        shim = shim_dir / command
        shim.write_text(
            "#!/usr/bin/env bash\n"
            'for arg in "$@"; do last="$arg"; done\n'
            f'if [[ "$last" == {shlex.quote(str(target))} ]]; then\n'
            f"  echo 'injected {command} promotion failure' >&2\n"
            "  exit 73\nfi\n"
            f'exec {shlex.quote(real_command)} "$@"\n')
        shim.chmod(0o755)
        before_target = digest(target)
        log = run(root, "bash", wrapper, *(("--quiet",) if quiet else ()), ok=False,
                  env={"PATH": str(shim_dir) + os.pathsep + os.environ["PATH"]})
        operation = "copy" if command == "cp" else "remove"
        assert f"promote failed: cannot {operation}" in log, log
        assert str(target) in log and "exit 73" in log, log
        assert f"injected {command} promotion failure" in log, log
        assert "\n✓ internal skills:" not in log and "build finished" not in log, log
        assert "skills/ updated" not in log, log
        if command == "rm":
            assert before_target == digest(target), "failed removal continued to copy"
        shim.unlink()
        run(root, "bash", wrapper, "--quiet")
    print("  ✓ T6.8: public/internal cp/rm promotion failures reject success, including quiet internal cp")

    # Metadata dirs must not become required skills; missing internal root is valid.
    (root / "src/skills/ordinary").mkdir()
    shutil.rmtree(root / "src/internal-skills")
    run(root, "python3", driver, "--no-root-skills", "--internal-out", str(separate))
    assert list(separate.iterdir()) == [], "obsolete internal package survived missing inventory"
    run(root, "bash", wrapper, "--out", str(root / "custom"), "--quiet")
    print("  ✓ T6.6: missing internal inventory builds empty; ordinary source dirs ignored")

    shutil.copytree(root / "src", root / "alternate-src")
    shutil.rmtree(root / "alternate-src/skills/issue-analysis")
    alternate = root / "alternate-src/skills/probe"
    alternate.mkdir(parents=True)
    (alternate / "SKILL.source.md").write_text("---\nname: probe\n---\n# Probe\n")
    run(root, "bash", wrapper, "--src", str(root / "alternate-src"),
        "--out", str(root / "alternate-out"), "--quiet")
    assert (root / "alternate-out/skills/probe/SKILL.md").is_file()
    print("  ✓ T6.7: wrapper verification resolves the selected --src inventory")
PY_INTERNAL
then
  pass "T6: internal emission and safety boundaries"
else
  fail "T6: internal emission or safety boundary regression"
fi

# ───────────────────────────────────────────────────────────
# T7: deprecated-skills without distribute flag excluded
# ───────────────────────────────────────────────────────────
if [ -d "$REPO_ROOT/src/deprecated-skills" ]; then
  for dep_dir in "$REPO_ROOT/src/deprecated-skills"/*/; do
    [ -d "$dep_dir" ] || continue
    name="$(basename "$dep_dir")"
    skill_md="$dep_dir/SKILL.md"
    distribute_flag=""
    if [ -f "$skill_md" ]; then
      # Look for "distribute:" in YAML frontmatter (first 30 lines).
      distribute_flag="$(head -30 "$skill_md" | grep -E '^distribute:' || true)"
    fi
    if [ -z "$distribute_flag" ]; then
      if [ ! -d "$ROOT_SKILLS/$name" ]; then
        pass "T7: deprecated skill '$name' (no distribute flag) excluded"
      else
        fail "T7: deprecated skill '$name' leaked into generated outputs without distribute flag"
      fi
    fi
  done
fi

# ───────────────────────────────────────────────────────────
# T8: every shared script ships into at least one skill, unchanged and runnable
# (issue #251). The build copies these with copy2 rather than copyfile — a
# regression to copyfile drops the mode to a umask-dependent 0644 and the
# shipped script silently stops being executable.
# ───────────────────────────────────────────────────────────
script_count=0
for src_script in "$SRC_SCRIPTS"/*.py; do
  [ -f "$src_script" ] || continue
  script_count=$((script_count + 1))
  name="$(basename "$src_script")"

  copies=0
  while IFS= read -r shipped; do
    copies=$((copies + 1))
    rel="${shipped#"$REPO_ROOT/"}"
    if cmp -s "$src_script" "$shipped"; then
      pass "T8: $rel is byte-identical to src/shared/scripts/$name"
    else
      fail "T8: $rel differs from src/shared/scripts/$name"
    fi
    # Never assert an absolute mode here: git records only the exec bit, so a
    # fresh checkout materialises a 100755 blob as 0777 & ~umask — 0o775 under
    # the common umask 002, 0o755 under 022. Compare the shipped copy to its
    # source instead; that is what catches a copy2 → copyfile regression, and it
    # holds under every umask.
    shipped_mode="$(mode_of "$shipped")"
    src_mode="$(mode_of "$src_script")"
    if [ "$shipped_mode" = "$src_mode" ]; then
      pass "T8: $rel has the source's mode ($shipped_mode)"
    else
      fail "T8: $rel is mode $shipped_mode, source is $src_mode"
    fi
    if [ -x "$shipped" ]; then
      pass "T8: $rel is executable"
    else
      fail "T8: $rel is not executable"
    fi
    set +e
    python3 "$shipped" --help >/dev/null 2>&1
    help_rc=$?
    set -e
    if [ "$help_rc" -eq 0 ]; then
      pass "T8: $rel --help exits 0"
    else
      fail "T8: $rel --help exited $help_rc"
    fi
  done < <(find "$ROOT_SKILLS" -type f -path '*/references/scripts/*' -name "$name" | sort)

  if [ "$copies" -gt 0 ]; then
    pass "T8: src/shared/scripts/$name ships into $copies skill(s)"
  else
    fail "T8: src/shared/scripts/$name ships into no skill — nothing cites it"
  fi
done

if [ "$script_count" -gt 0 ]; then
  pass "T8: src/shared/scripts/ holds $script_count script(s) to verify"
else
  fail "T8: src/shared/scripts/ is empty — T8 would pass vacuously"
fi

# ───────────────────────────────────────────────────────────
# T9: every tests/*.sh is invoked by a workflow (issue #275)
#
# A test nobody runs is not a test. Issue #275 found 20 of 42 test files that no
# workflow ever invoked — including the pre-commit security lint. Nothing
# asserted the wiring, so the gap grew silently, one unwired file at a time.
#
# To add a test: create tests/test-<name>.sh and add a named step for it in
# .github/workflows/dist-check.yml — before the build if it reads only src/ and
# docs/, after the build if it reads dist/ or skills/.
#
# To deliberately keep a test out of CI: add it to EXCLUDED below WITH a reason.
# The reason is the whole point of the array — an exclusion nobody can justify
# is indistinguishable from the rot this check exists to prevent.
#
# "Wired" is decided against a reduced view of the workflows, not their raw
# text. Two reductions, each closing a way a test can look wired while running
# nothing:
#
#   1. Comments are stripped — quote-aware, so an unquoted `#` at line start or
#      after whitespace opens a comment and a quoted one does not. A raw-text
#      grep counted a comment as wiring — including this check's own explanatory
#      note in dist-check.yml, which named tests/test-build-script.sh and so
#      kept T9 green even with the test-build-script step deleted: the guard
#      could not detect its own unwiring. Generalised, any test could be retired
#      behind a leftover `# TODO: wire bash tests/test-X.sh`.
#   2. Steps carrying `if: false` or `continue-on-error: true` (any case) are
#      dropped whole. A step that cannot run, or whose failure cannot fail the
#      job, is not a gate: marking a flaky test `continue-on-error: true` stops
#      it gating PRs, and nothing should still call it wired. A step ends at the
#      next `- ` line indented no deeper than its own, so bullets inside a
#      `run:` body or a `with:` sequence cannot split it away from its marker.
#
# Deliberately NOT covered, because closing them needs real YAML semantics:
# job-level `if:`/`continue-on-error:`, an expression that is falsy without
# being the literal `false`, and a reference inside a non-invoking command
# (`run: echo "see tests/test-X.sh"`). PyYAML is not in the stdlib and
# actions/setup-python does not install it, so a yaml.safe_load check would
# silently no-op on the very runner it has to bite on.
# ───────────────────────────────────────────────────────────
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"

# Format: "<repo-relative path>|<reason>". Empty today — every test runs in CI.
EXCLUDED=(
  # "tests/test-example.sh|needs a live GitHub token; run locally with GH_TOKEN set"
)

excluded_reason() {
  local want="$1" entry
  if [ "${#EXCLUDED[@]}" -eq 0 ]; then
    return 1
  fi
  for entry in "${EXCLUDED[@]}"; do
    # An entry with no `|` carries no reason, and must not excuse anything.
    # `${entry#*|}` returns the subject unchanged when there is no separator,
    # so a bare "tests/test-x.sh" would hand back the *path* as its own reason —
    # non-empty, so the caller's `[ -n "$reason" ]` accepts it and the file is
    # reported excluded with a self-referential justification. Skipping the
    # entry here is what makes the written reason mandatory rather than
    # advisory; the format itself is reported by the EXCLUDED audit below.
    case "$entry" in
      *"|"*) ;;
      *) continue ;;
    esac
    if [ "${entry%%|*}" = "$want" ]; then
      printf '%s' "${entry#*|}"
      return 0
    fi
  done
  return 1
}

# Repo-relative paths, not basenames: `git ls-files 'tests/*.sh'` matches
# tests/unit/test-x.sh too (git's `*` crosses `/`), and a basename comparison
# would report a correctly-wired nested test as unwired.
TEST_FILES=()
while IFS= read -r tracked; do
  TEST_FILES+=("$tracked")
done < <(cd "$REPO_ROOT" && git ls-files 'tests/*.sh')

# Inventory every workflow for diagnostics. Only pull-request-triggered workflows
# count as wiring: a test moved to a push-only or workflow_dispatch-only file no
# longer gates a PR, which is the gap this check exists to prevent.
WORKFLOW_FILES=()
if [ -d "$WORKFLOW_DIR" ]; then
  while IFS= read -r wf; do
    WORKFLOW_FILES+=("$wf")
  done < <(find "$WORKFLOW_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
fi

# Drop every step block that cannot gate. A step begins at a `- ` line whose
# indent is no deeper than the current step's; a `- ` line indented *further* is
# step content — a bullet inside a `run:` heredoc, or a YAML sequence under
# `with:` — and must not split the step.
#
# Splitting on a `- ` at *any* indent, as this did before, is not a conservative
# approximation. flush() resets `disabled`, so the remainder of a mis-split step
# becomes a NEW, UNDISABLED block: a step marked `continue-on-error: true` whose
# `run:` body contained a bullet line survived the reduction intact, and T9
# reported a disabled test as wired — precisely the failure this reduction
# exists to catch. The invariant is not "mis-splitting only shrinks a block"; it
# is the one enforced below, that a disabling marker stays attributed to every
# line of the step it disables.
strip_dead_steps() {
  awk '
    # Characters discarded before reading an `if:` value. Both YAML quote forms
    # belong here: the bare, double-quoted and single-quoted spellings of false
    # are the same dead step to GitHub, and stripping only the double quote left
    # the single-quoted one counted as live. The single quote is built with
    # sprintf rather than written, because this program is itself single-quoted.
    BEGIN { sq = sprintf("%c", 39); if_strip_re = "[[:space:]\"" sq "]" }
    function flush(   i) {
      if (n > 0 && disabled == 0) for (i = 1; i <= n; i++) print buf[i]
      n = 0; disabled = 0
    }
    /^[[:space:]]*-[[:space:]]/ {
      match($0, /^[[:space:]]*/)
      if (in_step == 0 || RLENGTH <= step_indent) {
        flush()
        in_step = 1
        step_indent = RLENGTH
      }
    }
    {
      buf[++n] = $0
      # tolower() first: a case-sensitive literal let `continue-on-error: TRUE`
      # through. Lowercasing the key too can only over-strip (a key GitHub would
      # not honour), and over-stripping loses wiring loudly; under-stripping
      # silently restores the hole.
      if (tolower($0) ~ /^[[:space:]]*continue-on-error:[[:space:]]*[^[:alnum:]]?true[^[:alnum:]]*$/) disabled = 1
      if ($0 ~ /^[[:space:]]*if:/) {
        v = $0
        sub(/^[[:space:]]*if:[[:space:]]*/, "", v)
        gsub(if_strip_re, "", v)
        sub(/^\$\{\{/, "", v)
        sub(/\}\}$/, "", v)
        if (tolower(v) == "false") disabled = 1
      }
    }
    END { flush() }
  '
}

# Strip comments without touching quoted text. A `#` opens a comment only when
# it is unquoted AND at line start or preceded by whitespace — the same rule in
# YAML and in the shell of a `run:` body, which is why one pass covers both.
#
# The quoting half is not optional. `sed -E 's/(^|[[:space:]])#.*$//'` applied
# YAML's *plain-scalar* rule to every line, including block scalars where `#` is
# literal, and deleted the rest of valid input:
#
#   run: |
#     echo "gate for issue #275" && bash tests/test-pre-commit-security.sh
#
# lost its invocation, so T9 failed a correctly-wired repo — and neither reason
# in the failure hint ("a comment", "a disabled step") applied, leaving the
# author no path to the cause. Note this still strips a *shell* comment inside a
# `run:` body (`# TODO: wire bash tests/test-x.sh`), which is right: a commented
# command invokes nothing either way.
#
# Two corrections to the naive character scan, each for an input that a
# quote-aware pass gets wrong in the *opposite* direction to the sed rule:
#
#   1. Inside a double-quoted run, a backslash escapes the next character. Both
#      YAML double-quoted scalars and the shell of a `run:` body work that way,
#      so `\"` continues the run rather than ending it. Reading it as a closing
#      quote leaves the scanner unquoted for the rest of the line, where the
#      next ` #` truncates — deleting the invocation behind it. Single quotes
#      have no backslash escape in either language, so this applies to double
#      quotes only.
#   2. A line that reaches its end still inside a quote usually never held a
#      quoted run at all — the common cause is an apostrophe in a YAML plain
#      scalar, as in `- name: Verify the build's drift gate  # ...`, which reads
#      here as an opening quote and hides everything after it, comment
#      included. Such a line is re-cut by the quoting-blind rule, which is what
#      the sed rule applied to every line and got right on this one. The cost is
#      a genuinely multi-line quoted scalar carrying a ` #`, which this
#      over-strips; no workflow in this repo has one.
strip_comments() {
  awk '
    BEGIN { sq = sprintf("%c", 39) }
    # Index of the `#` that opens a comment when quoting is ignored, or 0.
    function naive_cut(line,   i, n, c) {
      n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[[:space:]]/)) return i
      }
      return 0
    }
    {
      line = $0
      inq = ""
      cut = 0
      n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1)
        if (inq != "") {
          if (inq == "\"" && c == "\\") { i++; continue }
          if (c == inq) inq = ""
          continue
        }
        if (c == "\"" || c == sq) { inq = c; continue }
        if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[[:space:]]/)) {
          cut = i
          break
        }
      }
      if (inq != "") cut = naive_cut(line)
      # cut-2, not cut-1: consume the separating space too, so the reduced text
      # is byte-identical to the sed rule this replaced on every input the sed
      # rule handled correctly. A `#` in column 1 yields the empty string.
      out = (cut > 0) ? substr(line, 1, cut - 2) : line
      print out
    }
  '
}

# Return success only when the workflow top-level `on` declaration includes
# pull_request. Block children are matched at the first indentation level only,
# so nested input keys or sequences under workflow_call do not qualify. Scalar,
# flow-list, block-map, and simple block-sequence forms are supported without
# PyYAML; unsupported or malformed list forms are rejected conservatively.
workflow_gates_pull_requests() {
  strip_comments < "$1" | awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    # Deliberately support only the simple event-name subset of YAML flow
    # sequences. Requiring both brackets, non-empty comma-separated items, and
    # plain event names makes malformed scalar/list input fail closed.
    function scalar_or_flow_has_pr(value,   inner, count, i, item, has_pr, items) {
      value = trim(value)
      if (value == "pull_request") return 1
      if (substr(value, 1, 1) != "[" || substr(value, length(value), 1) != "]") return 0
      inner = substr(value, 2, length(value) - 2)
      if (trim(inner) == "") return 0
      count = split(inner, items, ",")
      for (i = 1; i <= count; i++) {
        item = trim(items[i])
        if (item == "" || item !~ /^[A-Za-z0-9_-]+$/) return 0
        if (item == "pull_request") has_pr = 1
      }
      return has_pr
    }
    /^[^[:space:]][^:]*:/ {
      if ($0 ~ /^on[[:space:]]*:/) {
        # Duplicate top-level keys are invalid YAML for this detector. In
        # particular, do not let a first pull_request declaration leave `found`
        # sticky when a later `on` declaration replaces it in some parsers.
        if (seen_on) invalid = 1
        seen_on = 1
        event_indent = -1
        block_style = ""
        value = $0
        sub(/^on[[:space:]]*:[[:space:]]*/, "", value)
        value = trim(value)
        if (scalar_or_flow_has_pr(value)) found = 1
        # Only an empty declaration can own indented block children. Treating
        # children of a scalar or flow value as events would accept bad YAML.
        in_on = (value == "")
      } else {
        in_on = 0
      }
      next
    }
    in_on && /^[[:space:]]+[^[:space:]]/ {
      match($0, /^[[:space:]]*/)
      indent = RLENGTH
      if (event_indent < 0) event_indent = indent
      if (indent < event_indent) {
        invalid = 1
        next
      }
      # A simple event sequence contains scalar items, so deeper indentation
      # cannot be valid continuation data. A map event may own nested config
      # only when its direct value was empty; `{}` is already a complete value.
      if (indent > event_indent) {
        if (block_style == "sequence" || !event_allows_nested) invalid = 1
        next
      }
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (line ~ /^-[[:space:]]+/) {
        if (block_style == "map") invalid = 1
        block_style = "sequence"
        event_allows_nested = 0
        item = line
        sub(/^-[[:space:]]+/, "", item)
        item = trim(item)
        if (item !~ /^[A-Za-z0-9_-]+$/) {
          invalid = 1
        } else if (item == "pull_request") {
          found = 1
        }
      } else if (line ~ /^[A-Za-z0-9_-]+[[:space:]]*:/) {
        if (block_style == "sequence") invalid = 1
        block_style = "map"
        key = line
        sub(/[[:space:]]*:.*$/, "", key)
        value = line
        sub(/^[^:]*:[[:space:]]*/, "", value)
        value = trim(value)
        # GitHub event-map entries are null or mappings. Support the common
        # empty/nested form and an empty flow map; reject every other direct
        # value rather than treating malformed YAML as a PR gate.
        if (value != "" && value !~ /^\{[[:space:]]*\}$/) invalid = 1
        if (seen_event[key]) invalid = 1
        seen_event[key] = 1
        event_allows_nested = (value == "")
        if (key == "pull_request") found = 1
      } else {
        invalid = 1
      }
    }
    END { exit(found && !invalid ? 0 : 1) }
  '
}

# Pin the trigger detector so neither manual-only wiring, malformed YAML, nor a
# nested input name/sequence can become a second, non-PR source of truth.
trigger_fixtures="$TMP_OUT/workflow-trigger-fixtures"
mkdir -p "$trigger_fixtures"
printf '%s\n' 'name: manual' 'on: workflow_dispatch' > "$trigger_fixtures/manual.yml"
printf '%s\n' 'name: scalar' 'on: pull_request' > "$trigger_fixtures/scalar.yml"
printf '%s\n' 'name: flow' 'on: [push, pull_request]' > "$trigger_fixtures/flow.yml"
printf '%s\n' 'name: block' 'on:' '  push:' '  pull_request:' > "$trigger_fixtures/block.yml"
printf '%s\n' 'name: block sequence' 'on:' '  - push' '  - pull_request' > "$trigger_fixtures/block-sequence.yml"
printf '%s\n' 'name: empty event' 'on:' '  pull_request:' > "$trigger_fixtures/empty-event.yml"
printf '%s\n' 'name: empty event map' 'on:' '  pull_request: {}' > "$trigger_fixtures/empty-event-map.yml"
printf '%s\n' 'name: nested event map' 'on:' '  pull_request:' \
  '    branches: [main]' > "$trigger_fixtures/nested-event-map.yml"
printf '%s\n' 'name: malformed scalar' 'on: pull_request, push' > "$trigger_fixtures/malformed-scalar.yml"
printf '%s\n' 'name: duplicate trigger' 'on: pull_request' 'on: push' > "$trigger_fixtures/duplicate-on.yml"
printf '%s\n' 'name: malformed event value' 'on:' \
  '  pull_request: [' > "$trigger_fixtures/malformed-event-value.yml"
printf '%s\n' 'name: duplicate event key' 'on:' '  pull_request:' \
  '  pull_request: {}' > "$trigger_fixtures/duplicate-event-key.yml"
printf '%s\n' 'name: malformed flow' 'on: [push, pull_request' > "$trigger_fixtures/malformed-flow.yml"
printf '%s\n' 'name: malformed block sequence' 'on:' '  - push' \
  '  - [pull_request' > "$trigger_fixtures/malformed-block-sequence.yml"
printf '%s\n' 'name: nested' 'on:' '  workflow_call:' '    inputs:' \
  '      pull_request:' '        type: boolean' > "$trigger_fixtures/nested.yml"
printf '%s\n' 'name: nested sequence' 'on:' '  workflow_call:' '    inputs:' \
  '      events:' '        default:' '          - push' \
  '          - pull_request' > "$trigger_fixtures/nested-sequence.yml"
if ! workflow_gates_pull_requests "$trigger_fixtures/manual.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/malformed-scalar.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/duplicate-on.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/malformed-event-value.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/duplicate-event-key.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/malformed-flow.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/malformed-block-sequence.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/nested.yml" && \
   ! workflow_gates_pull_requests "$trigger_fixtures/nested-sequence.yml" && \
   workflow_gates_pull_requests "$trigger_fixtures/scalar.yml" && \
   workflow_gates_pull_requests "$trigger_fixtures/flow.yml" && \
   workflow_gates_pull_requests "$trigger_fixtures/block.yml" && \
   workflow_gates_pull_requests "$trigger_fixtures/block-sequence.yml" && \
   workflow_gates_pull_requests "$trigger_fixtures/empty-event.yml" && \
   workflow_gates_pull_requests "$trigger_fixtures/empty-event-map.yml" && \
   workflow_gates_pull_requests "$trigger_fixtures/nested-event-map.yml"; then
  pass "T9: only valid direct pull_request triggers qualify as CI wiring"
else
  fail "T9: workflow trigger detector accepted invalid/non-PR wiring or rejected pull_request"
fi

WIRING_TEXT=""
if [ "${#WORKFLOW_FILES[@]}" -gt 0 ]; then
  for wf in "${WORKFLOW_FILES[@]}"; do
    if workflow_gates_pull_requests "$wf"; then
      WIRING_TEXT+="$(strip_comments < "$wf" | strip_dead_steps)"$'\n'
    fi
  done
fi

# Is $1 (a repo-relative path) referenced by a live step? Compared as a whole
# path so tests/unit/x.sh and `tests/test zz space.sh` work, with boundaries so
# tests/test-x.sh is not matched by xtests/test-x.sh or tests/test-x.shell.
path_wired() {
  local rel="$1" esc
  esc="$(printf '%s' "$rel" | sed -E 's/[][\.^$*+?(){}|]/\\&/g')"
  printf '%s\n' "$WIRING_TEXT" | grep -qE "(^|[^A-Za-z0-9._-])${esc}([^A-Za-z0-9._-]|$)"
}

# For the stat line and the all-or-nothing vacuity guard only; per-file
# decisions go through path_wired.
WIRED="$(printf '%s\n' "$WIRING_TEXT" | grep -oE 'tests/[A-Za-z0-9._/-]+\.sh' | LC_ALL=C sort -u || true)"

if [ "${#TEST_FILES[@]}" -eq 0 ]; then
  fail "T9: git tracks no tests/*.sh — the wiring check would be vacuous"
elif [ -z "$WIRED" ]; then
  fail "T9: no pull_request workflow under .github/workflows/ invokes any tests/*.sh"
else
  wired_count="$(printf '%s\n' "$WIRED" | wc -l | tr -d ' ')"
  pass "T9.0: checking ${#TEST_FILES[@]} tracked test(s) against $wired_count workflow reference(s)"

  unwired=0
  for rel in "${TEST_FILES[@]}"; do
    if path_wired "$rel"; then
      continue
    fi
    if reason="$(excluded_reason "$rel")" && [ -n "$reason" ]; then
      pass "T9: $rel excluded from CI — $reason"
    else
      unwired=$((unwired + 1))
      fail "T9: $rel is not invoked by any live pull-request workflow step and has no EXCLUDED reason"
      # Distinguish "never wired" from "wired, but the reduction removed it".
      # Without this the two are indistinguishable in the output, and an author
      # staring at a step they can see in the file has nothing to go on.
      raw_hits="$(grep -n -F -- "$rel" "${WORKFLOW_FILES[@]}" 2>/dev/null || true)"
      if [ -n "$raw_hits" ]; then
        echo "        A workflow does name it — but not from a live step, so the"
        echo "        reduction below dropped it. Raw occurrence(s):"
        printf '%s\n' "$raw_hits" | sed 's/^/          /'
      fi
    fi
  done

  if [ "$unwired" -eq 0 ]; then
    pass "T9: every tests/*.sh is invoked by a workflow or excluded with a reason"
  else
    echo "      Add a step to .github/workflows/dist-check.yml, or add the file"
    echo "      to EXCLUDED in tests/test-build-script.sh with a written reason."
    echo "      A mention in a comment, a non-pull-request workflow, or a step"
    echo "      disabled by 'if: false' / 'continue-on-error: true' does not count."
  fi

  # Every EXCLUDED entry is audited on two counts. A stale exclusion outlives
  # the test it names and would silently excuse a future file that reuses the
  # name. An entry with no `|`, or with nothing after it, excuses a file
  # without saying why — excluded_reason() already refuses to honour it, and
  # this is where the author is told what is wrong with it.
  if [ "${#EXCLUDED[@]}" -gt 0 ]; then
    for entry in "${EXCLUDED[@]}"; do
      name="${entry%%|*}"
      if [ -f "$REPO_ROOT/$name" ]; then
        pass "T9: EXCLUDED entry '$name' names an existing test"
      else
        fail "T9: EXCLUDED entry '$name' names no such file — stale exclusion"
      fi
      case "$entry" in
        *"|"?*)
          pass "T9: EXCLUDED entry '$name' carries a written reason"
          ;;
        *)
          fail "T9: EXCLUDED entry '$name' has no written reason"
          echo "      Write it as '<repo-relative path>|<reason>'. Without the"
          echo "      reason the entry is ignored and the file counts as unwired."
          ;;
      esac
    done
  fi
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Build script tests failed"
  exit 1
fi

echo "  ✓ Build script tests pass"
exit 0
