# Free speech and Pro cloud AI review — 9 October 2026

The Android review now uses the phone’s speech recognition, free Google ML Kit translation and installed reading voices. API AI spending is disabled (daily and monthly budgets are zero). No paid AI account or API key is needed for the supported free translation pairs. This is a same-Wi-Fi development review, not a production deployment.

The newest [walkie-talkie layout review](walkie-review.md) supersedes the tap-to-speak layout and records the current tablet APK and test rerun limitation.

## Try a direct conversation

1. Sign in with your phone number and development code **123456**. This does not send an SMS.
2. Create or join a team through Settings; invite the other account and choose each person’s spoken and listening languages.
3. Tap a member on Home/Team to open their direct conversation. Tap the microphone, speak, then tap again to stop. Pauses keep the recording session open, up to **60 seconds total**. The phone recognizer may briefly restart between utterances; it is not gapless or always-on background listening.
4. Check the recognized words and named recipient before **Send message**. **Type instead** also works.
5. Keep the other app open. Enable **Read replies aloud** there if automatic playback is wanted. Otherwise use the reply’s listen button or History. Google translation models download on first use over Wi-Fi; retry if the first download takes longer.
6. For a test without another person, use **Settings → Voice & recording → Test voice on this phone** and its **Read my words aloud** checkbox. This tests recognition and installed reading voices without sending a message.

The microphone equalizer responds to actual captured sound level. Fonts, spacing and the direct conversation controls are compact. Phone 390×844 and landscape tablet 960×600 layouts fit the main direct controls and latest reply without main-page scrolling at normal text size. Large accessibility text and long lists retain scrolling. Member administration, identity photos, salary and detailed work records remain in Settings with admin authorization.

## Free regional languages

Free translation supports **Tamil, Bengali, Hindi, English, Telugu, Kannada, Marathi, Gujarati and Urdu** among the app’s choices. Speech recognition and reading voices are separate device services and may support a different set. Selecting an extra language starts its preparation on demand; actual completion is displayed only after the service callback. The five default choices are not a claim that their models or voices are preinstalled. Default free translation models download on first translation use.

Odia, Malayalam, Punjabi, Assamese and other unsupported device-translation pairs need the Pro cloud path. The app fails visibly for unsupported pairs instead of presenting original text as a translation. Same-language messaging still works without translation. The browser preview cannot run the Android translation models.

ML Kit runs inference on the phone; model downloads need internet/Wi-Fi, and text is not uploaded to an AI provider. Team message text still travels through the app’s authorized API. Translations show the official Google Translate attribution. Translation is fallible; the numerical guard on automatic speech does not certify meaning, quantities written as words or safety instructions. Review with real speakers before site use.

References: [Google Android translation guide](https://developers.google.com/ml-kit/language/translation/android), [supported languages](https://developers.google.com/ml-kit/language/translation/translation-language-support), [translation terms](https://developers.google.com/ml-kit/language/translation/translation-terms), [Google attribution notices](https://docs.cloud.google.com/translate/attribution).

## Pro and real phone login

Cloud transcription, translation and speech are checked against an **active, unexpired, server-verified Pro subscription** before provider requests, including cached transcription and later priced stages. Trial, Basic, expired and past-due accounts cannot use the paid AI pipeline. Free messages use their normal plan message/team allowances without AI reservations or provider consent.

The Sarvam adapter is implemented and tested against local HTTP fixtures, but no live Sarvam credentials are configured or paid calls made. When Pro cloud languages/quality are needed, create a Sarvam API account, configure its key in the ignored server environment, review versioned positive prices/budgets and provider consent, and use verified Pro entitlements. Do not paste keys into chat. Sarvam lists 23 languages for transcription/translation and 11 for Bulbul reading voices; unsupported voices fall back only to a matching installed device voice.

For production phone OTP, the existing adapter uses **Twilio Verify**. It needs an account, a Verify service and server-only credentials. SMS verification has provider charges; keep the development code during this review. Buying a login provider is independent of Pro AI access.

References: [Sarvam models](https://docs.sarvam.ai/api/getting-started/models), [Sarvam pricing](https://docs.sarvam.ai/api/getting-started/pricing), [Twilio Verify API](https://www.twilio.com/docs/verify/api), [Twilio Verify pricing](https://www.twilio.com/en-us/verify/pricing).

## Connection

Keep the Mac awake and its API running, and use the same Wi-Fi. The Android endpoint is **http://Karthikeyans-MacBook-Pro.local:3100/v1**. USB forwarding is not required. Mobile-data/off-site operation requires hosted HTTPS/WSS. The web preview is [localhost:4174](http://127.0.0.1:4174), for layout and typed-message review.

## Verification

- Before the walkie layout change, all **59 Flutter host tests** passed, including dictation restarts, cancellation during initialization, the 60-second limit, unavailable-cloud fallback, real-level meter updates, privacy/playback policy and seven responsive/golden layouts.
- All **28 API tests** pass, including free authorized/idempotent zero-cost messages, Pro gating, cached-transcription revocation and Sarvam wire contracts. Paid Sarvam inference is not tested.
- Direct Dart analysis reports **no issues**.

Current native installation, actual English→Tamil/Tamil→Bengali model inference and the layout verification are recorded in the [walkie review](walkie-review.md). Physical microphone audibility, linguistic quality, network interruptions and background delivery still require human/device review.
