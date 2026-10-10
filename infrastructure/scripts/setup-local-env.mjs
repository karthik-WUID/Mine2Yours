import { randomBytes } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const target = fileURLToPath(new URL('../../.env', import.meta.url));
const value = [
  '# Generated local development secrets. Do not commit or use in production.',
  `POSTGRES_PASSWORD=${randomBytes(24).toString('hex')}`,
  `MINIO_ROOT_PASSWORD=${randomBytes(24).toString('hex')}`,
  `DATA_ENCRYPTION_KEY=${randomBytes(32).toString('base64')}`,
  `AUDIO_SIGNING_KEY=${randomBytes(32).toString('hex')}`,
  `DEV_ADMIN_KEY=${randomBytes(32).toString('hex')}`,
  'API_PORT=3100',
  '',
].join('\n');
try {
  await writeFile(target, value, { flag: 'wx', mode: 0o600 });
  console.log('Created private local .env. Start with docker compose up --build -d.');
} catch (error) {
  if (error.code === 'EEXIST') {
    console.error('A .env already exists. It was preserved; remove it yourself only if you intend to replace its secrets.');
    process.exitCode = 1;
  } else throw error;
}
