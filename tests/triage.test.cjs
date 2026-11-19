'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {buildTriage,amountOf,MAX_SCAN}=require('../src/app/functions/lib/triage.cjs');
const queue=require('../src/app/functions/TriageQueue.js');
process.env.PRIVATE_APP_ACCESS_TOKEN='TEST_TOKEN_NON_SECRET';
const now='2026-11-19T12:00:00Z';
const good=(id,name,amount)=>({id:String(id),properties:{dealname:name,amount,hs_is_closed:'false',
  createdate:'2026-11-01',closedate:'2026-12-01',notes_last_contacted:'2026-11-18',
  notes_next_activity_date:'2026-11-24',hs_next_step:'Arrange visit',hs_v2_date_entered_current_stage:'2026-11-10'}});
test('triage ranks highest rule risk first',()=>{
  const low=good(1,'Low',1000),high=good(2,'High',100000);
  high.properties.closedate='2026-10-03';high.properties.notes_next_activity_date=null;
  const x=buildTriage([low,high],{now});
  assert.equal(x.deals[0].id,'2');assert.equal(x.summary.high,0);
  assert.equal(x.deals[0].priority,55);assert.equal(x.deals[1].priority,0);
});
test('ties rank by opportunity value',()=>{
  const x=buildTriage([good(1,'Smaller',100),good(2,'Bigger','1,500')],{now});
  assert.equal(x.deals[0].id,'2');
});
test('closed deals excluded defensively',()=>{
  const closed=good(3,'Closed',2000);closed.properties.hs_is_closed='true';
  const x=buildTriage([good(1,'Open',1500),closed],{now});
  assert.equal(x.summary.assessed,1);
});
test('bulk triage does not invent association risk',()=>{
  const x=buildTriage([good(1,'Only',3000)],{now});
  assert.equal(x.deals[0].priority,0);assert.ok(x.deals[0].dataQuality.some(s=>s.includes('Contact count unavailable')));
});
test('empty data returns safe totals',()=>{
  const x=buildTriage([],{now});
  assert.equal(x.summary.assessed,0);assert.equal(x.summary.attentionValue,0);
});
test('unknown amount is not treated as real value',()=>{
  assert.equal(amountOf('NaN'),0);assert.equal(amountOf('-500'),0);assert.equal(amountOf('1,500.50'),1500.50);
  assert.equal(MAX_SCAN,100);
});
test('live queue searches HubSpot read-only with open-deal filter',async()=>{
  const calls=[];
  global.fetch=async(url,opts={})=>{calls.push({url,opts});return{ok:true,status:200,json:async()=>({total:1,results:[good(8,'Active',4000)]}),text:async()=>''};};
  const r=await queue.main({});
  assert.equal(r.totalOpen,1);assert.equal(r.scanned,1);assert.equal(r.deals[0].name,'Active');
  assert.equal(calls.length,1);assert.equal(calls[0].opts.method,'POST');
  const body=JSON.parse(calls[0].opts.body);
  assert.equal(body.limit,100);assert.equal(body.filterGroups[0].filters[0].propertyName,'hs_is_closed');
});
test('live queue exposes sampling caveat',async()=>{
  global.fetch=async()=>({ok:true,status:200,json:async()=>({total:150,results:[good(3,'Active',4000)],paging:{next:{after:'4'}}}),text:async()=>''});
  const r=await queue.main({});
  assert.equal(r.incomplete,true);assert.equal(r.totalOpen,150);
});
