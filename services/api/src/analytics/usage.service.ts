import { HttpException, Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Store } from "../common/store";
import { State, Usage } from "../common/types";
import { cloudAiAllowed, entitlement, membership } from "../groups/groups.service";
import { now } from "../auth/auth.service";
import { globalBudgetCaps } from "../common/limits";
export const pricing = () => ({
  version:
    process.env.AI_PRICING_VERSION || "development-conservative-estimate-v1",
  stt: Number(process.env.STT_USD_PER_SECOND || 0.0002),
  translation: Number(process.env.TRANSLATION_USD_PER_CHARACTER || 0.00002),
  tts: Number(process.env.TTS_USD_PER_CHARACTER || 0.00005),
});
export function monthStart() {
  return new Date().toISOString().slice(0, 7) + "-01T00:00:00.000Z";
}
export function dayStart() {
  return new Date().toISOString().slice(0, 10) + "T00:00:00.000Z";
}
export function costs(events: Usage[]) {
  return events.reduce((sum, v) => sum + v.estimatedCostUsd, 0);
}
export function quotaCheck(
  s: State,
  userId: string,
  groupId: string,
  reservation: number,
  seconds: number,
  createsMessage = true,
) {
  const globalCaps = globalBudgetCaps();
  membership(s, groupId, userId);
  const plan = entitlement(s, userId);
  const group = s.groups.find((v) => v.id === groupId)!;
  const groupPlan = entitlement(s, group.createdBy);
  const monthly = s.usage.filter(
    (v) => v.userId === userId && v.createdAt >= monthStart(),
  );
  const daily = monthly.filter((v) => v.createdAt >= dayStart());
  const groupUsage = s.usage.filter(
    (v) => v.groupId === groupId && v.createdAt >= monthStart(),
  );
  const globalMonth = s.usage.filter((v) => v.createdAt >= monthStart()),
    globalDay = globalMonth.filter((v) => v.createdAt >= dayStart());
  if (
    costs(globalMonth) + reservation > globalCaps.monthly ||
    costs(globalDay) + reservation > globalCaps.daily
  )
    throw new HttpException(
      {
        code: "GLOBAL_BUDGET_EXCEEDED",
        message:
          "AI processing is paused because the service spending budget has been reached.",
      },
      429,
    );
  if (
    (createsMessage &&
      monthly.filter((v) => v.kind === "message").length >=
        plan.monthlyMessages) ||
    monthly.filter((v) => v.kind === "stt").reduce((a, b) => a + b.amount, 0) +
      seconds >
      plan.monthlyAudioSeconds ||
    costs(monthly) + reservation > plan.monthlyBudgetUsd ||
    costs(daily) + reservation > plan.dailyBudgetUsd ||
    costs(groupUsage) + reservation > groupPlan.monthlyBudgetUsd
  )
    throw new HttpException(
      {
        code: "QUOTA_EXCEEDED",
        message:
          "Usage or AI spending quota reached. No provider request was started.",
      },
      429,
    );
}
export function recordUsage(
  s: State,
  userId: string,
  groupId: string,
  messageId: string | undefined,
  kind: Usage["kind"],
  amount: number,
  estimatedCostUsd: number,
  provider: string,
) {
  s.usage.push({
    id: randomUUID(),
    userId,
    groupId,
    messageId,
    kind,
    amount,
    estimatedCostUsd,
    provider,
    pricingVersion: pricing().version,
    createdAt: now(),
  });
}
@Injectable()
export class UsageService {
  constructor(private readonly store: Store) {}
  get(userId: string) {
    return this.store.read((s) => {
      const subscription = s.subscriptions.find((v) => v.userId === userId);
      const plan = entitlement(s, userId);
      const events = s.usage.filter(
        (v) => v.userId === userId && v.createdAt >= monthStart(),
      );
      return {
        planId: plan.id,
        planName: plan.name,
        cloudAiAllowed: cloudAiAllowed(s, userId),
        month: monthStart().slice(0, 7),
        messages: events.filter((v) => v.kind === "message").length,
        audioSeconds: events
          .filter((v) => v.kind === "stt")
          .reduce((a, b) => a + b.amount, 0),
        translationCharacters: events
          .filter((v) => v.kind === "translation")
          .reduce((a, b) => a + b.amount, 0),
        ttsCharacters: events
          .filter((v) => v.kind === "tts")
          .reduce((a, b) => a + b.amount, 0),
        estimatedCostUsd: Math.max(0, costs(events)),
        cacheHits: events.filter((v) => v.kind === "cache").length,
        limits: plan
          ? {
              monthlyMessages: plan.monthlyMessages,
              monthlyAudioSeconds: plan.monthlyAudioSeconds,
              monthlyBudgetUsd: plan.monthlyBudgetUsd,
              dailyBudgetUsd: plan.dailyBudgetUsd,
            }
          : {
              monthlyMessages: 0,
              monthlyAudioSeconds: 0,
              monthlyBudgetUsd: 0,
              dailyBudgetUsd: 0,
            },
        pricingVersion: pricing().version,
        subscription,
      };
    });
  }
}
