const {api,idOrThrow}=require('./lib/hubspot.cjs');
exports.main=async context=>{
  const dealId=idOrThrow(context?.parameters?.dealId);
  const props=['dealname','hs_is_closed','sri_risk_priority','sri_risk_level',
    'sri_assessment_status','sri_last_assessed'];
  const url='/crm/v3/objects/deals/'+dealId+'?'+props.map(p=>'properties='+encodeURIComponent(p)).join('&');
  const d=await api(url),p=d.properties||{};
  if(!p.sri_last_assessed||p.sri_risk_priority==null||p.sri_risk_level==null)
    return {reviewed:false,reason:'Save an assessment before marking it reviewed.'};
  if(String(p.hs_is_closed)==='true')
    return {reviewed:false,reason:'Closed deals cannot be reviewed.'};
  if(!context?.parameters?.expectedLastAssessed||
      context.parameters.expectedLastAssessed!==p.sri_last_assessed)
    return {reviewed:false,reason:'Assessment has changed or the review token is missing. Refresh before reviewing.'};
  if(p.sri_assessment_status==='reviewed')return {reviewed:true,alreadyReviewed:true};
  await api('/crm/v3/objects/deals/'+dealId,{method:'PATCH',body:{properties:{sri_assessment_status:'reviewed'}}});
  return {reviewed:true,dealId,reviewStatus:'reviewed'};
};
