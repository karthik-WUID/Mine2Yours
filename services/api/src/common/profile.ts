import { languages, State, User } from "./types";

export function displayName(value: unknown, fallback = "Team Member"): string {
  if (typeof value !== "string") return fallback;
  const name = value.trim();
  return name && !["null", "undefined"].includes(name.toLowerCase()) ? name : fallback;
}
export function languageCode(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const code = value.trim().toLowerCase().replace(/_/g, "-").split("-")[0];
  return languages.includes(code) ? code : undefined;
}
/** Repair old partial PATCH damage without replacing identities or valid preferences. */
export function normalizeUser(user: User, legacyName?: string): User {
  user.displayName = displayName(user.displayName, displayName(legacyName));
  user.spokenLanguage = languageCode(user.spokenLanguage) || languageCode(user.listeningLanguage) || "en";
  user.listeningLanguage = languageCode(user.listeningLanguage) || user.spokenLanguage;
  user.version = Number.isSafeInteger(user.version) && user.version! > 0 ? user.version : 1;
  user.updatedAt = user.updatedAt && Number.isFinite(Date.parse(user.updatedAt)) ? user.updatedAt : user.createdAt;
  return user;
}
export function normalizeProfiles(state: State) {
  for (const user of state.users) {
    const worker = state.groups.flatMap(g => g.workers || []).find(w => w.linkedUserId === user.id);
    normalizeUser(user, worker?.displayName);
  }
}
export function memberState(user: User) {
  const normalized = normalizeUser({ ...user });
  return { userId: normalized.id, displayName: normalized.displayName,
    spokenLanguage: normalized.spokenLanguage, listeningLanguage: normalized.listeningLanguage,
    updatedAt: normalized.updatedAt!, version: normalized.version! };
}
/** Credential material must never appear in profile, export or auth responses. */
export function publicUser(user: User) {
  const { phoneHash, deviceHash, ...profile } = normalizeUser({ ...user });
  return profile;
}
