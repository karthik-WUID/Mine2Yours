import test from 'node:test';
import assert from 'node:assert/strict';
import { AuthGuard } from '../src/auth/auth.guard';
test('authenticated budgets isolate users behind one proxy and receipts from sends', async () => {
  const guard = new AuthGuard({authenticate: async (token: string) => ({user: {id: token}, sessionId: token})} as any);
  const headers: Record<string, unknown> = {};
  const context = (id: string, path: string, method = 'GET') => ({switchToHttp: () => ({getRequest: () => ({headers: {authorization: 'Bearer '+id}, ip: '127.0.0.1', path, method, res: {setHeader: (k: string,v: unknown) => headers[k]=v}})})} as any);
  for(let i=0;i<180;i++) await guard.canActivate(context('one','/v1/messages'));
  await assert.rejects(()=>guard.canActivate(context('one','/v1/messages')), (e: any) => e.getStatus()===429);
  assert.ok(Number(headers['Retry-After'])>0);
  await guard.canActivate(context('two','/v1/messages'));
  for(let i=0;i<100;i++) await guard.canActivate(context('one','/v1/messages/id/ack','POST'));
  for(let i=0;i<30;i++) await guard.canActivate(context('one','/v1/messages','POST'));
  await assert.rejects(()=>guard.canActivate(context('one','/v1/messages','POST')), (e: any) => e.getStatus()===429);
  await guard.canActivate(context('two','/v1/messages','POST'));
});
