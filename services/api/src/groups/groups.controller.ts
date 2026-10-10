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
} from "@nestjs/common";
import { ApiBearerAuth, ApiTags } from "@nestjs/swagger";
import { AuthGuard } from "../auth/auth.guard";
import {
  GroupDto,
  InvitationDto,
  JoinDto,
  MemberRoleDto,
  UpdateGroupDto,
} from "../common/validation";
import { RealtimeService } from "../realtime/realtime.service";
import { GroupsService } from "./groups.service";
@ApiTags("Groups")
@ApiBearerAuth()
@UseGuards(AuthGuard)
@Controller("groups")
export class GroupsController {
  constructor(
    private readonly groups: GroupsService,
    private readonly realtime: RealtimeService,
  ) {}
  @Get() list(@Req() req: any) {
    return this.groups.list(req.user.id);
  }
  @Post() async create(@Req() req: any, @Body() input: GroupDto) {
    const group = await this.groups.create(req.user.id, input);
    await this.realtime.group(group.id);
    return group;
  }
  @Post("join") async join(@Req() req: any, @Body() input: JoinDto) {
    const result = await this.groups.join(req.user.id, input.token);
    await this.realtime.group(result.groupId);
    return result;
  }
  @Get(":id") detail(@Req() req: any, @Param("id") id: string) {
    return this.groups.detail(req.user.id, id);
  }
  @Patch(":id") async update(
    @Req() req: any,
    @Param("id") id: string,
    @Body() input: UpdateGroupDto,
  ) {
    const result = await this.groups.update(req.user.id, id, input);
    await this.realtime.group(id);
    return result;
  }
  @Delete(":id") async delete(@Req() req: any, @Param("id") id: string) {
    const before = await this.groups.detail(req.user.id, id);
    const result = await this.groups.delete(req.user.id, id);
    await this.realtime.group(
      id,
      before.members.map((v) => v.userId),
    );
    return result;
  }
  @Post(":id/invitations") invite(
    @Req() req: any,
    @Param("id") id: string,
    @Body() input: InvitationDto,
  ) {
    return this.groups.invite(req.user.id, id, input.expiresInHours);
  }
  @Post(":id/leave") async leave(@Req() req: any, @Param("id") id: string) {
    const result = await this.groups.remove(req.user.id, id, req.user.id);
    await this.realtime.group(id, [req.user.id]);
    return result;
  }
  @Delete(":id/members/:userId") async remove(
    @Req() req: any,
    @Param("id") id: string,
    @Param("userId") userId: string,
  ) {
    const result = await this.groups.remove(req.user.id, id, userId);
    await this.realtime.group(id, [userId]);
    return result;
  }
  @Patch(":id/members/:userId") async role(
    @Req() req: any,
    @Param("id") id: string,
    @Param("userId") userId: string,
    @Body() input: MemberRoleDto,
  ) {
    const result = await this.groups.role(req.user.id, id, userId, input.role);
    await this.realtime.group(id);
    return result;
  }
}
