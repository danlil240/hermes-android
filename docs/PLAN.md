# Docs Index

This fork of [`rusty4444/hermes-android`](https://github.com/rusty4444/hermes-android)
adds a home-PC Hermes control experience over **Cloudflare Tunnel** — no VPN,
no Telegram in the core path.

The authoritative architecture plan lives at the repo root:
[`../HERMES_ANDROID_CLOUDFLARE_PLAN.md`](../HERMES_ANDROID_CLOUDFLARE_PLAN.md).

## Architecture (summary)

```text
Hermes Android App
    ↓ HTTPS
Cloudflare Tunnel
    ↓
Hermes Gateway on Home PC
    ↓
Hermes Agent  ├─ Question Engine
              ├─ Services Runner
              ├─ Database
              └─ Logs / Status / Updates
```

## Documents

- [`CLOUD_FLARE_TUNNEL.md`](CLOUD_FLARE_TUNNEL.md) — expose the home PC without a VPN.
- [`SERVICES_API.md`](SERVICES_API.md) — public API + services engine contract.
- [`CHOICE_QUESTIONS.md`](CHOICE_QUESTIONS.md) — structured LLM question blocks.
- [`SECURITY.md`](SECURITY.md) — auth, confirmation policy, safe execution.
- [`TELEGRAM_OPTIONAL.md`](TELEGRAM_OPTIONAL.md) — optional Phase-6 secondary channel.

## App layout (`lib/`)

```text
lib/
  core/      config/ network/ auth/ models/ storage/
  features/  chat/ sessions/ services/ questions/ settings/ diagnostics/
             (+ memory/ cron/ skills/ dashboard features)
  shared/    widgets/ theme/ errors/ responsive.dart
```

Backend helper code (gateway extensions, services-runner, question-engine) is
intentionally **not** in this repo; it belongs in a separate `hermes-home-backend`
repository per the plan (§8).
