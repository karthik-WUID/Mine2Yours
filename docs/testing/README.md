# Validation and release test matrix

Use this matrix as the release evidence record. A configured CI job is not a passed test. An unsigned build is not a signed install. Playback completion is not a heard/understood receipt. This increment needs production integration and physical-device testing before commercial release.

## Automated checks

From each Node package, run `npm ci`, the package build and tests. API additionally runs `npm run prisma:generate`; schema migrations must be exercised on a fresh PostgreSQL database. From `apps/mobile`, run `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` and `flutter build apk --debug`. macOS with full Xcode runs `flutter build ios --release --no-codesign`.

GitHub CI performs those checks, runtime npm security audits, a limited committed-credential signature check and a Compose integration smoke check. It does not prove production OTP, AI quality, push delivery, battery consumption or billing settlement. Full secret-history scanning and mobile dependency/container scans remain recommended release checks.

| Check | Local evidence for this native/infra increment |
| --- | --- |
| Compose/workflow/Dependabot YAML parsing | Passed Ruby YAML syntax parse |
| Local setup/storage/credential scripts | Passed Node syntax checks |
| iOS Info.plist | Passed `plutil -lint` |
| Android native Kotlin type compilation | Passed direct Kotlin2.4.0 compilation against real Android36 SDK and Flutter3.47.6 embedding jars, JVM17, with a 512MiB heap; all six production source files and three JVM test classes compiled |
| Native media-download, deadline and request-ID policy tests | Passed 15 JUnit tests on JVM17: 7 download tests including actual loopback networking/blocked redirects, 4 deadline type/bounds/expiry tests and 4 request-ID type/length/character tests |
| Integrated Android Gradle/APK build/install | Current worker-interface arm64 debug APK built in 99.9 seconds; v2 signature and stable Wi-Fi hostname verified. Installed/launched on SM-F766B, normal app capabilities HTTP 200; real native English TTS engine smoke passed. Earlier devices still need this update when reconnected. See [current evidence](worker-review.md). Earlier ENOSPC attempts are superseded |
| Swift type-check / iOS build | Blocked: no usable Xcode/iOS SDK, `xcrun` developer path missing |
| PostgreSQL migrations and runtime | Passed isolated PostgreSQL16.14: `prisma migrate deploy`, concurrent two-client transactions/idempotency, encrypted relational records, receipts, session rotation, membership removal and deletion preserving the usage ledger. Test server/cluster stopped and task-owned binaries removed |
| Docker containers, Redis, BullMQ, MinIO/S3 and proxy integration | Blocked locally: Docker is not installed; CI configured, not yet run. The isolated PostgreSQL test does not verify these integrations |
| AWS deployment, TLS and restore drill | Not performed; reference deployment only |
| Physical-device audio, battery and push | SM-F766B native English TTS engine completion is verified; human audibility, microphone recognition, multilingual quality, battery and push remain unverified. No microphone/notification permissions were automatically granted |

Native JVM tests exercise the shared production URL/download policy: release HTTPS enforcement; explicit debug loopback hosts; credential/fragment rejection; actual loopback Authorization transmission without Cookie/provider headers; rejected redirects that never contact the destination; the exact 4MB bound; oversize/empty streams; and cancellation before writes. Deadline tests cover integer codec types, omission, the inclusive 48-hour future bound, expired timestamps and invalid extremes. Request-ID tests cover UUID/all allowed ASCII characters, inclusive 1/128-character bounds, explicit null/non-string codec types and rejection of whitespace, punctuation, controls and Unicode. These tests do not execute Android Handler scheduling, MethodChannel callback races, TTS/MediaPlayer or iOS URLSession; they do not replace physical-device verification. CI runs `:app:testDebugUnitTest` after building the debug APK.

## API security and correctness

Validate registration simulator isolation; expired OTP and rate limits; refresh rotation/reuse; logout/revocation; invite expiration and role authorization; direct/group/broadcast recipients; unauthorized realtime subscriptions; removed-member cache/audio access; audio signature/expiry/recipient language; account deletion/export; blocked/muted users; input/body-size limits; duplicate and concurrently submitted idempotency keys; pricing version/reservations/quotas; provider timeout/circuit recovery; numerical-token changes; retention and orphaned audio; webhook replay and server-derived subscription entitlements.

Use at least two independent groups with overlapping language preferences and users. A group admin must not obtain another group's profiles/messages/usage through a guessed ID. Run the same checks through the proxy and WebSocket gateway. Test PostgreSQL restarts and queue worker termination around provider calls; verify no duplicate charging or false completion state.

## Physical-device matrix

Record model, OS/API, OEM battery policy, app build/signing, selected TTS voice and whether it is installed. Use non-sensitive synthetic sentences with names, numbers, units and negations. Obtain permission before installing a test app or changing a user's device settings.

| Scenario | Android expected behavior | iOS expected behavior |
| --- | --- | --- |
| First recording permission denial | No recording; visible fallback | No recording; visible fallback |
| First receiving activation | Visible user action; notification permission and Stop notification | User action and ordinary notification prompt; foreground-only explanation |
| Foreground same/different language message | Authorized delivery; installed local voice or visible text fallback | Authorized delivery; available system voice or visible text fallback |
| Server-generated cloud audio | Same-origin signed API link + bearer, bounded fetch, truthful MediaPlayer callbacks | Same-origin signed API link + bearer, bounded RAM fetch, truthful AVAudioPlayer callbacks |
| Audio redirect, oversized body, revoked authorization | Reject; no redirect/token forwarding; no completion receipt; transcript remains | Reject; no redirect/token forwarding; no completion receipt; transcript remains |
| Rapid replay of the same message / automatic playback replaced by manual playback | Every event retains the original `playbackRequestId`; stale callbacks cannot complete/clear the new attempt | Same request correlation; prior utterance/player/task callbacks fail object-identity checks |
| Unsupported/missing local voice | `voice_unavailable`; no wrong-language voice substitution | `voice_unavailable`; text/replay remains |
| Strict headphones-only | Fail closed: system TTS cannot verify/select the private media route; routed-file playback remains work | Accept only an active route reported as headphones; generic Bluetooth/USB routes fail closed |
| Unplug wired/USB headphones during speech | Cancel; never mark completed | Cancel; never mark completed |
| Disconnect Bluetooth during speech | Cancel; measure route-transition leakage on device | Cancel; measure route-transition leakage on device |
| Incoming call / competing audio focus | Stop speech; explicit replay | Stop speech on interruption; explicit replay |
| Silent / vibrate / Do Not Disturb | Reject native speech | Ambient audio obeys silent switch; engine completion does not imply audible output |
| Background with active session | Only already-delivered speech may continue; no guaranteed native networking | Stop speech; opening a notification/user replay is required |
| Quiet-hours boundary during playback or download | Token-bound native deadline cancels with `quiet_hours_started`; no completion receipt; repeat with Dart suspended, replacement playback and device-clock changes | Flutter's foreground boundary cancels playback; backgrounding also cancels native playback |
| 60-second Android idle / 15-minute session bound | Service stops and app clears receiving toggle | Not applicable |
| Process killed, force-stop or reboot | No automatic service resurrection; reopen and re-enable | No automatic speech; configured remote notification behavior must be tested separately |
| Airplane mode with installed voice | Cached text TTS can work; cross-device communication cannot | Test cached speech voice; no cross-device communication claim |
| Wi-Fi/cellular transition / transient outage | Realtime reconnect/outbox behavior; no duplicate message/receipt | Foreground reconnect/outbox behavior; no delivery promise after suspension |
| Notification denied | Receiving activation is rejected on Android | Foreground can operate; fallback notifications unavailable |
| Lock screen / shared device | Generic private notification; verify no unintended transcript exposure | Generic notification; verify actual notification preview settings |
| Logout / account deletion mid-playback | Stop local playback and prevent further authenticated retrieval | Stop local playback and prevent further authenticated retrieval |

Include Android API 26, 33, 34, 35 and 36 where supported, one low-memory/OEM-restricted device and Bluetooth/wired/USB output variants. Test the minimum supported iOS version, current supported iOS and an older/lower-memory iPhone. The exact supported versions must match the pinned Flutter/packages and store requirements at release time.

## Battery and network measurements

Measure an idle baseline, foreground connected receiving, bounded native playback, reconnect attempts and realistic shift usage on the same device with a fixed workload. Capture elapsed time, screen state, network type, message count/duration, bytes transferred, wakelocks, CPU and battery metrics. Do not extrapolate a percentage improvement from a single run. Verify no microphone capture, GPS or polling occurs during native receiving. Test OEM battery restrictions without requesting blanket optimization exemptions by default.

## Commercial release gates

Before a paid pilot, require signed Android/iOS installs; verified identity integration; configured provider quality/privacy/cost review for Tamil, Bengali, Hindi, Odia and English; reviewed quantities/negations/terminology; APNs/FCM delivery tests; store permission review; real billing webhook/restore/cancellation tests; cross-group penetration testing; concurrent-load and offline retry tests; retention/export/deletion evidence; full dependency/secret scans; TLS ingress; monitored staging deployment; database/object/key restore drill; and owner-approved privacy/terms/support processes.

Emergency broadcasts must state their delivery limits. No test or receipt may be described as proof that every recipient heard or followed a safety instruction.
