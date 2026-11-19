const {scoreDeal}=require('./lib/scoring.cjs');
const {api,loadDeal,idOrThrow}=require('./lib/hubspot.cjs');
exports.main=async context=>{
  const id=idOrThrow(context?.parameters?.dealId),d=await loadDeal(id),a=scoreDeal(d);
  if(a.status==='excluded')return {dealId:id,saved:false,reason:'Closed deal excluded'};
  const old=Number(d.properties.sri_risk_priority);
  const same=d.properties.sri_risk_priority!==undefined && Number.isFinite(old) && old===a.score && d.properties.sri_risk_level===a.level;
  const oldStatus=d.properties.sri_assessment_status;
  const status=same&&['reviewed','dismissed'].includes(oldStatus)?oldStatus:'pending';
  await api('/crm/v3/objects/deals/'+id,{method:'PATCH',body:{properties:{
    sri_risk_priority:String(a.score),
    sri_risk_level:a.level,
    sri_risk_factors:a.flags.map(f=>f.points+' pts | '+f.detail).join('\n')||'No risk factors',
    sri_recommended_action:a.recommendation,
    sri_assessment_status:status,
    sri_last_assessed:a.assessedAt
  }}});
  return {dealId:id,dealName:d.properties.dealname||'Deal '+id,saved:true,...a,reviewStatus:status};
};
