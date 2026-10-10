import "reflect-metadata";
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "node:http";
import { createHmac, randomUUID } from "node:crypto";
import { once } from "node:events";
import { WebSocket } from "ws";
import { Store } from "../src/common/store";
import { AuthService } from "../src/auth/auth.service";
import { GroupsService } from "../src/groups/groups.service";
import { MessagingService } from "../src/messaging/messaging.service";
import { AudioService } from "../src/audio/audio.service";
import { RealtimeService } from "../src/realtime/realtime.service";
import {
  HttpAiProviders,
  ProviderError,
  quantitiesChanged,
  numericTokens,
  cacheKey,
} from "../src/ai/providers";
import { PrivacyService } from "../src/privacy/privacy.service";
import { UsageService, pricing } from "../src/analytics/usage.service";
import { BillingService } from "../src/billing/billing.service";
import { inspectWav } from "../src/audio/wav";
import { plans } from "../src/common/types";
class FixtureProviders extends HttpAiProviders {
  translations = 0;
  speeches = 0;
  transcriptions = 0;
  failure = false;
  changedNumbers = false;
  block?: Promise<void>;
  override capabilities() {
    return { stt: true, translation: true, tts: true };
  }
  override async transcribe() {
    this.transcriptions++;
    return { text: "fixture source text", provider: "TEST-ONLY-STT" };
  }
  override async translate(text: string, source: string, target: string) {
    this.translations++;
    await this.block;
    if (this.failure)
      throw new ProviderError(
        "PROVIDER_UNAVAILABLE",
        "Test provider unavailable",
      );
    return {
      text: this.changedNumbers
        ? text.replace("2", "3")
        : `fixture ${target}: ${text}`,
      provider: "TEST-ONLY-TRANSLATION",
    };
  }
  override async synthesize(text: string, language: string) {
    this.speeches++;
    return {
      bytes: Buffer.from(`TEST-ONLY-AUDIO:${language}:${text}`),
      mimeType: "audio/mpeg",
      provider: "TEST-ONLY-TTS",
    };
  }
  override version() {
    return "test-fixture-v1";
  }
}
async function fixture() {
  process.env.NODE_ENV = "test";
  process.env.ENABLE_DEV_AUTH = "true";
  delete process.env.DATABASE_URL;
  delete process.env.REDIS_URL;
  delete process.env.S3_BUCKET;
  delete process.env.DATA_ENCRYPTION_KEY;
  process.env.AI_PRICING_VERSION = "test-v1";
  process.env.AI_PRICING_CONFIRMED = "true";
  process.env.STT_USD_PER_SECOND = "0.0002";
  process.env.TRANSLATION_USD_PER_CHARACTER = "0.00002";
  process.env.TTS_USD_PER_CHARACTER = "0.00005";
  const directory = await mkdtemp(join(tmpdir(), "lingo-test-"));
  process.env.DEV_DATA_DIR = directory;
  const store = new Store();
  await store.init();
  const auth = new AuthService(store),
    groups = new GroupsService(store),
    ai = new FixtureProviders(),
    audio = new AudioService(store),
    realtime = new RealtimeService(auth, store),
    messages = new MessagingService(store, ai, audio, realtime),
    privacy = new PrivacyService(store, audio),
    usage = new UsageService(store);
  const users = await Promise.all(
    ["ta", "bn", "bn", "hi", "en"].map((language, index) =>
      auth.dev({ displayName: `Fixture ${index}`, language }),
    ),
  );
  await store.transaction((s) => {
    for (const user of s.users) user.providerConsent = true;
    for (const subscription of s.subscriptions) { subscription.planId = "pro"; subscription.state = "active"; }
  });
  const group = await groups.create(users[0].user.id, {
    name: "Test private group",
  });
  const invite = await groups.invite(users[0].user.id, group.id);
  for (const user of users.slice(1))
    await groups.join(user.user.id, invite.token);
  return {
    store,
    auth,
    groups,
    ai,
    audio,
    realtime,
    messages,
    privacy,
    usage,
    users,
    group,
    directory,
    cleanup: async () => {
      await messages.onModuleDestroy();
      realtime.onModuleDestroy();
      await store.onModuleDestroy();
      await rm(directory, { recursive: true, force: true });
    },
  };
}
const input = (groupId: string, recipientId?: string, text = "Hello team") => ({
  groupId,
  recipientId,
  text,
  sourceLanguage: "ta",
  mode: recipientId ? ("direct" as const) : ("group" as const),
  idempotencyKey: randomUUID(),
});

test("Session rotation revokes old access token and refresh replay revokes current family", async () => {
  const f = await fixture();
  try {
    const user = f.users[0];
    const rotated = await f.auth.refresh(user.refreshToken);
    await assert.rejects(() => f.auth.authenticate(user.accessToken));
    assert.equal(
      (await f.auth.authenticate(rotated.accessToken)).user.id,
      user.user.id,
    );
    await assert.rejects(() => f.auth.refresh(user.refreshToken));
    await assert.rejects(() => f.auth.authenticate(rotated.accessToken));
  } finally {
    await f.cleanup();
  }
});

test("Authorization denies outsiders, ordinary member invites, and unrelated direct messages", async () => {
  const f = await fixture();
  try {
    const outsider = await f.auth.dev({
      displayName: "Outsider",
      language: "en",
    });
    await assert.rejects(() => f.groups.detail(outsider.user.id, f.group.id));
    await assert.rejects(() => f.groups.invite(f.users[1].user.id, f.group.id));
    const message = await f.messages.create(
      f.users[1].user.id,
      input(f.group.id, f.users[2].user.id),
    );
    await f.messages.settle();
    await assert.rejects(() => f.messages.get(f.users[0].user.id, message.id));
    await assert.rejects(() => f.messages.get(outsider.user.id, message.id));
    assert.equal(
      (await f.messages.get(f.users[2].user.id, message.id)).translations
        .length,
      1,
    );
  } finally {
    await f.cleanup();
  }
});

test("Group fanout synthesizes once per language, private caching and idempotency avoid duplicate work", async () => {
  const f = await fixture();
  try {
    const payload = input(f.group.id);
    const responses = await Promise.all([
      f.messages.create(f.users[0].user.id, payload),
      f.messages.create(f.users[0].user.id, payload),
    ]);
    assert.equal(responses[0].id, responses[1].id);
    await f.messages.settle();
    const message = await f.messages.get(f.users[0].user.id, responses[0].id);
    assert.equal(message.state, "READY");
    assert.equal(f.ai.translations, 3);
    assert.equal(f.ai.speeches, 3);
    const assetIds = await f.store.read((s) =>
      s.translations
        .filter((v) => v.messageId === message.id)
        .map((v) => v.audioId),
    );
    assert.equal(new Set(assetIds).size, 3);
    assert.equal(
      message.recipients.filter((v) => v.language === "bn").length,
      2,
    );
    const second = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id),
    );
    await f.messages.settle();
    assert.equal(f.ai.translations, 3);
    assert.equal(f.ai.speeches, 3);
    const cached = await f.messages.get(f.users[0].user.id, second.id);
    assert.equal(cached.translations[0].text, message.translations[0].text);
    assert.equal((await f.usage.get(f.users[0].user.id)).cacheHits, 3);
    await assert.rejects(() =>
      f.messages.create(f.users[0].user.id, {
        ...payload,
        text: "Different text",
      }),
    );
    assert.notEqual(
      cacheKey("one", "text", "ta", "bn", "1"),
      cacheKey("two", "text", "ta", "bn", "1"),
    );
  } finally {
    await f.cleanup();
  }
});

test("Signed audio still requires the intended recipient and current group membership", async () => {
  const f = await fixture();
  try {
    const created = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id),
    );
    await f.messages.settle();
    const message = await f.messages.get(f.users[1].user.id, created.id);
    const url = new URL(message.translations[0].audioUrl!, "http://localhost");
    const audioId = url.pathname.split("/").pop()!;
    const expires = url.searchParams.get("expires")!,
      signature = url.searchParams.get("signature")!;
    assert.ok(
      (await f.audio.get(audioId, f.users[1].user.id, expires, signature)).bytes
        .length,
    );
    await assert.rejects(() =>
      f.audio.get(audioId, f.users[2].user.id, expires, signature),
    );
    await f.groups.remove(f.users[0].user.id, f.group.id, f.users[1].user.id);
    await assert.rejects(() =>
      f.audio.get(audioId, f.users[1].user.id, expires, signature),
    );
    await assert.rejects(() => f.messages.get(f.users[1].user.id, created.id));
  } finally {
    await f.cleanup();
  }
});

test("Receipt state transitions are ordered, idempotent, and cannot assert human comprehension", async () => {
  const f = await fixture();
  try {
    const created = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id),
    );
    await f.messages.settle();
    await assert.rejects(() =>
      f.messages.ack(f.users[1].user.id, created.id, "PLAYBACK_COMPLETED"),
    );
    let receiptEvents = 0;
    f.realtime.receipt = async (id, userId, state) => {
      assert.equal(id, created.id);
      assert.equal(userId, f.users[1].user.id);
      assert.ok(["DELIVERED", "PLAYBACK_STARTED", "PLAYBACK_COMPLETED"].includes(state));
      receiptEvents++;
    };
    await f.messages.ack(f.users[1].user.id, created.id, "DELIVERED");
    assert.equal(
      (await f.messages.ack(f.users[1].user.id, created.id, "DELIVERED"))
        .status,
      "duplicate",
    );
    assert.equal(receiptEvents, 1);
    await f.messages.ack(f.users[1].user.id, created.id, "PLAYBACK_STARTED");
    await f.messages.ack(f.users[1].user.id, created.id, "PLAYBACK_COMPLETED");
    await assert.rejects(() =>
      f.messages.ack(f.users[0].user.id, created.id, "DELIVERED"),
    );
  } finally {
    await f.cleanup();
  }
});

test("Cost estimates meter distinct languages and quotas stop provider traffic before calls", async () => {
  const f = await fixture();
  try {
    await f.messages.create(f.users[0].user.id, input(f.group.id));
    await f.messages.settle();
    const meter = await f.usage.get(f.users[0].user.id);
    assert.equal(meter.messages, 1);
    assert.equal(meter.translationCharacters, "Hello team".length * 3);
    assert.ok(meter.estimatedCostUsd > 0);
    assert.ok(
      Math.abs(
        meter.estimatedCostUsd -
          (meter.translationCharacters * pricing().translation +
            meter.ttsCharacters * pricing().tts),
      ) < 1e-8,
    );
    await f.store.transaction((s) => {
      s.usage.push({
        id: randomUUID(),
        userId: f.users[0].user.id,
        groupId: f.group.id,
        createdAt: new Date().toISOString(),
        kind: "tts",
        amount: 10000,
        estimatedCostUsd: 4,
        provider: "test",
        pricingVersion: "test",
      });
    });
    const before = f.ai.translations;
    await assert.rejects(
      () => f.messages.create(f.users[0].user.id, input(f.group.id)),
      (e: any) => e.getStatus() === 429,
    );
    assert.equal(f.ai.translations, before);
  } finally {
    await f.cleanup();
  }
});

test("Provider outages preserve FAILED state and retries recover without fabricated content", async () => {
  const f = await fixture();
  try {
    f.ai.failure = true;
    const created = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id),
    );
    await f.messages.settle();
    const failed = await f.messages.get(f.users[0].user.id, created.id);
    assert.equal(failed.state, "FAILED");
    assert.equal(failed.error?.code, "PROVIDER_UNAVAILABLE");
    assert.deepEqual(failed.translations, []);
    f.ai.failure = false;
    await f.messages.retry(f.users[0].user.id, created.id);
    await f.messages.settle();
    assert.equal(
      (await f.messages.get(f.users[0].user.id, created.id)).state,
      "READY",
    );
  } finally {
    await f.cleanup();
  }
});

test("Numbers and safety text require sender review; changed quantities cannot be delivered", async () => {
  const f = await fixture();
  try {
    const created = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id, "Bring 2 bags"),
    );
    await f.messages.settle();
    assert.equal(
      (await f.messages.get(f.users[0].user.id, created.id)).state,
      "REVIEW_REQUIRED",
    );
    await assert.rejects(() => f.messages.get(f.users[1].user.id, created.id));
    await assert.rejects(() =>
      f.messages.confirm(f.users[1].user.id, created.id),
    );
    await f.messages.confirm(f.users[0].user.id, created.id);
    assert.equal(
      (await f.messages.get(f.users[1].user.id, created.id)).state,
      "READY",
    );
    f.ai.changedNumbers = true;
    const broken = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id, "Bring 2 large bags"),
    );
    await f.messages.settle();
    await assert.rejects(() =>
      f.messages.confirm(f.users[0].user.id, broken.id),
    );
    assert.deepEqual(numericTokens("২ २ ௨ ୨"), ["2", "2", "2", "2"]);
    assert.equal(quantitiesChanged("Bring 2", "আনুন ২"), false);
  } finally {
    await f.cleanup();
  }
});

test("Encrypted persistence survives restart without plaintext tokens, names or transcripts", async () => {
  const f = await fixture();
  try {
    const created = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id, "Private source content"),
    );
    await f.messages.settle();
    const disk = await readFile(join(f.directory, "state.enc"), "utf8");
    assert.equal(disk.includes("Private source content"), false);
    assert.equal(disk.includes(f.users[0].accessToken), false);
    process.env.DEV_DATA_DIR = f.directory;
    const restarted = new Store();
    await restarted.init();
    assert.equal(
      await restarted.read(
        (s) => s.messages.find((v) => v.id === created.id)?.sourceText,
      ),
      "Private source content",
    );
    assert.equal(
      (await new AuthService(restarted).authenticate(f.users[0].accessToken))
        .user.id,
      f.users[0].user.id,
    );
  } finally {
    await f.cleanup();
  }
});

test("Account deletion revokes sessions and removes eligible messages/audio; retention erases expired content", async () => {
  const f = await fixture();
  try {
    const created = await f.messages.create(
      f.users[1].user.id,
      input(f.group.id, f.users[0].user.id),
    );
    await f.messages.settle();
    await f.privacy.delete(f.users[1].user.id);
    await assert.rejects(() => f.auth.authenticate(f.users[1].accessToken));
    assert.equal(
      await f.store.read((s) => s.messages.some((v) => v.id === created.id)),
      false,
    );
    const expiring = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[2].user.id),
    );
    await f.messages.settle();
    await f.store.transaction((s) => {
      s.messages.find((v) => v.id === expiring.id)!.expiresAt =
        "2000-01-01T00:00:00.000Z";
      s.cache.forEach((v) => (v.expiresAt = "2000-01-01T00:00:00.000Z"));
    });
    await f.privacy.retain();
    assert.equal(
      await f.store.read((s) => s.messages.some((v) => v.id === expiring.id)),
      false,
    );
  } finally {
    await f.cleanup();
  }
});

test("Billing webhooks require signatures, deduplicate verified events and disable past-due access", async () => {
  const f = await fixture();
  try {
    process.env.BILLING_WEBHOOK_SECRET = "test-only-webhook-secret";
    const billing = new BillingService(f.store);
    await assert.rejects(() =>
      billing.verify(f.users[0].user.id, {
        provider: "web",
        receipt: "fake success",
      }),
    );
    await f.store.transaction(
      (s) =>
        (s.subscriptions.find(
          (v) => v.userId === f.users[0].user.id,
        )!.billingCustomerId = "verified-test-customer"),
    );
    const timestamp = String(Math.floor(Date.now() / 1000));
    const raw = Buffer.from(
      JSON.stringify({
        id: "event-test",
        customerId: "verified-test-customer",
        planId: "pro",
        status: "past_due",
        currentPeriodEnd: new Date(Date.now() + 86400000).toISOString(),
      }),
    );
    await assert.rejects(() => billing.webhook(raw, "bad", timestamp));
    const signature = createHmac("sha256", process.env.BILLING_WEBHOOK_SECRET!)
      .update(`${timestamp}.`)
      .update(raw)
      .digest("hex");
    assert.equal(
      (await billing.webhook(raw, signature, timestamp)).status,
      "processed",
    );
    assert.equal(
      (await billing.webhook(raw, signature, timestamp)).status,
      "duplicate",
    );
    await assert.rejects(() =>
      f.groups.create(f.users[0].user.id, { name: "Disabled" }),
    );
  } finally {
    delete process.env.BILLING_WEBHOOK_SECRET;
    await f.cleanup();
  }
});

test("Authenticated WebSocket events do not leak direct conversations to group admins or removed members", async () => {
  const f = await fixture();
  const server = createServer();
  f.realtime.attach(server);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const port = (server.address() as any).port;
  const sockets: WebSocket[] = [];
  try {
    const events: any[][] = [[], [], []];
    for (const [index, who] of [0, 1, 2].entries()) {
      const socket = new WebSocket(`ws://127.0.0.1:${port}/v1/realtime`);
      sockets.push(socket);
      await once(socket, "open");
      socket.on("message", (raw) =>
        events[index].push(JSON.parse(raw.toString())),
      );
      const authenticated = once(socket, "message");
      socket.send(
        JSON.stringify({
          type: "authenticate",
          accessToken: f.users[who].accessToken,
        }),
      );
      await authenticated;
    }
    const created = await f.messages.create(
      f.users[1].user.id,
      input(f.group.id, f.users[2].user.id),
    );
    await f.messages.settle();
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.equal(events[0].filter((v) => v.type === "message.ready").length, 0);
    assert.ok(events[1].some((v) => v.type === "message.ready"));
    assert.ok(events[2].some((v) => v.type === "message.ready"));
    await f.groups.remove(f.users[0].user.id, f.group.id, f.users[2].user.id);
    const count = events[2].length;
    await f.realtime.message(created.id);
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.equal(events[2].length, count);
  } finally {
    for (const socket of sockets) socket.terminate();
    await f.cleanup();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test("Production cannot use local auth or file persistence", async () => {
  const f = await fixture();
  try {
    process.env.NODE_ENV = "production";
    await assert.rejects(() =>
      f.auth.dev({ displayName: "No", language: "en" }),
    );
    const store = new Store();
    await assert.rejects(() => store.init(), /PostgreSQL/);
  } finally {
    process.env.NODE_ENV = "test";
    await f.cleanup();
  }
});

test("Service-wide budgets stop account proliferation and concurrent reservations atomically", async () => {
  const f = await fixture();
  try {
    process.env.GLOBAL_DAILY_AI_BUDGET_USD = "0.00001";
    const before = f.ai.translations;
    await assert.rejects(
      () => f.messages.create(f.users[0].user.id, input(f.group.id)),
      (e: any) => e.getResponse().code === "GLOBAL_BUDGET_EXCEEDED",
    );
    assert.equal(f.ai.translations, before);
    assert.equal(await f.store.read((s) => s.messages.length), 0);
    process.env.GLOBAL_DAILY_AI_BUDGET_USD = "0.003";
    const concurrent = await Promise.allSettled([
      f.messages.create(
        f.users[0].user.id,
        input(f.group.id, f.users[1].user.id),
      ),
      f.messages.create(
        f.users[0].user.id,
        input(f.group.id, f.users[1].user.id),
      ),
    ]);
    assert.equal(concurrent.filter((v) => v.status === "fulfilled").length, 1);
    assert.equal(concurrent.filter((v) => v.status === "rejected").length, 1);
    await f.messages.settle();
    delete process.env.GLOBAL_DAILY_AI_BUDGET_USD;
  } finally {
    delete process.env.GLOBAL_DAILY_AI_BUDGET_USD;
    await f.cleanup();
  }
});

test("Malformed service budgets reject delivery before any AI calls or persisted reservations", async () => {
  const f = await fixture();
  const names = [
    "GLOBAL_DAILY_AI_BUDGET_USD",
    "GLOBAL_MONTHLY_AI_BUDGET_USD",
  ];
  const original = names.map((name) => process.env[name]);
  try {
    for (const name of names) {
      for (const invalid of [
        "NaN",
        "Infinity",
        "-Infinity",
        "invalid",
        "",
        "-1",
      ]) {
        process.env[name] = invalid;
        await assert.rejects(
          () =>
            f.messages.create(
              f.users[0].user.id,
              input(f.group.id, f.users[1].user.id),
            ),
          (error: any) => {
            assert.equal(error.getStatus(), 503);
            assert.deepEqual(error.getResponse(), {
              code: "USAGE_LIMITS_INVALID",
              message:
                "Usage limits are not configured correctly. AI processing is paused.",
            });
            return true;
          },
        );
      }
      // Zero is a valid operator pause, rather than malformed configuration.
      process.env[name] = "0";
      await assert.rejects(
        () =>
          f.messages.create(
            f.users[0].user.id,
            input(f.group.id, f.users[1].user.id),
          ),
        (error: any) =>
          error.getStatus() === 429 &&
          error.getResponse().code === "GLOBAL_BUDGET_EXCEEDED",
      );
      delete process.env[name];
    }
    await f.messages.settle();
    assert.equal(f.ai.transcriptions + f.ai.translations + f.ai.speeches, 0);
    assert.equal(await f.store.read((s) => s.messages.length), 0);
    assert.equal(await f.store.read((s) => s.usage.length), 0);
  } finally {
    names.forEach((name, index) => {
      if (original[index] === undefined) delete process.env[name];
      else process.env[name] = original[index];
    });
    await f.cleanup();
  }
});

test("Invalid active plan limits cannot authorize AI calls or consume a message", async () => {
  const f = await fixture();
  const trial = plans.find((plan) => plan.id === "diamond")!;
  const original = { ...trial };
  const fields = [
    "priceInr",
    "monthlyMessages",
    "monthlyAudioSeconds",
    "monthlyBudgetUsd",
    "dailyBudgetUsd",
    "maxGroupMembers",
  ] as const;
  try {
    for (const field of fields) {
      for (const invalid of [NaN, Infinity, -1]) {
        trial[field] = invalid;
        await assert.rejects(
          () =>
            f.messages.create(
              f.users[0].user.id,
              input(f.group.id, f.users[1].user.id),
            ),
          (error: any) =>
            error.getStatus() === 503 &&
            error.getResponse().code === "USAGE_LIMITS_INVALID",
        );
      }
      trial[field] = original[field];
    }
    await f.messages.settle();
    assert.equal(f.ai.transcriptions + f.ai.translations + f.ai.speeches, 0);
    assert.equal(await f.store.read((s) => s.messages.length), 0);
    assert.equal(await f.store.read((s) => s.usage.length), 0);
  } finally {
    Object.assign(trial, original);
    await f.cleanup();
  }
});

test("Invalidating a budget during translation stops the next priced stage", async () => {
  const f = await fixture();
  const original = process.env.GLOBAL_MONTHLY_AI_BUDGET_USD;
  let release!: () => void;
  f.ai.block = new Promise<void>((resolve) => (release = resolve));
  try {
    const created = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id),
    );
    const deadline = Date.now() + 2000;
    while (f.ai.translations === 0 && Date.now() < deadline)
      await new Promise((resolve) => setTimeout(resolve, 5));
    assert.equal(f.ai.translations, 1);
    process.env.GLOBAL_MONTHLY_AI_BUDGET_USD = "Infinity";
    release();
    await f.messages.settle();
    const failed = await f.messages.get(f.users[0].user.id, created.id);
    assert.equal(failed.state, "FAILED");
    assert.equal(failed.error?.code, "USAGE_LIMITS_INVALID");
    assert.equal(f.ai.speeches, 0);
    assert.equal(
      await f.store.read(
        (s) => s.usage.filter((entry) => entry.kind === "tts").length,
      ),
      0,
    );
    assert.equal(
      await f.store.read(
        (s) =>
          s.messages.find((entry) => entry.id === created.id)!.reservationUsd,
      ),
      0,
    );
  } finally {
    release();
    if (original === undefined) delete process.env.GLOBAL_MONTHLY_AI_BUDGET_USD;
    else process.env.GLOBAL_MONTHLY_AI_BUDGET_USD = original;
    await f.cleanup();
  }
});

test("Revoking provider consent during translation stops TTS and removed recipients cannot receive or retry", async () => {
  const f = await fixture();
  try {
    let release!: () => void;
    f.ai.block = new Promise<void>((resolve) => (release = resolve));
    const created = await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id),
    );
    await new Promise((resolve) => setTimeout(resolve, 15));
    await f.store.transaction((s) => {
      s.users.find((v) => v.id === f.users[0].user.id)!.providerConsent = false;
    });
    release();
    await f.messages.settle();
    assert.equal(f.ai.speeches, 0);
    assert.equal(
      (await f.messages.get(f.users[0].user.id, created.id)).error?.code,
      "PROVIDER_CONSENT_REVOKED",
    );
    await f.store.transaction((s) => {
      s.users.find((v) => v.id === f.users[0].user.id)!.providerConsent = true;
    });
    await f.groups.remove(f.users[0].user.id, f.group.id, f.users[1].user.id);
    const before = f.ai.translations;
    await assert.rejects(() =>
      f.messages.retry(f.users[0].user.id, created.id),
    );
    assert.equal(f.ai.translations, before);
    await assert.rejects(() => f.messages.get(f.users[1].user.id, created.id));
  } finally {
    await f.cleanup();
  }
});

test("Deleting a group cannot reset financial usage and bypass spending quotas", async () => {
  const f = await fixture();
  try {
    await f.messages.create(
      f.users[0].user.id,
      input(f.group.id, f.users[1].user.id),
    );
    await f.messages.settle();
    const before = await f.usage.get(f.users[0].user.id);
    assert.ok(before.estimatedCostUsd > 0);
    await f.groups.delete(f.users[0].user.id, f.group.id);
    const after = await f.usage.get(f.users[0].user.id);
    assert.equal(after.estimatedCostUsd, before.estimatedCostUsd);
    assert.equal(after.messages, before.messages);
    assert.equal(
      await f.store.read((s) => s.usage.some((v) => !!v.messageId)),
      false,
    );
  } finally {
    await f.cleanup();
  }
});

test("Synthetic WAV verifies metered idempotent drafts and Tamil/Bengali reverse routing without claiming real inference", async () => {
  const f = await fixture();
  try {
    const samples = Buffer.alloc(32000);
    for (let i = 0; i < samples.length; i += 2)
      samples.writeInt16LE(Math.round(Math.sin(i / 16) * 1000), i);
    const header = Buffer.alloc(44);
    header.write("RIFF");
    header.writeUInt32LE(samples.length + 36, 4);
    header.write("WAVE", 8);
    header.write("fmt ", 12);
    header.writeUInt32LE(16, 16);
    header.writeUInt16LE(1, 20);
    header.writeUInt16LE(1, 22);
    header.writeUInt32LE(16000, 24);
    header.writeUInt32LE(32000, 28);
    header.writeUInt16LE(2, 32);
    header.writeUInt16LE(16, 34);
    header.write("data", 36);
    header.writeUInt32LE(samples.length, 40);
    const audioBase64 = Buffer.concat([header, samples]).toString("base64");
    const draft = {
      groupId: f.group.id,
      sourceLanguage: "ta",
      audioBase64,
      mimeType: "audio/wav",
      idempotencyKey: randomUUID(),
    };
    const concurrent = await Promise.allSettled([
      f.messages.transcribe(f.users[0].user.id, draft),
      f.messages.transcribe(f.users[0].user.id, draft),
    ]);
    assert.ok(concurrent.some((v) => v.status === "fulfilled"));
    assert.equal(f.ai.transcriptions, 1);
    await f.store.transaction((s) => { s.subscriptions.find((v) => v.userId === f.users[0].user.id)!.state = "past_due"; });
    await assert.rejects(() => f.messages.transcribe(f.users[0].user.id, draft), (e: any) => e.getResponse().code === "PRO_AI_REQUIRED");
    await f.store.transaction((s) => { s.subscriptions.find((v) => v.userId === f.users[0].user.id)!.state = "active"; });
    const cached = await f.messages.transcribe(f.users[0].user.id, draft);
    assert.equal(cached.provider, "TEST-ONLY-STT");
    assert.equal(f.ai.transcriptions, 1);
    assert.equal((await f.usage.get(f.users[0].user.id)).audioSeconds, 1);
    await assert.rejects(() =>
      f.messages.transcribe(f.users[0].user.id, {
        ...draft,
        sourceLanguage: "bn",
      }),
    );
    const audioMessage = await f.messages.create(f.users[0].user.id, {
      groupId: f.group.id,
      recipientId: f.users[1].user.id,
      sourceLanguage: "ta",
      audioBase64,
      mimeType: "audio/wav",
      durationSeconds: 0.1,
      idempotencyKey: randomUUID(),
      mode: "direct",
    });
    await f.messages.settle();
    const reviewed = await f.messages.get(f.users[0].user.id, audioMessage.id);
    assert.equal(reviewed.durationSeconds, 1);
    assert.equal(reviewed.state, "REVIEW_REQUIRED");
    assert.equal(reviewed.translations[0].language, "bn");
    await f.messages.confirm(f.users[0].user.id, audioMessage.id);
    assert.equal(
      (await f.messages.get(f.users[1].user.id, audioMessage.id))
        .translations[0].language,
      "bn",
    );
    const reply = await f.messages.create(f.users[1].user.id, {
      ...input(f.group.id, f.users[0].user.id),
      sourceLanguage: "bn",
    });
    await f.messages.settle();
    assert.equal(
      (await f.messages.get(f.users[0].user.id, reply.id)).translations[0]
        .language,
      "ta",
    );
    assert.equal(
      await f.store.read((s) => JSON.stringify(s).includes(audioBase64)),
      false,
    );
  } finally {
    await f.cleanup();
  }
});


test("Free direct messages require no external consent, reservation or AI call, and remain private/idempotent", async () => {
  const f = await fixture();
  const oldCap = process.env.GLOBAL_DAILY_AI_BUDGET_USD;
  try {
    await f.store.transaction((s) => {
      for (const u of s.users) u.providerConsent = false;
      for (const sub of s.subscriptions) { sub.planId = "trial"; sub.state = "trial"; }
    });
    process.env.GLOBAL_DAILY_AI_BUDGET_USD = "0";
    const draft = { ...input(f.group.id, f.users[1].user.id, "Bring two bags"), processing: "device" as const };
    const created = await f.messages.create(f.users[0].user.id, draft);
    assert.equal(created.state, "READY");
    assert.equal(created.processing, "device");
    assert.equal(created.translations[0].needsDeviceTranslation, true);
    assert.equal(created.translations[0].text, "");
    assert.equal((await f.messages.create(f.users[0].user.id, draft)).id, created.id);
    assert.equal(f.ai.transcriptions + f.ai.translations + f.ai.speeches, 0);
    const usage = await f.usage.get(f.users[0].user.id);
    assert.equal(usage.cloudAiAllowed, false);
    assert.equal(usage.estimatedCostUsd, 0);
    assert.equal(usage.messages, 1);
    await assert.rejects(() => f.messages.get(f.users[2].user.id, created.id), (e: any) => e.getStatus() === 403);
    await assert.rejects(() => f.messages.create(f.users[0].user.id, { ...draft, text: "Changed content" }), (e: any) => e.getResponse().code === "IDEMPOTENCY_CONFLICT");
    await f.store.transaction((s) => { s.users.find((u) => u.id === f.users[1].user.id)!.listeningLanguage = "or"; });
    await assert.rejects(() => f.messages.create(f.users[0].user.id, { ...draft, idempotencyKey: randomUUID() }), (e: any) => e.getResponse().code === "DEVICE_LANGUAGE_UNSUPPORTED");
    assert.equal(await f.store.read((s) => s.messages.length), 1);
  } finally {
    if (oldCap === undefined) delete process.env.GLOBAL_DAILY_AI_BUDGET_USD; else process.env.GLOBAL_DAILY_AI_BUDGET_USD = oldCap;
    await f.cleanup();
  }
});

test("Only active server-verified Pro subscriptions may create cloud messages or transcribe audio", async () => {
  const f = await fixture();
  try {
    for (const [planId, state, expiresAt] of [
      ["trial", "trial", new Date(Date.now() + 86400000).toISOString()],
      ["basic", "active", new Date(Date.now() + 86400000).toISOString()],
      ["pro", "past_due", new Date(Date.now() + 86400000).toISOString()],
      ["pro", "active", new Date(Date.now() - 1000).toISOString()],
    ]) {
      await f.store.transaction((s) => Object.assign(s.subscriptions.find((v) => v.userId === f.users[0].user.id)!, { planId, state, expiresAt }));
      await assert.rejects(() => f.messages.create(f.users[0].user.id, input(f.group.id)), (e: any) => ["PRO_AI_REQUIRED", "SUBSCRIPTION_EXPIRED"].includes(e.getResponse().code));
    }
    assert.equal(f.ai.transcriptions + f.ai.translations + f.ai.speeches, 0);
    assert.equal(await f.store.read((s) => s.messages.length), 0);
  } finally { await f.cleanup(); }
});


test("Free translated message emits ready to the authorized recipient socket", async () => {
  const f = await fixture();
  const server = createServer();
  let socket: WebSocket | undefined;
  try {
    f.realtime.attach(server);
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const port = (server.address() as any).port;
    socket = new WebSocket(`ws://127.0.0.1:${port}/v1/realtime`);
    await new Promise<void>((resolve, reject) => {
      socket!.once("open", () => socket!.send(JSON.stringify({type: "authenticate", accessToken: f.users[1].accessToken})));
      socket!.on("message", b => { if (JSON.parse(b.toString()).type === "authenticated") resolve(); });
      socket!.once("error", reject);
    });
    const received = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(Error("No ready delivery event")), 3000);
      socket!.on("message", b => { const event = JSON.parse(b.toString()); if (event.type === "message.ready") { clearTimeout(timer); resolve(event); } });
    });
    const message = await f.messages.create(f.users[0].user.id, {...input(f.group.id, f.users[1].user.id, "இங்கே வா"), processing: "device"});
    assert.equal((await received).data.messageId, message.id);
    assert.equal(message.needsReview, false);
    assert.equal(message.sourceText, "இங்கே வா");
    assert.equal(message.translations[0].needsDeviceTranslation, true);
    assert.equal(f.ai.transcriptions + f.ai.translations + f.ai.speeches, 0);
  } finally {
    socket?.terminate();
    await f.cleanup();
    await new Promise<void>(r => server.close(() => r()));
  }
});
