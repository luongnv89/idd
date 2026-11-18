# Security practices

- **S1 Authorize per resource.** Each new entry point checks server-side that the caller may act on that resource; signed in is not enough. *Check:* a test refuses a user without access.
- **S2 Bind query parameters.** Input reaches queries only as bound parameters; dynamic identifiers come from an allowlist. *Check:* no query text built from input.
- **S3 Shell-free subprocesses.** Run commands as an argument list, never a shell string built from input. *Check:* no added `shell=True`, `os.system` or `sh -c` with input.
- **S4 No code from data.** No external data reaches `eval` or a native deserializer (`pickle`, `yaml.load`); use JSON or a safe loader. *Check:* no added sink takes input.
- **S5 Validate at the boundary.** Check each new input's type, format, range and size before use. *Check:* a test sends an invalid or oversized value.
- **S6 Escape output.** Render input through auto-escaping, never `innerHTML`, `v-html`, `|safe` or concatenated markup. *Check:* raw sinks get only constants.
- **S7 Contain file paths.** Join input onto a fixed base, canonicalize, and reject it unless it stays inside. *Check:* each input-derived path has a `../` test.
- **S8 Secrets from the environment.** Read a new secret from env or a store with no literal default; never log or return it. *Check:* no log line prints one.
- **S9 Dependency changes.** Add or bump a dependency only with its regenerated lockfile and a repo-style pin, never `latest`. *Check:* the repo's audit command reports nothing new.
- **S10 Sensitive data at rest.** Store passwords through a password hash and tokens hashed or encrypted. *Check:* no new sensitive field is plaintext.
- **S11 Safe defaults.** Debug off, generic error responses, CORS limited to named origins, security headers kept. *Check:* no added debug flag, wildcard origin or response stack trace.
