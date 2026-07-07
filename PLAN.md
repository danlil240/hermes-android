# Hermes Android Fork + Telegram Backend Support — Comprehensive PLAN.md

**Project goal:** fork [`rusty4444/hermes-android`](https://github.com/rusty4444/hermes-android) and extend the Hermes ecosystem so your Android app, Telegram bot, and home-PC Hermes server all work together through one safe backend architecture.

**User-specific assumptions:**

- Hermes Agent runs on your **home PC**, not on a cloud server.
- The Android app is based on a fork of `rusty4444/hermes-android`.
- Telegram support should be implemented in the **backend**, not inside the Android app.
- “Services” means operational actions such as **reset**, **update**, **restart**, **status check**, **logs**, **backup**, and similar home-PC/Hermes maintenance operations.
- “Questions” means the LLM can ask the user structured questions during a session, usually with a few choices such as **Yes/No**, **Restart Hermes / Restart Ollama / Restart Cloudflare**, or **choose multiple components to update**.
- Remote access should work **without VPN**, using a public HTTPS endpoint, preferably through Cloudflare Tunnel.

---

## 1. Executive summary

The best architecture is:

```text
Android App Fork  ───────┐
                         │ HTTPS / SSE / API
Telegram Bot      ───────┤
                         ▼
                Hermes Bridge Backend
                         │
                         ▼
              Hermes Gateway on Home PC
                         │
                         ▼
        Agent / Skills / Services / Local Tools
```

The Android app remains a rich client. Telegram is another channel. The backend owns all sensitive logic: bot token, service execution, session mapping, confirmations, audit logs, and safety policies.

Do **not** place Telegram bot tokens, webhook handlers, or shell-execution logic in the Android app.

---

## 2. Why fork `hermes-android`

The upstream project already gives a strong base:

- Flutter/Dart Android client.
- Session list and chat screen.
- Streaming responses through Hermes Gateway’s OpenAI-compatible endpoint.
- Gateway API integration, usually port `8642`.
- Dashboard integration, usually port `9119`.
- Memory, Cron, Skills, and Settings screens.
- HTTP/HTTPS host support.
- Reverse-proxy path-prefix support.
- API-key connection model.
- Voice dictation and optional spoken replies.
- MIT license.

So the fork should focus on your missing product layer:

1. Home-PC remote-access profile.
2. Services UI for reset/update/restart/status/logs.
3. Structured LLM question/choice rendering.
4. Telegram backend bridge.
5. Shared session state between Android and Telegram.
6. Strong confirmation and audit model for dangerous operations.

---

## 3. Core design decision

### Correct separation

```text
Android app:
  - Chat UI
  - Connection profiles
  - Services UI
  - Choice-question UI
  - Dashboard/status screens
  - Local notification display

Telegram bridge backend:
  - Telegram webhook receiver
  - Bot token storage
  - Telegram chat/session mapping
  - Telegram inline-button rendering
  - Telegram command handling

Hermes backend/home PC:
  - Agent orchestration
  - Service execution
  - Update/restart/reset commands
  - Local scripts
  - Logs
  - Skills
  - Memory
  - Database
  - Audit logs
```

### Incorrect separation

```text
Do not:
  - Put the Telegram bot token in Android.
  - Execute shell commands from Android directly.
  - Let Telegram commands directly run scripts without confirmation.
  - Hardcode every LLM question as plain text.
  - Let each channel manage its own independent session state.
```

---

## 4. Target architecture

```text
┌─────────────────────────────────────────────┐
│ Android App Fork                             │
│ Based on rusty4444/hermes-android            │
│                                             │
│ Features:                                    │
│ - Chat sessions                              │
│ - Streaming responses                        │
│ - Services screen                            │
│ - Choice question renderer                   │
│ - Home-PC status screen                      │
│ - Telegram connector status                  │
└───────────────────────┬─────────────────────┘
                        │ HTTPS
                        ▼
┌─────────────────────────────────────────────┐
│ Public HTTPS Host                            │
│ Example: https://hermes-api.example.com      │
│ Cloudflare Tunnel / reverse proxy            │
└───────────────────────┬─────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────┐
│ Home PC                                      │
│                                             │
│ Docker Compose / systemd:                    │
│ - hermes-gateway                             │
│ - hermes-dashboard                           │
│ - hermes-bridge-api                          │
│ - hermes-telegram-bridge                     │
│ - hermes-service-runner                      │
│ - postgres/sqlite                            │
│ - redis optional                             │
│ - cloudflared                                │
└───────────────────────┬─────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────┐
│ Local capabilities                            │
│ - Restart Hermes                              │
│ - Update Hermes                               │
│ - Restart Docker services                     │
│ - Restart Cloudflare Tunnel                   │
│ - Restart Ollama/local model server           │
│ - View logs                                   │
│ - Backup/restore                              │
│ - Trigger skills                              │
│ - Read system status                          │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│ Telegram Bot                                 │
│                                             │
│ User sends message/clicks buttons            │
│        ↓                                     │
│ Telegram webhook                             │
│        ↓                                     │
│ hermes-telegram-bridge                       │
│        ↓                                     │
│ Hermes session / agent / service engine      │
└─────────────────────────────────────────────┘
```

---

## 5. Connectivity model without VPN

Use Cloudflare Tunnel or another secure reverse proxy so the phone and Telegram webhook can reach the home PC without opening router ports.

Recommended public hostnames:

```text
https://hermes-api.example.com
  → local http://localhost:8642

https://hermes-dashboard.example.com
  → local http://localhost:9119

https://hermes-bridge.example.com
  → local http://localhost:8787
```

Simpler single-host option:

```text
https://hermes.example.com/gateway
  → local http://localhost:8642

https://hermes.example.com/dashboard
  → local http://localhost:9119

https://hermes.example.com/bridge
  → local http://localhost:8787

https://hermes.example.com/telegram/webhook
  → local http://localhost:8787/telegram/webhook
```

Because the upstream Android app supports reverse-proxy path prefixes, the single-host option is practical.

---

## 6. Repository strategy

### Option A — Personal monorepo fork, fastest MVP

```text
hermes-android-fork/
  lib/                              # Flutter app
  android/
  ios/
  docs/
  backend/
    telegram_bridge/
    bridge_api/
    service_runner/
  infra/
    docker-compose.yml
    cloudflared/
    systemd/
  scripts/
    restart_hermes.sh
    update_hermes.sh
    backup_db.sh
```

This is easiest while the project is personal and moving quickly.

### Option B — Split repositories, better long-term

```text
hermes-android/             # Flutter Android/iOS app fork
hermes-bridge-backend/      # API, Telegram bridge, services, question engine
hermes-home-infra/          # Docker, cloudflared, systemd, deployment scripts
```

Start with Option A. Split later if the backend becomes large.

---

## 7. Git workflow

```bash
git clone https://github.com/rusty4444/hermes-android.git hermes-android-fork
cd hermes-android-fork

git remote rename origin upstream
git remote add origin git@github.com:danlil240/hermes-android.git

git checkout -b main-fork
```

Recommended branches:

```text
main-fork
  Stable branch for your fork.

upstream-sync
  Clean branch tracking rusty4444/main.

feature/home-pc-cloudflare-profile
  Cloudflare / home-PC connection presets.

feature/services-ui
  Android service screen for reset/update/restart/status/logs.

feature/choice-question-renderer
  Structured LLM choice prompts in the app.

feature/telegram-bridge-backend
  Telegram webhook backend and channel mapping.

feature/service-runner
  Safe backend execution of system services.
```

Sync upstream periodically:

```bash
git fetch upstream
git checkout upstream-sync
git merge upstream/main

git checkout main-fork
git merge upstream-sync
```

---

## 8. Backend components

### 8.1 Hermes Bridge API

A small backend layer in front of Hermes Gateway.

Responsibilities:

- Normalize Android and Telegram requests.
- Manage channel sessions.
- Store service runs.
- Store question sessions.
- Enforce service permissions.
- Enforce confirmations.
- Send requests to Hermes Gateway.
- Return structured message blocks to clients.

Suggested stack:

```text
Language: Python
Framework: FastAPI
DB: SQLite for MVP, PostgreSQL later
Queue: Redis/RQ or Dramatiq optional
HTTP client: httpx
Telegram library: aiogram or python-telegram-bot
Deployment: Docker Compose on home PC
```

### 8.2 Telegram Bridge

Responsibilities:

- Receive Telegram webhook updates.
- Verify webhook secret token.
- Map Telegram `chat_id` to Hermes session.
- Forward text messages to Hermes.
- Render Hermes responses back to Telegram.
- Render choice questions as inline keyboards.
- Render service confirmations as inline buttons.
- Handle callback queries.
- Support `/start`, `/help`, `/status`, `/services`, `/link`, `/cancel`.

### 8.3 Service Runner

Responsibilities:

- Execute allowed home-PC actions.
- Validate inputs.
- Require explicit confirmation for risky operations.
- Prevent arbitrary shell execution.
- Store audit logs.
- Return progress and result.

Services should be declared in manifests, not improvised by the LLM.

### 8.4 Question Engine

Responsibilities:

- Store active question sessions.
- Track choices selected by user.
- Support single-choice and multi-choice questions.
- Convert selections into structured answers.
- Continue the original agent/service flow after answer submission.

---

## 9. Android app changes

### 9.1 New connection preset: Home PC Hermes

Add a saved connection template:

```text
Name: Home PC Hermes
Gateway URL: https://hermes.example.com
Gateway path prefix: /gateway
Dashboard path prefix: /dashboard
Bridge path prefix: /bridge
Telegram status path: /bridge/telegram/status
Auth: API_SERVER_KEY or bridge token
```

UI additions:

```text
Connection details:
  - Gateway status
  - Dashboard status
  - Bridge status
  - Telegram bot status
  - Cloudflare tunnel status
  - Last latency
  - Current model
```

### 9.2 Services screen

Add drawer item:

```text
Services
```

Categories:

```text
System
  - Status
  - Restart Hermes
  - Restart Bridge
  - Restart Telegram Bridge
  - Restart Cloudflare Tunnel
  - Restart Ollama

Updates
  - Check for updates
  - Pull latest Hermes
  - Pull latest Android fork
  - Rebuild Docker containers
  - Restart after update

Sessions
  - Clear current session
  - Export session
  - Reset memory for session

Logs
  - Hermes logs
  - Bridge logs
  - Telegram logs
  - Cloudflared logs

Backup
  - Backup database
  - List backups
  - Restore backup
```

Service flow:

```text
User selects service
  ↓
App shows description + risk level
  ↓
If required, app asks for confirmation
  ↓
App sends service request to bridge backend
  ↓
Backend starts service run
  ↓
App displays queued/running/completed/failed state
  ↓
Result is shown in chat and in service history
```

### 9.3 Structured message blocks

Currently chat messages are mostly text/markdown. Add a generalized block renderer:

```dart
sealed class HermesMessageBlock {}

class TextBlock extends HermesMessageBlock {
  final String markdown;
}

class ChoiceQuestionBlock extends HermesMessageBlock {
  final String questionId;
  final String title;
  final String? description;
  final ChoiceMode mode; // single or multiple
  final List<ChoiceOption> options;
  final bool required;
  final int? minSelections;
  final int? maxSelections;
}

class ServiceConfirmationBlock extends HermesMessageBlock {
  final String serviceRunId;
  final String serviceId;
  final String title;
  final String riskLevel;
  final Map<String, dynamic> inputPreview;
}

class ServiceProgressBlock extends HermesMessageBlock {
  final String serviceRunId;
  final String status; // queued, running, completed, failed
  final String? message;
}

class ServiceResultBlock extends HermesMessageBlock {
  final String serviceRunId;
  final bool success;
  final String summary;
  final Map<String, dynamic>? details;
}
```

### 9.4 Choice-question UI

Single choice:

```text
Hermes:
Which service do you want to restart?

( ) Hermes
( ) Ollama
( ) Cloudflare Tunnel
( ) Telegram Bridge

[Submit] [Cancel]
```

Multiple choice:

```text
Hermes:
Which components should be updated?

[ ] Hermes Agent
[ ] Android fork
[ ] Telegram bridge
[ ] Docker images

[Submit] [Clear] [Cancel]
```

### 9.5 Telegram connector status screen

Add a screen or card:

```text
Telegram Connector
  Status: Connected / Error / Disabled
  Bot username: @your_bot
  Webhook: configured / missing
  Last update: timestamp
  Linked chats: N
  Pending callbacks: N
  Last error: message
```

---

## 10. Telegram backend design

### 10.1 Telegram webhook endpoint

```http
POST /telegram/webhook
```

Handler flow:

```text
Receive update
  ↓
Verify secret token header
  ↓
Deduplicate update_id
  ↓
Parse message/callback_query
  ↓
Normalize into HermesChannelEvent
  ↓
Route:
    message text → Hermes conversation
    command → command handler
    callback query → question/service handler
  ↓
Render response to Telegram
```

### 10.2 Internal normalized event

```json
{
  "event_id": "telegram:123456789",
  "channel": "telegram",
  "event_type": "message",
  "external_user_id": "12345",
  "external_chat_id": "67890",
  "text": "restart hermes",
  "attachments": [],
  "timestamp": "2026-07-07T22:00:00+03:00"
}
```

### 10.3 Telegram commands

```text
/start
  Create or resume Telegram-Hermes mapping.

/help
  Show available commands.

/status
  Show Hermes status.

/services
  Show service categories.

/restart
  Start restart flow with choices.

/update
  Start update flow with choices.

/logs
  Ask which logs to view.

/link
  Link Telegram chat to Android/Hermes user.

/cancel
  Cancel current question/service flow.
```

### 10.4 Inline keyboard callback format

Keep callback data short and deterministic:

```text
q:<question_id>:select:<option_id>
q:<question_id>:unselect:<option_id>
q:<question_id>:submit
q:<question_id>:cancel

svc:<service_run_id>:confirm
svc:<service_run_id>:cancel

menu:services
menu:status
```

Example:

```text
q:q_abc123:select:restart_ollama
svc:run_abc123:confirm
```

### 10.5 Telegram rendering rules

| Hermes block | Telegram rendering |
|---|---|
| TextBlock | Send normal message with Markdown/HTML formatting |
| ChoiceQuestionBlock single | Inline keyboard, one option per row or two per row |
| ChoiceQuestionBlock multiple | Inline keyboard with selected/unselected markers + Submit |
| ServiceConfirmationBlock | Summary text + Confirm/Cancel buttons |
| ServiceProgressBlock | Message edit or new status message |
| ServiceResultBlock | Final result message |

---

## 11. Services engine

### 11.1 Service manifest format

Each service is declared in YAML/JSON.

```yaml
id: restart_hermes
name: Restart Hermes
category: system
summary: Restart the Hermes Gateway, dashboard, and bridge services.
risk_level: high
requires_confirmation: true
requires_admin: true
cooldown_seconds: 30
timeout_seconds: 60
inputs:
  reason:
    type: string
    required: false
    max_length: 200
execution:
  type: command
  command: /opt/hermes/scripts/restart_hermes.sh
audit:
  enabled: true
  include_input: true
  include_output: true
```

### 11.2 Recommended services

#### System status

```text
system_status
  - uptime
  - CPU/RAM/disk
  - Docker container status
  - Hermes Gateway health
  - Dashboard health
  - Telegram bridge health
  - Cloudflare tunnel health
  - model server health
```

#### Restart services

```text
restart_hermes
restart_hermes_gateway
restart_hermes_dashboard
restart_hermes_bridge
restart_telegram_bridge
restart_cloudflared
restart_ollama
restart_postgres
restart_redis
restart_all
```

#### Update services

```text
check_updates
update_hermes_agent
update_android_fork_repo
update_telegram_bridge
pull_docker_images
rebuild_containers
restart_after_update
```

#### Reset services

```text
clear_current_session
reset_session_memory
reset_telegram_mapping
reset_dashboard_session
reset_bridge_cache
```

#### Logs

```text
view_hermes_logs
view_bridge_logs
view_telegram_logs
view_cloudflared_logs
view_docker_logs
```

#### Backup

```text
backup_database
list_backups
restore_backup
export_conversation
```

### 11.3 Service run states

```text
requested
waiting_for_confirmation
queued
running
waiting_for_user
completed
failed
cancelled
timeout
```

### 11.4 Service request example

```http
POST /bridge/services/runs
Authorization: Bearer <token>
Content-Type: application/json
```

```json
{
  "service_id": "restart_ollama",
  "source_channel": "android",
  "conversation_id": "conv_123",
  "inputs": {
    "reason": "Model server not responding"
  }
}
```

### 11.5 Service confirmation example

```json
{
  "type": "service_confirmation",
  "service_run_id": "run_123",
  "service_id": "restart_ollama",
  "title": "Restart Ollama?",
  "risk_level": "medium",
  "summary": "This will restart the local model server on the home PC. Current chat processing may pause for a short time.",
  "actions": [
    { "id": "confirm", "label": "Restart" },
    { "id": "cancel", "label": "Cancel" }
  ]
}
```

---

## 12. LLM choice questions during sessions

### 12.1 Goal

The LLM should be able to ask structured questions instead of only asking text questions.

Bad:

```text
Do you want me to restart Hermes, Ollama, or Cloudflare? Please type one.
```

Good:

```json
{
  "type": "choice_question",
  "question_id": "q_123",
  "title": "Which service do you want to restart?",
  "mode": "single",
  "options": [
    { "id": "hermes", "label": "Hermes" },
    { "id": "ollama", "label": "Ollama" },
    { "id": "cloudflared", "label": "Cloudflare Tunnel" },
    { "id": "telegram_bridge", "label": "Telegram Bridge" }
  ],
  "required": true
}
```

### 12.2 Supported question types for MVP

```text
choice_single
choice_multiple
confirmation
text_short
text_long
number
```

Start with only:

```text
choice_single
choice_multiple
confirmation
```

### 12.3 Question state machine

```text
created
  ↓
sent_to_user
  ↓
answered / cancelled / expired
  ↓
agent_continues / service_continues / flow_ends
```

### 12.4 Multi-choice behavior

Rules:

```text
- min_selections
- max_selections
- required
- allow_other
- exclusive options, e.g. "None"
- Submit button
- Cancel button
```

Example:

```json
{
  "type": "choice_question",
  "question_id": "q_update_components",
  "title": "Which components should I update?",
  "mode": "multiple",
  "min_selections": 1,
  "max_selections": 4,
  "options": [
    { "id": "hermes_agent", "label": "Hermes Agent" },
    { "id": "android_app", "label": "Android App Fork" },
    { "id": "telegram_bridge", "label": "Telegram Bridge" },
    { "id": "docker_images", "label": "Docker Images" }
  ]
}
```

### 12.5 Android rendering

```text
Single choice → radio buttons or big choice cards
Multiple choice → checkboxes/chips + Submit
Confirmation → destructive action card
```

### 12.6 Telegram rendering

```text
Single choice → inline keyboard options
Multiple choice → inline keyboard toggles + Done
Confirmation → Confirm / Cancel inline buttons
```

---

## 13. API contract

### 13.1 Health

```http
GET /bridge/health
```

```json
{
  "status": "ok",
  "version": "0.1.0",
  "hermes_gateway": "ok",
  "dashboard": "ok",
  "telegram": "ok",
  "cloudflared": "unknown"
}
```

### 13.2 List services

```http
GET /bridge/services
```

```json
{
  "services": [
    {
      "id": "restart_hermes",
      "name": "Restart Hermes",
      "category": "system",
      "risk_level": "high",
      "requires_confirmation": true
    }
  ]
}
```

### 13.3 Start service

```http
POST /bridge/services/runs
```

```json
{
  "service_id": "restart_hermes",
  "inputs": {
    "reason": "Gateway not responding"
  },
  "conversation_id": "conv_123"
}
```

### 13.4 Confirm service

```http
POST /bridge/services/runs/{service_run_id}/confirm
```

```json
{
  "confirmed": true
}
```

### 13.5 Answer question

```http
POST /bridge/questions/{question_id}/answer
```

Single choice:

```json
{
  "selected": ["ollama"]
}
```

Multiple choice:

```json
{
  "selected": ["hermes_agent", "telegram_bridge"]
}
```

### 13.6 Telegram status

```http
GET /bridge/telegram/status
```

```json
{
  "enabled": true,
  "bot_username": "your_bot",
  "webhook_configured": true,
  "linked_chats": 3,
  "last_update_at": "2026-07-07T22:00:00+03:00",
  "last_error": null
}
```

---

## 14. Database schema

SQLite for MVP is acceptable. PostgreSQL is better if you expect more users or heavier audit logs.

### 14.1 Tables

```sql
CREATE TABLE channel_sessions (
    id TEXT PRIMARY KEY,
    channel TEXT NOT NULL,
    external_user_id TEXT NOT NULL,
    external_chat_id TEXT,
    hermes_session_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(channel, external_user_id, external_chat_id)
);

CREATE TABLE service_runs (
    id TEXT PRIMARY KEY,
    service_id TEXT NOT NULL,
    conversation_id TEXT,
    source_channel TEXT NOT NULL,
    requested_by TEXT,
    status TEXT NOT NULL,
    risk_level TEXT NOT NULL,
    input_json TEXT,
    output_json TEXT,
    error TEXT,
    confirmation_required INTEGER NOT NULL DEFAULT 0,
    confirmed_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE question_sessions (
    id TEXT PRIMARY KEY,
    conversation_id TEXT,
    source_channel TEXT NOT NULL,
    question_json TEXT NOT NULL,
    selected_json TEXT,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    expires_at TEXT
);

CREATE TABLE telegram_updates (
    update_id TEXT PRIMARY KEY,
    received_at TEXT NOT NULL,
    processed_at TEXT,
    status TEXT NOT NULL,
    error TEXT
);

CREATE TABLE audit_logs (
    id TEXT PRIMARY KEY,
    actor_id TEXT,
    source_channel TEXT,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    summary TEXT,
    metadata_json TEXT,
    created_at TEXT NOT NULL
);
```

---

## 15. Security model

### 15.1 Secrets

Secrets must stay on the home PC/backend:

```text
TELEGRAM_BOT_TOKEN
TELEGRAM_WEBHOOK_SECRET
API_SERVER_KEY
BRIDGE_ADMIN_TOKEN
DASHBOARD_USERNAME
DASHBOARD_PASSWORD
CLOUDFLARE_TUNNEL_TOKEN
```

Never store these in the Android repo.

Use `.env` locally:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_WEBHOOK_SECRET=...
HERMES_GATEWAY_URL=http://localhost:8642
HERMES_DASHBOARD_URL=http://localhost:9119
BRIDGE_ADMIN_TOKEN=...
```

### 15.2 Dangerous service policy

High-risk services must require confirmation:

```text
restart_all
update_hermes_agent
restore_backup
reset_memory
restart_postgres
clear_database
```

For the most dangerous actions, require a typed confirmation:

```text
Type RESTART to confirm.
Type RESTORE to confirm.
Type DELETE to confirm.
```

Telegram version:

```text
Hermes:
This is a high-risk action.
Reply with: RESTART
```

Android version:

```text
Confirmation dialog with typed confirmation field.
```

### 15.3 Authorization

Roles:

```text
admin
trusted_user
viewer
telegram_unlinked
```

Permissions:

```text
service:read
service:run:low
service:run:medium
service:run:high
logs:read
memory:read
memory:reset
telegram:link
admin:settings
```

### 15.4 Service runner isolation

Do not let the agent generate arbitrary shell commands.

Allowed:

```text
service_id = restart_ollama
backend maps to fixed script /opt/hermes/scripts/restart_ollama.sh
```

Forbidden:

```text
LLM says: run `rm -rf ...`
Telegram command passes arbitrary shell string
Android sends shell_command directly
```

### 15.5 Audit log requirements

Every service run records:

```text
who requested it
from which channel
which service
input summary
confirmation state
start time
end time
status
stdout/stderr summary if safe
error if failed
```

---

## 16. Home PC deployment

### 16.1 Docker Compose layout

```yaml
services:
  hermes-bridge:
    build: ./backend/bridge_api
    env_file: .env
    ports:
      - "8787:8787"
    restart: unless-stopped

  hermes-telegram-bridge:
    build: ./backend/telegram_bridge
    env_file: .env
    depends_on:
      - hermes-bridge
    restart: unless-stopped

  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: hermes_bridge
      POSTGRES_USER: hermes
      POSTGRES_PASSWORD: change_me
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: redis:7
    restart: unless-stopped

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run
    env_file: .env
    restart: unless-stopped

volumes:
  postgres_data:
```

### 16.2 Required home-PC settings

```text
- Disable sleep.
- Use wired Ethernet if possible.
- Auto-start Docker on boot.
- Auto-start cloudflared on boot.
- Keep backups outside the Docker volume.
- Add watchdog/restart policies.
- Monitor disk usage.
```

### 16.3 Local script folder

```text
/opt/hermes/scripts/
  restart_hermes.sh
  restart_gateway.sh
  restart_dashboard.sh
  restart_bridge.sh
  restart_telegram_bridge.sh
  restart_cloudflared.sh
  restart_ollama.sh
  update_hermes.sh
  backup_db.sh
  view_logs.sh
```

Example script:

```bash
#!/usr/bin/env bash
set -euo pipefail

systemctl restart hermes-gateway
systemctl restart hermes-dashboard
systemctl restart hermes-bridge

echo "Hermes services restarted successfully"
```

---

## 17. LLM integration strategy

### 17.1 Current path

The Android app currently talks to Hermes Gateway for sessions and chat. Keep this path.

### 17.2 Add structured output layer

The bridge should detect structured blocks returned by Hermes or wrap them around service/question events.

Possible response format:

```json
{
  "message_id": "msg_123",
  "conversation_id": "conv_123",
  "blocks": [
    {
      "type": "text",
      "markdown": "I can restart a service. Which one?"
    },
    {
      "type": "choice_question",
      "question_id": "q_123",
      "mode": "single",
      "title": "Choose service",
      "options": [
        { "id": "hermes", "label": "Hermes" },
        { "id": "ollama", "label": "Ollama" }
      ]
    }
  ]
}
```

### 17.3 Agent tool contract

Expose a tool to the LLM:

```json
{
  "name": "ask_user_choice",
  "description": "Ask the user a structured choice question during the current session.",
  "parameters": {
    "type": "object",
    "properties": {
      "title": { "type": "string" },
      "mode": { "type": "string", "enum": ["single", "multiple"] },
      "options": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "id": { "type": "string" },
            "label": { "type": "string" }
          },
          "required": ["id", "label"]
        }
      }
    },
    "required": ["title", "mode", "options"]
  }
}
```

Expose another tool:

```json
{
  "name": "request_service_run",
  "description": "Request a predefined service run such as restart/update/status. The backend validates permissions and confirmation.",
  "parameters": {
    "type": "object",
    "properties": {
      "service_id": { "type": "string" },
      "inputs": { "type": "object" }
    },
    "required": ["service_id"]
  }
}
```

---

## 18. UX examples

### 18.1 Android: restart flow

```text
User:
Restart one of the services.

Hermes:
Which service do you want to restart?

[Hermes Gateway]
[Hermes Dashboard]
[Telegram Bridge]
[Ollama]
[Cloudflare Tunnel]

User taps: Ollama

Hermes:
Restart Ollama on the home PC?
Risk: Medium
This may interrupt local model responses for a short time.

[Restart Ollama]
[Cancel]

User taps: Restart Ollama

Hermes:
Ollama restarted successfully.
```

### 18.2 Telegram: update flow

```text
User:
/update

Hermes:
Which components should I update?

[ ] Hermes Agent
[ ] Telegram Bridge
[ ] Docker Images
[Done]
[Cancel]

User taps Hermes Agent + Telegram Bridge + Done.

Hermes:
I will update:
- Hermes Agent
- Telegram Bridge

This is a high-risk action and may restart services.

[Confirm Update]
[Cancel]
```

### 18.3 Status flow

```text
User:
/status

Hermes:
Home PC status:
- Hermes Gateway: OK
- Dashboard: OK
- Telegram Bridge: OK
- Cloudflare Tunnel: OK
- Ollama: OK
- Disk: 72%
- RAM: 41%
- Uptime: 3 days
```

---

## 19. Implementation phases

### Phase 0 — Baseline fork validation

Goals:

- Clone upstream.
- Build Android APK.
- Connect app to local Hermes on LAN.
- Verify session browsing.
- Verify streaming chat.
- Verify dashboard screens.

Deliverables:

```text
- Fork repository created.
- APK builds successfully.
- App connects to home-PC Hermes over LAN.
- README updated with your environment.
```

Acceptance criteria:

```text
- You can open the app.
- You can create a chat.
- You can stream a response.
- You can browse sessions.
```

---

### Phase 1 — Cloudflare/home-PC remote profile

Goals:

- Expose Hermes Gateway and dashboard through Cloudflare Tunnel.
- Configure Android app to connect through HTTPS.
- Add connection preset fields if needed.

Deliverables:

```text
- cloudflared config.
- Android connection works without VPN.
- Reverse-proxy path prefix tested.
- Security checklist written.
```

Acceptance criteria:

```text
- Android app connects from mobile network, not home Wi-Fi.
- Chat streaming works over HTTPS.
- Dashboard screens work or fail with clear error messages.
```

---

### Phase 2 — Bridge backend skeleton

Goals:

- Add `/bridge/health`.
- Add DB.
- Add channel session table.
- Add service registry table or file loader.
- Add basic auth token.

Deliverables:

```text
backend/bridge_api
  - FastAPI app
  - health route
  - SQLite/Postgres integration
  - service manifest loader
  - Dockerfile
```

Acceptance criteria:

```text
curl https://hermes.example.com/bridge/health
returns status ok.
```

---

### Phase 3 — Services MVP

Goals:

- Implement `system_status`.
- Implement `restart_ollama`.
- Implement `restart_cloudflared`.
- Implement `restart_hermes_bridge`.
- Add confirmation flow.
- Add audit logging.

Deliverables:

```text
- Service manifests.
- Service runner.
- Confirmation endpoint.
- Audit log table.
- Android Services screen MVP.
```

Acceptance criteria:

```text
- Android lists services.
- Android can run status service.
- Android asks confirmation before restart.
- Backend records audit entry.
```

---

### Phase 4 — Choice-question renderer in Android

Goals:

- Define message block schema.
- Add Android renderer for single choice.
- Add Android renderer for multi-choice.
- Add answer submission endpoint.

Deliverables:

```text
- ChoiceQuestionBlock model.
- ChoiceQuestionWidget.
- POST /bridge/questions/{id}/answer.
- Demo question flow.
```

Acceptance criteria:

```text
- Backend sends a choice question.
- Android displays buttons/checkboxes.
- User answer is submitted and stored.
```

---

### Phase 5 — Telegram bridge MVP

Goals:

- Create Telegram bot.
- Configure webhook.
- Receive updates.
- Send text replies.
- Map Telegram chat to Hermes session.
- Implement `/start`, `/help`, `/status`.

Deliverables:

```text
backend/telegram_bridge
  - webhook route
  - Telegram sender
  - command handlers
  - session mapper
  - Dockerfile
```

Acceptance criteria:

```text
- You can send /start to the bot.
- Bot replies.
- /status returns home-PC status.
- Telegram events are deduplicated.
```

---

### Phase 6 — Telegram choice questions

Goals:

- Render single-choice questions as inline keyboard.
- Render multiple-choice questions as toggle inline keyboard.
- Handle callback queries.
- Submit answer to question engine.

Deliverables:

```text
- callback data parser.
- Telegram renderer for ChoiceQuestionBlock.
- Telegram question state storage.
```

Acceptance criteria:

```text
- Telegram bot asks which service to restart.
- User taps an inline button.
- Backend receives callback.
- Correct service confirmation appears.
```

---

### Phase 7 — Telegram service confirmations

Goals:

- Render service confirmation cards in Telegram.
- Handle Confirm/Cancel callbacks.
- Run service only after confirmation.
- Return progress/result.

Acceptance criteria:

```text
- Telegram never runs high-risk service without confirmation.
- Confirmation button starts service.
- Cancel button cancels service run.
- Audit log records source_channel=telegram.
```

---

### Phase 8 — Hardening

Goals:

- RBAC.
- Secret rotation.
- Rate limiting.
- Backup/restore.
- Error handling.
- Observability.
- Integration tests.
- Release APK.

Acceptance criteria:

```text
- App survives backend offline states.
- Telegram bridge survives duplicate updates.
- Dangerous services require confirmation.
- Logs show clear trace for every action.
```

---

## 20. Testing plan

### 20.1 Android tests

```text
- Connection normalization.
- HTTPS host connection.
- Gateway prefix handling.
- Dashboard prefix handling.
- Services screen rendering.
- Confirmation dialog.
- Choice question single/multiple selection.
- Offline/error UI.
```

### 20.2 Backend tests

```text
- Health endpoint.
- Service manifest parsing.
- Permission checks.
- Confirmation required logic.
- Service timeout.
- Audit log creation.
- Question session creation.
- Single-choice validation.
- Multi-choice validation.
```

### 20.3 Telegram tests

```text
- Webhook secret validation.
- Update deduplication.
- /start command.
- /status command.
- Callback parsing.
- Inline keyboard rendering.
- Multi-choice toggle state.
- Service confirmation callback.
```

### 20.4 End-to-end tests

```text
Telegram /status
  → webhook
  → bridge
  → service_runner
  → system_status
  → Telegram reply

Android restart Ollama
  → services screen
  → service request
  → confirmation
  → service runner
  → result card
  → audit log

LLM asks user a choice question
  → backend creates question_session
  → Android renders choices
  → user answers
  → agent continues
```

---

## 21. Observability

### 21.1 Logs

Use structured JSON logs:

```json
{
  "event": "service_run_completed",
  "service_id": "restart_ollama",
  "service_run_id": "run_123",
  "source_channel": "telegram",
  "status": "completed",
  "duration_ms": 1840
}
```

### 21.2 Metrics

Track:

```text
- Telegram webhook latency
- Telegram webhook failure count
- Duplicate Telegram updates
- Service run count by service_id
- Service failures
- Question sessions created
- Question sessions cancelled/expired
- Android connection errors
- Hermes Gateway latency
- Cloudflare tunnel availability
```

### 21.3 Debug screen

Android debug/status screen:

```text
Gateway: OK / Error
Dashboard: OK / Error
Bridge: OK / Error
Telegram: OK / Error
Last bridge error: ...
Current connection: ...
API prefix: ...
Dashboard prefix: ...
```

---

## 22. Release plan

### 22.1 Internal release

```text
Version: 1.1.0-daniel.1
Scope:
  - fork branding
  - Cloudflare connection profile
  - status screen
```

### 22.2 Services release

```text
Version: 1.2.0-daniel.1
Scope:
  - services screen
  - status service
  - restart service
  - confirmation flow
```

### 22.3 Telegram release

```text
Version: 1.3.0-daniel.1
Scope:
  - Telegram bridge
  - /start, /help, /status
  - Telegram session mapping
```

### 22.4 Choice questions release

```text
Version: 1.4.0-daniel.1
Scope:
  - Android choice renderer
  - Telegram inline keyboard renderer
  - question engine
```

---

## 23. Main risks and mitigations

### Risk: exposing Hermes publicly

Mitigation:

```text
- Use Cloudflare Tunnel.
- Use HTTPS only.
- Do not expose raw dashboard publicly without auth.
- Use API keys/tokens.
- Add rate limits.
- Keep dangerous services behind confirmation.
```

### Risk: LLM triggers dangerous service accidentally

Mitigation:

```text
- LLM can only request service_id.
- Backend validates service_id.
- Backend enforces confirmation.
- Backend enforces role permission.
- No arbitrary shell commands.
```

### Risk: Telegram callback duplication

Mitigation:

```text
- Store update_id.
- Store callback_id if needed.
- Make service confirmation idempotent.
- Use service_run_id state machine.
```

### Risk: home PC goes offline

Mitigation:

```text
- Disable sleep.
- Auto-start Docker/cloudflared.
- Add health checks.
- Add watchdog restart policy.
- Optional: later add small VPS relay.
```

### Risk: fork diverges too much from upstream

Mitigation:

```text
- Keep app changes modular.
- Put backend in separate folder.
- Avoid rewriting existing chat flow.
- Maintain upstream-sync branch.
- Rebase/merge upstream regularly.
```

---

## 24. Recommended immediate TODO list

### Day 1

```text
1. Fork repository.
2. Build APK locally.
3. Connect to Hermes over LAN.
4. Document current connection settings.
5. Create `docs/HOME_PC_SETUP.md`.
```

### Day 2

```text
1. Configure Cloudflare Tunnel.
2. Test app over HTTPS without VPN.
3. Verify streaming works through reverse proxy.
4. Add a Home PC connection preset if needed.
```

### Day 3

```text
1. Create backend/bridge_api skeleton.
2. Add /bridge/health.
3. Add service manifest loader.
4. Add system_status service.
```

### Day 4

```text
1. Add Android Services screen.
2. List services from /bridge/services.
3. Run system_status from Android.
4. Display result card.
```

### Day 5

```text
1. Add restart_ollama and restart_cloudflared services.
2. Add confirmation flow.
3. Add audit log.
```

### Day 6

```text
1. Create Telegram bot.
2. Add Telegram webhook.
3. Implement /start and /status.
4. Map Telegram chat to Hermes session.
```

### Day 7

```text
1. Add choice question schema.
2. Render choices in Android.
3. Render choices in Telegram inline keyboard.
4. Test restart flow end-to-end.
```

---

## 25. Definition of done for MVP

The MVP is done when:

```text
- Android app fork connects to home-PC Hermes without VPN.
- Telegram bot can talk to the same Hermes backend.
- Android can show and run safe services.
- Telegram can show and run safe services.
- High-risk services require confirmation.
- The LLM can ask a choice question during a session.
- Android renders that question as buttons/checkboxes.
- Telegram renders that question as inline buttons.
- Answers continue the same session.
- Every service execution is audited.
- No Telegram token or shell execution exists inside Android.
```

---

## 26. References

- `rusty4444/hermes-android`: https://github.com/rusty4444/hermes-android
- Telegram Bot API: https://core.telegram.org/bots/api
- Cloudflare Tunnel setup: https://developers.cloudflare.com/tunnel/setup/
- Cloudflare Tunnel routing/published applications: https://developers.cloudflare.com/tunnel/routing/
- Firebase Cloud Messaging: https://firebase.google.com/docs/cloud-messaging

---

## 27. Final recommendation

Forking `rusty4444/hermes-android` is the right path because it already solves the core mobile-Hermes client problem. Your work should not be a full rewrite. It should be a focused extension:

```text
Fork hermes-android
  + Home-PC/Cloudflare connection profile
  + Services screen for reset/update/restart/status/logs
  + Structured choice-question renderer
  + Telegram connector status screen

Backend bridge
  + Telegram webhook
  + Telegram session mapping
  + Service engine
  + Question engine
  + Confirmations
  + Audit logs
```

This gives you a serious Hermes control app, Telegram fallback, service automation, and LLM-driven interactive choices — while keeping the dangerous parts safely on the home-PC backend.
