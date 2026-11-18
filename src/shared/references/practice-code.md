# Code quality practices

- **C1 Errors surface.** Catch only errors the handler acts on, and never default a required value that is missing or unparsable (`?? 0`, `or {}`). *Check:* no added catch or fallback hides a failure.
- **C2 Fix the cause.** Correct the code that produces the wrong value, not the place the symptom surfaces. *Check:* the diff changes where the bad value originates.
- **C3 Release on every path.** Close every file, connection, lock and task the diff opens, on error paths too. *Check:* each acquire has a release on its error path.
- **C4 Pinned-version idioms.** Use current idioms of the versions the repo pins: nothing newer, no shim, no deprecated call. *Check:* new APIs exist in the pinned versions.
- **C5 Keep typed code typed.** Add no `any`, `interface{}` or checker suppression (`@ts-ignore`, `# type: ignore`) outside a validated boundary. *Check:* grep added lines for those tokens.
- **C6 No redundant guards.** Validate untrusted input once, at the boundary; past it, guard nothing the type guarantees. *Check:* each new guard covers a real absence or failure.
- **C7 No test-only branches.** Production code gets no flag, branch or export that exists only for tests. *Check:* grep added non-test lines for test checks.
- **C8 Replace, don't fork.** Remove the path the diff supersedes (no `fooV2` beside `foo`) unless it is public API. *Check:* the old symbol has no definition or caller left.
- **C9 No speculative generality.** Add no layer, option, parameter or pass-through wrapper the issue does not need. *Check:* some caller uses each new option.
- **C10 Comments say why.** A new comment explains a non-obvious why; none restates code, logs history or disables code. *Check:* read each one.
- **C11 One definition per value.** Reuse the repo's constant or config key; name a new limit or timeout once. *Check:* grep the repo for each new literal.
