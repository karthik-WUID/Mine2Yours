export interface User {
  id: string;
  displayName: string;
  spokenLanguage: string;
  listeningLanguage: string;
  isAdmin: boolean;
  receivingMode?: string;
}
export interface Session { accessToken: string; refreshToken: string; user: User; mode?: string }
export interface Member { userId: string; displayName: string; spokenLanguage: string; listeningLanguage: string; role: 'admin' | 'moderator' | 'member' }
export interface Group { id: string; name: string; description?: string; role: Member['role']; memberCount: number }
export interface GroupDetails extends Group { members: Member[] }
export interface Usage {
  month: string;
  messages: number;
  audioSeconds: number;
  translationCharacters: number;
  ttsCharacters: number;
  estimatedCostUsd: number;
  limits: { monthlyMessages: number; monthlyAudioSeconds: number; monthlyBudgetUsd: number; dailyBudgetUsd: number };
}
export interface Plan { id: string; name: string; priceInr: number | null; monthlyMessages: number; monthlyAudioSeconds: number; monthlyBudgetUsd: number; maxGroupMembers: number; broadcasts: boolean; indicative: boolean }
export interface ProviderHealth { name: string; configured: boolean; state: string }
export interface Overview {
  users: number; groups: number; messages: number; activeUsers: number; activeGroups: number; failedMessages: number;
  estimatedAiCostUsd: number; usage: { audioSeconds: number; translationCharacters: number; ttsCharacters: number; cacheHits: number };
  subscriptions: { trial: number; active: number; pastDue: number }; providerHealth: ProviderHealth[]; revenueInr: number | null; revenueNote?: string; scope: string;
}
export interface Capabilities {
  auth: { developmentSimulator: boolean; phoneOtp: boolean; email: boolean };
  ai: { stt: boolean; translation: boolean; tts: boolean };
  billing: { configured: boolean; purchasesEnabled: boolean };
  storage: { mode: string }; realtime: { path: string }; limitations: string[];
}
export interface Invitation { token: string; expiresAt: string; joinUrl: string }
export type View = 'overview' | 'groups' | 'members' | 'usage' | 'providers' | 'plans' | 'privacy';
