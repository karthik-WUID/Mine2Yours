import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AuthGuard } from "../auth/auth.guard";
import { AudioService } from "./audio.service";
import { MessagingService } from "../messaging/messaging.service";
import { TranscribeDto } from "../common/validation";
@ApiTags("Audio")
@ApiBearerAuth()
@UseGuards(AuthGuard)
@Controller("audio")
export class AudioController {
  constructor(
    private readonly audio: AudioService,
    private readonly messages: MessagingService,
  ) {}
  @Post("transcribe") transcribe(
    @Req() req: any,
    @Body() input: TranscribeDto,
  ) {
    return this.messages.transcribe(req.user.id, input);
  }
  @Get(":id") async get(
    @Req() req: any,
    @Param("id") id: string,
    @Query("expires") expires: string,
    @Query("signature") signature: string,
    @Res() res: any,
  ) {
    const data = await this.audio.get(id, req.user.id, expires, signature);
    res.setHeader("Content-Type", data.mimeType);
    res.setHeader("Cache-Control", "private, no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.send(data.bytes);
  }
}
