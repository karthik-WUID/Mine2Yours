# Deployment and signing

The supplied Compose stack is a local integration environment. It enables development authentication and uses local passwords and an archived MinIO source build. It must not be published as a production service. Commercial release is blocked until verified identity, configured AI/push/billing integrations and the device/operational checks in [testing](../testing/README.md) pass.

## Local containers

Install Docker Engine/Desktop with Compose v2, then from the repository root:

```sh
node infrastructure/scripts/setup-local-env.mjs
docker compose config --quiet
docker compose up --build -d
docker compose ps
curl --fail http://localhost:3100/v1/health
curl --fail http://localhost:8080/v1/health
```

The setup script creates a mode-0600 `.env` with random keys and refuses to overwrite an existing file. Keep this file when retaining database/object volumes. Losing `DATA_ENCRYPTION_KEY` loses the ability to decrypt those records. Do not commit it or print resolved Compose configuration.

PostgreSQL migrations run before API startup. A separate one-time storage initializer creates a private local audio bucket with the API AWS SDK. Redis is private to the Compose network. API and admin health checks gate startup; dependency ordering follows [Docker Compose's documented conditions](https://docs.docker.com/compose/how-tos/startup-order/).

| Service | Local endpoint | Purpose |
| --- | --- | --- |
| Admin | `http://localhost:8080` | Static SPA; `/v1` and `/v1/realtime` proxy to API |
| API | `http://localhost:3100/v1` | REST, health and realtime; configurable `API_PORT`, internal port3000 |
| PostgreSQL | `127.0.0.1:5432` | Local tooling only |
| MinIO | `127.0.0.1:9000`, console `127.0.0.1:9001` | Local encrypted object compatibility |
| Redis | private container port 6379 | Ephemeral state and queue coordination |

The MinIO service builds official upstream commit `9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a` (release `RELEASE.2025-10-15T17-29-55Z`) from source. Historical Quay image access returned HTTP 401 even after registry authentication, so Compose avoids that inaccessible image. The community repository is archived and AGPL-3.0 licensed; review licensing, security and support before distribution. The source Docker build was not verified by a local Docker daemon. Use managed AWS S3 for production. Local `S3_SERVER_SIDE_ENCRYPTION=none` omits MinIO's KMS-dependent server encryption; application AES-GCM encryption still applies. [Official MinIO source release](https://github.com/minio/minio/releases/tag/RELEASE.2025-10-15T17-29-55Z).

Stop with `docker compose down`; named volumes remain. `docker compose down -v` destroys local stored data and belongs only in disposable test cleanup.

## Development without Docker

Use the API's explicitly labelled encrypted-file development mode and the API/admin package scripts in the root README. It does not validate PostgreSQL, Redis, BullMQ or S3 integration. The production API requires a real PostgreSQL URL and external secrets. The Vite dev server runs on port 5173; the built admin uses a same-origin `/v1` API path.

For Android debug development, use emulator `http://10.0.2.2:3100/v1` or explicitly configured device networking. The debug manifest permits HTTP; release manifests retain TLS requirements. For iOS development on a physical device, use a trusted HTTPS development endpoint rather than relaxing ATS globally. No broad App Transport Security bypass is included. [Apple ATS guidance](https://developer.apple.com/documentation/Security/preventing-insecure-network-connections).

## Android release signing

The release build has no debug-signing fallback. Generate and protect an upload key outside the repository, and create ignored `apps/mobile/android/key.properties`:

```properties
storeFile=/absolute/private/path/mine2yourlingo-upload.jks
storePassword=private-secret
keyAlias=mine2yourlingo-upload
keyPassword=private-secret
```

Then build with the production HTTPS endpoint and development authentication disabled:

```sh
cd apps/mobile
flutter build appbundle --release --dart-define=API_URL=https://api.example.com/v1
```

Use your own actual endpoint. Development authentication is controlled by the server's `ENABLE_DEV_AUTH`; no mobile build-time flag replaces that check. Without `key.properties`, a release can be unsigned; it is not a store-ready signing artifact. CI uploads only a debug APK. Manage upload-key backups, Play App Signing and key rotation in the owner's release process. Declare and justify the `mediaPlayback` foreground-service type in Play Console and demonstrate the explicit session/notification flow.

## iOS release signing

Full Xcode, the iOS SDK, an Apple Developer team, a unique bundle identifier, distribution certificate and provisioning profile are required. Open `apps/mobile/ios/Runner.xcworkspace`, set the signing team for Runner, and verify generated Flutter package/plugin integration. Use `flutter build ios --release --no-codesign` for compile verification; this is not an installable or App Store-ready package. Archive/export with the owner's actual signing profile after device testing.

If APNs/FCM is added, configure verified application identifiers, APNs credentials and appropriate notification capability. Do not add PushKit, VoIP, CallKit or background audio solely to keep the process alive. Current native speech deliberately stops on app backgrounding.

The local host has no usable Xcode/iOS SDK and `xcrun` currently reports a missing active developer path. iOS native compilation and signing remain unverified locally. The macOS CI build is configured but has not been executed in GitHub Actions from this workspace. Android Gradle is limited to a 2 GB heap and two workers with in-process Kotlin compilation to limit memory/swap pressure on this host; owner-controlled CI may tune those limits after measurement.

## AWS staging reference

Provision an ACM-backed HTTPS application load balancer, an ECS/Fargate API task, a static admin frontend, private RDS PostgreSQL, TLS-enabled authenticated ElastiCache Redis and a private S3 bucket. Use security groups to allow API-to-database/Redis traffic only and restrict administrative ingress. There is no applied AWS infrastructure in this repository.

Build the API image with `services/api/Dockerfile`, scan it, pin its tested digest, and run migrations as a separate one-shot job before updating the API task. Use `infrastructure/.env.production.example` as an inventory; load values through AWS Secrets Manager/task roles rather than committing an environment file. Disable development authentication. Configure the Twilio Verify adapter and verify genuine OTP delivery before inviting users; a successful health response does not prove login or translation works.

The API task needs only S3 `PutObject`, `GetObject` and `DeleteObject` on its `audio/*` prefix. A provisioning role owns bucket creation, public-access blocks, lifecycle/retention and TLS-only policies. Current adapter support is SSE-S3; review additional KMS support before selecting a policy requiring SSE-KMS.

Publish the admin with its `VITE_API_URL` chosen at build time. Use a same-origin HTTPS `/v1` reverse proxy or a tightly scoped HTTPS origin. Pass WebSocket upgrades through the proxy, avoid logging authorization or audio-signature queries, and configure the API's exact CORS origins.

## Backups and operations

`bash infrastructure/scripts/backup-postgres.sh` writes a private custom-format local PostgreSQL dump without logging passwords. It is an operator helper, not a scheduled managed backup. Preserve application encryption keys separately and include object-storage retention/versioning in the restore plan.

On AWS, enable RDS backups and choose retention/RPO/RTO based on the product policy; RDS supports recovery within the configured retention window. Perform a restore drill into a separate database and verify membership, encrypted-message reads and audio retrieval using the restored key. [RDS backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html).

Collect container uptime, API errors/latency, database capacity, queue age/failures, provider latency/circuit state, quota rejections, estimated versus invoiced spend, missing receipts and retention-cleanup failures. Set owner-routed alerts before production. OpenTelemetry dependencies alone do not prove complete trace export or monitoring. Avoid bodies, audio, access tokens and provider secrets in logs and trace attributes.

CI contains no deployment or mobile-publishing job. It uses read-only repository permissions and pinned Action SHAs. Review dependency updates, protect the release branch and require the relevant checks before publishing signed artifacts.
