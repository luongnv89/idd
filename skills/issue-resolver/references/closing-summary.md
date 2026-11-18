# Closing Summary — /issue-resolver

## Review contract

One block, printed once: after the tracker's last line or a stop's error
block. Every variant prints five rows, in this order:

1. `Result:` — the status and the main finding or stop reason. `DONE`: a PR
   was created and every step printed `Result: PASS`, or the issue was already
   resolved. `PARTIAL`: a PR was created but a step printed `Result: PARTIAL`.
   `BLOCKED`: the run stopped before a PR was created.
2. `Evidence:` — only checks that ran, each with its observed result; a resumed
   run adds `resumed from step {k}/5 (record {age} old)`.
3. `Uncertainty:` — what the run did not verify, else `none identified`.
   `risk_rating` is a judgment, not a measurement.
4. `Decision: No approval needed.` — every mode; the resolver never merges.
5. `Next action:` — the user's remaining step; under `/auto-pilot`,
   `none — auto-pilot reviews and merges`.

Rows are for humans; report-back fields and the run-log record keep their
shape. A wrapped row aligns under its value, within 80 characters.
