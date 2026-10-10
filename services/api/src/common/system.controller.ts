import { Controller, Get } from "@nestjs/common";
import { AuthService } from "../auth/auth.service";
import { Store } from "./store";
import { HttpAiProviders } from "../ai/providers";
import { BillingService } from "../billing/billing.service";
import { pricing } from "../analytics/usage.service";
import { languages } from "./types";
@Controller()
export class SystemController {
  constructor(
    private readonly auth: AuthService,
    private readonly store: Store,
    private readonly ai: HttpAiProviders,
    private readonly billing: BillingService,
  ) {}
  @Get("health") async health() {
    await this.store.init();
    return {
      status: "ok",
      service: "mine2yourlingo-api",
      storage: this.store.mode,
    };
  }
  @Get("capabilities") capabilities() {
    return {
      developmentAuth: this.auth.devEnabled(),
      devAuth: this.auth.devEnabled(),
      auth: {
        developmentSimulator: this.auth.devEnabled(),
        phoneOtp: this.auth.otpEnabled(),
        phoneLogin: this.auth.devEnabled() || this.auth.otpEnabled(),
        email: false,
      },
      ai: this.ai.capabilities(),
      aiConfigured: this.ai.capabilities(),
      pricingValidated:
        process.env.AI_PRICING_CONFIRMED === "true" &&
        !!process.env.AI_PRICING_VERSION &&
        [
          "STT_USD_PER_SECOND",
          "TRANSLATION_USD_PER_CHARACTER",
          "TTS_USD_PER_CHARACTER",
        ].every((key) => Number(process.env[key]) > 0),
      billing: this.billing.capabilities(),
      storage: { mode: this.store.mode },
      realtime: { path: "/v1/realtime" },
      languages,
      pricingVersion: pricing().version,
      limitations: [
        "Configured provider support varies by language; no language quality certification.",
        "No guaranteed background or emergency delivery.",
        "Cloud translation processes readable content; this is not end-to-end encryption.",
        "Purchases require a configured server verification gateway and platform approval.",
        "Local file storage is development only; deployment Redis/S3 integrations remain unverified.",
        "Realtime events require reconnect synchronization; receiving an event does not acknowledge delivery.",
      ],
    };
  }
}
