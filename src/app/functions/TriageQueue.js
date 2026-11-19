const {api}=require('./lib/hubspot.cjs');
const {buildTriage,MAX_SCAN}=require('./lib/triage.cjs');
exports.main=async()=>{
  // On-demand, capped snapshot. No CRM writes, no AI actions, no credit usage.
  const body={
    limit:MAX_SCAN,
    filterGroups:[{filters:[{propertyName:'hs_is_closed',operator:'EQ',value:'false'}]}],
    properties:['dealname','amount','dealstage','pipeline','hubspot_owner_id','hs_is_closed',
      'createdate','closedate','notes_last_contacted','notes_next_activity_date',
      'hs_next_step','hs_v2_date_entered_current_stage',
      'sri_risk_priority','sri_risk_level','sri_assessment_status','sri_last_assessed'],
    sorts:[{propertyName:'hs_lastmodifieddate',direction:'DESCENDING'}]
  };
  const data=await api('/crm/v3/objects/deals/search',{method:'POST',body});
  const ranked=buildTriage(data.results||[]);
  const totalOpen=Number(data.total||0);
  return {...ranked,totalOpen,scanned:(data.results||[]).length,
    incomplete:!!data.paging?.next||totalOpen>(data.results||[]).length,
    scope:'Most recently modified open Deals, at most 100. Ranking is within the scanned set. Contact association penalties are excluded until individual Deal review.',
    assessedAt:new Date().toISOString(),
    mode:'real'};
};
