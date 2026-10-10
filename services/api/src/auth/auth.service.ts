import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
  ServiceUnavailableException,
  HttpException,
  BadRequestException,
} from "@nestjs/common";
import { createHmac, randomUUID } from "node:crypto";
import { Store } from "../common/store";
import { equal, hash, secret } from "../common/crypto";
import { DevAuthDto, OtpVerifyDto, PhoneLoginVerifyDto, DeviceSessionDto } from "../common/validation";
import { publicUser } from "../common/profile";
import { State, User } from "../common/types";
export const now = () => new Date().toISOString();
export const dateAfter = (seconds: number) =>
  new Date(Date.now() + seconds * 1000).toISOString();
@Injectable()
export class AuthService {
  constructor(private readonly store: Store) {}
  async deviceSession(input: DeviceSessionDto) {
    const fingerprint = hash(input.deviceSecret);
    return this.store.transaction((s) => {
      let user = s.users.find((v) => v.deviceHash === fingerprint);
      if (!user) {
        user = { id: randomUUID(), deviceHash: fingerprint, displayName: input.displayName?.trim() || "Team member", spokenLanguage: input.language, listeningLanguage: input.language, isAdmin: false, createdAt: now(), receivingMode: "automatic", providerConsent: false };
        s.users.push(user);
        s.subscriptions.push({ id: randomUUID(), userId: user.id, planId: "silver", state: "active", expiresAt: "9999-12-31T23:59:59.000Z" });
      }
      // A device has one live anonymous session. Re-entry retains its teams.
      for (const session of s.sessions.filter((v) => v.userId === user!.id && !v.revokedAt)) session.revokedAt = now();
      return { ...this.issue(s, user.id), user: publicUser(user), mode: "device" };
    });
  }
  async bindDevice(userId: string, input: DeviceSessionDto) {
    return this.store.transaction((s) => {
      const fingerprint = hash(input.deviceSecret);
      if (s.users.some((v) => v.deviceHash === fingerprint && v.id !== userId)) throw new BadRequestException("This device already belongs to another profile.");
      const user = s.users.find((v) => v.id === userId);
      if (!user) throw new UnauthorizedException();
      user.deviceHash = fingerprint;
      return { status: "linked" };
    });
  }
  private phoneFingerprint(phone: string) {
    return createHmac("sha256", process.env.DATA_ENCRYPTION_KEY || "development-phone-fingerprint").update(phone).digest("hex");
  }
  async requestPhoneLogin(phone: string) {
    if (this.devEnabled()) {
      return { status: "development-code", mode: "development-phone", developmentCode: process.env.DEV_LOGIN_CODE || "123456", phoneVerified: false };
    }
    return this.requestOtp(phone);
  }
  async verifyPhoneLogin(input: PhoneLoginVerifyDto) {
    if (!this.devEnabled()) {
      return this.verifyOtp({ ...input, displayName: input.displayName || "Team member" });
    }
    if (!equal(input.code, process.env.DEV_LOGIN_CODE || "123456")) {
      throw new UnauthorizedException({ code: "OTP_INVALID", message: "The development login code is incorrect." });
    }
    return this.store.transaction((s) => {
      const phoneHash = this.phoneFingerprint(input.phone);
      let user = s.users.find((v) => v.phoneHash === phoneHash);
      if (!user) {
        if (!input.displayName?.trim()) throw new BadRequestException("Enter your name to create your account.");
        user = { id: randomUUID(), displayName: input.displayName.trim(), spokenLanguage: input.language, listeningLanguage: input.language, isAdmin: false, createdAt: now(), receivingMode: "notification", providerConsent: false, phoneHash, phoneLast4: input.phone.slice(-4), phoneVerified: false };
        s.users.push(user);
        s.subscriptions.push({ id: randomUUID(), userId: user.id, planId: "trial", state: "trial", expiresAt: dateAfter(14 * 86400) });
      }
      return { ...this.issue(s, user.id), user: publicUser(user), mode: "development-phone" };
    });
  }
  async linkPhone(userId: string, input: PhoneLoginVerifyDto) {
    const dev = this.devEnabled();
    if (dev) {
      if (!equal(input.code, process.env.DEV_LOGIN_CODE || "123456")) throw new UnauthorizedException("The development login code is incorrect.");
    } else {
      const result = await this.twilio("VerificationCheck", { To: input.phone, Code: input.code });
      if (result.status !== "approved" || result.to !== input.phone) throw new UnauthorizedException("Verification code is invalid or expired.");
    }
    return this.store.transaction((s) => {
      const fingerprint = this.phoneFingerprint(input.phone);
      if (s.users.some((v) => v.phoneHash === fingerprint && v.id !== userId)) throw new BadRequestException("This phone already has an account. Sign into that account instead.");
      const user = s.users.find((v) => v.id === userId);
      if (!user) throw new UnauthorizedException();
      user.phoneHash = fingerprint; user.phoneLast4 = input.phone.slice(-4); user.phoneVerified = !dev;
      return publicUser(user);
    });
  }
  otpEnabled() {
    return !!(
      process.env.TWILIO_ACCOUNT_SID &&
      process.env.TWILIO_AUTH_TOKEN &&
      process.env.TWILIO_VERIFY_SERVICE_SID
    );
  }
  private async twilio(operation: string, fields: Record<string, string>) {
    if (!this.otpEnabled())
      throw new ServiceUnavailableException({
        code: "OTP_UNCONFIGURED",
        message: "Verified phone authentication is not configured.",
      });
    try {
      const result = await fetch(
        `https://verify.twilio.com/v2/Services/${process.env.TWILIO_VERIFY_SERVICE_SID}/${operation}`,
        {
          method: "POST",
          headers: {
            Authorization:
              "Basic " +
              Buffer.from(
                `${process.env.TWILIO_ACCOUNT_SID}:${process.env.TWILIO_AUTH_TOKEN}`,
              ).toString("base64"),
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: new URLSearchParams(fields),
          signal: AbortSignal.timeout(10000),
          redirect: "error",
        },
      );
      if (!result.ok)
        throw new ServiceUnavailableException({
          code: "OTP_PROVIDER_ERROR",
          message:
            "Phone verification provider could not process this request.",
        });
      return (await result.json()) as any;
    } catch (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException({
        code: "OTP_PROVIDER_UNAVAILABLE",
        message: "Phone verification is temporarily unavailable.",
      });
    }
  }
  async requestOtp(phone: string) {
    if (!this.otpEnabled())
      throw new ServiceUnavailableException({
        code: "OTP_UNCONFIGURED",
        message: "Verified phone authentication is not configured.",
      });
    const fingerprint = createHmac(
      "sha256",
      process.env.DATA_ENCRYPTION_KEY || "development-phone-fingerprint",
    )
      .update(phone)
      .digest("hex");
    await this.store.transaction((s) => {
      const recent = s.audit.filter(
        (v) =>
          v.action === "auth.otp_requested" && v.createdAt > dateAfter(-900),
      );
      const daily = s.audit.filter(
        (v) =>
          v.action === "auth.otp_requested" &&
          v.createdAt >= new Date().toISOString().slice(0, 10),
      );
      if (
        recent.filter((v) => v.actorId === fingerprint).length >= 3 ||
        daily.length >=
          Number(process.env.GLOBAL_DAILY_OTP_REQUEST_LIMIT || 200)
      )
        throw new HttpException(
          {
            code: "OTP_RATE_LIMITED",
            message: "Phone verification request limit reached.",
          },
          429,
        );
      s.audit.push({
        id: randomUUID(),
        actorId: fingerprint,
        action: "auth.otp_requested",
        entityId: randomUUID(),
        createdAt: now(),
      });
    });
    await this.twilio("Verifications", { To: phone, Channel: "sms" });
    return { status: "sent", mode: "verified-provider" };
  }
  async verifyOtp(input: OtpVerifyDto) {
    const result = await this.twilio("VerificationCheck", {
      To: input.phone,
      Code: input.code,
    });
    if (result.status !== "approved" || result.to !== input.phone)
      throw new UnauthorizedException({
        code: "OTP_INVALID",
        message: "Verification code is invalid or expired.",
      });
    return this.store.transaction((s) => {
      const phoneHash = createHmac(
        "sha256",
        process.env.DATA_ENCRYPTION_KEY || "development-phone-fingerprint",
      )
        .update(input.phone)
        .digest("hex");
      let user = s.users.find((v) => (v as any).phoneHash === phoneHash);
      if (!user) {
        user = {
          id: randomUUID(),
          displayName: input.displayName.trim(),
          spokenLanguage: input.language,
          listeningLanguage: input.language,
          isAdmin: false,
          createdAt: now(),
          receivingMode: "notification",
          providerConsent: false,
        };
        (user as any).phoneHash = phoneHash;
        s.users.push(user);
        s.subscriptions.push({
          id: randomUUID(),
          userId: user.id,
          planId: "trial",
          state: "trial",
          expiresAt: dateAfter(14 * 86400),
        });
      }
      user.phoneLast4 = input.phone.slice(-4);
      user.phoneVerified = true;
      return {
        ...this.issue(s, user.id),
        user: publicUser(user),
        mode: "verified-phone",
      };
    });
  }
  devEnabled() {
    return (
      process.env.NODE_ENV !== "production" &&
      process.env.ENABLE_DEV_AUTH === "true"
    );
  }
  async dev(input: DevAuthDto) {
    if (!this.devEnabled())
      throw new ForbiddenException({
        code: "DEV_AUTH_DISABLED",
        message:
          "Development authentication is disabled. Configure verified authentication for production.",
      });
    return this.store.transaction((s) => {
      const user: User = {
        id: randomUUID(),
        displayName: input.displayName.trim(),
        spokenLanguage: input.language,
        listeningLanguage: input.language,
        isAdmin:
          !!process.env.DEV_ADMIN_KEY &&
          !!input.adminKey &&
          equal(input.adminKey, process.env.DEV_ADMIN_KEY),
        createdAt: now(),
        receivingMode: "notification",
        providerConsent: false,
      };
      s.users.push(user);
      s.subscriptions.push({
        id: randomUUID(),
        userId: user.id,
        planId: "trial",
        state: "trial",
        expiresAt: dateAfter(14 * 86400),
      });
      const tokens = this.issue(s, user.id);
      return { ...tokens, user: publicUser(user), mode: "development-simulator" };
    });
  }
  private issue(s: State, userId: string) {
    const accessToken = secret(),
      refreshToken = secret();
    const session = {
      id: randomUUID(),
      userId,
      accessHash: hash(accessToken),
      refreshHash: hash(refreshToken),
      accessExpiresAt: dateAfter(900),
      expiresAt: dateAfter(30 * 86400),
      createdAt: now(),
    };
    s.sessions.push(session);
    return { accessToken, refreshToken, expiresIn: 900 };
  }
  async authenticate(
    token?: string,
  ): Promise<{ user: User; sessionId: string }> {
    if (!token) throw new UnauthorizedException();
    return this.store.read((s) => {
      const session = s.sessions.find((v) => equal(v.accessHash, hash(token)));
      const user = session && s.users.find((v) => v.id === session.userId);
      if (
        !session ||
        !user ||
        session.revokedAt ||
        session.accessExpiresAt <= now() ||
        session.expiresAt <= now()
      )
        throw new UnauthorizedException();
      return { user, sessionId: session.id };
    });
  }
  async refresh(token: string) {
    const value = hash(token);
    let reused = false;
    const result = await this.store.transaction((s) => {
      const session = s.sessions.find(
        (v) =>
          v.refreshHash === value ||
          v.previousRefreshHash === value ||
          v.refreshHistory?.includes(value),
      );
      if (!session || session.expiresAt <= now() || session.revokedAt)
        return undefined;
      if (session.refreshHash !== value) {
        session.revokedAt = now();
        reused = true;
        return undefined;
      }
      const accessToken = secret(),
        refreshToken = secret();
      session.refreshHistory = [
        ...(session.refreshHistory || []),
        session.refreshHash,
      ];
      session.previousRefreshHash = session.refreshHash;
      session.refreshHash = hash(refreshToken);
      session.accessHash = hash(accessToken);
      session.accessExpiresAt = dateAfter(900);
      return {
        accessToken,
        refreshToken,
        expiresIn: 900,
        user: (() => {
          return publicUser(s.users.find((v) => v.id === session.userId)!);
        })(),
      };
    });
    if (!result)
      throw new UnauthorizedException({
        code: reused ? "REFRESH_REUSE" : "SESSION_INVALID",
        message: "Session expired or revoked.",
      });
    return result;
  }
  async logout(sessionId: string) {
    await this.store.transaction((s) => {
      const session = s.sessions.find((v) => v.id === sessionId);
      if (session) session.revokedAt = now();
    });
    return { status: "revoked" };
  }
}
