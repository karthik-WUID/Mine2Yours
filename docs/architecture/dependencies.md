# Dependency choices

The mobile `pubspec.yaml` and Node `package.json` files pin direct dependencies; lockfiles pin resolved trees. Flutter is pinned to 3.47.6 in CI, with Dart supplied by that SDK, Node22 and Java17. These are reproducible compatibility selections, not a statement that every upstream release or vulnerability has been reviewed. Use the lockfile and test a change before updating pins.

| Dependency family | Reason |
| --- | --- |
| Riverpod / GoRouter | Explicit state transitions and declarative app navigation |
| Dio / WebSocketChannel | REST timeouts/session rotation plus authenticated event transport; provider credentials never enter mobile requests |
| Drift / SQLite | Transactional local cache and retry outbox; local content currently relies on OS disk protection |
| flutter_secure_storage | Platform-backed access/refresh token storage rather than ordinary preference files |
| record / speech_to_text | Bounded user-triggered audio capture and optional platform dictation; locale/offline availability is detected rather than promised |
| Native Kotlin / AVSpeechSynthesizer | Explicit voice inventory, focus/interruptions, truthful native playback lifecycle and platform-compliant session handling |
| flutter_tts | Browser speech playback fallback; it does not bypass mobile native privacy checks |
| NestJS / Prisma | Modular API/authorization boundaries, PostgreSQL migration schema and transactions |
| Redis / BullMQ | Ephemeral coordination and retriable processing when Redis is configured |
| AWS S3 SDK | S3-compatible encrypted object storage with the standard credential chain; IAM task roles preferred |
| React / Vite / Vitest | Accessible administration UI, static production build and deterministic UI/domain tests |
| Bundled Fontsource fonts | Same-origin typography compatible with CSP; no external Google Fonts request |

`path_provider_foundation` is explicitly pinned to 2.4.4. The initially resolved 2.6.0 Objective-C native build hook required a usable Apple developer toolchain even for local macOS-hosted Flutter tests. The earlier maintained Flutter plugin implementation avoids that hook requirement and remains an intentional compatibility pin; revisit it after testing with a full Xcode environment. It does not make iOS builds possible without an iOS SDK.

The `sqlite3` native asset hook can require `xcrun` to select/build a universal Apple-host binary. On this host, a temporary test-only hook configuration selected the system SQLite library for macOS Flutter tests; do not ship that override as an Android/iOS runtime configuration. The final app retains its package-provided mobile SQLite artifacts. Record test-only overrides with evidence so a passing host test is not mistaken for a mobile-native build.

GitHub Actions are pinned to full commit SHAs verified against their tags; Dependabot tracks package/action updates. Docker bases use versioned tags; pin a scanned platform-specific digest in the owner's release manifest before deploying. The local MinIO helper builds an official immutable commit because archived historical binary-image access was unavailable; it is not a supported production storage selection.
