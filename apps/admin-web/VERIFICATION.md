# Admin portal verification

Verified on 2026-10-08 using Node 24.19.0. The portal is available locally at `http://localhost:5173`, with Vite forwarding `/v1` to the Mine2YourLingo API on port 3100. The unrelated application on port 3000 was preserved.

## Automated coverage

The suite covers explicit development login and language submission, disabled simulator failures, real group mutation requests, aggregate-only administrative access, unavailable revenue, disabled purchase controls, stale API data notices, confirmed server logout, failed session revocation, group selection request races, and refresh-token rotation followed by authorization failure. API tests verify transport constraints, bearer headers, JSON payloads, authorization errors, network failures, and empty delete responses. Cost tests validate all unit conversions, missing prices, unused stages, invalid rates, and invalid usage.

## Live integration smoke

17 assertions passed against the running NestJS API through the Vite proxy:

1. Explicit development admin authorization.
2. Regular authentication without administrator privilege.
3. Private group creation.
4. Expiring invitation generation.
5. Joining through a valid invitation.
6. Authorized membership visibility and distinct listening languages.
7. Rejected privilege escalation (403).
8. Restricted administrator aggregates (403 for a regular user).
9. Authorized member role update.
10. Group rename.
11. Actual usage and server-enforced allowance retrieval.
12. Aggregate-only overview and `null` revenue visibility.
13. Provider configuration and disabled purchases.
14. Configured plan retrieval.
15. Personal account export.
16. Member removal.
17. Immediate denial of group access after removal (403).

The temporary group and both temporary accounts were removed during teardown. No provider keys were added, external AI calls made, or payments simulated. The development admin key was supplied only to the running test process and was not saved in source.

## Remaining validation

Actual browser screenshot and viewport QA could not be run because this environment has no available browser automation surface. React DOM interactions were tested instead; these do not prove pixel-perfect layout, screen reader behavior, or device-specific rendering. Production identity, billing verification and reconciliation, support and abuse workflows, financial reporting, and feature configuration remain outside the implemented portal. Container image builds and production HTTPS deployment require separate validation.

Font files are bundled locally and their license notices are included in `public/`, so the production console does not fetch Google Fonts. The deployed reverse proxy must expose the API at `/v1`; `VITE_API_URL` can alternatively select an explicit HTTPS API origin at build time.
