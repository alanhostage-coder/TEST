'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const fn=require('../src/app/functions/SiloyTime.js')._test;
test('week normalisation and date guards',()=>{assert.equal(fn.monday('2026-11-14'),'2026-11-09');assert.equal(fn.date('2026-02-30'),null);});
test('valid time increments',()=>{assert.equal(fn.duration('1.25'),75);assert.equal(fn.duration('1.33'),null);});
test('maps duration to CRM properties',()=>{const p=fn.properties({date:'2026-11-13',start:'09:15',hours:'1.75',billable:true});assert.equal(p.end_time,'2026-11-13T11:00:00.000Z');assert.equal(p.total_minutes_spent,'105');});
test('independent from Notes',()=>{const a=JSON.parse(fs.readFileSync('src/app/app-hsmeta.json'));const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');assert.equal(a.config.name,'Siloy Time');assert.match(ui,/<Heading>Siloy Time<\/Heading>/);assert.doesNotMatch(ui,/corpus_notes_api|CorpusNoteCard/);});


test('UAT: creating time writes valid properties and both associations',async()=>{
 const api=require('../src/app/functions/SiloyTime.js');
 const previous=global.fetch,token=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='uat-mock-token';
 const requests=[];
 global.fetch=async(url,options={})=>{
  requests.push({url:String(url),method:options.method||'GET',body:options.body?JSON.parse(options.body):null});
  const id=options.method==='POST'&&String(url).endsWith('/crm/v3/objects/2-143515197')?'777001':null;
  return {ok:true,status:id?201:200,json:async()=>id?{id}:{}};
 };
 try{
  const result=await api.main({parameters:{action:'create',contactId:'10001',
   entry:{date:'2026-11-13',start:'09:15',hours:'1.75',billable:true,projectId:'20001',description:'UAT support'}}});
  assert.equal(result.body.success,true);
  assert.equal(result.body.entryId,'777001');
  assert.equal(requests.length,4);
  assert.equal(requests[0].method,'GET');
  assert.match(requests[0].url,/\/0-970\/20001/);
  assert.equal(requests[1].body.properties.total_minutes_spent,'105');
  assert.equal(requests[1].body.properties.end_time,'2026-11-13T11:00:00.000Z');
  assert.equal(requests[2].method,'PUT');
  assert.match(requests[2].url,/associations\/default\/contacts\/10001/);
  assert.match(requests[3].url,/associations\/default\/0-970\/20001/);
 }finally{
  global.fetch=previous;
  if(token===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=token;
 }
});

test('UAT: updating an associated entry persists without duplicating',async()=>{
 const api=require('../src/app/functions/SiloyTime.js');
 const previous=global.fetch,token=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='uat-mock-token';
 const requests=[];
 global.fetch=async(url,options={})=>{
  const target=String(url);
  requests.push({url:target,method:options.method||'GET',body:options.body?JSON.parse(options.body):null});
  const data=target.includes('/associations/contacts')?{results:[{toObjectId:10001}]}:{};
  return {ok:true,status:200,json:async()=>data};
 };
 try{
  const result=await api.main({parameters:{action:'update',contactId:'10001',
   entry:{id:'777001',date:'2026-11-13',start:'10:00',hours:'2.25',billable:false}}});
  assert.equal(result.body.success,true);
  assert.equal(result.body.entryId,'777001');
  assert.deepEqual(requests.map(x=>x.method),['GET','PATCH']);
  assert.equal(requests[1].body.properties.total_minutes_spent,'135');
 }finally{
  global.fetch=previous;
  if(token===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=token;
 }
});

test('UAT: refuses editing a time log not associated with selected Contact',async()=>{
 const api=require('../src/app/functions/SiloyTime.js');
 const previous=global.fetch,token=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='uat-mock-token';
 const methods=[];
 global.fetch=async(url,options={})=>{
  methods.push(options.method||'GET');
  return {ok:true,status:200,json:async()=>({results:[{toObjectId:33333}]})};
 };
 try{
  const result=await api.main({parameters:{action:'update',contactId:'10001',
   entry:{id:'777001',date:'2026-11-13',start:'10:00',hours:'1'}}});
  assert.equal(result.statusCode,403);
  assert.deepEqual(methods,['GET']);
 }finally{
  global.fetch=previous;
  if(token===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=token;
 }
});

test('UAT: partial association failure returns existing Time Log ID for safe recovery',async()=>{
 const api=require('../src/app/functions/SiloyTime.js');
 const previous=global.fetch,token=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='uat-mock-token';
 global.fetch=async(url,options={})=>{
  if(options.method==='PUT'&&String(url).includes('/0-970/'))
   return {ok:false,status:403,json:async()=>({message:'Association denied'})};
  return {ok:true,status:200,json:async()=>options.method==='POST'?{id:'777001'}:{}};
 };
 try{
  const result=await api.main({parameters:{action:'create',contactId:'10001',
   entry:{date:'2026-11-13',start:'09:00',hours:'1',projectId:'20001'}}});
  assert.equal(result.body.partial,true);
  assert.equal(result.body.entryId,'777001');
  assert.equal(result.statusCode,207);
 }finally{
  global.fetch=previous;
  if(token===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=token;
 }
});

test('UAT: weekly loader restores allocations and totals from HubSpot API',async()=>{
 const api=require('../src/app/functions/SiloyTime.js');
 const previous=global.fetch,token=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='uat-mock-token';
 const requested=[];
 global.fetch=async(url,options={})=>{
  const s=String(url);requested.push(s);
  let data={};
  if(s.includes('/contacts/10001/associations/'))data={results:[{toObjectId:777001}]};
  else if(s.includes('/2-143515197/batch/read'))data={results:[{id:'777001',properties:{
   start_time:'2026-11-13T09:15:00Z',end_time:'2026-11-13T11:00:00Z',
   total_minutes_spent:'105',description:'Research',is_billable:'true'}}]};
  else if(s.includes('/associations/2-143515197/0-970/batch/read'))data={results:[{from:{id:'777001'},to:[{toObjectId:20001}]}]};
  else if(s.includes('/objects/0-970'))data={results:[{id:'20001',properties:{hs_name:'UAT Project'}}]};
  return {ok:true,status:200,json:async()=>data};
 };
 try{
  const result=await api.main({parameters:{action:'load',contactId:'10001',week:'2026-11-14'}});
  assert.equal(result.body.success,true);
  assert.equal(result.body.entries.length,1);
  assert.equal(result.body.entries[0].hours,1.75);
  assert.equal(result.body.entries[0].projectId,'20001');
  assert.equal(result.body.projects[0].name,'UAT Project');
  assert.equal(result.body.entries[0].billable,true);
 }finally{
  global.fetch=previous;
  if(token===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=token;
 }
});

test('UAT: review usability and warn on unsaved draft replacement',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/onClick=\{\(\)=>fresh\(d.date\)\}/);
 assert.match(ui,/onClick=\{\(\)=>edit\(e\)\}/);
 assert.match(ui,/pending\.current/);
});

test('UAT: draft switching is guarded and official Siloy brand asset is loaded',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/const fresh=date=>\{\s*if\(dirty\)/);
 assert.match(ui,/const edit=row=>\{\s*if\(dirty\)/);
 assert.match(ui,/const displayedBrandMark=isSiloyBrand\?SILOY_MARK:CORPUS_BRAND.logoUrl/);
 assert.match(ui,/User-level access control is not yet enabled/);
});
