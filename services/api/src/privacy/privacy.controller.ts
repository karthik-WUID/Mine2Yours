import { Controller, Get, Req, UseGuards } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AuthGuard } from "../auth/auth.guard";
import { PrivacyService } from "./privacy.service";
@ApiTags("Privacy")
@ApiBearerAuth()
@UseGuards(AuthGuard)
@Controller("privacy")
export class PrivacyController {
  constructor(private readonly privacy: PrivacyService) {}
  @Get("export") export(@Req() req: any) {
    return this.privacy.export(req.user.id);
  }
}
