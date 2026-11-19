const {scoreDeal}=require('./lib/scoring.cjs');
const {loadDeal,idOrThrow}=require('./lib/hubspot.cjs');
exports.main=async context=>{
  const id=idOrThrow(context?.parameters?.dealId);
  const d=await loadDeal(id);
  const a=scoreDeal(d);
  const p=d.properties||{};
  const hasSavedAssessment=Boolean(p.sri_last_assessed&&p.sri_risk_priority!==undefined&&p.sri_risk_priority!==null);
  return {dealId:id,dealName:p.dealname||'Deal '+id,...a,
    reviewStatus:p.sri_assessment_status||null,
    lastSavedAt:p.sri_last_assessed||null,
    hasSavedAssessment,
    // Detect scored change before permitting acknowledgement.
    savedScoreMatches:hasSavedAssessment && Number(p.sri_risk_priority)===a.score&&p.sri_risk_level===a.level};
};
