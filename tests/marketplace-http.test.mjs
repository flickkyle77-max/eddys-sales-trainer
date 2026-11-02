import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {marketplaceRubric} from '../marketplace.mjs';
process.env.SUPABASE_URL='https://market-db.test';process.env.SUPABASE_PUBLISHABLE_KEY='test-key';process.env.OPENAI_API_KEY='test-key';process.env.COOKIE_SECRET='test-only-marketplace';
const actualFetch=globalThis.fetch,records=[],requests=[];let failSave=false,failHistory=false;
globalThis.fetch=async(url,options={})=>{
 url=String(url);if(url.startsWith('http://127.0.0.1:'))return actualFetch(url,options);requests.push({url,options});
 if(url==='https://market-db.test/auth/v1/user'){const id=options.headers.Authorization?.slice(7);return Response.json(id==='alpha'||id==='beta'?{id,email:id+'@example.test'}:{},{status:['alpha','beta'].includes(id)?200:401});}
 if(url.startsWith('https://market-db.test/rest/v1/')){
  const u=new URL(url),user=options.headers.Authorization.slice(7);
  if(options.method==='POST'){if(failSave)return Response.json({error:'outage'},{status:503});const record=JSON.parse(options.body);assert.equal(record.user_id,user);if(!records.some(r=>r.id===record.id))records.push({...record,created_at:new Date().toISOString()});return new Response(null,{status:201});}
  if(failHistory)return Response.json({error:'outage'},{status:503});
  const id=u.searchParams.get('id')?.slice(3),owner=u.searchParams.get('user_id')?.slice(3),filter=u.searchParams.get('scenario');assert.equal(owner,user);
  return Response.json(records.filter(r=>r.user_id===owner&&(!id||r.id===id)&&(filter==='like.marketplace_*'?r.scenario.startsWith('marketplace_'):filter==='not.like.marketplace_*'?!r.scenario.startsWith('marketplace_'):true)));
 }
 if(url==='https://api.openai.com/v1/responses'){
  const body=JSON.parse(options.body);assert.equal(body.store,false);assert.equal(body.text.format.strict,true);assert(options.signal);const input=JSON.parse(body.input),schema=body.text.format.schema;let value;
  if(schema.properties.reply)value={reply:'Would you take $35,000?',offerCents:3500000};
  else if(schema.properties.focus)value={focus:'comparison'};
  else {const index=input.messages.findIndex(m=>m.role==='salesperson');value={categories:Object.fromEntries(Object.keys(marketplaceRubric).map(k=>[k,{score:5,messageIndex:index,quote:input.messages[index].text,assessment:'This message answered the question.',advice:'Explore the comparison next.',alternative:'What are you comparing?'}]))};}
  return Response.json({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(value)}]}]});
 }
 throw Error('Unexpected request '+url);
};
const {app}=await import('../server.mjs');const server=app.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
const call=async(path,body,user='alpha')=>{const r=await actualFetch(base+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(user?{Cookie:'trainer_access='+user}:{})},body:body===undefined?undefined:JSON.stringify(body)});return {status:r.status,cache:r.headers.get('cache-control'),value:await r.json()};};
test.after(()=>{server.close();globalThis.fetch=actualFetch;});
test('all Marketplace routes require authentication and disable caching',async()=>{for(const p of ['catalog','history']){const r=await call('/api/marketplace/'+p,undefined,'');assert.equal(r.status,401);assert.equal(r.cache,'no-store');}for(const p of ['start','reply','manager','finish','save'])assert.equal((await call('/api/marketplace/'+p,{},'')).status,401);});
test('HTTP customer/manager/grade/history flow uses employee RLS credentials and correct history filters',async()=>{
 let s=(await call('/api/marketplace/start',{vehicleId:'silverado-2022'})).value;
 s=(await call('/api/marketplace/reply',{token:s.token,message:'Yes, available. What would help?'})).value;
 s=(await call('/api/marketplace/manager',{token:s.token,message:'The customer offered based on another listing.',offerCents:3500000})).value;
 assert.equal(s.decisions[0].authorizedPriceCents,3500000);
 const r=await call('/api/marketplace/finish',{token:s.token});assert.equal(r.status,200);assert.equal(r.value.saved,true);assert.equal(records.length,1);assert.equal(records[0].scores._marketplace.review.managerMessages.length,2);
 const a=await call('/api/marketplace/history');assert.equal(a.value.length,1);assert.equal((await call('/api/marketplace/history',undefined,'beta')).value.length,0);assert.equal((await call('/api/text/history')).value.length,0);
 assert(requests.some(r=>r.url.includes('scenario=like.marketplace_*')));assert(requests.some(r=>r.url.includes('scenario=not.like.marketplace_*')));
 const publicInput=JSON.parse(JSON.parse(requests.find(r=>r.url.includes('api.openai.com')).options.body).input);assert.equal(publicInput.managerMessages,undefined);
});
test('HTTP unauthorized price and cross-account replay return clear client errors',async()=>{const s=(await call('/api/marketplace/start',{vehicleId:'trax-2021'})).value;assert.equal((await call('/api/marketplace/manager',{token:s.token,message:'Approve free car',offerCents:1})).status,400);assert.equal((await call('/api/marketplace/reply',{token:s.token,message:'Hi'},'beta')).status,401);});
test('HTTP save outage preserves sealed retry; history outage is explicit',async()=>{let s=(await call('/api/marketplace/start',{})).value;s=(await call('/api/marketplace/reply',{token:s.token,message:'Happy to help.'})).value;failSave=true;const r=await call('/api/marketplace/finish',{token:s.token});assert.equal(r.value.saved,false);assert(r.value.saveToken);failSave=false;assert.equal((await call('/api/marketplace/save',{token:r.value.saveToken})).value.saved,true);failHistory=true;assert.equal((await call('/api/marketplace/history')).status,502);failHistory=false;});
