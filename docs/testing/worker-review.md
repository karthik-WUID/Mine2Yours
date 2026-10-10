# Worker interface and voice review — 9 October 2026

This is the earlier review record. The illustrated theme, phone login, member records and language downloads are described in the [latest team-member review](team-member-review.md).

The review update uses a quieter navy/blue theme, larger text, a single large Speak button, fewer Home controls and the transparent logo. The voice test is available before sign-in, from the Home checkbox and from Settings. It does not create messages, add anything to the outbox or send to a team. Android's own speech service may use the internet for recognition.

## Test on one phone

1. Open **Test voice on this phone** on the welcome screen, or check the matching box on Home. No account, group or Mine2YourLingo server is needed for this check.
2. Choose a **Test language**. The reading-voice indicator lists installed offline TTS support; it does not certify speech-input support. If Tamil is missing and English is installed, **Try an English test** changes only the local test language.
3. Tap **Play test voice** to test the sample words, or type your own words. Check the phone's media volume and normal sound mode. Playback errors show an explanation.
4. Tap **Tap to test speaking** and allow microphone access when Android asks. Say a short sentence, then tap **Stop and check my words**. Inspect the actual recognized words. The **Read my words aloud** checkbox controls automatic read-back.
5. For missing languages, use **Speech input settings** for recognition or **Reading voice settings** for TTS. These are separate services. Install the required language in the phone's available service, return and use **Check voices again**. Available languages depend on that phone's installed engine; the app does not pretend to download unavailable models.

Native speech waits for the final result instead of treating the early `notListening` status as completion. Repeated attempts use the current callbacks and language. An incomplete reported locale list no longer blocks a requested language before the vendor recognizer tries it. Missing language, microphone permission and speech-service network errors have readable recovery messages. Recognition does not silently substitute a different language. [Android SpeechRecognizer reference](https://developer.android.com/reference/android/speech/SpeechRecognizer).

## Same-Wi-Fi connection

The API address is **`http://Karthikeyans-MacBook-Pro.local:3100/v1`**. The old `192.168.0.101` address became unreachable after DHCP changed the Mac to `192.168.0.104`. Android supports `.local` resolution through its DNS resolver; this hostname was tested from the new Samsung and the tablet over Wi-Fi. [Android DNS resolver documentation](https://source.android.google.cn/docs/core/ota/modular-system/dns-resolver?hl=en).

The review API now binds both IPv6 and IPv4. The tablet initially refused a hostname connection when the server was IPv4-only; hostname health returned HTTP 200 after dual-stack binding. Keep the Mac awake, API running and all participants on the same Wi-Fi. USB is for installation only. Foreground message receiving still requires opening the app; off-site/mobile-data access needs a hosted HTTPS/WSS backend.

Reproduce the server from the repository root:

```bash
HOST=:: bash scripts/dev-api.sh
```

Build from `apps/mobile`:

```bash
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=API_URL=http://Karthikeyans-MacBook-Pro.local:3100/v1 \
  --dart-define=MIGRATE_USB_REVIEW=true \
  --dart-define=REVIEW_PREVIOUS_API_URL=http://192.168.0.101:3100/v1
```

The explicit debug-only migration moves the saved old review IP or loopback endpoint to this hostname and preserves accounts/groups. Other custom endpoints and production/profile builds are retained. Settings includes Retry for reconnecting and readable connection errors instead of raw Dio exceptions. Wi-Fi availability alone does not prove that the app server is reachable.

## Transparent logo

Workspace asset: `apps/mobile/assets/logo-transparent.png`, generated with the built-in image generation tool using the original supplied `logo.png`. The original remains unchanged. Read-only PNG inspection confirms RGBA transparency: 1,080,492 fully transparent pixels of 1,572,864 total. The logo was inspected in Flutter phone and desktop renderings on the app background.

Generation prompt:

> BACKGROUND REMOVAL ONLY. Make a clean transparent PNG cutout of this exact original logo. Preserve the original colored pixels and all original letter shapes, proportions, silhouettes and details; no redesign. The transparent area MUST be empty alpha=0: no color glow, haze, shadow, blur, vignette, black fill, checkerboard or background decoration. The logo shapes and text must be solid opaque colors with clean sharp anti-aliased edges, with no halo outside their edges. Retain intentional white stripes in the helmets/collars. Remove the large white paper-like backdrop surrounding the mark and words, and the white spaces between and inside letters. Keep exact text 'Mine2YourLingo' and tagline 'My Voice. Your Language.'. Crop the canvas to the artwork with a small transparent margin. Crisp professional app asset.

## Verification

- All **44 Flutter host tests pass**, with normal assets/widget tracking, concurrency 1 and the stable-hostname/migration defines. Updated phone/desktop/onboarding goldens were visually inspected; large-text layout passes. Direct Dart analysis has no issues.
- Four endpoint-preservation checks each pass with product and profile flags, even when debug migration and the old-IP define are supplied. This prevents those builds from moving saved server credentials.
- Real Android integration test passes on Samsung **SM-F766B / RZCY7110XXK**, Android 16/API 36. The app's Dio client gets HTTP 200 from the Wi-Fi hostname without API USB forwarding. Installed offline reading locales reported by Android are **en-IN, en-US and ta-IN**. The local test screen plays synthetic English words and receives the native `playbackCompleted` callback. Tamil is listed as installed; its audible output and microphone recognition were not certified by this check.
- The test APK built in 105.2 seconds and installed in 11.3 seconds. The normal application is rebuilt and installed after that temporary test bundle; its final artifact/device record follows below.

Engine completion is not evidence that a human heard or understood the words. Real microphone accuracy and multilingual/noisy-site testing still require actual speakers. Cloud translation, cloud STT/TTS and production identity providers remain unconfigured.

## Normal review app installation

The normal arm64 debug APK built successfully in **99.9 seconds**. Android v2 signing verifies. The packaged kernel contains the stable hostname and excludes the temporary device-test entry point; the transparent logo and bundled arm64 SQLite/Flutter libraries are included. Size: **139,630,283 bytes**. SHA-256: **`c01ab49c9e9ca9f59339b495e63d9b903234ddc656360a4acda0e1ac25eadb6f`**. Artifact: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`. Package `com.mine2yourlingo.mine2yourlingo`, version 1.0.0 (1), minimum API 24, target API 36; debug signing is for review.

Installation on **SM-F766B / RZCY7110XXK**, personal user 0, returned **Success**. Cold launch returned **Status ok** (1,627 ms); the app is the resumed activity with a live process. The normal app successfully fetched `/v1/capabilities` (HTTP 200) from the API. Its scoped AndroidRuntime/Flutter error logs are empty. API USB forwarding is absent. Microphone and notification permissions remain ungranted; the app requests them when the user chooses the relevant action.

The **TB373FU / HAE00ZXX** connected briefly and passed Wi-Fi hostname health, then disconnected before this APK was ready. The earlier **SM-A076B / R9ZL605VTYZ** has not reconnected during this increment. Their previously installed app versions still need the same update; installation does not require deleting their app data. The final APK is ready for them when they reconnect.

The JavaScript web release also rebuilt successfully in **209.7 seconds**, including the new theme and transparent logo. The existing Mac preview at `http://127.0.0.1:4174` serves the new build; reload the browser to update. Its HTML, main JavaScript, logo, SQLite WASM and Drift worker return HTTP 200 with the required isolation headers. Browser interaction/audio was not certified by these HTTP checks. Flutter's optional Wasm app dry-run reports upstream TTS interop findings; this artifact is the successful JavaScript app build.
