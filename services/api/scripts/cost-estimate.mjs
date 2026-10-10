import "dotenv/config";
const args = Object.fromEntries(
  process.argv.slice(2).map((argument) => {
    const [key, value] = argument.replace(/^--/, "").split("=");
    return [key, Number(value)];
  }),
);
const required = [
  "seconds",
  "characters",
  "languages",
  "messagesPerMonth",
  "monthlyRevenueInr",
  "usdInr",
];
if (
  required.some((key) => !Number.isFinite(args[key]) || args[key] < 0) ||
  args.usdInr <= 0 ||
  args.monthlyRevenueInr <= 0 ||
  args.languages < 1 ||
  !Number.isInteger(args.languages) ||
  (args.expansion !== undefined &&
    (!Number.isFinite(args.expansion) || args.expansion <= 0))
) {
  process.stderr.write(
    "Provide --seconds=N --characters=N --languages=N --messagesPerMonth=N --monthlyRevenueInr=N --usdInr=N. Supply your reviewed exchange assumption; no current rate is implied.\n",
  );
  process.exitCode = 1;
} else {
  const rates = {
    stt: Number(process.env.STT_USD_PER_SECOND || 0.0002),
    translation: Number(process.env.TRANSLATION_USD_PER_CHARACTER || 0.00002),
    tts: Number(process.env.TTS_USD_PER_CHARACTER || 0.00005),
  };
  const expansion = args.expansion || 1,
    stt = args.seconds * rates.stt,
    translation = args.characters * args.languages * rates.translation,
    tts = args.characters * expansion * args.languages * rates.tts;
  const perMessageUsd = stt + translation + tts,
    monthlyUsd = perMessageUsd * args.messagesPerMonth,
    monthlyInr = monthlyUsd * args.usdInr;
  process.stdout.write(
    JSON.stringify(
      {
        pricingVersion:
          process.env.AI_PRICING_VERSION ||
          "development-conservative-estimate-v1",
        pricingValidated: process.env.AI_PRICING_CONFIRMED === "true",
        assumptions: { ...args, expansion },
        perMessageUsd: { stt, translation, tts, total: perMessageUsd },
        monthlyUsd,
        monthlyInr,
        variableCostRevenueRatio: monthlyInr / args.monthlyRevenueInr,
        excludes: [
          "storage",
          "bandwidth",
          "notifications",
          "OTP",
          "payment fees",
          "taxes",
          "fixed infrastructure",
        ],
        note: "Estimate only. Use actual provider invoices and pilot observations to validate pricing and 10–20% cost target.",
      },
      null,
      2,
    ) + "\n",
  );
}
