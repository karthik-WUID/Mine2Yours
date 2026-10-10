import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
  NotFoundException,
  BadRequestException,
  ConflictException,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { randomUUID } from "node:crypto";
import { Store } from "../common/store";
import { publicUser, displayName, normalizeUser } from "../common/profile";
import { AuthGuard } from "../auth/auth.guard";
import { now } from "../auth/auth.service";
import { DeviceDto, ProfileDto, DeleteAccountDto } from "../common/validation";
import { PrivacyService } from "../privacy/privacy.service";
import { RealtimeService } from "../realtime/realtime.service";
@ApiTags("Users")
@ApiBearerAuth()
@UseGuards(AuthGuard)
@Controller("users")
export class UsersController {
  constructor(
    private readonly store: Store,
    private readonly privacy: PrivacyService,
    private readonly realtime: RealtimeService,
  ) {}
  @Get("me") profile(@Req() req: any) {
    return publicUser(req.user);
  }
  @Patch("me") async update(@Req() req: any, @Body() input: ProfileDto) {
    const result = await this.store.transaction((s) => {
      const user = normalizeUser(s.users.find((v) => v.id === req.user.id)!);
      if (input.expectedVersion !== undefined && input.expectedVersion !== user.version)
        throw new ConflictException({ code: "PROFILE_VERSION_CONFLICT", message: "Your profile changed. Refresh and retry.", user: publicUser(user) });
      const allowed = ["displayName", "spokenLanguage", "listeningLanguage", "receivingMode", "quietHours", "providerConsent"] as const;
      let changed = false;
      // ES2022 DTO fields exist even when omitted: never assign undefined/null.
      for (const key of allowed) {
        const value = input[key];
        if (value === undefined) continue;
        if (value === null) throw new BadRequestException("Profile fields cannot be null.");
        if (key === "displayName" && displayName(value, "") === "")
          throw new BadRequestException("Enter a valid display name.");
        const next = key === "displayName" ? displayName(value) : value;
        if (user[key] !== next) { (user as any)[key] = next; changed = true; }
      }
      if (changed) { user.version = user.version! + 1; user.updatedAt = now(); }
      if (input.providerConsent !== undefined)
        s.audit.push({
          id: randomUUID(),
          actorId: user.id,
          action: input.providerConsent
            ? "privacy.provider_consent_granted"
            : "privacy.provider_consent_revoked",
          entityId: user.id,
          createdAt: now(),
        });
      return publicUser(user);
    });
    // An event lost during disconnect is recovered by the next team snapshot.
    await this.realtime.member(result.id);
    return result;
  }
  @Delete("me") delete(@Req() req: any, @Body() input: DeleteAccountDto) {
    return this.privacy.delete(req.user.id);
  }
  @Get("me/devices") devices(@Req() req: any) {
    return this.store.read((s) =>
      s.devices
        .filter((v) => v.userId === req.user.id)
        .map(({ pushToken, ...v }) => v),
    );
  }
  @Post("me/devices") addDevice(@Req() req: any, @Body() input: DeviceDto) {
    return this.store.transaction((s) => {
      const device = {
        id: randomUUID(),
        userId: req.user.id,
        ...input,
        createdAt: now(),
      };
      s.devices.push(device);
      const { pushToken, ...result } = device;
      return result;
    });
  }
  @Delete("me/devices/:id") revoke(@Req() req: any, @Param("id") id: string) {
    return this.store.transaction((s) => {
      const device = s.devices.find(
        (v) => v.id === id && v.userId === req.user.id,
      );
      if (!device) throw new NotFoundException();
      s.devices = s.devices.filter((v) => v.id !== id);
      return {
        status: "revoked",
        note: "Push registration removed. Use logout to revoke the current access session.",
      };
    });
  }
  @Get("me/sessions") sessions(@Req() req: any) {
    return this.store.read((s) =>
      s.sessions
        .filter((v) => v.userId === req.user.id)
        .map((v) => ({
          id: v.id,
          createdAt: v.createdAt,
          expiresAt: v.expiresAt,
          revokedAt: v.revokedAt,
          current: v.id === req.sessionId,
        })),
    );
  }
  @Delete("me/sessions/:id") revokeSession(
    @Req() req: any,
    @Param("id") id: string,
  ) {
    return this.store.transaction((s) => {
      const session = s.sessions.find(
        (v) => v.id === id && v.userId === req.user.id,
      );
      if (!session) throw new NotFoundException();
      session.revokedAt = now();
      return { status: "revoked" };
    });
  }
}
