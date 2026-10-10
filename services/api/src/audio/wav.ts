import { BadRequestException } from "@nestjs/common";
// Derive duration from PCM headers rather than trusting a client supplied number.
export function inspectWav(bytes: Buffer): {
  seconds: number;
  silent: boolean;
} {
  if (
    bytes.length < 44 ||
    bytes.length > 4_000_000 ||
    bytes.toString("ascii", 0, 4) !== "RIFF" ||
    bytes.toString("ascii", 8, 12) !== "WAVE" ||
    bytes.readUInt32LE(4) + 8 !== bytes.length
  )
    throw new BadRequestException({
      code: "AUDIO_FORMAT_UNSUPPORTED",
      message: "Upload a PCM WAV recording of at most 60 seconds.",
    });
  let seenFormat = false;
  let sampleRate = 0,
    channels = 0,
    bits = 0,
    byteRate = 0,
    data: Buffer | undefined;
  for (let offset = 12; offset + 8 <= bytes.length; ) {
    const name = bytes.toString("ascii", offset, offset + 4),
      size = bytes.readUInt32LE(offset + 4);
    if (offset + 8 + size > bytes.length)
      throw new BadRequestException("Truncated WAV audio");
    if (name === "fmt ") {
      if (seenFormat)
        throw new BadRequestException(
          "Duplicate WAV format chunks are not allowed",
        );
      seenFormat = true;
      if (size < 16 || bytes.readUInt16LE(offset + 8) !== 1)
        throw new BadRequestException("WAV must use PCM encoding");
      channels = bytes.readUInt16LE(offset + 10);
      sampleRate = bytes.readUInt32LE(offset + 12);
      byteRate = bytes.readUInt32LE(offset + 16);
      bits = bytes.readUInt16LE(offset + 22);
    }
    if (name === "data") {
      if (data)
        throw new BadRequestException(
          "Duplicate WAV data chunks are not allowed",
        );
      data = bytes.subarray(offset + 8, offset + 8 + size);
    }
    offset += 8 + size + (size % 2);
  }
  if (
    !data ||
    !data.length ||
    ![1, 2].includes(channels) ||
    bits !== 16 ||
    sampleRate < 8000 ||
    sampleRate > 48000 ||
    byteRate !== (sampleRate * channels * bits) / 8 ||
    data.length % (channels * 2) !== 0
  )
    throw new BadRequestException("Unsupported WAV metadata");
  const seconds = data.length / byteRate;
  if (seconds > 60 || seconds < 0.1)
    throw new BadRequestException("Voice recordings must be 0.1–60 seconds");
  let sum = 0,
    count = 0;
  for (
    let i = 0;
    i + 1 < data.length;
    i += Math.max(2, Math.floor(data.length / 20000 / 2) * 2)
  ) {
    const sample = data.readInt16LE(i);
    sum += sample * sample;
    count++;
  }
  return { seconds, silent: Math.sqrt(sum / count) < 8 };
}
