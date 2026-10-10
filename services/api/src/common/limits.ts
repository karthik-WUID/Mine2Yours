import { ServiceUnavailableException } from "@nestjs/common";

const invalidLimits = () =>
  new ServiceUnavailableException({
    code: "USAGE_LIMITS_INVALID",
    message:
      "Usage limits are not configured correctly. AI processing is paused.",
  });

export function finiteNonnegativeLimit(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw invalidLimits();
  }
  return value;
}

export function globalBudgetCaps() {
  const read = (name: string, fallback: number): number => {
    const configured = process.env[name];
    if (configured === undefined) return fallback;
    const parsed = configured.trim() === "" ? NaN : Number(configured);
    return finiteNonnegativeLimit(parsed);
  };
  return {
    daily: read("GLOBAL_DAILY_AI_BUDGET_USD", 10),
    monthly: read("GLOBAL_MONTHLY_AI_BUDGET_USD", 100),
  };
}

export function validatePlanLimits(plan: {
  priceInr: number;
  monthlyMessages: number;
  monthlyAudioSeconds: number;
  monthlyBudgetUsd: number;
  dailyBudgetUsd: number;
  maxGroupMembers: number;
}) {
  for (const value of [
    plan.priceInr,
    plan.monthlyMessages,
    plan.monthlyAudioSeconds,
    plan.monthlyBudgetUsd,
    plan.dailyBudgetUsd,
    plan.maxGroupMembers,
  ]) {
    finiteNonnegativeLimit(value);
  }
}
