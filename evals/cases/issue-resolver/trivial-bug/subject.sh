#!/usr/bin/env bash
# Resolver stand-in: red→green fixture bug, conventional artifacts, run log.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_WORK:?EVAL_WORK is required}"

REPO="$EVAL_WORK/resolver-repo"
rm -rf "$REPO"
mkdir -p "$REPO/src/auth" "$REPO/tests"

# Deliberate bug: always returns False
cat > "$REPO/src/auth/login.py" <<'EOF'
"""Minimal auth module used by the hermetic resolver eval."""


def login(user: str, password: str) -> bool:
    # BUG: always rejects (eval fixture — fix in this subject).
    return False
EOF

# Pure-python unit test (no pytest) — exits 1 while bug present
cat > "$REPO/tests/test_login.py" <<'EOF'
#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from auth.login import login  # noqa: E402


def main() -> int:
    assert login("alice", "secret") is True, "matching credentials must succeed"
    assert login("alice", "wrong") is False, "mismatched credentials must fail"
    print("ok")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
EOF

# Make auth a package
printf '' > "$REPO/src/auth/__init__.py"

cd "$REPO"
git init -q -b main
git -c user.name=eval -c user.email=eval@harness.local config user.name eval
git config user.email eval@harness.local
git add src tests
git commit -qm "chore(init): scaffold login fixture (#1)"

# Confirm red
set +e
python3 tests/test_login.py >/dev/null 2>&1
RED_EXIT=$?
set -e
if [ "$RED_EXIT" -eq 0 ]; then
  echo "✗ expected failing test before fix" >&2
  exit 1
fi
echo "  ○ red confirmed (test exit $RED_EXIT)"

# Apply fix
cat > src/auth/login.py <<'EOF'
"""Minimal auth module used by the hermetic resolver eval."""


def login(user: str, password: str) -> bool:
    return user == "alice" and password == "secret"
EOF

set +e
python3 tests/test_login.py >/dev/null 2>&1
GREEN_EXIT=$?
set -e
if [ "$GREEN_EXIT" -ne 0 ]; then
  echo "✗ expected passing test after fix" >&2
  exit 1
fi
echo "  ○ green confirmed (test exit 0)"

printf 'red→green: test_login.py exit %s → 0\n' "$RED_EXIT" > "$EVAL_OUT/red-green.txt"

BRANCH="fix/1-login-always-false"
git checkout -qb "$BRANCH"
git add src/auth/login.py
COMMIT_MSG="fix(auth): return true when credentials match (#1)"
git commit -qm "$COMMIT_MSG"

printf '%s\n' "$BRANCH" > "$EVAL_OUT/branch.txt"
printf '%s\n' "$COMMIT_MSG" > "$EVAL_OUT/commit.txt"

# PR body matching report-templates (Closes, Decision Record, AC table, Reproduction)
cat > "$EVAL_OUT/pr-body.md" <<'EOF'
Closes #1

## Summary

Fix login() always returning False so matching credentials succeed.

## Decision Record

- **Root cause:** login() hardcoded `return False` and never compared credentials.
- **Options considered:** Option 1 — delete the function; Option 2 — compare user/password
- **Options rejected:** Option 1 — breaks the auth surface
- **Selected option:** Option 2 — compare credentials against expected values
- **Residual risk:** none identified for this fixture
- **Reproduction:** `python3 tests/test_login.py` confirmed red → green after the fix

Analyzed at: `fix/1-login-always-false @ HEAD` (2026-08-11)

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| login returns True for matching credentials | pass | tests/test_login.py red→green |
| login returns False for mismatched credentials | pass | tests/test_login.py |
EOF

# Skill-shaped gh calls under the shim
gh auth status >/dev/null
gh issue view 1 --json number,title,body,labels,assignees,state >/dev/null
gh pr create --title "$COMMIT_MSG" --body-file "$EVAL_OUT/pr-body.md" \
  > "$EVAL_OUT/pr-url.txt"

# Valid runs.jsonl record for issue-resolver success
cat > "$EVAL_OUT/run.json" <<'EOF'
{
  "ts": "2026-08-11T12:00:00Z",
  "issue": 1,
  "mode": "auto",
  "skill": "issue-resolver",
  "complexity": "low",
  "profile": "light",
  "qa_cycles": 1,
  "outcome": "success",
  "pr": 1,
  "duration_s": 12
}
EOF
