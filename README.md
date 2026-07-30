# Find My Android

A self-hosted, privacy-first "find my device" system for Android — without Google Play Services and without collecting any personally-identifying information.

- **No Google Play Services.** Location is read via a small custom plugin ([`packages/location_bridge`](packages/location_bridge)) that talks directly to Android's built-in `LocationManager` (GPS/network providers), not the Google fused location API.
- **No email, no phone number, ever.** The only identity is a single high-entropy account code, generated once and never recoverable if lost.
- **End-to-end encrypted.** The location-encryption key is derived on-device (and in the web viewer) from your account code — the server only ever stores/serves opaque ciphertext it cannot read.
- **Reports location every 5 minutes** via a persistent foreground service (not WorkManager — its periodic-task floor is 15 minutes).
- **"Play sound"** rings the phone at forced maximum volume through Do Not Disturb, reusing the same [`alarm`](https://pub.dev/packages/alarm) engine as [Hidde-Balestra/alarm](https://github.com/Hidde-Balestra/alarm).

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

- **Account session** (code + TOTP, ~1 hour) — used interactively (the app's device list, the web viewer) to view history and queue a "play sound" command.
- **Device token** (issued once when a phone is paired) — used only by that phone's unattended 5-minute check-in to submit its own location and poll for a pending ring command. It cannot read history or see other devices, so the background service never needs to prompt for a TOTP code.

## Encryption

The location-encryption key is `PBKDF2-HMAC-SHA256(code, salt, 210,000 iterations)`, computed identically by the Flutter app ([`cryptography` package](https://pub.dev/packages/cryptography)) and the web viewer (browser `SubtleCrypto` — no WASM/CDN crypto library needed). PBKDF2 rather than a memory-hard KDF like Argon2id is a deliberate choice: the account code has ~160 bits of server-generated entropy, so there's no dictionary attack to defend against, and PBKDF2's native browser support keeps the web viewer dependency-free.

Each location sample is AES-256-GCM encrypted client-side with a fresh random nonce before it's ever sent over the network. The server (`backend/api/locations.php`) only stores/serves the resulting ciphertext blob.

## Why "play sound" polls instead of pushing

Without Google Play Services there's no Firebase Cloud Messaging. Rather than run a separate always-on WebSocket server, the phone's existing 5-minute location check-in also polls for a pending ring command (`GET /ring.php`) and plays the sound immediately if one is waiting. That means ringing can take up to 5 minutes to trigger — a deliberate trade-off for zero extra infrastructure and battery cost.

## Running the backend

1. Create a MySQL/MariaDB database and import `backend/sql/schema.sql`.
2. `backend/api/config.php` reads every secret from an environment variable — **never edit real values into that file**, since it lives in this public repo. Set these on the server itself (Apache/Nginx vhost, php-fpm pool `env[...]`, etc.), not by editing PHP:
   - `FMA_DB_HOST`, `FMA_DB_USER`, `FMA_DB_PASSWORD`, `FMA_DB_NAME`
   - `FMA_CODE_LOOKUP_PEPPER` — generate with `php -r "echo bin2hex(random_bytes(32));"`
   - `FMA_TOTP_ENCRYPTION_KEY_BASE64` — generate with `php -r "echo base64_encode(random_bytes(32));"`
3. Deploy `backend/api/` behind PHP 8.2+ with the `sodium` and `pdo_mysql` extensions enabled, and `backend/web/` as a static site pointed at that API.
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
