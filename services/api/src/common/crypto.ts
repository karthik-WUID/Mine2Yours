import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";
export const hash = (value: string): string =>
  createHash("sha256").update(value).digest("hex");
export const secret = (): string => randomBytes(32).toString("base64url");
export const equal = (a: string, b: string): boolean => {
  const x = Buffer.from(a),
    y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};
export class Cipher {
  constructor(private key: Buffer) {
    if (key.length !== 32)
      throw new Error("DATA_ENCRYPTION_KEY must decode to 32 bytes");
  }
  encrypt(value: unknown): string {
    const iv = randomBytes(12);
    const c = createCipheriv("aes-256-gcm", this.key, iv);
    const data = Buffer.concat([
      c.update(JSON.stringify(value), "utf8"),
      c.final(),
    ]);
    return [iv, c.getAuthTag(), data]
      .map((b) => b.toString("base64"))
      .join(".");
  }
  decrypt<T>(value: string): T {
    const [iv, tag, data] = value
      .split(".")
      .map((v) => Buffer.from(v, "base64"));
    const d = createDecipheriv("aes-256-gcm", this.key, iv);
    d.setAuthTag(tag);
    return JSON.parse(
      Buffer.concat([d.update(data), d.final()]).toString("utf8"),
    ) as T;
  }
}
