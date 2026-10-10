# Mine2YourLingo mobile

Flutter 3.47.6 / Dart 3.13.5 client for Android, iOS and web. Uses the supplied logo, local licensed Inter/Indic fonts, Riverpod, GoRouter, Dio and Drift. Dependencies are pinned in the pubspec/lockfile.

## Run

```bash
flutter pub get
flutter run --dart-define=API_URL=http://127.0.0.1:3100/v1
```

The API must run separately. The current installed Wi-Fi review uses `http://Karthikeyans-MacBook-Pro.local:3100/v1`, with no USB forwarding. Start the Mac API with `HOST=:: bash scripts/dev-api.sh` and keep all devices on the same Wi-Fi. A physical device for off-site/production use needs a reachable HTTPS API address. An alternate loopback debug build can still use `adb reverse tcp:3100 tcp:3100`. For web, run `bash ../../scripts/build-mobile-web.sh` from this directory or `bash scripts/build-mobile-web.sh` from the repository root. Start `python3 scripts/preview-mobile-web.py` from the root to serve [the preview](http://127.0.0.1:4174) with SQLite worker isolation headers. The web build downloads the pinned official SQLite WASM runtime with SHA-256 verification and compiles the Drift worker. These dependency binaries and generated assets are excluded from Git. The default Dart constant uses port 3100; the Wi-Fi review overrides it at build time. `MIGRATE_USB_REVIEW=true` explicitly migrates saved loopback addresses, and the exact optional `REVIEW_PREVIOUS_API_URL`, on debug startup while retaining accounts/groups; other custom endpoints and production/profile builds retain their address.

The [walkie review](../../docs/testing/walkie-review.md) records the current screenshot-based layout, tablet APK and incomplete full rerun caused by unavailable iCloud test files. The [free speech review](../../docs/testing/free-voice-review.md) covers the compact direct conversation, real sound-level equalizer, 60-second utterance-restarting device dictation and free Android translation. Cloud AI is restricted to active Pro accounts; this review has zero API AI budgets.

The [team-member review guide](../../docs/testing/team-member-review.md) covers the illustrated reference theme, development phone code, member directory, admin personnel records and on-demand regional speech downloads. The transparent logo and local voice test are retained; management is in Settings. The test works before login and does not send team messages.

## Implemented flows

Onboarding uses phone login with a fixed development code (123456, no SMS and no phone verification); repeated sign-ins retain the account. A configured verified OTP provider replaces that development flow in production. Existing review accounts can link a phone in Settings without losing teams. Users choose independent spoken/listening languages, create/join private groups, invite members, send reviewed text or recorded voice, choose direct/group audiences, view authorized translations and truthful recipient states, maintain an idempotent local outbox, save custom source phrases and manage consent/privacy/settings.

Device speech recognition depends on installed language support and may use the device vendor's network service. Cloud PCM/WAV transcription requires configured server providers, confirmed prices and consent. Source phrase text is English and labelled; no built-in translation is invented. Material navigation labels have five-language translations; full screen localization remains a release task.

Native playback prefers authorized server-generated audio, then available installed TTS. Android uses bounded foreground playback sessions; iOS is foreground-only. Device-local quiet hours and per-group mute pause automatic speech while preserving transcripts and manual replay. Android quiet-hour deadlines bind to native utterance tokens and cancel without completion; actual timing/clock/route behavior needs device testing. Native background network delivery, FCM/APNs and strict Android private routing remain unimplemented. Browser speech uses installed voices for manual replay; automatic receiving and native receipts are disabled because mutable browser callbacks cannot prove message identity. See [native limits](../../docs/architecture/native-audio.md).

SQLite transcripts/outbox are protected by OS storage, not app-level encryption or E2EE. Logout/account changes clear cached account content and queued audio. Successful server processing/discard removes outbox items. Production needs reviewed retention, encryption, provider agreements and device testing.

## Verification

Before the walkie layout change, the free-speech increment passed all **59 host tests** with normal assets/widget tracking, concurrency 1 and stable-hostname review defines. Seven responsive/golden comparisons pass, including direct phone/tablet controls with a latest reply and no main-page scroll at normal text size. Dictation tests cover silence restarts, cancellation during initialization and the total recording limit. Input tests cover unavailable-cloud fallback and actual sound-level meter updates. API tests pass all 28 cases. Current build/install evidence is in the [free speech review record](../../docs/testing/free-voice-review.md).

Current `dart analyze` passes. The final walkie-focused run passes all 23 UI/input/playback tests; the complete rerun remains incomplete due to three unavailable original iCloud test files, as recorded in the walkie review. The previous `flutter analyze` and latest JavaScript web release passed; the Flutter analyzer wrapper currently encounters an SDK Unicode-path framing error after relocation. The latest focused run passes 18 cases: nine playback ownership/receipt regressions, three native channel checks and six privacy/receiving races. It uses one test process with widget tracking/assets disabled, because these cases use neither. The earlier full suite passed 22 onboarding/consent, outbox/purge, privacy/receiving, responsive/golden and policy/channel cases. The complete 32-test host suite passed after disk capacity was restored. The subsequent Wi-Fi increment passes all 35 tests with normal assets/widget tracking, concurrency 1 and the Wi-Fi migration build defines; three endpoint checks also pass without migration opt-in. Golden identities are test-only. Native Kotlin compilation and 15 download/deadline/request-ID tests pass; this is not an APK or physical audio test.

```bash
flutter test --concurrency=1
flutter test test/layout_test.dart --update-goldens --concurrency=1
# Against the isolated local API: creates then deletes its own test identities.
dart --disable-dart-dev --packages=.dart_tool/package_config.json tool/verify_live_contract.dart
```

The live mobile-client script passed 14 HTTP contract checks with English passthrough, no cloud inference. Its submitted receipt transitions are API checks, not actual playback evidence. On the current Mac without Xcode/CLT, use `scripts/test-mobile-local.sh`; it temporarily uses system SQLite for host tests and restores the production pubspec. Run it alone. Native builds retain bundled SQLite. A prior arm64 debug APK built in 111.5 seconds, its v2 signature verified, and it was installed on both TB373FU and SM-A076B (Android 16/API 36). Both devices reach API health over Wi-Fi with USB forwarding removed. Tablet authenticated synchronization is verified; the Samsung was locked/asleep during startup verification and needs the user to unlock/open the app. Swift/iOS and the physical microphone/playback pilot remain unverified. See [release evidence](../../PROGRESS.md).

Playback hardening (9 October): each replay, automatic message and local phrase preview owns a fresh playback request. Automatic speech waits during replay/recording; native events must match both message and request before affecting the queue or receipts. Already-started/completed messages do not automatically replay on a later event. Static analysis passes. All 18 focused regressions and the current browser release rebuild pass. The subsequently completed full host run passes all 32 tests after disk capacity was restored. Prior 22-test/layout evidence remains dated to the preceding increment. The user initially chose browser review, then restored disk capacity and requested Android installation; the debug APK was installed on TB373FU. That earlier Wi-Fi build was installed on both original devices and passed 35 host tests. The current team/login/regional-language increment passes 50 host tests, rebuilds the JavaScript preview and is installed on SM-F766B and TB373FU; SM-A076B still needs reconnection for this update. See the team-member review record for the current APK hash and evidence.

For the installed Android app, follow [the device review guide](../../docs/testing/android-review.md). The [browser review guide](../../docs/testing/first-review.md) remains available.
