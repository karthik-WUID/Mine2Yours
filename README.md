Current review: [Internet translation review](docs/testing/internet-translation-review.md). Public HTTPS, direct sending and receiver-language translation are now the default.

> Current review behavior (9 October): [direct voice and login-free device profiles](docs/testing/direct-voice-review.md). Stop/release sends immediately. The earlier transcript-confirmation workflow below is superseded.

# Mine2YourLingo

**My Voice. Your Language.** Private multilingual communication for teams and communities.

This is an implemented, locally runnable pilot foundation. It is **not production launch ready**. Live Tamil–Bengali voice quality, background phone delivery, store billing, deployment, and release signing have not been certified or fabricated. The current status and outstanding requirements are in [PROGRESS.md](PROGRESS.md).

## What runs

- Flutter Android/iOS/web source using the supplied official logo, a consistent light theme, large voice controls, self-hosted Inter/Indic fonts, and accessible tap-to-record alternatives.
- Explicit development identity simulator; provider-backed Twilio Verify phone authentication adapter; rotating opaque sessions and revocation.
- Private group creation, expiring invitations, joining, membership permissions, direct audiences, group messages, and plan-gated broadcasts.
- Device speech recognition where available; 60-second PCM WAV capture; metered cloud transcription; editable transcript review; source-language phrase library and custom phrases.
- Authenticated REST/WebSocket communication, sender translation review, per-recipient ordered delivery/playback receipts, persistent Drift cache and bounded idempotent outbox retries.
- Interchangeable real HTTP STT/TTS adapters, Google Cloud/LibreTranslate-compatible translation, optional OpenAI audio adapters, distinct-language fanout, scoped cache, versioned cost estimates, circuit breakers, and atomic spending/usage limits.
- Native Kotlin/Swift audio with explicit receiving consent, quiet hours, per-group automatic-speech mute, bounded Android foreground sessions, installed voice checks, silence/audio-focus handling, and disconnect cancellation. Android enforces a token-bound quiet-hour deadline in native playback. Replay, phrases and incoming speech share queue ownership; native request IDs prevent delayed callbacks from completing a replacement. **Live network receiving works while the Flutter app is open; no background-network delivery claim is made.** Strict headphone playback is restricted when the native route cannot be verified.
- React admin portal using real usage and authorization: groups/members, plans, costs, provider readiness, privacy export, and session management. No invented revenue or transcript browser.
- Prisma/PostgreSQL schema and initial migration, Redis/BullMQ integration, private audio storage, signed authorized audio access, local encrypted development persistence, OpenAPI, Docker configuration, CI, deployment/security/physical-device guides.

Android supports free on-device Google ML Kit translation for its supported language pairs, with actual model downloads and no AI API bill. Paid cloud AI requires an active server-verified Pro subscription. Absent cloud AI credentials produce explicit unavailable errors. They never produce a sample translation. Built-in phrases are identified as source text; deterministic AI doubles exist only inside tests. Missing verified billing never unlocks paid entitlements.

## Local development

Requirements: Flutter **3.47.6** / Dart **3.13.5**, Node **22+**, npm **10+**, Java 17, Android SDK 36 for Android builds. Dependencies and lockfiles are pinned. Full Xcode is necessary for Apple builds.

```bash
npm --prefix services/api ci
npm --prefix services/api run prisma:generate
npm --prefix apps/admin-web ci
cd apps/mobile
flutter pub get
cd ../..
```

Run in separate terminals:

```bash
bash scripts/dev-api.sh       # http://127.0.0.1:3100/v1
bash scripts/dev-admin.sh     # http://localhost:5173
cd apps/mobile
flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:3100/v1
```

The scripts can use the existing Codex Node/Flutter runtimes on this host without changing global installations. Port 3000 belongs to an unrelated existing application here; Mine2YourLingo uses **3100** locally and preserves it. Deployment's internal API port is 3000.

For a first review, follow [the browser review guide](docs/testing/first-review.md). Open [the mobile preview](http://127.0.0.1:4174), [the admin portal](http://localhost:5173) and [API documentation](http://127.0.0.1:3100/v1/docs). Build/serve the mobile preview with `bash scripts/build-mobile-web.sh` and `python3 scripts/preview-mobile-web.py`. For aggregate admin access, set a private `DEV_ADMIN_KEY` in the API environment and enter it during **development** login. Ordinary users still see only their authorized groups. The development simulator intentionally creates a new test identity on each new registration; persisting a session keeps that identity across app restarts.

For a Wi-Fi Android review, follow the [device network guide](docs/testing/android-review.md). The API must listen on the network and the APK must use the Mac’s LAN address. USB forwarding is optional and is only used by the alternate loopback setup below.

For a USB-connected Android test device:

```bash
adb reverse tcp:3100 tcp:3100
cd apps/mobile
flutter run -d YOUR_DEVICE_ID --dart-define=API_URL=http://127.0.0.1:3100/v1
```

Production must disable development authentication, use verified identity, HTTPS/WSS, PostgreSQL, Redis, managed secrets, and reviewed encryption/storage settings. See [deployment instructions](docs/deployment/README.md). Raw audio is not retained by the server by default; offline audio queued on a phone stays on that device until processing or explicit discard. Local SQLite is protected by OS disk security, **not app-level encrypted SQLite or E2EE**.

## Configure real processing

Copy `services/api/.env.example` into its ignored `.env`, review provider privacy/retention, and configure an actual translator and optional speech providers. Explicit `AI_PRICING_VERSION`, `AI_PRICING_CONFIRMED=true`, and positive reviewed unit rates are required before paid provider traffic. Grant provider consent in the app's Privacy settings. Secrets stay on the server.

The five default language choices are Tamil, Bengali, Hindi, Odia, and English. Eighteen additional Indian regional languages prepare on selection; actual recognition and voice installation vary by device/provider. The [walkie-talkie review](docs/testing/walkie-review.md) covers the current reference layout, hold-to-talk controls, tablet installation and the full-test rerun limitation. The [free speech and Pro review](docs/testing/free-voice-review.md) explains the zero-cost translation path and Pro cloud gates. The [team/member guide](docs/testing/team-member-review.md) documents development phone login (code 123456), invitations and admin personnel records; its build evidence is historical. Source and listening languages are independent and communication directions are not tied to job roles.

Create an engineer identity in Tamil, create a private group, invite a Bengali identity on another device, and follow [the real-speaker pilot checklist](docs/testing/README.md). Quantity/safety instructions enter a sender confirmation state. Numeric validation can catch changed digits; it does not certify preservation of spelled quantities, negation, technical meaning, or translation quality.

## Verification and release gates

```bash
npm --prefix services/api test
npm --prefix services/api run build
npm --prefix apps/admin-web test
npm --prefix apps/admin-web run build
cd apps/mobile
flutter analyze
flutter test
```

On this Mac without Xcode/CLT, run `FLUTTER_BIN=/path/to/flutter bash scripts/test-mobile-local.sh`. It temporarily selects the system SQLite library **only for host tests**, then restores the normal bundled-SQLite pubspec. Run this script alone, without another simultaneous Flutter build. Native release builds always use bundled SQLite. The compatible Apple path-provider implementation is pinned at 2.4.4 because its newer FFI implementation requires Apple build tools even for host tests.

Further artifacts and evidence: [admin verification](apps/admin-web/VERIFICATION.md), [backend guide](services/api/README.md), [architecture](docs/architecture/README.md), [native platform limits](docs/architecture/native-audio.md), [security](docs/security/README.md), [API contract](packages/api-contracts/README.md).

Outstanding launch work includes physical two-phone cloud testing, FCM/notification delivery, strict Android private audio routing, headset/consented reply windows, offline voice pack evaluation, store receipts/webhooks and refunds against live providers, fine-grained consent/retention/legal review, scalable database query design, deployment backups/KMS/monitoring, signing, and store acceptance. The progress tracker is authoritative; interface visibility alone does not prove implementation.
