# Telegram (Optional, Phase 6)

Telegram is **not** part of the core path. The main product is:

```text
Hermes on the home PC, controlled directly by the Android app through Cloudflare Tunnel.
```

Only start this after the direct Android path works end-to-end (plan §6, §23 Phase 6).

## When it's useful

- Quick `/restart` from any Telegram client.
- Emergency access if the Android app is broken.
- Share Hermes with someone who does not have the app.
- Simple notifications / desktop control.

## Optional architecture

```text
Telegram App → Telegram Servers → webhook → Cloudflare Tunnel
→ Home PC: Telegram Bridge → Hermes Gateway
```

## Scope when implemented

- Create a Telegram bot; add a Telegram Bridge backend (separate service).
- Expose the bridge webhook through Cloudflare Tunnel.
- Map Telegram chat → Hermes session.
- Render text responses; inline buttons for choice questions; confirm buttons for services.

## Guardrails

- The Telegram bridge is a **frontend**, not the transport. All service
  validation, confirmation and audit stay in the backend (see `SECURITY.md`).
- Bot token and webhook secret live only on the backend, never in this app.
