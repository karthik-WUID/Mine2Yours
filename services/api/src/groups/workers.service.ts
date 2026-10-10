import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Store } from "../common/store";
import { State, WorkerRecord } from "../common/types";
import { WorkerDto, WorkerDocumentDto, WorkerLogDto, WorkerPaymentDto } from "../common/validation";
import { privileged, membership } from "./groups.service";
import { imageBytes, PersonnelMediaService } from "./personnel-media.service";
import { now } from "../auth/auth.service";

function date(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value)
    throw new BadRequestException("Choose a valid date.");
}
function group(s: State, actor: string, id: string) {
  privileged(s, id, actor, true);
  const result = s.groups.find((v) => v.id === id);
  if (!result) throw new NotFoundException();
  result.workers ||= [];
  return result;
}
function worker(s: State, actor: string, team: string, id: string) {
  const result = group(s, actor, team).workers!.find((v) => v.id === id);
  if (!result) throw new NotFoundException();
  return result;
}
function audit(s: State, actor: string, id: string, action: string) {
  s.audit.push({ id: randomUUID(), actorId: actor, entityId: id, action, createdAt: now() });
}
@Injectable()
export class WorkersService {
  constructor(private readonly store: Store, private readonly media: PersonnelMediaService) {}
  list(actor: string, team: string) { return this.store.read((s) => group(s, actor, team).workers!); }
  detail(actor: string, team: string, id: string) { return this.store.read((s) => worker(s, actor, team, id)); }
  save(actor: string, team: string, input: WorkerDto, id?: string) {
    if (!input.consent) throw new BadRequestException("Record the worker's permission before saving their personal details.");
    date(input.joinedDate);
    if (!input.displayName.trim()) throw new BadRequestException("Enter the member's name.");
    if (input.photoData) {
      const match = /^data:(image\/(?:jpeg|png));base64,([A-Za-z0-9+/]+={0,2})$/.exec(input.photoData);
      if (!match) throw new BadRequestException("Choose a JPEG or PNG photo.");
      imageBytes(match[2], match[1], 256 * 1024);
    }
    return this.store.transaction((s) => {
      const teamRecord = group(s, actor, team);
      if (input.linkedUserId) {
        membership(s, team, input.linkedUserId);
        if (teamRecord.workers!.some((v) => v.linkedUserId === input.linkedUserId && v.id !== id))
          throw new BadRequestException("This account already has a member record in this team.");
      }
      let record = id ? worker(s, actor, team, id) : undefined;
      if (!record) {
        if (teamRecord.workers!.length >= 100) throw new BadRequestException("This team has reached its 100 member-record limit.");
        record = { id: randomUUID(), createdAt: now(), consentRecordedAt: now(), payments: [], workLog: [] } as unknown as WorkerRecord;
        teamRecord.workers!.push(record);
      }
      const { consent, ...details } = input;
      Object.assign(record, details, { displayName: input.displayName.trim(), updatedAt: now() });
      record.linkedUserId = input.linkedUserId;
      audit(s, actor, record.id, id ? "personnel.updated" : "personnel.created");
      return record;
    });
  }
  async remove(actor: string, team: string, id: string) {
    const document = await this.store.transaction((s) => {
      const record = worker(s, actor, team, id);
      group(s, actor, team).workers = group(s, actor, team).workers!.filter((v) => v.id !== id);
      audit(s, actor, id, "personnel.deleted");
      return record.identityDocumentId;
    });
    if (document) await this.media.delete(document);
    return { status: "deleted" };
  }
  async document(actor: string, team: string, id: string, input: WorkerDocumentDto) {
    if (!input.consent) throw new BadRequestException("Record permission to store this identity document.");
    await this.detail(actor, team, id);
    const asset = await this.media.put(input.base64, input.mimeType);
    let old: string | undefined;
    try {
      await this.store.transaction((s) => {
        const record = worker(s, actor, team, id);
        old = record.identityDocumentId;
        record.identityDocumentId = asset;
        record.identityDocumentMime = input.mimeType;
        record.updatedAt = now();
        audit(s, actor, id, "personnel.document_uploaded");
      });
    } catch (e) { await this.media.delete(asset); throw e; }
    if (old) await this.media.delete(old);
    return { uploaded: true, verification: "manual-review-only" };
  }
  async readDocument(actor: string, team: string, id: string) {
    const record = await this.detail(actor, team, id);
    if (!record.identityDocumentId) throw new NotFoundException("No document uploaded.");
    const data = await this.media.get(record.identityDocumentId);
    // Recheck authorization after storage retrieval, including role changes.
    const current = await this.detail(actor, team, id);
    if (current.identityDocumentId !== record.identityDocumentId) throw new NotFoundException();
    return data;
  }
  async removeDocument(actor: string, team: string, id: string) {
    const document = await this.store.transaction((s) => {
      const record = worker(s, actor, team, id), old = record.identityDocumentId;
      delete record.identityDocumentId; delete record.identityDocumentMime;
      record.updatedAt = now(); audit(s, actor, id, "personnel.document_deleted");
      return old;
    });
    if (document) await this.media.delete(document);
    return { status: "deleted" };
  }
  removeEntry(actor: string, team: string, id: string, kind: "payments" | "workLog", entry: string) {
    return this.store.transaction((s) => {
      const record = worker(s, actor, team, id);
      if (!record[kind].some((v) => v.id === entry)) throw new NotFoundException();
      if (kind === "payments") record.payments = record.payments.filter((v) => v.id !== entry);
      else record.workLog = record.workLog.filter((v) => v.id !== entry);
      record.updatedAt = now(); audit(s, actor, id, `personnel.${kind}_entry_deleted`); return record;
    });
  }
  payment(actor: string, team: string, id: string, input: WorkerPaymentDto) {
    date(input.date);
    return this.store.transaction((s) => {
      const record = worker(s, actor, team, id);
      if (record.payments.length >= 500) throw new BadRequestException("Payment record limit reached.");
      record.payments.push({ id: randomUUID(), ...input }); record.updatedAt = now();
      audit(s, actor, id, "personnel.payment_added"); return record;
    });
  }
  work(actor: string, team: string, id: string, input: WorkerLogDto) {
    date(input.date);
    return this.store.transaction((s) => {
      const record = worker(s, actor, team, id);
      if (record.workLog.length >= 500) throw new BadRequestException("Work record limit reached.");
      record.workLog.push({ id: randomUUID(), ...input }); record.updatedAt = now();
      audit(s, actor, id, "personnel.work_added"); return record;
    });
  }
}
