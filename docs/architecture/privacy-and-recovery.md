# Privacy and account recovery — proposed direction

## Current implementation

The review uses automatic device identities, authorized private teams/messages and encrypted server storage. Messages and team memberships are currently stored on the server, with a device history cache. This is not end-to-end encryption, device-only storage or a complete backup/recovery system. Verified phone OTP adapters exist but no live OTP provider is configured; development codes stay disabled on the public review server.

## Recommended product model

- The operator dashboard shows aggregate teams/sites/member counts, subscriptions, server health and delivery failures. It does not need conversation content, salary details or identity documents for routine monitoring.
- Verified phone OTP establishes account identity once, and again on a replacement device. Keep the logged-in session between app launches. Linking the existing device account should retain the same user ID and teams. Never accept a fixed development OTP as production verification.
- The server retains minimum account, team membership, subscription and authorized routing data, so users can reconnect and restore teams.
- Conversation history may live on user devices, while the server relays end-to-end encrypted messages for a bounded delivery period. This requires new client key management, encryption and server retention/migration work; it has not been implemented by the layout update.
- Device-only history cannot be recovered from a lost phone without backup. Offer optional encrypted backup or transfer from the old phone. OTP restores account/team access, not encryption keys: backup restoration additionally needs a user-held recovery key or a trusted-device transfer.
- Team admins can maintain their own member records. Operator monitoring should remain separate from those private records.

## Scope of this update

The mockup and request-rate fixes do not remove existing server data or change retention. No OTP provider was purchased or enabled, and no new end-to-end encryption claim is made.
