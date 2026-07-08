# Release Checklist

Run through this before every release PR. Mark each item ✅ or ⚠️.

## Analysis
- [ ] `flutter analyze` — zero errors
- [ ] `flutter test` — all tests pass
- [ ] `flutter pub outdated` — key deps current
- [ ] `flutter build apk --release --split-per-abi` — clean build

## Architecture
- [ ] State management consistency (no orphaned setState vs Riverpod)
- [ ] No orphaned imports
- [ ] Error handling on all network calls
- [ ] `dispose()` on all `StatefulWidget`s with controllers/timers
- [ ] WebSocket lifecycle (connect/dispose)
- [ ] Async `ConnectionManager` methods awaited at all call sites

## UX
- [ ] Error states visible (not silent failures)
- [ ] Loading indicators on network calls
- [ ] Responsive layout (phone + tablet)
- [ ] Dark mode follows system
- [ ] Input validation (no empty submits)

## Security
- [ ] API keys stored in `flutter_secure_storage` (Keystore / Keychain)
- [ ] Dashboard credentials stored in `flutter_secure_storage`
- [ ] No secrets in plaintext `SharedPreferences`
- [ ] No hardcoded API keys
- [ ] Proper URL scheme validation (HTTPS for remote, HTTP for LAN)
- [ ] Biometric app lock toggle works (when device supports it)
- [ ] Biometric lock screen shows on app startup when enabled
- [ ] App falls back gracefully on devices without biometrics
- [ ] `USE_BIOMETRIC` permission in `AndroidManifest.xml`
- [ ] `NSFaceIDUsageDescription` in iOS `Info.plist`
- [ ] High-risk services show confirmation dialog
- [ ] Critical-risk services require typed confirmation phrase

## Cloudflare Tunnel
- [ ] Gateway path prefix applied to all API calls
- [ ] Dashboard path prefix applied to all dashboard calls
- [ ] Proxied dashboard mode sends clean headers (no token/cookie)
- [ ] Health check works through Cloudflare Tunnel URL
- [ ] Chat streaming works through Cloudflare Tunnel URL
- [ ] Services screen works through Cloudflare Tunnel URL
- [ ] Diagnostics screen shows Cloudflare Tunnel status

## Release
- [ ] Version bumped in `pubspec.yaml`
- [ ] CHANGELOG.md updated
- [ ] CI/CD builds clean APK
- [ ] GitHub Actions workflow passes
- [ ] Tag pushed (`git tag v0.x.y && git push origin main --tags`)

## Testing (Android Emulator / Device)
- [ ] Add connection profile (host, port, API key)
- [ ] Connect via Cloudflare Tunnel URL
- [ ] Browse sessions
- [ ] Send message → see streaming response
- [ ] LLM choice question renders as buttons
- [ ] Answer question → state updates
- [ ] Run low-risk service (e.g. check_status)
- [ ] Run high-risk service → confirmation dialog appears
- [ ] Run critical-risk service → typed confirmation required
- [ ] Service run status polls and updates
- [ ] Service run SSE log streaming works (real-time logs)
- [ ] Service run progress steps display on active run card
- [ ] Full-screen log viewer shows streaming logs and steps
- [ ] SSE stream falls back to polling on error
- [ ] Diagnostics screen shows gateway/agent/cloudflare status
- [ ] Biometric lock toggle in Home screen menu
- [ ] Biometric lock prompts on app restart
- [ ] Delete connection removes secrets from secure storage

## Unit Tests
- [ ] `connection_manager_test.dart` — all tests pass
- [ ] `models_test.dart` — all tests pass
- [ ] `widget_test.dart` — all tests pass
