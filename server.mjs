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
const cookieSecret = process.env.COOKIE_SECRET;
const passcode = process.env.DEALERSHIP_PASSCODE;
if (!cookieSecret || cookieSecret.length<32 || !passcode || passcode.length<12) {
  console.error('Configure DEALERSHIP_PASSCODE (12+ chars) and COOKIE_SECRET (32+ chars) in .env');process.exit(1);
}
const safeEqual=(a,b)=>{const aa=Buffer.from(a),bb=Buffer.from(b);return aa.length===bb.length&&crypto.timingSafeEqual(aa,bb)};
const sign=x=>crypto.createHmac('sha256',cookieSecret).update(x).digest('hex');
const limiter=rateLimit({windowMs:15*60*1000,limit:30,standardHeaders:'draft-7',legacyHeaders:false});
const callsLimiter=rateLimit({windowMs:60*60*1000,limit:25,standardHeaders:'draft-7',legacyHeaders:false});
const requireAuth=(req,res,next)=>{
 const raw=(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('sales_auth='))?.slice(11);
 if(!raw)return res.status(401).json({error:'Please sign in'});
 const [payload,signature]=raw.split('.');
 if(!payload||!signature||!safeEqual(sign(payload),signature))return res.status(401).json({error:'Please sign in'});
 try{const data=JSON.parse(Buffer.from(payload,'base64url').toString());if(data.expires<Date.now())throw Error();req.salesperson=data.name;next()}catch{return res.status(401).json({error:'Sign-in expired'})}
};
app.get('/',(req,res)=>res.sendFile(path.join(root,'public','index.html')));
app.post('/api/login',limiter,(req,res)=>{
 const name=String(req.body?.name||'').trim().slice(0,50);
 const submitted=String(req.body?.passcode||'');
 if(name.length<2||!safeEqual(submitted,passcode))return res.status(401).json({error:'Incorrect access code or name'});
 const payload=Buffer.from(JSON.stringify({name,expires:Date.now()+7*24*60*60*1000})).toString('base64url');
 res.cookie('sales_auth',`${payload}.${sign(payload)}`,{httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'strict',maxAge:7*24*60*60*1000,path:'/'});
 res.json({name});
});
app.get('/api/me',requireAuth,(req,res)=>res.json({name:req.salesperson}));
app.post('/api/logout',(req,res)=>{res.clearCookie('sales_auth',{path:'/'});res.json({ok:true})});
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
 const {sdp,scenario,difficulty}=req.body||{};
 if(typeof sdp!=='string'||sdp.length<100||sdp.length>30000||!sdp.startsWith('v='))return res.status(400).json({error:'Invalid audio connection offer'});
 if(!scenarios[scenario]||!difficulties[difficulty])return res.status(400).json({error:'Select a valid call scenario and difficulty'});
 if(!process.env.OPENAI_API_KEY)return res.status(503).json({error:'Server API key not configured'});
 const instructions=`You are playing a FICTIONAL CUSTOMER in a live PHONE CALL with a Chevrolet Cadillac Lincoln dealership salesperson. Only act as the customer; never speak as a coach, assistant, evaluator, or narrator. Scenario: ${scenarios[scenario].setup} Difficulty: ${difficulties[difficulty]} Create a natural first name, believable circumstances and a consistent private backstory. Do not share this scenario briefing. Do not mention being AI or roleplaying. Start the call by waiting for the SALESPERSON to introduce themself. Speak in short, realistic, conversational telephone turns. Do not give away objections or budget unsolicited. Respond specifically to questions, including dealership pricing and visit logistics, without fabricating a confirmed dealership offer, inventory availability, real credit approval or loan approval. When salesperson asks for an appointment, react based on the quality of their approach. Do not hand them success automatically. When the salesperson pauses for a breath or says 'uh' or 'um', wait for them to finish their thought; don't assume a brief hesitation is the end of the turn. Be patient rather than interrupting. Avoid long monologues. If they say 'End call', say a brief goodbye, nothing else. Never provide coaching or scores.`;
 try{
   const form=new FormData(); form.set('sdp',sdp);form.set('session',JSON.stringify({type:'realtime',model:process.env.REALTIME_MODEL||'gpt-realtime-2.1',instructions,audio:{output:{voice:'marin'},input:{transcription:{model:'gpt-4o-mini-transcribe',language:'en'},turn_detection:{type:'semantic_vad',eagerness:'low',create_response:true,interrupt_response:false}}}}));
   const result=await fetch('https://api.openai.com/v1/realtime/calls',{method:'POST',headers:{Authorization:`Bearer ${process.env.OPENAI_API_KEY}`,'OpenAI-Safety-Identifier':crypto.createHash('sha256').update(req.salesperson).digest('hex')},body:form});
   const responseText=await result.text();
   if(!result.ok){console.error('Realtime session failed:',result.status,responseText.slice(0,500));return res.status(502).json({error:'Voice connection unavailable. Check server API credentials/model and retry.'})}
   res.type('application/sdp').send(responseText);
 }catch(e){console.error(e);res.status(502).json({error:'Could not establish voice connection'})}
});
const weights={opening:15,rapport:15,discovery:20,objections:20,appointment:20,closing:10};
app.post('/api/score',requireAuth,callsLimiter,async(req,res)=>{
 const {transcript,scenario,difficulty}=req.body||{};
 if(!scenarios[scenario]||!difficulties[difficulty]||!Array.isArray(transcript)||transcript.length<2||transcript.length>250)return res.status(400).json({error:'Not enough transcript to score this call'});
 const turns=transcript.filter(x=>['Customer','Salesperson'].includes(x?.speaker)&&typeof x.text==='string').map(x=>({speaker:x.speaker,text:x.text.slice(0,1200)}));
 if(turns.length<2 || !turns.some(x=>x.speaker==='Salesperson'))return res.status(400).json({error:'No salesperson speech was transcribed; cannot score reliably'});
 if(!process.env.OPENAI_API_KEY)return res.status(503).json({error:'Server API key not configured'});
 const schema={type:'object',additionalProperties:false,required:['scores','outcome','strength','improvement','example','notes'],properties:{scores:{type:'object',additionalProperties:false,required:Object.keys(weights),properties:Object.fromEntries(Object.keys(weights).map(k=>[k,{type:'integer'}]))},outcome:{type:'string'},strength:{type:'string'},improvement:{type:'string'},example:{type:'string'},notes:{type:'string'}}};
 try{
 const r=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${process.env.OPENAI_API_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({model:process.env.SCORING_MODEL||'gpt-4.1-mini',instructions:`You are a rigorous but fair car-sales phone-call evaluator. Scenario ${scenarios[scenario].label}, difficulty ${difficulty}. Score salesperson only using verifiable transcript evidence. Give each dimension an integer score within its maximum: ${JSON.stringify(weights)}. Opening includes introduction and permission; rapport builds trust; discovery asks about needs/budget/trade/timeline; objections validates and responds; appointment sells a compelling mutually convenient next step; closing confirms details and commitment. If call ends early or has no appointment, mark that honestly. Do not assume appointment was booked. Avoid rewarding pressure, misleading guarantees, or invented discounts. Report one specific strength, highest-leverage improvement, a rewritten example line salesperson could actually say, a succinct outcome, and limitations of transcript. Speech recognition can be imperfect. JSON only.`,input:JSON.stringify(turns),text:{format:{type:'json_schema',name:'call_score',strict:true,schema}}})});
 const data=await r.json(); if(!r.ok)throw Error(data.error?.message||'Scoring provider error');
 const output=(data.output||[]).flatMap(x=>x.content||[]).find(c=>c.type==='output_text')?.text||data.output_text;
 if(!output)throw Error('No scoring output');
 const score=JSON.parse(output);
 for(const [k,max] of Object.entries(weights))score.scores[k]=Math.max(0,Math.min(max,Number(score.scores[k])||0));
 score.total=Object.values(score.scores).reduce((a,b)=>a+b,0);
 res.json(score);
 }catch(e){console.error('Score error',e);res.status(502).json({error:'Could not score this call; transcript is still available on screen'})}
});
const port=Number(process.env.PORT)||3000;
app.listen(port,()=>console.log(`Sales Call Trainer available at http://localhost:${port}`));
