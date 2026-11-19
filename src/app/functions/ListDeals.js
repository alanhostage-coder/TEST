const {api}=require('./lib/hubspot.cjs');
exports.main=async context=>{
  const requested=Number(context?.parameters?.limit||20),limit=Number.isFinite(requested)?Math.max(1,Math.min(30,requested)):20;
  const after=context?.parameters?.after;
  if(after!=null&&!/^\d+$/.test(String(after)))throw new Error('Invalid paging cursor');
  const body={limit,properties:['dealname','dealstage','pipeline','amount','sri_risk_priority','sri_risk_level','sri_assessment_status','sri_last_assessed'],sorts:[{propertyName:'hs_lastmodifieddate',direction:'DESCENDING'}]};
  if(after!=null)body.after=String(after);
  const data=await api('/crm/v3/objects/deals/search',{method:'POST',body});
  return {deals:(data.results||[]).map(x=>({id:x.id,...x.properties})),nextCursor:data.paging?.next?.after||null,total:data.total||0};
};
