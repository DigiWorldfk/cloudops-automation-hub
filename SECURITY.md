# Security Policy

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report security issues to: https://github.com/DigiWorldfk/cloudops-automation-hub/security/advisories/new

We will acknowledge within 48 hours and provide a fix timeline within 7 days.

## Credential Handling

- All credentials are injected via `.env` file at runtime
- `.env` is gitignored — never committed to source control
- Gitleaks scans the complete repository and Git history for accidental secret commits
- No credentials are logged or included in error responses
- `JWT_SECRET`, `ADMIN_PASS_HASH`, and `TOTP_SECRET` are required; the backend fails closed when they are missing or use placeholder values
- Production requires `ENVIRONMENT=production`, `COOKIE_SECURE=true`, and an explicit `CORS_ALLOWED_ORIGINS` allowlist
- The backend does not mount `/var/run/docker.sock`; Docker operations are disabled unless a separately designed privileged worker is introduced

## Before Deployment

1. Rotate any credential that has ever been committed or exposed. Do not rely on deleting it from the current branch.
2. Generate a unique JWT secret, bcrypt administrator password hash, and TOTP secret for each environment.
3. Use short-lived, least-privilege cloud identities. Prefer workload identity or OIDC over static access keys.
4. Run Gitleaks, Trivy, Terraform validation, Helm validation, and Kubernetes manifest validation across every platform tree.
5. Confirm HTTPS is enforced and production cookies are marked `Secure`.
6. Confirm the API is reachable only through the intended network boundary and that destructive operations require the correct role.
7. Verify logs, Terraform responses, pod logs, and activity records do not contain passwords, tokens, keys, or connection strings.

## Incident Response

If a secret may have leaked:

1. Disable or rotate it immediately at the provider.
2. Revoke active sessions and regenerate JWT/TOTP material where applicable.
3. Preserve relevant audit and CI metadata without copying secret values into tickets or logs.
4. Remove the secret from the working tree and rewrite repository history when required by the incident process.
5. Review cloud, Kubernetes, Docker, and Terraform audit logs for unauthorized activity.

## Supported Versions

| Version | Supported |
|---------|-----------|
| main    | ✅        |
