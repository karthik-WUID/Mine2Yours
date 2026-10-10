# Internet translation review

This review uses public HTTPS and WSS. A shared Wi-Fi network, USB reverse forwarding and manual server address entry are no longer required. Existing review device identities and teams migrate from the previous LAN endpoint.

## Review setup

- Samsung SM-F766B: speak Tamil; listen Tamil.
- Lenovo TB373FU tablet: speak English; listen English.
- Open the same team on both devices. Select the other person's name for a direct conversation.
- Enable Speaker on both devices and leave the app open during this review.
- Hold the microphone, speak, and release; alternatively tap once to start and once to stop. Stop/release sends directly without a confirmation dialog.
- Spoken words appear live while recognizing. The receiver translates those words on its device and speaks its chosen listening language. The original recording is not substituted when translation fails.
- Open History for the source words, translated text, replay and delivery status. A completed playback receipt requires actual audio-engine start and completion callbacks.
- Test one device using mobile data and the other using Wi-Fi. USB cables may be disconnected after installation.
- Example: phone says “இங்கே வா”; tablet should hear the English meaning. Reply “Come here” on the tablet; the phone should hear Tamil. Check recognition and translation accuracy as a human, not just delivery.

First use can download selected translation models over Wi-Fi or mobile data. Tamil ↔ English uses free Google on-device translation and the phone's speech-recognition/reading-voice services. Paid cloud AI remains disabled without a configured provider and an active Diamond entitlement. Unsupported free-language pairs fail explicitly instead of sending untranslated speech.

## Review server lifetime

The current endpoint is a Cloudflare Quick Tunnel to the API running on this Mac. Keep the Mac, API and tunnel running. The temporary hostname changes when the tunnel is recreated and this build must then be updated. This is an internet-accessible review, not an always-on hosted production service. A permanent HTTPS domain and hosted API/database are still needed for operation independent of the Mac. See [official Quick Tunnel documentation](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

Public fixed-code development login is disabled. Automatic device identities retain private team and message authorization. No paid provider requests are enabled.

## Interface and brand

Home contains team selection, clear member cards, chosen recipient language, microphone, Speaker and typing controls. Recent Messages moved to History. The server-address editor was removed from Settings. Admin-maintained linked member names are used in team details without exposing pay or identity documents.

New transparent wordmark: `apps/mobile/assets/logo-universal.png`.
New launcher symbol: `apps/mobile/android/app/src/main/res/drawable/logo_universal_foreground.png`.
Generated with the built-in imagegen tool. Prompt: create a professional universal Mine2YourLingo communication logo using interlocking speech bubbles and a shared waveform, navy/blue/green, a gold numeral 2, tagline “My Voice. Your Language.”, transparent background, with no people, hardhats or construction imagery. The launcher edit keeps only the speech-bubble/waveform symbol on a transparent square.

## Verification

Automated checks cover direct sending, capture cancellation, authenticated-session recovery, selected recipient translation and TTS language, transcript persistence, private message access, zero paid AI calls, member names and phone/tablet layouts. Native model inference and fresh device startup are checked separately. Hardware audibility, microphone recognition accuracy and switching to mobile data require the human review described above.


### Installed review evidence — 9 October 2026

- Final app APK SHA-256: `3011b5f1b91f9fc72ec026bf55d78954047bfe74f8dbf4a2950c6ea2de05f117`.
- Updated TB373FU and SM-F766B successfully with data-preserving installs.
- Both cached endpoints migrated to public HTTPS. Original device profiles and each existing team were retained.
- Tablet spoken/listening English; phone spoken/listening Tamil.
- No scoped AndroidRuntime or Flutter startup errors on either device.
- 30 API tests passed; 31 focused Flutter checks passed, with the changed capture/layout checks rerun after final UI edits. Reviewed phone and landscape tablet golden images.
- Public HTTPS + authenticated WSS smoke passed both Tamil/English routing directions, source transcript persistence, ready delivery, unauthorized-recipient denial and zero paid AI usage. Temporary fixture profiles/teams/messages were deleted after the check.
- No USB reverse forwarding configured on either device.

- Tablet native instrumentation passed real English → Tamil and Tamil → English model inference; actual offline Tamil and English reading voices were confirmed installed. The temporary instrumentation package was removed and the app reopened.
- Phone disconnected from USB after its successful install/startup verification, before optional native instrumentation. A reconnect was requested; this is not a failed installation.


### Temporary tunnel recovery — 9 October 2026, 21:06 IST

- Old Quick Tunnel was removed upstream (`Unauthorized: Tunnel not found`); the API itself still returned HTTP 200.
- Recreated the public tunnel: `https://reaction-invisible-satisfactory-characteristics.trycloudflare.com/v1`. Process log: `/tmp/m2yl-internet-tunnel-recovery.log`.
- Public HTTPS/authenticated WSS smoke passed bidirectional Tamil/English routing, source transcript persistence, direct ready delivery, recipient privacy and zero paid AI usage; temporary fixture accounts and data removed. Evidence: `/tmp/m2yl-server-recovery-smoke.log`.
- Updated only the saved server address on TB373FU and SM-F766B while each app was stopped, then reopened both. Existing profile IDs and one team per device were retained. Local database backups were kept; no credentials were printed.
- After the user unlocked the phone, both tablet and phone UIs show Online with no Offline label or connection-error banner. No scoped AndroidRuntime/Flutter startup errors were found.
- No new APK was installed during this recovery; the existing APK still embeds the previous temporary address. Reinstalling/clearing app data needs an updated build. No USB reverse mappings are configured.
- API and this temporary tunnel continue to require the Mac to remain running; a permanent hosted domain is still pending.


### Communication mockup and request-rate repair — 9 October 2026

- Home now follows `5.png`: team channel header, Everyone/member/Add cards, spoken/listening language panels, circular microphone, Mute/More, bottom navigation. `Type instead` removed. Receiver languages are shown from actual member preferences; each member changes their own preference. No stock people or invented presence status is displayed.
- Delivery/playback receipts use small `message.receipt` events limited to the sender and acknowledging recipient. They update local History status without refetching teams/history or announcing another message. Simultaneous message-ID events share one fetch; group changes debounce sync.
- Authenticated rate budgets are scoped to verified user identities; message creation, receipts and general reads have separate limits. Coarse IP/anonymous and authentication protection remain.
- Clients honor the server's Retry-After cooldown. Rate limited outgoing messages remain in the outbox; single-flight flushing prevents overlapping retries. Failed older messages are preserved rather than silently resent or deleted.
- 31 API tests passed, including identity budget isolation and receipt transition checks. 30 focused mobile checks passed; after final label/layout edits, 15 layout/privacy/session checks passed. Targeted Dart analysis reports no issues.
- Public HTTPS/WSS smoke passed Tamil/English routing, status-only receipt events, 72 acknowledgement calls without consuming send quota or re-announcing messages, private recipient enforcement and zero paid AI calls. Temporary fixture records removed. `/tmp/m2yl-public-receipt-smoke.log`.
- Physical speech recognition, pronunciation and audible translated playback still require human review.
- Phone OTP/account restore and device history backups are a proposed next step, documented in `docs/architecture/privacy-and-recovery.md`; no OTP provider or end-to-end encryption was enabled by this change.

- Final mockup APK SHA-256: `d34bee349a173f272742f6ff653ee77b8f9335e4123c33dcb76b59a71c65aa20` (173,596,016 bytes). Final build succeeded; compiled kernel contains receipt/cooldown/new layout markers.
- Installed successfully with data-preserving updates on TB373FU and SM-F766B. Both devices show Connected, I speak and They hear; Type instead and rate-error text absent. Original profiles and one team per device retained, correct public endpoint retained. No scoped AndroidRuntime/Flutter errors or USB reverse mappings.
