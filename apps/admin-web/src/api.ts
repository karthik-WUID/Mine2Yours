import type { Session } from './types';

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); this.name = 'ApiError'; }
}

export function validateApiUrl(raw: string): string {
  // A relative API path keeps the browser on the host's HTTPS origin in deployment.
  if (/^\/(?!\/)[a-zA-Z0-9/_-]*$/.test(raw)) return raw.replace(/\/$/, '');
  const url = new URL(raw);
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) throw new Error('The API must use HTTPS. HTTP is allowed only on localhost.');
  if (url.username || url.password) throw new Error('The API URL must not contain credentials.');
  return url.toString().replace(/\/$/, '');
}

export const API_URL = validateApiUrl(import.meta.env.VITE_API_URL || '/v1');
const SESSION_KEY = 'm2yl:admin:session';

export function readSession(): Session | null {
  try {
    const item = sessionStorage.getItem(SESSION_KEY);
    if (!item) return null;
    const value = JSON.parse(item) as Session;
    return value.accessToken && value.refreshToken && value.user?.id ? value : null;
  } catch { return null; }
}
export function saveSession(session: Session | null) {
  if (session) sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));
  else sessionStorage.removeItem(SESSION_KEY);
}

export async function request<T>(path: string, token?: string, options: RequestInit = {}): Promise<T> {
  let response: Response;
  try {
    response = await fetch(`${API_URL}${path}`, {
      ...options,
      headers: { ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...options.headers },
      signal: options.signal || AbortSignal.timeout(15000),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    throw new ApiError(0, 'Cannot reach the API. Check the server and your connection, then try again.');
  }
  if (response.status === 204) return undefined as T;
  const contentType = response.headers.get('content-type') || '';
  const data = contentType.includes('application/json') ? await response.json() : null;
  if (!response.ok) {
    const detail = data?.message;
    throw new ApiError(response.status, Array.isArray(detail) ? detail.join('. ') : typeof detail === 'string' ? detail : `Request failed (${response.status}).`);
  }
  return data as T;
}

export function body(value: unknown): RequestInit { return { body: JSON.stringify(value) }; }
