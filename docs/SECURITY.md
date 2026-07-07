# Security

Security requirements for the Android app and the home-PC backend (plan §12, §20).

## Android

- Store the API key securely (platform secure storage), never in plain logs.
- Support biometric app lock.
- Obscure sensitive fields (API keys, passwords).
- HTTPS only for remote profiles.
- Allow device logout / key revoke.
- Show a clear warning before high/critical-risk services.

## Backend

- Authenticate every request (API key / bearer token) — even behind Cloudflare.
- Role-based authorization (`admin`, `trusted_user`, `viewer`).
- **Never** let the LLM run arbitrary shell commands — only registered manifests.
- Require confirmation for risky actions; keep audit logs for every run.
- Rate-limit public endpoints; restrict CORS.
- Separate read-only services from destructive ones.

## Confirmation policy

| Risk | Confirmation | Extra protection |
|---|---|---|
| Low | No | None |
| Medium | Yes | Normal confirm button |
| High | Yes | Confirm + show exact command/result |
| Critical | Yes | Typed confirmation phrase or biometric unlock |

Example high-risk confirmation:

```text
Restart Hermes?
This will temporarily disconnect the Android app.
Service: restart_hermes   Target: Home PC   Est. downtime: 10-30s
[Confirm Restart] [Cancel]
```

## Cloudflare Tunnel

- Use a dedicated hostname (e.g. `hermes-api.<domain>`).
- Do not expose unnecessary ports; protect admin endpoints.
- Do not rely on URL obscurity — keep API auth on.
- Optional extras: Cloudflare Access, mTLS, IP allowlist, short-lived tokens.

## Audit log

Every service run records: who, from which channel, which service, input
summary, confirmation state, start/end time, status, and safe output/errors.
