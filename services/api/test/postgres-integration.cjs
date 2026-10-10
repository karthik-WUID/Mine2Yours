// Optional deployment integration test. Supply an isolated TEST_DATABASE_URL only.
// Never point this test at a database containing real user data.
const assert = require("node:assert/strict");
const { randomBytes, randomUUID } = require("node:crypto");
const { mkdtemp, rm } = require("node:fs/promises");
const { tmpdir } = require("node:os");
const { join } = require("node:path");
const { spawnSync } = require("node:child_process");
async function main() {
  if (!process.env.TEST_DATABASE_URL)
    throw new Error(
      "Supply TEST_DATABASE_URL for an isolated empty integration database",
    );
  if (
    !/test|isolated|integration/i.test(
      new URL(process.env.TEST_DATABASE_URL).pathname,
    )
  )
    throw new Error(
      "Integration database name must explicitly identify an isolated test database",
    );
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
  process.env.NODE_ENV = "test";
  process.env.ENABLE_DEV_AUTH = "true";
  process.env.DATA_ENCRYPTION_KEY = randomBytes(32).toString("base64");
  process.env.GLOBAL_DAILY_AI_BUDGET_USD = "10";
  process.env.GLOBAL_MONTHLY_AI_BUDGET_USD = "100";
  delete process.env.REDIS_URL;
  delete process.env.S3_BUCKET;
  delete process.env.STT_HTTP_URL;
  delete process.env.TTS_HTTP_URL;
  delete process.env.TRANSLATION_HTTP_URL;
  delete process.env.GOOGLE_TRANSLATE_API_KEY;
  delete process.env.OPENAI_API_KEY;
  const directory = await mkdtemp(join(tmpdir(), "lingo-pg-data-"));
  process.env.DEV_DATA_DIR = directory;
  const { PrismaClient: PreflightClient } = require("@prisma/client");
  const preflight = new PreflightClient();
  try {
    const tables = await preflight.$queryRawUnsafe(
      "SELECT COUNT(*)::int AS count FROM information_schema.tables WHERE table_schema='public'",
    );
    assert.equal(
      tables[0].count,
      0,
      "Integration database must be empty before migration",
    );
  } finally {
    await preflight.$disconnect();
  }
  const migrate = spawnSync(
    process.execPath,
    ["node_modules/prisma/build/index.js", "migrate", "deploy"],
    { cwd: join(__dirname, ".."), env: process.env, encoding: "utf8" },
  );
  assert.equal(migrate.status, 0, "PostgreSQL migration applies");
  const { Store } = require("../dist/common/store");
  const { AuthService } = require("../dist/auth/auth.service");
  const { GroupsService } = require("../dist/groups/groups.service");
  const { MessagingService } = require("../dist/messaging/messaging.service");
  const { HttpAiProviders } = require("../dist/ai/providers");
  const { AudioService } = require("../dist/audio/audio.service");
  const { RealtimeService } = require("../dist/realtime/realtime.service");
  const { PrivacyService } = require("../dist/privacy/privacy.service");
  const { UsageService } = require("../dist/analytics/usage.service");
  const { PrismaClient } = require("@prisma/client");
  const store = new Store(),
    otherStore = new Store(),
    db = new PrismaClient();
  const auth = new AuthService(store),
    groups = new GroupsService(store),
    otherGroups = new GroupsService(otherStore);
  const ai = new HttpAiProviders(),
    audio = new AudioService(store),
    realtime = new RealtimeService(auth, store);
  const messages = new MessagingService(store, ai, audio, realtime),
    otherMessages = new MessagingService(otherStore, ai, audio, realtime);
  const privacy = new PrivacyService(store, audio);
  try {
    const sender = await auth.dev({
        displayName: "PostgreSQL fixture sender",
        language: "en",
      }),
      receiver = await auth.dev({
        displayName: "PostgreSQL fixture receiver",
        language: "en",
      }),
      outsider = await auth.dev({
        displayName: "PostgreSQL fixture outsider",
        language: "en",
      });
    const group = await groups.create(sender.user.id, {
      name: "PostgreSQL private fixture",
    });
    const invitation = await groups.invite(sender.user.id, group.id);
    await groups.join(receiver.user.id, invitation.token);
    await assert.rejects(() => groups.detail(outsider.user.id, group.id));
    const payload = {
      groupId: group.id,
      recipientId: receiver.user.id,
      sourceLanguage: "en",
      text: "POSTGRESQL PRIVATE FIXTURE CONTENT",
      mode: "direct",
      idempotencyKey: randomUUID(),
    };
    const results = await Promise.all([
      messages.create(sender.user.id, payload),
      otherMessages.create(sender.user.id, payload),
    ]);
    assert.equal(results[0].id, results[1].id);
    await messages.settle();
    await otherMessages.settle();
    assert.equal(await db.message.count(), 1);
    const message = await messages.get(receiver.user.id, results[0].id);
    assert.equal(message.state, "READY");
    assert.equal(
      message.translations[0].provider,
      "source-language-passthrough",
    );
    const privateRow = await db.message.findUnique({
      where: { id: message.id },
    });
    assert.equal(privateRow.payload.includes(payload.text), false);
    assert.equal(await db.messageRecipient.count(), 1);
    assert.equal(await db.messageTranslation.count(), 1);
    const concurrent = await Promise.all([
      groups.create(sender.user.id, { name: "Concurrent database fixture A" }),
      otherGroups.create(sender.user.id, {
        name: "Concurrent database fixture B",
      }),
    ]);
    assert.equal(new Set(concurrent.map((v) => v.id)).size, 2);
    assert.equal(await db.group.count(), 3);
    await messages.ack(receiver.user.id, message.id, "DELIVERED");
    assert.equal(
      (await messages.ack(receiver.user.id, message.id, "DELIVERED")).status,
      "duplicate",
    );
    await groups.remove(sender.user.id, group.id, receiver.user.id);
    await assert.rejects(() => messages.get(receiver.user.id, message.id));
    const tokens = await auth.refresh(sender.refreshToken);
    await assert.rejects(() => auth.authenticate(sender.accessToken));
    assert.equal(
      (await auth.authenticate(tokens.accessToken)).user.id,
      sender.user.id,
    );
    await assert.rejects(() => auth.refresh(sender.refreshToken));
    await assert.rejects(() => auth.authenticate(tokens.accessToken));
    const financialBefore = (await new UsageService(store).get(sender.user.id))
      .messages;
    await groups.delete(sender.user.id, group.id);
    assert.equal(
      (await new UsageService(store).get(sender.user.id)).messages,
      financialBefore,
    );
    assert.equal(await db.message.count(), 0);
    assert.equal(await db.messageRecipient.count(), 0);
    await privacy.delete(sender.user.id);
    assert.equal(await db.user.count(), 2);
    assert.equal(await db.group.count(), 0);
    assert.equal(await db.groupMember.count(), 0);
    assert.equal(await db.session.count(), 2);
    assert.ok((await db.usageEvent.count()) > 0);
    console.log(
      JSON.stringify({
        test: "postgresql-integration",
        result: "passed",
        version: (
          await db.$queryRawUnsafe("SELECT version()")
        )[0].version.split(" on ")[0],
        scope:
          "migration, encrypted normalized persistence, cross-client transactions, direct authorization, idempotency, receipts, removal, session rotation, deletion, ledger retention",
        actualAiInference: false,
      }),
    );
  } finally {
    await messages.onModuleDestroy();
    await otherMessages.onModuleDestroy();
    await realtime.onModuleDestroy();
    await store.onModuleDestroy();
    await otherStore.onModuleDestroy();
    await db.$disconnect();
    await rm(directory, { recursive: true, force: true });
  }
}
main().catch((error) => {
  console.error("PostgreSQL integration failed:", error.message);
  process.exitCode = 1;
});
