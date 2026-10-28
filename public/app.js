const $=id=>document.getElementById(id);
const scenarios=[['internet','🌐','Internet Lead'],['unsold','↩️','Unsold Follow-Up'],['cold','📞','Cold Call'],['upgrade','🚘','Customer Upgrade'],['price','💰','Price Shopper'],['marketplace','💬','Marketplace Lead'],['service','🔧','Service Upgrade'],['random','🎲','Surprise Scenario']];
const dimensions=[['opening','Opening',15],['rapport','Rapport',15],['discovery','Needs Discovery',20],['objections','Objection Handling',20],['appointment','Appointment Setting',20],['closing','Closing',10]];
let scenario='internet',difficulty='realistic',language='en',pc,dc,localStream,timerInterval,startTime,turns=[],items=new Map(),active=false,finishing=false;
let customerSpeaking=false,userMuted=false,unmuteDelay=null;
function text(el,value){$(el).textContent=value}
function show(page){for(const id of ['login','app'])$(id).hidden=id!==page}
function setPanel(id){for(const p of ['setup','call','results'])$(p).hidden=p!==id}
function error(e){alert(typeof e==='string'?e:(e?.message||'Unexpected error'))}
function escapeHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function addLanguagePicker(){
 const difficultyPicker=$('difficulties');if(!difficultyPicker||document.getElementById('sales-language'))return;
 const section=document.createElement('div'); section.id='sales-language';section.style.margin='24px 0 8px';
 section.innerHTML=`<div class="subheading">CUSTOMER LANGUAGE / IDIOMA DEL CLIENTE</div><div style="display:flex;gap:12px;flex-wrap:wrap"><button type="button" data-lang="en" class="secondary" style="min-width:130px">English</button><button type="button" data-lang="es" class="secondary" style="min-width:130px">Español</button></div><p style="font-size:12px;color:#94a2b8">Spanish mode: the customer speaks Spanish; coaching and scores remain in English.</p>`;
 difficultyPicker.insertAdjacentElement('afterend',section);
 section.querySelectorAll('[data-lang]').forEach(button=>button.addEventListener('click',()=>{language=button.dataset.lang;syncLanguagePicker()}));
 syncLanguagePicker();
}
function syncLanguagePicker(){document.querySelectorAll('#sales-language [data-lang]').forEach(b=>{const selected=b.dataset.lang===language;b.style.borderColor=selected?'#52b3ee':'#45607c';b.style.background=selected?'#143550':'#263447';b.setAttribute('aria-pressed',String(selected))})}
function renderChoices(){$('scenarios').innerHTML=scenarios.map(([id,ico,label])=>`<button class="scenario ${id===scenario?'selected':''}" data-id="${id}"><span class="ico">${ico}</span><b>${label}</b></button>`).join('');document.querySelectorAll('.scenario').forEach(b=>b.onclick=()=>{scenario=b.dataset.id;renderChoices()});document.querySelectorAll('[data-difficulty]').forEach(b=>b.classList.toggle('selected',b.dataset.difficulty===difficulty))}
document.querySelectorAll('[data-difficulty]').forEach(b=>b.onclick=()=>{difficulty=b.dataset.difficulty;renderChoices()});
$('name').type='email';$('name').placeholder='Your email address';$('name').autocomplete='email';$('passcode').placeholder='Your personal password';$('passcode').autocomplete='current-password';document.querySelector('label:has(#name)').firstChild.textContent='Email address';document.querySelector('label:has(#passcode)').firstChild.textContent='Password';
$('loginForm').onsubmit=async e=>{e.preventDefault();try{const r=await fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:$('name').value,password:$('passcode').value})});const d=await r.json();if(!r.ok)throw Error(d.error);text('userName',d.name);show('app');renderHistory()}catch(e){error(e)}};
$('logout').onclick=async()=>{await fetch('/api/logout',{method:'POST'});if(active)await finish(false);show('login')};
function addTurn(key,speaker,line){if(!line?.trim())return;items.set(key,{speaker,text:line.trim()});renderTranscript()}
function renderTranscript(){turns=[...items.values()];$('transcript').innerHTML=turns.map(t=>`<div class="turn"><b>${t.speaker}</b><p>${escapeHtml(t.text)}</p></div>`).join('');$('transcript').scrollTop=$('transcript').scrollHeight}
// Echo guard: no microphone audio is sent to the AI while its voice is audible.
// We use output_audio_buffer events rather than response.done: response.done can arrive before playback finishes.
function applyMicState(){const track=localStream?.getAudioTracks()[0];if(track)track.enabled=!userMuted&&!customerSpeaking; if(active&&!finishing)text('connectionStatus',customerSpeaking?'Customer speaking — microphone paused to prevent echo':userMuted?'Microphone muted':'Customer connected — your turn to speak')}
function setCustomerSpeaking(speaking){clearTimeout(unmuteDelay);if(speaking){customerSpeaking=true;applyMicState()}else{unmuteDelay=setTimeout(()=>{customerSpeaking=false;applyMicState()},350)}}
function handleEvent(ev){let d;try{d=JSON.parse(ev.data)}catch{return}
 if(d.type==='output_audio_buffer.started')setCustomerSpeaking(true);
 if(d.type==='output_audio_buffer.stopped'||d.type==='output_audio_buffer.cleared')setCustomerSpeaking(false);
 if(d.type==='conversation.item.input_audio_transcription.completed')addTurn(d.item_id||crypto.randomUUID(),'Salesperson',d.transcript);
 if(d.type==='response.output_audio_transcript.done')addTurn(d.item_id||crypto.randomUUID(),'Customer',d.transcript);
 if(d.type==='conversation.item.created'&&d.item?.role==='assistant'&&d.item?.content){const content=d.item.content.map(c=>c.transcript||c.text||'').join(' ');if(content)addTurn(d.item.id,'Customer',content)}
 if(d.type==='error')console.warn('Realtime event error',d.error);
}
async function start(){if(active)return;$('start').disabled=true;items=new Map();turns=[];renderTranscript();setPanel('call');text('callScenario',scenarios.find(x=>x[0]===scenario)[2]);text('connectionStatus','Connecting microphone...');customerSpeaking=false;userMuted=false;
 try{
 localStream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
 pc=new RTCPeerConnection();localStream.getTracks().forEach(track=>pc.addTrack(track,localStream));pc.ontrack=e=>{$('remoteAudio').srcObject=e.streams[0];$('remoteAudio').play().catch(()=>{})};
 dc=pc.createDataChannel('oai-events');dc.onmessage=handleEvent;dc.onopen=()=>{text('connectionStatus','Customer connected — your turn to speak');active=true;startTime=Date.now();timerInterval=setInterval(()=>{const t=Math.floor((Date.now()-startTime)/1000);text('timer',`${String(Math.floor(t/60)).padStart(2,'0')}:${String(t%60).padStart(2,'0')}`)},1000)};
 pc.onconnectionstatechange=()=>{if(['failed','disconnected'].includes(pc.connectionState)&&!finishing)text('connectionStatus','Connection interrupted — you may end and score')};
 const offer=await pc.createOffer();await pc.setLocalDescription(offer);
 if(pc.iceGatheringState!=='complete')await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Microphone connection timed out')),10000);pc.onicegatheringstatechange=()=>{if(pc.iceGatheringState==='complete'){clearTimeout(timeout);resolve()}}});
 const r=await fetch('/api/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({sdp:pc.localDescription.sdp,scenario,difficulty,language})});if(!r.ok){const d=await r.json().catch(()=>({}));throw Error(d.error||'Voice setup failed')};const sdp=await r.text();await pc.setRemoteDescription({type:'answer',sdp});
 }catch(e){cleanup();setPanel('setup');error(e)}finally{$('start').disabled=false}}
function cleanup(){clearInterval(timerInterval);clearTimeout(unmuteDelay);if(dc&&dc.readyState==='open')dc.close();if(pc)pc.close();if(localStream)localStream.getTracks().forEach(x=>x.stop());$('remoteAudio').srcObject=null;active=false;pc=null;dc=null;localStream=null;customerSpeaking=false;userMuted=false}
async function finish(doScore=true){if(finishing)return;finishing=true;text('connectionStatus','Finishing call...');if(dc?.readyState==='open'){try{dc.send(JSON.stringify({type:'session.close'}))}catch{}}await new Promise(r=>setTimeout(r,1400));cleanup();if(!doScore){finishing=false;return}setPanel('results');text('totalScore','…');text('outcome','Reviewing your conversation...');$('scoreRows').innerHTML='';text('strength','');text('improvement','');text('example','');text('scoreNotes','');
 try{const r=await fetch('/api/score',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({transcript:turns,scenario,difficulty,language})});const d=await r.json();if(!r.ok)throw Error(d.error||'Scoring failed');showScore(d);if(d.save_warning)text('scoreNotes',`${d.notes} ${d.save_warning}`);await renderHistory()}catch(e){text('totalScore','—');text('outcome',e.message+'. Your call transcript is displayed during the call but not stored. Try another call.')}finally{finishing=false}}
function showScore(d){text('totalScore',d.total);text('outcome',d.outcome);$('scoreRows').innerHTML=dimensions.map(([key,label,max])=>`<div class="scoreLine"><div class="scoreTitle"><span>${label}</span><b>${d.scores[key]} / ${max}</b></div><div class="bar"><div style="width:${100*d.scores[key]/max}%"></div></div></div>`).join('');text('strength',d.strength);text('improvement',d.improvement);text('example',d.example);text('scoreNotes',d.notes)}
async function renderHistory(){
 $('history').textContent='Loading your personal history...';
 try{const r=await fetch('/api/history');if(!r.ok)throw Error('History temporarily unavailable');const history=await r.json();
 $('history').innerHTML=history.length?history.map(h=>`<div class="historyItem"><div>${escapeHtml(scenarios.find(x=>x[0]===h.scenario)?.[2]||h.scenario)}<small>${new Date(h.created_at).toLocaleDateString()} · ${escapeHtml(h.difficulty)} · ${h.language==='es'?'Español':'English'}</small></div><b>${Number(h.total_score)}/100</b></div>`).join(''):'<p>No saved calls yet. Start your first practice session.</p>';
 }catch(e){$('history').textContent=e.message}
}
$('start').onclick=start;$('end').onclick=()=>finish(true);$('again').onclick=()=>setPanel('setup');$('mute').onclick=()=>{userMuted=!userMuted;text('mute',userMuted?'Unmute mic':'Mute mic');applyMicState()};
(async()=>{try{const r=await fetch('/api/me');if(r.ok){const d=await r.json();text('userName',d.name);show('app');renderHistory()}else show('login')}catch{show('login')}})();renderChoices();addLanguagePicker();
