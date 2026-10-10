import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { randomUUID } from "node:crypto";
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
test("REST integration validates input, live authorization, profiles, invitations, truthful receipts and fail-closed capabilities", async () => {
  const directory = await mkdtemp(join(tmpdir(), "lingo-http-"));
  const processEnv = {
    ...process.env,
    NODE_ENV: "test",
    ENABLE_DEV_AUTH: "true",
    PORT: "0",
    DEV_DATA_DIR: directory,
    DEV_ADMIN_KEY: "HTTP-TEST-ONLY-ADMIN",
    DATABASE_URL: "",
    REDIS_URL: "",
    DATA_ENCRYPTION_KEY: "",
    S3_BUCKET: "",
    STT_HTTP_URL: "",
    TTS_HTTP_URL: "",
    TRANSLATION_HTTP_URL: "",
    GOOGLE_TRANSLATE_API_KEY: "",
    OPENAI_API_KEY: "",
    SARVAM_API_KEY: "",
    TWILIO_ACCOUNT_SID: "",
    TWILIO_AUTH_TOKEN: "",
    TWILIO_VERIFY_SERVICE_SID: "",
    BILLING_VERIFICATION_URL: "",
    BILLING_VERIFICATION_KEY: "",
  };
  const child = spawn(process.execPath, ["dist/main.js"], {
    cwd: resolve(__dirname, ".."),
    env: processEnv,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "",
    errorOutput = "";
  child.stdout.on("data", (raw) => (output += raw));
  child.stderr.on("data", (raw) => (errorOutput += raw));
  try {
    let port: number | undefined;
    for (let i = 0; i < 200; i++) {
      const line = output.split("\n").find((v) => v.includes("api.started"));
      if (line) {
        port = JSON.parse(line).port;
        break;
      }
      if (child.exitCode !== null)
        throw new Error("API startup failed: " + errorOutput);
      await sleep(50);
    }
    assert.ok(port, "API starts successfully");
    const base = `http://127.0.0.1:${port}/v1`;
    const request = async (
      path: string,
      method = "GET",
      body?: unknown,
      token?: string,
    ) => {
      const response = await fetch(base + path, {
        method,
        headers: {
          "Content-Type": "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      });
      return { status: response.status, body: (await response.json()) as any };
    };
    assert.equal((await request("/health")).status, 200);
    assert.equal((await request("/users/me")).status, 401);
    assert.equal(
      (
        await request("/auth/dev", "POST", {
          displayName: "Malformed",
          language: "en",
          isAdmin: true,
        })
      ).status,
      400,
    );
    const capabilities = (await request("/capabilities")).body;
    assert.equal(capabilities.developmentAuth, true);
    assert.equal(capabilities.ai.translation, false);
    assert.equal(capabilities.billing.purchasesEnabled, false);
    const sender = (
      await request("/auth/dev", "POST", {
        displayName: "Sender fixture",
        language: "en",
      })
    ).body;
    const receiver = (
      await request("/auth/dev", "POST", {
        displayName: "Receiver fixture",
        language: "en",
      })
    ).body;
    const stranger = (
      await request("/auth/dev", "POST", {
        displayName: "Stranger fixture",
        language: "en",
      })
    ).body;
    const admin = (
      await request("/auth/dev", "POST", {
        displayName: "Admin fixture",
        language: "en",
        adminKey: "HTTP-TEST-ONLY-ADMIN",
      })
    ).body;
    assert.equal(
      (await request("/admin/overview", "GET", undefined, sender.accessToken))
        .status,
      403,
    );
    assert.equal(
      (await request("/admin/overview", "GET", undefined, admin.accessToken))
        .body.scope,
      "aggregates-only",
    );
    const group = (
      await request(
        "/groups",
        "POST",
        { name: "Integration fixture" },
        sender.accessToken,
      )
    ).body;
    const invite = (
      await request(
        `/groups/${group.id}/invitations`,
        "POST",
        { expiresInHours: 1 },
        sender.accessToken,
      )
    ).body;
    assert.ok(invite.token.length >= 32);
    assert.equal(
      (
        await request(
          "/groups/join",
          "POST",
          { token: invite.token },
          receiver.accessToken,
        )
      ).status,
      201,
    );
    assert.equal(
      (
        await request(
          `/groups/${group.id}`,
          "GET",
          undefined,
          stranger.accessToken,
        )
      ).status,
      403,
    );
    const messageResponse = await request(
      "/messages",
      "POST",
      {
        groupId: group.id,
        recipientId: receiver.user.id,
        sourceLanguage: "en",
        text: "Private fixture content",
        processing: "device",
        idempotencyKey: randomUUID(),
        mode: "direct",
      },
      sender.accessToken,
    );
    assert.equal(messageResponse.status, 201);
    let message = messageResponse.body;
    for (let i = 0; i < 40 && message.state === "PROCESSING"; i++) {
      await sleep(25);
      message = (
        await request(
          `/messages/${message.id}`,
          "GET",
          undefined,
          sender.accessToken,
        )
      ).body;
    }
    assert.equal(message.state, "READY");
    assert.equal(
      message.translations[0].provider,
      "source-language-passthrough",
    );
    assert.equal(
      (
        await request(
          `/messages/${message.id}`,
          "GET",
          undefined,
          stranger.accessToken,
        )
      ).status,
      403,
    );
    assert.equal(
      (
        await request(
          `/messages/${message.id}/ack`,
          "POST",
          { state: "PLAYBACK_COMPLETED" },
          receiver.accessToken,
        )
      ).status,
      400,
    );
    assert.equal(
      (
        await request(
          `/messages/${message.id}/ack`,
          "POST",
          { state: "DELIVERED" },
          receiver.accessToken,
        )
      ).status,
      201,
    );
    assert.equal(
      (await request("/auth/otp/request", "POST", { phone: "+919999999999" }))
        .status,
      503,
    );
    assert.equal(
      (
        await request("/auth/otp/verify", "POST", {
          phone: "+919999999999",
          code: "123456",
          displayName: "Never verified",
          language: "en",
        })
      ).status,
      503,
    );
    assert.equal(
      (
        await request(
          "/billing/purchases/verify",
          "POST",
          { provider: "web", receipt: "client says paid" },
          sender.accessToken,
        )
      ).status,
      503,
    );
    const malformed = await fetch(base + "/auth/dev", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: '{"SECRET_INVALID_BODY_MARKER"',
    });
    assert.equal(malformed.status, 400);
    assert.equal(
      (await malformed.text()).includes("SECRET_INVALID_BODY_MARKER"),
      false,
    );
    assert.equal(
      (await request("/privacy/export", "GET", undefined, sender.accessToken))
        .body.ownMessages.length,
      1,
    );
    assert.equal(
      (
        await request(
          "/users/me",
          "DELETE",
          { confirmation: "DELETE" },
          sender.accessToken,
        )
      ).status,
      200,
    );
    assert.equal(
      (await request("/users/me", "GET", undefined, sender.accessToken)).status,
      401,
    );
    assert.equal(output.includes("Private fixture content"), false);
    assert.equal(output.includes(sender.accessToken), false);
  } finally {
    child.kill("SIGTERM");
    for (let i = 0; i < 100 && child.exitCode === null; i++) await sleep(20);
    if (child.exitCode === null) child.kill("SIGKILL");
    await rm(directory, { recursive: true, force: true });
  }
});
