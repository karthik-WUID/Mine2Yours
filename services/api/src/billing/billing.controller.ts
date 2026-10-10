import { Body, Controller, Get, Post, Req, UseGuards } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AuthGuard } from "../auth/auth.guard";
import { PurchaseDto } from "../common/validation";
import { plans } from "../common/types";
import { UsageService } from "../analytics/usage.service";
import { BillingService } from "./billing.service";
@ApiTags("Billing")
@Controller()
export class BillingController {
  constructor(
    private readonly usage: UsageService,
    private readonly billing: BillingService,
  ) {}
  @Get("plans") plans() {
    return plans;
  }
  @Get("usage") @ApiBearerAuth() @UseGuards(AuthGuard) usageForUser(
    @Req() req: any,
  ) {
    return this.usage.get(req.user.id);
  }
  @Post("billing/purchases/verify")
  @ApiBearerAuth()
  @UseGuards(AuthGuard)
  verify(@Req() req: any, @Body() input: PurchaseDto) {
    return this.billing.verify(req.user.id, input);
  }
  @Post("billing/webhook") webhook(@Req() req: any) {
    return this.billing.webhook(
      req.rawBody,
      req.headers["x-billing-signature"],
      req.headers["x-billing-timestamp"],
    );
  }
}
