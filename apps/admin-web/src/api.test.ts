import { afterEach, describe, expect, it, vi } from 'vitest';
import { API_URL, ApiError, body, request, validateApiUrl } from './api';

afterEach(() => vi.unstubAllGlobals());
describe('API connection boundary', () => {
  it('allows local development HTTP and requires HTTPS for remote APIs', () => {
    expect(validateApiUrl('/v1')).toBe('/v1');
    expect(() => validateApiUrl('//api.example.com/v1')).toThrow();
    expect(validateApiUrl('http://localhost:3000/v1/')).toBe('http://localhost:3000/v1');
    expect(validateApiUrl('https://api.example.com/v1')).toBe('https://api.example.com/v1');
    expect(() => validateApiUrl('http://api.example.com/v1')).toThrow('HTTPS');
    expect(() => validateApiUrl('https://secret:password@api.example.com/v1')).toThrow('credentials');
  });
  it('submits authenticated group mutations with JSON and bearer authorization', async () => {
    const fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ id: 'group-id', name: 'Team' }), { headers: { 'content-type': 'application/json' } }));
    vi.stubGlobal('fetch', fetch);
    const result = await request('/groups', 'session-token', { method: 'POST', ...body({ name: 'Team' }) });
    expect(result).toEqual({ id: 'group-id', name: 'Team' });
    expect(fetch).toHaveBeenCalledWith(`${API_URL}/groups`, expect.objectContaining({ method: 'POST', body: '{"name":"Team"}', headers: { Authorization: 'Bearer session-token', 'Content-Type': 'application/json' } }));
  });
  it('does not attach authorization to development login', async () => {
    const fetch = vi.fn().mockResolvedValue(new Response('{}', { headers: { 'content-type': 'application/json' } }));
    vi.stubGlobal('fetch', fetch);
    await request('/auth/dev', undefined, { method: 'POST', ...body({ displayName: 'Test', language: 'ta' }) });
    expect(fetch.mock.calls[0][1].headers).not.toHaveProperty('Authorization');
  });
  it('preserves authorization failure and backend validation messages', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('{"message":["Permission denied","Group is private"]}', { status: 403, headers: { 'content-type': 'application/json' } })));
    await expect(request('/groups/private', 'token')).rejects.toMatchObject({ status: 403, message: 'Permission denied. Group is private' });
  });
  it('reports unavailable network without inventing loaded data', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('fetch failed')));
    await expect(request('/usage', 'token')).rejects.toBeInstanceOf(ApiError);
    await expect(request('/usage', 'token')).rejects.toMatchObject({ status: 0 });
  });
  it('accepts a successful delete with no body', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(null, { status: 204 })));
    expect(await request('/groups/id', 'token', { method: 'DELETE' })).toBeUndefined();
  });
});
