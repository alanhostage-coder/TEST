'use strict';
/** Pure, deterministic deal attention. Scores are not forecast probabilities. */
const DEFAULT_RULES = Object.freeze({ missingFutureActivity:25, inactivity14d:20, overdueCloseDate:30, missingContacts:15, missingNextStep:10, staleStage30d:15 });
const DAY = 86400000;
const parseDate = value => { if (!value) return null; const d = new Date(value); return Number.isFinite(d.getTime()) ? d : null; };
const daysBetween = (a,b) => Math.floor((b-a)/DAY);
const isTrue = v => v === true || String(v||'').toLowerCase()==='true';
function scoreDeal(deal, opts={}) {
  if (!deal || typeof deal !== 'object') throw new TypeError('Deal required');
  const p=deal.properties||deal, now=parseDate(opts.now)||new Date(), rules={...DEFAULT_RULES,...(opts.rules||{})}, flags=[], quality=[];
  if (isTrue(p.hs_is_closed)||isTrue(deal.isClosed))
    return {score:0,level:'closed',flags:[],recommendation:'Closed deal. No assessment required.',assessedAt:now.toISOString(),status:'excluded',dataQuality:[],ruleVersion:'0.3.0'};
  const add=(id,points,detail,recommendation)=>flags.push({id,points,detail,recommendation});
  const next=parseDate(p.notes_next_activity_date);
  if (!next || next.getTime()<now.getTime()) add('missing_future_activity',rules.missingFutureActivity,'No future CRM activity recorded','Agree and schedule the next client-facing activity.');
  const contacted=parseDate(p.notes_last_contacted),created=parseDate(p.createdate||deal.createdAt);
  if (contacted && daysBetween(contacted,now)>=14) add('inactivity_14d',rules.inactivity14d,'Sales contact was '+daysBetween(contacted,now)+' days ago','Re-establish contact and log the discussion.');
  else if (!contacted && created && daysBetween(created,now)>=14) add('inactivity_14d',rules.inactivity14d,'No logged sales contact since creation','Confirm progress and log a call, meeting or sales email.');
  else if (!contacted && !created) quality.push('Contact activity freshness unknown.');
  const close=parseDate(p.closedate);
  const utcDay=d=>Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),d.getUTCDate());
  if (close && utcDay(close)<utcDay(now)) add('overdue_close_date',rules.overdueCloseDate,'Close date is in the past','Confirm the buying timeline and update the close date.');
  else if (!close) quality.push('Close date missing.');
  if (deal.contactCount===0) add('missing_contacts',rules.missingContacts,'No associated contacts','Associate the relevant buying contacts.');
  else if (deal.contactCount==null) quality.push('Contact count unavailable; no contact penalty applied.');
  if (!String(p.hs_next_step||'').trim()) add('missing_next_step',rules.missingNextStep,'Next step is blank','Record a clear next step, owner and date.');
  const stage=parseDate(p.hs_v2_date_entered_current_stage);
  if (stage && daysBetween(stage,now)>=30) add('stale_stage_30d',rules.staleStage30d,'Deal in current stage for '+daysBetween(stage,now)+' days','Review stage criteria and agree a progression milestone.');
  else if (!stage) quality.push('Stage age unavailable.');
  flags.sort((a,b)=>b.points-a.points||a.id.localeCompare(b.id));
  const score=Math.min(100,flags.reduce((sum,item)=>sum+item.points,0));
  return {score,level:score>=60?'high':score>=30?'medium':'low',flags,recommendation:flags[0]?.recommendation||'Keep the next agreed activity on track.',assessedAt:now.toISOString(),status:'assessed',dataQuality:quality,ruleVersion:'0.3.0'};
}
module.exports={scoreDeal,DEFAULT_RULES,parseDate,daysBetween};
