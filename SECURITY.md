# Security Policy

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report security issues to: https://github.com/DigiWorldfk/cloudops-automation-hub/security/advisories/new

We will acknowledge within 48 hours and provide a fix timeline within 7 days.

## Credential Handling

- All credentials are injected via `.env` file at runtime
- `.env` is gitignored — never committed to source control
- gitleaks scans every push for accidental secret commits
- No credentials are logged or included in error responses

## Supported Versions

| Version | Supported |
|---------|-----------|
| main    | ✅        |
