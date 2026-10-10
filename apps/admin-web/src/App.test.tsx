// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import App from './App';

const user = { id: 'user-1', displayName: 'Pilot tester', spokenLanguage: 'ta', listeningLanguage: 'bn', isAdmin: false };
const session = { accessToken: 'test-access', refreshToken: 'test-refresh', user, mode: 'development-simulator' };
const group = { id: 'group-1', name: 'Pilot group', description: 'Real API integration boundary', role: 'admin', memberCount: 1 };
const capabilities = { auth: { developmentSimulator: true, phoneOtp: false, email: false }, ai: { stt: false, translation: false, tts: false }, billing: { configured: false, purchasesEnabled: false }, storage: { mode: 'file-development' }, realtime: { path: '/v1/realtime' }, limitations: ['Physical-device receiving has not been verified.'] };
const usage = { month: '2026-10', messages: 3, audioSeconds: 120, translationCharacters: 300, ttsCharacters: 100, estimatedCostUsd: 0.25, limits: { monthlyMessages: 100, monthlyAudioSeconds: 600, monthlyBudgetUsd: 1, dailyBudgetUsd: 0.25 } };
const overview = { users: 1, groups: 1, messages: 3, activeUsers: 1, activeGroups: 1, failedMessages: 0, estimatedAiCostUsd: 0.25, usage: { audioSeconds: 120, translationCharacters: 300, ttsCharacters: 100, cacheHits: 0 }, subscriptions: { trial: 1, active: 0, pastDue: 0 }, providerHealth: [], revenueInr: null, revenueNote: 'Revenue is unavailable until verified payment reconciliation is configured.', scope: 'aggregates-only' };
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
function installFetch(overrides: Record<string, (options: RequestInit) => Response | Promise<Response>> = {}) {
  const fetch = vi.fn(async (url: string, options: RequestInit = {}) => {
    const path = new URL(url, 'http://localhost').pathname.replace(/^\/v1/, '');
    if (overrides[path]) return overrides[path](options);
    if (path === '/auth/dev') return json(session);
    if (path === '/users/me') return json(user);
    if (path === '/groups') return json([group]);
    if (path === '/groups/group-1') return json({ ...group, members: [{ userId: user.id, displayName: user.displayName, spokenLanguage: user.spokenLanguage, listeningLanguage: user.listeningLanguage, role: 'admin' }] });
    if (path === '/usage') return json(usage);
    if (path === '/capabilities') return json(capabilities);
    if (path === '/plans') return json([{ id: 'trial', name: 'Free Trial', priceInr: 0, monthlyMessages: 100, monthlyAudioSeconds: 600, monthlyBudgetUsd: 1, maxGroupMembers: 10, broadcasts: false, indicative: true }]);
    if (path === '/admin/overview') return json(overview);
    return json({ message: 'Unexpected test endpoint' }, 404);
  });
  vi.stubGlobal('fetch', fetch);
  return fetch;
}
beforeEach(() => {
  sessionStorage.clear();
  HTMLDialogElement.prototype.showModal = function () { this.setAttribute('open', ''); };
});
afterEach(() => { cleanup(); sessionStorage.clear(); vi.unstubAllGlobals(); });

describe('connected workspace behavior', () => {
  it('requires an explicit local login and sends the selected language', async () => {
    const fetch = installFetch(); render(<App />);
    expect(screen.getByText('Development authentication')).toBeTruthy();
    const button = screen.getByRole('button', { name: 'Start development session' }) as HTMLButtonElement;
    expect(button.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText('Your display name'), { target: { value: 'Tamil pilot' } });
    fireEvent.change(screen.getByLabelText('Your language'), { target: { value: 'ta' } });
    fireEvent.click(button);
    await screen.findByRole('heading', { name: 'Overview' });
    const loginCall = fetch.mock.calls.find(([url]) => url.endsWith('/auth/dev'));
    expect(JSON.parse(String(loginCall?.[1]?.body))).toEqual({ displayName: 'Tamil pilot', language: 'ta' });
    await screen.findByText('API connected');
    expect(fetch.mock.calls.some(([url]) => url.endsWith('/admin/overview'))).toBe(false);
  });
  it('shows authentication failures without creating a session', async () => {
    installFetch({ '/auth/dev': () => json({ message: 'Development authentication is disabled.' }, 503) }); render(<App />);
    fireEvent.change(screen.getByLabelText('Your display name'), { target: { value: 'Tester' } });
    fireEvent.click(screen.getByRole('button', { name: 'Start development session' }));
    await screen.findByText('Development authentication is disabled.');
    expect(sessionStorage.getItem('m2yl:admin:session')).toBeNull();
  });
  it('creates a group through the API and refreshes the returned membership list', async () => {
    sessionStorage.setItem('m2yl:admin:session', JSON.stringify(session));
    let created = false;
    const fetch = installFetch({ '/groups': options => {
      if (options.method === 'POST') { created = true; return json({ ...group, id: 'group-2', name: 'New multilingual team' }, 201); }
      return json(created ? [group, { ...group, id: 'group-2', name: 'New multilingual team' }] : [group]);
    } });
    render(<App />); await screen.findByText('API connected');
    fireEvent.click(screen.getByRole('button', { name: 'Groups' }));
    fireEvent.click(screen.getByRole('button', { name: 'Create group' }));
    const dialog = screen.getByRole('dialog');
    fireEvent.change(within(dialog).getByLabelText('Group name'), { target: { value: 'New multilingual team' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Create group' }));
    await screen.findByRole('heading', { name: 'New multilingual team' });
    const create = fetch.mock.calls.find(([url, options]) => url.endsWith('/groups') && options?.method === 'POST');
    expect(JSON.parse(String(create?.[1]?.body))).toEqual({ name: 'New multilingual team', description: '' });
  });
  it('displays unknown revenue honestly and does not offer a paid entitlement shortcut', async () => {
    sessionStorage.setItem('m2yl:admin:session', JSON.stringify({ ...session, user: { ...user, isAdmin: true } }));
    const fetch = installFetch(); render(<App />);
    await screen.findByText('Revenue is unavailable until verified payment reconciliation is configured.');
    expect(screen.getByText('Unavailable')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'Plans & billing' }));
    const purchase = await screen.findByRole('button', { name: 'Purchases unavailable' }) as HTMLButtonElement;
    expect(purchase.disabled).toBe(true);
    fireEvent.click(purchase);
    expect(fetch.mock.calls.some(([url]) => url.includes('/billing/'))).toBe(false);
  });
  it('keeps previous values visibly stale when a refresh fails', async () => {
    sessionStorage.setItem('m2yl:admin:session', JSON.stringify(session));
    let offline = false;
    installFetch({ '/usage': () => offline ? json({ message: 'Usage service unavailable.' }, 503) : json(usage) });
    render(<App />); await screen.findByText('API connected'); offline = true;
    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));
    await screen.findByText('Partial connection');
    expect(screen.getByText('Some data could not be refreshed. Previously loaded values may be stale. Use Refresh to retry.')).toBeTruthy();
    await waitFor(() => expect(screen.getByText('3')).toBeTruthy());
  });
  it('revokes a session through the server before clearing the browser session', async () => {
    sessionStorage.setItem('m2yl:admin:session', JSON.stringify(session));
    const fetch = installFetch({ '/auth/logout': () => json({ status: 'revoked' }) });
    render(<App />); await screen.findByText('API connected');
    fireEvent.click(screen.getByRole('button', { name: 'Privacy & account' }));
    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }));
    await screen.findByRole('heading', { name: 'Welcome to your workspace' });
    const logout = fetch.mock.calls.find(([url]) => url.endsWith('/auth/logout'));
    expect(logout?.[1]?.method).toBe('POST');
    expect(sessionStorage.getItem('m2yl:admin:session')).toBeNull();
  });
  it('retains the session when the server cannot confirm revocation', async () => {
    sessionStorage.setItem('m2yl:admin:session', JSON.stringify(session));
    installFetch({ '/auth/logout': () => json({ message: 'Server offline.' }, 503) });
    render(<App />); await screen.findByText('API connected');
    fireEvent.click(screen.getByRole('button', { name: 'Privacy & account' }));
    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }));
    await screen.findByText('Server offline. The server could not confirm session revocation.');
    expect(sessionStorage.getItem('m2yl:admin:session')).not.toBeNull();
  });
  it('keeps the newer group selection when an older detail request finishes late', async () => {
    sessionStorage.setItem('m2yl:admin:session', JSON.stringify(session));
    let resolveFirst!: (response: Response) => void;
    const first = new Promise<Response>(resolve => { resolveFirst = resolve; });
    const members = [{ userId: user.id, displayName: user.displayName, spokenLanguage: 'ta', listeningLanguage: 'bn', role: 'admin' }];
    const fetch = installFetch({
      '/groups': () => json([group, { ...group, id: 'group-2', name: 'Second group' }]),
      '/groups/group-1': () => first,
      '/groups/group-2': () => json({ ...group, id: 'group-2', name: 'Second group', description: 'Second selected description', members }),
    });
    render(<App />); await screen.findByText('API connected');
    fireEvent.click(screen.getByRole('button', { name: 'Groups' }));
    await waitFor(() => expect(fetch.mock.calls.some(([url]) => url.endsWith('/groups/group-1'))).toBe(true));
    fireEvent.click(screen.getByRole('button', { name: /Second group/ }));
    await screen.findByText('Second selected description');
    await act(async () => { resolveFirst(json({ ...group, description: 'Late first description', members })); });
    expect(screen.queryByText('Late first description')).toBeNull();
    expect(screen.getByText('Second selected description')).toBeTruthy();
  });
  it('refreshes expired tokens without logging out on a subsequent authorization denial', async () => {
    sessionStorage.setItem('m2yl:admin:session', JSON.stringify(session));
    const fetch = installFetch({
      '/usage': options => (options.headers as Record<string, string>).Authorization === 'Bearer test-access'
        ? json({ message: 'Session expired.' }, 401) : json({ message: 'Usage access denied.' }, 403),
      '/auth/refresh': () => json({ ...session, accessToken: 'rotated-access', refreshToken: 'rotated-refresh' }),
    });
    render(<App />); await screen.findByText('Partial connection');
    fireEvent.click(screen.getByRole('button', { name: 'Usage & costs' }));
    await screen.findByText('Usage access denied.', { exact: false });
    expect(screen.queryByRole('heading', { name: 'Welcome to your workspace' })).toBeNull();
    expect(JSON.parse(sessionStorage.getItem('m2yl:admin:session')!).accessToken).toBe('rotated-access');
    expect(fetch.mock.calls.filter(([url]) => url.endsWith('/auth/refresh'))).toHaveLength(1);
  });
});
