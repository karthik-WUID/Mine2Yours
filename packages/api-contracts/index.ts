/** Public API v1. Provider outputs are never substituted with invented translations. */
export type LanguageCode = "ta" | "bn" | "hi" | "or" | "en" | string;
export interface Profile {
  id: string;
  displayName: string;
  spokenLanguage: LanguageCode;
  listeningLanguage: LanguageCode;
  isAdmin: boolean;
  providerConsent: boolean;
  receivingMode: "notification" | "automatic" | "headphones" | "silent";
  quietHours?: string;
  createdAt: string;
  phoneLast4?: string;
  phoneVerified?: boolean;
}
export interface SessionResponse {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  user: Profile;
  mode?: "development-simulator" | "development-phone" | "verified-phone";
}
export type GroupRole = "admin" | "moderator" | "member";
export interface GroupMember {
  userId: string;
  displayName: string;
  spokenLanguage: LanguageCode;
  listeningLanguage: LanguageCode;
  role: GroupRole;
  joinedDate?: string;
  jobTitle?: string;
  workDetails?: string;
  site?: string;
  photoData?: string;
  employmentStatus?: "active" | "on_leave" | "left";
}
export interface Group {
  id: string;
  name: string;
  description: string;
  createdBy: string;
  createdAt: string;
  role?: GroupRole;
  memberCount?: number;
  members?: GroupMember[];
}
export interface Invitation {
  token: string;
  expiresAt: string;
  joinUrl: string;
}
export type MessageState =
  | "CREATED"
  | "PROCESSING"
  | "READY"
  | "REVIEW_REQUIRED"
  | "FAILED"
  | "EXPIRED"
  | "CANCELLED"
  | "RETRY_PENDING";
export type ReceiptState =
  | "PENDING"
  | "DELIVERED"
  | "PLAYBACK_STARTED"
  | "PLAYBACK_COMPLETED"
  | "FAILED";
export interface Message {
  processing?: "device" | "cloud";
  id: string;
  groupId: string;
  senderId: string;
  sourceLanguage: LanguageCode;
  sourceText: string;
  mode: "direct" | "group" | "broadcast";
  state: MessageState;
  createdAt: string;
  expiresAt: string;
  durationSeconds: number;
  needsReview: boolean;
  translations: {
    language: LanguageCode;
    text: string;
    provider: string;
    needsDeviceTranslation?: boolean;
    audioUrl?: string;
    audioMimeType?: string;
  }[];
  recipients: { userId: string; language: LanguageCode; state: ReceiptState }[];
  error?: { code: string; message: string };
  timings?: Record<string, number>;
}
export interface MessageInput {
  processing?: "device" | "cloud";
  groupId: string;
  recipientId?: string;
  sourceLanguage: LanguageCode;
  text?: string;
  audioBase64?: string;
  mimeType?: "audio/wav";
  durationSeconds?: number;
  idempotencyKey: string;
  mode: "direct" | "group" | "broadcast";
  needsReview?: boolean;
  requiresReview?: boolean;
}
export interface Usage {
  cloudAiAllowed?: boolean;
  month: string;
  messages: number;
  audioSeconds: number;
  translationCharacters: number;
  ttsCharacters: number;
  estimatedCostUsd: number;
  cacheHits: number;
  limits: {
    monthlyMessages: number;
    monthlyAudioSeconds: number;
    monthlyBudgetUsd: number;
    dailyBudgetUsd: number;
  };
  pricingVersion: string;
  subscription?: Subscription;
}
export interface Subscription {
  id: string;
  userId: string;
  planId: string;
  state: "trial" | "active" | "past_due" | "cancelled";
  expiresAt: string;
}
export interface Plan {
  id: string;
  name: string;
  priceInr: number;
  monthlyMessages: number;
  monthlyAudioSeconds: number;
  monthlyBudgetUsd: number;
  dailyBudgetUsd: number;
  maxGroupMembers: number;
  broadcasts: boolean;
  indicative: true;
}
export interface Capabilities {
  developmentAuth: boolean;
  devAuth: boolean;
  auth: { developmentSimulator: boolean; phoneLogin: boolean; phoneOtp: boolean; email: false };
  ai: { stt: boolean; translation: boolean; tts: boolean };
  billing: {
    configured: boolean;
    purchasesEnabled: boolean;
    providers: string[];
    requiresServerVerification: true;
  };
  storage: { mode: "postgresql" | "isolated-development-file" };
  realtime: { path: "/v1/realtime" };
  languages: LanguageCode[];
  pricingVersion: string;
  limitations: string[];
}
export type RealtimeEvent = {
  type:
    | "authenticated"
    | "message.ready"
    | "message.updated"
    | "group.updated"
    | "pong";
  data: {
    userId?: string;
    messageId?: string;
    groupId?: string;
    state?: MessageState;
    removedUserIds?: string[];
  };
};

/** Admin-only personnel endpoint. Never put these records in a public Group/cache. */
export interface WorkerInput {
  displayName: string;
  linkedUserId?: string;
  phone: string;
  jobTitle: string;
  workDetails: string;
  site: string;
  joinedDate: string;
  status: "active" | "on_leave" | "left";
  salaryAmount: number;
  salaryPeriod: "day" | "week" | "month";
  photoData?: string;
  consent: boolean;
}
export interface WorkerRecord extends Omit<WorkerInput, "consent"> {
  id: string;
  identityDocumentId?: string;
  identityDocumentMime?: "image/jpeg" | "image/png";
  consentRecordedAt: string;
  createdAt: string;
  updatedAt: string;
  payments: { id: string; date: string; amount: number; note: string }[];
  workLog: { id: string; date: string; hours: number; detail: string }[];
}
