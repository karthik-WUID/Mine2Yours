> This guide describes an earlier build. Use [Internet translation review](internet-translation-review.md) for the current translated internet review.

> Current review behavior (9 October): [direct voice and login-free device profiles](direct-voice-review.md). Stop/release sends immediately. The earlier transcript-confirmation workflow below is superseded.

# Walkie-talkie layout review — 9 October 2026

The supplied **4.png** is the visual reference for the new interactive Home and direct-conversation screen. It uses the transparent logo, pastel cyan/yellow/green background, white team and message panels, selectable member cards, a circular blue microphone, vector blue/yellow radios and concentric rings. Phone and tablet layouts adapt to available space; the landscape conversation puts recent messages beside the microphone.

## Use the app

1. Choose your team at the top. Tap a member card for a private direct message, or **Everyone** for the team. A green check means selected; it is not an invented member-online status.
2. **Hold the microphone and speak, then release.** Release opens an editable transcript review. Check the recipient, names and numbers before **Send message**. A quick tap is also available; tap again to stop. Turn Walkie Talkie off for the tap interaction.
3. Recording continues across recognizer pauses, with brief utterance restarts and a **60-second total limit**. The equalizer responds to actual captured level. Cancelling, leaving/backgrounding or releasing during microphone startup prevents a late recording.
4. The speaker control enables/disables **Read replies aloud**, with explicit receiving consent. Keep the receiving app open. The recent-message play button replays the authorized reply in your listening language. Recent rows show actual message text, authors and timestamps; no fabricated waveform recording or duration is shown.
5. **Type instead** remains available. The language button opens language settings. Manage teams, invitations, photos, private identity images, salary and work records through Settings/Manage. Sign in for this review with your phone and development code **123456** (no SMS).

For free/Pro languages, model downloads, provider setup and the local one-phone voice test, see [free speech and Pro AI](free-voice-review.md). Unsupported free translation pairs require configured Pro cloud translation. The current API has zero AI budgets and no paid Sarvam calls.

## Installed devices and actual translation

- Updated **Lenovo TB373FU / HAE00ZXX** with `adb install --user 0 -r`, retaining existing application data. MainActivity was verified resumed at installation; launch succeeds after model tests and the process remains running. The tablet was subsequently dozing; unlock/open the app for review. Existing session refresh, profile, groups, messages and usage synchronize successfully; scoped AndroidRuntime/Flutter startup error output is empty.
- The tablet reaches **http://Karthikeyans-MacBook-Pro.local:3100/v1/health** over Wi-Fi with HTTP **200**. USB reverse forwarding is absent. Keep the Mac awake and the API running on the same Wi-Fi. Off-site/mobile-data access requires hosted HTTPS/WSS.
- Real production ML Kit model inference passes on this tablet in the final APK: English→Tamil and Tamil→Bengali, with instrumentation result **-1**. The test downloads/prepares real models and checks real nonempty translated output; it does not certify linguistic quality or record the microphone. Human speech, audibility, meaning and noisy-site review remain necessary.
- **Samsung SM-F766B / RZCY7110XXK updated on 9 October 2026** with the identical APK using `adb install --user 0 -r`, retaining app data. MainActivity is resumed and the process runs with no scoped AndroidRuntime/Flutter startup errors. Its Wi-Fi hostname health check returns HTTP 200 and USB reverse forwarding is absent. The earlier SM-A076B remains disconnected and still needs this increment. Real model inference above was tested on the tablet; this phone downloads matching translation models on demand.

APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`, **173,594,604 bytes**. SHA-256:
`76bb6b01604c72cd3bf4714450fa3de28aa0f8d70de170db11bf5cf1141e2aec`.

Android arm64 debug build succeeds in **374.1 seconds**. Android v2 signature verifies. The kernel contains current walkie controls, the stable Wi-Fi hostname and translation channel; packaged logo, Google attribution badge, Tamil font and valid original phrase JSON are verified. This is a development APK, not a signed commercial release.

## Browser preview

The current JavaScript release rebuild succeeds (final incremental build **145.3 seconds**). Nonempty HTML, application script containing the new walkie controls, bootstrap, logo, attribution badge, SQLite WASM and unchanged Drift worker return HTTP 200 with COOP/COEP isolation headers at [localhost:4174](http://127.0.0.1:4174). Reload the preview. Browser asset/build checks and Flutter goldens are verified; no automated browser interaction or Android model execution in the browser is claimed.

## Test evidence and environment limitation

The original free-speech increment completed **59 Flutter tests**, **28 API tests** and clean Dart analysis before this layout change. In the new layout run, **39 executed Flutter tests pass**, including all seven normal golden comparisons and all new member selection/hold-release/startup-cancellation/equalizer cases. A full rerun is incomplete: four older test files were iCloud dataless placeholders returning zero bytes, so their test entry points could not load. Their failures are recorded rather than counted as passing. The original playback ownership test source was subsequently recovered byte-for-byte from the earlier compiled test cache. The final focused run passes **all 23 tests**: seven normal layout/golden comparisons, four input/hold/equalizer cases, three onboarding/settings cases and nine playback ownership/receipt regressions. Three files remain unavailable:

- `apps/mobile/test/local_store_test.dart`
- `apps/mobile/test/privacy_race_test.dart`
- `apps/mobile/test/receiving_policy_test.dart`

Make those original files available locally from iCloud/backup before a complete suite rerun. They have not been replaced with simplified tests. Existing phrase JSON and web entry assets were recovered from the preceding verified release artifacts. Current direct Dart analysis reports no issues.

Phone 390×844 and landscape tablet 960×600 conversation goldens, including a real fixture reply, were visually inspected. Normal-size main controls fit without page scrolling; horizontal member lists and recent messages can scroll internally. Enlarged accessibility text retains a scroll fallback.

Logs: `/tmp/mine2yourlingo-walkie-focused-tests.log`, `/tmp/mine2yourlingo-walkie-mobile-tests.log`, `/tmp/mine2yourlingo-free-api-tests.log`, `/tmp/mine2yourlingo-free-analyze.log`, `/tmp/mine2yourlingo-android-build.log`, `/tmp/mine2yourlingo-translation-smoke-device.log`, `/tmp/mine2yourlingo-walkie-web-final.log`.
