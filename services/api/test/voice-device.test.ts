import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, rm, readdir, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import { WebSocket } from 'ws';

function wav() {
  const b=Buffer.alloc(32044);
  b.write('RIFF'); b.writeUInt32LE(b.length-8,4); b.write('WAVEfmt ',8); b.writeUInt32LE(16,16); b.writeUInt16LE(1,20); b.writeUInt16LE(1,22); b.writeUInt32LE(16000,24); b.writeUInt32LE(32000,28); b.writeUInt16LE(2,32); b.writeUInt16LE(16,34); b.write('data',36); b.writeUInt32LE(32000,40);
  for(let i=44;i<b.length;i+=2) b.writeInt16LE(Math.round(3000*Math.sin(i/8)),i);
  return b;
}

test('Silver direct voice: login-free identity, realtime delivery, encrypted audio, replay and site/member limits', async()=>{
 const directory=await mkdtemp(join(tmpdir(),'lingo-direct-'));
 const child=spawn(process.execPath,['dist/main.js'],{cwd:resolve(__dirname,'..'),env:{...process.env,NODE_ENV:'test',ENABLE_DEV_AUTH:'true',DEV_DATA_DIR:directory,PORT:'0',HOST:'127.0.0.1',DATABASE_URL:'',REDIS_URL:'',DATA_ENCRYPTION_KEY:'',S3_BUCKET:'',SARVAM_API_KEY:'',STT_HTTP_URL:'',TTS_HTTP_URL:'',TRANSLATION_HTTP_URL:'',GLOBAL_DAILY_AI_BUDGET_USD:'0',GLOBAL_MONTHLY_AI_BUDGET_USD:'0',AI_PRICING_CONFIRMED:'false'},stdio:['ignore','pipe','pipe']});
 let output='',errors='';child.stdout.on('data',v=>output+=v);child.stderr.on('data',v=>errors+=v);
 let socket:WebSocket|undefined;
 try{
  let port=0;for(let i=0;i<200;i++){const line=output.split('\n').find(v=>v.includes('api.started'));if(line){port=JSON.parse(line).port;break;}if(child.exitCode!==null)throw Error(errors);await new Promise(r=>setTimeout(r,50));}assert.ok(port);
  const request=async(path:string,method='GET',body?:unknown,token?:string)=>{const r=await fetch(`http://127.0.0.1:${port}/v1${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return {status:r.status,body:await r.json() as any};};
  const key=randomBytes(32).toString('hex');
  const login=async(secret:string,language:string)=>{const r=await request('/auth/device','POST',{deviceSecret:secret,language});assert.equal(r.status,201);assert.equal(r.body.user.deviceHash,undefined);return r.body;};
  const sender=await login(key,'ta'),receiver=await login(randomBytes(32).toString('hex'),'or'),other=await login(randomBytes(32).toString('hex'),'en');
  const group=(await request('/groups','POST',{name:'Voice fixture'},sender.accessToken)).body;
  assert.equal((await request('/groups','POST',{name:'Second site'},sender.accessToken)).status,400);
  const invite=(await request(`/groups/${group.id}/invitations`,'POST',{},sender.accessToken)).body;
  for(const u of [receiver,other])assert.equal((await request('/groups/join','POST',{token:invite.token},u.accessToken)).status,201);
  socket=new WebSocket(`ws://127.0.0.1:${port}/v1/realtime`);
  await new Promise<void>((r,j)=>{socket!.once('open',()=>socket!.send(JSON.stringify({type:'authenticate',accessToken:receiver.accessToken})));socket!.on('message',b=>{if(JSON.parse(b.toString()).type==='authenticated')r();});socket!.once('error',j);});
  const event=new Promise<any>((r,j)=>{const t=setTimeout(()=>j(Error('No voice delivery event')),3000);socket!.on('message',b=>{const d=JSON.parse(b.toString());if(d.type==='message.ready'){clearTimeout(t);r(d);}});});
  const recording=wav();const input={processing:'voice',groupId:group.id,recipientId:receiver.user.id,mode:'direct',sourceLanguage:'ta',audioBase64:recording.toString('base64'),mimeType:'audio/wav',durationSeconds:1,idempotencyKey:randomUUID()};
  const sent=await request('/messages','POST',input,sender.accessToken);assert.equal(sent.status,201,JSON.stringify(sent.body));assert.equal(sent.body.state,'READY');assert.equal(sent.body.needsReview,false);assert.equal(sent.body.durationSeconds,1);assert.equal((await event).data.messageId,sent.body.id);
  const received=await request(`/messages/${sent.body.id}`,'GET',undefined,receiver.accessToken);assert.equal(received.status,200);assert.equal(received.body.translations[0].provider,'original-voice');
  const url=received.body.translations[0].audioUrl;const audio=await fetch(`http://127.0.0.1:${port}${url}`,{headers:{Authorization:`Bearer ${receiver.accessToken}`}});assert.equal(audio.status,200);assert.deepEqual(Buffer.from(await audio.arrayBuffer()),recording);
  assert.equal((await request(`/messages/${sent.body.id}`,'GET',undefined,other.accessToken)).status,403);assert.equal((await fetch(`http://127.0.0.1:${port}${url}`,{headers:{Authorization:`Bearer ${other.accessToken}`}})).status,403);
  assert.equal((await request('/messages','POST',input,sender.accessToken)).body.id,sent.body.id);assert.equal((await readdir(join(directory,'audio'))).length,1);
  assert.equal((await request('/messages','POST',{...input,idempotencyKey:randomUUID(),recipientId:randomUUID()},sender.accessToken)).status,400);
  const usage=(await request('/usage','GET',undefined,sender.accessToken)).body;assert.equal(usage.planId,'silver');assert.equal(usage.estimatedCostUsd,0);assert.equal(usage.audioSeconds,0);assert.equal(usage.cloudAiAllowed,false);
  const plans=(await request('/plans')).body;assert.deepEqual(plans.map((p:any)=>p.id),['silver','gold','diamond']);assert.equal(plans[0].maxGroupMembers,5);
  for(let i=0;i<2;i++){const u=await login(randomBytes(32).toString('hex'),'hi');assert.equal((await request('/groups/join','POST',{token:invite.token},u.accessToken)).status,201);}
  const sixth=await login(randomBytes(32).toString('hex'),'hi');assert.equal((await request('/groups/join','POST',{token:invite.token},sixth.accessToken)).status,400);
  const again=await login(key,'en');assert.equal(again.user.id,sender.user.id);assert.equal((await request('/groups','GET',undefined,again.accessToken)).body[0].id,group.id);
  const file=(await readdir(join(directory,'audio')))[0];assert.ok(!(await readFile(join(directory,'audio',file),'utf8')).includes(input.audioBase64));
 }finally{socket?.close();child.kill('SIGTERM');await new Promise(r=>child.exitCode!==null?r(null):child.once('exit',r));await rm(directory,{recursive:true,force:true});}
});
