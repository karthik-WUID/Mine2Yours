import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm, readdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

test('phone login retains teams; personnel documents and pay are admin-only, encrypted and removable', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'lingo-personnel-'));
  const env = { ...process.env, NODE_ENV: 'test', ENABLE_DEV_AUTH: 'true', DEV_LOGIN_CODE: '123456', DEV_DATA_DIR: directory, PORT: '0', HOST: '127.0.0.1', DATABASE_URL: '', REDIS_URL: '', DATA_ENCRYPTION_KEY: '', S3_BUCKET: '', TWILIO_ACCOUNT_SID: '', TWILIO_AUTH_TOKEN: '', TWILIO_VERIFY_SERVICE_SID: '', STT_HTTP_URL: '', TTS_HTTP_URL: '', TRANSLATION_HTTP_URL: '', GOOGLE_TRANSLATE_API_KEY: '', OPENAI_API_KEY: '' };
  const child = spawn(process.execPath, ['dist/main.js'], { cwd: resolve(__dirname, '..'), env, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '', errors = ''; child.stdout.on('data', (v) => output += v); child.stderr.on('data', (v) => errors += v);
  try {
    let port = 0;
    for (let i = 0; i < 200; i++) {
      const started = output.split('\n').find((v) => v.includes('api.started'));
      if (started) { port = JSON.parse(started).port; break; }
      if (child.exitCode !== null) throw Error(errors);
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.ok(port);
    const request = async (path: string, method = 'GET', body?: unknown, token?: string) => {
      const r = await fetch(`http://127.0.0.1:${port}/v1${path}`, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
      return { status: r.status, body: await r.json() as any, headers: r.headers };
    };
    assert.equal((await request('/auth/phone/request', 'POST', { phone: 'bad' })).status, 400);
    assert.equal((await request('/auth/phone/request', 'POST', { phone: '+919000000001' })).body.developmentCode, '123456');
    assert.equal((await request('/auth/phone/verify', 'POST', { phone: '+919000000001', code: '000000', displayName: 'Admin fixture', language: 'ta' })).status, 401);
    const login = async (phone: string, displayName: string) => (await request('/auth/phone/verify', 'POST', { phone, displayName, code: '123456', language: 'te' })).body;
    const admin = await login('+919000000001', 'Admin fixture');
    const member = await login('+919000000002', 'Member fixture');
    const outsider = await login('+919000000003', 'Other fixture');
    assert.equal(admin.user.phoneVerified, false); assert.equal(admin.user.phoneHash, undefined);
    const group = (await request('/groups', 'POST', { name: 'Personnel fixture' }, admin.accessToken)).body;
    const invite = (await request(`/groups/${group.id}/invitations`, 'POST', { expiresInHours: 1 }, admin.accessToken)).body;
    assert.equal((await request('/groups/join', 'POST', { token: invite.token }, member.accessToken)).status, 201);
    const base = `/groups/${group.id}/workers`;
    const input = { displayName: 'Full maintained member name', linkedUserId: member.user.id, phone: '+919000000002', jobTitle: 'Mason', workDetails: 'Brick work', site: 'Site A', joinedDate: '2026-10-09', status: 'active', salaryAmount: 750, salaryPeriod: 'day', consent: true };
    assert.equal((await request(base, 'POST', { ...input, consent: false }, admin.accessToken)).status, 400);
    assert.equal((await request(base, 'POST', { ...input, joinedDate: '2026-02-31' }, admin.accessToken)).status, 400);
    assert.equal((await request(base, 'POST', input, member.accessToken)).status, 403);
    const record = (await request(base, 'POST', input, admin.accessToken)).body; assert.ok(record.id);
    assert.equal((await request(base, 'POST', input, admin.accessToken)).status, 400, 'linked user cannot have duplicate record');
    const path = `${base}/${record.id}`;
    for (const token of [member.accessToken, outsider.accessToken]) {
      assert.ok([403, 404].includes((await request(base, 'GET', undefined, token)).status));
      assert.ok([403, 404].includes((await request(path, 'GET', undefined, token)).status));
    }
    const detail = (await request(`/groups/${group.id}`, 'GET', undefined, member.accessToken)).body;
    assert.equal(detail.workers, undefined); assert.equal(detail.role, "member"); assert.equal((await request(`/groups/${group.id}`, "GET", undefined, admin.accessToken)).body.role, "admin");
    const publicMember = detail.members.find((v: any) => v.userId === member.user.id);
    assert.equal(publicMember.displayName, member.user.displayName, 'authenticated profile name takes precedence over personnel record label');
    assert.equal((await request(path, 'GET', undefined, admin.accessToken)).body.displayName, 'Full maintained member name');
    assert.equal(publicMember.jobTitle, 'Mason'); assert.equal(publicMember.salaryAmount, undefined); assert.equal(publicMember.phone, undefined); assert.equal(publicMember.identityDocumentId, undefined);
    assert.equal((await request(path + '/document', 'POST', { mimeType: 'image/png', base64: Buffer.from('not an image').toString('base64'), consent: true }, admin.accessToken)).status, 400);
    const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aUxsAAAAASUVORK5CYII=';
    const uploaded = await request(path + '/document', 'POST', { mimeType: 'image/png', base64: png, consent: true }, admin.accessToken);
    assert.equal(uploaded.status, 201); assert.equal(uploaded.body.verification, 'manual-review-only');
    const image = await request(path + '/document', 'GET', undefined, admin.accessToken);
    assert.equal(image.headers.get('cache-control'), 'no-store'); assert.equal(image.body.base64, png);
    assert.ok([403, 404].includes((await request(path + '/document', 'GET', undefined, member.accessToken)).status));
    const list = await request(base, 'GET', undefined, admin.accessToken); assert.equal(list.headers.get('cache-control'), 'no-store');
    const privateDir = join(directory, 'personnel');
    const files = await readdir(privateDir); assert.equal(files.length, 1);
    assert.ok(!(await readFile(join(privateDir, files[0]), 'utf8')).includes(png), 'private file encrypted');
    const pay = (await request(path + '/payments', 'POST', { date: '2026-10-09', amount: 750, note: 'Fixture payment' }, admin.accessToken)).body;
    assert.equal(pay.payments.length, 1);
    const work = (await request(path + '/work', 'POST', { date: '2026-10-09', hours: 8, detail: 'Fixture work' }, admin.accessToken)).body;
    assert.equal(work.workLog.length, 1);
    assert.equal((await request(path + '/work', 'POST', { date: '2026-10-09', hours: 25, detail: 'Invalid' }, admin.accessToken)).status, 400);
    const removed = (await request(path + '/payments/' + pay.payments[0].id, 'DELETE', undefined, admin.accessToken)).body; assert.equal(removed.payments.length, 0);
    const repeat = await login('+919000000001', 'Name must not overwrite'); assert.equal(repeat.user.id, admin.user.id); assert.equal(repeat.user.displayName, 'Admin fixture');
    assert.equal((await request('/groups', 'GET', undefined, repeat.accessToken)).body[0].id, group.id);
    assert.equal((await request('/auth/phone/link', 'POST', { phone: '+919000000001', code: '123456', language: 'en' }, member.accessToken)).status, 400);
    const old = (await request('/auth/dev', 'POST', { displayName: 'Legacy fixture', language: 'en' })).body;
    await request('/auth/phone/link', 'POST', { phone: '+919000000004', code: '123456', language: 'en' }, old.accessToken);
    assert.equal((await login('+919000000004', 'Unused')).user.id, old.user.id, 'link keeps old account');
    assert.equal((await request(path, 'DELETE', undefined, admin.accessToken)).status, 200);
    assert.equal((await readdir(privateDir)).length, 0, 'record deletion removes private identity file');
    assert.equal((await request(path + '/document', 'GET', undefined, admin.accessToken)).status, 404);
    const retained = (await request(base, 'POST', input, admin.accessToken)).body;
    await request(`${base}/${retained.id}/document`, 'POST', { mimeType: 'image/png', base64: png, consent: true }, admin.accessToken);
    assert.equal((await readdir(privateDir)).length, 1);
    assert.equal((await request(`/groups/${group.id}`, 'DELETE', undefined, admin.accessToken)).status, 200);
    assert.equal((await readdir(privateDir)).length, 0, 'team deletion removes private identity files');
  } finally { child.kill('SIGTERM'); await new Promise((r) => child.exitCode !== null ? r(null) : child.once('exit', r)); await rm(directory, { recursive: true, force: true }); }
});

test('production phone login never accepts the fixed development code', async () => {
  const { AuthService } = await import('../src/auth/auth.service');
  const before = { NODE_ENV: process.env.NODE_ENV, ENABLE_DEV_AUTH: process.env.ENABLE_DEV_AUTH, TWILIO_ACCOUNT_SID: process.env.TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN: process.env.TWILIO_AUTH_TOKEN, TWILIO_VERIFY_SERVICE_SID: process.env.TWILIO_VERIFY_SERVICE_SID };
  try {
    Object.assign(process.env, { NODE_ENV: 'production', ENABLE_DEV_AUTH: 'true', TWILIO_ACCOUNT_SID: '', TWILIO_AUTH_TOKEN: '', TWILIO_VERIFY_SERVICE_SID: '' });
    const auth = new AuthService({} as any);
    assert.equal(auth.devEnabled(), false);
    await assert.rejects(auth.requestPhoneLogin('+919000000001'), (e: any) => e.getStatus() === 503);
    await assert.rejects(auth.verifyPhoneLogin({ phone: '+919000000001', code: '123456', displayName: 'Fixture', language: 'en' }), (e: any) => e.getStatus() === 503);
  } finally { for (const [key, value] of Object.entries(before)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; } }
});
