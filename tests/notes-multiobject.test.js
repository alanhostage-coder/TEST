'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const app=require('../src/app/functions/CorpusNotes.js');

test('Siloy Notes full workspace and quick rail support core HubSpot records',()=>{
 const middle=JSON.parse(fs.readFileSync('src/app/cards/card-hsmeta.json','utf8'));
 const sidebar=JSON.parse(fs.readFileSync('src/app/cards/quick-rail-hsmeta.json','utf8'));
 const rail=fs.readFileSync('src/app/cards/CorpusQuickRail.jsx','utf8');
 const main=fs.readFileSync('src/app/cards/CorpusNoteCard.jsx','utf8');
 for(const card of [middle,sidebar])assert.deepEqual(card.config.objectTypes,['companies','contacts','deals','tickets']);
 assert.equal(sidebar.config.location,'crm.record.sidebar');
 assert.match(rail,/recordType, recordId: companyId/);
 assert.match(main,/recordType, recordId: companyId/);
 assert.match(main,/Focus on writing/);
});
test('Notes can list linked notes from Deals and Tickets',async()=>{
 const oldToken=process.env.PRIVATE_APP_ACCESS_TOKEN,oldFetch=global.fetch;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock';
 const urls=[];
 global.fetch=async(url)=>{urls.push(String(url));return {ok:true,status:200,text:async()=>JSON.stringify({results:[]})};};
 try{
  for(const recordType of ['deals','tickets']){
   const res=await app.main({parameters:{action:'list',recordType,recordId:'23456'}});
   assert.equal(res.body.success,true);
  }
  assert.match(urls[0],/objects\/deals\/23456\/associations/);
  assert.match(urls[1],/objects\/tickets\/23456\/associations/);
 }finally{
  global.fetch=oldFetch;
  if(oldToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=oldToken;
 }
});
test('Notes creates single record associated with selected Contact',async()=>{
 const oldToken=process.env.PRIVATE_APP_ACCESS_TOKEN,oldFetch=global.fetch;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock';
 const urls=[];
 global.fetch=async(url,opt)=>{urls.push({url:String(url),method:opt.method});return{ok:true,status:201,text:async()=>JSON.stringify(opt.method==='POST'?{id:'901'}:{})};};
 try{
  const res=await app.main({parameters:{action:'create',recordType:'contacts',recordId:'12345',
    note:{note_title:'Follow-up',note_type:'internal_update',note_date:'2026-11-15',internal_notes:'Update for contact'}}});
  assert.equal(res.body.success,true);
  assert.equal(urls.length,2);
  assert.match(urls[1].url,/associations\/default\/contacts\/12345/);
 }finally{
  global.fetch=oldFetch;
  if(oldToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=oldToken;
 }
});
test('Notes rejects object type or record ID without making requests',async()=>{
 const oldToken=process.env.PRIVATE_APP_ACCESS_TOKEN,oldFetch=global.fetch;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock';
 let calls=0;global.fetch=async()=>{calls++;throw Error('Unexpected network request')};
 try{
  const badType=await app.main({parameters:{action:'list',recordType:'orders',recordId:'1'}});
  const badId=await app.main({parameters:{action:'list',recordType:'companies',recordId:'../../invalid'}});
  assert.equal(badType.statusCode,400);
  assert.equal(badId.statusCode,400);
  assert.equal(calls,0);
 }finally{
  global.fetch=oldFetch;
  if(oldToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=oldToken;
 }
});
