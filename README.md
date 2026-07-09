# Hermes Android

Android client for [Hermes Agent](https://hermes-agent.nousresearch.com/) — chat with your Hermes sessions from a phone or tablet over local Wi-Fi, a private Tailscale network, or a Cloudflare Tunnel.

## Current release

- Version: **1.0.10**
- Package: `com.hermesagent.hermes_android`
- Recommended APK for most modern phones: `app-arm64-v8a-release.apk`
- Other APKs: `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`
- Download: [GitHub Releases](https://github.com/danlil240/hermes-android/releases/latest)

## What's new in v1.0.10

- **SSE log streaming for service runs** — real-time log output via `GET /api/service-runs/{runId}/logs` Server-Sent Events. Falls back to polling if the SSE endpoint is unavailable.
- **Service run progress steps** — multi-phase operations (pulling code, rebuilding, restarting) now show step-by-step progress indicators on the active run card and in the full-screen log viewer.
- **Full-screen log viewer** (`ServiceLogViewer`) — terminal-style log output with color-coded lines, progress stepper, status bar, and cancel button. Accessible by tapping an active service run.
- **iOS Face ID permission** — `NSFaceIDUsageDescription` added to `Info.plist` for biometric authentication support.

## What's new in v1.0.9

- **Secure API key storage** using `flutter_secure_storage` — API keys and dashboard credentials are now stored in the Android Keystore / iOS Keychain instead of plaintext `SharedPreferences`.
- **Biometric app lock** — optional fingerprint/face unlock on app startup. Toggle from the Home screen overflow menu. Uses `local_auth`; falls back gracefully on devices without biometrics.

## What's new in v1.0.8

- **Reverse-proxy path prefixes** — configure separate path prefixes for the Gateway API and dashboard, e.g. `/profile/peter` before `/api` and `/v1`, and `/dashboard` before dashboard `/api` routes.
- **Proxied dashboard mode** — enable **Dashboard behind proxy** when nginx/Caddy/your host injects dashboard authentication. In this mode the app sends clean dashboard requests without trying to scrape a dashboard session token or perform password login.
- **Prefix-aware validation and chat** — API-key validation, session browsing, existing chat history, streaming chat completions, and dashboard drawer screens all use the configured prefixes.

## What's new in v1.0.7

- **Password-protected dashboards** — the Memory/Cron/Skills/Settings tabs now work against a dashboard secured with basic-auth, not just an open (`--insecure`) one. The app logs in via the dashboard's `/auth/password-login` flow and reuses the session cookie (the same mechanism the desktop client uses).
- **Configurable dashboard port** — set a custom dashboard port per connection when it isn't the default `9119`.
- **Dashboard details in the connection flow** — set the dashboard port/username/password while adding a connection (expand **Custom dashboard details**) or later via **⋮ → Dashboard Login**, with validation before saving.

## What's new in v1.0.6

- **Voice chat support** — tap the microphone in chat to dictate a message to Hermes, and Hermes can speak the response back.
- Spoken replies can be toggled from the chat input bar.
- Android/iOS microphone and speech-recognition permissions are included.

## Features

- **Hermes chat on Android** — browse sessions, create new chats, and send prompts to your Hermes Agent.
- **Streaming responses** — chat uses the Hermes Gateway OpenAI-compatible streaming endpoint: `POST /v1/chat/completions`. Tokens appear in real-time with smooth auto-scroll.
- **Messaging-style UI** — dark/light/system themes, gold Hermes accent color (`#D4AF37`), markdown rendering, relative timestamps, and responsive phone/tablet layouts.
- **Gold/black Hermes branding** — distinctive gold accent on black background, custom app icon with mipmap densities, agent messages use grey bubbles.
- **Gateway API integration** — sessions and chat run through the Hermes Gateway API Server, normally on port `8642`, with HTTP and HTTPS endpoints supported. Reverse-proxy deployments can set a gateway path prefix that is applied before `/api` and `/v1` routes.
- **Dashboard integrations** — Memory, Cron Jobs, Skills, and Settings screens use the Hermes dashboard API (default port `9119`, configurable per connection) on the same host. Works with open (`--insecure`) dashboards, **password-protected dashboards** via the built-in login, and proxied dashboards where auth is injected upstream.
- **Model settings** — view and change the configured Hermes model where the dashboard exposes model settings.
- **Cron management** — list, trigger, pause/resume, create, edit, and delete scheduled Hermes cron jobs.
- **Skills browser** — view available Hermes skills with descriptions and trigger conditions.
- **Memory viewer** — inspect conversation memory across sessions.
- **Verbose mode toggle** — show raw message metadata (role, tool calls, timestamps) in chat.
- **Three-way theme toggle** — Dark / Light / System default.
- **Keyboard handling** — auto-scroll on keyboard open, send action on Enter, FAB to scroll to bottom.
- **Voice chat** — microphone dictation sends recognised speech to Hermes, with optional text-to-speech replies.
- **Biometric app lock** — optional fingerprint/face unlock on app startup, with graceful fallback on devices without biometrics.
- **Secure credential storage** — API keys and dashboard credentials stored in Android Keystore / iOS Keychain via `flutter_secure_storage`.
- **Services screen** — run predefined Hermes services (restart, update, status, logs) with risk-based confirmation and real-time SSE log streaming.
- **Diagnostics screen** — view Hermes stack health (gateway, agent, tunnel, model server, database) with auto-refresh.
- **Structured LLM questions** — the agent can ask single-choice, multiple-choice, confirmation, text-input, number, and date-time questions during a chat, rendered as interactive cards.
- **Session management** — swipe-to-delete with confirmation, rename sessions, search/filter by title, model, or preview.
- **Session export/share** — share a chat transcript as Markdown via the system share sheet.
- **Markdown code highlighting** — syntax-highlighted code blocks in chat with dark/light theme support.
- **Cloudflare Access service tokens** — `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers sent on every request when configured, for tunnels protected by Cloudflare Access.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-session-list.jpg" width="220" alt="Session list"><br><sub>Session list</sub></td>
    <td align="center"><img src="docs/screenshots/02-navigation-drawer.jpg" width="220" alt="Navigation drawer"><br><sub>Navigation drawer</sub></td>
    <td align="center"><img src="docs/screenshots/03-cron-jobs.jpg" width="220" alt="Cron jobs"><br><sub>Cron jobs</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/04-add-cron-job.jpg" width="220" alt="Add cron job"><br><sub>Add cron job</sub></td>
    <td align="center"><img src="docs/screenshots/05-memory.jpg" width="220" alt="Memory"><br><sub>Memory</sub></td>
    <td align="center"><img src="docs/screenshots/06-settings.jpg" width="220" alt="Settings"><br><sub>Settings</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/07-skills.jpg" width="220" alt="Skills"><br><sub>Skills</sub></td>
  </tr>
</table>

## Quick start

### Prerequisites

- Android device or emulator (Android 8+).
- Hermes Agent installed on the host machine.
- Hermes Gateway API Server reachable from the Android device — via LAN, Tailscale, or Cloudflare Tunnel.
- `API_SERVER_KEY` from the Hermes host environment (`~/.hermes/.env`).
- Optional: Hermes dashboard reachable for Memory/Cron/Skills/Settings screens.
- For development: Flutter SDK, Android Studio (or Android SDK + command-line tools).

Hermes Agent docs: <https://hermes-agent.nousresearch.com/docs>

### Install the APK

Download the latest APK from the [GitHub Releases](https://github.com/danlil240/hermes-android/releases/latest) page.

For most Android phones, install the arm64 APK:

```bash
adb install app-arm64-v8a-release.apk
```

If sideloading directly on Android, enable **Install unknown apps** for your browser or file manager, then open the downloaded APK.

### 1. Start the Gateway API Server

The Android chat/session features connect to the Hermes Gateway API Server. It must bind to an address your phone can reach, not only `127.0.0.1`.

Use your normal Hermes gateway/API-server startup command and confirm:

- host/IP is reachable from Android
- port is usually `8642`
- `API_SERVER_KEY` is available in `~/.hermes/.env`

### 2. Optional: start the dashboard for drawer features

Memory, Cron Jobs, Skills, and Settings use the Hermes dashboard API (default port `9119`).

Open dashboard (no login):

```bash
hermes dashboard --insecure --host 0.0.0.0 --tui --port 9119
```

Password-protected dashboard (recommended on shared networks) — start it with a
basic-auth provider instead of `--insecure`, then enter the username/password in
the app's **Dashboard / Proxy Settings** dialog (see [Dashboard access](#4-optional-configure-dashboard-access)).

> `--host 0.0.0.0` is required when connecting from another device. A localhost-only dashboard cannot be reached from Android.

### 3. Connect the app

1. Put the Android device and Hermes host on the same Wi-Fi/LAN (or connect via Tailscale — see below).
2. Find the Hermes host IP:

   ```bash
   # macOS
   ipconfig getifaddr en0

   # Linux
   hostname -I | awk '{print $1}'
   ```

3. Open the Hermes Android app.
4. Tap **+** to add a connection.
5. Enter:
   - **Label:** any name, e.g. `Home`
   - **Host:** the host IP, e.g. `192.168.1.50`
   - **Port:** `8642`
   - **API Key:** `API_SERVER_KEY` from the Hermes machine
6. If your deployment is behind a reverse proxy path, expand **Custom proxy and dashboard details** and set the gateway/dashboard prefixes there. Do not put URL paths in the Host field; the Host field is just the scheme, hostname, and optional port.
7. Tap the saved connection to browse sessions.
8. Tap a session to start chatting, or create a new one.

### 4. Optional: configure dashboard access

The drawer screens (Memory, Cron Jobs, Skills, Settings) talk to the Hermes
dashboard, which can run on a different port from the Gateway API Server and may
be password-protected. Configure it per connection — either while adding the
connection (expand **Custom proxy and dashboard details** in the Add Connection dialog) or
afterwards:

1. On the connections list, tap the **⋮** menu on a connection → **Dashboard / Proxy Settings**.
2. Fill in:
   - **Gateway path prefix** — optional reverse-proxy path before gateway `/api`
     and `/v1` routes, e.g. `/profile/peter`.
   - **Dashboard path prefix** — optional reverse-proxy path before dashboard
     `/api` routes, e.g. `/dashboard`.
   - **Dashboard behind proxy** — enable this when the proxy injects dashboard
     authentication and the app should not fetch a dashboard SPA token or log in
     with username/password.
   - **Dashboard Port** — leave blank to use the default (`9119` for HTTP, or the
     same external port for HTTPS deployments), or set an explicit port if your
     dashboard is exposed elsewhere.
   - **Username / Password** — only for a password-protected dashboard. Leave
     both blank for an open (`--insecure`) dashboard.
3. Tap **Save**. The app validates the settings against the dashboard before
   storing them.

When credentials are set, the app authenticates via the dashboard's
`/auth/password-login` flow and reuses the returned session cookie — the same
mechanism the Hermes desktop client uses.

## Connect remotely with Tailscale

Tailscale gives your phone and Hermes machine a private encrypted network, so you do **not** need to expose Hermes directly to the public internet.

Tailscale website: <https://tailscale.com/>

### Install Tailscale on Android

1. Install Tailscale for Android: <https://tailscale.com/download/android>
2. Sign in with the same Tailscale account/tailnet used by your Hermes machine.
3. Leave Tailscale connected while using the Hermes app.

### Install Tailscale on the Hermes machine

Install Tailscale for your OS: <https://tailscale.com/download>

Examples:

```bash
# macOS with Homebrew
brew install --cask tailscale

# Debian/Ubuntu
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

After the Hermes machine is connected, get its Tailscale address:

```bash
tailscale ip -4
```

You can also enable MagicDNS and use the machine name instead of the `100.x.y.z` IP:

- MagicDNS docs: <https://tailscale.com/kb/1081/magicdns>

### Connect the app over Tailscale

In the Android app connection dialog:

- **Host:** the Hermes machine Tailscale IP, e.g. `100.64.12.34`, or its MagicDNS name
- **Port:** `8642`
- **API Key:** `API_SERVER_KEY`

If using Memory/Cron/Skills/Settings remotely, keep the dashboard reachable on the same Tailscale host at port `9119`.

## Connect over Cloudflare Tunnel

Cloudflare Tunnel exposes your home-PC Hermes to the internet over HTTPS without router port forwarding or VPN. The Android app connects to a public URL (e.g. `https://hermes-api.your-domain.com`) and Cloudflare routes traffic through the tunnel to your Hermes Gateway and dashboard.

```text
Android app → HTTPS → Cloudflare public hostname → tunnel → Home PC Hermes
```

### 1. Install cloudflared

Install `cloudflared` on the Hermes host machine. See the official guide: <https://developers.cloudflare.com/tunnel/setup/>

### 2. Create a tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create hermes-home
# note the tunnel UUID and credentials JSON path
```

### 3. Configure ingress with path-based routing

The Gateway API (port `8642`) and the dashboard (port `9119`) run on different ports. Use path-based ingress rules to route requests to the correct backend:

`/etc/cloudflared/config.yml` (or `./cloudflared/config.yml` if running in Docker):

```yaml
tunnel: hermes-home
credentials-file: /etc/cloudflared/<UUID>.json

ingress:
  # Gateway API routes → port 8642
  - hostname: hermes-api.your-domain.com
    path: /api/sessions*
    service: http://hermes-gateway:8642
  - hostname: hermes-api.your-domain.com
    path: /v1/*
    service: http://hermes-gateway:8642

  # Dashboard routes (everything else) → port 9119
  - hostname: hermes-api.your-domain.com
    service: http://hermes-gateway:9119

  - service: http_status:404
```

> Replace `hermes-gateway` with your actual container name (if using Docker) or `localhost` (if running directly on the host).

### 4. Route DNS and start the tunnel

```bash
cloudflared tunnel route dns hermes-home hermes-api.your-domain.com
cloudflared tunnel run hermes-home

# Or install as a persistent service:
sudo cloudflared service install
```

### 5. Run cloudflared in Docker (bridge network)

If `cloudflared` runs in a Docker container on a bridge network, `localhost` inside the container refers to the container itself — not the host. Use one of these approaches:

**Same Docker network (recommended):** Put `cloudflared` and `hermes-gateway` on the same Docker network and use the container name:

```yaml
# docker-compose.yml
services:
  hermes-gateway:
    # no ports needed — cloudflared reaches it internally
    networks:
      - hermes-net

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run hermes-home
    volumes:
      - ./cloudflared:/etc/cloudflared
    networks:
      - hermes-net
    depends_on:
      - hermes-gateway

networks:
  hermes-net:
    driver: bridge
```

Then in `config.yml`, use `http://hermes-gateway:8642` and `http://hermes-gateway:9119`.

**Host machine:** If Hermes runs on the host (not in Docker), add `extra_hosts` and use `host.docker.internal`:

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel run hermes-home
    volumes:
      - ./cloudflared:/etc/cloudflared
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Then in `config.yml`, use `http://host.docker.internal:8642` and `http://host.docker.internal:9119`. The Hermes Gateway and dashboard must bind to `0.0.0.0` (not `127.0.0.1`) for the container to reach them.

### 6. Verify the tunnel

```bash
# Gateway (should return sessions JSON)
curl https://hermes-api.your-domain.com/api/sessions \
  -H "Authorization: Bearer <API_SERVER_KEY>" \
  -H "CF-Access-Client-Id: <CF_CLIENT_ID>" \
  -H "CF-Access-Client-Secret: <CF_CLIENT_SECRET>"

# Dashboard (should return model info JSON)
curl https://hermes-api.your-domain.com/api/model/info \
  -H "CF-Access-Client-Id: <CF_CLIENT_ID>" \
  -H "CF-Access-Client-Secret: <CF_CLIENT_SECRET>"
```

### 7. Point the app at it

In the app's **Add Connection** dialog:

| Field | Value |
|-------|-------|
| **Label** | any name, e.g. `Home Hermes` |
| **Host** | `https://hermes-api.your-domain.com` |
| **Port** | leave blank (defaults to 443 for HTTPS) |
| **API Key** | `API_SERVER_KEY` from the Hermes machine |
| **CF Access Client ID** | Service Token Client ID from Cloudflare Access |
| **CF Access Client Secret** | Service Token Client Secret from Cloudflare Access |

For dashboard drawer features (Memory, Cron, Skills, Settings), configure auth via **⋮ → Dashboard / Proxy Settings**:

- If the dashboard is **password-protected**: enter **Username** and **Password**, leave **Dashboard behind proxy** off. The app logs in via `/auth/password-login` and reuses the session cookie.
- If the dashboard runs with **`--insecure`** (no auth): enable **Dashboard behind proxy** so the app sends clean requests without trying to scrape a session token.
- **Dashboard Port**: leave blank — for HTTPS connections the app uses the same port as the gateway (443).
- **Dashboard Host**: set this when the dashboard is on a different subdomain than the Gateway API (e.g. dashboard at `hermes.example.com`, API at `hermes-api.example.com`). Leave blank to use the same host as the gateway.

### Cloudflare Access service tokens

When Cloudflare Access protects your tunnel, every request must include `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers or Cloudflare returns **403 Forbidden**. The app sends these headers on every Gateway API and Dashboard request when the fields are filled in.

**Three-layer protection:**

1. **Cloudflare Access service token** — `CF-Access-Client-Id` + `CF-Access-Client-Secret` headers let the request through Cloudflare Access.
2. **Hermes API key** — `Authorization: Bearer <API_SERVER_KEY>` header authenticates against the Gateway API Server.
3. **Cloudflare Tunnel** — encrypted connection from Cloudflare's edge to your home PC, no open ports.

**Creating a service token in Cloudflare Access:**

1. Go to **Cloudflare Zero Trust → Access → Service Tokens**.
2. Click **Create Service Token**.
3. Copy the **Client ID** and **Client Secret** (shown only once).
4. Create an Access policy that requires the service token for your Hermes hostname.

Enter the Client ID and Client Secret in the app's **Add Connection** dialog (or **⋮ → Dashboard / Proxy Settings** for existing connections). The app stores them securely and sends them as headers on every request.

### Cloudflare Tunnel security notes

- Keep the Gateway API key required even behind Cloudflare — do not rely on URL obscurity.
- Cloudflare Access service tokens add an authentication layer in front of the tunnel — use them for production deployments.
- Optional additional hardening: mTLS, IP allowlist.
- See [`docs/CLOUD_FLARE_TUNNEL.md`](docs/CLOUD_FLARE_TUNNEL.md) for a concise setup reference.

## Connect over HTTPS

For hosted/reverse-proxy deployments (e.g., Hugging Face Spaces, VPS with nginx/Caddy), enter the full HTTPS URL in the **Host** field:

```text
https://your-hermes-host.example.com
```

If no port is included, the app uses port `443`. If your HTTPS service uses a custom port, either include it in the URL (`https://host.example.com:8443`) or set the Port field to that value before connecting.

For HTTPS connections, dashboard drawer screens use the same external HTTPS port. For local HTTP/LAN connections, chat uses port `8642` and dashboard screens use port `9119`.

### Reverse-proxy paths

If your proxy exposes Hermes under URL paths, keep the **Host** field to the origin only and put paths in **Custom proxy and dashboard details**:

```text
Host: https://your-hermes-host.example.com
Port: 443
Gateway path prefix: /profile/peter
Dashboard path prefix: /dashboard
Dashboard behind proxy: on, if the proxy injects dashboard auth
```

With that setup, the app calls gateway routes such as
`https://your-hermes-host.example.com/profile/peter/v1/chat/completions` and
dashboard routes such as
`https://your-hermes-host.example.com/dashboard/api/model/info`.

### Security notes

- Prefer Tailscale/VPN or Cloudflare Tunnel for remote use.
- Do not port-forward the Gateway API Server or dashboard directly to the public internet.
- Rotate `API_SERVER_KEY` if it is shared or exposed.
- Local/Tailscale examples use HTTP, so the private network boundary matters. Use HTTPS for public or hosted endpoints.
- Cloudflare Tunnel provides HTTPS automatically — no need to manage TLS certificates.

## Architecture

```text
Android app (Flutter)
├─ Gateway API Server, port 8642 or HTTPS proxy prefix
│  ├─ GET /api/sessions
│  ├─ GET /api/sessions/{id}/messages
│  └─ POST /v1/chat/completions  (SSE streaming)
└─ Hermes dashboard, port 9119 or HTTPS proxy prefix
   ├─ /api/memory
   ├─ /api/cron/jobs
   ├─ /api/skills
   └─ /api/model/*

Connection modes:
├─ LAN/Wi-Fi     → http://<host-ip>:8642 (gateway) + :9119 (dashboard)
├─ Tailscale     → http://<tailscale-ip>:8642 + :9119
├─ Cloudflare    → https://hermes-api.your-domain.com (path-based routing)
└─ HTTPS proxy   → https://your-host:443 (with path prefixes)
```

## Using the app

### Chat screen

- **Send messages** — Type in the input field and tap the send button or press Enter.
- **Streaming responses** — The agent's response appears token-by-token in real-time. The chat auto-scrolls to the bottom as new tokens arrive.
- **Tool progress** — When the agent uses tools, inline progress messages show the tool name, status, and progress.
- **Verbose mode** — Toggle in the app settings to show raw message metadata (role, tool call IDs, timestamps).
- **Markdown rendering** — Assistant messages render markdown (code blocks, tables, lists, links).
- **Relative timestamps** — Messages show "2m ago", "3h ago", etc.

### Voice chat

The chat input bar has two voice controls:

| Button | Icon | What it does |
|--------|------|-------------|
| **Mic** | 🎤 / 🎤🔴 | Tap to start voice dictation. Speak your message — it appears in the input field and sends automatically when you pause. Tap again (or the red stop icon) to cancel. |
| **Voice reply toggle** | 🔊 / 🔇 | Toggles whether Hermes reads its response aloud after a voice-input message. On = 🔊 (volume up), Off = 🔇 (volume off). |

**How voice replies work:**

1. Tap the mic, speak your question, and wait for the recognition to finish (the text appears and auto-sends).
2. Hermes streams its response as text in the chat as usual.
3. After the full response arrives, if the voice reply toggle is on (🔊), the app reads the response aloud using text-to-speech.

Voice replies **only** trigger when you send a message via the mic button. Typed messages produce text responses only.

#### Setting up text-to-speech (Android)

Spoken replies require Google Text-to-Speech to be installed and configured on your device. The app uses the device's built-in TTS engine — it does not bundle its own voices.

**Step-by-step:**

1. **Install Google Text-to-Speech** — If not already on your device, install from the Play Store: [Google Text-to-Speech](https://play.google.com/store/apps/details?id=com.google.android.tts)
2. **Set as default engine** — Settings → Accessibility → Text-to-speech output → Preferred engine → **Google Text-to-Speech**
3. **Download voice data** — In the same TTS settings screen, tap the gear icon ⚙️ next to Google Text-to-Speech → Install voice data → select **English (Australia)** or your preferred English voice → download
4. **Check media volume** — TTS uses the **media** audio stream, not the ringer. Turn up media volume and make sure your phone isn't in silent/vibrate-only mode.
5. **Test TTS** — In the TTS settings screen, tap "Play" to hear a test phrase. If you hear it, the app should work.

**Troubleshooting voice:**

- **Mic button does nothing** — Speech recognition may be unavailable on your device. Ensure Google app is installed and has microphone permission.
- **Voice reply toggle is on (🔊) but Hermes doesn't speak** — Google TTS is likely not installed or has no voice data downloaded. Follow the TTS setup steps above.
- **Hermes speaks quietly or too fast** — Adjust speech rate and volume in Settings → Accessibility → Text-to-speech output.
- **Recognition is inaccurate** — Speak clearly, reduce background noise, and check that the device's system language includes English.

### Session list

- Browse all Hermes sessions.
- Tap a session to open its chat.
- Pull to refresh the session list.
- Create a new session from the session list header.

### Navigation drawer (☰)

Access these dashboard-powered screens:

- **Memory** — View conversation memory across sessions. Shows stored facts, preferences, and project context.
- **Cron Jobs** — List all scheduled cron jobs. Trigger, pause/resume, create, edit, or delete jobs.
- **Skills** — Browse available Hermes skills with descriptions and trigger conditions.
- **Settings** — View and change the configured Hermes model, theme preference, and verbose mode.

### Theme

- Three-way toggle: **Dark** / **Light** / **System default**.
- Gold Hermes accent (`#D4AF37`) on dark mode; adapted for light mode.

### Cron job management

The Cron Jobs screen supports full CRUD:

- **List** — See all jobs with status (enabled/disabled), next run, and schedule.
- **Create** — Tap **+** to add a new job with schedule (cron expression or interval), prompt, and optional skills.
- **Edit** — Tap a job to modify its schedule, prompt, skills, or status.
- **Trigger** — Manually run a job immediately.
- **Pause/Resume** — Toggle job enabled state.
- **Delete** — Remove a job (with confirmation).

## Development

### Run in an Android emulator

1. Install **Android Studio** (or the Android SDK + command-line tools) and create an **x86_64** emulator AVD:

   ```bash
   flutter emulators          # list available AVDs
   flutter emulators --launch <emulator_id>
   ```

2. Run the app:

   ```bash
   cd hermes-android
   flutter pub get
   flutter run -d android
   ```

   If multiple devices are connected, target the emulator explicitly:

   ```bash
   flutter devices            # find the emulator's device id
   flutter run -d <device_id>
   ```

3. **Network access from the emulator:**
   - The emulator has its own virtual network. `10.0.2.2` routes to the host machine's `localhost`.
   - For a **LAN Hermes host** (e.g. `192.168.0.100`): use that IP directly — the emulator has outbound LAN access.
   - For a **Cloudflare Tunnel** deployment: use the public URL (e.g. `https://hermes-api.your-domain.com`) — the emulator has full internet access.

   | Hermes location | Host field in the app |
   |-----------------|----------------------|
   | Host PC localhost (port 8642) | `10.0.2.2` |
   | Another LAN machine | that machine's LAN IP |
   | Cloudflare Tunnel | `https://hermes-api.your-domain.com` |

4. **Hot reload** while editing: press **r** (hot reload), **R** (hot restart), **q** (quit).

### Run tests and analysis

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d android
```

## Build release APKs

```bash
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
mkdir -p release-apks
cp build/app/outputs/flutter-apk/app-*-release.apk release-apks/
```

Output files:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
```

## Release checklist

Every release PR must complete [`CODE_QUALITY_CHECKLIST.md`](CODE_QUALITY_CHECKLIST.md) before tagging or publishing APKs. The checklist covers analysis, architecture, UX, security, release, and manual smoke-test checks.

Minimum release flow:

1. Update `pubspec.yaml` version (`version: X.Y.Z+versionCode`).
2. Update `CHANGELOG.md` with a new `## [X.Y.Z]` section.
3. Complete `CODE_QUALITY_CHECKLIST.md` and record any exceptions in the release PR.
4. Commit: `git commit -m "release: vX.Y.Z"`.
5. Tag: `git tag vX.Y.Z`.
6. Push: `git push origin HEAD --tags` — this triggers the CI workflow (`.github/workflows/build-apk.yml`) which builds signed APKs and creates a GitHub Release automatically.
7. Verify the CI build passed and APKs are attached to the release.

See `.windsurf/workflows/release.md` for the full release workflow, including hotfix and pre-release/beta procedures.

## Troubleshooting

### I can see sessions but dashboard drawer screens fail

Chat/session features use port `8642`. Memory, Cron Jobs, Skills, and Settings use the dashboard on port `9119`. Start the dashboard with `--host 0.0.0.0` and make sure port `9119` is reachable over Wi-Fi or Tailscale.

### Chat fails with an auth error

Check that the Android connection's API key matches `API_SERVER_KEY` from the Hermes machine (`~/.hermes/.env`).

### The app cannot find the host

- Verify phone and host are on the same Wi-Fi or same Tailscale tailnet.
- Try the raw IP before a hostname.
- Check local firewall rules for ports `8642` and `9119`.
- On Android, ensure the app has network permission (granted by default).

### Streaming stops or messages don't appear

- The SSE connection may have timed out. Pull to refresh the session list and re-enter the chat.
- Check that the Gateway API Server is running and responsive: `curl http://<host>:8642/api/sessions`.
- If using a reverse proxy, ensure it supports long-lived SSE connections (no aggressive timeouts).

### Dashboard screens show empty or error

- Verify the dashboard is running with `--host 0.0.0.0` (an open dashboard also needs `--insecure`).
- If the dashboard is password-protected, set the username/password under **⋮ → Dashboard / Proxy Settings** (or **Custom proxy and dashboard details** when adding the connection). A 401 here means the credentials are wrong.
- If the dashboard sits behind a reverse-proxy path, set **Dashboard path prefix**. If the proxy injects dashboard auth, enable **Dashboard behind proxy** so the app sends clean requests.
- Check the dashboard port matches the connection (default `9119` for local/Tailscale, same HTTPS port for hosted; override it in Dashboard / Proxy Settings if needed).
- The dashboard must be on the same host as the Gateway API Server for the app's drawer to reach it.
- **Over Cloudflare Tunnel**: ensure the tunnel ingress routes dashboard paths (`/api/memory`, `/api/cron/jobs`, `/api/skills`, `/api/model/*`, `/auth/*`) to port `9119` and gateway paths (`/api/sessions`, `/v1/*`) to port `8642`. See [Connect over Cloudflare Tunnel](#connect-over-cloudflare-tunnel).
- **Over Cloudflare Tunnel with `--insecure` dashboard**: enable **Dashboard behind proxy** in Dashboard / Proxy Settings so the app skips token scraping (which fails through the tunnel) and sends clean requests directly.

### Voice dictation or spoken replies aren't working

- **Spoken replies not working** — Install Google Text-to-Speech, set it as the default engine, and download English voice data. See [Setting up text-to-speech](#setting-up-text-to-speech-android) above for step-by-step instructions.
- **Speech recognition not working** — Ensure the Google app is installed and has microphone permission (Settings → Apps → Hermes → Permissions → Microphone).
- **Voice reply toggle is off** — Check the speaker icon in the chat input bar: 🔊 = on, 🔇 = off. Tap it to enable spoken replies.
- **Media volume is zero** — TTS uses the media audio stream, not the ringer. Turn up media volume with the physical volume buttons while on the home screen.
- **Hermes speaks but audio is quiet or fast** — Adjust speech rate and volume in Settings → Accessibility → Text-to-speech output.

### Host field examples

The app accepts any of these forms and normalizes them when saving:

```text
192.168.1.50
192.168.1.50:8642
http://192.168.1.50:8642
100.64.12.34
hermes-machine.tailnet-name.ts.net
https://your-hermes-host.example.com
https://your-hermes-host.example.com:8443
```

For hosted paths such as `https://your-hermes-host.example.com/profile/peter`, enter `https://your-hermes-host.example.com` as the host and `/profile/peter` as the **Gateway path prefix**.

## Project structure

```text
lib/
├── main.dart                          # App shell, saved connections, navigation drawer
├── core/
│   ├── auth/                          # Authentication utilities
│   ├── config/                        # Configuration constants
│   ├── models/
│   │   ├── connection.dart            # SavedConnection model and host normalization
│   │   └── session.dart               # Session model
│   ├── network/
│   │   └── connection_manager.dart    # Saved connections, Gateway API, Dashboard API
│   └── ...
├── features/
│   ├── chat/                          # Chat screen with SSE streaming
│   ├── sessions/                      # Session browser
│   ├── cron/                          # Cron job manager
│   ├── memory/                        # Memory viewer
│   ├── skills/                        # Skills browser
│   ├── services/                      # Service log viewer
│   ├── settings/                      # Model/theme/app settings
│   └── diagnostics/                   # Diagnostics screen
├── shared/
│   ├── errors/                        # Error handling widgets
│   ├── theme/                         # Theme definitions
│   ├── widgets/                       # Shared UI components
│   └── responsive.dart                # Phone/tablet breakpoints
└── assets/
    └── icon/
        └── icon.png                   # App icon source
```

## Credits

- **grunjol** — contributed PR #68: reverse-proxy path prefix and proxied dashboard support.
- **sternbergm** — contributed PR #67: password-protected dashboards and configurable dashboard port.

## License

MIT
