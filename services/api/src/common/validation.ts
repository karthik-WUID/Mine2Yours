import {
  IsBoolean,
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
  Matches,
} from "class-validator";
import { languages } from "./types";
export class PhoneLoginRequestDto {
  @IsString() @Matches(/^\+[1-9][0-9]{7,14}$/) phone!: string;
}
export class PhoneLoginVerifyDto extends PhoneLoginRequestDto {
  @IsString() @Matches(/^\d{6}$/) code!: string;
  @IsOptional() @IsString() @MinLength(2) @MaxLength(80) displayName?: string;
  @IsIn(languages) language!: string;
}
export class WorkerDto {
  @IsString() @MinLength(2) @MaxLength(80) displayName!: string;
  @IsOptional() @IsUUID() linkedUserId?: string;
  @IsString() @MaxLength(20) @Matches(/^(\+[1-9][0-9]{7,14})?$/) phone!: string;
  @IsString() @MaxLength(100) jobTitle!: string;
  @IsString() @MaxLength(2000) workDetails!: string;
  @IsString() @MaxLength(100) site!: string;
  @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) joinedDate!: string;
  @IsIn(["active", "on_leave", "left"]) status!: "active" | "on_leave" | "left";
  @IsNumber({ maxDecimalPlaces: 2, allowNaN: false, allowInfinity: false }) @Min(0) @Max(10000000) salaryAmount!: number;
  @IsIn(["day", "week", "month"]) salaryPeriod!: "day" | "week" | "month";
  @IsOptional() @IsString() @MaxLength(400000) photoData?: string;
  @IsBoolean() consent!: boolean;
}
export class WorkerDocumentDto {
  @IsIn(["image/jpeg", "image/png"]) mimeType!: string;
  @IsString() @MaxLength(1500000) @Matches(/^[A-Za-z0-9+/]+={0,2}$/) base64!: string;
  @IsBoolean() consent!: boolean;
}
export class WorkerPaymentDto {
  @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) date!: string;
  @IsNumber({ maxDecimalPlaces: 2, allowNaN: false, allowInfinity: false }) @Min(0.01) @Max(10000000) amount!: number;
  @IsString() @MaxLength(500) note!: string;
}
export class WorkerLogDto {
  @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) date!: string;
  @IsNumber({ maxDecimalPlaces: 2, allowNaN: false, allowInfinity: false }) @Min(0) @Max(24) hours!: number;
  @IsString() @MinLength(1) @MaxLength(1000) detail!: string;
}
export class DevAuthDto {
  @IsString() @MinLength(1) @MaxLength(80) displayName!: string;
  @IsIn(languages) language!: string;
  @IsOptional() @IsString() @MaxLength(100) adminKey?: string;
}
export class DeviceSessionDto {
  @IsString() @Matches(/^[a-f0-9]{64}$/) deviceSecret!: string;
  @IsOptional() @IsString() @MinLength(1) @MaxLength(80) displayName?: string;
  @IsIn(languages) language!: string;
}
export class RefreshDto {
  @IsString() @MinLength(20) @MaxLength(128) refreshToken!: string;
}
export class ProfileDto {
  @IsOptional() @IsInt() @Min(1) expectedVersion?: number;
  @IsOptional() @IsString() @MinLength(1) @MaxLength(80) displayName?: string;
  @IsOptional() @IsIn(languages) spokenLanguage?: string;
  @IsOptional() @IsIn(languages) listeningLanguage?: string;
  @IsOptional()
  @IsIn(["notification", "automatic", "headphones", "silent"])
  receivingMode?: "notification" | "automatic" | "headphones" | "silent";
  @IsOptional() @IsString() @MaxLength(30) quietHours?: string;
  @IsOptional() @IsBoolean() providerConsent?: boolean;
}
export class GroupDto {
  @IsString() @MinLength(1) @MaxLength(100) name!: string;
  @IsOptional() @IsString() @MaxLength(500) description?: string;
}
export class UpdateGroupDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(100) name?: string;
  @IsOptional() @IsString() @MaxLength(500) description?: string;
}
export class InvitationDto {
  @IsOptional() @IsInt() @Min(1) @Max(168) expiresInHours?: number;
}
export class JoinDto {
  @IsString() @MinLength(20) @MaxLength(128) token!: string;
}
export class MemberRoleDto {
  @IsIn(["admin", "moderator", "member"]) role!:
    | "admin"
    | "moderator"
    | "member";
}
export class MessageDto {
  @IsOptional() @IsIn(["device", "cloud", "voice"]) processing?: "device" | "cloud" | "voice";
  @IsUUID() groupId!: string;
  @IsOptional() @IsUUID() recipientId?: string;
  @IsIn(languages) sourceLanguage!: string;
  @IsOptional() @IsString() @MinLength(1) @MaxLength(4000) text?: string;
  @IsOptional()
  @IsString()
  @MaxLength(5_600_000)
  @Matches(/^[A-Za-z0-9+/]*={0,2}$/)
  audioBase64?: string;
  @IsOptional()
  @IsIn([
    "audio/wav",
    "audio/mpeg",
    "audio/mp4",
    "audio/webm",
    "audio/ogg",
    "audio/x-m4a",
  ])
  mimeType?: string;
  @IsOptional() @IsNumber() @Min(0.1) @Max(60) durationSeconds?: number;
  @IsString() @MinLength(8) @MaxLength(128) idempotencyKey!: string;
  @IsIn(["direct", "group", "broadcast"]) mode!:
    | "direct"
    | "group"
    | "broadcast";
  @IsOptional() @IsBoolean() needsReview?: boolean;
  @IsOptional() @IsBoolean() requiresReview?: boolean;
}
export class AckDto {
  @IsIn(["DELIVERED", "PLAYBACK_STARTED", "PLAYBACK_COMPLETED", "FAILED"])
  state!: "DELIVERED" | "PLAYBACK_STARTED" | "PLAYBACK_COMPLETED" | "FAILED";
}
export class DeleteAccountDto {
  @IsIn(["DELETE"]) confirmation!: "DELETE";
}
export class DeviceDto {
  @IsString() @MaxLength(80) name!: string;
  @IsIn(["android", "ios", "web"]) platform!: "android" | "ios" | "web";
  @IsOptional() @IsString() @MaxLength(2048) pushToken?: string;
}
export class PurchaseDto {
  @IsIn(["apple", "google", "web"]) provider!: "apple" | "google" | "web";
  @IsString() @MaxLength(20000) receipt!: string;
}

export class TranscribeDto {
  @IsUUID() groupId!: string;
  @IsIn(languages) sourceLanguage!: string;
  @IsString()
  @MaxLength(5_600_000)
  @Matches(/^[A-Za-z0-9+/]*={0,2}$/)
  audioBase64!: string;
  @IsIn(["audio/wav"]) mimeType!: string;
  @IsOptional() @IsNumber() @Min(0.1) @Max(60) durationSeconds?: number;
  @IsString() @MinLength(8) @MaxLength(128) idempotencyKey!: string;
}
export class OtpRequestDto {
  @IsString() @Matches(/^\+[1-9][0-9]{7,14}$/) phone!: string;
}
export class OtpVerifyDto extends OtpRequestDto {
  @IsString() @Matches(/^[0-9]{4,10}$/) code!: string;
  @IsString() @MinLength(1) @MaxLength(80) displayName!: string;
  @IsIn(languages) language!: string;
}
