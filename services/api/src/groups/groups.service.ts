import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  Optional,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { hash, secret } from "../common/crypto";
import { Store } from "../common/store";
import { memberState, displayName } from "../common/profile";
import { Role, State, plans } from "../common/types";
import { GroupDto, UpdateGroupDto } from "../common/validation";
import { now, dateAfter } from "../auth/auth.service";
import { validatePlanLimits } from "../common/limits";
import { Group } from "../common/types";
import { PersonnelMediaService } from "./personnel-media.service";
function publicGroup(group: Group) {
  const { workers, ...visible } = group;
  return visible;
}
export function membership(s: State, groupId: string, userId: string) {
  const member = s.members.find(
    (v) => v.groupId === groupId && v.userId === userId,
  );
  if (!member)
    throw new ForbiddenException({
      code: "GROUP_ACCESS_DENIED",
      message: "You are not a member of this group.",
    });
  return member;
}
export function privileged(
  s: State,
  groupId: string,
  userId: string,
  adminOnly = false,
) {
  const member = membership(s, groupId, userId);
  if (adminOnly ? member.role !== "admin" : member.role === "member")
    throw new ForbiddenException();
  return member;
}
export function cloudAiAllowed(s: State, userId: string): boolean {
  return s.subscriptions.some((subscription) => subscription.userId === userId &&
    ["diamond", "pro"].includes(subscription.planId) && subscription.state === "active" && subscription.expiresAt > now());
}
export function requireCloudPro(s: State, userId: string) {
  if (!cloudAiAllowed(s, userId)) throw new ForbiddenException({
    code: "PRO_AI_REQUIRED", message: "Cloud AI is available only with an active Diamond subscription. Silver includes original voice messages and supported device translation.",
  });
}
export function entitlement(s: State, userId: string) {
  const subscription = s.subscriptions.find(
    (v) =>
      v.userId === userId &&
      (v.state === "trial" || v.state === "active") &&
      v.expiresAt > now(),
  );
  const aliases: Record<string, string> = { trial: "silver", basic: "gold", pro: "diamond" };
  const id = subscription ? (aliases[subscription.planId] || subscription.planId) : "silver";
  const plan = plans.find((v) => v.id === id) || plans[0];
  validatePlanLimits(plan);
  return plan;
}
@Injectable()
export class GroupsService {
  constructor(private readonly store: Store, @Optional() private readonly personnel?: PersonnelMediaService) {}
  list(userId: string) {
    return this.store.read((s) =>
      s.members
        .filter((v) => v.userId === userId)
        .flatMap((m) => {
          const group = s.groups.find((v) => v.id === m.groupId);
          return group
            ? [
                {
                  ...publicGroup(group),
                  role: m.role,
                  memberCount: s.members.filter((v) => v.groupId === group.id)
                    .length,
                },
              ]
            : [];
        }),
    );
  }
  create(userId: string, input: GroupDto) {
    return this.store.transaction((s) => {
      const plan = entitlement(s, userId);
      if (
        s.members.filter((v) => v.userId === userId && v.role === "admin")
          .length >= (plan.maxSites ?? 1)
      )
        throw new BadRequestException("Silver includes one site. Gold includes multiple sites.");
      const group = {
        id: randomUUID(),
        name: input.name.trim(),
        description: input.description || "",
        createdBy: userId,
        createdAt: now(),
      };
      s.groups.push(group);
      s.members.push({
        id: randomUUID(),
        groupId: group.id,
        userId,
        role: "admin",
        createdAt: now(),
      });
      return { ...group, role: "admin", memberCount: 1 };
    });
  }
  detail(userId: string, id: string) {
    return this.store.read((s) => {
      const viewer = membership(s, id, userId);
      const group = s.groups.find((v) => v.id === id);
      if (!group) throw new NotFoundException();
      return {
        ...publicGroup(group),
        role: viewer.role,
        memberCount: s.members.filter((v) => v.groupId === id).length,
        members: s.members
          .filter((v) => v.groupId === id)
          .map((m) => {
            const u = s.users.find((v) => v.id === m.userId)!;
            const worker = group.workers?.find((v) => v.linkedUserId === m.userId);
            return {
              ...(u ? memberState(u) : { userId: m.userId, displayName: displayName(worker?.displayName),
                spokenLanguage: "en", listeningLanguage: "en", updatedAt: m.createdAt, version: 1 }),
              role: m.role,
              joinedDate: worker?.joinedDate || m.createdAt.slice(0, 10),
              jobTitle: worker?.jobTitle || "",
              workDetails: worker?.workDetails || "",
              site: worker?.site || "",
              photoData: worker?.photoData || "",
              employmentStatus: worker?.status || "active",
            };
          }),
      };
    });
  }
  update(userId: string, id: string, input: UpdateGroupDto) {
    return this.store.transaction((s) => {
      privileged(s, id, userId, true);
      const group = s.groups.find((v) => v.id === id)!;
      if (input.name !== undefined) group.name = input.name.trim();
      if (input.description !== undefined)
        group.description = input.description;
      return publicGroup(group);
    });
  }
  invite(userId: string, groupId: string, hours = 24) {
    return this.store.transaction((s) => {
      privileged(s, groupId, userId);
      const token = secret();
      const invitation = {
        id: randomUUID(),
        groupId,
        tokenHash: hash(token),
        createdBy: userId,
        expiresAt: dateAfter(hours * 3600),
        usedBy: [],
      };
      s.invitations.push(invitation);
      return {
        token,
        expiresAt: invitation.expiresAt,
        joinUrl: `${process.env.INVITE_BASE_URL || "mine2yourlingo://join"}?token=${token}`,
      };
    });
  }
  join(userId: string, token: string) {
    return this.store.transaction((s) => {
      const inv = s.invitations.find(
        (v) => v.tokenHash === hash(token) && v.expiresAt > now(),
      );
      if (!inv)
        throw new BadRequestException({
          code: "INVITATION_INVALID",
          message: "Invitation is invalid or expired.",
        });
      const existing = s.members.find(
        (v) => v.groupId === inv.groupId && v.userId === userId,
      );
      if (!existing) {
        const group = s.groups.find((v) => v.id === inv.groupId)!;
        const plan = entitlement(s, group.createdBy);
        if (
          s.members.filter((v) => v.groupId === group.id).length >=
          plan.maxGroupMembers
        )
          throw new BadRequestException({
            code: "GROUP_LIMIT",
            message: "This group has reached its member limit.",
          });
        s.members.push({
          id: randomUUID(),
          groupId: inv.groupId,
          userId,
          role: "member",
          createdAt: now(),
        });
        inv.usedBy.push(userId);
      }
      return { groupId: inv.groupId, status: "joined" };
    });
  }
  remove(userId: string, groupId: string, target: string) {
    return this.store.transaction((s) => {
      const actor = membership(s, groupId, userId);
      const victim = membership(s, groupId, target);
      if (userId !== target) {
        if (
          actor.role === "member" ||
          (victim.role === "admin" && actor.role !== "admin")
        )
          throw new ForbiddenException();
      }
      if (
        victim.role === "admin" &&
        s.members.filter((v) => v.groupId === groupId && v.role === "admin")
          .length === 1
      )
        throw new BadRequestException(
          "Assign another admin before leaving or removing the last admin",
        );
      s.members = s.members.filter((v) => v.id !== victim.id);
      s.audit.push({
        id: randomUUID(),
        actorId: userId,
        action: "group.member_removed",
        entityId: groupId,
        createdAt: now(),
      });
      return { status: "removed" };
    });
  }
  role(userId: string, groupId: string, target: string, role: Role) {
    return this.store.transaction((s) => {
      privileged(s, groupId, userId, true);
      const member = membership(s, groupId, target);
      if (
        member.role === "admin" &&
        role !== "admin" &&
        s.members.filter((v) => v.groupId === groupId && v.role === "admin")
          .length === 1
      )
        throw new BadRequestException("Group must retain an admin");
      member.role = role;
      return { userId: target, role };
    });
  }
  async delete(userId: string, groupId: string) {
    const documents = await this.store.transaction((s) => {
      privileged(s, groupId, userId, true);
      const documents = (s.groups.find((v) => v.id === groupId)?.workers || []).map((v) => v.identityDocumentId).filter((v): v is string => !!v);
      const ids = s.messages
        .filter((v) => v.groupId === groupId)
        .map((v) => v.id);
      s.groups = s.groups.filter((v) => v.id !== groupId);
      s.members = s.members.filter((v) => v.groupId !== groupId);
      s.invitations = s.invitations.filter((v) => v.groupId !== groupId);
      s.messages = s.messages.filter((v) => v.groupId !== groupId);
      s.translations = s.translations.filter((v) => !ids.includes(v.messageId));
      s.recipients = s.recipients.filter((v) => !ids.includes(v.messageId));
      for (const event of s.usage)
        if (event.messageId && ids.includes(event.messageId))
          event.messageId = undefined;
      s.cache = s.cache.filter((v) => v.groupId !== groupId);
      s.audit.push({
        id: randomUUID(),
        actorId: userId,
        action: "group.deleted",
        entityId: groupId,
        createdAt: now(),
      });
      return documents;
    });
    if (this.personnel) await Promise.all(documents.map((id) => this.personnel!.delete(id)));
    return { status: "deleted" };
  }
}
