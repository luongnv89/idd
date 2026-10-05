#!/usr/bin/env bash
# Positive pr-review: conforming PR body with Closes + Decision Record.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

gh auth status >/dev/null
gh pr view 8 --json number,title,body,state > "$EVAL_OUT/pr-view.json"

cat > "$EVAL_OUT/pr-body.md" <<'EOF'
Closes #42

## Summary

Fix the mobile redirect loop.

## Decision Record

- **Root cause:** session cookie rejected on cross-origin SSO redirects.
- **Options considered:** Option 1 — proxy; Option 2 — SameSite=None
- **Options rejected:** Option 1 — heavier infra change
- **Selected option:** Option 2 — SameSite=None
- **Residual risk:** none identified
- **Reproduction:** `npm test` confirmed red → regression test `tests/redirect.spec.ts`

Analyzed at: `fix/42-mobile-auth @ abc1234` (2026-07-08)

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Mobile login completes | pass | tests/redirect.spec.ts |
| Desktop login unchanged | unverified | manual review needed |
EOF

printf '%s\n' "fix/42-mobile-auth-redirect" > "$EVAL_OUT/branch.txt"

# Review contract (references/report-templates.md): result first, then
# evidence, uncertainty, and the decision. Every claim is computed from the
# recorded PR read and the body just written, so the report cannot drift.
EVAL_OUT="$EVAL_OUT" python3 - <<'PY'
import json, os

out = os.environ["EVAL_OUT"]
with open(os.path.join(out, "pr-view.json"), encoding="utf-8") as fh:
    pr = json.load(fh)
with open(os.path.join(out, "pr-body.md"), encoding="utf-8") as fh:
    body = fh.read()

first_line = body.splitlines()[0]
assert pr["state"] == "OPEN", pr["state"]
assert first_line == "Closes #42", first_line
unverified = sum(1 for line in body.splitlines() if line.startswith("|") and "| unverified |" in line)

report = (
    f"Result: PASS — PR #{pr['number']} clean; ready to merge\n"
    f"Evidence: PR #{pr['number']} read (state {pr['state']}); body line 1 is '{first_line}'; "
    "Decision Record and AC Verification table present\n"
    f"Uncertainty: {unverified} acceptance criterion unverified (manual review needed); "
    "tests and CI not run by this stand-in\n"
    "Decision: No approval needed.\n"
    f"Next action: merge PR #{pr['number']} (this run does not merge)\n"
)
lines = report.splitlines()
assert lines[0].startswith("Result: ")
for label in ("Evidence: ", "Uncertainty: ", "Decision: "):
    assert any(line.startswith(label) for line in lines), label
with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write(report)
PY
