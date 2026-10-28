import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const app = express();
const root = path.dirname(fileURLToPath(import.meta.url));
app.disable('x-powered-by');
app.use(helmet({contentSecurityPolicy:false}));
app.use(express.json({limit:'120kb'}));
app.use(express.static(path.join(root,'public'), {index:false}));
const supabaseUrl=(process.env.SUPABASE_URL||'').replace(/\/$/,'');
const supabaseKey=process.env.SUPABASE_PUBLISHABLE_KEY;
if(!supabaseUrl.startsWith('https://')||!supabaseKey)console.warn('Supabase not configured: login unavailable until environment variables are present');
const limiter=rateLimit({windowMs:15*60*1000,limit:20,standardHeaders:'draft-7',legacyHeaders:false});
const callsLimiter=rateLimit({windowMs:60*60*1000,limit:25,standardHeaders:'draft-7',legacyHeaders:false});
const cookieOptions={httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'strict',path:'/'};
const cookie=(req,name)=>(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith(name+'='))?.slice(name.length+1);
const authHeaders=(token)=>({'apikey':supabaseKey,'Authorization':`Bearer ${token}`});
async function supabaseAuth(endpoint,method,body,token){
 const r=await fetch(`${supabaseUrl}/auth/v1/${endpoint}`,{method,headers:{'Content-Type':'application/json',...(token?authHeaders(token):{'apikey':supabaseKey})},body:body?JSON.stringify(body):undefined});
 return {ok:r.ok,status:r.status,data:await r.json().catch(()=>({}))};
}
function saveSession(res,data){res.cookie('trainer_access',data.access_token,{...cookieOptions,maxAge:60*60*1000});res.cookie('trainer_refresh',data.refresh_token,{...cookieOptions,maxAge:30*24*60*60*1000});}
async function requireAuth(req,res,next){
 if(!supabaseKey)return res.status(503).json({error:'Supabase configuration missing'});
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
 try{const r=await fetch(`${supabaseUrl}/rest/v1/call_scores?select=created_at,scenario,difficulty,language,total_score&order=created_at.desc&limit=30`,{headers:authHeaders(req.authToken)});
 if(!r.ok)throw Error(`Supabase ${r.status}`);res.json(await r.json());}catch(e){console.error(e);res.status(502).json({error:'Unable to load personal scores'})}
});
const scenarios={
 internet:{label:'Internet Lead',setup:'You submitted an online inquiry on a 2026 Chevrolet Equinox LT. You are cross-shopping a Honda CR-V. You can visit but dislike pushy sales calls.'},
 unsold:{label:'Unsold Follow-Up',setup:'You visited three days ago, drove a Silverado 1500, and left without purchasing. You are uncertain about payments and are considering waiting.'},
 cold:{label:'Cold Call',setup:'You are receiving a dealership prospecting call unexpectedly. You own a 2020 Chevrolet Traverse and did not request the call.'},
 upgrade:{label:'Previous Customer Upgrade',setup:'You bought a 2022 Chevrolet Tahoe from the dealership. You are somewhat interested in newer technology but are concerned about increasing your payment.'},
 price:{label:'Price Shopper',setup:'You want the best out-the-door price for a 2026 Colorado. You are comparing three dealers and are reluctant to come in before getting numbers.'},
 marketplace:{label:'Marketplace Lead',setup:'You messaged about a used Cadillac XT5 on Facebook Marketplace. You want to know whether the listed price is real and have a trade-in.'},
 service:{label:'Service Upgrade',setup:'Your 2018 Silverado is in service and a sales representative calls to discuss a possible upgrade. You like your truck and are skeptical.'},
 random:{label:'Random Scenario',setup:'Invent a realistic Chevrolet, Cadillac or Lincoln lead situation with a plausible customer goal and hidden objection. Do not tell salesperson your secrets.'}
};
const difficulties={easy:'Be fairly friendly, cooperative, and open to an appointment when invited with a clear reason.',realistic:'Be a believable busy shopper. Offer moderate resistance and 1-2 natural objections, reveal information only when asked, reward good questions.',hard:'Be skeptical, short on time, and protective of details. Raise substantial but reasonable objections. Agree to next steps only when the salesperson earns trust and creates a clear reason.'};
app.post('/api/session',requireAuth,callsLimiter,async(req,res)=>{
 const {sdp,scenario,difficulty,language='en'}=req.body||{};
 if(typeof sdp!=='string'||sdp.length<100||sdp.length>30000||!sdp.startsWith('v='))return res.status(400).json({error:'Invalid audio connection offer'});
 if(!scenarios[scenario]||!difficulties[difficulty]||!['en','es'].includes(language))return res.status(400).json({error:'Select a valid scenario, difficulty and language'});
 if(!process.env.OPENAI_API_KEY)return res.status(503).json({error:'Server API key not configured'});
 const languageInstructions = language === 'es' ? `IMPORTANT LANGUAGE RULE: You are a Spanish-speaking customer in Wichita, Kansas. Speak natural conversational Latin American Spanish (neutral Mexican/US Spanish), not a word-for-word English translation. Open and continue the conversation in Spanish, including pricing, trade-in, financing and appointment discussions. Understand English if the salesperson needs a clarification, but return to Spanish for normal conversation. Do not coach or translate unless directly asked IN CHARACTER. The salesperson may speak imperfect Spanish; react like a patient but realistic customer, and do not switch to English simply because they hesitate. ` : `IMPORTANT LANGUAGE RULE: Speak natural conversational American English throughout the call.`;
 const instructions=`${languageInstructions} You are playing a FICTIONAL CUSTOMER in a live PHONE CALL with a Chevrolet Cadillac Lincoln dealership salesperson. Only act as the customer; never speak as a coach, assistant, evaluator, or narrator. Scenario: ${scenarios[scenario].setup} Difficulty: ${difficulties[difficulty]} Create a natural first name, believable circumstances and a consistent private backstory. Do not share this scenario briefing. Do not mention being AI or roleplaying. Start the call by waiting for the SALESPERSON to introduce themself. Speak in short, realistic, conversational telephone turns. Do not give away objections or budget unsolicited. Respond specifically to questions, including dealership pricing and visit logistics, without fabricating a confirmed dealership offer, inventory availability, real credit approval or loan approval. When salesperson asks for an appointment, react based on the quality of their approach. Do not hand them success automatically. When the salesperson pauses for a breath or says 'uh' or 'um', wait for them to finish their thought; don't assume a brief hesitation is the end of the turn. Be patient rather than interrupting. Avoid long monologues. If they say 'End call', say a brief goodbye, nothing else. Never provide coaching or scores.`;
 try{
   const form=new FormData(); form.set('sdp',sdp);form.set('session',JSON.stringify({type:'realtime',model:process.env.REALTIME_MODEL||'gpt-realtime-2.1',instructions,audio:{output:{voice:'marin'},input:{transcription:{model:'gpt-4o-mini-transcribe',language},turn_detection:{type:'semantic_vad',eagerness:'low',create_response:true,interrupt_response:false}}}}));
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
const port=Number(process.env.PORT)||3000;
app.listen(port,()=>console.log(`Sales Call Trainer available at http://localhost:${port}`));
