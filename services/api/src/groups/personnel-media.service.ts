import { Injectable, NotFoundException, BadRequestException } from "@nestjs/common";
import { mkdir, readFile, writeFile, rm, readdir, stat } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from "@aws-sdk/client-s3";
import { Store } from "../common/store";

export function imageBytes(base64: string, mimeType: string, limit = 1024 * 1024) {
  const bytes = Buffer.from(base64, "base64");
  const png = bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
  const jpeg = bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  if (!bytes.length || bytes.length > limit || (mimeType === "image/png" ? !png : mimeType === "image/jpeg" ? !jpeg : true))
    throw new BadRequestException("Choose a JPEG or PNG image within the size limit.");
  return bytes;
}
@Injectable()
export class PersonnelMediaService {
  private s3?: S3Client;
  constructor(private readonly store: Store) {
    if (process.env.S3_BUCKET) this.s3 = new S3Client({ region: process.env.S3_REGION || "ap-south-1", endpoint: process.env.S3_ENDPOINT, forcePathStyle: !!process.env.S3_ENDPOINT });
  }
  async put(base64: string, mimeType: string) {
    const bytes = imageBytes(base64, mimeType);
    await this.store.init();
    const id = randomUUID();
    const encrypted = this.store.encrypt({ base64: bytes.toString("base64"), mimeType, createdAt: new Date().toISOString() });
    if (this.s3) await this.s3.send(new PutObjectCommand({ Bucket: process.env.S3_BUCKET, Key: `personnel/${id}`, Body: encrypted, ContentType: "application/octet-stream", ServerSideEncryption: "AES256" }));
    else {
      if (process.env.NODE_ENV === "production") throw new Error("Production personnel documents require S3_BUCKET");
      await mkdir(join(this.store.directory, "personnel"), { recursive: true, mode: 0o700 });
      await writeFile(join(this.store.directory, "personnel", id), encrypted, { mode: 0o600 });
    }
    return id;
  }
  async get(id: string) {
    if (!/^[0-9a-f-]{36}$/.test(id)) throw new NotFoundException();
    let encrypted: string;
    if (this.s3) {
      const value = await this.s3.send(new GetObjectCommand({ Bucket: process.env.S3_BUCKET, Key: `personnel/${id}` }));
      encrypted = await value.Body!.transformToString();
    } else {
      try { encrypted = await readFile(join(this.store.directory, "personnel", id), "utf8"); }
      catch { throw new NotFoundException(); }
    }
    return this.store.decrypt<{ base64: string; mimeType: string }>(encrypted);
  }
  async delete(id: string) {
    if (!/^[0-9a-f-]{36}$/.test(id)) return;
    if (this.s3) await this.s3.send(new DeleteObjectCommand({ Bucket: process.env.S3_BUCKET, Key: `personnel/${id}` }));
    else await rm(join(this.store.directory, "personnel", id), { force: true });
  }
  async sweep(retained: Set<string>) {
    if (this.s3) return;
    let files: string[];
    try { files = await readdir(join(this.store.directory, "personnel")); } catch { return; }
    for (const id of files) if (!retained.has(id) && (await stat(join(this.store.directory, "personnel", id))).mtimeMs < Date.now() - 86400000) await this.delete(id);
  }
}
