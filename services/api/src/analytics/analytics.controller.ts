import {
  Controller,
  ForbiddenException,
  Get,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { Store } from "../common/store";
import { AuthGuard } from "../auth/auth.guard";
import { HttpAiProviders } from "../ai/providers";
import { monthStart, costs } from "./usage.service";
@ApiTags("Administration")
@ApiBearerAuth()
@UseGuards(AuthGuard)
@Controller("admin")
export class AnalyticsController {
  constructor(
    private readonly store: Store,
    private readonly ai: HttpAiProviders,
  ) {}
  @Get("overview") overview(@Req() req: any) {
    if (!req.user.isAdmin) throw new ForbiddenException();
    return this.store.read((s) => {
      const day = new Date().toISOString().slice(0, 10);
      const events = s.usage.filter((v) => v.createdAt >= monthStart());
      return {
        users: s.users.length,
        groups: s.groups.length,
        messages: s.messages.length,
        activeUsers: new Set(
          s.messages
            .filter((v) => v.createdAt.startsWith(day))
            .map((v) => v.senderId),
        ).size,
        activeGroups: new Set(
          s.messages
            .filter((v) => v.createdAt.startsWith(day))
            .map((v) => v.groupId),
        ).size,
        failedMessages: s.messages.filter((v) => v.state === "FAILED").length,
        estimatedAiCostUsd: Math.max(0, costs(events)),
        usage: {
          audioSeconds: events
            .filter((v) => v.kind === "stt")
            .reduce((a, b) => a + b.amount, 0),
          translationCharacters: events
            .filter((v) => v.kind === "translation")
            .reduce((a, b) => a + b.amount, 0),
          ttsCharacters: events
            .filter((v) => v.kind === "tts")
            .reduce((a, b) => a + b.amount, 0),
          cacheHits: events.filter((v) => v.kind === "cache").length,
        },
        subscriptions: {
          trial: s.subscriptions.filter((v) => v.state === "trial").length,
          active: s.subscriptions.filter((v) => v.state === "active").length,
          pastDue: s.subscriptions.filter((v) => v.state === "past_due").length,
        },
        providerHealth: this.ai.health(),
        revenueInr: null,
        revenueNote:
          "Revenue is unavailable until verified payment reconciliation is configured.",
        scope: "aggregates-only",
      };
    });
  }
}
