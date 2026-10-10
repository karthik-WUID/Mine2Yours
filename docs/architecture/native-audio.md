# Native audio contract

The channel is `com.mine2yourlingo/audio`. Dart and native code use the same `MethodChannel` in both directions. Register a method-call handler before sending messages. Arguments and callback payloads are maps with string keys.

| Dart method | Arguments | Result |
| --- | --- | --- |
| `getCapabilities` | none | `platform`, `onDeviceTts`, `remoteAudioPlayback`, `backgroundPlayback`, `backgroundReceive`, `receivingEnabled`, `headphonesConnected`, `headphonesOnlySupported`, `voices`, `note` |
| `startReceiving` | none; call only after an explicit user action while visible | map containing `enabled`, background capability flags and a truthful note; iOS adds `notificationsAllowed` |
| `stopReceiving` | none | `true`; stops active utterance and Android service |
| `speak` | required `messageId`, `text`, BCP-47 `language`; optional `headphonesOnly` boolean, `stopAtEpochMillis` integer, `playbackRequestId` string | `true` means the engine accepted the request; completion arrives separately |
| `playAudio` | required `messageId`, absolute `url`; optional `headphonesOnly`, `headers` map, `stopAtEpochMillis` integer, `playbackRequestId` string | `true` accepts a bounded audio fetch; native lifecycle callbacks report subsequent failure/start/completion |
| `stopPlayback` | none | `true`; cancellation arrives as `playbackError` |

Text must contain 1–4000 characters; message identifiers must contain 1–200 characters. Do not send an access token or an audio URL as an identifier. Backend group permissions, mute state, quiet hours, review flags and recipient eligibility must be checked before the app calls `speak`. Native code owns device audio constraints; it is not the group authorization authority.

Pass a fresh UUID in `playbackRequestId` for each playback attempt, including replay of the same message. Both platforms accept a supplied string matching `[A-Za-z0-9_-]{1,128}`; explicit null, other types, empty/overlong strings, whitespace, punctuation and non-ASCII characters are rejected with `invalid_playback_request_id` before playback starts or replaces an earlier request. Only omission permits a legacy request. Every `playbackStarted`, `playbackCompleted` and `playbackError` event for an accepted request echoes its supplied ID; legacy events omit the field. Cancellation/replacement snapshots the earlier request ID before cleanup, so a delayed stop event cannot take the replacement's ID. Internal Android utterance UUID and iOS utterance/player/task identity checks remain separate. Dart must match both message and request before applying a callback; `receivingStopped` belongs to the service and carries no request ID.

When quiet hours are enabled, pass the next device-local quiet-hours boundary as `stopAtEpochMillis`. Android accepts an omitted field or a positive integer epoch timestamp strictly in the future and at most 48 hours ahead. Explicit null, non-integer, nonpositive and overly distant values are rejected with `invalid_playback_deadline`; an elapsed positive boundary is rejected with `quiet_hours_started` before voice selection or network work. A single main-thread timer belongs to the unique playback token and is removed on stop, failure, completion or replacement. Download, start and completion callbacks recheck the wall-clock boundary; expiry cancels playback with `playbackError` reason `quiet_hours_started`, never `playbackCompleted`. This also covers already-delivered Android playback while Dart is suspended. Scheduling timing and device-clock changes need physical-device testing. iOS ignores this optional field; Flutter's foreground boundary timer and native cancellation on backgrounding enforce its playback limit.

For `playAudio`, resolve backend relative audio links against the current API origin, check same-origin authorization before attaching the bearer token, and pass only an ephemeral `Authorization` header. Native code permits only Authorization/Accept headers, rejects URL credentials/fragments, never follows HTTP redirects, checks an audio content type and enforces a 4,000,000-byte limit even when content length is absent. HTTPS is required, except debug loopback/emulator HTTP development. Do not pass cloud-provider keys. Accepted downloads can still fail; only an actual player completion produces `playbackCompleted`.

Android downloads into a private temporary cache file, then plays via `MediaPlayer`; cancellation/completion removes the file and startup removes orphaned playback files. iOS uses an ephemeral `URLSession` with no response cache, bounded RAM data and `AVAudioPlayer`; it writes no playback file. Both retain the same silent/focus/interruption/disconnect and foreground rules as local speech. Neither fetch path is a native incoming-message receiver. Strict Android headphones-only remains unverified and fails closed for both methods.

| Native callback | Payload | Meaning |
| --- | --- | --- |
| `playbackStarted` | `messageId`, supplied `playbackRequestId` | Native utterance started |
| `playbackCompleted` | `messageId`, supplied `playbackRequestId` | Native utterance completed; not a human-heard receipt |
| `playbackError` | `messageId`, supplied `playbackRequestId`, `reason` | Playback failed or was stopped/interrupted; never mark it completed |
| `receivingStopped` (Android) | `reason` | Service ended; clear the receiving toggle and require a new explicit activation |

`speak` and `playAudio` can also fail with a `PlatformException` before any utterance exists. Do not wait for a callback after a rejected call. Reasons include `voice_unavailable`, `headphones_required`, `private_route_unverified`, `audio_focus_denied`, `device_silent`, `do_not_disturb`, `foreground_required`, `tts_unavailable`, `audio_session_unavailable`, `invalid_playback_deadline`, `invalid_playback_request_id` and `quiet_hours_started`. Keep the transcript and replay action available.

## Android

`MainActivity` handles user activation and notification permission. `ReceivingAudioService` declares `mediaPlayback`, uses a private persistent notification and returns `START_NOT_STICKY`. The service does not capture audio, hold a wake lock, poll the network or restart at boot. Android 14 requires foreground-service type declarations and permissions; Android 15 restricts audio-focus requests to the top app or a foreground service and disallows starting this media service from `BOOT_COMPLETED`. [Android service types](https://developer.android.com/develop/background-work/services/fgs/service-types), [audio focus](https://developer.android.com/media/optimize/audio-focus).

The selected voice is an installed, non-network TTS voice for the requested locale, with a same-language locale fallback. Unsupported languages require voice installation or authorized server-generated cloud audio through `playAudio`. The bridge does not download voices silently or send text to a cloud TTS endpoint. Media routes follow the operating system. Audio-device removal and `AUDIO_BECOMING_NOISY` stop playback conservatively; Bluetooth route selection and disconnect timing still require physical-device QA.

Strict headphones-only playback fails closed on Android: output inventory cannot prove the active private route, and the system TTS API cannot select a preferred output device. `headphonesOnlySupported` is false. The media player currently follows the operating-system route; implement and device-test explicit `AudioRouting` selection before enabling this capability. Never treat a connected Bluetooth speaker as verified headphones.

Android silent/vibrate mode and Do Not Disturb reject speech. Audio-focus loss stops speech instead of resuming a private message unexpectedly. A playback request replaces the previous utterance with a cancellation event. Without the activated service, backgrounding the activity stops speech.

The bridge emits no completion receipt after engine detachment or process death. No message-receipt guarantee can be inferred from the service notification being visible.

## iOS

The Swift implementation, including request correlation, has not been compiled on this host because full Xcode and the iOS SDK are unavailable. An unsigned CI build and physical-device verification remain release gates.

`AVSpeechSynthesizer` uses the application audio session with the ambient category, respecting the device's silent switch. Route removal, session interruption and app backgrounding stop speech. iOS does not expose a reliable silent-switch state to this implementation; an engine completion can occur without audible output. [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer), [route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes).

Enabling receiving requests ordinary notification authorization. If the running native handler is invoked while backgrounded, it refuses to speak and may enqueue a generic local notification without transcript content. This does not wake a suspended app or provide remote push. Apple treats background push delivery as system-managed; do not turn it into a promised always-on receiver. [Background update notifications](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).

System voice availability does not prove that every language is installed offline. Test the requested voice in airplane mode and leave text-only fallback visible if it fails. No background audio/VoIP entitlement is present. Strict headphones-only speech accepts only a current route explicitly reported as headphones; generic Bluetooth/USB routes fail closed because they can also be speakers/car kits. Ordinary consent-based speech still follows the operating system's Bluetooth/media route.
