'use strict';
const ROOT='https://api.hubapi.com';
function token(){const t=process.env.PRIVATE_APP_ACCESS_TOKEN;if(!t)throw new Error('HubSpot app not installed or token unavailable');return t;}
function idOrThrow(id){if(!/^\d{1,20}$/.test(String(id)))throw new Error('Invalid deal ID');return String(id);}
async function api(path,options={}) {
  const r=await fetch(ROOT+path,{method:options.method||'GET',headers:{Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:options.body?JSON.stringify(options.body):undefined});
  if(!r.ok)throw new Error('HubSpot API '+r.status+': '+(await r.text()).slice(0,250));
  return r.status===204?null:r.json();
}
const DEAL_PROPS=['dealname','dealstage','pipeline','amount','hs_is_closed','createdate','closedate','notes_last_contacted','notes_next_activity_date','hs_next_step','hs_v2_date_entered_current_stage','sri_risk_priority','sri_risk_level','sri_assessment_status','sri_last_assessed'];
async function loadDeal(id){
  const safe=idOrThrow(id);
  const result=await api('/crm/v3/objects/deals/'+safe+'?'+DEAL_PROPS.map(p=>'properties='+encodeURIComponent(p)).join('&'));
  let contactCount=null;
  try {
    const a=await api('/crm/v4/objects/deals/'+safe+'/associations/contacts?limit=100');
    contactCount=a.paging?.next?null:(a.results||[]).length;
  } catch(e){ console.warn('Contact count unavailable; skipping penalty:',String(e)); }
  return {...result,contactCount};
}
module.exports={api,idOrThrow,loadDeal,DEAL_PROPS};
