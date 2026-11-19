'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const score=require('../src/app/functions/ScoreDeal.js'),save=require('../src/app/functions/SaveAssessment.js'),listing=require('../src/app/functions/ListDeals.js');
process.env.PRIVATE_APP_ACCESS_TOKEN='TEST_KEY_NOT_REAL';
function mockFetch(changes={}){
 const calls=[],properties={dealname:'UAT opportunity',dealstage:'appointmentscheduled',pipeline:'default',hs_is_closed:'false',createdate:'2026-10-01',notes_last_contacted:'2026-10-10',notes_next_activity_date:null,closedate:'2026-10-15',hs_next_step:'',hs_v2_date_entered_current_stage:'2026-10-01',...changes};
 global.fetch=async(url,opts={})=>{calls.push({url,opts});const data=url.includes('/associations/contacts')?{results:[]}:url.includes('/deals/search')?{results:[{id:'123',properties}],total:1}:{id:'123',properties};return {ok:true,status:opts.method==='PATCH'?204:200,json:async()=>data,text:async()=>JSON.stringify(data)};};
 return calls;
}
test('score reads without mutation',async()=>{const calls=mockFetch(),x=await score.main({parameters:{dealId:'123'}});assert.equal(x.dealId,'123');assert.ok(x.score>0);assert.equal(calls.length,2);assert.ok(calls.every(x=>!x.opts.method||x.opts.method==='GET'));});
test('save writes exactly six custom fields',async()=>{const calls=mockFetch(),x=await save.main({parameters:{dealId:'123'}});assert.equal(x.saved,true);const patch=calls.find(x=>x.opts.method==='PATCH');assert.ok(patch);const properties=JSON.parse(patch.opts.body).properties;assert.deepEqual(Object.keys(properties).sort(),['sri_assessment_status','sri_last_assessed','sri_recommended_action','sri_risk_factors','sri_risk_level','sri_risk_priority']);});
test('closed deal save blocked',async()=>{const calls=mockFetch({hs_is_closed:'true'}),x=await save.main({parameters:{dealId:'123'}});assert.equal(x.saved,false);assert.equal(calls.some(x=>x.opts.method==='PATCH'),false);});
test('IDs reject injection',async()=>{const calls=mockFetch();await assert.rejects(save.main({parameters:{dealId:'123/associations'}}),/Invalid deal ID/);assert.equal(calls.length,0);});
test('deal list paginates and reads',async()=>{const calls=mockFetch(),x=await listing.main({parameters:{limit:20}});assert.equal(x.total,1);assert.equal(x.deals[0].dealname,'UAT opportunity');assert.equal(calls[0].opts.method,'POST');});
