# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Release notes for
versions prior to 1.0.7 are in the **What's new** sections of the [README](README.md).

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
