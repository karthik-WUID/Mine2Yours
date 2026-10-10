import 'dotenv/config';
// Do not seed production people, identities, transcripts or entitled subscriptions.
// Plans are checked-in indicative configuration returned by /v1/plans.
if(process.env.NODE_ENV==='production')console.log('No production identities or entitlements seeded.');
else console.log('Use explicit POST /v1/auth/dev and create your own private group. No fake AI data seeded.');
