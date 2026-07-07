# Cloudflare Tunnel

Expose the home-PC Hermes Gateway to the Android app over public HTTPS without a
VPN or router port forwarding (plan §4, §21).

```text
cloudflared (home PC)  ──outbound──▶  Cloudflare  ──▶  https://hermes-api.<domain>
```

## 1. Install cloudflared on the home PC

```bash
# Debian/Ubuntu
sudo mkdir -p /etc/cloudflared
# install per https://developers.cloudflare.com/tunnel/setup/
```

## 2. Create a tunnel

```bash
cloudflared tunnel login
cloudflared tunnel create hermes-home
# note the tunnel UUID and credentials json path
```

## 3. Configure ingress

`/etc/cloudflared/config.yml`:

```yaml
tunnel: hermes-home
credentials-file: /etc/cloudflared/<UUID>.json

ingress:
  - hostname: hermes-api.daniel-lilintal.com
    service: http://localhost:8642   # Hermes Gateway
  - service: http_status:404
```

## 4. Route DNS + run

```bash
cloudflared tunnel route dns hermes-home hermes-api.daniel-lilintal.com
cloudflared tunnel run hermes-home
# or install as a service:
sudo cloudflared service install
```

## 5. Point the Android app at it

Create a **Home Hermes** connection profile:

```text
Gateway URL: https://hermes-api.daniel-lilintal.com
API Key:     <API_SERVER_KEY>
Mode:        Cloudflare Tunnel
```

## Verify

```bash
curl https://hermes-api.daniel-lilintal.com/health
```

Then from the phone (on mobile data, not home Wi-Fi): open the app, add the
profile, and confirm chat streaming works.

## Notes

- Keep the gateway API key required even behind Cloudflare — do not rely on URL obscurity (see `SECURITY.md`).
- Optional hardening: Cloudflare Access, mTLS, IP allowlist.
