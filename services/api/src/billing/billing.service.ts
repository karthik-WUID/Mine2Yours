import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  ServiceUnavailableException,
} from "@nestjs/common";
import { createHmac, randomUUID } from "node:crypto";
import { Store } from "../common/store";
import { equal } from "../common/crypto";
import { PurchaseDto } from "../common/validation";
import { now } from "../auth/auth.service";
import { plans } from "../common/types";
@Injectable()
export class BillingService {
  constructor(private readonly store: Store) {}
  capabilities() {
    return {
      configured: !!(
        process.env.BILLING_VERIFICATION_URL &&
        process.env.BILLING_VERIFICATION_KEY &&
        process.env.BILLING_PROVIDERS
      ),
      purchasesEnabled: !!(
        process.env.BILLING_VERIFICATION_URL &&
        process.env.BILLING_VERIFICATION_KEY &&
        process.env.BILLING_PROVIDERS
      ),
      providers: process.env.BILLING_PROVIDERS?.split(",") || [],
      requiresServerVerification: true,
    };
  }
  private validate(data: any) {
    const aliases: Record<string, string> = { basic: "gold", pro: "diamond" };
    if (
      !plans.some((v) => v.id === (aliases[data.planId] || data.planId) && v.id !== "silver") ||
      !["active", "past_due", "cancelled"].includes(data.status) ||
      !Number.isFinite(Date.parse(data.currentPeriodEnd)) ||
      typeof data.customerId !== "string" ||
      !data.customerId
    )
      throw new BadRequestException({
        code: "BILLING_RESPONSE_INVALID",
        message: "Verified billing data is invalid.",
      });
  }
  async verify(userId: string, input: PurchaseDto) {
    if (
      !process.env.BILLING_VERIFICATION_URL ||
      !process.env.BILLING_VERIFICATION_KEY
    )
      throw new ServiceUnavailableException({
        code: "BILLING_UNCONFIGURED",
        message:
          "Purchasing is unavailable until a verified billing provider is configured.",
      });
    if (!process.env.BILLING_PROVIDERS?.split(",").includes(input.provider))
      throw new BadRequestException("Billing provider is not enabled");
    const url = new URL(process.env.BILLING_VERIFICATION_URL);
    if (url.protocol !== "https:" && process.env.NODE_ENV === "production")
      throw new ServiceUnavailableException(
        "Billing verification endpoint requires HTTPS",
      );
    let response: Response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${process.env.BILLING_VERIFICATION_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          userId,
          provider: input.provider,
          receipt: input.receipt,
        }),
        signal: AbortSignal.timeout(15000),
        redirect: "error",
      });
    } catch {
      throw new ServiceUnavailableException(
        "Billing verification provider unavailable",
      );
    }
    if (!response.ok)
      throw new BadRequestException("Purchase verification rejected");
    const data: any = await response.json();
    if (data.verified !== true || data.userId !== userId)
      throw new ForbiddenException("Purchase ownership was not verified");
    this.validate(data);
    return this.store.transaction((s) => {
      const other = s.subscriptions.find(
        (v) => v.billingCustomerId === data.customerId && v.userId !== userId,
      );
      if (other)
        throw new ForbiddenException("Billing account is already linked");
      let subscription = s.subscriptions.find((v) => v.userId === userId);
      if (!subscription) {
        subscription = {
          id: randomUUID(),
          userId,
          planId: data.planId,
          state: data.status,
          expiresAt: data.currentPeriodEnd,
        };
        s.subscriptions.push(subscription);
      }
      Object.assign(subscription, {
        billingCustomerId: data.customerId,
        planId: data.planId,
        state: data.status,
        expiresAt: data.currentPeriodEnd,
      });
      s.audit.push({
        id: randomUUID(),
        actorId: userId,
        action: "billing.purchase_verified",
        entityId: subscription.id,
        createdAt: now(),
      });
      return { status: "verified", subscription };
    });
  }
  async webhook(raw: Buffer, signature?: string, timestamp?: string) {
    if (!process.env.BILLING_WEBHOOK_SECRET)
      throw new ServiceUnavailableException("Billing webhook not configured");
    const seconds = Number(timestamp);
    if (
      !Number.isFinite(seconds) ||
      Math.abs(Date.now() / 1000 - seconds) > 300
    )
      throw new ForbiddenException("Webhook timestamp expired");
    const expected = createHmac("sha256", process.env.BILLING_WEBHOOK_SECRET)
      .update(`${timestamp}.`)
      .update(raw)
      .digest("hex");
    if (!equal(signature || "", expected))
      throw new ForbiddenException("Webhook signature invalid");
    let event: any;
    try {
      event = JSON.parse(raw.toString("utf8"));
    } catch {
      throw new BadRequestException();
    }
    if (typeof event.id !== "string" || event.id.length > 128)
      throw new BadRequestException();
    this.validate(event);
    return this.store.transaction((s) => {
      if (
        s.billingEvents.some(
          (v) => v.eventId === event.id && v.provider === "verified-webhook",
        )
      )
        return { status: "duplicate" };
      const subscription = s.subscriptions.find(
        (v) => v.billingCustomerId === event.customerId,
      );
      if (!subscription)
        throw new BadRequestException("Unknown verified billing customer");
      Object.assign(subscription, {
        planId: event.planId,
        state: event.status,
        expiresAt: event.currentPeriodEnd,
      });
      s.billingEvents.push({
        id: randomUUID(),
        provider: "verified-webhook",
        eventId: event.id,
        createdAt: now(),
      });
      return { status: "processed" };
    });
  }
}
