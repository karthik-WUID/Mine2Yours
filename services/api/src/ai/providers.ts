import { Injectable, ServiceUnavailableException } from "@nestjs/common";
import { createHash } from "node:crypto";
export class ProviderError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}
export interface Transcription {
  text: string;
  provider: string;
}
export interface TranslatedText {
  text: string;
  provider: string;
}
export interface Speech {
  bytes: Buffer;
  mimeType: string;
  provider: string;
}
export interface AiProviders {
  transcribe(
    audio: Buffer,
    mime: string,
    language: string,
  ): Promise<Transcription>;
  translate(
    text: string,
    source: string,
    target: string,
  ): Promise<TranslatedText>;
  synthesize(text: string, language: string): Promise<Speech | undefined>;
  capabilities(): { stt: boolean; translation: boolean; tts: boolean };
  health(): { name: string; configured: boolean; state: string }[];
  version(): string;
}
// HTTP adapter endpoint contracts are documented. Provider secrets stay server-side.
@Injectable()
export class HttpAiProviders implements AiProviders {
  private circuits = new Map<string, { failures: number; openUntil: number }>();
  capabilities() {
    return {
      stt: !!(
        process.env.SARVAM_API_KEY ||
        process.env.STT_HTTP_URL ||
        (process.env.OPENAI_API_KEY && process.env.OPENAI_STT_MODEL)
      ),
      translation: !!(
        process.env.SARVAM_API_KEY || process.env.TRANSLATION_HTTP_URL || process.env.GOOGLE_TRANSLATE_API_KEY
      ),
      tts: !!(
        process.env.SARVAM_API_KEY ||
        process.env.TTS_HTTP_URL ||
        (process.env.OPENAI_API_KEY && process.env.OPENAI_TTS_MODEL)
      ),
    };
  }
  version() {
    return process.env.AI_MODEL_VERSION || (process.env.SARVAM_API_KEY
      ? `sarvam:${process.env.SARVAM_STT_MODEL || "saaras:v4"}:${process.env.SARVAM_TRANSLATION_MODEL || "sarvam-translate:v1"}:${process.env.SARVAM_TTS_MODEL || "bulbul:v3"}`
      : "unconfigured");
  }
  health() {
    const capabilities = this.capabilities();
    return Object.entries(capabilities).map(([name, configured]) => ({
      name,
      configured,
      state:
        (this.circuits.get(name)?.openUntil || 0) > Date.now()
          ? "open"
          : configured
            ? "available-not-probed"
            : "unconfigured",
    }));
  }
  assertPricing(kind: string) {
    const value = Number(
      process.env[
        kind === "stt"
          ? "STT_USD_PER_SECOND"
          : kind === "tts"
            ? "TTS_USD_PER_CHARACTER"
            : "TRANSLATION_USD_PER_CHARACTER"
      ],
    );
    if (
      !process.env.AI_PRICING_VERSION ||
      process.env.AI_PRICING_CONFIRMED !== "true" ||
      !Number.isFinite(value) ||
      value <= 0
    )
      throw new ProviderError(
        "PRICING_UNCONFIGURED",
        "Provider pricing must be configured, reviewed and versioned before external processing.",
      );
  }
  private async call(
    kind: string,
    url: string,
    init: RequestInit,
  ): Promise<Response> {
    this.assertPricing(kind);
    const parsed = new URL(url);
    if (process.env.NODE_ENV === "production" && parsed.protocol !== "https:")
      throw new ProviderError(
        "PROVIDER_INSECURE",
        "Provider endpoints require HTTPS in production.",
      );
    const circuit = this.circuits.get(kind) || { failures: 0, openUntil: 0 };
    if (circuit.openUntil > Date.now())
      throw new ProviderError(
        "PROVIDER_CIRCUIT_OPEN",
        "AI provider is temporarily unavailable.",
      );
    try {
      const response = await fetch(url, {
        ...init,
        signal: AbortSignal.timeout(Number(process.env.AI_TIMEOUT_MS || 20000)),
        redirect: "error",
      });
      if (!response.ok)
        throw new ProviderError(
          "PROVIDER_HTTP_ERROR",
          `AI ${kind} provider returned HTTP ${response.status}.`,
        );
      this.circuits.set(kind, { failures: 0, openUntil: 0 });
      return response;
    } catch (error) {
      circuit.failures++;
      if (circuit.failures >= 3) circuit.openUntil = Date.now() + 60000;
      this.circuits.set(kind, circuit);
      if (error instanceof ProviderError) throw error;
      throw new ProviderError(
        "PROVIDER_UNAVAILABLE",
        `AI ${kind} provider request failed.`,
      );
    }
  }
  private headers(key?: string) {
    return {
      "Content-Type": "application/json",
      ...(key ? { Authorization: `Bearer ${key}` } : {}),
    };
  }
  private async bounded(
    response: Response,
    maximum = 6_000_000,
  ): Promise<Buffer> {
    if (Number(response.headers.get("content-length") || 0) > maximum)
      throw new ProviderError(
        "PROVIDER_INVALID_OUTPUT",
        "Provider response is oversized.",
      );
    const reader = response.body?.getReader();
    if (!reader)
      throw new ProviderError(
        "PROVIDER_INVALID_OUTPUT",
        "Provider returned no body.",
      );
    const chunks: Uint8Array[] = [];
    let size = 0;
    for (;;) {
      const result = await reader.read();
      if (result.done) break;
      size += result.value.length;
      if (size > maximum) {
        await reader.cancel();
        throw new ProviderError(
          "PROVIDER_INVALID_OUTPUT",
          "Provider response is oversized.",
        );
      }
      chunks.push(result.value);
    }
    return Buffer.concat(chunks);
  }
  private async json(kind: string, url: string, body: unknown, key?: string) {
    const response = await this.call(kind, url, {
      method: "POST",
      headers: this.headers(key),
      body: JSON.stringify(body),
    });
    try {
      return JSON.parse((await this.bounded(response)).toString("utf8"));
    } catch (error) {
      if (error instanceof ProviderError) throw error;
      throw new ProviderError(
        "PROVIDER_INVALID_OUTPUT",
        "Provider returned invalid JSON.",
      );
    }
  }
  private text(data: unknown): string {
    if (typeof data !== "string" || !data.trim() || data.length > 16000)
      throw new ProviderError(
        "PROVIDER_INVALID_OUTPUT",
        "Provider returned missing or oversized text.",
      );
    return data.trim();
  }
  supportsSynthesis(language: string, text: string): boolean {
    return !process.env.SARVAM_API_KEY || (["ta", "bn", "hi", "or", "en", "te", "kn", "ml", "mr", "gu", "pa"].includes(language) && text.length <= 2500);
  }
  private sarvamLocale(language: string) {
    const supported = ["ta", "bn", "hi", "or", "en", "te", "kn", "ml", "mr", "gu", "pa", "ur", "as", "brx", "doi", "ks", "kok", "mai", "mni", "ne", "sa", "sat", "sd"];
    if (!supported.includes(language)) throw new ProviderError("PROVIDER_LANGUAGE_UNSUPPORTED", "This language is not supported by the configured Indian-language provider.");
    return `${language === "or" ? "od" : language}-IN`;
  }
  private async sarvam(kind: string, path: string, body: unknown) {
    const response = await this.call(kind, `${process.env.SARVAM_BASE_URL || "https://api.sarvam.ai"}${path}`, {
      method: "POST", headers: { "Content-Type": "application/json", "api-subscription-key": process.env.SARVAM_API_KEY! },
      body: JSON.stringify(body),
    });
    try { return JSON.parse((await this.bounded(response)).toString("utf8")); }
    catch (e) { if (e instanceof ProviderError) throw e; throw new ProviderError("PROVIDER_INVALID_OUTPUT", "Provider returned invalid JSON."); }
  }
  async transcribe(
    audio: Buffer,
    mime: string,
    language: string,
  ): Promise<Transcription> {
    if (process.env.SARVAM_API_KEY) {
      const form = new FormData();
      form.set("file", new Blob([new Uint8Array(audio)], { type: mime }), "voice.wav");
      form.set("model", process.env.SARVAM_STT_MODEL || "saaras:v4");
      form.set("mode", "transcribe");
      form.set("language_code", this.sarvamLocale(language));
      const response = await this.call("stt", `${process.env.SARVAM_BASE_URL || "https://api.sarvam.ai"}/speech-to-text`, {
        method: "POST", headers: { "api-subscription-key": process.env.SARVAM_API_KEY }, body: form,
      });
      let data: any;
      try { data = JSON.parse((await this.bounded(response)).toString("utf8")); }
      catch (e) { if (e instanceof ProviderError) throw e; throw new ProviderError("PROVIDER_INVALID_OUTPUT", "Speech provider returned invalid JSON."); }
      const text = this.text(data.transcript);
      if (text.length > 4000) throw new ProviderError("TRANSCRIPT_TOO_LONG", "Transcript exceeds the message limit.");
      return { text, provider: `sarvam:${process.env.SARVAM_STT_MODEL || "saaras:v4"}` };
    }
    if (process.env.STT_HTTP_URL) {
      const data = await this.json(
        "stt",
        process.env.STT_HTTP_URL,
        { audioBase64: audio.toString("base64"), mimeType: mime, language },
        process.env.STT_API_KEY,
      );
      const text = this.text(data.text);
      if (text.length > 4000)
        throw new ProviderError(
          "TRANSCRIPT_TOO_LONG",
          "Transcript exceeds the message limit.",
        );
      return { text, provider: "configured-http-stt" };
    }
    if (!process.env.OPENAI_API_KEY || !process.env.OPENAI_STT_MODEL)
      throw new ProviderError(
        "STT_UNCONFIGURED",
        "Speech recognition provider is not configured. Send reviewed text or configure a provider.",
      );
    const form = new FormData();
    const extension: Record<string, string> = {
      "audio/wav": "wav",
      "audio/mpeg": "mp3",
      "audio/mp4": "m4a",
      "audio/x-m4a": "m4a",
      "audio/webm": "webm",
      "audio/ogg": "ogg",
    };
    form.set(
      "file",
      new Blob([new Uint8Array(audio)], { type: mime }),
      `voice.${extension[mime] || "wav"}`,
    );
    form.set("model", process.env.OPENAI_STT_MODEL);
    form.set("language", language);
    form.set("response_format", "json");
    const response = await this.call(
      "stt",
      `${process.env.OPENAI_BASE_URL || "https://api.openai.com/v1"}/audio/transcriptions`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY}` },
        body: form,
      },
    );
    const data: any = JSON.parse(
      (await this.bounded(response)).toString("utf8"),
    );
    const text = this.text(data.text);
    if (text.length > 4000)
      throw new ProviderError(
        "TRANSCRIPT_TOO_LONG",
        "Transcript exceeds the message limit.",
      );
    return { text, provider: `openai:${process.env.OPENAI_STT_MODEL}` };
  }
  async translate(
    text: string,
    source: string,
    target: string,
  ): Promise<TranslatedText> {
    if (source === target)
      return { text, provider: "source-language-passthrough" };
    if (process.env.SARVAM_API_KEY) {
      const chunks: string[] = [];
      let remaining = text.trim();
      while (remaining.length > 2000) {
        const candidate = remaining.slice(0, 2000);
        const boundary = Math.max(candidate.lastIndexOf(" "), candidate.lastIndexOf("\n"));
        let end = boundary > 1000 ? boundary : 2000;
        if (end > 0 && /[\uD800-\uDBFF]/.test(remaining[end - 1])) end--;
        chunks.push(remaining.slice(0, end)); remaining = remaining.slice(end).trimStart();
      }
      if (remaining) chunks.push(remaining);
      const translated: string[] = [];
      for (const input of chunks) {
        const data = await this.sarvam("translation", "/translate", {
          input, source_language_code: this.sarvamLocale(source), target_language_code: this.sarvamLocale(target),
          model: process.env.SARVAM_TRANSLATION_MODEL || "sarvam-translate:v1", mode: "formal", numerals_format: "international",
        });
        translated.push(this.text(data.translated_text));
      }
      return { text: this.text(translated.join(" ")), provider: `sarvam:${process.env.SARVAM_TRANSLATION_MODEL || "sarvam-translate:v1"}` };
    }
    if (process.env.GOOGLE_TRANSLATE_API_KEY) {
      const data = await this.json(
        "translation",
        `https://translation.googleapis.com/language/translate/v2?key=${encodeURIComponent(process.env.GOOGLE_TRANSLATE_API_KEY)}`,
        { q: text, source, target, format: "text", model: "nmt" },
      );
      const translated = this.text(data.data?.translations?.[0]?.translatedText)
        .replace(/&amp;/g, "&")
        .replace(/&quot;/g, '\"')
        .replace(/&#39;/g, "'")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&#([0-9]+);/g, (_, code) =>
          String.fromCodePoint(Number(code)),
        );
      return { text: translated, provider: "google-cloud-translation-v2" };
    }
    if (!process.env.TRANSLATION_HTTP_URL)
      throw new ProviderError(
        "TRANSLATION_UNCONFIGURED",
        "Translation provider is not configured. No translation was generated.",
      );
    const data = await this.json(
      "translation",
      process.env.TRANSLATION_HTTP_URL,
      {
        q: text,
        source,
        target,
        format: "text",
        ...(process.env.TRANSLATION_API_KEY
          ? { api_key: process.env.TRANSLATION_API_KEY }
          : {}),
      },
      process.env.TRANSLATION_BEARER_KEY,
    );
    return {
      text: this.text(data.translatedText),
      provider: `libretranslate-compatible:${this.version()}`,
    };
  }
  async synthesize(
    text: string,
    language: string,
  ): Promise<Speech | undefined> {
    if (process.env.SARVAM_API_KEY) {
      // Standard Bulbul voices support 11 languages. Others use an installed device voice.
      if (!["ta", "bn", "hi", "or", "en", "te", "kn", "ml", "mr", "gu", "pa"].includes(language)) return undefined;
      if (text.length > 2500) return undefined;
      const data = await this.sarvam("tts", "/text-to-speech", {
        text, language_code: this.sarvamLocale(language), model: process.env.SARVAM_TTS_MODEL || "bulbul:v3",
        ...(process.env.SARVAM_SPEAKER ? { speaker: process.env.SARVAM_SPEAKER } : {}),
        output_audio_codec: "wav", speech_sample_rate: 16000,
      });
      const encoded = data.audios?.[0];
      if (typeof encoded !== "string" || !/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) throw new ProviderError("PROVIDER_INVALID_OUTPUT", "Speech provider returned invalid audio.");
      const bytes = Buffer.from(encoded, "base64");
      if (!bytes.length || bytes.length > 4_000_000 || bytes.toString("ascii", 0, 4) !== "RIFF" || bytes.toString("ascii", 8, 12) !== "WAVE") throw new ProviderError("PROVIDER_INVALID_OUTPUT", "Speech provider did not return bounded WAV audio.");
      return { bytes, mimeType: "audio/wav", provider: `sarvam:${process.env.SARVAM_TTS_MODEL || "bulbul:v3"}` };
    }
    if (process.env.TTS_HTTP_URL) {
      const data = await this.json(
        "tts",
        process.env.TTS_HTTP_URL,
        { text, language, voice: process.env.TTS_VOICE || "default" },
        process.env.TTS_API_KEY,
      );
      if (
        typeof data.audioBase64 !== "string" ||
        !["audio/mpeg", "audio/wav", "audio/ogg", "audio/mp4"].includes(
          data.mimeType,
        )
      )
        throw new ProviderError(
          "PROVIDER_INVALID_OUTPUT",
          "Speech provider returned invalid audio.",
        );
      const bytes = Buffer.from(data.audioBase64, "base64");
      if (!bytes.length || bytes.length > 4_000_000)
        throw new ProviderError(
          "PROVIDER_INVALID_OUTPUT",
          "Speech audio size is invalid.",
        );
      return {
        bytes,
        mimeType: data.mimeType,
        provider: "configured-http-tts",
      };
    }
    if (!process.env.OPENAI_API_KEY || !process.env.OPENAI_TTS_MODEL)
      return undefined; // Client must detect an installed voice; text is still deliverable.
    const response = await this.call(
      "tts",
      `${process.env.OPENAI_BASE_URL || "https://api.openai.com/v1"}/audio/speech`,
      {
        method: "POST",
        headers: this.headers(process.env.OPENAI_API_KEY),
        body: JSON.stringify({
          model: process.env.OPENAI_TTS_MODEL,
          input: text,
          voice: process.env.TTS_VOICE || "alloy",
          response_format: "mp3",
        }),
      },
    );
    const bytes = await this.bounded(response, 4_000_000);
    if (bytes.length > 4_000_000)
      throw new ProviderError(
        "PROVIDER_INVALID_OUTPUT",
        "Speech audio size exceeds limit.",
      );
    return {
      bytes,
      mimeType: "audio/mpeg",
      provider: `openai:${process.env.OPENAI_TTS_MODEL}`,
    };
  }
}
export function numericTokens(text: string): string[] {
  return (
    text
      .normalize("NFKC")
      .replace(/[০-৯०-९௦-௯୦-୯౦-౯೦-೯൦-൯٠-٩]/g, (digit) => {
        const n = digit.codePointAt(0)!;
        const base = [
          0x09e6, 0x0966, 0x0be6, 0x0b66, 0x0c66, 0x0ce6, 0x0d66, 0x0660,
        ].find((base) => n >= base && n <= base + 9)!;
        return String(n - base);
      })
      .match(/[0-9]+(?:[.,][0-9]+)?/g) || []
  ).sort();
}
export const quantitiesChanged = (source: string, target: string) =>
  JSON.stringify(numericTokens(source)) !==
  JSON.stringify(numericTokens(target));
export function cacheKey(
  groupId: string,
  text: string,
  source: string,
  target: string,
  version: string,
): string {
  return createHash("sha256")
    .update(
      JSON.stringify([
        groupId,
        text.trim().replace(/\s+/g, " "),
        source,
        target,
        version,
        process.env.GLOSSARY_VERSION || "none",
        process.env.TTS_VOICE || "platform",
      ]),
    )
    .digest("hex");
}
