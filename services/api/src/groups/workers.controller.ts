import { Body, Controller, Delete, Get, Param, Patch, Post, Req, Res, UseGuards } from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AuthGuard } from "../auth/auth.guard";
import { WorkerDto, WorkerDocumentDto, WorkerLogDto, WorkerPaymentDto } from "../common/validation";
import { WorkersService } from "./workers.service";
import { RealtimeService } from "../realtime/realtime.service";

@ApiTags("Private personnel records") @ApiBearerAuth() @UseGuards(AuthGuard)
@Controller("groups/:team/workers")
export class WorkersController {
  constructor(private readonly workers: WorkersService, private readonly realtime: RealtimeService) {}
  @Get() list(@Req() req: any, @Param("team") team: string) { return this.workers.list(req.user.id, team); }
  @Post() async create(@Req() req: any, @Param("team") team: string, @Body() input: WorkerDto) {
    const result = await this.workers.save(req.user.id, team, input); await this.realtime.group(team); return result;
  }
  @Get(":id") detail(@Req() req: any, @Param("team") team: string, @Param("id") id: string) { return this.workers.detail(req.user.id, team, id); }
  @Patch(":id") async update(@Req() req: any, @Param("team") team: string, @Param("id") id: string, @Body() input: WorkerDto) {
    const result = await this.workers.save(req.user.id, team, input, id); await this.realtime.group(team); return result;
  }
  @Delete(":id") async remove(@Req() req: any, @Param("team") team: string, @Param("id") id: string) {
    const result = await this.workers.remove(req.user.id, team, id); await this.realtime.group(team); return result;
  }
  @Post(":id/document") document(@Req() req: any, @Param("team") team: string, @Param("id") id: string, @Body() input: WorkerDocumentDto) { return this.workers.document(req.user.id, team, id, input); }
  @Get(":id/document") async readDocument(@Req() req: any, @Param("team") team: string, @Param("id") id: string, @Res() res: any) {
    const data = await this.workers.readDocument(req.user.id, team, id);
    res.set("Cache-Control", "no-store").set("Pragma", "no-cache").json(data);
  }
  @Delete(":id/document") deleteDocument(@Req() req: any, @Param("team") team: string, @Param("id") id: string) { return this.workers.removeDocument(req.user.id, team, id); }
  @Delete(":id/payments/:entry") removePayment(@Req() req: any, @Param("team") team: string, @Param("id") id: string, @Param("entry") entry: string) { return this.workers.removeEntry(req.user.id, team, id, "payments", entry); }
  @Delete(":id/work/:entry") removeWork(@Req() req: any, @Param("team") team: string, @Param("id") id: string, @Param("entry") entry: string) { return this.workers.removeEntry(req.user.id, team, id, "workLog", entry); }
  @Post(":id/payments") payment(@Req() req: any, @Param("team") team: string, @Param("id") id: string, @Body() input: WorkerPaymentDto) { return this.workers.payment(req.user.id, team, id, input); }
  @Post(":id/work") work(@Req() req: any, @Param("team") team: string, @Param("id") id: string, @Body() input: WorkerLogDto) { return this.workers.work(req.user.id, team, id, input); }
}
