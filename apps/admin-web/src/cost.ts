export interface CostInputs {
  sttSeconds: number; translationCharacters: number; ttsCharacters: number; llmInputTokens: number; llmOutputTokens: number;
}
export interface Pricing {
  sttPerMinute: number | null; translationPerMillion: number | null; ttsPerMillion: number | null;
  llmInputPerMillion: number | null; llmOutputPerMillion: number | null;
}
export function estimateCost(usage: CostInputs, pricing: Pricing): number | null {
  const lines: [number, number | null, number][] = [
    [usage.sttSeconds, pricing.sttPerMinute, 60],
    [usage.translationCharacters, pricing.translationPerMillion, 1_000_000],
    [usage.ttsCharacters, pricing.ttsPerMillion, 1_000_000],
    [usage.llmInputTokens, pricing.llmInputPerMillion, 1_000_000],
    [usage.llmOutputTokens, pricing.llmOutputPerMillion, 1_000_000],
  ];
  if (lines.some(([amount, rate]) => !Number.isFinite(amount) || amount < 0 || (amount > 0 && (rate === null || !Number.isFinite(rate) || rate < 0)))) return null;
  return lines.reduce((total, [amount, rate, unit]) => total + (amount === 0 ? 0 : amount * rate! / unit), 0);
}
