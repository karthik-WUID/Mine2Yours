import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AuthGuard } from "../auth/auth.guard";
import { AckDto, MessageDto } from "../common/validation";
import { MessagingService } from "./messaging.service";
@ApiTags("Messages")
@ApiBearerAuth()
@UseGuards(AuthGuard)
@Controller("messages")
export class MessagingController {
  constructor(private readonly messages: MessagingService) {}
  @Post() create(@Req() req: any, @Body() input: MessageDto) {
    return this.messages.create(req.user.id, input);
  }
  @Get() list(@Req() req: any, @Query("groupId") groupId?: string) {
    return this.messages.list(req.user.id, groupId);
  }
  @Get(":id") get(@Req() req: any, @Param("id") id: string) {
    return this.messages.get(req.user.id, id);
  }
  @Post(":id/ack") ack(
    @Req() req: any,
    @Param("id") id: string,
    @Body() input: AckDto,
  ) {
    return this.messages.ack(req.user.id, id, input.state);
  }
  @Post(":id/confirm") confirm(@Req() req: any, @Param("id") id: string) {
    return this.messages.confirm(req.user.id, id);
  }
  @Post(":id/retry") retry(@Req() req: any, @Param("id") id: string) {
    return this.messages.retry(req.user.id, id);
  }
  @Post(":id/cancel") cancel(@Req() req: any, @Param("id") id: string) {
    return this.messages.cancel(req.user.id, id);
  }
}
