# Engineering decisions

## ADR 001 — Modular monolith

Use NestJS modules, PostgreSQL, Redis/BullMQ and S3-compatible storage. Keep group authorization, message orchestration, quotas and receipts in one deployable API. This avoids distributed authorization and transaction coordination during the first pilot. Split services only after measured load or an operational boundary warrants it.

## ADR 002 — Group-scoped encrypted payloads

Encrypt sensitive payloads in the store using AES-256-GCM. Use short-lived authenticated application audio links and private encrypted audio objects. Index minimum relationship metadata in PostgreSQL. Encryption keys are deployment secrets. This is server-side encryption, not end-to-end encryption: the API and configured AI providers can process message content.

The current single application encryption key has no automatic envelope-encryption or rotation migration. Introduce versioned keys, re-encryption tooling and tested restore procedures before long-lived commercial retention. Do not change `DATA_ENCRYPTION_KEY` on an existing data set without migration.

## ADR 003 — Platform-compliant receiving

Use a user-activated Android media-playback foreground service with visible Stop controls for active speech. Cap idle and session duration; do not disguise an idle network socket as continuous media playback. iOS uses foreground speech and ordinary notification fallback. A native background network receiver and configured push are remaining implementation work. Product wording must reflect these limits.

## ADR 004 — Fail closed without verified providers

Development authentication is an explicitly labelled simulator and is rejected in production. Missing AI translation configuration returns an unavailable result; it does not echo source text as a claimed translation. Billing activation must follow verified server-side events. Missing external integrations remain release blockers rather than synthetic production success.

## ADR 005 — Versioned cost estimates

Record provider/pricing versions and charge measured units against reservations and plan limits before making provider requests. Estimates are not provider invoices. Tenant-scoped caches and fanout by unique recipient language reduce duplicate work. Cost target validation requires real provider, bandwidth and storage measurements.

## ADR 006 — Development storage versus AWS release storage

Docker Compose provides Postgres, Redis and an archived MinIO source build for local S3 compatibility. Production should use managed S3 and a task IAM role. Historical public binary-image access failed, so the helper builds a verified official release commit. It must not be represented as a reviewed or supported production dependency; validate its build, licensing and security before running or distributing it. [MinIO releases](https://github.com/minio/minio/releases), [registry tags](https://hub.docker.com/r/minio/minio/tags).

## ADR 007 — No automatic deployment in CI

Pull-request CI builds, tests and audits without production credentials. It does not publish mobile applications or deploy infrastructure. Release signing keys, cloud account configuration, vendor agreements and launch gates require the owner's release process. GitHub Actions references use verified full commit SHAs and can be updated by Dependabot. [GitHub workflow security](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions).
