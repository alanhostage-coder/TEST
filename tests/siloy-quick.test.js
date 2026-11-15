'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');

test('Siloy Time quick log is a right sidebar card for core CRM records',()=>{
 const meta=JSON.parse(fs.readFileSync('src/app/cards/quick-log-hsmeta.json','utf8'));
 const ui=fs.readFileSync('src/app/cards/SiloyQuickTime.jsx','utf8');
 const weekly=fs.readFileSync('src/app/cards/card-hsmeta.json','utf8');
 assert.equal(meta.config.location,'crm.record.sidebar');
 assert.deepEqual(meta.config.objectTypes,['companies','contacts','deals','tickets']);
 assert.match(ui,/action: 'quickCreate'/);
 assert.match(ui,/recordType, recordId/);
 assert.match(ui,/siloy_time_api/);
 assert.match(ui,/Quick time log/);
 assert.match(weekly,/"crm.record.tab"/);
 assert.match(weekly,/"contacts"/);
});
test('Quick log can create one entry on Company without requiring a Project',async()=>{
 const app=require('../src/app/functions/SiloyTime.js');
 const prevFetch=global.fetch,prevToken=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock-uat';
 const calls=[];
 global.fetch=async(url,opt={})=>{
  calls.push({url:String(url),method:opt.method||'GET',body:opt.body?JSON.parse(opt.body):null});
  return {ok:true,status:201,json:async()=>({id:'55100'})};
 };
 try {
  const result=await app.main({parameters:{
   action:'quickCreate',recordType:'companies',recordId:'467489667321',
   entry:{date:'2026-11-15',start:'12:00',hours:'0.5',description:'Client catch-up',billable:false}
  }});
  assert.equal(result.body.success,true);
  assert.equal(result.body.entryId,'55100');
  assert.deepEqual(calls.map(x=>x.method),['POST','PUT']);
  assert.match(calls[1].url,/associations\/default\/companies\/467489667321/);
  assert.equal(calls[0].body.properties.total_minutes_spent,'30');
 }finally{
  global.fetch=prevFetch;
  if(prevToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=prevToken;
 }
});
test('Quick log links to Deal or Ticket and optionally also to Project',async()=>{
 const app=require('../src/app/functions/SiloyTime.js');
 const prevFetch=global.fetch,prevToken=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock-uat';
 let paths=[];
 global.fetch=async(url,opt={})=>{
  paths.push(String(url));
  return {ok:true,status:200,json:async()=>opt.method==='POST'?{id:'901'}:{}};
 };
 try {
  for(const recordType of ['deals','tickets']) {
   paths=[];
   const result=await app.main({parameters:{action:'quickCreate',recordType,recordId:'987654',
    entry:{date:'2026-11-15',start:'13:00',hours:1,description:'Client work',projectId:'1024'}}});
   assert.equal(result.body.success,true);
   assert.equal(paths.length,4);
   assert.match(paths[2],new RegExp('associations/default/'+recordType+'/987654'));
   assert.match(paths[3],/associations\/default\/0-970\/1024/);
  }
 }finally{
  global.fetch=prevFetch;
  if(prevToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=prevToken;
 }
});
test('Quick log refuses unsupported record types and missing descriptions without mutation',async()=>{
 const app=require('../src/app/functions/SiloyTime.js');
 const prevFetch=global.fetch,prevToken=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock-uat';
 let count=0;
 global.fetch=async()=>{count++;throw Error('Unexpected mutation')};
 try{
  const invalidType=await app.main({parameters:{action:'quickCreate',recordType:'orders',recordId:'987',entry:{}}});
  assert.equal(invalidType.statusCode,400);
  const empty=await app.main({parameters:{action:'quickCreate',recordType:'companies',recordId:'987',
    entry:{date:'2026-11-15',start:'09:00',hours:'0.5',description:''}}});
  assert.equal(empty.statusCode,400);
  assert.equal(count,0);
 }finally{
  global.fetch=prevFetch;
  if(prevToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=prevToken;
 }
});
