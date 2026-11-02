// Synthetic server contracts shared by offline UI previews and Swift decoder checks.
import {createMarketplaceService,marketplaceRubric} from '../marketplace.mjs';
export function marketplacePreviewService(records=[]){
 return createMarketplaceService({secret:'offline-preview-only',random:()=>.1,
  async ai(instructions,payload,schema){
   if(schema.properties.reply)return {reply:payload.messages.length<4?'Would you take $35,000? I saw a similar truck advertised for less.':'Thanks. An itemized comparison would help before I decide.',offerCents:payload.messages.length<4?3500000:0};
   if(schema.properties.focus)return {focus:'comparison'};
   const index=payload.messages.findIndex(m=>m.role==='salesperson');return {categories:Object.fromEntries(Object.entries(marketplaceRubric).map(([k,v])=>[k,{score:Math.round(v.max*.7),messageIndex:index,quote:payload.messages[index].text,assessment:'You directly answered the availability question and invited a useful next step.',advice:'Keep your next question tied to what the customer actually asks.',alternative:'Is the other truck similar in mileage and equipment?'}]))};
  },async find(id,user){return records.find(r=>r.id===id&&r.user_id===user)||null;},async save(r){if(!records.some(x=>x.id===r.id))records.push({...r,created_at:'2026-11-02T15:00:00Z'});}
 });
}
