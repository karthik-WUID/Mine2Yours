# Mine2YourLingo API v1

Local API for this development machine: `http://127.0.0.1:3100/v1`. The deployment default is port 3000. JSON over HTTPS in production; bearer access token on every private endpoint. Access tokens expire after 15 minutes. `POST /auth/refresh` rotates both tokens; reuse of a consumed refresh token revokes its session. Realtime uses `/v1/realtime`; authenticate with a Bearer header or first frame `{"type":"authenticate","accessToken":"…"}`. Tokens must never appear in URL parameters.

`GET /health`, `GET /capabilities`, `GET /auth/capabilities`, and `GET /plans` are public. `GET /docs` serves Swagger and `/openapi.json` serves its specification. All paths below are relative to `/v1`.

| Method and path | Request | Response |
|---|---|---|
| POST /auth/phone/request | `{phone:"+91…"}` | dev-only fixed code with no SMS, or provider OTP when configured |
| POST /auth/phone/verify | `{phone,code,displayName?,language}` | stable phone account session; name required for a new dev account |
| POST /auth/phone/link | same input, authenticated | links the current review account without losing teams; cannot take another account’s phone |
| POST /auth/dev | `{displayName, language, adminKey?}` | `{accessToken,refreshToken,expiresIn,user,mode:"development-simulator"}`; only when explicit development opt-in |
| POST /auth/otp/request | `{phone:"+91…"}` | `{status:"sent",mode:"verified-provider"}` when Twilio Verify configured; otherwise 503 |
| POST /auth/otp/verify | `{phone,code,displayName,language}` | verified session; provider must report `approved` for the same phone |
| POST /auth/refresh | `{refreshToken}` | rotated tokens, expiry and user |
| POST /auth/logout | optional `{refreshToken}` | `{status:"revoked"}` for the authenticated session |
| GET/PATCH /users/me | PATCH: displayName,spokenLanguage,listeningLanguage,receivingMode,quietHours,providerConsent | Profile |
| DELETE /users/me | `{confirmation:"DELETE"}` | `{status:"deleted",retentionNote}` |
| GET/POST /users/me/devices | POST: `{name,platform,pushToken?}` | registered device metadata (push token never returned) |
| DELETE /users/me/devices/:id | — | device push registration revoked; session revocation is separate |
| GET /users/me/sessions | — | own sessions without tokens or hashes |
| DELETE /users/me/sessions/:id | — | session revoked |
| GET/POST /groups | POST: `{name,description?}` | array of own groups / created group |
| GET/PATCH/DELETE /groups/:id | PATCH: `{name?,description?}` | details including `members:[{userId,displayName,spokenLanguage,listeningLanguage,role}]` / updated / deleted |
| POST /groups/:id/invitations | `{expiresInHours?:24}` (1–168) | `{token,expiresAt,joinUrl}` |
| POST /groups/join | `{token}` | `{groupId,status:"joined"}` |
| POST /groups/:id/leave | — | `{status:"removed"}`; the last admin must transfer admin role |
| DELETE /groups/:id/members/:userId | — | removed |
| PATCH /groups/:id/members/:userId | `{role:"admin"|"moderator"|"member"}` | updated role; admin only |
| POST /messages | MessageInput in index.ts; exactly one text/audio, recipientId required only for direct | Message; usually PROCESSING until polling/event synchronization |
| GET /messages?groupId=… | optional group filter | last 100 visible unexpired messages; unrelated direct messages omitted |
| GET /messages/:id | — | visible message; recipient receives only their translation and receipt |
| POST /messages/:id/ack | `{state:"DELIVERED"|"PLAYBACK_STARTED"|"PLAYBACK_COMPLETED"|"FAILED"}` | `{status,state}`; ordered, recipient-only, idempotent |
| POST /messages/:id/confirm | — | sender releases reviewed message; numeric mismatch must be corrected in a new message |
| POST /messages/:id/retry | — | retry failed reviewed source text; discarded raw audio needs a new upload |
| POST /messages/:id/cancel | — | cancel before release; released messages cannot be recalled |
| POST /audio/transcribe | `{groupId,sourceLanguage,audioBase64,mimeType:"audio/wav",durationSeconds?,idempotencyKey}` | `{text,sourceLanguage,provider,draftId}`; metered, no message delivery |
| GET /audio/:id?expires=…&signature=… | bearer authentication ALSO required | authorized audio; URL expires after five minutes |
| GET /usage | — | Usage in index.ts |
| GET /plans | — | indicative configurable plans; no payment claim |
| POST /billing/purchases/verify | `{provider:"apple"|"google"|"web",receipt}` | verified entitlement only from trusted configured server gateway; default503 |
| POST /billing/webhook | signed raw body + timestamp headers | processed or duplicate; HMAC verification and bound customer required |
| GET /privacy/export | — | own profile, memberships, authored messages/translated outputs, usage, devices, subscription |
| GET /admin/overview | admin session | aggregate metrics, provider health; `revenueInr:null` until payment reconciliation; never transcripts |

External processing requires `PATCH /users/me {providerConsent:true}`. Provider support in capabilities means configured, not proven availability or language quality. Missing providers/pricing return explicit errors; there is no built-in translation corpus. Same-language text can be delivered as a source-language passthrough without AI calls.

Raw audio accepts verified PCM16 WAV, 8–48kHz, mono/stereo, 0.1–60 seconds, at most 4MB. Duration is derived from WAV bytes and not trusted from client input. Audio is held transiently for recognition and discarded. Cloud-recognized source text, numeric/safety-bearing text, and an explicit review request enter REVIEW_REQUIRED. Recipients cannot fetch or play these until the sender confirms. Numeral checks cover Indic digit scripts, but cannot prove preservation of spelled quantities, units, negation, or meaning; speaker review and pilot tests remain required.

A WebSocket event contains IDs and the truthful message state, not a private transcript. Clients fetch and authorize the current message, then explicitly acknowledge fetch/playback. An event is never a delivery acknowledgement, and playback completion does not prove comprehension. Reconnect fetches history to recover missed events. Current membership is checked again for REST, audio and realtime; removed members lose access immediately.

## Team personnel records

All `/groups/:team/workers` routes are restricted to current team admins (not ordinary members, moderators or unrelated global admins). GET/POST list/create; GET/PATCH/DELETE `/:id` detail/update/remove; POST/GET/DELETE `/:id/document` upload/read/remove a private image; POST `/:id/payments` and `/:id/work` add entries; DELETE `/:id/payments/:entry` and `/:id/work/:entry` remove entries. See WorkerInput/WorkerRecord in index.ts and OpenAPI for bounds. All personnel responses use Cache-Control: no-store. Identity uploads require permission, JPEG/PNG data and a 1 MiB decoded limit; profile photos have a 256 KiB limit. Identity images are encrypted and never issued as public URLs. Team deletion, record deletion and account deletion remove eligible private images.

Public team details project only member photo, joining date, job/site/work summary and status; salary, identity files, phone and detailed work/payment logs are excluded. UI language choices include 22 scheduled Indian languages plus English; actual installed speech support is reported by each device’s service rather than asserted by the API.

### Free device processing and Pro cloud processing

`POST /v1/messages` accepts `processing: "device" | "cloud"`. Device messages require reviewed text and never call paid AI providers. Cross-language entries contain an empty text plus `needsDeviceTranslation: true`; Android must translate the authorized source text with its downloaded models before display/playback. Unsupported free pairs fail before persistence. Receipts still represent real device playback, not a server translation placeholder.

Cloud message creation, processing stages and `/v1/audio/transcribe` require a server-side active, unexpired `pro` subscription. Trial, Basic, past-due and expired Pro accounts cannot make provider calls. `/v1/usage.cloudAiAllowed` drives the UI; client flags cannot grant entitlement.
