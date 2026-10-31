import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import crypto from 'node:crypto';
process.env.SUPABASE_URL='https://supabase.test';process.env.SUPABASE_PUBLISHABLE_KEY='test-key';process.env.OPENAI_API_KEY='test-key';process.env.COOKIE_SECRET='test-secret';
const realFetch=globalThis.fetch;const records=[];const apiCalls=[];let failSave=false;
globalThis.fetch=async(url,options={})=>{
 url=String(url);if(url.startsWith('http://127.0.0.1:'))return realFetch(url,options);
 apiCalls.push({url,options});
 if(url==='https://supabase.test/auth/v1/user'){const id=options.headers.Authorization?.slice(7);return Response.json(id==='a'||id==='b'?{id,email:id+'@example.test'}:{},{status:id==='a'||id==='b'?200:401});}
 if(url.startsWith('https://supabase.test/rest/v1/')){
  if(options.method==='POST'){if(failSave)return Response.json({message:'outage'},{status:503});const record=JSON.parse(options.body);if(!records.some(x=>x.id===record.id))records.push(record);return new Response(null,{status:201});}
  const u=new URL(url);const id=u.searchParams.get('id')?.slice(3);const user=u.searchParams.get('user_id')?.slice(3);return Response.json(records.filter(r=>(!id||r.id===id)&&r.user_id===user));
 }
 if(url==='https://api.openai.com/v1/realtime/calls'){
  const session=JSON.parse(options.body.get('session'));
  const supported=new Set(['alloy','ash','ballad','coral','echo','sage','shimmer','verse','marin','cedar']);
  if(!supported.has(session.audio.output.voice))return Response.json({error:{code:'invalid_value',param:'session.audio.output.voice'}},{status:400});
  return new Response('v=0\r\ns=Mock voice answer\r\n',{headers:{'Content-Type':'application/sdp'}});
 }
 if(url==='https://api.openai.com/v1/responses'){
  const body=JSON.parse(options.body),schema=body.text.format.schema;let value;
  if(schema.properties.reply)value={reply:'I want an itemized quote before deciding.'};
  else if(schema.properties.assessment)value={assessment:'Useful question.',question:'What is included?',suggestion:'What would you like to compare?',reason:'Discover the concern.'};
  else value={scores:{acknowledge:8,discover:12,respond:15,trust:10,next_step:10},feedback:Object.fromEntries(['acknowledge','discover','respond','trust','next_step'].map(k=>[k,{quote:'',evidence:'Limited evidence.',advice:'Ask a specific question.'}])),outcome:'No visit agreed.',strength:'Asked a question.',improvement:'Explore the answer.',example:'What matters most?',real_concern:'Total price.',next_drill:'Written comparisons.'};
  return Response.json({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(value)}]}]});
 }
 throw Error('Unexpected outbound request '+url);
};
const {app}=await import('../server.mjs');const server=app.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
const call=async(path,body,user='a')=>{const r=await realFetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(user?{Cookie:'trainer_access='+user}:{})},body:body?JSON.stringify(body):undefined});return {status:r.status,value:await r.json()};};
const settings={topic:'price',difficulty:'realistic',language:'en',mode:'practice',challenge:'progressive'};
test.after(()=>{server.close();globalThis.fetch=realFetch;});
test('every English and Spanish customer can create a Realtime voice session',async()=>{
 const randomInt=crypto.randomInt;
 try{
  for(const language of ['en','es'])for(let index=0;index<8;index++){
   crypto.randomInt=(max)=>{assert.equal(max,8);return index;};
   const response=await realFetch(base+'/api/session',{method:'POST',headers:{'Content-Type':'application/json',Cookie:'trainer_access=a'},body:JSON.stringify({sdp:'v=0\r\n'+'a'.repeat(120),scenario:'internet',difficulty:'realistic',language})});
   assert.equal(response.status,200,`${language} customer ${index} must use a supported voice`);
   assert.match(response.headers.get('content-type'),/application\/sdp/);
   assert.match(await response.text(),/^v=0/);
   const outbound=apiCalls.filter(c=>c.url.endsWith('/realtime/calls')).at(-1);
   const session=JSON.parse(outbound.options.body.get('session'));
   assert.equal(session.audio.input.transcription.language,language);
   assert.equal(outbound.options.headers.Authorization,'Bearer test-key');
  }
 }finally{crypto.randomInt=randomInt;}
});
test('all objection endpoints require authentication',async()=>{assert.equal((await call('/api/objections/catalog',null,'')).status,401);for(const path of ['start','reply','coach','finish','save'])assert.equal((await call('/api/objections/'+path,{},'')).status,401);});
test('authenticated start/reply/finish persists a review with employee credentials',async()=>{const start=await call('/api/objections/start',settings);assert.equal(start.status,200);const next=await call('/api/objections/reply',{token:start.value.token,message:'What are you comparing?'});assert.equal(next.status,200);const score=await call('/api/objections/finish',{token:next.value.token});assert.equal(score.status,200);assert.equal(score.value.total,55);assert.equal(score.value.saved,true);const record=records.find(r=>r.id===start.value.id);assert.equal(record.user_id,'a');assert.equal(record.scenario,'objection_price');const savedCall=apiCalls.find(r=>r.options.method==='POST'&&r.url.endsWith('/text_sessions'));assert.equal(savedCall.options.headers.Authorization,'Bearer a');});
test('cross-account token replay and independent coaching fail',async()=>{const s=(await call('/api/objections/start',settings)).value;assert.equal((await call('/api/objections/reply',{token:s.token,message:'Hi'},'b')).status,401);assert.equal((await call('/api/objections/coach',{token:s.token,draft:'Hi'})).status,403);});
test('history explicitly filters employee ownership and returns objection reviews',async()=>{const a=await call('/api/text/history');assert(a.value.some(r=>r.scenario==='objection_price'));const b=await call('/api/text/history',null,'b');assert.deepEqual(b.value,[]);assert(apiCalls.some(c=>c.url.includes('user_id=eq.b')));});
test('database outage still returns the grade and permits save-only retry',async()=>{const s=(await call('/api/objections/start',settings)).value;const next=(await call('/api/objections/reply',{token:s.token,message:'Tell me more.'})).value;failSave=true;const result=await call('/api/objections/finish',{token:next.token});assert.equal(result.value.saved,false);assert(result.value.saveToken);const count=apiCalls.filter(c=>c.url.includes('api.openai.com')).length;failSave=false;assert.equal((await call('/api/objections/save',{token:result.value.saveToken})).value.saved,true);assert.equal(apiCalls.filter(c=>c.url.includes('api.openai.com')).length,count);});
