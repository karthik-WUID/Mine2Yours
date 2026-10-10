import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Store } from "../common/store";
import { AudioService } from "../audio/audio.service";
import { now } from "../auth/auth.service";
import { publicUser } from "../common/profile";
import { PersonnelMediaService } from "../groups/personnel-media.service";
@Injectable()
export class PrivacyService {
  constructor(
    private readonly store: Store,
    private readonly audio: AudioService,
    private readonly personnel?: PersonnelMediaService,
  ) {}
  export(userId: string) {
    return this.store.read((s) => ({
      exportedAt: now(),
      profile: publicUser(s.users.find((v) => v.id === userId)!),
      ownEmploymentRecords: s.groups.flatMap((g) => (g.workers || []).filter((w) => w.linkedUserId === userId).map((w) => ({ ...w, teamId: g.id }))),
      memberships: s.members.filter((v) => v.userId === userId),
      ownMessages: s.messages
        .filter((v) => v.senderId === userId)
        .map((m) => ({
          ...m,
          translations: s.translations.filter((v) => v.messageId === m.id),
        })),
      usage: s.usage.filter((v) => v.userId === userId),
      devices: s.devices
        .filter((v) => v.userId === userId)
        .map(({ pushToken, ...v }) => v),
      subscription: s.subscriptions.find((v) => v.userId === userId),
    }));
  }
  async delete(userId: string) {
    const result = await this.store.transaction((s) => {
      const candidates = new Set(
        s.translations
          .filter((v) =>
            s.messages.some(
              (m) => m.id === v.messageId && m.senderId === userId,
            ),
          )
          .flatMap((v) => (v.audioId ? [v.audioId] : [])),
      );
      const memberGroupIds = s.members
        .filter((v) => v.userId === userId)
        .map((v) => v.groupId);
      const removedGroups: string[] = [];
      for (const group of s.groups.filter((v) => v.createdBy === userId)) {
        const next = s.members
          .filter((v) => v.groupId === group.id && v.userId !== userId)
          .sort(
            (a, b) =>
              (a.role === "admin" ? -1 : 1) - (b.role === "admin" ? -1 : 1),
          )[0];
        if (next) {
          next.role = "admin";
          group.createdBy = next.userId;
        } else removedGroups.push(group.id);
      }
      const ids = s.messages
        .filter(
          (v) => v.senderId === userId || removedGroups.includes(v.groupId),
        )
        .map((v) => v.id);
      s.messages = s.messages.filter((v) => !ids.includes(v.id));
      for (const t of s.translations.filter((v) => ids.includes(v.messageId)))
        if (t.audioId) candidates.add(t.audioId);
      s.translations = s.translations.filter((v) => !ids.includes(v.messageId));
      s.recipients = s.recipients.filter(
        (v) => !ids.includes(v.messageId) && v.userId !== userId,
      );
      for (const c of s.cache.filter((v) => memberGroupIds.includes(v.groupId)))
        if (c.audioId) candidates.add(c.audioId);
      s.cache = s.cache.filter((v) => !memberGroupIds.includes(v.groupId));
      const personnelDocuments: string[] = [];
      for (const g of s.groups) {
        for (const w of g.workers || [])
          if ((w.linkedUserId === userId || removedGroups.includes(g.id)) && w.identityDocumentId) personnelDocuments.push(w.identityDocumentId);
        g.workers = (g.workers || []).filter((w) => w.linkedUserId !== userId);
      }
      s.groups = s.groups.filter((v) => !removedGroups.includes(v.id));
      s.members = s.members.filter(
        (v) => v.userId !== userId && !removedGroups.includes(v.groupId),
      );
      s.invitations = s.invitations.filter(
        (v) => v.createdBy !== userId && !removedGroups.includes(v.groupId),
      );
      s.users = s.users.filter((v) => v.id !== userId);
      s.sessions = s.sessions.filter((v) => v.userId !== userId);
      s.devices = s.devices.filter((v) => v.userId !== userId);
      s.subscriptions = s.subscriptions.filter((v) => v.userId !== userId);
      const pseudonym = randomUUID();
      for (const u of s.usage) {
        if (u.userId === userId) u.userId = pseudonym;
        if (u.messageId && ids.includes(u.messageId)) u.messageId = undefined;
      }
      for (const a of s.audit) if (a.actorId === userId) a.actorId = pseudonym;
      s.audit.push({
        id: randomUUID(),
        actorId: pseudonym,
        action: "privacy.account_deleted",
        entityId: pseudonym,
        createdAt: now(),
      });
      const retained = new Set(
        [...s.translations, ...s.cache].flatMap((v) =>
          v.audioId ? [v.audioId] : [],
        ),
      );
      return { deleteAudio: [...candidates].filter((id) => !retained.has(id)), personnelDocuments };
    });
    for (const id of result.deleteAudio) await this.audio.delete(id);
    for (const id of result.personnelDocuments) await this.personnel?.delete(id);
    return {
      status: "deleted",
      retentionNote:
        "Eligible profile, sessions, authored messages and unshared audio removed; pseudonymized financial usage and security audits retained. Independent backup retention requires the deployment deletion process.",
    };
  }
  async retain() {
    const removal = await this.store.transaction((s) => {
      const ids = s.messages
        .filter((v) => v.expiresAt <= now())
        .map((v) => v.id);
      const candidates = new Set(
        s.translations
          .filter((v) => ids.includes(v.messageId))
          .flatMap((v) => (v.audioId ? [v.audioId] : [])),
      );
      s.messages = s.messages.filter((v) => !ids.includes(v.id));
      s.recipients = s.recipients.filter((v) => !ids.includes(v.messageId));
      s.translations = s.translations.filter((v) => !ids.includes(v.messageId));
      for (const usage of s.usage)
        if (usage.messageId && ids.includes(usage.messageId))
          usage.messageId = undefined;
      for (const c of s.cache.filter((v) => v.expiresAt <= now()))
        if (c.audioId) candidates.add(c.audioId);
      s.cache = s.cache.filter((v) => v.expiresAt > now());
      s.invitations = s.invitations.filter((v) => v.expiresAt > now());
      const retained = new Set(
        [...s.translations, ...s.cache].flatMap((v) =>
          v.audioId ? [v.audioId] : [],
        ),
      );
      return {
        remove: [...candidates].filter((id) => !retained.has(id)),
        retained,
      };
    });
    for (const id of removal.remove) await this.audio.delete(id);
    await this.audio.sweep(removal.retained);
    if (this.personnel) {
      const retained = await this.store.read((s) => new Set(s.groups.flatMap((g) => (g.workers || []).flatMap((w) => w.identityDocumentId ? [w.identityDocumentId] : []))));
      await this.personnel.sweep(retained);
    }
  }
}
