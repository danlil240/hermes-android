# Hermes Android + Cloudflare Tunnel Plan

## 1. Final Direction

The correct architecture is:

```text
Hermes Android App
    ↓ HTTPS
Cloudflare Tunnel
    ↓
Hermes Gateway on Home PC
    ↓
Hermes Agent / Services / Question Engine
```

Telegram is **not** required in the middle.

Telegram should be treated only as an optional secondary frontend later.

---

## 2. Main Goal

Create a reliable Android client for Hermes Agent by forking:

```text
https://github.com/rusty4444/hermes-android
```

Then modify it for your setup:

```text
Android phone
    ↓
https://hermes.your-domain.com
    ↓
Cloudflare Tunnel
    ↓
Home PC running Hermes
```

The Android app should directly communicate with Hermes through the Cloudflare Tunnel URL.

---

## 3. What Runs Where

| Component | Runs On | Purpose |
|---|---|---|
| Hermes Android App fork | Android phone | Main UI for chat, services, questions, settings |
| Cloudflare Tunnel | Home PC | Exposes Hermes securely without VPN or port forwarding |
| Hermes Gateway API | Home PC | Public API used by the Android app |
| Hermes Agent | Home PC | Main AI agent logic |
| Services Runner | Home PC | Executes reset/update/restart/status/log commands |
| Question Engine | Home PC | Creates LLM-driven questions with choices |
| Database | Home PC | Stores sessions, settings, service runs, question state |
| Redis / Queue | Home PC, optional | Handles long jobs and retries |
| Telegram Bridge | Optional later, Home PC or VPS | Secondary chat/control channel only |

---

## 4. Correct Network Architecture

### Main Android Flow

```text
Android App
    ↓ HTTPS request
Cloudflare public hostname
    ↓ tunnel
Home PC: Hermes Gateway
    ↓
Hermes Agent
```

Example public hostname:

```text
https://hermes-api.daniel-lilintal.com
```

Example local target on the home PC:

```text
http://localhost:8642
```

Cloudflare Tunnel maps:

```text
https://hermes-api.daniel-lilintal.com
    → http://localhost:8642
```

---

## 5. Why Telegram Is Not Needed

Telegram is not needed for:

- Remote access to Hermes.
- Avoiding VPN.
- Chatting with Hermes from Android.
- Running services like reset/update/restart.
- Showing LLM questions with choices.
- Receiving structured responses.
- Managing sessions.

Cloudflare Tunnel already solves the main problem:

```text
Access home PC from outside the home without VPN
```

Telegram only adds another channel. It should not be the core transport.

---

## 6. Optional Telegram Use Later

Telegram can still be useful later as a fallback channel.

Possible use cases:

- Quick `/restart` command from any Telegram client.
- Emergency access if Android app is broken.
- Share Hermes with someone who does not have the app.
- Receive simple notifications.
- Control Hermes from desktop Telegram.

Optional architecture:

```text
Telegram App
    ↓
Telegram Servers
    ↓ webhook
Cloudflare Tunnel
    ↓
Home PC: Telegram Bridge
    ↓
Hermes Gateway
```

But this is phase 2 or later.

---

## 7. Repository Strategy

Fork the existing Android app:

```bash
git clone https://github.com/rusty4444/hermes-android.git
cd hermes-android
git remote rename origin upstream
git remote add origin git@github.com:danlil240/hermes-android.git
```

Recommended branches:

```text
main
  Stable fork branch.

upstream-main
  Mirror of the original project.

feature/home-cloudflare-profile
  Connection profile for home PC through Cloudflare Tunnel.

feature/services-ui
  Android UI for reset/update/restart/status/logs.

feature/choice-questions
  UI support for LLM questions with buttons and multiple choices.

feature/security-hardening
  API key handling, biometric lock, confirmation flows.

feature/telegram-optional
  Optional future Telegram bridge documentation/status screen.
```

---

## 8. Recommended Project Layout

Inside the fork:

```text
hermes-android/
  lib/
    core/
      config/
      network/
      auth/
      models/
      storage/

    features/
      chat/
      sessions/
      services/
      questions/
      settings/
      diagnostics/

    shared/
      widgets/
      theme/
      errors/

  docs/
    PLAN.md
    CLOUD_FLARE_TUNNEL.md
    SERVICES_API.md
    CHOICE_QUESTIONS.md
    SECURITY.md
    TELEGRAM_OPTIONAL.md
```

If backend helper code is added later, prefer a separate repository:

```text
hermes-home-backend/
  gateway/
  services-runner/
  question-engine/
  docker-compose.yml
```

Do not mix too much backend logic inside the Android repository.

---

## 9. Home PC Backend Layout

On the home PC:

```text
~/hermes-stack/
  docker-compose.yml
  .env

  hermes-gateway/
  hermes-agent/
  hermes-services-runner/
  hermes-question-engine/
  postgres/
  redis/
  cloudflared/
```

Recommended runtime layout:

```text
Home PC
│
├── hermes-gateway
│   └── HTTP API used by Android
│
├── hermes-agent
│   └── Main AI agent
│
├── hermes-services-runner
│   └── Executes approved system services
│
├── hermes-question-engine
│   └── Manages LLM choice questions
│
├── postgres
│   └── Persistent data
│
├── redis
│   └── Job queue/cache
│
└── cloudflared
    └── Exposes Gateway API to the internet
```

---

## 10. Public API Design

The Android app should talk to one main API:

```text
https://hermes-api.your-domain.com
```

Recommended endpoints:

```text
GET    /health
GET    /status

POST   /auth/login
POST   /auth/refresh
POST   /auth/logout

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

---

## 11. Android App Features

### 11.1 Connection Profile

Add a connection profile screen:

```text
Connection Name:
  Home Hermes

Gateway URL:
  https://hermes-api.daniel-lilintal.com

API Key:
  ********

Connection Mode:
  Cloudflare Tunnel

Status:
  Online / Offline
```

Features:

- Save multiple Hermes hosts.
- Test connection.
- Show latency.
- Show current server version.
- Show model status.
- Show tunnel status if backend exposes it.

---

### 11.2 Chat Screen

The chat screen should support:

- Normal messages.
- Streaming responses.
- Markdown.
- Code blocks.
- File attachments.
- Session switching.
- Retry failed message.
- Stop generation.
- Clear session.
- Export session.
- Service result cards.
- Choice question cards.

---

### 11.3 Services Screen

This is important for your use case.

Services mean operations like:

```text
reset
update
restart
status
logs
backup
restore
clear session
restart model server
restart cloudflared
restart Docker stack
```

Service categories:

```text
System
  - Check system status
  - Restart Hermes
  - Restart Hermes Gateway
  - Restart Hermes Agent
  - Restart Cloudflare Tunnel
  - Restart Ollama
  - Restart Docker stack

Update
  - Pull latest Hermes code
  - Update Android app info
  - Rebuild backend containers
  - Update model list
  - Restart after update

Session
  - Reset current session
  - Clear memory for session
  - Export session
  - Delete session

Database
  - Backup database
  - Restore database
  - Check database health

Logs
  - View Hermes logs
  - View cloudflared logs
  - View agent logs
  - Download logs
```

---

## 12. Service Safety Model

System services are dangerous. They need strict rules.

### 12.1 Risk Levels

```text
low
  Safe read-only actions.
  Example: check status, view version.

medium
  Non-destructive changes.
  Example: clear temporary cache, reload config.

high
  Restart/update operations.
  Example: restart Hermes, update containers.

critical
  Destructive or irreversible actions.
  Example: reset database, delete memory, restore backup.
```

### 12.2 Confirmation Policy

| Risk | Confirmation Required | Extra Protection |
|---|---:|---|
| Low | No | None |
| Medium | Yes | Normal confirm button |
| High | Yes | Confirm + show exact command/result |
| Critical | Yes | Type confirmation phrase or biometric unlock |

Example high-risk confirmation:

```text
Restart Hermes?

This will temporarily disconnect the Android app.

Service:
  restart_hermes

Target:
  Home PC

Estimated downtime:
  10-30 seconds

[Confirm Restart] [Cancel]
```

### 12.3 Backend Service Manifest

Each service should be defined as a manifest:

```yaml
id: restart_hermes
name: Restart Hermes
category: system
description: Restarts the Hermes backend services on the home PC.
risk_level: high
requires_confirmation: true
allowed_roles:
  - admin
command:
  type: systemd
  value: restart hermes
timeout_seconds: 60
audit: true
```

Never let the LLM directly execute arbitrary shell commands.

The LLM may request a service, but the backend validates and executes only registered services.

---

## 13. Services Runner

The Services Runner runs on the home PC.

Its job:

```text
Receive approved service request
Validate permission
Validate service manifest
Execute safe predefined command
Capture output
Save audit log
Return structured result
```

Example result:

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

---

## 14. LLM Choice Questions During Session

This means:

The LLM can ask the user a structured question with a few choices while working.

Example:

```text
User:
Update the system.

Hermes:
What should I update?

[Hermes only]
[Cloudflare Tunnel only]
[Model server only]
[Everything]
[Cancel]
```

The question should not be just plain text.

It should be a structured event.

---

## 15. Question Event Schema

### 15.1 Single Choice

```json
{
  "type": "choice_question",
  "question_id": "q_001",
  "session_id": "s_123",
  "title": "What should I update?",
  "description": "Choose one update target.",
  "mode": "single",
  "required": true,
  "options": [
    {
      "id": "hermes",
      "label": "Hermes only"
    },
    {
      "id": "cloudflared",
      "label": "Cloudflare Tunnel only"
    },
    {
      "id": "ollama",
      "label": "Model server only"
    },
    {
      "id": "everything",
      "label": "Everything"
    }
  ]
}
```

### 15.2 Multiple Choice

```json
{
  "type": "choice_question",
  "question_id": "q_002",
  "session_id": "s_123",
  "title": "Which components should I restart?",
  "mode": "multiple",
  "min_selected": 1,
  "max_selected": 4,
  "options": [
    {
      "id": "gateway",
      "label": "Gateway"
    },
    {
      "id": "agent",
      "label": "Agent"
    },
    {
      "id": "cloudflared",
      "label": "Cloudflare Tunnel"
    },
    {
      "id": "ollama",
      "label": "Ollama"
    }
  ],
  "submit_label": "Restart selected",
  "cancel_label": "Cancel"
}
```

### 15.3 Confirmation Question

```json
{
  "type": "confirmation_question",
  "question_id": "q_003",
  "session_id": "s_123",
  "title": "Confirm restart",
  "description": "Hermes will restart and the app may disconnect for a few seconds.",
  "confirm_label": "Restart Hermes",
  "cancel_label": "Cancel",
  "risk_level": "high"
}
```

---

## 16. Android Question Renderer

The Android app should render structured question blocks.

Supported renderers:

```text
choice_question mode=single
  → radio buttons / large choice buttons

choice_question mode=multiple
  → checkboxes + submit button

confirmation_question
  → confirm/cancel card

text_input_question
  → text field + submit button

number_question
  → numeric input

date_time_question
  → date/time picker
```

Recommended message block model:

```text
Message
  ├── TextBlock
  ├── ChoiceQuestionBlock
  ├── ConfirmationQuestionBlock
  ├── ServiceProgressBlock
  ├── ServiceResultBlock
  └── ErrorBlock
```

---

## 17. Android Service Renderer

Service events should appear as cards.

Example service progress card:

```text
Restarting Hermes

Status:
  Running

Steps:
  ✓ Request approved
  ✓ Stopping old service
  → Starting new service
  ○ Health check

[View logs]
```

Example result card:

```text
Hermes restarted successfully

Duration:
  12 seconds

Result:
  Gateway online
  Agent online
  Cloudflare tunnel online

[Open diagnostics]
```

---

## 18. Backend Question Flow

```text
User sends message
    ↓
Hermes Agent decides more info is needed
    ↓
Question Engine creates structured question
    ↓
Gateway sends question block to Android
    ↓
Android renders buttons
    ↓
User selects answer
    ↓
Android posts answer to Gateway
    ↓
Question Engine resumes agent run
```

This allows the LLM to ask controlled questions without creating fragile free-text flows.

---

## 19. Database Tables

Recommended tables:

```text
users
devices
api_keys
sessions
messages
message_blocks
services
service_runs
service_run_logs
questions
question_options
question_answers
audit_logs
system_status_snapshots
```

### Example: service_runs

```sql
CREATE TABLE service_runs (
    id TEXT PRIMARY KEY,
    service_id TEXT NOT NULL,
    session_id TEXT,
    requested_by_user_id TEXT NOT NULL,
    status TEXT NOT NULL,
    risk_level TEXT NOT NULL,
    confirmation_required BOOLEAN NOT NULL,
    confirmed_at TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    result_summary TEXT,
    created_at TIMESTAMP NOT NULL
);
```

### Example: questions

```sql
CREATE TABLE questions (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    mode TEXT,
    status TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    answered_at TIMESTAMP
);
```

---

## 20. Security Requirements

### 20.1 Android Security

- Store API key securely.
- Support biometric app lock.
- Hide sensitive values.
- Do not log tokens.
- Allow device logout/revoke.
- Use HTTPS only.
- Show warning for high-risk services.

### 20.2 Backend Security

- Validate every request.
- Require authentication.
- Use role-based authorization.
- Never let the LLM run arbitrary shell commands.
- Use service manifests.
- Require confirmation for risky actions.
- Keep audit logs.
- Rate-limit public endpoints.
- Restrict CORS.
- Use Cloudflare Access if needed.
- Separate read-only services from destructive services.

### 20.3 Cloudflare Tunnel Security

Recommended:

```text
Use a dedicated hostname:
  hermes-api.your-domain.com

Do not expose unnecessary ports.

Protect admin endpoints.

Use API authentication even behind Cloudflare.

Do not rely on obscurity of the URL.
```

Optional extra protection:

```text
Cloudflare Access
mTLS
IP allowlist
Short-lived tokens
Device approval
```

---

## 21. Cloudflare Tunnel Setup Concept

Cloudflare Tunnel runs on the home PC.

```text
cloudflared
    ↓ outbound connection
Cloudflare
    ↓
Public HTTPS hostname
```

Example mapping:

```yaml
tunnel: hermes-home
credentials-file: /etc/cloudflared/hermes-home.json

ingress:
  - hostname: hermes-api.daniel-lilintal.com
    service: http://localhost:8642

  - service: http_status:404
```

Android uses:

```text
https://hermes-api.daniel-lilintal.com
```

The home router does not need port forwarding.

The Android phone does not need VPN.

---

## 22. Docker Compose Concept

Example conceptual stack:

```yaml
services:
  hermes-gateway:
    image: hermes/gateway:latest
    ports:
      - "8642:8642"
    env_file:
      - .env
    depends_on:
      - postgres
      - redis

  hermes-agent:
    image: hermes/agent:latest
    env_file:
      - .env
    depends_on:
      - hermes-gateway

  hermes-services-runner:
    image: hermes/services-runner:latest
    env_file:
      - .env
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/log:/host/var/log:ro

  postgres:
    image: postgres:16
    volumes:
      - postgres_data:/var/lib/postgresql/data
    env_file:
      - .env

  redis:
    image: redis:7

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run hermes-home
    volumes:
      - ./cloudflared:/etc/cloudflared

volumes:
  postgres_data:
```

This is only a concept. The actual Hermes containers depend on the existing Hermes project structure.

---

## 23. Development Phases

### Phase 1: Direct Android → Cloudflare → Hermes

Goal:

```text
Forked Android app connects directly to Hermes on home PC.
```

Tasks:

- Fork `hermes-android`.
- Build app locally.
- Configure Hermes Gateway URL.
- Expose Gateway through Cloudflare Tunnel.
- Test health endpoint from phone.
- Test basic chat.
- Save home connection profile.

Deliverable:

```text
Android app can chat with Hermes from outside home without VPN.
```

---

### Phase 2: Home PC Diagnostics

Goal:

```text
Android app can show whether Hermes/home stack is healthy.
```

Tasks:

- Add `/status` endpoint.
- Add diagnostics screen.
- Show:
  - Gateway online/offline.
  - Agent online/offline.
  - Cloudflare tunnel status.
  - Model server status.
  - Database status.
  - Disk usage.
  - Memory usage.
  - Last error.

Deliverable:

```text
Android app shows home PC Hermes health.
```

---

### Phase 3: Services Runner

Goal:

```text
Android app can run safe predefined services.
```

Tasks:

- Define service manifest format.
- Implement service list endpoint.
- Implement service run endpoint.
- Add confirmation system.
- Add audit logs.
- Add Android Services screen.
- Add service result cards.

First services:

```text
check_status
restart_hermes
restart_gateway
restart_agent
restart_cloudflared
restart_ollama
view_logs
backup_database
```

Deliverable:

```text
Android app can safely restart/update/check Hermes services.
```

---

### Phase 4: LLM Choice Questions

Goal:

```text
Hermes can ask structured questions with buttons during a session.
```

Tasks:

- Define question schema.
- Add question table.
- Add question answer endpoint.
- Add Android renderer for single choice.
- Add Android renderer for multiple choice.
- Add Android renderer for confirmation.
- Connect agent flow to question engine.

Deliverable:

```text
The LLM can pause and ask the user to choose from buttons.
```

---

### Phase 5: Update/Reset Workflows

Goal:

```text
Hermes can guide user through system maintenance.
```

Example flow:

```text
User:
Update Hermes.

Hermes:
What should I update?

[Hermes only]
[Agent only]
[Gateway only]
[Everything]
[Cancel]

User:
Everything.

Hermes:
This will pull latest code, rebuild containers, and restart Hermes.
Continue?

[Confirm Update] [Cancel]
```

Tasks:

- Add update service.
- Add restart-after-update service.
- Add logs streaming.
- Add progress updates.
- Add rollback notes.

Deliverable:

```text
Maintenance workflows are controlled through Android.
```

---

### Phase 6: Optional Telegram Bridge

Goal:

```text
Telegram becomes secondary control/chat channel.
```

Only start this after the direct Android path works.

Tasks:

- Create Telegram bot.
- Add Telegram Bridge backend.
- Expose bridge through Cloudflare Tunnel.
- Map Telegram chat to Hermes session.
- Render simple text responses.
- Add inline buttons for choice questions.
- Add confirmation buttons for services.

Deliverable:

```text
Telegram can control Hermes, but it is not required for normal use.
```

---

## 24. MVP Definition

The MVP should include:

```text
Android fork
Cloudflare Tunnel connection
Chat with Hermes
Session list
Basic status page
Services screen
Restart Hermes service
View logs service
Single-choice LLM question
Confirmation LLM question
Audit log for services
```

MVP should not include:

```text
Telegram bridge
VPS
Complex admin dashboard
Multi-user organization system
Full marketplace of services
Complex permissions
```

---

## 25. First Concrete Implementation Steps

1. Fork the repo.
2. Build the Android app unchanged.
3. Connect it to local Hermes on LAN.
4. Expose Hermes Gateway using Cloudflare Tunnel.
5. Connect Android to Cloudflare URL.
6. Add a saved connection profile called `Home Hermes`.
7. Add `/health` and `/status` checks if missing.
8. Add basic Services screen.
9. Add `check_status` service.
10. Add `restart_hermes` service with confirmation.
11. Add question schema.
12. Add Android button renderer for questions.
13. Test full flow:
    ```text
    User: restart hermes
    Hermes: Which service?
    User chooses Hermes
    Hermes asks confirmation
    User confirms
    Service Runner restarts Hermes
    Android shows result
    ```

---

## 26. Final Recommended Architecture

Use this:

```text
Android App Fork
    ↓ HTTPS
Cloudflare Tunnel
    ↓
Hermes Gateway on Home PC
    ↓
Hermes Agent
    ├── Question Engine
    ├── Services Runner
    ├── Database
    └── Logs/Status/Updates
```

Do not use this as the main path:

```text
Android App
    ↓
Telegram
    ↓
Hermes
```

Telegram is optional later.

The main product should be:

```text
Hermes on home PC, controlled directly by your Android app through Cloudflare Tunnel.
```

---

## 27. Implementation Status & Remaining Work

> **Last updated:** 2026-05-30 — based on codebase audit of `lib/`, `test/`, `docs/`, and CI configuration.

### 27.1 Completed Features

The following plan items are **implemented and functional** in the current codebase:

| Area | Status | Key Files |
|------|--------|-----------|
| **Connection profiles** | ✅ Done | `lib/core/models/connection.dart`, `lib/core/network/connection_manager.dart`, `lib/main.dart` |
| **Secure credential storage** | ✅ Done | `lib/core/storage/secure_storage.dart` (flutter_secure_storage for API keys + dashboard creds) |
| **HTTPS + Cloudflare Tunnel support** | ✅ Done | `SavedConnection.normalizeHostAndPort()` handles HTTPS URLs, custom ports, path prefixes |
| **Reverse-proxy path prefixes** | ✅ Done | Gateway prefix + dashboard prefix, proxied dashboard mode |
| **Biometric app lock** | ✅ Done | `lib/core/auth/biometric_lock.dart` (local_auth, optional toggle) |
| **Session list** | ✅ Done | `lib/features/sessions/session_list_screen.dart` (fetch, display, create new) |
| **Chat with SSE streaming** | ✅ Done | `lib/features/chat/chat_screen.dart`, `GatewayChatClient` (token-by-token streaming via `/v1/chat/completions`) |
| **Tool progress rendering** | ✅ Done | `hermes.tool.progress` SSE events parsed and rendered as tool cards during streaming |
| **Voice input & TTS output** | ✅ Done | `speech_to_text` + `flutter_tts` integrated in chat screen |
| **LLM structured questions (all 5 types)** | ✅ Done | `lib/core/models/question.dart`, `lib/features/questions/question_widgets.dart` (single choice, multiple choice, confirmation, text input, number, date-time) |
| **Question SSE event handling** | ✅ Done | `hermes.question` SSE events parsed during streaming; question blocks extracted from message history |
| **Question answer flow** | ✅ Done | `POST /api/questions/{id}/answer` with answer payload; answered state rendered |
| **Services screen** | ✅ Done | `lib/features/services/services_screen.dart` (list, group by category, run with risk-based confirmation) |
| **Risk-based confirmation** | ✅ Done | Low/medium/high/critical risk levels; typed confirmation for critical services |
| **Service run SSE log streaming** | ✅ Done | `ServiceRunStreamController`, `lib/features/services/service_log_viewer.dart` (real-time logs, progress steps, cancel) |
| **Service run polling fallback** | ✅ Done | Falls back to 3-second polling if SSE endpoint unavailable |
| **Diagnostics screen** | ✅ Done | `lib/features/diagnostics/diagnostics_screen.dart` (`/status` endpoint, auto-refresh) |
| **Settings screen (model selection)** | ✅ Done | `lib/features/settings/settings_screen.dart` (model info, options, set model) |
| **Memory browser** | ✅ Done | `lib/features/memory/memory_screen.dart` (via DashboardClient) |
| **Cron job management** | ✅ Done | `lib/features/cron/cron_screen.dart` (list, add, edit, pause/resume/trigger, delete) |
| **Skills browser** | ✅ Done | `lib/features/skills/skills_screen.dart` (list, enabled/disabled status) |
| **Navigation drawer** | ✅ Done | All feature screens wired in drawer from session list |
| **Health check** | ✅ Done | `ApiClient.healthCheck()` validates both `/health` and authenticated `/api/sessions` |
| **CI/CD: PR quality checks** | ✅ Done | `.github/workflows/pr-quality.yml` (flutter analyze + test) |
| **CI/CD: Release APK build** | ✅ Done | `.github/workflows/build-apk.yml` (tag-triggered, signed APK) |
| **Server patch: TCP_NODELAY for SSE** | ✅ Done | `server-patches/0001-tcp-nodelay-sse.patch` |
| **Unit tests: data models** | ✅ Done | `test/models_test.dart` (ServiceDefinition, ServiceRun, Question, Session) |
| **Unit tests: connection manager** | ✅ Done | `test/connection_manager_test.dart` (SavedConnection, ApiClient, DashboardClient, SSE parsing) |
| **Responsive layout** | ✅ Done | `lib/shared/responsive.dart` (tablet grid for connection list) |

### 27.2 Remaining Work

The following items from the plan are **not yet implemented** or need additional work:

#### High Priority — MVP Gaps

| Area | Status | Notes |
|------|--------|-------|
| **Session management** | ✅ Done | Swipe-to-delete with confirmation, rename dialog, `DELETE /api/sessions/{id}` and `PATCH /api/sessions/{id}` wired in `ApiClient` and `SessionListScreen` |
| **Service audit log** | ✅ Done | "History" tab on Services screen with `GET /api/service-runs` pagination, status icons, relative timestamps, result summaries |
| **Session search/filter** | ✅ Done | Search bar on session list filtering by title, model, preview, and session ID |
| **Connection auto-retry** | ✅ Done | Health check retries with exponential backoff (3 attempts); session fetch auto-retries up to 3 times on failure |
| **Error handling polish** | ✅ Done | `ErrorMessages.format()` maps HTTP codes and network exceptions to user-friendly messages; integrated in session list and services screens |

#### Medium Priority — UX & Polish

| Area | What's Missing | Notes |
|------|----------------|-------|
| **Theme toggle UI** | ✅ Done | Dark/light/system toggle in Settings screen |
| **Voice configuration UI** | ✅ Done | Voice name and locale picker in Settings screen |
| **Verbose mode toggle UI** | ✅ Done | Verbose mode toggle in Settings screen |
| **Chat: markdown code highlighting** | ✅ Done | `CodeHighlighter` in `lib/shared/widgets/code_highlighter.dart` wired to `flutter_markdown` `MarkdownBody.syntaxHighlighter` with dark/light themes |
| **Tablet layout for chat** | ✅ Done | Chat screen constrained to 800px max width on tablets via `ConstrainedBox`; session list uses `GridView` on tablets |
| **Session export/share** | ✅ Done | Share button in chat AppBar exports transcript as Markdown via `share_plus` |
| **File/media in chat** | No attachment support | Only text messages are sent |
| **Scroll-to-bottom FAB** | ✅ Done | FAB shows whenever user is scrolled up >200px from bottom, regardless of streaming state |
| **Empty state for questions** | ✅ Done | Empty state with icon and "No messages yet" text shown when no messages or pending questions |

#### Low Priority — Hardening & Infrastructure

| Area | What's Missing | Notes |
|------|----------------|-------|
| **Push notifications** | No FCM/APNs integration | Would notify on service completion, question pending, etc. |
| **Offline caching** | No local caching of sessions or messages | Every screen requires a live connection |
| **Crash reporting** | No Crashlytics, Sentry, or similar | |
| **End-to-end integration tests** | No integration tests with a mock server | Only unit tests for models and connection manager |
| **Widget tests** | ✅ Done | `test/widget_test.dart` and `test/question_widgets_test.dart` cover QuestionCard dispatch, interaction, and all question types (22 widget tests); `test/code_highlighter_test.dart` covers syntax highlighting (6 tests) |
| **Cloudflare Tunnel setup automation** | No in-app guide or validation for tunnel setup | `docs/CLOUD_FLARE_TUNNEL.md` covers manual setup only |
| **Release signing docs** | Keystore setup documented in CI but not in README | |
| **App version display** | ✅ Done | Shown in Settings screen via `package_info_plus` |
| **Deep linking** | No deep link support for `hermes://` URLs | |

#### Optional — Phase 6 (Telegram Bridge)

| Area | What's Missing | Notes |
|------|----------------|-------|
| **Telegram bot** | Not started | Explicitly optional per plan; only after direct Android path is complete |
| **Telegram bridge backend** | Not started | |
| **Telegram inline buttons** | Not started | |

### 27.3 MVP Readiness Assessment

Per the MVP definition in Section 24, the current status is:

| MVP Item | Status |
|----------|--------|
| Android fork | ✅ Done |
| Cloudflare Tunnel connection | ✅ Done |
| Chat with Hermes | ✅ Done |
| Session list | ✅ Done |
| Basic status page | ✅ Done |
| Services screen | ✅ Done |
| Restart Hermes service | ✅ Done (depends on backend service manifest) |
| View logs service | ✅ Done (SSE log viewer) |
| Single-choice LLM question | ✅ Done |
| Confirmation LLM question | ✅ Done |
| Audit log for services | ✅ Done |

**MVP is 100% complete.** All MVP items are implemented.

### 27.4 Recommended Next Steps

1. ~~**Service audit log**~~ — ✅ Done. History tab with pagination added to Services screen.
2. ~~**Session management**~~ — ✅ Done. Swipe-to-delete and rename wired in SessionListScreen.
3. ~~**Theme + voice settings UI**~~ — ✅ Done. Toggles in Settings screen.
4. ~~**Widget tests**~~ — ✅ Done. Tests for QuestionCard (all types), CodeHighlighter, and interaction callbacks.
5. ~~**Error handling polish**~~ — ✅ Done. `ErrorMessages` utility maps HTTP codes to user-friendly messages.
6. ~~**Connection auto-retry**~~ — ✅ Done. Exponential backoff on health check and session fetch.
7. ~~**Markdown code highlighting**~~ — ✅ Done. `CodeHighlighter` wired with `flutter_markdown` using `highlight` package.
8. ~~**Tablet layout for chat**~~ — ✅ Done. Chat constrained to 800px on tablets; session list uses responsive grid.
9. **Offline caching** — Cache sessions and messages locally for offline viewing.
10. **Push notifications** — FCM integration for service completion and question alerts.
