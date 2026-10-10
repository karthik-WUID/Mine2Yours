# Android first review

The current network review uses `http://Karthikeyans-MacBook-Pro.local:3100/v1` on this Mac. Keep the devices on the same Wi-Fi, the Mac awake and its dual-stack API running. USB is used to install the update; communication uses Wi-Fi without forwarding. See the [latest worker interface, voice-test and installation record](worker-review.md). This debug review uses development identities; off-site/mobile-data access requires a hosted HTTPS/WSS API.

1. Open **Mine2YourLingo**, select **Get started**, enter a display name and choose **English** for the initial communication check. Other language selectors/fonts can also be inspected.
2. Open **Team**, create a private group and generate an invitation. Treat its expiring token as a secret.
3. Use the [Mac browser preview](http://127.0.0.1:4174) as a second development identity; choose English and join the invitation from Team.
4. Send a reviewed English text such as **Hello team** and inspect delivery/history on both clients. English-to-English preserves the original source text; it does not test AI translation.
5. Review History, phrases, independent spoken/listening languages, consent, quiet hours, group mute and privacy controls. Recording/receiving prompts request permission when needed; microphone and notification permissions were not granted during installation. Native replay depends on an installed voice for the selected language and must still be physically tested.

Real translation, cloud STT/TTS, OTP and purchases are unconfigured and fail visibly. Provider consent defaults off. A multilingual voice pilot requires configured, reviewed providers/prices, appropriate voices and actual speakers.

## Initial USB build evidence — 9 October 2026

- Complete Flutter host suite: 32 tests passed with normal assets/widget tracking, concurrency 1. Live mobile/API contract: 14 checks passed and its test identities were removed.
- Integrated debug build: `assembleDebug` passed in 282.1 seconds, targeting Android arm64; APK includes arm64 Flutter and bundled SQLite libraries.
- APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`, about 100 MiB; Android v2 signature verified. Package `com.mine2yourlingo.mine2yourlingo`, version 1.0.0 (1), minimum API 24, target API 36. This is debug signing, not a production release signature.
- SHA-256: `d4e252ee974964b3f7274d9e3cf9bb12e04d9ff7c593e62db5cb0b02805b3915`.
- TB373FU: Android 16/API 36, arm64-v8a. `adb install -r` returned Success; cold `am start -W` returned Status ok. The app remained the resumed activity with a live process and no scoped AndroidRuntime/Flutter error logs. Device HTTP health returned 200 through USB forwarding.

These checks verify build, installation, basic startup and connectivity. They do not establish physical microphone/playback quality, audibility, noisy-site accuracy, background delivery, interruptions, battery usage, billing or production readiness. See the [device test matrix](README.md) and [release tracker](../../PROGRESS.md).

## Earlier second-device USB installation (superseded)

The earlier debug APK was installed and launched on Samsung SM-A076B (Android 16/API 36, arm64) on 9 October 2026. Installation returned Success, cold launch returned Status ok, and device health returned HTTP 200 through USB forwarding at that stage. No microphone/notification permission was automatically granted. The current review uses direct Wi-Fi and does not require restoring USB forwarding. Both identities must join the same group using Team → Invite members → Copy invitation on the group administrator’s device, then Team → Join with invitation → paste the complete token → Join group on the new device. Invitations expire after 24 hours. Physical audio and two-device message delivery remain manual review tasks.

## Reproduce the Wi-Fi setup

From the repository root, start the same development backend with network binding:

```bash
HOST=:: bash scripts/dev-api.sh
```

Build the Android review from `apps/mobile`, using the Mac’s Wi-Fi hostname:

```bash
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=API_URL=http://Karthikeyans-MacBook-Pro.local:3100/v1 \
  --dart-define=MIGRATE_USB_REVIEW=true \
  --dart-define=REVIEW_PREVIOUS_API_URL=http://192.168.0.101:3100/v1
```

`MIGRATE_USB_REVIEW` is an explicit debug-only option for this same-backend move. It replaces saved loopback review endpoints and the exact `REVIEW_PREVIOUS_API_URL` with the build endpoint, retaining identity/session/group/outbox data. Other custom endpoints and production/profile builds are retained. Moving to an unrelated server should use Settings → Server connection, which logs out the old account.

This review uses HTTP/WS on the private Wi-Fi network; release configuration requires HTTPS/WSS. Authorized native cloud-audio download guards still reject non-loopback HTTP. Installed local voices remain available for review, while real cloud providers remain unconfigured. Native background networking/push delivery remains pending: keep the app in the foreground to test live receiving.

## Earlier IP-address Wi-Fi build evidence — 9 October 2026 (superseded)

The arm64 debug APK rebuilt successfully in 111.5 seconds with the Wi-Fi API URL and migration flag. Android v2 signing verifies, and the packaged debug kernel contains `http://192.168.0.101:3100/v1`. Its SHA-256 is `c3f48a3512bab98d212fb50f07e81f45a65f8280fd506a69312aa6be38b973b1`, superseding the initial USB APK above. All 35 Flutter host tests pass with those build defines; the three endpoint checks also pass without opt-in. Three standalone product-flag checks confirm that saved endpoints are retained even if the migration flag is supplied. Direct Dart analysis passes; the Flutter analyzer wrapper encountered an SDK Unicode-path framing error after relocation.

The Mac API now listens on the network. Both devices returned HTTP 200 from its Wi-Fi address, and USB port forwarding for port 3100 was removed on both devices. The Mac uses `192.168.0.101`, TB373FU `192.168.0.103`, and SM-A076B `192.168.0.100` for this review; DHCP may change these addresses later.

Both Wi-Fi APK updates returned Success. Tablet launch returned Status ok, and its existing session refreshed successfully before authorized group/message/profile/usage synchronization returned HTTP 200. A persistent API connection from its Wi-Fi address is present. Samsung launch returned Status ok with a live process and no scoped startup errors, but Android reports its screen locked/asleep and the app paused; the user must unlock/open it for live foreground receiving. Installation did not clear app data or automatically grant permissions.
