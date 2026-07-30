# Find My Android

A self-hosted, privacy-first "find my device" system for Android — without Google Play Services and without collecting any personally-identifying information.

- **No Google Play Services.** Location is read via a small custom plugin ([`packages/location_bridge`](packages/location_bridge)) that talks directly to Android's built-in `LocationManager` (GPS/network providers), not the Google fused location API.
- **No email, no phone number, ever.** The only identity is a single high-entropy account code, generated once and never recoverable if lost.
- **End-to-end encrypted.** The location-encryption key is derived on-device (and in the web viewer) from your account code — the server only ever stores/serves opaque ciphertext it cannot read.
- **Reports location every 5 minutes** via a persistent foreground service (not WorkManager — its periodic-task floor is 15 minutes).
- **"Play sound"** rings the phone at forced maximum volume through Do Not Disturb, reusing the same [`alarm`](https://pub.dev/packages/alarm) engine as [Hidde-Balestra/alarm](https://github.com/Hidde-Balestra/alarm).
- **Security snapshot** (opt-in, documented — see below): after too many failed attempts — the in-app account-code/TOTP login, or (optionally) this phone's own lock-screen credential — log a front-camera photo + location as a security event, visible later in that device's own history.

## Repository layout

```
app/                    Flutter app (Android)
packages/location_bridge/  Local plugin: LocationManager bridge, no Play Services
backend/api/            PHP REST API
backend/sql/schema.sql  Database schema
backend/web/            Static web viewer (view/ring a device from any browser)
```

## How authentication works

There is no username/password/email. Registering (`POST /register.php`) generates:

1. **An account code** — a long random string, shown once. This is the entire login credential. **Store it in your password manager immediately** — it cannot be shown again, and there is no "forgot code" flow, by design (that's the trade-off for collecting zero recoverable personal data).
2. **A TOTP secret** (QR code) for a standard authenticator app (Aegis, FreeOTP, etc.) as the second factor.

Two separate credential tiers exist after that:

- **Account session** (code + TOTP, ~2 hours) — used interactively (the app's device list, the web viewer) to view history and queue a "play sound" command. The web viewer persists this in `localStorage` so a page refresh doesn't force logging in again — meaning the account code sits in the browser for that window too; the server-side session expires on the same schedule either way.
- **Device token** (issued once when a phone is paired) — used only by that phone's unattended 5-minute check-in to submit its own location and poll for a pending ring command. It cannot read history or see other devices, so the background service never needs to prompt for a TOTP code.

## Encryption

The location-encryption key is `PBKDF2-HMAC-SHA256(code, salt, 210,000 iterations)`, computed identically by the Flutter app ([`cryptography` package](https://pub.dev/packages/cryptography)) and the web viewer (browser `SubtleCrypto` — no WASM/CDN crypto library needed). PBKDF2 rather than a memory-hard KDF like Argon2id is a deliberate choice: the account code has ~160 bits of server-generated entropy, so there's no dictionary attack to defend against, and PBKDF2's native browser support keeps the web viewer dependency-free.

Each location sample is AES-256-GCM encrypted client-side with a fresh random nonce before it's ever sent over the network. The server (`backend/api/locations.php`) only stores/serves the resulting ciphertext blob.

## Security snapshot: a documented feature, not a hidden one

Two independent triggers feed the same `SecurityCaptureService`, which takes one front-camera photo, reads the current location, encrypts both exactly like an ordinary location check-in, and uploads them (`POST /security_events.php`) using the device's own scoped token — no interactive login required, so it works even if whoever failed the attempt never gets past that screen. The account owner reviews these later from the device's own screen (the shield icon next to "Play sound" in the app's device-history view), the same way a bank app logs failed sign-in attempts.

1. **In-app login failures** — `login_dialog.dart` (the "log in to view devices & history" flow, on an already-paired phone) counts consecutive failed account-code/TOTP attempts (`FailedAttemptTracker`).
2. **Lock-screen failures** (optional, Device Administrator) — a regular app has no visibility at all into the phone's own PIN/pattern/password unlock attempts; the only API that exposes this is `DeviceAdminReceiver.onPasswordFailed()`, which requires the user to explicitly activate this app as a device administrator via `Settings → Device administrator`. Activating it shows Android's own prominent system warning listing everything a device administrator *could* do (including things this app never uses, like remote wipe) — that warning is the OS's transparency mechanism, not something this app can soften or skip. Once activated, `SecurityDeviceAdminReceiver` (native, Kotlin) records failed unlocks to its own SharedPreferences file; the existing 5-minute background check-in (`LockscreenTriggerHandler`) polls and consumes that flag, so a lock-screen-triggered snapshot can take up to 5 minutes to fire — the same latency trade-off already made for location reporting and "play sound".

Both triggers share one configurable threshold (Settings → Security snapshot, default 1 failed attempt, 0 disables both entirely).

This is deliberately **not** built to be covert or undetectable:
- Camera permission must be explicitly granted in Settings — Android's own runtime permission dialog is the transparency mechanism here, and it's listed alongside every other permission this app requests.
- Device Administrator must be explicitly activated through Android's own system screen, which shows its standard capability warning — this app cannot suppress, reword, or auto-accept it.
- Android has shown a mandatory camera-in-use indicator (a dot in the status bar) since Android 12, and many devices/regions (Japan, South Korea) always play an audible shutter sound. This code makes no attempt to suppress either — those are OS-level anti-covert-surveillance protections, not implementation gaps.
- The feature, its two triggers, its threshold, and where to review captured events are documented here and in the app's own Settings screen, not hidden.

## Why "play sound" polls instead of pushing

Without Google Play Services there's no Firebase Cloud Messaging. Rather than run a separate always-on WebSocket server, the phone's existing 5-minute location check-in also polls for a pending ring command (`GET /ring.php`) and plays the sound immediately if one is waiting. That means ringing can take up to 5 minutes to trigger — a deliberate trade-off for zero extra infrastructure and battery cost.

## Running the backend

1. Create a MySQL/MariaDB database and import `backend/sql/schema.sql`.
2. `backend/api/config.php` reads every secret from an environment variable — **never edit real values into that file**, since it lives in this public repo. Copy `backend/api/.env.example` to `backend/api/.env` (gitignored, never committed) and fill in real values — this is the easiest route on shared hosting where you can't set real server env vars. If your host *does* let you set real environment variables (Apache/Nginx vhost, php-fpm pool `env[...]`), those take precedence over `.env` automatically:
   - `FMA_DB_HOST`, `FMA_DB_USER`, `FMA_DB_PASSWORD`, `FMA_DB_NAME`
   - `FMA_CODE_LOOKUP_PEPPER` — generate with `php -r "echo bin2hex(random_bytes(32));"`
   - `FMA_TOTP_ENCRYPTION_KEY_BASE64` — generate with `php -r "echo base64_encode(random_bytes(32));"`
3. Deploy `backend/api/` (including your `.env`) behind PHP 8.2+ with the `sodium` and `pdo_mysql` extensions enabled, and `backend/web/` as a static site pointed at that API.
4. In the Flutter app and `backend/web/api.js`, update the default API base URL to your deployment.

## Building the app

```
cd app
flutter pub get
flutter test
flutter build apk --release
```

## Releases & CI

- `.github/workflows/test.yml` runs `flutter analyze`/`flutter test` and lints the PHP backend on every push/PR.
- `.github/workflows/release.yml` builds signed, split-per-ABI release APKs and publishes them to GitHub Releases whenever a `vX.Y.Z` tag is pushed (or via manual dispatch). It needs these repo secrets to produce a *signed* build (falls back to debug signing otherwise): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- The in-app Settings screen checks this repo's [latest release](https://github.com/Hidde-Balestra/findmyandroid/releases/latest) and links straight to it when an update is available.
