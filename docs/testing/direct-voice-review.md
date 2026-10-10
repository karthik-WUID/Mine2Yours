> This guide describes an earlier build. Use [Internet translation review](internet-translation-review.md) for the current translated internet review.

# Direct voice review — 9 October 2026

Walkie Talkie records the original voice as PCM WAV. Tap to record and tap again to send, or hold and release to send. There is no transcript confirmation popup. Sending does not require speech recognition, a downloaded language, external AI consent, or a paid AI provider. Original audio is not translated; the receiver hears the language actually spoken.

Open both apps on the same Wi-Fi, select the same team, select a member or Everyone, and keep Speaker enabled on the receiver. The app starts a foreground receiving session when entering Home unless Silent mode was selected. Recording pauses playback until capture finishes. History provides replay and real delivery/playback receipts. Background and force-stopped delivery are not implemented in this review build.

The review API is http://Karthikeyans-MacBook-Pro.local:3100/v1. USB is used to install updates, not to transport messages. The Mac hosts the server and must stay awake on this Wi-Fi.

The phone-code login screen and sign-out action have been removed. A random device credential creates and retains an automatic device profile; name and language can be changed in Settings. Existing profiles bind to the device after their current session is refreshed, retaining teams and personnel records. Invalid bound sessions recover without showing login. Requests, realtime connections and native audio download use refreshed credentials. Team and personnel access remain scoped to that device's profile.

Plans: Silver is permanent and free, with one owned site and five app team members including the owner. Gold currently allows ten owned sites and 100 team members per team. Diamond includes Gold limits and is the only plan allowed to use cloud AI. Old Trial/Basic/Pro records map to Silver/Gold/Diamond. Gold and Diamond prices have not been set; purchases remain disabled until verified billing is configured. No paid AI provider is enabled and budgets stay zero for this review.

With Walkie Talkie off, supported on-device recognition and Google translation remain available. Typed messages submit directly after their text entry. Existing safety review requirements for cloud-generated translations remain server-enforced.

Original voice assets are encrypted with the existing server storage. A direct message and its signed audio URL are accessible only to the sender and intended recipient, while current team membership is retained. Retries with the same idempotency key reuse the same asset and message.

Validation includes real HTTP device enrollment, reconnect preserving teams, direct voice delivery over WebSocket, exact WAV replay bytes across Tamil/Odia preferences, zero AI cost, idempotent upload, outsider rejection, Silver site/member limits; Flutter tests for tap-stop and hold-release direct sending, microphone startup cancellation, receiving playback ownership, login-free UI and concurrent/invalid credential refresh. Original older iCloud-backed unreadable test sources have not been substituted or counted as passing.

Native playback review: debug Android now accepts the configured server audio origin on loopback, RFC1918 LAN or mDNS .local. The app checks origin equality before sending credentials; native downloads reject redirects, credential URLs, public cleartext URLs, empty/oversized audio and cancellation. Production still requires HTTPS. Both tablet and phone returned HTTP 200 from the review hostname over their network without adb reverse.
