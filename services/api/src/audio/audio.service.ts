import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { readFile, writeFile, mkdir, rm, readdir } from "node:fs/promises";
import { join } from "node:path";
import { createHmac, randomUUID } from "node:crypto";
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { Store } from "../common/store";
import { equal } from "../common/crypto";
import { membership } from "../groups/groups.service";
import { now } from "../auth/auth.service";

@Injectable()
export class AudioService {
  private s3?: S3Client;
  constructor(private readonly store: Store) {
    if (process.env.S3_BUCKET)
      this.s3 = new S3Client({
        region: process.env.S3_REGION || "ap-south-1",
        endpoint: process.env.S3_ENDPOINT,
        forcePathStyle: !!process.env.S3_ENDPOINT,
      });
  }
  async put(bytes: Buffer, mimeType: string) {
    await this.store.init();
    const id = randomUUID();
    const encrypted = this.store.encrypt({
      audio: bytes.toString("base64"),
      mimeType,
      createdAt: now(),
    });
    if (this.s3)
      await this.s3.send(
        new PutObjectCommand({
          Bucket: process.env.S3_BUCKET,
          Key: `audio/${id}`,
          Body: encrypted,
          ContentType: "application/octet-stream",
          ServerSideEncryption:
            process.env.S3_SERVER_SIDE_ENCRYPTION === "none"
              ? undefined
              : "AES256",
        }),
      );
    else {
      if (process.env.NODE_ENV === "production")
        throw new Error("Production audio requires S3_BUCKET");
      const path = join(this.store.directory, "audio");
      await mkdir(path, { recursive: true, mode: 0o700 });
      await writeFile(join(path, id), encrypted, { mode: 0o600 });
    }
    return id;
  }
  private signingKey() {
    return (
      process.env.AUDIO_SIGNING_KEY ||
      process.env.DATA_ENCRYPTION_KEY ||
      "development-authenticated-audio-only"
    );
  }
  url(id: string, userId: string) {
    const expires = Date.now() + 5 * 60000;
    const signature = createHmac("sha256", this.signingKey())
      .update(`${id}:${userId}:${expires}`)
      .digest("hex");
    return `/v1/audio/${id}?expires=${expires}&signature=${signature}`;
  }
  async get(id: string, userId: string, expires: string, signature: string) {
    if (!/^[0-9a-f-]{36}$/.test(id)) throw new NotFoundException();
    const deadline = Number(expires);
    if (
      !Number.isFinite(deadline) ||
      deadline < Date.now() ||
      deadline > Date.now() + 6 * 60000
    )
      throw new ForbiddenException("Audio URL expired");
    const expected = createHmac("sha256", this.signingKey())
      .update(`${id}:${userId}:${expires}`)
      .digest("hex");
    if (!equal(signature || "", expected)) throw new ForbiddenException();
    await this.store.read((s) => {
      const translation = s.translations.find(
        (v) =>
          v.audioId === id &&
          s.messages.some(
            (m) =>
              m.id === v.messageId &&
              m.expiresAt > now() &&
              (m.senderId === userId ||
                (m.state === "READY" &&
                  s.recipients.some(
                    (r) =>
                      r.messageId === m.id &&
                      r.userId === userId &&
                      r.language === v.language,
                  ))),
          ),
      );
      if (!translation) throw new NotFoundException();
      const message = s.messages.find((v) => v.id === translation.messageId)!;
      membership(s, message.groupId, userId);
      if (message.senderId !== userId) {
        const recipient = s.recipients.find(
          (v) =>
            v.messageId === message.id &&
            v.userId === userId &&
            v.language === translation.language,
        );
        if (!recipient || message.state !== "READY")
          throw new ForbiddenException();
      }
    });
    let encrypted: string;
    if (this.s3) {
      const response = await this.s3.send(
        new GetObjectCommand({
          Bucket: process.env.S3_BUCKET,
          Key: `audio/${id}`,
        }),
      );
      encrypted = await response.Body!.transformToString();
    } else {
      try {
        encrypted = await readFile(
          join(this.store.directory, "audio", id),
          "utf8",
        );
      } catch {
        throw new NotFoundException();
      }
    }
    const data = this.store.decrypt<{ audio: string; mimeType: string }>(
      encrypted,
    );
    return {
      bytes: Buffer.from(data.audio, "base64"),
      mimeType: data.mimeType,
    };
  }
  async delete(id: string) {
    if (this.s3)
      await this.s3.send(
        new DeleteObjectCommand({
          Bucket: process.env.S3_BUCKET,
          Key: `audio/${id}`,
        }),
      );
    else await rm(join(this.store.directory, "audio", id), { force: true });
  }
  async sweep(retainedIds: Set<string>) {
    if (this.s3) return;
    const path = join(this.store.directory, "audio");
    let files: string[];
    try {
      files = await readdir(path);
    } catch {
      return;
    }
    for (const id of files) if (!retainedIds.has(id)) await this.delete(id);
  }
}
