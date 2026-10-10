# Team, phone login and regional-language review — 9 October 2026

**Historical build record.** The newer [free speech review](free-voice-review.md) supersedes the UI, AI path and installation evidence below. The team/login/personnel instructions remain applicable.

This update replaces the earlier minimal theme with the illustrated sky, cream, cyan/blue controls and rounded white cards from the supplied 3.png reference. Controls are live widgets. Home prioritizes teams and their members; management is in Settings. The reference informs the layout and colors; the worker scene is newly generated artwork.

## Phone login for development

1. Enter your phone number. Indian numbers can use 10 digits; other countries need the country code.
2. Tap **Get login code**. In this development build the code is **123456**; no SMS is sent and phone ownership is not verified.
3. Enter the code, your name for a new account, the language you speak, and acknowledge the privacy information.
4. Later logins with the same phone return the same account, teams and member records. A returning account keeps its existing name and language.
5. If already signed into an earlier name-only review account, use **Settings → Link phone login to this account** before signing out. Enter the phone and development code there to retain that account's existing teams. A phone already linked to another account cannot take over this one.

Fixed-code login is disabled in production. The same phone flow delegates to a configured verified OTP provider when development authentication is disabled; missing provider configuration fails visibly.

## Teams and direct speech

1. Open **Settings → Manage teams & invitations** to create a team or join using an invite token.
2. The creating account is the team admin. Open its team details and create/copy an invitation.
3. The other person signs in with their own phone number and enters the token in **Join team**. Tokens expire; get another from the admin if needed.
4. Home and Team show joined accounts with their name, listening language, photo and work summary when linked to a personnel record.
5. Tap a member's microphone to open a direct conversation. Tap **Tap to speak**, speak, tap again to stop, check the text and recipient, then send. **Type instead** is available.
6. To address everyone, use **Speak to your team**. An employee record without a joined account cannot receive a message; invite the person and link their account first.

The review sheet names the selected recipient. A changed team, recipient or signed-in account invalidates that review instead of sending to a different audience.

## Member records in Settings

**Settings → Team member records → Choose a team → Add member record** is available only to that team's admins. Maintain name, optional phone, profile photo, role, site, joining date, work description, active/on-leave/left status, salary amount in INR and day/week/month period. Link a record to the person's joined team account to show their photo/work summary in the directory.

After saving, the editor supports:
- Uploading, replacing, viewing, hiding and deleting a private Aadhaar/identity photo for manual review.
- Recording salary payments with amount/date/note, and correcting mistakes by deleting an entry.
- Recording work with date/hours/description, and deleting an incorrect work entry.
- Editing or deleting the complete member record.

The worker's permission is recorded before storing personal details. Profile photo, joining date and work summary are shared inside the team. Salary, payment history, detailed work logs, phone and identity images are admin-only. There is no Aadhaar-number field, UIDAI verification, eKYC or automatic verified badge. Images are resized before upload; originals are unchanged. Identity files are encrypted in private storage and served only through authenticated, freshly authorized, no-store responses. Personnel data is not written to the mobile SQLite cache; identity previews are cleared on backgrounding and account/role changes close private views. Android personnel routes prevent screenshots/task previews. The pilot bounds each team to 100 personnel records and each record to 500 payment/work entries.

## Language selection and automatic downloads

The default set remains **Tamil, Bengali, Hindi, Odia and English**. The picker also includes Telugu, Kannada, Malayalam, Marathi, Gujarati, Punjabi, Urdu, Assamese, Bodo, Dogri, Kashmiri, Konkani, Maithili, Manipuri, Nepali, Sanskrit, Santali and Sindhi. Licensed script fonts are bundled so these language names can be read.

Selecting an additional language in spoken/listening preferences, onboarding or the local voice test starts preparation for that language only. It does not download all extra languages on startup. Android 13+ requests the speech model through the selected recognition service; Android 14+ can report actual progress/success/scheduled/error callbacks. Requests are queued and the recognizer is retained until the callback or bounded timeout. Microphone permission, if required by the service, is requested without starting a recording.

**Settings → Languages & downloads** distinguishes:
- The reading voice detected by Android's TTS engine.
- Speech-model download progress and confirmed installation.
- Scheduled/unconfirmed downloads.
- Unsupported engines/languages, network failures and manual installation.

A scheduled/requested download is never labelled installed. Use **Check / retry** to query again. The default five are the existing default choices, not a claim that every phone ships with their voice packs.

Reading voices are separate from recognition models. When an extra language lacks a detected reading voice, the app opens the current engine's installer/settings automatically once for that selected language. Confirm any vendor prompt and select the language there, then return and refresh/test. Android does not offer a universal silent TTS-pack installer; some engines do not offer every language. The browser cannot download Android speech models. Unsupported language output never silently switches to another language.

Use **Settings → Voice & recording → Test voice on this phone**, or the same button before login. Its **Read my words aloud** checkbox tests recognition/readback on one phone, without groups, outbox or the app server. Unknown sample phrases start empty so the user can enter words in the selected language.

Primary platform references: [Android SpeechRecognizer downloads](https://developer.android.com/reference/android/speech/SpeechRecognizer), [TTS engine installation](https://developer.android.com/reference/android/speech/tts/TextToSpeech.Engine), [Google Android voice-data settings](https://support.google.com/accessibility/android/answer/6006983/text-to-speech-output?hl=en-GB). Photo selection on other platforms uses the official [Flutter file_selector plugin](https://pub.dev/packages/file_selector).

## Wi-Fi review

API address: **http://Karthikeyans-MacBook-Pro.local:3100/v1**. Keep the Mac awake with its API running and use the same Wi-Fi. API traffic does not depend on USB or adb reverse. Off-site/mobile-data access still needs hosted HTTPS/WSS, which is outside the chosen same-Wi-Fi review.

Browser preview: [http://127.0.0.1:4174](http://127.0.0.1:4174). Reload after the build update.

## Artwork and font provenance

The original supplied logo is preserved. The transparent logo remains at apps/mobile/assets/logo-transparent.png; its generation prompt is recorded in [the earlier worker review](worker-review.md).

The worker illustration is at apps/mobile/assets/team-hero.png. It was generated with the built-in image-generation tool using the supplied 3.png as reference and copied from:
`/Users/utvyakta.com/.codex/generated_images/01a11bef-14a7-7773-b2dc-6d4c9f8227a5/exec-7ac2d211-4b92-4f2f-be87-0c12804c2373.png`.

Generation prompt:

> Create a production mobile app hero/background illustration matching the attached Mine2YourLingo screenshot precisely in style, colors and composition. Only the scenic illustration, no screenshot UI. Wide landscape 1536x1024. Soft cyan sky fading to creamy white at left; pale fluffy clouds, softly blurred construction cranes and city in the background, greenery and warm yellow sunlight near the lower edge. On the LOWER RIGHT, the same friendly polished 3D cartoon Indian male construction worker in orange safety helmet and blue shirt with neon safety vest facing an Indian female construction worker in yellow helmet and bright green safety vest, both holding smartphones and conversing. Cyan and green speech bubbles with white sound waves between them. Keep upper left and middle left empty pale sky for app typography. Recreate the characters' expressions and clothing style from the reference. The lower edge can have a gentle teal/blue gradient. No text, no letters, no numbers, no logos, no status bar, no cards, no buttons, no watermark. Keep the attractive illustrated workplace palette very close to the reference.

Fonts come from the official google/fonts repository, including the regional Noto families. Each SIL Open Font License is retained alongside its font and included in the application's About/Licenses page.

## Verification and installed artifact

Verified on 9 October 2026:

- API build and all **25 tests** pass, including phone-account stability, production development-code rejection, admin authorization, personnel validation, encrypted identity-image access and deletion.
- All **50 Flutter host tests** pass. The five responsive/golden comparisons also pass without regeneration; phone/desktop conversation, phone directory/login and enlarged-text layouts were checked. Direct `dart analyze` reports no issues.
- Android review APK builds successfully in 225.2 seconds; Android v2 signature and packaged fonts, illustration, bundled SQLite and stable Wi-Fi hostname were verified.
- Installed with `adb install --user 0 -r` on **Samsung SM-F766B** and **Lenovo TB373FU (HAE00ZXX)**, preserving existing app data. Both launch successfully with no scoped AndroidRuntime/Flutter startup errors. Tablet MainActivity is resumed. The tablet's existing session refreshes and its group/profile requests return HTTP 200.
- Both devices reach the hostname health endpoint over Wi-Fi with HTTP 200; USB reverse forwarding is absent. The earlier SM-A076B is disconnected and has not received this increment.
- JavaScript web release builds successfully in 282.7 seconds. Preview HTML, application script, illustration, regional font license, SQLite WASM and Drift worker return HTTP 200 with COOP/COEP isolation headers. New phone-login, directory and language controls are present in the compiled application. This is build/asset verification, not automated browser interaction.

APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` (139,783,816 bytes), SHA-256:
`b702e6603b5183ae5f93b75da2ce4216595ac1d8afd1fca16ac6ec86a13d4a78`.

Logs: `/tmp/mine2yourlingo-team-api-tests.log`, `/tmp/mine2yourlingo-team-mobile-tests.log`, `/tmp/mine2yourlingo-final-goldens.log`, `/tmp/mine2yourlingo-analyze.log`, `/tmp/mine2yourlingo-android-build.log`, `/tmp/mine2yourlingo-team-web-build.log`.

Host tests and engine callbacks do not certify linguistic accuracy, audibility or human comprehension. Tamil and English were reported working by the user; additional real speakers and noisy-site trials are still needed. Cloud translation/STT/TTS providers and production OTP hosting are not configured for this review.
