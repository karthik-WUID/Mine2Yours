// Google ML Kit on-device translation model coverage. Not cloud language coverage.
export const deviceTranslationLanguages = "af ar be bg bn ca cs cy da de el en eo es et fa fi fr ga gl gu he hi hr ht hu id is it ja ka kn ko lt lv mk mr ms mt nl no pl pt ro ru sk sl sq sv sw ta te th tl tr uk ur vi zh".split(" ");
export type Role = "admin" | "moderator" | "member";
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
export interface User {
  id: string;
  displayName: string;
  /** Optional on legacy encrypted records; normalized before reads and writes. */
  updatedAt?: string;
  version?: number;
  spokenLanguage: string;
  listeningLanguage: string;
  isAdmin: boolean;
  createdAt: string;
  receivingMode: "notification" | "automatic" | "headphones" | "silent";
  quietHours?: string;
  providerConsent: boolean;
  deviceHash?: string;
  phoneHash?: string;
  phoneLast4?: string;
  phoneVerified?: boolean;
}
export interface Session {
  id: string;
  userId: string;
  accessHash: string;
  refreshHash: string;
  previousRefreshHash?: string;
  refreshHistory?: string[];
  accessExpiresAt: string;
  expiresAt: string;
  revokedAt?: string;
  createdAt: string;
}
export interface Group {
  id: string;
  name: string;
  description: string;
  createdBy: string;
  createdAt: string;
  workers?: WorkerRecord[];
}
export interface WorkerRecord {
  id: string;
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
  identityDocumentId?: string;
  identityDocumentMime?: string;
  consentRecordedAt: string;
  updatedAt: string;
  createdAt: string;
  payments: { id: string; date: string; amount: number; note: string }[];
  workLog: { id: string; date: string; hours: number; detail: string }[];
}
export interface Member {
  id: string;
  groupId: string;
  userId: string;
  role: Role;
  createdAt: string;
}
export interface Invitation {
  id: string;
  groupId: string;
  tokenHash: string;
  createdBy: string;
  expiresAt: string;
  usedBy: string[];
}
export interface Translation {
  needsDeviceTranslation?: boolean;
  id: string;
  messageId: string;
  language: string;
  text: string;
  provider: string;
  audioId?: string;
  audioMimeType?: string;
  voiceProfile: string;
}
export interface Recipient {
  id: string;
  messageId: string;
  userId: string;
  language: string;
  state: ReceiptState;
  updatedAt: string;
}
export interface Message {
  processing?: "device" | "cloud" | "voice";
  id: string;
  groupId: string;
  senderId: string;
  sourceLanguage: string;
  sourceText: string;
  mode: "direct" | "group" | "broadcast";
  state: MessageState;
  idempotencyKey: string;
  requestHash: string;
  createdAt: string;
  expiresAt: string;
  durationSeconds: number;
  error?: { code: string; message: string };
  timings?: Record<string, number>;
  reservationUsd: number;
  needsReview: boolean;
}
export interface Usage {
  id: string;
  userId: string;
  groupId: string;
  messageId?: string;
  createdAt: string;
  kind:
    | "stt"
    | "translation"
    | "tts"
    | "reservation"
    | "release"
    | "message"
    | "cache";
  amount: number;
  estimatedCostUsd: number;
  provider: string;
  pricingVersion: string;
}
export interface Cache {
  id: string;
  groupId: string;
  text: string;
  language: string;
  audioId?: string;
  audioMimeType?: string;
  provider: string;
  expiresAt: string;
  status?: "PROCESSING" | "READY" | "FAILED";
  requestHash?: string;
  errorCode?: string;
}
export interface Subscription {
  id: string;
  userId: string;
  planId: string;
  state: "trial" | "active" | "past_due" | "cancelled";
  expiresAt: string;
  billingCustomerId?: string;
}
export interface Audit {
  id: string;
  actorId: string;
  action: string;
  entityId: string;
  createdAt: string;
}
export interface Device {
  id: string;
  userId: string;
  name: string;
  platform: "android" | "ios" | "web";
  pushToken?: string;
  createdAt: string;
}
export interface BillingEvent {
  id: string;
  provider: string;
  eventId: string;
  createdAt: string;
}
export interface State {
  users: User[];
  sessions: Session[];
  groups: Group[];
  members: Member[];
  invitations: Invitation[];
  messages: Message[];
  translations: Translation[];
  recipients: Recipient[];
  usage: Usage[];
  cache: Cache[];
  subscriptions: Subscription[];
  audit: Audit[];
  devices: Device[];
  billingEvents: BillingEvent[];
}
export const emptyState = (): State => ({
  users: [],
  sessions: [],
  groups: [],
  members: [],
  invitations: [],
  messages: [],
  translations: [],
  recipients: [],
  usage: [],
  cache: [],
  subscriptions: [],
  audit: [],
  devices: [],
  billingEvents: [],
});
export const languages = [
  "ta",
  "bn",
  "hi",
  "or",
  "en",
  "te",
  "kn",
  "ml",
  "mr",
  "gu",
  "pa",
  "ur",
  "as", "brx", "doi", "ks", "kok", "mai", "mni", "ne", "sa", "sat", "sd",
  "es",
  "fr",
  "de",
  "ar",
  "zh",
  "ja",
  "pt",
];
export interface Plan {
  id: string;
  name: string;
  priceInr: number;
  monthlyMessages: number;
  monthlyAudioSeconds: number;
  monthlyBudgetUsd: number;
  dailyBudgetUsd: number;
  maxGroupMembers: number;
  maxSites?: number;
  broadcasts: boolean;
  indicative: true;
}
export const plans: Plan[] = [
  { id: "silver", name: "Silver", priceInr: 0, monthlyMessages: 100000, monthlyAudioSeconds: 6000000, monthlyBudgetUsd: 0, dailyBudgetUsd: 0, maxGroupMembers: 5, maxSites: 1, broadcasts: false, indicative: true },
  { id: "gold", name: "Gold", priceInr: 0, monthlyMessages: 100000, monthlyAudioSeconds: 6000000, monthlyBudgetUsd: 0, dailyBudgetUsd: 0, maxGroupMembers: 100, maxSites: 10, broadcasts: true, indicative: true },
  { id: "diamond", name: "Diamond", priceInr: 0, monthlyMessages: 100000, monthlyAudioSeconds: 6000000, monthlyBudgetUsd: 12, dailyBudgetUsd: 3, maxGroupMembers: 100, maxSites: 10, broadcasts: true, indicative: true },
];

// Optional reviewed configuration replaces business hypotheses without a code change.
if (process.env.PLANS_JSON) {
  const configured = JSON.parse(process.env.PLANS_JSON) as Plan[];
  if (
    !Array.isArray(configured) ||
    !configured.length ||
    !configured.some((p) => p.id === "silver") ||
    configured.some(
      (p) =>
        !p.id ||
        !p.name ||
        !Number.isFinite(p.priceInr) ||
        p.priceInr < 0 ||
        [
          p.monthlyMessages,
          p.monthlyAudioSeconds,
          p.monthlyBudgetUsd,
          p.dailyBudgetUsd,
          p.maxGroupMembers,
        ].some((v) => !Number.isFinite(v) || v < 0) ||
        typeof p.broadcasts !== "boolean",
    )
  )
    throw new Error("PLANS_JSON is invalid");
  plans.splice(
    0,
    plans.length,
    ...configured.map((p) => ({ ...p, indicative: true as const })),
  );
}
