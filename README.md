# Hermes Android

Chat with your Hermes Agent from your phone or tablet — at home or anywhere in the world.

The app connects to your Hermes server over your home Wi-Fi, a private Tailscale network, or a secure Cloudflare Tunnel. No complicated setup, no router changes, no open ports.

---

## New here? Start here.

**You need three things to use this app:**

1. **The Hermes app on your phone** — download and install it (see below).
2. **A Hermes server running on your computer** — this is the AI agent you'll chat with.
3. **A way for your phone to reach your computer** — pick one:

| Method | Best for | What you need |
|--------|----------|---------------|
| **Home Wi-Fi** | At home, same network | Your computer's IP address |
| **Tailscale** | Away from home, private | Free Tailscale account on both devices |
| **Cloudflare Tunnel** | Away from home, public URL | A domain name + Cloudflare account |

> **Not sure which to pick?** If you only use the app at home, use **Home Wi-Fi**. If you want to chat from anywhere without a VPN, use **Cloudflare Tunnel**. If you already use Tailscale, use that.

---

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

## Install the app

1. Download the latest APK from the [GitHub Releases](https://github.com/danlil240/hermes-android/releases/latest) page.
2. For most Android phones, choose **`app-arm64-v8a-release.apk`**.
3. Open the downloaded file on your phone. If asked, allow your browser or file manager to **install unknown apps**.
4. Once installed, open **Hermes** from your app drawer.

> **Using `adb`?** `adb install app-arm64-v8a-release.apk`

---

## Method 1: Connect over Home Wi-Fi

Use this if your phone and Hermes computer are on the same Wi-Fi network.

### What you need

- Your Hermes server running on your computer
- Your computer's IP address on the home network (e.g. `192.168.1.50`)
- The API key from your Hermes setup (found in `~/.hermes/.env` on your computer)

### Step 1: Find your computer's IP address

On your Hermes computer, open a terminal and run:

```bash
# macOS
ipconfig getifaddr en0

# Linux
hostname -I | awk '{print $1}'
```

Note down the IP address it shows (e.g. `192.168.1.50`).

### Step 2: Make sure Hermes is reachable

Your Hermes Gateway API Server needs to be running and reachable from other devices on the network (not just `localhost`). The default port is `8642`.

### Step 3: Add the connection in the app

1. Open the Hermes app on your phone.
2. Tap the **+** button (bottom right).
3. Fill in the fields:

   | Field | What to type |
   |-------|-------------|
   | **Label** | Any name you like, e.g. `Home` |
   | **Host** | Your computer's IP, e.g. `192.168.1.50` |
   | **Port** | `8642` (already filled in — leave as is) |
   | **API Key** | The API key from your Hermes computer |

4. Tap **Connect**. The app will test the connection and save it.
5. Tap your new connection to start chatting!

### Optional: Dashboard features (Memory, Cron, Skills, Settings)

The chat works with just the Gateway API. For the extra drawer features (Memory, Cron Jobs, Skills, Settings), you also need the Hermes dashboard running on port `9119`.

If your dashboard is **password-protected**, tap the **⋮** menu next to your connection → **Dashboard / Proxy Settings**, and enter the username and password there.

If your dashboard is **open** (started with `--insecure`), no extra setup is needed — just make sure it's running with `--host 0.0.0.0`.

---

## Method 2: Connect over Tailscale (private VPN)

Tailscale creates a private encrypted network between your phone and your computer. It's free for personal use and works from anywhere — no router changes needed.

### What you need

- A free [Tailscale](https://tailscale.com/) account
- Tailscale installed on **both** your phone and your Hermes computer
- Both devices signed in to the same Tailscale account

### Step 1: Install Tailscale on your phone

1. Install Tailscale from the [Play Store](https://tailscale.com/download/android) or the link above.
2. Open Tailscale and sign in.
3. Leave it connected while using the Hermes app.

### Step 2: Install Tailscale on your Hermes computer

Install Tailscale for your OS: <https://tailscale.com/download>

```bash
# macOS with Homebrew
brew install --cask tailscale

# Debian/Ubuntu
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Step 3: Find your computer's Tailscale address

```bash
tailscale ip -4
```

This gives you a `100.x.y.z` address. You can also use MagicDNS (the machine name) if enabled.

### Step 4: Add the connection in the app

1. Open the Hermes app. Tap **+**.
2. Fill in:

   | Field | What to type |
   |-------|-------------|
   | **Label** | e.g. `Home Tailscale` |
   | **Host** | The Tailscale IP, e.g. `100.64.12.34` |
   | **Port** | `8642` (leave as is) |
   | **API Key** | The API key from your Hermes computer |

3. Tap **Connect**. You're ready to chat from anywhere!

---

## Method 3: Connect over Cloudflare Tunnel (public URL)

A Cloudflare Tunnel gives your Hermes server a public web address (like `https://hermes-api.your-domain.com`) that works from anywhere — no VPN, no router port forwarding, no open ports on your computer. Cloudflare handles the encryption and routing.

```text
Your phone  →  HTTPS  →  Cloudflare public URL  →  tunnel  →  Your computer's Hermes
```

### What you need (checklist)

Before you start, make sure you have:

- [ ] A **domain name** (e.g. `your-domain.com`) managed by Cloudflare
- [ ] A free **Cloudflare account**
- [ ] Your Hermes server running on your computer (Gateway on port `8642`, dashboard on port `9119`)
- [ ] Your **API key** from Hermes (found in `~/.hermes/.env` on your computer)
- [ ] Optional but recommended: **Cloudflare Access** set up for extra security (see below)

> **Don't have a domain?** Use [Method 2 (Tailscale)](#method-2-connect-over-tailscale-private-vpn) instead — it's free and doesn't require a domain.

---

### Step 1: Install the Cloudflare tunnel tool

On your Hermes computer, install `cloudflared`:

- **Guide:** <https://developers.cloudflare.com/tunnel/setup/>
- **macOS:** `brew install cloudflared`
- **Linux:** `curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared`

### Step 2: Log in and create a tunnel

```bash
cloudflared tunnel login
```

This opens a browser to authorize Cloudflare. After that:

```bash
cloudflared tunnel create hermes-home
```

Note the **tunnel UUID** and the **credentials JSON path** it prints — you'll need them in the next step.

### Step 3: Create the config file

Create a file at `/etc/cloudflared/config.yml` (or `./cloudflared/config.yml` if using Docker):

```yaml
tunnel: hermes-home
credentials-file: /etc/cloudflared/<UUID>.json

ingress:
  # Chat & sessions → port 8642
  - hostname: hermes-api.your-domain.com
    path: /api/sessions*
    service: http://localhost:8642
  - hostname: hermes-api.your-domain.com
    path: /v1/*
    service: http://localhost:8642

  # Dashboard (Memory, Cron, Skills, Settings) → port 9119
  - hostname: hermes-api.your-domain.com
    service: http://localhost:9119

  - service: http_status:404
```

> **Replace** `hermes-api.your-domain.com` with your actual domain.
> **Replace** `<UUID>` with the tunnel UUID from Step 2.
> **Replace** `localhost` with your Docker container name if Hermes runs in Docker.

### Step 4: Connect your domain and start the tunnel

```bash
cloudflared tunnel route dns hermes-home hermes-api.your-domain.com
cloudflared tunnel run hermes-home
```

To keep the tunnel running permanently:

```bash
sudo cloudflared service install
```

### Step 5: Test that the tunnel works

On your computer, run:

```bash
curl https://hermes-api.your-domain.com/api/sessions \
  -H "Authorization: Bearer YOUR_API_KEY"
```

If you see JSON output with sessions, the tunnel is working!

> **If you set up Cloudflare Access** (recommended), also add the service token headers to the test:
> ```bash
> curl https://hermes-api.your-domain.com/api/sessions \
>   -H "Authorization: Bearer YOUR_API_KEY" \
>   -H "CF-Access-Client-Id: YOUR_CF_CLIENT_ID" \
>   -H "CF-Access-Client-Secret: YOUR_CF_CLIENT_SECRET"
> ```
> If you get **403 Forbidden**, your Cloudflare Access policy is blocking the request — see [Setting up Cloudflare Access](#setting-up-cloudflare-access-optional-but-recommended) below.

### Step 6: Enter the tunnel URL in the app

This is the key step — here's exactly what to type in each field:

1. Open the Hermes app on your phone.
2. Tap the **+** button (bottom right corner).
3. You'll see the **Add Gateway Connection** form. Fill it in like this:

   | Field | What to type | Example |
   |-------|-------------|---------|
   | **Label** | Any name to remember this connection | `Home Hermes` |
   | **Host** | Your full Cloudflare Tunnel URL **with** `https://` | `https://hermes-api.your-domain.com` |
   | **Port** | **Delete the default value and leave it blank** — HTTPS uses port 443 automatically | *(empty)* |
   | **API Key** | The API key from your Hermes computer's `~/.hermes/.env` file | `sk-abc123...` |
   | **CF Access Client ID** | Your Cloudflare Access service token Client ID *(only if you set up Access)* | `abc123.access` |
   | **CF Access Client Secret** | Your Cloudflare Access service token Client Secret *(only if you set up Access)* | `xyz789...` |

4. Tap **Connect**. The app will test the connection.
5. If it says **connected**, tap your new connection to start chatting!

> **Important notes about the Host field:**
> - Always include `https://` at the start — this tells the app to use encrypted HTTPS.
> - Do **not** include a port number in the URL (e.g. `https://hermes-api.your-domain.com:8642` is wrong). The tunnel handles ports internally.
> - Do **not** include a path (e.g. `https://hermes-api.your-domain.com/api`). Just the domain.

> **About the Port field:** When the Host starts with `https://`, the app automatically uses port 443 (the standard HTTPS port). You can leave the Port field empty.

### Step 7: Set up dashboard features (optional)

For the drawer features (Memory, Cron Jobs, Skills, Settings) to work over the tunnel:

1. On the connections list, tap the **⋮** (three dots) menu next to your connection.
2. Tap **Dashboard / Proxy Settings**.
3. Choose your dashboard type:

   **If your dashboard is password-protected:**
   - Enter the **Username** and **Password**
   - Leave **Dashboard behind proxy** **off**
   - Leave **Dashboard Port** blank
   - Tap **Save**

   **If your dashboard is open (started with `--insecure`):**
   - Turn **on** the **Dashboard behind proxy** switch
   - Leave everything else blank
   - Tap **Save**

   **If your dashboard is on a different domain than your API:**
   - Enter the dashboard domain in **Dashboard Host** (e.g. `hermes.example.com`)
   - Leave blank if both are on the same domain

---

### Setting up Cloudflare Access (optional but recommended)

Cloudflare Access adds an extra security layer in front of your tunnel. Without it, anyone who knows your URL could try to connect. With it, only requests carrying your service token are allowed through.

**How it works:**

```text
Request from app
  → CF-Access-Client-Id + CF-Access-Client-Secret headers
  → Cloudflare Access checks them
  → If valid: request goes through to your Hermes
  → If invalid: 403 Forbidden
```

**Create a service token:**

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) → **Access → Service Tokens**.
2. Click **Create Service Token**.
3. **Copy the Client ID and Client Secret immediately** — they're only shown once!
4. Create an Access policy that requires the service token for your Hermes hostname.
5. Enter the Client ID and Client Secret in the app's **Add Connection** dialog (the two **CF Access** fields), or in **⋮ → Dashboard / Proxy Settings** for an existing connection.

**Your three layers of protection:**

1. **Cloudflare Access service token** — blocks unauthorized requests at Cloudflare's edge.
2. **Hermes API key** — authenticates against the Gateway API Server.
3. **Cloudflare Tunnel** — encrypted connection from Cloudflare to your computer, no open ports.

---

### Cloudflare Tunnel troubleshooting

| Problem | What to check |
|---------|-------------|
| **App says "Cannot reach host"** | Is the tunnel running? Run `cloudflared tunnel run hermes-home` on your computer and try again. |
| **App says "403 Forbidden"** | You have Cloudflare Access enabled but didn't enter the CF Access Client ID and Secret in the app. Add them in the connection settings. |
| **Chat works but dashboard screens fail** | The tunnel ingress config might not route dashboard paths to port `9119`. Check your `config.yml` — the catch-all rule should point to `9119`. |
| **Dashboard screens show "401 Unauthorized"** | Your dashboard is password-protected. Enter the username and password in **⋮ → Dashboard / Proxy Settings**. |
| **Dashboard screens show empty/error with `--insecure` dashboard** | Enable **Dashboard behind proxy** in Dashboard / Proxy Settings so the app skips token scraping (which fails through the tunnel). |
| **Worked before but now stopped** | The tunnel service may have stopped. Restart it: `sudo systemctl restart cloudflared` or `cloudflared tunnel run hermes-home`. |

---

### Advanced: Cloudflare Tunnel in Docker

<details>
<summary>Click to expand Docker setup</summary>

If `cloudflared` runs in a Docker container, `localhost` inside the container refers to the container itself — not your host machine. Use one of these approaches:

**Option A — Same Docker network (recommended):**

Put `cloudflared` and `hermes-gateway` on the same Docker network and use the container name:

```yaml
# docker-compose.yml
services:
  hermes-gateway:
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

**Option B — Hermes on the host (not in Docker):**

Add `extra_hosts` and use `host.docker.internal`:

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

</details>

### Cloudflare Tunnel security notes

- Always keep the Hermes API key required, even behind Cloudflare — don't rely on URL obscurity.
- Cloudflare Access service tokens add an authentication layer — use them for any deployment exposed to the internet.
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
- **Over Cloudflare Tunnel**: ensure the tunnel ingress routes dashboard paths (`/api/memory`, `/api/cron/jobs`, `/api/skills`, `/api/model/*`, `/auth/*`) to port `9119` and gateway paths (`/api/sessions`, `/v1/*`) to port `8642`. See [Method 3: Cloudflare Tunnel](#method-3-connect-over-cloudflare-tunnel-public-url).
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
