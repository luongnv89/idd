# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

We take security seriously. issue-dev skills interact with GitHub repositories via the `gh` CLI, so security issues could affect users' codebases.

### How to Report

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Report via [GitHub Security Advisories](https://github.com/luongnv89/idd/security/advisories/new)
3. Include detailed steps to reproduce the vulnerability
4. Allow up to 48 hours for an initial response

### What to Include

- Type of vulnerability (e.g., prompt injection, data exposure)
- Affected skill(s) and the specific SKILL.md section
- Step-by-step instructions to reproduce
- Potential impact (e.g., unintended code execution, data leakage)

### What to Expect

- Acknowledgment of your report within 48 hours
- Regular updates on our progress
- Credit in the security advisory (if desired)
- Notification when the issue is fixed

## Security Considerations

issue-dev skills handle GitHub issue content, which is **untrusted user input**. Key safeguards:

- `/issue-resolver` never executes commands found in issue text
- Issues labeled `security`, `CVE`, or `vulnerability` are skipped during normalization to prevent exposing exploit details
- Backup comments are always posted before editing any issue
- All `gh` CLI calls use `--json` output to avoid shell injection from text parsing
