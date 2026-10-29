import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import crypto from 'node:crypto';
import {createObjectionService,registerObjectionRoutes} from './objections.mjs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const app = express();
const root = path.dirname(fileURLToPath(import.meta.url));
app.disable('x-powered-by');
// Render terminates HTTPS at its reverse proxy. Keep local development unproxied.
if(process.env.RENDER==='true')app.set('trust proxy',1);
app.use(helmet({contentSecurityPolicy:false}));
app.use(express.json({limit:'512kb'}));
app.use('/api',(req,res,next)=>{res.set('Cache-Control','no-store');next();});
app.use(express.static(path.join(root,'public'), {index:false}));
const supabaseUrl=(process.env.SUPABASE_URL||'').replace(/\/$/,'');
const supabaseKey=process.env.SUPABASE_PUBLISHABLE_KEY;
if(!supabaseUrl.startsWith('https://')||!supabaseKey)console.warn('Supabase not configured: login unavailable until environment variables are present');
const limiter=rateLimit({windowMs:15*60*1000,limit:20,standardHeaders:'draft-7',legacyHeaders:false});
const callsLimiter=rateLimit({windowMs:60*60*1000,limit:150,keyGenerator:req=>req.userId,standardHeaders:'draft-7',legacyHeaders:false,message:{error:'Hourly practice limit reached. Please try again later.'}});
const objectionLimiter=rateLimit({windowMs:60*60*1000,limit:120,keyGenerator:req=>req.userId,standardHeaders:'draft-7',legacyHeaders:false,message:{error:'Hourly objection practice limit reached. Please try again later.'}});
const cookieOptions={httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'strict',path:'/'};
const cookie=(req,name)=>(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith(name+'='))?.slice(name.length+1);
const authHeaders=(token)=>({'apikey':supabaseKey,'Authorization':`Bearer ${token}`});
async function supabaseAuth(endpoint,method,body,token){
 const r=await fetch(`${supabaseUrl}/auth/v1/${endpoint}`,{method,headers:{'Content-Type':'application/json',...(token?authHeaders(token):{'apikey':supabaseKey})},body:body?JSON.stringify(body):undefined});
 return {ok:r.ok,status:r.status,data:await r.json().catch(()=>({}))};
}
function saveSession(res,data){res.cookie('trainer_access',data.access_token,{...cookieOptions,maxAge:60*60*1000});res.cookie('trainer_refresh',data.refresh_token,{...cookieOptions,maxAge:30*24*60*60*1000});}
async function requireAuth(req,res,next){
 if(!supabaseKey||!supabaseUrl)return res.status(503).json({error:'Supabase configuration missing'});
 try{
  let token=cookie(req,'trainer_access');let r=token?await supabaseAuth('user','GET',null,token):{ok:false};
  if(!r.ok){const refresh=cookie(req,'trainer_refresh');if(!refresh)return res.status(401).json({error:'Please sign in'});
   const updated=await supabaseAuth('token?grant_type=refresh_token','POST',{refresh_token:refresh});
   if(!updated.ok)return res.status(401).json({error:'Session expired. Please sign in again'});
   saveSession(res,updated.data);token=updated.data.access_token;r=await supabaseAuth('user','GET',null,token);
  }
  if(!r.ok||!r.data.id)return res.status(401).json({error:'Please sign in'});
  req.userId=r.data.id;req.authToken=token;req.salesperson=r.data.email||'Salesperson';next();
 }catch(e){console.error('Auth unavailable',e.message);res.status(502).json({error:'Login system temporarily unavailable'})}
}
app.get('/',(req,res)=>res.sendFile(path.join(root,'public','index.html')));
app.post('/api/login',limiter,async(req,res)=>{
 const email=String(req.body?.email||'').trim().toLowerCase();const password=req.body?.password;
 if(!email.includes('@')||typeof password!=='string'||password.length>256)return res.status(400).json({error:'Enter a valid email and password'});
 try{const r=await supabaseAuth('token?grant_type=password','POST',{email,password});if(!r.ok||!r.data.access_token)return res.status(401).json({error:'Email or password incorrect. Confirm your user in Supabase Authentication → Users.'});
 saveSession(res,r.data);res.json({name:r.data.user?.email||email});}
 catch(e){console.error(e);res.status(502).json({error:'Unable to contact sign-in service'})}
});
app.get('/api/me',requireAuth,(req,res)=>res.json({name:req.salesperson}));
app.post('/api/logout',async(req,res)=>{const token=cookie(req,'trainer_access');if(token)try{await supabaseAuth('logout','POST',{},token)}catch{}res.clearCookie('trainer_access',cookieOptions);res.clearCookie('trainer_refresh',cookieOptions);res.json({ok:true})});
app.get('/api/history',requireAuth,async(req,res)=>{
 try{const r=await fetch(`${supabaseUrl}/rest/v1/call_scores?user_id=eq.${encodeURIComponent(req.userId)}&select=created_at,scenario,difficulty,language,total_score,opening,rapport,discovery,objections,appointment,closing,outcome,strength,improvement,example&order=created_at.desc&limit=30`,{headers:authHeaders(req.authToken)});
 if(!r.ok)throw Error(`Supabase ${r.status}`);res.json(await r.json());}catch(e){console.error(e);res.status(502).json({error:'Unable to load personal scores'})}
});
const scenarios={
 internet:{label:'Internet Lead',setup:'You submitted an online inquiry on a new compact SUV. You are cross-shopping a another compact SUV. You can visit but dislike pushy sales calls.'},
 unsold:{label:'Unsold Follow-Up',setup:'You visited three days ago, drove a full-size pickup, and left without purchasing. You are uncertain about payments and are considering waiting.'},
 cold:{label:'Cold Call',setup:'You are receiving a dealership prospecting call unexpectedly. You own a six-year-old midsize SUV and did not request the call.'},
 upgrade:{label:'Previous Customer Upgrade',setup:'You bought a full-size SUV four years ago from the dealership. You are somewhat interested in newer technology but are concerned about increasing your payment.'},
 price:{label:'Price Shopper',setup:'You want the best out-the-door price for a new midsize pickup. You are comparing three dealers and are reluctant to come in before getting numbers.'},
 marketplace:{label:'Marketplace Lead',setup:'You messaged about a used luxury crossover on Facebook Marketplace. You want to know whether the listed price is real and have a trade-in.'},
 service:{label:'Service Upgrade',setup:'Your eight-year-old pickup is in service and a sales representative calls to discuss a possible upgrade. You like your truck and are skeptical.'},
 random:{label:'Random Scenario',setup:'Invent a realistic automotive retail lead situation with a plausible customer goal and hidden objection. Do not tell salesperson your secrets.'}
};
const difficulties={easy:'Be fairly friendly, cooperative, and open to an appointment when invited with a clear reason.',realistic:'Be a believable busy shopper. Offer moderate resistance and 1-2 natural objections, reveal information only when asked, reward good questions.',hard:'Be skeptical, short on time, and protective of details. Raise substantial but reasonable objections. Agree to next steps only when the salesperson earns trust and creates a clear reason.'};
// Pair fictional names with voice profiles before the session starts.
// Do not infer voice from a name; choose a matching pair as one fictional character.
const customerProfiles = {
 en: [
  {name:'Bill',voice:'onyx'}, {name:'Jason',voice:'ash'},
  {name:'Michael',voice:'echo'}, {name:'David',voice:'onyx'},
  {name:'Sarah',voice:'shimmer'}, {name:'Emily',voice:'coral'},
  {name:'Ashley',voice:'nova'}, {name:'Megan',voice:'shimmer'}
 ],
 es: [
  {name:'Carlos',voice:'onyx'}, {name:'Miguel',voice:'ash'},
  {name:'Javier',voice:'echo'}, {name:'Diego',voice:'onyx'},
  {name:'Sofía',voice:'shimmer'}, {name:'María',voice:'coral'},
  {name:'Lucía',voice:'nova'}, {name:'Ana',voice:'shimmer'}
 ]
};
function pickCustomer(language) {
 const profiles=customerProfiles[language];
 return profiles[crypto.randomInt(profiles.length)];
}
app.post('/api/session',requireAuth,callsLimiter,async(req,res)=>{
 const {sdp,scenario,difficulty,language='en'}=req.body||{};
 if(typeof sdp!=='string'||sdp.length<100||sdp.length>30000||!sdp.startsWith('v='))return res.status(400).json({error:'Invalid audio connection offer'});
 if(!scenarios[scenario]||!difficulties[difficulty]||!['en','es'].includes(language))return res.status(400).json({error:'Select a valid scenario, difficulty and language'});
 if(!process.env.OPENAI_API_KEY)return res.status(503).json({error:'Server API key not configured'});
 const customer=pickCustomer(language);
 const languageInstructions = language === 'es' ? `IMPORTANT LANGUAGE RULE: You are a Spanish-speaking customer in the United States. Speak natural conversational Latin American Spanish (neutral Mexican/US Spanish), not a word-for-word English translation. Open and continue the conversation in Spanish, including pricing, trade-in, financing and appointment discussions. Understand English if the salesperson needs a clarification, but return to Spanish for normal conversation. Do not coach or translate unless directly asked IN CHARACTER. The salesperson may speak imperfect Spanish; react like a patient but realistic customer, and do not switch to English simply because they hesitate. ` : `IMPORTANT LANGUAGE RULE: Speak natural conversational American English throughout the call.`;
 const instructions=`${languageInstructions} You are playing a FICTIONAL CUSTOMER in a live PHONE CALL with a dealership salesperson. Only act as the customer; never speak as a coach, assistant, evaluator, or narrator. Scenario: ${scenarios[scenario].setup} Difficulty: ${difficulties[difficulty]} Your fictional FIRST NAME is ${customer.name}. Keep this exact first name for the entire call, and never introduce yourself with a different name. Create believable circumstances and a consistent private backstory. Do not share this scenario briefing. Do not mention being AI or roleplaying. Start the call by waiting for the SALESPERSON to introduce themself. Speak in short, realistic, conversational telephone turns. Do not give away objections or budget unsolicited. Respond specifically to questions, including dealership pricing and visit logistics, without fabricating a confirmed dealership offer, inventory availability, real credit approval or loan approval. When salesperson asks for an appointment, react based on the quality of their approach. Do not hand them success automatically. When the salesperson pauses for a breath or says 'uh' or 'um', wait for them to finish their thought; don't assume a brief hesitation is the end of the turn. Be patient rather than interrupting. Avoid long monologues. If they say 'End call', say a brief goodbye, nothing else. Never provide coaching or scores.`;
 try{
   const form=new FormData(); form.set('sdp',sdp);form.set('session',JSON.stringify({type:'realtime',model:process.env.REALTIME_MODEL||'gpt-realtime-2.1',instructions,audio:{output:{voice:customer.voice},input:{transcription:{model:'gpt-4o-mini-transcribe',language},turn_detection:{type:'semantic_vad',eagerness:'low',create_response:true,interrupt_response:false}}}}));
   const result=await fetch('https://api.openai.com/v1/realtime/calls',{method:'POST',headers:{Authorization:`Bearer ${process.env.OPENAI_API_KEY}`,'OpenAI-Safety-Identifier':crypto.createHash('sha256').update(req.salesperson).digest('hex')},body:form});
   const responseText=await result.text();
   if(!result.ok){console.error('Realtime session failed:',result.status,responseText.slice(0,500));return res.status(502).json({error:'Voice connection unavailable. Check server API credentials/model and retry.'})}
   res.type('application/sdp').send(responseText);
 }catch(e){console.error(e);res.status(502).json({error:'Could not establish voice connection'})}
});
const weights={opening:15,rapport:15,discovery:20,objections:20,appointment:20,closing:10};
app.post('/api/score',requireAuth,callsLimiter,async(req,res)=>{
 const {transcript,scenario,difficulty,language='en'}=req.body||{};
 if(!scenarios[scenario]||!difficulties[difficulty]||!['en','es'].includes(language)||!Array.isArray(transcript)||transcript.length<2||transcript.length>250)return res.status(400).json({error:'Not enough transcript to score this call'});
 const turns=transcript.filter(x=>['Customer','Salesperson'].includes(x?.speaker)&&typeof x.text==='string').map(x=>({speaker:x.speaker,text:x.text.slice(0,1200)}));
 if(turns.length<2 || !turns.some(x=>x.speaker==='Salesperson'))return res.status(400).json({error:'No salesperson speech was transcribed; cannot score reliably'});
 if(!process.env.OPENAI_API_KEY)return res.status(503).json({error:'Server API key not configured'});
 const schema={type:'object',additionalProperties:false,required:['scores','outcome','strength','improvement','example','notes'],properties:{scores:{type:'object',additionalProperties:false,required:Object.keys(weights),properties:Object.fromEntries(Object.keys(weights).map(k=>[k,{type:'integer'}]))},outcome:{type:'string'},strength:{type:'string'},improvement:{type:'string'},example:{type:'string'},notes:{type:'string'}}};
 try{
 const r=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${process.env.OPENAI_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({model:process.env.SCORING_MODEL||'gpt-4.1-mini',instructions:`You are a rigorous but fair car-sales phone-call evaluator. Scenario ${scenarios[scenario].label}, difficulty ${difficulty}. Language of the simulated customer is ${language==='es'?'Spanish':'English'}. Evaluate a Spanish-language call fairly, including whether the salesperson communicates understandably in Spanish, but do not require native fluency. Write outcome, strength, improvement, example and notes in English so the manager and employee can read feedback; the rewritten sample phrase MUST be in Spanish ONLY when language is es, with a short English translation if helpful. If language is en, the rewritten sample phrase MUST be English only; do not include Spanish or translations. Score salesperson only using verifiable transcript evidence. Give each dimension an integer score within its maximum: ${JSON.stringify(weights)}. Opening includes introduction and permission; rapport builds trust; discovery asks about needs/budget/trade/timeline; objections validates and responds; appointment sells a compelling mutually convenient next step; closing confirms details and commitment. If call ends early or has no appointment, mark that honestly. Do not assume appointment was booked. Avoid rewarding pressure, misleading guarantees, or invented discounts. Report one specific strength, highest-leverage improvement, a rewritten example line salesperson could actually say, a succinct outcome, and limitations of transcript. Speech recognition can be imperfect. JSON only.`,input:JSON.stringify(turns),text:{format:{type:'json_schema',name:'call_score',strict:true,schema}}})});
 const data=await r.json(); if(!r.ok)throw Error(data.error?.message||'Scoring provider error');
 const output=(data.output||[]).flatMap(x=>x.content||[]).find(c=>c.type==='output_text')?.text||data.output_text;
 if(!output)throw Error('No scoring output');
 const score=JSON.parse(output);
 for(const [k,max] of Object.entries(weights))score.scores[k]=Math.max(0,Math.min(max,Number(score.scores[k])||0));
 score.total=Object.values(score.scores).reduce((a,b)=>a+b,0);
 try{
   const record={user_id:req.userId,scenario,difficulty,language,total_score:score.total,
    opening:score.scores.opening,rapport:score.scores.rapport,discovery:score.scores.discovery,
    objections:score.scores.objections,appointment:score.scores.appointment,closing:score.scores.closing,
    outcome:score.outcome,strength:score.strength,improvement:score.improvement,example:score.example};
   const saved=await fetch(`${supabaseUrl}/rest/v1/call_scores`,{method:'POST',headers:{...authHeaders(req.authToken),'Content-Type':'application/json','Prefer':'return=minimal'},body:JSON.stringify(record)});
   if(!saved.ok){const details=await saved.text();console.error('Score save failed',saved.status,details.slice(0,200));score.save_warning='Score calculated but not saved to employee history.';}
 }catch(e){console.error('Score save failed',e.message);score.save_warning='Score calculated but not saved to employee history.';}
 res.json(score);
 }catch(e){console.error('Score error',e);res.status(502).json({error:'Could not score this call; transcript is still available on screen'})}
});
// Text simulator routes: all customers fictional, all sessions authenticated, no external SMS sent.
const textDifficulty={easy:'Friendly, usually responsive.',realistic:'Typical lead with real concerns and occasional short replies.',hard:'Skeptical and guarded; harder to earn an appointment.'};
const textTopics={internet:'Asked about a new compact SUV online',marketplace:'Asked about a used luxury crossover on Marketplace',price:'Asks for the out-the-door number of a pickup',unsold:'Visited the store and left without buying',upgrade:'Previous SUV buyer considering an upgrade',noshow:'Missed an appointment and is reluctant to reschedule'};
function validatedTextInput(input){
 const {scenario,difficulty,language,messages}=input||{};
 if(!textTopics[scenario]||!textDifficulty[difficulty]||!['en','es'].includes(language)||!Array.isArray(messages)||messages.length>45)throw Error('Invalid session settings or conversation length');
 const cleaned=messages.map(m=>({role:m.role,text:String(m.text||'').slice(0,1500)}));
 if(cleaned.some(m=>!['customer','salesperson'].includes(m.role)||!m.text.trim()))throw Error('Invalid conversation message');
 return {scenario,difficulty,language,messages:cleaned};
}
async function textAI(instructions,payload,schema){
 if(!process.env.OPENAI_API_KEY)throw Error('OPENAI_API_KEY is not configured');
 const response=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${process.env.OPENAI_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({model:process.env.SCORING_MODEL||'gpt-4.1-mini',instructions,input:JSON.stringify(payload),max_output_tokens:3000,store:false,text:{format:{type:'json_schema',name:'trainer_text',strict:true,schema}}}),signal:AbortSignal.timeout(45000)});
 const raw=await response.json();if(!response.ok)throw Error(raw.error?.message||'AI response failed');
 const output=(raw.output||[]).flatMap(x=>x.content||[]).find(x=>x.type==='output_text')?.text||raw.output_text;
 if(raw.status==='incomplete'||!output)throw Error('No complete AI response');return JSON.parse(output);
}
const textResultSchema={type:'object',additionalProperties:false,required:['reply'],properties:{reply:{type:'string'}}};
app.post('/api/text/reply',requireAuth,callsLimiter,async(req,res)=>{
 try{const data=validatedTextInput(req.body);const customer=data.messages.find(m=>m.role==='customer');
 const result=await textAI(`You are a fictional car-shopping CUSTOMER replying by SMS, not a coach. Situation: ${textTopics[data.scenario]}. Difficulty: ${textDifficulty[data.difficulty]}. Language: ${data.language==='es'?'Spanish':'English'}. Stay in the requested language, keep all texts brief (usually one or two sentences), realistic, and avoid repetitive praise. Never invent verified inventory, pricing, dealer policies, discounts, or financing approvals. Keep the same fictional customer identity and history based on the conversation. If there are no prior messages, introduce yourself as a fictional first name and initiate a short inquiry appropriate to the situation. Never give coaching, never speak as the salesperson. Reply JSON.`,{...data,hasExistingCustomer:!!customer},textResultSchema);
 res.json({reply:String(result.reply||'').slice(0,700)});
 }catch(e){console.error('Text reply:',e.message);res.status(502).json({error:'Unable to generate customer response. Check settings and try again.'})}
});
const coachSchema={type:'object',additionalProperties:false,required:['assessment','suggestion','reason'],properties:{assessment:{type:'string'},suggestion:{type:'string'},reason:{type:'string'}}};
app.post('/api/text/coach',requireAuth,callsLimiter,async(req,res)=>{
 try{const data=validatedTextInput(req.body);const draft=String(req.body?.draft||'').slice(0,1500);
 const result=await textAI(`You coach dealership text etiquette. Provide a concise, honest tone assessment of the proposed draft, a short natural suggested text in ${data.language==='es'?'Spanish':'English'} and a one-sentence rationale in English. If price, inventory, taxes, fee, discount, approval or warranty details are unverified, NEVER invent numbers or claim availability. Recommend transparency, helpful next steps, permission-based appointment setting, and conversational brevity. The suggested text must be copy-ready, with no markdown or placeholders unless absolutely needed for missing facts. Do not imply an actual customer message has been sent.`,{...data,draft},coachSchema);res.json(result);
 }catch(e){console.error('Text coaching:',e.message);res.status(502).json({error:'Unable to provide coaching right now'})}
});
const textScoreSchema={type:'object',additionalProperties:false,required:['scores','outcome','strength','improvement','example'],properties:{scores:{type:'object',additionalProperties:false,required:['tone','clarity','rapport','discovery','objections','appointment'],properties:Object.fromEntries(['tone','clarity','rapport','discovery','objections','appointment'].map(k=>[k,{type:'integer'}]))},outcome:{type:'string'},strength:{type:'string'},improvement:{type:'string'},example:{type:'string'}}};
app.post('/api/text/finish',requireAuth,callsLimiter,async(req,res)=>{
 try{const data=validatedTextInput(req.body);const mode=req.body?.mode==='coaching'?'coaching':'practice';if(data.messages.filter(m=>m.role==='salesperson').length<1)return res.status(400).json({error:'Send a message before finishing'});
 const weights={tone:20,clarity:15,rapport:15,discovery:15,objections:15,appointment:20};
 const score=await textAI(`Score a fictional sales text conversation strictly from the salesperson messages. Award integer scores within maxima ${JSON.stringify(weights)}. Be tough but fair; never assume a booked appointment. Evaluate whether tone is warm, not pushy; clarity and professionalism; rapport; discovery; objections; actionable appropriate next step. Avoid inventing pricing or finance facts. This is ${mode} mode: in coached mode, assistance was available, so note that this is assisted practice in outcome. Output outcome, strength, improvement in English; sample reply in ${data.language==='es'?'Spanish':'English'} only.`,data,textScoreSchema);
 for(const [k,max] of Object.entries(weights))score.scores[k]=Math.min(max,Math.max(0,Math.round(Number(score.scores[k])||0)));
 score.total=Object.values(score.scores).reduce((a,b)=>a+b,0);score.mode=mode;
 const record={user_id:req.userId,scenario:data.scenario,difficulty:data.difficulty,language:data.language,mode,total_score:score.total,scores:score.scores,outcome:score.outcome,strength:score.strength,improvement:score.improvement,example:score.example,conversation:data.messages};
 const saved=await fetch(`${supabaseUrl}/rest/v1/text_sessions`,{method:'POST',headers:{...authHeaders(req.authToken),'Content-Type':'application/json','Prefer':'return=minimal'},body:JSON.stringify(record)});
 if(!saved.ok){console.error('Text save error',saved.status,(await saved.text()).slice(0,300));score.save_warning='Score generated but could not be saved. Check the Supabase SQL setup.'}
 res.json(score);
 }catch(e){console.error('Text score:',e.message);res.status(502).json({error:'Could not complete text evaluation'})}
});
app.get('/api/text/history',requireAuth,async(req,res)=>{
 try{const r=await fetch(`${supabaseUrl}/rest/v1/text_sessions?user_id=eq.${encodeURIComponent(req.userId)}&select=id,created_at,scenario,difficulty,language,mode,total_score,scores,outcome,strength,improvement,example,conversation&order=created_at.desc&limit=30`,{headers:authHeaders(req.authToken)});if(!r.ok)throw Error(`Supabase ${r.status}`);res.json(await r.json())}catch(e){console.error('Text history',e);res.status(502).json({error:'Could not load text sessions'})}
});

// Reuse the existing text_sessions table and its employee ownership policies.
// No schema changes or new credentials are required for Objection Lab.
const sessionSecret=process.env.OBJECTION_SESSION_SECRET||process.env.COOKIE_SECRET||crypto.randomBytes(32).toString('hex');
if(!process.env.OBJECTION_SESSION_SECRET&&!process.env.COOKIE_SECRET)console.warn('Set OBJECTION_SESSION_SECRET to retain objection drills across server restarts');
const objectionService=createObjectionService({secret:sessionSecret,ai:textAI,
 async find(id,userId,token){
  const r=await fetch(`${supabaseUrl}/rest/v1/text_sessions?id=eq.${id}&user_id=eq.${encodeURIComponent(userId)}&select=*&limit=1`,{headers:authHeaders(token),signal:AbortSignal.timeout(15000)});
  if(!r.ok)throw Error('Unable to check saved review');return (await r.json())[0]||null;
 },
 async save(record,token){
  const r=await fetch(`${supabaseUrl}/rest/v1/text_sessions`,{method:'POST',headers:{...authHeaders(token),'Content-Type':'application/json','Prefer':'resolution=ignore-duplicates,return=minimal'},body:JSON.stringify(record),signal:AbortSignal.timeout(15000)});
  if(!r.ok)throw Error('Unable to save objection review');
 }
});
registerObjectionRoutes(app,{requireAuth,limiter:objectionLimiter,service:objectionService});
const port=Number(process.env.PORT)||3000;
export {app};
if(process.argv[1]===fileURLToPath(import.meta.url))app.listen(port,()=>console.log(`ObjectionIQ available at http://localhost:${port}`));
