const {scoreDeal}=require('./lib/scoring.cjs');
const {loadDeal,idOrThrow}=require('./lib/hubspot.cjs');
exports.main=async context=>{
  const id=idOrThrow(context?.parameters?.dealId);
  const d=await loadDeal(id);
  return {dealId:id,dealName:d.properties.dealname||'Deal '+id,...scoreDeal(d)};
};
