import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { randomBytes } from "node:crypto";
import { Cipher } from "./crypto";
import { State, emptyState } from "./types";
import { normalizeProfiles } from "./profile";
const tables: Record<keyof State, { model: string; fields: string[] }> = {
  users: { model: "user", fields: [] },
  sessions: { model: "session", fields: ["userId"] },
  groups: { model: "group", fields: ["createdBy"] },
  members: { model: "groupMember", fields: ["groupId", "userId"] },
  invitations: { model: "groupInvitation", fields: ["groupId", "tokenHash"] },
  messages: {
    model: "message",
    fields: ["groupId", "senderId", "idempotencyKey", "createdAt"],
  },
  translations: {
    model: "messageTranslation",
    fields: ["messageId", "language"],
  },
  recipients: { model: "messageRecipient", fields: ["messageId", "userId"] },
  usage: {
    model: "usageEvent",
    fields: ["userId", "groupId", "messageId", "createdAt"],
  },
  cache: { model: "translationCache", fields: ["groupId"] },
  subscriptions: { model: "subscription", fields: ["userId"] },
  audit: { model: "auditEvent", fields: ["actorId", "action", "createdAt"] },
  devices: { model: "device", fields: ["userId"] },
  billingEvents: { model: "billingEvent", fields: ["provider", "eventId"] },
};
const order = Object.keys(tables) as (keyof State)[];
@Injectable()
export class Store implements OnModuleDestroy {
  private state: State = emptyState();
  private queue: Promise<unknown> = Promise.resolve();
  private cipher!: Cipher;
  private prisma?: PrismaClient;
  private initialized?: Promise<void>;
  readonly mode = process.env.DATABASE_URL
    ? "postgresql"
    : "isolated-development-file";
  readonly directory = resolve(process.env.DEV_DATA_DIR || ".local/api");
  async init() {
    if (!this.initialized) this.initialized = this.initialize();
    return this.initialized;
  }
  private async initialize() {
    if (process.env.NODE_ENV === "production" && !process.env.DATABASE_URL)
      throw new Error("Production requires PostgreSQL DATABASE_URL");
    let key = process.env.DATA_ENCRYPTION_KEY;
    if (!key) {
      if (process.env.NODE_ENV === "production")
        throw new Error("Production requires DATA_ENCRYPTION_KEY");
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      try {
        key = await readFile(
          resolve(this.directory, "development.key"),
          "utf8",
        );
      } catch (e: any) {
        if (e.code !== "ENOENT") throw e;
        key = randomBytes(32).toString("base64");
        await writeFile(resolve(this.directory, "development.key"), key, {
          mode: 0o600,
          flag: "wx",
        });
      }
    }
    this.cipher = new Cipher(Buffer.from(key.trim(), "base64"));
    if (process.env.DATABASE_URL) {
      this.prisma = new PrismaClient();
      await this.prisma.$connect();
    } else {
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      try {
        this.state = this.cipher.decrypt<State>(
          await readFile(resolve(this.directory, "state.enc"), "utf8"),
        );
      } catch (e: any) {
        if (e.code !== "ENOENT") throw e;
      }
      const before = JSON.stringify(this.state.users);
      normalizeProfiles(this.state);
      if (before !== JSON.stringify(this.state.users)) {
        const file = resolve(this.directory, "state.enc");
        await writeFile(file + ".tmp", this.cipher.encrypt(this.state), { mode: 0o600 });
        await rename(file + ".tmp", file);
      }
    }
  }
  async read<T>(fn: (state: State) => T): Promise<T> {
    await this.init();
    if (this.prisma)
      return this.prisma.$transaction(async (tx) => { const state = await this.load(tx); normalizeProfiles(state); return fn(state); }, {
        isolationLevel: "RepeatableRead",
      });
    await this.queue;
    return fn(structuredClone(this.state));
  }
  async transaction<T>(fn: (state: State) => T | Promise<T>): Promise<T> {
    await this.init();
    const operation = async () => {
      if (this.prisma)
        return this.prisma.$transaction(
          async (tx) => {
            await tx.$queryRawUnsafe(
              "SELECT pg_advisory_xact_lock(879201)::text",
            );
            const state = await this.load(tx);
            const before = structuredClone(state);
            normalizeProfiles(state);
            const result = await fn(state);
            normalizeProfiles(state);
            await this.save(tx, before, state);
            return result;
          },
          { maxWait: 10000, timeout: 30000 },
        );
      const next = structuredClone(this.state);
      normalizeProfiles(next);
      const result = await fn(next);
      normalizeProfiles(next);
      const file = resolve(this.directory, "state.enc");
      await writeFile(file + ".tmp", this.cipher.encrypt(next), {
        mode: 0o600,
      });
      await rename(file + ".tmp", file);
      this.state = next;
      return result;
    };
    const pending = this.queue.then(operation, operation);
    this.queue = pending.then(
      () => {},
      () => {},
    );
    return pending;
  }
  private async load(tx: any): Promise<State> {
    const state = emptyState();
    await Promise.all(
      order.map(async (key) => {
        (state[key] as any[]) = (await tx[tables[key].model].findMany()).map(
          (row: any) => this.cipher.decrypt(row.payload),
        );
      }),
    );
    return state;
  }
  private async save(tx: any, before: State, next: State) {
    for (const key of [...order].reverse()) {
      const ids = new Set((next[key] as any[]).map((v) => v.id));
      const remove = (before[key] as any[])
        .filter((v) => !ids.has(v.id))
        .map((v) => v.id);
      if (remove.length)
        await tx[tables[key].model].deleteMany({
          where: { id: { in: remove } },
        });
    }
    for (const key of order) {
      const prior = new Map(
        (before[key] as any[]).map((v) => [v.id, JSON.stringify(v)]),
      );
      for (const item of next[key] as any[]) {
        if (prior.get(item.id) === JSON.stringify(item)) continue;
        const data: any = { id: item.id, payload: this.cipher.encrypt(item) };
        for (const field of tables[key].fields)
          data[field] =
            field === "createdAt" ? new Date(item[field]) : item[field];
        await tx[tables[key].model].upsert({
          where: { id: item.id },
          create: data,
          update: data,
        });
      }
    }
  }
  encrypt(value: unknown) {
    return this.cipher.encrypt(value);
  }
  decrypt<T>(value: string) {
    return this.cipher.decrypt<T>(value);
  }
  async onModuleDestroy() {
    await this.prisma?.$disconnect();
  }
}
