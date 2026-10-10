import { describe, expect, it } from 'vitest';
import { estimateCost } from './cost';

const usage = { sttSeconds: 120, translationCharacters: 50_000, ttsCharacters: 20_000, llmInputTokens: 1000, llmOutputTokens: 500 };
const rates = { sttPerMinute: 0.006, translationPerMillion: 20, ttsPerMillion: 15, llmInputPerMillion: 1, llmOutputPerMillion: 4 };
describe('provider pricing calculator', () => {
  it('converts seconds, characters, and tokens into a combined USD estimate', () => {
    expect(estimateCost(usage, rates)).toBeCloseTo(1.315, 6);
  });
  it('requires explicit pricing for every processing stage with usage', () => {
    expect(estimateCost(usage, { ...rates, translationPerMillion: null })).toBeNull();
  });
  it('does not require rates for unused processing stages', () => {
    expect(estimateCost({ ...usage, llmInputTokens: 0, llmOutputTokens: 0 }, { ...rates, llmInputPerMillion: null, llmOutputPerMillion: null })).toBeCloseTo(1.312, 6);
  });
  it('rejects negative, nonfinite usage and invalid prices', () => {
    expect(estimateCost({ ...usage, sttSeconds: -1 }, rates)).toBeNull();
    expect(estimateCost({ ...usage, ttsCharacters: NaN }, rates)).toBeNull();
    expect(estimateCost(usage, { ...rates, translationPerMillion: Infinity })).toBeNull();
    expect(estimateCost(usage, { ...rates, sttPerMinute: -1 })).toBeNull();
  });
});
