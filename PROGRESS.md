# Mine2YourLingo implementation and release tracker

Updated 9 October 2026. **Runnable engineering foundation; commercial release is not approved.** Live multilingual quality, locked-phone delivery, measured latency/battery, store purchases and deployment have not been certified or fabricated.

The latest [walkie layout review](docs/testing/walkie-review.md) records the installed tablet APK, actual free model inference, Pro-only cloud gates and the incomplete full rerun caused by three unavailable original iCloud test files.

## Current deliverable

Flutter source, native Kotlin/Swift audio, NestJS API, PostgreSQL migration, React admin, configurable real provider adapters, private message orchestration, cost/billing controls, CI, Docker definitions and engineering guides are implemented. The supplied logo and reference design are used throughout. Groups and communication directions are domain-independent.

Local API uses port 3100, admin port 5173 and compiled mobile preview port 4174. An unrelated application on port 3000 was preserved. Missing real providers and paid purchases fail closed. Development identity simulation is labelled and rejected in production.

## Implemented slices

- **Identity/privacy:** independent spoken/listening languages; rotating opaque sessions; refresh-reuse revocation; logout; provider consent; devices/session APIs; export/account deletion; transient raw server audio; encrypted server records/assets; default retention; isolated encrypted development persistence.
- **Private groups:** create/rename/description; expiring secret invitations; join/leave/delete; admin/moderator/member permissions; member removal/role administration; membership-change events; authorization on messages/audio/realtime, including removed participants.
- **Communication:** reviewed text; supported device recognition; bounded PCM WAV capture; metered transcription drafts; direct/group/plan-gated broadcasts; one translation/audio per distinct language; sender safety/quantity confirmation; retry/cancel; signed current-member audio retrieval; ordered delivery and native playback states.
- **Reliability:** authenticated metadata-only WebSocket events; reconnect synchronization; Drift cache; durable idempotent outbox with bounded retries/discard; account-content purge; asynchronous logout/sync/playback guards; recording cancellation on backgrounding.
- **Receiving:** explicit consent; foreground automatic playback; installed native voices or authorized cloud audio; bounded Android foreground playback service and persistent Stop notification; foreground iOS audio; focus/disconnection/silent/DND controls. Device-local quiet hours and per-group mute preserve transcripts/manual replay. Android token-bound quiet deadlines stop speech even if Flutter is suspended; physical timing remains unverified. Replay and phrase previews reserve a playback request before async work; native callbacks carry that request ID and cannot release a replacement. Flutter playback/privacy regressions pass; physical native timing/routing remains unverified. Browser automatic receiving/playback receipts are unavailable; manual browser-voice replay is supported.
- **AI/cost:** genuine configurable HTTP STT/TTS; optional OpenAI audio; Google/LibreTranslate-compatible translation; scoped private cache; atomic global/user/group reservations and quotas; confirmed versioned pricing gate; finite/nonnegative plan/global cap validation before reservations and each priced stage; circuit breakers; WAV duration/silence/duplicate-chunk checks; actual usage estimates and cost tools. Synthetic providers exist only in tests.
- **Commercial/admin:** configurable indicative plans; trusted billing-verification gateway abstraction; signed/idempotent webhooks; server-derived entitlements/payment-failure handling; responsive React groups/members, usage/cost, readiness, aggregate admin, privacy export and sessions. Missing store verification never unlocks paid service; unsupported revenue is unavailable.
- **Engineering:** pinned dependencies/locks; real PostgreSQL migration and concurrent Prisma runtime verification; Redis/BullMQ/PubSub and private S3 adapters; versioned OpenAPI; launch/build scripts; Docker/CI definitions; generated development secrets; backup/restore, security, architecture and device-pilot guides.

## Verification evidence

| Check | Result and practical limits |
| --- | --- |
| API build/tests |Passed; 28 tests, including free zero-cost authorization/idempotency, active-Pro cloud restrictions and Sarvam wire contracts, plus including phone login, private personnel authorization/media/deletion and malformed/runtime-invalid budget caps with zero subsequent provider calls. Synthetic audio/provider fixtures validate orchestration and safeguards, not AI quality |
| PostgreSQL migration/runtime |Passed on isolated PostgreSQL 16.14: initial migration, encrypted records, two Prisma clients, concurrent writes/idempotency, receipts, removed-member authorization, refresh replay, deletion and ledger retention. Temporary cluster/binaries removed |
| React build/tests |TypeScript/Vite passed; 19 tests |
| Live admin proxy/API |17 checks passed; test identities/groups removed |
| Live mobile Dio/API |14 checks passed: isolated identities, invitations, English passthrough, idempotency, ordered receipt API and usage. Identities removed; submitted receipts are not actual audio playback evidence |
| Flutter host tests |Free-speech full suite passed all 59 before the layout update. Current layout full attempt passes 39 executed cases, including seven normal goldens and all new hold/member/equalizer cases; older iCloud placeholder tests cannot load. Playback test source recovered from compiled cache; final focused 23 UI/input/playback tests all pass. Three original files still need local recovery. Full latest-suite verification is incomplete; see the walkie review |
| Dart/Flutter analysis |Current `dart analyze` passes with no issues. `flutter analyze` previously passed for playback changes; its latest wrapper fails in Flutter SDK LSP message framing on the relocated path’s Unicode character (character length used instead of UTF-8 byte length). Direct Dart analysis completes successfully |
| Flutter web release |Current walkie JavaScript release succeeds; final incremental rebuild takes 145.3 seconds. Nonempty HTML, compiled controls, logo, Google badge, SQLite WASM and Drift worker return HTTP 200 with isolation headers. No browser interaction or Wasm app build claim |
| Visual review |Phone 390 px, desktop 1440 px and onboarding goldens inspected; enlarged-text layout passes. Fixture identities are test-only. Browser automation unavailable |
| Kotlin compile/native tests |All 6 production files + 3 test classes compile against actual Android 36/Flutter 3.47.6/JVM 17; 15 JUnit tests passed (download, deadline and request-ID validation). Not an APK/hardware test |
| Integrated Android build/install |Current walkie/free-translation arm64 debug APK builds in 374.1 seconds; v2 signature/assets/hostname verified. Installed with data retained on TB373FU and SM-F766B; MainActivity resumed, synchronization succeeds and Wi-Fi health is HTTP 200 with no USB forwarding. Actual production ML Kit English→Tamil and Tamil→Bengali model inference passes on the final APK. SM-F766B is now updated and verified; SM-A076B remains disconnected and needs this increment; audibility and meaning remain human-review tasks |
| iOS build |Blocked: full Xcode/iOS SDK/usable xcrun absent; Swift source uncompiled |
| Dependency audits |API production/admin full npm audits: 0 findings at verification time |
| Config/credential checks |YAML/scripts/plist and limited signature scan including untracked source passed; not a full security/secret-history audit |
| Redis/S3/Docker/AWS |Source/configuration provided; actual Redis/S3/container execution, TLS, KMS and restore drills unverified |
| Real voice/battery/latency/billing |Native English TTS engine smoke passed on SM-F766B; audible quality, microphone recognition, multilingual pilot, battery/latency and billing remain unverified |

Evidence: [API report](services/api/TEST_REPORT.md), [admin report](apps/admin-web/VERIFICATION.md), [mobile guide](apps/mobile/README.md), [test matrix](docs/testing/README.md), [native limits](docs/architecture/native-audio.md).

## Phase readiness

| Requested phase | Current state | Required to advance |
| --- | --- | --- |
| 0 — Foundation |Architecture/source/configuration implemented |Execute staging stack and observability |
| 1 — Identity/groups |Core authorization/persistence verified |Configure OTP; finish optional media, QR/deep links, join approvals and onboarding |
| 2 — Voice pilot |Capture/adapters/pipeline/playback source implemented; **mandatory real-speaker pilot has not passed** |Usable Android/iOS installs, provider credentials/consent/prices, two phones and Tamil/Bengali speakers; repeat Hindi/Odia/noisy-site tests |
| 3 — Reliability |Foreground realtime/outbox/receipts/receiving policy implemented |Native background networking, FCM/APNs, presence, private routing and physical interruptions/offline tests |
| 4 — Cost control |Reservations/private cache/quotas/estimates implemented |Measured invoices/quality, device model evaluation, terminology/fallback and distributed policies |
| 5 — Commercial SaaS |Guarded billing abstraction/plans/admin implemented |Real platform/web verification, order/grace/refund/renewal handling, organizations and operational admin |
| 6 — Release hardening |CI/procedures supplied; no release approval |Load/battery/device/security/accessibility/legal/store/deployment audit and signed candidates |

## Explicit pending functionality

These are implementation gaps, not merely missing credentials:

- Full screen localization/voice-guided onboarding; profile/group images; QR invitation/app links; join approvals; complete permission setup and mobile device-management UI.
- Native background message networking; FCM/APNs delivery and notification inbox/actions; distributed presence; headset/consented reply windows; verified Android private routing and playback-volume preferences. iOS cannot promise unsolicited background speech.
- Local/offline model/voice-pack evaluation/downloads; language identification confidence; domain/glossary normalization/custom terminology; bounded premium fallback routing; explicit upload-progress/durable upload API.
- Reviewed encrypted SQLite/local content protection; fine-grained consent; blocking/abuse/moderation/support/audited investigation; legal retention/deletion schedules and downloadable mobile export.
- Real Apple/Google/web purchase verification and purchase UI; restore/renewal/order/grace/refund/settlement/revenue; enterprise organizations/sites; feature flags/system administration.
- Scoped/paginated Prisma repositories and scalable budget ledgers beyond the initial global advisory transaction; shared rate/circuit state; OTel exporters/alert dashboards; object orphan cleanup; managed KMS/keys; audited restore and deployment automation.
- Performance/load/battery reports, multi-device/network/OS/headset tests, real quantities/negations/meaning quality, complete accessibility review, store assets/signing/compliance and penetration testing.

## Known limitations

- The earlier ENOSPC blocker is resolved. The latest walkie/free-translation Wi-Fi APK is installed on TB373FU and SM-F766B; the earlier SM-A076B is disconnected and still needs this increment. The Mac API now uses `Karthikeyans-MacBook-Pro.local:3100`, with IPv4/IPv6 binding; USB forwarding is removed. See the [latest walkie review](docs/testing/walkie-review.md) for current installation evidence. Same-Wi-Fi access requires the Mac awake with its API running. Release signing and physical microphone/playback, interruption, background and battery verification remain pending; off-site/mobile-data access requires hosted HTTPS/WSS.
- PostgreSQL currently loads normalized tables into memory and serializes mutations using a database advisory lock. This validates persistence and is not a proven scalable production repository.
- Local SQLite cache/outbox is plaintext in OS-protected app storage, not app-level encryption or E2EE. Logout purges content; independent age-based purge/backup/export review remains required.
- Background network receiving is absent. Android may finish already-delivered speech in a bounded session; iOS stops on backgrounding. Strict Android headphone playback fails closed; Swift/device behavior is unverified.
- Native callbacks prove engine progression, not audibility or comprehension. Numeric checks do not certify spoken numbers, units, negation or meaning. Adapter language support does not certify quality.
- Plans/costs are explicit estimates/business hypotheses. A billing trust abstraction is not a store-provider implementation. Docker/CI definitions are not a successful deployment.

## External dependencies

- Reviewed STT/translation/TTS/OTP accounts, privacy agreements, server-only secrets and confirmed pricing. Configure ignored server env files; never paste secrets into chat/source.
- Android release keystore and Firebase; full Xcode/Apple SDK, signing/APNs and iPhones.
- PostgreSQL/Redis/private managed storage, HTTPS ingress, secrets/KMS, monitoring and staging/production accounts.
- Payment/store accounts and legal/tax/store policy review.
- Actual speakers/phones and repeatable noisy-site, locked/background/force-stop, network/headset/battery/security testing.

## Next actions

1. Review the installed Android app using the [device review guide](docs/testing/android-review.md). Full 44-test Flutter suite and prior 14 live mobile/API checks passed; debug APK build, signature, installation, startup and device-to-API connectivity are verified.
2. Complete physical Android audio/permission/routing tests; compile iOS on a real Xcode host and prepare signed release candidates.
3. Configure test providers and execute Tamil→Bengali→Tamil pilot, measuring meaning/quantities, stage latency and actual cost; repeat Hindi/Odia/noise cases.
4. Implement/verify background/notification/private-routing, scalable repository and observability slices before paid deployment.
5. Connect real billing; execute full device/security/load/restore/store matrix and approve a signed release only with measured evidence.


## 9 October — direct voice and login-free plans

Walkie recording now sends the original PCM WAV immediately on stop/release, without a review popup or speech-recognition/AI requirement. Typed/phrase messages submit directly. The automatic device profile preserves current teams by binding an existing authenticated profile before enabling credential recovery. Shared refresh owns token persistence once; delayed 401s retry the newer credential. WebSocket enrollment and native audio playback check the current session. Silver is permanent/free (one site, five members), Gold expands sites/members, Diamond alone permits paid cloud AI. Pricing and billing remain unconfigured and review AI budgets are zero. Original audio remains scoped and encrypted.

Validation: 29 API tests and 19 targeted Flutter tests passed, including real HTTP/WebSocket original-audio transfer between Tamil/Odia preferences, identical replay bytes, idempotency, outsider rejection, site/member quotas, tap-stop/hold-release immediate sending, automatic receiver audio, and concurrent/invalid refresh recovery. See docs/testing/direct-voice-review.md. Device installation verification follows below.


## 9 October 2026 — translated internet review

- Public Cloudflare HTTPS/WSS review endpoint replaces the review LAN address; explicit migration preserves identities and teams. Fixed-code development auth is disabled on the exposed server. The API/tunnel still run on this Mac; permanent hosting is outstanding.
- Walkie capture recognizes words, sends directly without confirmation, then translates/speaks the recipient's listening language on-device. Native model downloads allow Wi-Fi or mobile data. Free translated messages emit message.ready consistently.
- Home Recent Messages removed; History keeps source words and translated content. Member names appear first, in larger two-line cards, and linked personnel names are returned without private personnel data. Settings server-address editor removed.
- Universal transparent speech-bubble/waveform wordmark and launcher icon replace construction imagery. Generated assets copied into the project.
- 30 API tests and 31 focused Flutter checks passed; final capture/layout changes rerun. Public HTTPS/WSS both-direction routing, private access and source transcript checks passed with cleanup of isolated fixtures.
- Final APK 3011b5f1b91f9fc72ec026bf55d78954047bfe74f8dbf4a2950c6ea2de05f117 installed successfully on tablet TB373FU and phone SM-F766B. Both endpoints/profile languages verified; no scoped startup errors; existing profiles and team retained. Tablet native Tamil/English inference and installed reading voices verified. Phone disconnected before its optional native inference check.
- Human microphone/audibility/linguistic quality and different-network test remain review steps; paid Diamond AI remains unconfigured and disabled.
- Current guide: docs/testing/internet-translation-review.md.


## 9 October 2026 — communication mockup / request-rate update

Implemented 5.png communication layout with real team/recipient/language controls, removed Home typing action, fixed receipt-driven request amplification, split verified user send/read/receipt budgets, coalesced message events, and added Retry-After/outbox handling. 31 API tests and 30 focused mobile checks passed; final UI/privacy/session checks (15) passed; targeted Dart analysis clean. Public HTTPS/WSS receipt smoke passed 72 acknowledgements, private routing and zero paid AI usage. Final APK d34bee349a173f272742f6ff653ee77b8f9335e4123c33dcb76b59a71c65aa20 installed on both review devices; both Connected, retained profiles/teams, no startup errors, no USB reverse. OTP and encrypted-history backup direction documented; no storage migration or OTP enablement. See docs/testing/internet-translation-review.md and docs/architecture/privacy-and-recovery.md.
