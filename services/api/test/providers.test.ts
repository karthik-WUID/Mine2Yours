import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { once } from "node:events";
import { HttpAiProviders } from "../src/ai/providers";
import { inspectWav } from "../src/audio/wav";
export function wav(seconds = 1) {
  const data = Buffer.alloc(Math.floor(seconds * 16000) * 2);
  for (let i = 0; i < data.length; i += 2)
    data.writeInt16LE(Math.round(Math.sin(i / 16) * 1000), i);
  const header = Buffer.alloc(44);
  header.write("RIFF");
  header.writeUInt32LE(data.length + 36, 4);
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
  header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}
test("WAV duration and silence detection reject malformed and oversized duration claims", () => {
  assert.equal(inspectWav(wav(2)).seconds, 2);
  assert.equal(inspectWav(wav()).silent, false);
  const silence = wav();
  silence.fill(0, 44);
  assert.equal(inspectWav(silence).silent, true);
  assert.throws(() => inspectWav(Buffer.from("not audio")));
  assert.throws(() => inspectWav(wav(61)));
  const forged = wav();
  forged.writeUInt32LE(1, 28);
  assert.throws(() => inspectWav(forged));
  const ambiguous = Buffer.concat([wav(61), wav().subarray(36)]);
  ambiguous.writeUInt32LE(ambiguous.length - 8, 4);
  assert.throws(() => inspectWav(ambiguous));
});
test("Configured HTTP adapters honor STT, translation, TTS contracts and circuit breakers; test fixtures are not linguistic evidence", async () => {
  const received: any[] = [];
  let failure = false;
  const server = createServer(async (req, res) => {
    let bytes = "";
    for await (const part of req) bytes += part;
    const data = JSON.parse(bytes);
    received.push({ path: req.url, data });
    res.setHeader("Content-Type", "application/json");
    if (failure) {
      res.statusCode = 503;
      res.end("{}");
      return;
    }
    if (req.url === "/stt")
      res.end(JSON.stringify({ text: "TEST ONLY speech result" }));
    else if (req.url === "/translate")
      res.end(
        JSON.stringify({ translatedText: "TEST ONLY translation result" }),
      );
    else
      res.end(
        JSON.stringify({
          audioBase64: Buffer.from("TEST ONLY audio").toString("base64"),
          mimeType: "audio/mpeg",
        }),
      );
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as any).port}`;
  try {
    process.env.NODE_ENV = "test";
    process.env.STT_HTTP_URL = base + "/stt";
    process.env.TRANSLATION_HTTP_URL = base + "/translate";
    process.env.TTS_HTTP_URL = base + "/tts";
    delete process.env.GOOGLE_TRANSLATE_API_KEY;
    process.env.AI_PRICING_VERSION = "test-http-v1";
    process.env.AI_PRICING_CONFIRMED = "true";
    process.env.STT_USD_PER_SECOND = "0.0001";
    process.env.TRANSLATION_USD_PER_CHARACTER = "0.0001";
    process.env.TTS_USD_PER_CHARACTER = "0.0001";
    const ai = new HttpAiProviders();
    assert.equal(
      (await ai.transcribe(wav(), "audio/wav", "ta")).provider,
      "configured-http-stt",
    );
    assert.equal(
      (await ai.translate("source", "ta", "bn")).text,
      "TEST ONLY translation result",
    );
    assert.equal((await ai.synthesize("source", "bn"))?.mimeType, "audio/mpeg");
    assert.equal(received[0].data.language, "ta");
    assert.equal(received[1].data.target, "bn");
    const calls = received.length;
    process.env.AI_PRICING_CONFIRMED = "false";
    await assert.rejects(
      () => ai.translate("source", "ta", "bn"),
      (e: any) => e.code === "PRICING_UNCONFIGURED",
    );
    assert.equal(received.length, calls);
    process.env.AI_PRICING_CONFIRMED = "true";
    failure = true;
    for (let i = 0; i < 3; i++)
      await assert.rejects(() => ai.translate("source", "ta", "bn"));
    await assert.rejects(
      () => ai.translate("source", "ta", "bn"),
      (e: any) => e.code === "PROVIDER_CIRCUIT_OPEN",
    );
  } finally {
    delete process.env.STT_HTTP_URL;
    delete process.env.TRANSLATION_HTTP_URL;
    delete process.env.TTS_HTTP_URL;
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

test("Sarvam adapter uses native language contracts, Odia mapping, bounded chunks and valid WAV; no live credentials used", async () => {
  const original = { ...process.env };
  const requests: { path: string; body: string; key?: string }[] = [];
  let malformed = false;
  const server = createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk;
    requests.push({ path: req.url!, body, key: req.headers["api-subscription-key"] as string });
    res.setHeader("Content-Type", "application/json");
    if (req.url === "/speech-to-text") res.end(JSON.stringify({ transcript: "தமிழ் சோதனை" }));
    else if (req.url === "/translate") res.end(JSON.stringify({ translated_text: "ପରୀକ୍ଷା" }));
    else res.end(JSON.stringify({ audios: [malformed ? Buffer.from("invalid").toString("base64") : wav().toString("base64")] }));
  });
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  try {
    process.env.NODE_ENV = "test";
    process.env.SARVAM_API_KEY = "TEST-ONLY-SARVAM";
    process.env.SARVAM_BASE_URL = `http://127.0.0.1:${(server.address() as any).port}`;
    process.env.AI_PRICING_VERSION = "test-sarvam-v1";
    process.env.AI_PRICING_CONFIRMED = "true";
    process.env.STT_USD_PER_SECOND = "0.001";
    process.env.TRANSLATION_USD_PER_CHARACTER = "0.001";
    process.env.TTS_USD_PER_CHARACTER = "0.001";
    const ai = new HttpAiProviders();
    assert.deepEqual(ai.capabilities(), { stt: true, translation: true, tts: true });
    assert.equal((await ai.transcribe(wav(), "audio/wav", "ta")).text, "தமிழ் சோதனை");
    assert.ok(requests[0].body.includes("saaras:v4"));
    assert.ok(requests[0].body.includes("ta-IN"));
    assert.equal((await ai.translate("Hello", "en", "or")).text, "ପରୀକ୍ଷା");
    assert.equal(JSON.parse(requests[1].body).target_language_code, "od-IN");
    assert.equal(JSON.parse(requests[1].body).model, "sarvam-translate:v1");
    await ai.translate("x ".repeat(1500), "en", "ta");
    assert.ok(requests.slice(2).every((request) => JSON.parse(request.body).input.length <= 2000));
    assert.equal((await ai.synthesize("Hello", "ta"))?.mimeType, "audio/wav");
    const calls = requests.length;
    assert.equal(await ai.synthesize("Hello", "ur"), undefined);
    assert.equal(requests.length, calls);
    malformed = true;
    await assert.rejects(() => ai.synthesize("Hello", "ta"), (error: any) => error.code === "PROVIDER_INVALID_OUTPUT");
    assert.ok(requests.every((request) => request.key === "TEST-ONLY-SARVAM"));
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in original)) delete process.env[key];
    Object.assign(process.env, original);
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});
