# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Release notes for
versions prior to 1.0.7 are in the **What's new** sections of the [README](README.md).

## [1.0.21]

### Fixed
- **Silent automatic session naming** — removed the `Session titled...` snackbar; automatic names are now assigned without interrupting the user.

## [1.0.20]

### Fixed
- Removed a stale unused import that caused the Flutter release analysis gate to fail.

## [1.0.19]

### Fixed
- **Hidden one-time Android context** — Android prompts are sent as a hidden session-level system instruction instead of visible text appended to every user message.
- **Automatic session naming UX** — auto-assigned names no longer show a Rename action or dialog at the start of a chat.
- **SSE question compatibility** — wrapped Hermes question events and CRLF-delimited SSE frames are handled correctly.

## [1.0.18]

### Added
- **Android prompt context** — prompts sent from Android now identify the mobile client and its capabilities to Hermes.
- **Structured choice guidance** — Hermes is instructed to use native structured questions and buttons for choices instead of plain-text options.

## [1.0.17]

### Added
- **Active runs tracking** — background work (chats, services, questions, reconnections) is now tracked with unified status monitoring and lifecycle management via `ActiveRunsManager`.
- **Smart session titles** — sessions now get intelligently generated titles from preview, timestamp, or ID when no title is set, with placeholder detection and `hasGeneratedTitle` tracking.

## [1.0.16]

### Added
- **Instant connection startup** — with one saved connection, the app now opens it directly; with multiple connections, it reopens the last-used connection.
- **Session and conversation cache** — session lists and chat history render immediately from a per-connection local cache while the server refreshes in the background.
- **Background synchronization** — cached sessions and changed conversations refresh periodically without opening each session.

## [1.0.15]

### Fixed
- **Notification conversation refresh** — tapping a reply notification now refreshes the open conversation from the server, so the completed answer appears immediately instead of requiring a trip through All Sessions.

## [1.0.14]

### Fixed
- **Server-owned chat runs** — Android now submits `POST /v1/runs` and only polls the run status. Closing or swiping away the app can no longer cancel the Hermes agent execution.
- **Reconnectable conversation sync** — when the app returns, it reads the completed server-side session from the Hermes API.

## [1.0.13]

### Fixed
- Updated the Flutter 3.44 lint cleanup and test theme setup so release
  analysis and widget tests pass reliably in CI.

## [1.0.12]

### Fixed
- **Android chat work now survives leaving the app** — each user-initiated
  Hermes reply is owned by an Android foreground data-sync service, rather than
  by the chat screen or Flutter activity.
- **Reply notifications while away from the app** — Android asks for notification
  permission on first use and shows a reply (or failure) notification when the
  activity is no longer visible.

## [1.0.11]

### Fixed
- **Chat sessions no longer fail when the app is exited mid-response** — the
  streaming request now has its own HTTP client and can finish independently
  from the chat screen's lifecycle.

## [1.0.10]

### Added
- **SSE log streaming for service runs** — real-time log output via
  `GET /api/service-runs/{runId}/logs` Server-Sent Events. Falls back to
  polling if the SSE endpoint is unavailable.
- **Service run progress steps** — multi-phase operations (pulling code,
  rebuilding, restarting) now show step-by-step progress indicators on
  the active run card and in the full-screen log viewer.
- **Full-screen log viewer** (`ServiceLogViewer`) — terminal-style log
  output with color-coded lines, progress stepper, status bar, and
  cancel button. Accessible by tapping an active service run.
- **iOS Face ID permission** — `NSFaceIDUsageDescription` added to
  `Info.plist` for biometric authentication support.
- **Unit tests for `ServiceRunStep` and `ServiceRunProgress`** models,
  covering SSE event parsing, status transitions, and edge cases.

## [1.0.9]

### Added
- **Secure API key storage** using `flutter_secure_storage` — API keys and
  dashboard credentials are now stored in the Android Keystore / iOS Keychain
  instead of plaintext `SharedPreferences`.
- **Biometric app lock** — optional fingerprint/face unlock on app startup.
  Toggle from the Home screen overflow menu. Uses `local_auth`; falls back
  gracefully on devices without biometrics.
- **Unit tests for data models** — `ServiceDefinition`, `ServiceRun`,
  `Question`, and `Session` parsing and edge cases.

### Changed
- `ConnectionManager` methods (`saveConnection`, `updateApiKey`,
  `updateDashboardAuth`, `deleteConnection`) are now async to support
  secure storage writes.
- `getConnectionsWithSecrets()` async method loads connections with
  secrets merged from secure storage.

## [1.0.8]

### Added
- **Reverse-proxy path prefixes** for Gateway API and dashboard routes. Gateway
  prefixes are applied before `/api` and `/v1` routes; dashboard prefixes are
  applied before dashboard `/api` routes.
- **Proxied dashboard mode** for deployments where nginx/Caddy/another proxy
  injects dashboard authentication. In this mode the app sends clean dashboard
  requests without scraping the SPA token or using password login.
- **Dashboard / Proxy Settings** can edit gateway prefix, dashboard prefix,
  proxied-dashboard mode, dashboard port, and dashboard credentials after a
  connection is created.

### Fixed
- Existing chat history, streaming chat completions, session browsing, API-key
  validation, and dashboard validation now consistently use configured path
  prefixes.

## [1.0.7]

### Added
- Support for **password-protected dashboards**: the Memory, Cron Jobs, Skills,
  and Settings screens now authenticate against a basic-auth dashboard via the
  `/auth/password-login` flow and reuse the returned session cookie. Open
  (`--insecure`) dashboards continue to work via the existing token scrape.
- **Configurable dashboard port** per connection (`dashboardPortOverride`),
  defaulting to the previous behaviour (`9119` for HTTP, the external port for
  HTTPS) when unset.
- **Dashboard details in the Add Connection dialog** under a collapsible
  "Custom dashboard details" section, plus a **Dashboard Login** entry on each
  connection's overflow menu. Both validate the dashboard before saving.

### Changed
- `DashboardClient` accepts an optional `http.Client` for testability and
  de-duplicates concurrent login / token requests.

### Fixed
- Updating a connection's API key no longer clears its saved dashboard settings.
