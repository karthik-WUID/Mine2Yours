import 'reflect-metadata';
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';
import { Cipher, hash } from '../src/common/crypto';
import { emptyState, deviceTranslationLanguages } from '../src/common/types';
import { normalizeProfiles, memberState } from '../src/common/profile';
const pause = (ms: number) => new Promise(r => setTimeout(r, ms));

test('legacy member names and regional codes normalize without replacing identities or valid preferences', () => {
 const s=emptyState();
 for(const displayName of [undefined,null,'','null',' undefined ']) s.users.push({id:randomUUID(),displayName,spokenLanguage:'TA_in',createdAt:'2026-01-01T00:00:00.000Z'} as any);
 s.users.push({id:randomUUID(),displayName:'  Profile Name  ',spokenLanguage:'ta',listeningLanguage:'hi',createdAt:'2026-01-01T00:00:00.000Z',version:9} as any);
 const ids=s.users.map(u=>u.id);normalizeProfiles(s);
 for(const u of s.users.slice(0,5)){assert.equal(u.displayName,'Team Member');assert.equal(u.spokenLanguage,'ta');assert.equal(u.listeningLanguage,'ta');assert.equal(u.version,1);assert.equal(memberState(u).userId,u.id);}
 assert.deepEqual(s.users.map(u=>u.id),ids);assert.equal(s.users[5].displayName,'Profile Name');assert.equal(s.users[5].listeningLanguage,'hi');assert.equal(s.users[5].version,9);
 const before=JSON.stringify(s);normalizeProfiles(s);assert.equal(JSON.stringify(s),before);
 assert.ok(deviceTranslationLanguages.includes('ta')&&deviceTranslationLanguages.includes('hi'));
});

test('real authenticated REST/WebSocket member synchronization and free receiver translation', async t=>{
 const directory=await mkdtemp(join(tmpdir(),'lingo-members-')),key=randomBytes(32),cipher=new Cipher(key);
 const legacySecret=randomBytes(32).toString('hex'),legacyId=randomUUID();
 const seed=emptyState();seed.users.push({id:legacyId,deviceHash:hash(legacySecret),spokenLanguage:'hi-IN',createdAt:'2026-01-01T00:00:00.000Z',receivingMode:'automatic',providerConsent:false,isAdmin:false} as any);
 await writeFile(join(directory,'state.enc'),cipher.encrypt(seed));
 const child=spawn(process.execPath,['dist/main.js'],{cwd:resolve(__dirname,'..'),env:{...process.env,NODE_ENV:'test',ENABLE_DEV_AUTH:'false',HOST:'127.0.0.1',PORT:'0',DEV_DATA_DIR:directory,DATA_ENCRYPTION_KEY:key.toString('base64'),DATABASE_URL:'',REDIS_URL:'',S3_BUCKET:'',SARVAM_API_KEY:'',OPENAI_API_KEY:'',GOOGLE_TRANSLATE_API_KEY:'',TRANSLATION_HTTP_URL:'',STT_HTTP_URL:'',TTS_HTTP_URL:'',GLOBAL_DAILY_AI_BUDGET_USD:'0',GLOBAL_MONTHLY_AI_BUDGET_USD:'0',AI_PRICING_CONFIRMED:'false'},stdio:['ignore','pipe','pipe']});
 let output='',errors='';child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>errors+=d);const sockets:WebSocket[]=[];
 try{
  let port=0;for(let i=0;i<200;i++){const line=output.split('\n').find(l=>l.includes('api.started'));if(line){port=JSON.parse(line).port;break;}if(child.exitCode!==null)throw Error(errors);await pause(50);}assert.ok(port);
  const request=async(path:string,method='GET',body?:any,token?:string)=>{const r=await fetch(`http://127.0.0.1:${port}/v1${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return {status:r.status,body:await r.json() as any};};
  const login=async(secret:string,displayName:string,language:string)=>{const r=await request('/auth/device','POST',{deviceSecret:secret,displayName,language});assert.equal(r.status,201);return r.body;};
  const A=await login(randomBytes(32).toString('hex'),'Karthik','ta'),B=await login(legacySecret,'Ignored existing name','en'),C=await login(randomBytes(32).toString('hex'),'Meena','en'),O=await login(randomBytes(32).toString('hex'),'Outsider','ta');
  await t.test('legacy repair persists and partial DTO PATCH does not erase omitted fields',async()=>{
   assert.equal(B.user.id,legacyId);assert.equal(B.user.displayName,'Team Member');assert.equal(B.user.listeningLanguage,'hi');
   const r=await request('/users/me','PATCH',{displayName:'Suresh',expectedVersion:B.user.version},B.accessToken);assert.equal(r.status,200);B.user=r.body;
   assert.equal(B.user.spokenLanguage,'hi');assert.equal(B.user.listeningLanguage,'hi');assert.equal(B.user.providerConsent,false);
   const saved=cipher.decrypt<any>(await readFile(join(directory,'state.enc'),'utf8')).users.find((u:any)=>u.id===legacyId);assert.equal(saved.displayName,'Suresh');assert.equal(saved.listeningLanguage,'hi');
   for(const displayName of ['null',' ','undefined',null])assert.equal((await request('/users/me','PATCH',{displayName},B.accessToken)).status,400);
  });
  const group=(await request('/groups','POST',{name:'Member regression'},A.accessToken)).body;
  const invite=(await request(`/groups/${group.id}/invitations`,'POST',{},A.accessToken)).body;
  for(const user of [B,C])assert.equal((await request('/groups/join','POST',{token:invite.token},user.accessToken)).status,201);
  await t.test('invitation and joining returns authenticated names and stable member IDs',async()=>{
   const detail=(await request(`/groups/${group.id}`,'GET',undefined,B.accessToken)).body;
   assert.deepEqual(detail.members.map((m:any)=>[m.userId,m.displayName]),[[A.user.id,'Karthik'],[B.user.id,'Suresh'],[C.user.id,'Meena']]);for(const m of detail.members){assert.ok(m.updatedAt);assert.ok(m.version>0);}
  });
  const connect=async(user:any)=>{
   const socket=new WebSocket(`ws://127.0.0.1:${port}/v1/realtime`);sockets.push(socket);const events:any[]=[];socket.on('message',d=>events.push(JSON.parse(d.toString())));
   await new Promise<void>((r,j)=>{socket.once('open',()=>{socket.send(JSON.stringify({type:'authenticate',accessToken:user.accessToken}));r();});socket.once('error',j);});
   const wait=async(type:string,predicate=(_:any)=>true)=>{for(let i=0;i<100;i++){const e=events.find(e=>e.type===type&&predicate(e.data));if(e)return e.data;await pause(20);}throw Error(`Missing ${type}`);};await wait('authenticated');return {socket,events,wait};
  };
  const sa=await connect(A),sb=await connect(B),so=await connect(O);
  await t.test('A Tamil→English and B Hindi→Tamil are visible on the other socket without changing its preferences',async()=>{
   const a=await request('/users/me','PATCH',{spokenLanguage:'en',expectedVersion:A.user.version},A.accessToken);assert.equal(a.status,200);A.user=a.body;
   const ea=await sb.wait('member.language.updated',d=>d.member.userId===A.user.id&&d.member.version===A.user.version);assert.equal(ea.member.spokenLanguage,'en');assert.equal(ea.member.listeningLanguage,'ta');assert.equal(ea.member.displayName,'Karthik');
   const b=await request('/users/me','PATCH',{spokenLanguage:'ta',listeningLanguage:'ta',expectedVersion:B.user.version},B.accessToken);assert.equal(b.status,200);B.user=b.body;
   const eb=await sa.wait('member.language.updated',d=>d.member.userId===B.user.id&&d.member.version===B.user.version);assert.equal(eb.member.spokenLanguage,'ta');assert.equal(eb.member.listeningLanguage,'ta');assert.equal((await request('/users/me','GET',undefined,A.accessToken)).body.listeningLanguage,'ta');
   assert.equal(so.events.filter(e=>['member.language.updated','team.members.snapshot'].includes(e.type)).length,0);
   assert.equal((await request('/users/me','PATCH',{userId:B.user.id,spokenLanguage:'hi'},A.accessToken)).status,400);assert.equal((await request(`/users/${B.user.id}`,'PATCH',{listeningLanguage:'hi'},A.accessToken)).status,404);assert.equal((await request('/users/me','PATCH',{listeningLanguage:'hi'})).status,401);
  });
  await t.test('Tamil→Hindi is a free device path and each of three users keeps its own listening language',async()=>{
   B.user=(await request('/users/me','PATCH',{listeningLanguage:'hi'},B.accessToken)).body;
   const input={processing:'device',sourceLanguage:'ta',text:'வணக்கம்',groupId:group.id,mode:'group',idempotencyKey:randomUUID()};
   const sent=await request('/messages','POST',input,A.accessToken);assert.equal(sent.status,201);assert.deepEqual(sent.body.translations.map((v:any)=>v.language).sort(),['en','hi']);
   for(const [u,language] of [[B,'hi'],[C,'en']] as const){const m=(await request(`/messages/${sent.body.id}`,'GET',undefined,u.accessToken)).body;assert.equal(m.translations[0].language,language);assert.equal(m.translations[0].needsDeviceTranslation,true);}
   assert.equal((await request('/users/me','GET',undefined,A.accessToken)).body.listeningLanguage,'ta');
   B.user=(await request('/users/me','PATCH',{listeningLanguage:'ta'},B.accessToken)).body;
   const later=(await request(`/messages/${sent.body.id}`,'GET',undefined,B.accessToken)).body;assert.equal(later.translations[0].language,'ta');assert.equal(later.translations[0].needsDeviceTranslation,false);assert.equal(later.recipients[0].language,'ta');
  });
  await t.test('simultaneous changes are independent; duplicate and stale writes cannot revert current state',async()=>{
   const results=await Promise.all([request('/users/me','PATCH',{spokenLanguage:'hi',expectedVersion:A.user.version},A.accessToken),request('/users/me','PATCH',{spokenLanguage:'en',expectedVersion:B.user.version},B.accessToken)]);assert.deepEqual(results.map(r=>r.status),[200,200]);A.user=results[0].body;B.user=results[1].body;
   await sb.wait('member.language.updated',d=>d.member.userId===A.user.id&&d.member.version===A.user.version);await sa.wait('member.language.updated',d=>d.member.userId===B.user.id&&d.member.version===B.user.version);
   const conflict=await Promise.all(['en','ta'].map(listeningLanguage=>request('/users/me','PATCH',{listeningLanguage,expectedVersion:A.user.version},A.accessToken)));assert.deepEqual(conflict.map(r=>r.status).sort(),[200,409]);A.user=conflict.find(r=>r.status===200)!.body;
   const duplicate=await request('/users/me','PATCH',{listeningLanguage:A.user.listeningLanguage,expectedVersion:A.user.version},A.accessToken);assert.equal(duplicate.body.version,A.user.version);
  });
  await t.test('reconnect snapshot and device session recovery preserve identity, names and versions',async()=>{
   sb.socket.close();const recovered=await login(legacySecret,'Different name','or');assert.equal(recovered.user.id,legacyId);assert.equal(recovered.user.displayName,'Suresh');assert.equal(recovered.user.spokenLanguage,B.user.spokenLanguage);
   const sc=await connect(recovered);const snapshot=await sc.wait('team.members.snapshot',d=>d.groupId===group.id);assert.equal(snapshot.members.find((m:any)=>m.userId===A.user.id).version,A.user.version);assert.equal(snapshot.members.find((m:any)=>m.userId===B.user.id).listeningLanguage,'ta');B.accessToken=recovered.accessToken;
  });
  await t.test('genuinely unsupported language fails explicitly and never silently charges cloud AI',async()=>{
   await request('/users/me','PATCH',{listeningLanguage:'or'},B.accessToken);
   const input={processing:'device',sourceLanguage:'ta',text:'வணக்கம்',groupId:group.id,recipientId:B.user.id,mode:'direct',idempotencyKey:randomUUID()};const failed=await request('/messages','POST',input,A.accessToken);assert.equal(failed.status,400);assert.equal(failed.body.code,'DEVICE_LANGUAGE_UNSUPPORTED');assert.deepEqual(failed.body.unsupportedLanguages,['or']);
   assert.equal((await request('/messages','POST',{...input,processing:'cloud',idempotencyKey:randomUUID()},A.accessToken)).status,403);
   const usage=(await request('/usage','GET',undefined,A.accessToken)).body;assert.equal(usage.estimatedCostUsd,0);assert.equal(usage.cloudAiAllowed,false);
   const state=cipher.decrypt<any>(await readFile(join(directory,'state.enc'),'utf8'));assert.ok(state.usage.every((u:any)=>u.estimatedCostUsd===0));assert.equal(state.users.find((u:any)=>u.id===A.user.id).providerConsent,false);
  });
 }finally{for(const s of sockets)s.terminate();child.kill('SIGTERM');await new Promise(r=>child.exitCode!==null?r(null):child.once('exit',r));await rm(directory,{recursive:true,force:true});}
});
