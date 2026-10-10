# Member identity, translation and language synchronization regression review

Review: 9–10 October 2026. This report covers changes to the existing Flutter/Riverpod app, NestJS encrypted Store and authenticated WebSocket transport. No new dependencies were added.

## Root causes

1. **False Tamil → Hindi unsupported error:** the installed SDK is native Google ML Kit `com.google.mlkit:translate:17.0.3`; its supported language codes include `ta` and `hi`. The backend also already included both. `ProfileDto` targets ES2022, so its omitted optional fields exist with value `undefined`. `Object.assign(user, input)` erased the omitted name/listening language when only speaking language was patched. The persisted review data contained exactly this damage. Group sends tested every recipient's missing listening language against SDK coverage and misreported an unsupported pair. This was a data/update bug, rather than a Tamil/Hindi SDK limitation.
2. **Missing member name:** the same partial-update bug erased names. The channel rendered a missing member name as “Everyone”, and other views did not reject literal `null`, blank or `undefined` names. Personnel labels also overrode valid authenticated profile names.
3. **Stale member preferences:** PATCH updated only the sender's profile. It emitted no member-language event, had no version or update timestamp, and Flutter replaced team snapshots without comparing versions. Playback relied on a recipient-language snapshot made at message creation.

## Fixes

- Update only explicitly supplied, non-null profile fields; reject blank/literal-null names. Use stable authenticated user IDs and valid profile names. Fall back to a valid linked personnel name only for a damaged legacy profile, otherwise “Team Member”. Normalize legacy locale tags; recover a missing listening preference from that person's valid spoken preference. Already valid independent preferences remain unchanged. An erased personal name cannot be guessed; the user can rename “Team Member” in Settings.
- Normalize legacy records in the existing encrypted Store. File migration persists at initialization; PostgreSQL reads normalize projections and the next transaction persists repairs. No users, memberships or tokens are re-keyed. No relational schema/dependency changes are needed because these profiles use existing encrypted payloads.
- Member projections/events contain `userId`, `displayName`, `spokenLanguage`, `listeningLanguage`, `updatedAt`, `version`. Atomic updates increment the server version; optimistic concurrency returns 409 for stale writes. `PATCH /users/me` remains authenticated and cannot target another member.
- Publish `member.language.updated` only to authorized teammates through existing WebSockets/Redis; send full authorized `team.members.snapshot` after socket authentication. Flutter applies events to the matching user ID and ignores stale/duplicate versions. REST snapshot merges retain newer events. Join/reconnect requests arriving during a sync trigger one subsequent sync.
- Flutter immediately displays its own edits, persists an account-bound pending profile cache, serializes changes, and retries on reconnect/resume. Version conflicts fetch authenticated current state and rebase pending fields. Another person's preferences never overwrite this device's preferences. Logout clears pending changes and guards in-flight operations by session generation. No preference polling or background wakeup was introduced.
- Free device delivery/replay targets each receiver's current listening language. The backend projects current target languages and Flutter checks its current preference again at playback. No original-audio or paid-cloud fallback occurs after a device-translation failure.
- ML Kit model downloads, offline download failures, unsupported languages, initialization failures, inference failures and timeouts have distinct errors. Translators close after success/failure/timeout. Language readiness is reported only by actual model callbacks.
- Names are normalized in team lists/cards, History and speaker labels. History includes authorized sender/recipient names; the active speaker retains stable sender identity.

## Changed files

| Area | Files |
| --- | --- |
| Backend profiles and persistence | `services/api/src/common/profile.ts`, `types.ts`, `store.ts`, `validation.ts`; `services/api/src/users/users.controller.ts` |
| Backend teams, delivery and realtime | `services/api/src/groups/groups.service.ts`; `services/api/src/messaging/messaging.service.ts`; `services/api/src/realtime/realtime.service.ts` |
| Flutter state and native bridge | `apps/mobile/lib/core/member_state.dart`, `app_controller.dart`, `audio.dart`, `shell.dart` |
| Existing display surfaces | `apps/mobile/lib/features/communication/walkie_layout.dart`; `groups/groups_screen.dart`, `groups/team_home_screen.dart`; `history/history_screen.dart`; `settings/settings_screen.dart`; `personnel/personnel_screen.dart` |
| Actual Android ML Kit bridge | `apps/mobile/android/app/src/main/kotlin/com/mine2yourlingo/mine2yourlingo/DeviceTranslation.kt`, `MainActivity.kt` |
| Regression tests | `services/api/test/member-language.test.ts`, `personnel-login.test.ts`; `apps/mobile/test/member_language_test.dart`, `playback_queue_test.dart`, `language_download_test.dart` |
| Hardware SDK checks | `apps/mobile/android/app/src/androidTest/kotlin/com/mine2yourlingo/mine2yourlingo/TranslationSmokeInstrumentation.kt`; `.local/build-translation-smoke.py`; `.local/public-member-state-smoke.cjs` |

## Validation

- Backend build and entire test suite: **40/40 passed**. New real HTTP/WebSocket integration tests cover invited named users, Tamil → Hindi free routing, two-way preference changes, three different receiver preferences, delayed delivery after a change, simultaneous updates, stale/conflicting/duplicate updates, stable device-session recovery, reconnect snapshots, outsider authorization and unsupported Odia without cloud charges.
- Flutter focused state/playback/session regressions: **28/28 passed**. Includes optimistic offline edits, durable pending cache, reconnect flush, independent/versioned snapshot merges, simultaneous edits, version-conflict rebasing, safe legacy names, native failure propagation without cloud/original playback, current Hindi receiver playback and active speaker identity.
- Full Flutter suite: **78/78 passed**. Final state/playback/logout checks after reconnect race handling: **28/28 passed**. Direct Dart analysis: **no issues found**.
- Public internet smoke: **passed** through the actual review HTTPS/WSS address, covering named invited members, two-way preference events, three language preferences, Tamil → Hindi routing, reconnect snapshots and zero cloud charges. Temporary fixture accounts were deleted.
- Existing review data after migration: 4 profiles, 0 invalid names, 0 missing language preferences, 0 missing versions/timestamps and 0 dangling member references.
- Native SDK artifact inspected directly: cached ML Kit 17.0.3 AAR exposes `TAMIL = "ta"`, `HINDI = "hi"`, `fromLanguageTag`, and `getAllLanguages`. Android app build and actual-model instrumentation APK build succeeded. The instrumentation includes Tamil ↔ Hindi, Tamil ↔ English, cached offline inference and an offline missing-model failure check.
- **Physical inference verification is pending:** both USB devices disconnected before the instrumentation could run. No downloaded-model or linguistic-success result is claimed from an unexecuted test. Tablet installation of the first fixed APK succeeded; phone disconnected during install. Final installation/verification must use the refreshed endpoint build described below.
- These unit/integration tests exercise actual app/backend control flow. Test doubles do not establish linguistic quality. Hardware inference uses synthetic test phrases, never user audio/transcripts.

## Genuine SDK limits

[Google's supported language list](https://developers.google.com/ml-kit/language/translation/translation-language-support) includes Tamil and Hindi. [Android integration documentation](https://developers.google.com/ml-kit/language/translation/android) requires Android API 23+ and downloaded models before translation; this app's minimum SDK is 24 and the connected tablet reports API 36. Initial model download needs internet and storage. Cached inference runs locally. Speech recognition and text-to-speech are separate Android services with separate language/voice availability.

[ML Kit translation limitations](https://developers.google.com/ml-kit/language/translation) state that non-English pairs use English as an intermediary and quality should be evaluated for the use case. Odia, Malayalam and several other selectable Indian languages are absent from ML Kit translation coverage. Selecting them does not silently purchase cloud translation. Cloud requests continue to require the eligible plan, provider consent, configured provider and validated spending limits. Review budgets remain zero.

## Review deployment status

The original temporary Cloudflare address expired with “Unauthorized: Tunnel not found” while the Mac was suspended. The replacement temporary address also expired during the extended review. Local backend health still returns HTTP 200. No permanent hosting account/domain is configured. The earlier public HTTPS/WSS integration pass remains valid evidence of routing and authorization; it is not a claim that an expired address is currently online.

The first fixed Android APK built successfully and installed on the tablet without resetting profiles or teams. The phone disconnected during install. A later APK refresh for the temporary address exceeded the build time guard and was cancelled; it did not replace the first verified APK. That APK's default review address is now expired, so the address must be updated in Settings or in the next deployment build before internet review resumes.

Verified fix APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`.
SHA-256: `171d0a06cedd62232efe566b003a3dff276dc022a4dadb545607898889e07343`.
Prepared real-SDK instrumentation APK: `apps/mobile/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`.

**Remaining physical checks:** reconnect/unlock the tablet and phone, restore a live review endpoint, finish installs and run actual ML Kit inference. Android-model inference and offline model availability have not been falsely marked successful. No physical microphone or human linguistic-quality check is claimed by automated routing/unit tests.
