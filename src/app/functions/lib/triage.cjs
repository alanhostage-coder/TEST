'use strict';
const {scoreDeal}=require('./scoring.cjs');
const MAX_SCAN=100;
const amountOf=value=>{
  const v=Number(String(value??'').replaceAll(',',''));
  return Number.isFinite(v)&&v>0?v:0;
};
function buildTriage(results,options={}){
  const now=options.now||new Date();
  const assessed=results.filter(d=>String(d?.properties?.hs_is_closed||'').toLowerCase()!=='true')
    .map(d=>{
      // Association coverage is unknown in bulk search. Never invent a contact penalty.
      const assessment=scoreDeal({...d,contactCount:null},{now});
      return {
        id:String(d.id), name:String(d.properties?.dealname||'Deal '+d.id),
        amount:amountOf(d.properties?.amount),
        stage:String(d.properties?.dealstage||''),
        ownerId:String(d.properties?.hubspot_owner_id||''),
        pipeline:String(d.properties?.pipeline||''),
        priority:assessment.score,
        level:assessment.level,
        recommendation:assessment.recommendation,
        leadingFactor:assessment.flags[0]?.detail||'No attention flags',
        factors:assessment.flags.map(f=>({id:f.id,points:f.points,detail:f.detail})),
        storedPriority:d.properties?.sri_risk_priority??null,
        storedStatus:d.properties?.sri_assessment_status||null,
        lastAssessed:d.properties?.sri_last_assessed||null,
        dataQuality:assessment.dataQuality
      };
    });
  assessed.sort((a,b)=>b.priority-a.priority||b.amount-a.amount||a.name.localeCompare(b.name));
  const summary={
    assessed:assessed.length,
    high:assessed.filter(d=>d.level==='high').length,
    medium:assessed.filter(d=>d.level==='medium').length,
    low:assessed.filter(d=>d.level==='low').length,
    attentionValue:Math.round(assessed.filter(d=>d.level==='high').reduce((s,d)=>s+d.amount,0)*100)/100
  };
  return {deals:assessed,summary};
}
module.exports={buildTriage,MAX_SCAN,amountOf};
