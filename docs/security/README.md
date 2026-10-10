# Security, privacy and release gates

This document separates protections in the current increment from controls that need deployment configuration or further implementation. It makes no legal-compliance or end-to-end-encryption claim.

## Data flow and trust

The mobile application captures a message only after a user action. Platform speech recognition may use an operating-system service whose processing and offline language availability vary; this is not proof of fully local speech recognition. When server transcription is selected, the recorded audio and chosen source language are sent to the configured STT provider. Translation receives reviewed/transcribed text and language codes. Cloud synthesis receives translated text and voice settings. Configure providers, retention/training terms and consent before enabling those routes for real people.

The API decrypts content to process it. Application AES-GCM encryption, production TLS and storage-volume encryption protect different surfaces. They do not prevent the API or an authorized cloud provider from accessing plaintext. Do not market this design as E2EE.

Raw source audio should be used for processing rather than retained as a default conversation artifact. Synthesized audio and server message payloads follow retention rules. The mobile SQLite cache/outbox currently relies on OS disk protection rather than application-level content encryption; a pending recorded message includes its raw audio until sent or discarded. Android cloud backup is disabled. Encrypted local caches, platform backup exclusion, device-lock behavior and cross-account purge are release checks. Confirm temporary files, failed jobs, caches, object versions and backups against the deployed retention policy; deleting a database row alone does not erase all copies.

## Controls and remaining work

| Surface | Current approach | Required validation or remaining work |
| --- | --- | --- |
| Authentication | Configurable Twilio Verify phone adapter, explicit development simulator and session token hashing/rotation/revocation | Genuine OTP tests with the owner's configured service, SMS anti-abuse/account recovery; optional email authentication remains additional work |
| Authorization | Server group/member/recipient checks; roles are permissions | Cross-group/direct-message isolation tests on every endpoint and realtime subscription; no browser-side privilege enforcement |
| Stored content | AES-256-GCM encrypted payloads and synthesized audio | Managed key custody, envelope/versioned key rotation, restore testing, regional retention decisions |
| Audio links | User-bound expiring HMAC application URLs plus authenticated authorization | Expiry/replay/removed-member tests; redact URL queries in access logs |
| Provider calls | Server-only configured credentials, timeout/circuit breaking, production HTTPS checks | Vendor agreements, data-region settings, training/retention restrictions, fallback reviews |
| AI budgets | Versioned unit estimates and quotas | Actual invoice reconciliation, concurrent reservations, refund/retry semantics and spending alerts |
| Device privacy | Visible receiving consent, no continuous mic in native receiving, disconnect cancellation | Physical headset/Bluetooth tests, notification privacy, shared-device logout and lock-screen behavior |
| Push tokens | No verified production push integration in this increment | Firebase/APNs provisioning, token rotation/revocation, minimal notification payload and authenticated fetch |
| Logs | Application logging must exclude message bodies/tokens/provider secrets | Validate API/proxy/queue/export logs and observability exporters with adversarial inputs |
| Supply chain | Pinned direct packages/lockfiles, CI runtime dependency audit, limited credential-signature check, pinned Actions | Full secret/history scanner, container vulnerability review, dev-tool advisories, branch protection |
| Operations | Container health and reference AWS deployment/backup guidance | Restore drill, load test, alert routing, incident response and actual staging deployment |

## Deployment secrets

`DATA_ENCRYPTION_KEY` is a 32-byte base64 AES key; `AUDIO_SIGNING_KEY` is a separate random signing secret. Never replace an existing encryption key casually: encrypted records and audio require the original key until a versioned migration is complete. Back up key material in a separately controlled secret manager, not beside the database dump.

Use an AWS task IAM role for S3 and a managed secret manager for database credentials and provider keys. Grant only object put/get/delete under the audio prefix; use a separate provisioning identity to create buckets or change policies. Block public access, enforce TLS, encrypt database/storage volumes and audit privileged operations. The current S3 adapter explicitly requests SSE-S3 (`AES256`); changing to SSE-KMS requires adapter support and KMS permissions rather than only a bucket setting. [S3 access controls](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-management.html), [required API permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-with-s3-policy-actions.html).

Local Docker Compose injects random development secrets through environment variables. These are not production secret-manager integration and can be read by a container administrator. `docker compose config` can print resolved secrets; use `docker compose config --quiet` for checks. Compose secret-file mounts are an available alternative when the application supports `_FILE` settings; this API currently expects environment values. [Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/).

## Threat model

Treat invite tokens, access/refresh tokens, device identifiers, audio URLs and provider endpoints as sensitive. Check token expiry, single-use invite decisions, reuse of rotated refresh tokens, duplicate idempotency keys and webhook replay. Test a removed member against cached audio and active realtime connections. Run provider response-size and latency checks and avoid arbitrary user-supplied provider URLs.

Protect the administration application against XSS and shared-device session leakage. Its static Nginx configuration includes a same-origin content policy, frame denial and MIME-sniffing protection. This does not make browser token storage immune to XSS. Review UI session persistence and close sensitive data on logout. Never expose service credentials or provider pricing mutation through unscoped UI requests.

Cloud translation can mistranslate negation, measurements, names and mixed-language expressions. Numeric-token preservation is only one safeguard. Safety messages need reviewed content and a recipient confirmation path. Playback completion never proves comprehension or emergency delivery.

## Retention and legal review

Before launch, publish a plain-language privacy notice naming processing categories and vendors, collect appropriate consent, document deletion/export handling, define retention per group/plan, and determine Indian DPDP and other target-market requirements with qualified counsel. This repository does not certify legal compliance. Audio/transcript exports and backups need the same scoped authorization and deletion handling as messages.

## Incident procedure

Revoke compromised sessions and provider credentials; disable the affected integration; preserve minimally scoped audit evidence; identify impacted groups/data; rotate signing secrets; migrate encryption keys using tested tooling; restore verified backups only into an isolated environment; document notification obligations with the owner/counsel. Never paste raw message content or secret values into an issue or CI log.
