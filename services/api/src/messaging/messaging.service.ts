import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
  ServiceUnavailableException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Queue, Worker } from "bullmq";
import Redis from "ioredis";
import { Store } from "../common/store";
import { displayName } from "../common/profile";
import { Message, State, ReceiptState, deviceTranslationLanguages } from "../common/types";
import { MessageDto, TranscribeDto } from "../common/validation";
import { hash } from "../common/crypto";
import { dateAfter, now } from "../auth/auth.service";
import { entitlement, membership, privileged, requireCloudPro } from "../groups/groups.service";
import {
  AiProviders,
  HttpAiProviders,
  ProviderError,
  cacheKey,
  quantitiesChanged,
} from "../ai/providers";
import { AudioService } from "../audio/audio.service";
import { inspectWav } from "../audio/wav";
import { RealtimeService } from "../realtime/realtime.service";
import { globalBudgetCaps } from "../common/limits";
import { pricing, quotaCheck, recordUsage } from "../analytics/usage.service";
export function messageAccess(s: State, userId: string, id: string) {
  const m = s.messages.find((v) => v.id === id);
  if (!m) throw new NotFoundException();
  membership(s, m.groupId, userId);
  if (m.expiresAt <= now()) throw new NotFoundException("Message expired");
  if (
    m.senderId !== userId &&
    !s.recipients.some((v) => v.messageId === id && v.userId === userId)
  )
    throw new ForbiddenException();
  if (m.senderId !== userId && m.state === "REVIEW_REQUIRED")
    throw new ForbiddenException("Sender review pending");
  return m;
}
@Injectable()
export class MessagingService implements OnModuleInit, OnModuleDestroy {
  private queue?: Queue;
  private worker?: Worker;
  private redis?: Redis;
  private running = new Set<string>();
  private localJobs = new Set<Promise<unknown>>();
  constructor(
    private readonly store: Store,
    private readonly ai: HttpAiProviders,
    private readonly audio: AudioService,
    private readonly realtime: RealtimeService,
  ) {}
  async onModuleInit() {
    await this.store.init();
    if (process.env.NODE_ENV === "production" && !process.env.REDIS_URL)
      throw new Error(
        "Production requires REDIS_URL for durable text processing",
      );
    if (process.env.REDIS_URL) {
      this.redis = new Redis(process.env.REDIS_URL, {
        maxRetriesPerRequest: null,
      });
      this.queue = new Queue("mine2yourlingo-processing", {
        connection: this.redis as any,
      });
      this.worker = new Worker(
        "mine2yourlingo-processing",
        async (job) => {
          await this.process(job.data.messageId);
        },
        {
          connection: this.redis as any,
          concurrency: 2,
          limiter: { max: 30, duration: 60000 },
        },
      );
      this.worker.on("error", () => {});
    }
    const pending = await this.store.read((s) =>
      s.messages
        .filter((v) => v.state === "PROCESSING" || v.state === "RETRY_PENDING")
        .map((v) => ({ id: v.id, text: v.sourceText })),
    );
    for (const m of pending) {
      if (m.text) await this.schedule(m.id);
      else
        await this.fail(
          m.id,
          "AUDIO_UPLOAD_REQUIRED",
          "Processing was interrupted. Record or upload the audio again.",
        );
    }
  }
  private reservation(
    text: string | undefined,
    seconds: number,
    targets: number,
  ) {
    const p = pricing(),
      length = text?.length || 1000;
    return (
      seconds * p.stt +
      targets *
        (length * p.translation +
          (this.ai.capabilities().tts
            ? Math.min(16000, length * 4) * p.tts
            : 0))
    );
  }
  private async schedule(id: string) {
    if (this.queue) {
      await this.queue.add(
        "process",
        { messageId: id },
        { jobId: id, removeOnComplete: true, removeOnFail: 500, attempts: 1 },
      );
    } else {
      const job = this.process(id);
      this.localJobs.add(job);
      void job.then(
        () => this.localJobs.delete(job),
        () => this.localJobs.delete(job),
      );
    }
  }
  private async createDeviceMessage(userId: string, input: MessageDto) {
    if (!input.text || input.audioBase64) throw new BadRequestException({
      code: "DEVICE_TEXT_REQUIRED", message: "Use phone speech recognition or type the words for a free translated message.",
    });
    const fingerprint = hash(JSON.stringify({ ...input, text: input.text.trim(), processing: "device" }));
    const message = await this.store.transaction((s) => {
      membership(s, input.groupId, userId);
      const prior = s.messages.find((m) => m.senderId === userId && m.idempotencyKey === input.idempotencyKey);
      if (prior) {
        if (prior.requestHash !== fingerprint) throw new BadRequestException({ code: "IDEMPOTENCY_CONFLICT", message: "This key was used for another message." });
        return prior;
      }
      const plan = entitlement(s, userId);
      if (input.mode === "broadcast") {
        privileged(s, input.groupId, userId);
        if (!plan.broadcasts) throw new ForbiddenException("Your plan does not include announcements.");
      }
      const recipients = s.members.filter((m) => m.groupId === input.groupId && m.userId !== userId &&
          (!input.recipientId || m.userId === input.recipientId))
          .map((m) => s.users.find((u) => u.id === m.userId)).filter((u): u is NonNullable<typeof u> => !!u);
      if (!recipients.length) throw new BadRequestException("Select another current team member.");
      if (recipients.some((u) => u.listeningLanguage !== input.sourceLanguage &&
          (!deviceTranslationLanguages.includes(input.sourceLanguage) || !deviceTranslationLanguages.includes(u.listeningLanguage)))) {
        throw new BadRequestException({ code: "DEVICE_LANGUAGE_UNSUPPORTED", message: "A receiver selected a language unavailable in ML Kit device translation. Choose a supported listening language. Cloud translation requires Diamond, consent and configured billing.", sourceLanguage: input.sourceLanguage, unsupportedLanguages: [...new Set(recipients.map(u => u.listeningLanguage).filter(l => l !== input.sourceLanguage && (!deviceTranslationLanguages.includes(input.sourceLanguage) || !deviceTranslationLanguages.includes(l))))] });
      }
      const start = new Date(); start.setUTCDate(1); start.setUTCHours(0, 0, 0, 0);
      if (s.usage.filter((v) => v.userId === userId && v.kind === "message" && v.createdAt >= start.toISOString()).length >= plan.monthlyMessages) {
        throw new ForbiddenException("Monthly message allowance reached.");
      }
      const message: Message = {
        id: randomUUID(), groupId: input.groupId, senderId: userId,
        sourceLanguage: input.sourceLanguage, sourceText: input.text!.trim(), processing: "device",
        mode: input.mode, state: "READY", idempotencyKey: input.idempotencyKey,
        requestHash: fingerprint, createdAt: now(), expiresAt: dateAfter(Number(process.env.MESSAGE_RETENTION_DAYS || 30) * 86400),
        durationSeconds: 0, reservationUsd: 0, needsReview: false,
      };
      s.messages.push(message);
      for (const user of recipients) s.recipients.push({ id: randomUUID(), messageId: message.id,
        userId: user.id, language: user.listeningLanguage, state: "PENDING", updatedAt: now() });
      for (const language of new Set(recipients.map((u) => u.listeningLanguage))) {
        const same = language === input.sourceLanguage;
        s.translations.push({ id: randomUUID(), messageId: message.id, language,
          text: same ? message.sourceText : "", needsDeviceTranslation: !same,
          provider: same ? "source-language-passthrough" : "device-translation-pending",
          voiceProfile: "device" });
      }
      recordUsage(s, userId, input.groupId, message.id, "message", 1, 0, "device-processing");
      return message;
    });
    await this.realtime.message(message.id, "message.ready");
    return this.get(userId, message.id);
  }

  private async createVoiceMessage(userId: string, input: MessageDto) {
    if (!input.audioBase64 || input.text || input.mimeType !== "audio/wav") throw new BadRequestException("Voice messages require a PCM WAV recording.");
    const bytes = Buffer.from(input.audioBase64, "base64");
    const metadata = inspectWav(bytes);
    if (metadata.silent) throw new BadRequestException({ code: "NO_SPEECH", message: "No voice was recorded. Speak closer to the microphone." });
    const fingerprint = hash(JSON.stringify({ groupId: input.groupId, recipientId: input.recipientId, mode: input.mode, sourceLanguage: input.sourceLanguage, audio: hash(input.audioBase64), processing: "voice" }));
    let uploaded: string | undefined;
    let message: Message;
    try {
      message = await this.store.transaction(async (s) => {
        membership(s, input.groupId, userId);
        const prior = s.messages.find((m) => m.senderId === userId && m.idempotencyKey === input.idempotencyKey);
        if (prior) {
          if (prior.requestHash !== fingerprint) throw new BadRequestException({ code: "IDEMPOTENCY_CONFLICT", message: "This key was used for another message." });
          return prior;
        }
        const plan = entitlement(s, userId);
        if (input.mode === "broadcast") {
          privileged(s, input.groupId, userId);
          if (!plan.broadcasts) throw new ForbiddenException("Gold or Diamond is required for announcements.");
        }
        const recipients = s.members.filter((m) => m.groupId === input.groupId && m.userId !== userId && (!input.recipientId || m.userId === input.recipientId)).map((m) => s.users.find((u) => u.id === m.userId)).filter((u): u is NonNullable<typeof u> => !!u);
        if (!recipients.length) throw new BadRequestException("Select another current team member.");
        const start = new Date(); start.setUTCDate(1); start.setUTCHours(0, 0, 0, 0);
        if (s.usage.filter((v) => v.userId === userId && v.kind === "message" && v.createdAt >= start.toISOString()).length >= plan.monthlyMessages) throw new ForbiddenException("Monthly message allowance reached.");
        uploaded = await this.audio.put(bytes, "audio/wav");
        const m: Message = { id: randomUUID(), groupId: input.groupId, senderId: userId, sourceLanguage: input.sourceLanguage, sourceText: "", processing: "voice", mode: input.mode, state: "READY", idempotencyKey: input.idempotencyKey, requestHash: fingerprint, createdAt: now(), expiresAt: dateAfter(Number(process.env.MESSAGE_RETENTION_DAYS || 30) * 86400), durationSeconds: metadata.seconds, reservationUsd: 0, needsReview: false };
        s.messages.push(m);
        for (const user of recipients) s.recipients.push({ id: randomUUID(), messageId: m.id, userId: user.id, language: user.listeningLanguage, state: "PENDING", updatedAt: now() });
        // Each intended recipient receives the original recording, in its original language.
        for (const language of new Set([...recipients.map((u) => u.listeningLanguage), input.sourceLanguage])) s.translations.push({ id: randomUUID(), messageId: m.id, language, text: "", audioId: uploaded, audioMimeType: "audio/wav", provider: "original-voice", voiceProfile: "original" });
        recordUsage(s, userId, input.groupId, m.id, "message", 1, 0, "original-voice");
        return m;
      });
    } catch (error) {
      if (uploaded) await this.audio.delete(uploaded).catch(() => {});
      throw error;
    }
    await this.realtime.message(message.id, "message.ready");
    return this.get(userId, message.id);
  }

  async create(userId: string, input: MessageDto) {
    if (!!input.text === !!input.audioBase64)
      throw new BadRequestException(
        "Provide exactly one of text or audioBase64",
      );
    if (input.text && !input.text.trim())
      throw new BadRequestException("Message text is empty");
    if (input.mode === "direct" && !input.recipientId)
      throw new BadRequestException("Direct messages require recipientId");
    if (input.mode !== "direct" && input.recipientId)
      throw new BadRequestException(
        "recipientId is only valid for direct messages",
      );
    if (input.processing === "voice") return this.createVoiceMessage(userId, input);
    if (input.processing === "device") return this.createDeviceMessage(userId, input);
    let audioBytes: Buffer | undefined,
      seconds = 0;
    if (input.audioBase64) {
      if (input.mimeType !== "audio/wav")
        throw new BadRequestException({
          code: "AUDIO_FORMAT_UNSUPPORTED",
          message: "PCM WAV is required for verified duration enforcement.",
        });
      audioBytes = Buffer.from(input.audioBase64, "base64");
      const metadata = inspectWav(audioBytes);
      if (metadata.silent)
        throw new BadRequestException({
          code: "NO_SPEECH",
          message: "The recording contains no detectable audio.",
        });
      seconds = metadata.seconds;
    }
    const fingerprint = hash(
      JSON.stringify({
        groupId: input.groupId,
        recipientId: input.recipientId,
        sourceLanguage: input.sourceLanguage,
        text: input.text,
        audio: input.audioBase64 ? hash(input.audioBase64) : undefined,
        mode: input.mode,
        review: input.needsReview || input.requiresReview || false,
      }),
    );
    const result = await this.store.transaction((s) => {
      membership(s, input.groupId, userId);
      const previous = s.messages.find(
        (v) =>
          v.senderId === userId && v.idempotencyKey === input.idempotencyKey,
      );
      if (previous) {
        if (previous.requestHash !== fingerprint)
          throw new BadRequestException({
            code: "IDEMPOTENCY_CONFLICT",
            message: "This idempotency key was used for a different message.",
          });
        return { message: previous, existing: true };
      }
      requireCloudPro(s, userId);
      const plan = entitlement(s, userId);
      if (input.mode === "broadcast") {
        privileged(s, input.groupId, userId);
        if (!plan.broadcasts)
          throw new ForbiddenException({
            code: "BROADCAST_PLAN_REQUIRED",
            message: "Your current plan does not include broadcasts.",
          });
      }
      let members = s.members.filter(
        (v) => v.groupId === input.groupId && v.userId !== userId,
      );
      if (input.recipientId)
        members = members.filter((v) => v.userId === input.recipientId);
      if (!members.length)
        throw new BadRequestException("Select another current group member");
      const recipients = members.map(
        (v) => s.users.find((u) => u.id === v.userId)!,
      );
      const targets = new Set(recipients.map((v) => v.listeningLanguage));
      const translateTargets = [...targets].filter(
        (v) => v !== input.sourceLanguage,
      ).length;
      if (
        (audioBytes || translateTargets || this.ai.capabilities().tts) &&
        !s.users.find((v) => v.id === userId)!.providerConsent
      )
        throw new ForbiddenException({
          code: "PROVIDER_CONSENT_REQUIRED",
          message:
            "Review and enable external AI processing in privacy settings before sending.",
        });
      const configured = this.ai.capabilities();
      if (audioBytes && !configured.stt)
        throw new ServiceUnavailableException({
          code: "STT_UNCONFIGURED",
          message:
            "Speech recognition is not configured. No provider request was started.",
        });
      if (translateTargets && !configured.translation)
        throw new ServiceUnavailableException({
          code: "TRANSLATION_UNCONFIGURED",
          message:
            "Translation is not configured. No translation was generated.",
        });
      try {
        if (audioBytes) this.ai.assertPricing("stt");
        if (translateTargets) this.ai.assertPricing("translation");
        if (configured.tts) this.ai.assertPricing("tts");
      } catch (error) {
        throw new ServiceUnavailableException({
          code: "PRICING_UNCONFIGURED",
          message:
            "Provider pricing must be configured, reviewed and versioned before external processing.",
        });
      }
      const reservation =
        this.reservation(input.text, seconds, translateTargets) +
        (this.ai.capabilities().tts && targets.has(input.sourceLanguage)
          ? (input.text?.length || 1000) * 4 * pricing().tts
          : 0);
      quotaCheck(s, userId, input.groupId, reservation, seconds);
      const message: Message = {
        id: randomUUID(),
        groupId: input.groupId,
        senderId: userId,
        sourceLanguage: input.sourceLanguage,
        sourceText: input.text?.trim() || "",
        mode: input.mode,
        state: "PROCESSING",
        idempotencyKey: input.idempotencyKey,
        requestHash: fingerprint,
        processing: "cloud",
        createdAt: now(),
        expiresAt: dateAfter(
          Number(process.env.MESSAGE_RETENTION_DAYS || 30) * 86400,
        ),
        durationSeconds: seconds,
        reservationUsd: reservation,
        needsReview:
          !!audioBytes ||
          !!(input.needsReview || input.requiresReview) ||
          /\p{Decimal_Number}|\b(one|two|three|four|five|stop|safety|helmet|danger|do not)\b|இரண்டு|பாதுகாப்பு|நிறுத்த|দুই|নিরাপত্তা|दो|सुरक्षा|ନିରାପତ୍ତା|ଦୁଇ/iu.test(
            input.text || "",
          ),
      };
      s.messages.push(message);
      for (const u of recipients)
        s.recipients.push({
          id: randomUUID(),
          messageId: message.id,
          userId: u.id,
          language: u.listeningLanguage,
          state: "PENDING",
          updatedAt: now(),
        });
      recordUsage(
        s,
        userId,
        message.groupId,
        message.id,
        "message",
        1,
        0,
        "internal",
      );
      recordUsage(
        s,
        userId,
        message.groupId,
        message.id,
        "reservation",
        1,
        reservation,
        "budget-reservation",
      );
      return { message, existing: false };
    });
    if (result.existing) return this.get(userId, result.message.id);
    if (audioBytes) {
      try {
        await this.charge(
          result.message.id,
          "stt",
          seconds,
          seconds * pricing().stt,
          "configured-stt",
        );
        const started = Date.now();
        const transcription = await this.ai.transcribe(
          audioBytes,
          "audio/wav",
          input.sourceLanguage,
        );
        await this.store.transaction((s) => {
          const m = s.messages.find((v) => v.id === result.message.id)!;
          m.sourceText = transcription.text;
          m.needsReview = m.needsReview || /\d/.test(transcription.text);
          m.timings = { sttMs: Date.now() - started };
        });
      } catch (error) {
        await this.fail(
          result.message.id,
          error instanceof ProviderError ? error.code : "STT_FAILED",
          error instanceof ProviderError
            ? error.message
            : "Speech recognition failed.",
        );
        return this.get(userId, result.message.id);
      } finally {
        audioBytes.fill(0);
      }
    }
    await this.schedule(result.message.id);
    return this.get(userId, result.message.id);
  }
  async get(userId: string, id: string) {
    return this.store.read((s) => {
      const m = messageAccess(s, userId, id);
      const own = m.senderId === userId;
      const recipient = s.recipients.find(
        (v) => v.messageId === id && v.userId === userId,
      );
      const { requestHash, reservationUsd, idempotencyKey, ...visible } = m;
      // Local inference replays/delivers in each receiver's current language.
      const currentLanguages = m.processing === "device" ? [...new Set(s.recipients
        .filter(r => r.messageId === id && (own || r.userId === userId))
        .map(r => s.users.find(u => u.id === r.userId)?.listeningLanguage || r.language))] : [];
      return {
        ...visible,
        senderDisplayName: displayName(s.users.find(u => u.id === m.senderId)?.displayName),
        translations: m.processing === "device" ? currentLanguages.map(language => ({
          language, text: language === m.sourceLanguage ? m.sourceText : "",
          needsDeviceTranslation: language !== m.sourceLanguage,
          provider: language === m.sourceLanguage ? "source-language-passthrough" : "device-translation-pending",
        })) : s.translations
          .filter(
            (v) =>
              v.messageId === id && (own || v.language === recipient?.language),
          )
          .map((v) => ({
            language: v.language,
            text: v.text,
            provider: v.provider,
            ...(v.needsDeviceTranslation ? { needsDeviceTranslation: true } : {}),
            ...(v.audioId
              ? {
                  audioUrl: this.audio.url(v.audioId, userId),
                  audioMimeType: v.audioMimeType,
                }
              : {}),
          })),
        recipients: s.recipients
          .filter((v) => v.messageId === id && (own || v.userId === userId))
          .map((v) => ({
            userId: v.userId,
            displayName: displayName(s.users.find(u => u.id === v.userId)?.displayName),
            state: v.state,
            language: m.processing === "device" ? s.users.find(u => u.id === v.userId)?.listeningLanguage || v.language : v.language,
          })),
      };
    });
  }
  async list(userId: string, groupId?: string) {
    const ids = await this.store.read((s) => {
      if (groupId) membership(s, groupId, userId);
      const groups = s.members
        .filter((v) => v.userId === userId)
        .map((v) => v.groupId);
      return s.messages
        .filter(
          (v) =>
            (!groupId || v.groupId === groupId) &&
            groups.includes(v.groupId) &&
            v.expiresAt > now() &&
            (v.senderId === userId ||
              (v.state !== "REVIEW_REQUIRED" &&
                s.recipients.some(
                  (r) => r.messageId === v.id && r.userId === userId,
                ))),
        )
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
        .slice(0, 100)
        .map((v) => v.id);
    });
    return Promise.all(ids.map((id) => this.get(userId, id)));
  }
  private async charge(
    messageId: string,
    kind: "stt" | "translation" | "tts",
    amount: number,
    cost: number,
    provider: string,
  ) {
    await this.store.transaction((s) => {
      const chargedMessage = s.messages.find((v) => v.id === messageId);
      if (chargedMessage) requireCloudPro(s, chargedMessage.senderId);
      const m = s.messages.find((v) => v.id === messageId);
      if (!m || m.state !== "PROCESSING")
        throw new ProviderError(
          "MESSAGE_INTERRUPTED",
          "Message processing was interrupted.",
        );
      membership(s, m.groupId, m.senderId);
      try {
        globalBudgetCaps();
        entitlement(s, m.senderId);
        const group = s.groups.find((v) => v.id === m.groupId)!;
        entitlement(s, group.createdBy);
      } catch (error) {
        if (error instanceof ServiceUnavailableException)
          throw new ProviderError(
            "USAGE_LIMITS_INVALID",
            "Usage limits are not configured correctly. AI processing is paused.",
          );
        throw error;
      }
      if (!s.users.find((v) => v.id === m.senderId)?.providerConsent)
        throw new ProviderError(
          "PROVIDER_CONSENT_REVOKED",
          "External processing consent was revoked. Processing stopped.",
        );
      if (
        !s.recipients.some(
          (v) =>
            v.messageId === messageId &&
            s.members.some(
              (member) =>
                member.groupId === m.groupId && member.userId === v.userId,
            ),
        )
      )
        throw new ProviderError(
          "NO_AUTHORIZED_RECIPIENTS",
          "No intended recipients remain in the group.",
        );
      const lastReservationIndex = s.usage
        .map((v) => v.messageId === messageId && v.kind === "reservation")
        .lastIndexOf(true);
      const spent = s.usage
        .slice(lastReservationIndex + 1)
        .filter(
          (v) =>
            v.messageId === messageId &&
            ["stt", "translation", "tts"].includes(v.kind),
        )
        .reduce((a, b) => a + b.estimatedCostUsd, 0);
      if (spent + cost > m.reservationUsd + 0.0000001)
        throw new ProviderError(
          "BUDGET_ESTIMATE_EXCEEDED",
          "Processing exceeded its reserved budget and has stopped.",
        );
      recordUsage(s, m.senderId, m.groupId, m.id, kind, amount, cost, provider);
    });
  }
  private release(s: State, m: Message) {
    if (m.reservationUsd) {
      recordUsage(
        s,
        m.senderId,
        m.groupId,
        m.id,
        "release",
        1,
        -m.reservationUsd,
        "budget-release",
      );
      m.reservationUsd = 0;
    }
  }
  private async fail(id: string, code: string, message: string) {
    await this.store.transaction((s) => {
      const m = s.messages.find((v) => v.id === id);
      if (!m || m.state === "CANCELLED") return;
      m.state = "FAILED";
      m.error = { code, message };
      this.release(s, m);
    });
    await this.realtime.message(id);
  }
  async process(id: string) {
    if (this.running.has(id)) return;
    this.running.add(id);
    const start = Date.now();
    try {
      const snapshot = await this.store.read((s) => {
        const m = s.messages.find((v) => v.id === id);
        if (!m || m.state !== "PROCESSING") return;
        membership(s, m.groupId, m.senderId);
        requireCloudPro(s, m.senderId);
        return {
          message: m,
          languages: [
            ...new Set(
              s.recipients
                .filter(
                  (v) =>
                    v.messageId === id &&
                    s.members.some(
                      (member) =>
                        member.groupId === m.groupId &&
                        member.userId === v.userId,
                    ),
                )
                .map((v) => v.language),
            ),
          ],
        };
      });
      if (!snapshot) return;
      const { message, languages } = snapshot;
      if (!languages.length)
        throw new ProviderError(
          "NO_AUTHORIZED_RECIPIENTS",
          "No intended recipients remain in the group.",
        );
      if (!message.sourceText)
        throw new ProviderError(
          "AUDIO_UPLOAD_REQUIRED",
          "Audio must be uploaded again.",
        );
      let quantityProblem = false;
      for (const language of languages) {
        const already = await this.store.read((s) =>
          s.translations.some(
            (v) => v.messageId === id && v.language === language,
          ),
        );
        if (already) continue;
        const scope =
          message.mode === "direct"
            ? `${message.groupId}:${[message.senderId, ...(await this.store.read((s) => s.recipients.filter((v) => v.messageId === id).map((v) => v.userId)))].sort().join(":")}`
            : message.groupId;
        const key = cacheKey(
          scope,
          message.sourceText,
          message.sourceLanguage,
          language,
          this.ai.version(),
        );
        const cached = await this.store.read((s) =>
          s.cache.find((v) => v.id === key && v.expiresAt > now()),
        );
        let text: string,
          provider: string,
          audioId: string | undefined,
          audioMimeType: string | undefined;
        if (cached) {
          text = cached.text;
          provider = cached.provider;
          audioId = cached.audioId;
          audioMimeType = cached.audioMimeType;
          await this.store.transaction((s) =>
            recordUsage(
              s,
              message.senderId,
              message.groupId,
              id,
              "cache",
              1,
              0,
              "group-private-cache",
            ),
          );
        } else {
          if (language !== message.sourceLanguage)
            await this.charge(
              id,
              "translation",
              message.sourceText.length,
              message.sourceText.length * pricing().translation,
              "configured-translation",
            );
          const translateStart = Date.now();
          const translated = await this.ai.translate(
            message.sourceText,
            message.sourceLanguage,
            language,
          );
          text = translated.text;
          provider = translated.provider;
          await this.store.transaction((s) => {
            const m = s.messages.find((v) => v.id === id)!;
            m.timings = {
              ...m.timings,
              [`translation_${language}Ms`]: Date.now() - translateStart,
            };
          });
          quantityProblem =
            quantityProblem || quantitiesChanged(message.sourceText, text);
          if (
            this.ai.capabilities().tts &&
            this.ai.supportsSynthesis(language, text) &&
            !quantitiesChanged(message.sourceText, text)
          ) {
            await this.charge(
              id,
              "tts",
              text.length,
              text.length * pricing().tts,
              "configured-tts",
            );
            const speech = await this.ai.synthesize(text, language);
            if (speech) {
              audioId = await this.audio.put(speech.bytes, speech.mimeType);
              audioMimeType = speech.mimeType;
            }
          }
          await this.store.transaction((s) => {
            if (!s.groups.some((v) => v.id === message.groupId)) return;
            const cache = {
              id: key,
              groupId: message.groupId,
              text,
              language,
              audioId,
              audioMimeType,
              provider,
              expiresAt: [dateAfter(86400), message.expiresAt].sort()[0],
            };
            s.cache = s.cache.filter((v) => v.id !== key);
            s.cache.push(cache);
          });
        }
        quantityProblem =
          quantityProblem || quantitiesChanged(message.sourceText, text);
        await this.store.transaction((s) => {
          const m = s.messages.find((v) => v.id === id);
          if (!m || m.state !== "PROCESSING") return;
          s.translations.push({
            id: randomUUID(),
            messageId: id,
            language,
            text,
            provider,
            audioId,
            audioMimeType,
            voiceProfile: process.env.TTS_VOICE || "platform",
          });
        });
      }
      await this.store.transaction((s) => {
        const m = s.messages.find((v) => v.id === id);
        if (!m || m.state !== "PROCESSING") return;
        membership(s, m.groupId, m.senderId);
        m.state =
          m.needsReview || quantityProblem ? "REVIEW_REQUIRED" : "READY";
        if (quantityProblem)
          m.error = {
            code: "QUANTITY_REVIEW_REQUIRED",
            message:
              "Numeric values changed during translation. Review and correct before delivery.",
          };
        m.timings = { ...m.timings, processingMs: Date.now() - start };
        this.release(s, m);
      });
      await this.realtime.message(id, "message.ready");
    } catch (error) {
      await this.fail(
        id,
        error instanceof ProviderError ? error.code : "PROCESSING_FAILED",
        error instanceof ProviderError
          ? error.message
          : "Processing failed. No delivery was confirmed.",
      );
    } finally {
      this.running.delete(id);
    }
  }
  async ack(userId: string, id: string, state: ReceiptState) {
    const result = await this.store.transaction((s) => {
      const m = messageAccess(s, userId, id);
      if (m.state !== "READY")
        throw new BadRequestException("Message is not ready for playback");
      const recipient = s.recipients.find(
        (v) => v.messageId === id && v.userId === userId,
      );
      if (!recipient)
        throw new ForbiddenException(
          "Only recipients can acknowledge delivery",
        );
      if (recipient.state === state)
        return { status: "duplicate", state: recipient.state };
      const order = [
        "PENDING",
        "DELIVERED",
        "PLAYBACK_STARTED",
        "PLAYBACK_COMPLETED",
      ];
      if (state === "FAILED") {
        if (recipient.state === "PLAYBACK_COMPLETED")
          throw new BadRequestException("Playback already completed");
        recipient.state = state;
      } else {
        const from = order.indexOf(recipient.state),
          to = order.indexOf(state);
        if (to <= from) return { status: "duplicate", state: recipient.state };
        if (to !== from + 1 && recipient.state !== "FAILED")
          throw new BadRequestException(
            "Acknowledge each playback state in order",
          );
        recipient.state = state;
      }
      recipient.updatedAt = now();
      return { status: "acknowledged", state: recipient.state };
    });
    if (result.status === "acknowledged") await this.realtime.receipt(id, userId, result.state);
    return result;
  }
  async confirm(userId: string, id: string) {
    await this.store.transaction((s) => {
      const m = messageAccess(s, userId, id);
      if (m.senderId !== userId) throw new ForbiddenException();
      if (m.state !== "REVIEW_REQUIRED")
        throw new BadRequestException("Message does not require review");
      if (m.error?.code === "QUANTITY_REVIEW_REQUIRED")
        throw new BadRequestException({
          code: "CORRECTION_REQUIRED",
          message:
            "Cancel this message and submit corrected text because numeric values changed.",
        });
      m.state = "READY";
      m.needsReview = false;
      delete m.error;
    });
    await this.realtime.message(id, "message.ready");
    return this.get(userId, id);
  }
  async retry(userId: string, id: string) {
    await this.store.transaction((s) => {
      const m = messageAccess(s, userId, id);
      if (m.senderId !== userId) throw new ForbiddenException();
      if (m.state !== "FAILED")
        throw new BadRequestException("Only failed messages can be retried");
      if (!m.sourceText)
        throw new BadRequestException({
          code: "AUDIO_UPLOAD_REQUIRED",
          message:
            "Raw recordings are not retained. Upload audio again with a new idempotency key.",
        });
      const languages = [
        ...new Set(
          s.recipients
            .filter(
              (v) =>
                v.messageId === id &&
                s.members.some(
                  (member) =>
                    member.groupId === m.groupId && member.userId === v.userId,
                ),
            )
            .map((v) => v.language),
        ),
      ];
      if (!languages.length)
        throw new BadRequestException({
          code: "NO_AUTHORIZED_RECIPIENTS",
          message: "No intended recipients remain in the group.",
        });
      if (!s.users.find((v) => v.id === userId)?.providerConsent)
        throw new ForbiddenException(
          "External processing consent is required.",
        );
      const reserve = this.reservation(m.sourceText, 0, languages.length);
      quotaCheck(s, userId, m.groupId, reserve, 0, false);
      m.state = "PROCESSING";
      m.reservationUsd = reserve;
      delete m.error;
      recordUsage(
        s,
        userId,
        m.groupId,
        id,
        "reservation",
        1,
        reserve,
        "budget-reservation",
      );
    });
    await this.schedule(id);
    return this.get(userId, id);
  }
  async cancel(userId: string, id: string) {
    await this.store.transaction((s) => {
      const m = messageAccess(s, userId, id);
      if (m.senderId !== userId) throw new ForbiddenException();
      if (
        m.state === "READY" ||
        s.recipients.some((v) => v.messageId === id && v.state !== "PENDING")
      )
        throw new BadRequestException("A released message cannot be recalled");
      m.state = "CANCELLED";
      this.release(s, m);
    });
    await this.realtime.message(id);
    return this.get(userId, id);
  }
  async transcribe(userId: string, input: TranscribeDto) {
    const bytes = Buffer.from(input.audioBase64, "base64");
    const metadata = inspectWav(bytes);
    if (metadata.silent) throw new BadRequestException("No detectable audio");
    const key = hash(
      JSON.stringify(["draft", userId, input.groupId, input.idempotencyKey]),
    );
    const fingerprint = hash(
      JSON.stringify([input.sourceLanguage, input.audioBase64]),
    );
    const claimed = await this.store.transaction((s) => {
      membership(s, input.groupId, userId);
      requireCloudPro(s, userId);
      const cached = s.cache.find((v) => v.id === key && v.expiresAt > now());
      if (cached) {
        if (cached.requestHash !== fingerprint)
          throw new BadRequestException({
            code: "IDEMPOTENCY_CONFLICT",
            message: "This transcription key was used for different audio.",
          });
        if (cached.status === "PROCESSING")
          throw new BadRequestException({
            code: "TRANSCRIPTION_PROCESSING",
            message:
              "This recording is already being transcribed. Retry synchronization shortly.",
          });
        if (cached.status === "FAILED")
          throw new BadRequestException({
            code: cached.errorCode || "STT_FAILED",
            message:
              "The previous transcription failed. Record again with a new key.",
          });
        return { cached };
      }
      if (!this.ai.capabilities().stt)
        throw new ServiceUnavailableException({
          code: "STT_UNCONFIGURED",
          message: "Speech recognition is not configured.",
        });
      try {
        this.ai.assertPricing("stt");
      } catch {
        throw new ServiceUnavailableException({
          code: "PRICING_UNCONFIGURED",
          message: "Provider pricing is not reviewed and configured.",
        });
      }
      if (!s.users.find((v) => v.id === userId)!.providerConsent)
        throw new ForbiddenException({
          code: "PROVIDER_CONSENT_REQUIRED",
          message: "Enable external AI processing in privacy settings.",
        });
      const cost = metadata.seconds * pricing().stt;
      quotaCheck(s, userId, input.groupId, cost, metadata.seconds, false);
      recordUsage(
        s,
        userId,
        input.groupId,
        undefined,
        "stt",
        metadata.seconds,
        cost,
        "configured-stt",
      );
      s.cache.push({
        id: key,
        groupId: input.groupId,
        text: "",
        language: input.sourceLanguage,
        provider: "pending",
        expiresAt: dateAfter(3600),
        status: "PROCESSING",
        requestHash: fingerprint,
      });
      return {};
    });
    if (claimed.cached) {
      bytes.fill(0);
      return {
        text: claimed.cached.text,
        sourceLanguage: input.sourceLanguage,
        provider: claimed.cached.provider,
        draftId: key,
      };
    }
    try {
      const result = await this.ai.transcribe(
        bytes,
        "audio/wav",
        input.sourceLanguage,
      );
      await this.store.transaction((s) => {
        const draft = s.cache.find((v) => v.id === key);
        if (!draft) throw new ForbiddenException("Transcription was revoked");
        membership(s, input.groupId, userId);
        draft.text = result.text;
        draft.provider = result.provider;
        draft.status = "READY";
      });
      return {
        text: result.text,
        sourceLanguage: input.sourceLanguage,
        provider: result.provider,
        draftId: key,
      };
    } catch (error) {
      const code = error instanceof ProviderError ? error.code : "STT_FAILED";
      await this.store.transaction((s) => {
        const draft = s.cache.find((v) => v.id === key);
        if (draft) {
          draft.status = "FAILED";
          draft.errorCode = code;
        }
      });
      throw new BadRequestException({
        code,
        message:
          error instanceof ProviderError
            ? error.message
            : "Speech recognition failed.",
      });
    } finally {
      bytes.fill(0);
    }
  }

  async settle() {
    await Promise.all([...this.localJobs]);
  }
  async onModuleDestroy() {
    await this.settle();
    await this.worker?.close();
    await this.queue?.close();
    await this.redis?.quit();
  }
}
