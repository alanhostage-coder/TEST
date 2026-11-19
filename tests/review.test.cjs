'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const review=require('../src/app/functions/ReviewAssessment.js');
process.env.PRIVATE_APP_ACCESS_TOKEN='TEST_TOKEN_NON_SECRET';
const base={dealname:'A',hs_is_closed:'false',sri_risk_priority:'45',sri_risk_level:'medium',sri_assessment_status:'pending',sri_last_assessed:'2026-11-19T18:00:00Z'};
const createMock=(change={})=>{
  const calls=[],p={...base,...change};
  global.fetch=async(url,opts={})=>{calls.push({url,opts});return{ok:true,status:opts.method==='PATCH'?204:200,json:async()=>({id:'7',properties:p}),text:async()=>''};};
  return calls;
};
test('review requires a saved assessment',async()=>{
  const calls=createMock({sri_last_assessed:null});
  const res=await review.main({parameters:{dealId:'7'}});
  assert.equal(res.reviewed,false);assert.equal(calls.some(c=>c.opts.method==='PATCH'),false);
});
test('review refuses closed deals',async()=>{
  const calls=createMock({hs_is_closed:'true'});
  const res=await review.main({parameters:{dealId:'7',expectedLastAssessed:base.sri_last_assessed}});
  assert.equal(res.reviewed,false);assert.equal(calls.length,1);
});
test('review rejects stale timestamp',async()=>{
  const calls=createMock();
  const res=await review.main({parameters:{dealId:'7',expectedLastAssessed:'2026-11-18T12:00:00Z'}});
  assert.equal(res.reviewed,false);assert.equal(calls.length,1);
});
test('review requires timestamp for concurrency',async()=>{
  const calls=createMock();
  const res=await review.main({parameters:{dealId:'7'}});
  assert.equal(res.reviewed,false);assert.equal(calls.length,1);
});
test('review writes only review status',async()=>{
  const calls=createMock();
  const res=await review.main({parameters:{dealId:'7',expectedLastAssessed:base.sri_last_assessed}});
  assert.equal(res.reviewed,true);
  const patch=calls.find(c=>c.opts.method==='PATCH');
  assert.deepEqual(JSON.parse(patch.opts.body),{properties:{sri_assessment_status:'reviewed'}});
});
test('already reviewed actions are idempotent',async()=>{
  const calls=createMock({sri_assessment_status:'reviewed'});
  const res=await review.main({parameters:{dealId:'7',expectedLastAssessed:base.sri_last_assessed}});
  assert.equal(res.alreadyReviewed,true);assert.equal(calls.length,1);
});
test('invalid record ID prevents network reads',async()=>{
  const calls=createMock();
  await assert.rejects(review.main({parameters:{dealId:'7/other'}}),/Invalid deal ID/);
  assert.equal(calls.length,0);
});
