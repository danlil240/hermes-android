# Services API

The Android app talks to one Hermes Gateway origin (via Cloudflare Tunnel). This
document is the contract the app codes against (plan §10, §12, §13). The backend
that implements it lives in a separate `hermes-home-backend` repo.

## Endpoints

```text
GET    /health
GET    /status

GET    /sessions
POST   /sessions
GET    /sessions/{session_id}
DELETE /sessions/{session_id}
GET    /sessions/{session_id}/messages
POST   /sessions/{session_id}/messages

GET    /services
POST   /services/{service_id}/run
GET    /service-runs/{run_id}
POST   /service-runs/{run_id}/confirm
POST   /service-runs/{run_id}/cancel

GET    /questions/{question_id}
POST   /questions/{question_id}/answer

GET    /diagnostics/home-pc
GET    /diagnostics/cloudflare
GET    /diagnostics/models
```

## Service manifest

Each service is a fixed, registered manifest — the LLM may *request* a
`service_id` but never supplies a shell command (plan §12.3, §13).

```yaml
id: restart_hermes
name: Restart Hermes
category: system
description: Restarts the Hermes backend services on the home PC.
risk_level: high           # low | medium | high | critical
requires_confirmation: true
allowed_roles: [admin]
command:
  type: systemd
  value: restart hermes
timeout_seconds: 60
audit: true
```

## Service run lifecycle

```text
requested → (waiting_for_confirmation) → running → completed | failed | cancelled | timeout
```

Result shape:

```json
{
  "run_id": "run_123",
  "service_id": "restart_hermes",
  "status": "completed",
  "started_at": "2026-07-07T20:00:00Z",
  "completed_at": "2026-07-07T20:00:12Z",
  "summary": "Hermes restarted successfully.",
  "logs_tail": "... last lines ..."
}
```

## First services (MVP)

```text
check_status   restart_hermes   restart_gateway   restart_agent
restart_cloudflared   restart_ollama   view_logs   backup_database
```

## App rendering

- Service progress → `ServiceProgressBlock` card (steps + status).
- Service result → `ServiceResultBlock` card (duration + component health).
- See `CHOICE_QUESTIONS.md` for confirmation cards on medium/high/critical risk.
