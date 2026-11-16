'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const fn=require('../src/app/functions/SiloyTime.js')._test;
test('week normalisation and date guards',()=>{assert.equal(fn.monday('2026-11-14'),'2026-11-09');assert.equal(fn.date('2026-02-30'),null);});
test('valid time increments',()=>{assert.equal(fn.duration('1.25'),75);assert.equal(fn.duration('1.33'),null);});
test('maps duration to CRM properties',()=>{const p=fn.properties({date:'2026-11-13',start:'09:15',hours:'1.75',billable:true});assert.equal(p.end_time,'2026-11-13T11:00:00.000Z');assert.equal(p.total_minutes_spent,'105');});
test('independent from Notes',()=>{const a=JSON.parse(fs.readFileSync('src/app/app-hsmeta.json'));const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');assert.equal(a.config.name,'Siloy Time');assert.match(ui,/Siloy Time/);assert.doesNotMatch(ui,/corpus_notes_api|CorpusNoteCard/);});


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
  assert.equal(result.body.objectTypeId,'2-143515197');
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
 assert.match(ui,/const displayedBrandMark=isSiloyBrand\?SILOY_HEADER:CORPUS_BRAND.logoUrl/);
 assert.match(ui,/User-level access control is not yet enabled/);
});

test('UAT: the date range, daily rows and entry picker cover the same seven days',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/const NAMES=\['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'\]/);
 assert.match(ui,/uk\(shift\(week,6\)\)/);
 assert.match(ui,/options=\{days\.map/);
});

test('UAT: partial saves close the form and provide a warning with the existing record link',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/setReceipt\(\{id:out\.entryId,partial:Boolean\(out\.partial\),objectTypeId:out\.objectTypeId\|\|''\}\);\s*setDirty\(false\);setResetArmed\(false\);setOpen\(false\);setForm\(blank\(form\.date\)\);/);
 assert.match(ui,/receipt\.partial\?'warning':'success'/);
 assert.match(ui,/receipt\.id\}>Open Time Log/);
});


test('Weekly timesheet supports Company, Contact, Deal and Ticket records without changing sidebar placement',()=>{
 const meta=JSON.parse(fs.readFileSync('src/app/cards/card-hsmeta.json','utf8'));
 const quick=JSON.parse(fs.readFileSync('src/app/cards/quick-log-hsmeta.json','utf8'));
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.deepEqual(meta.config.objectTypes,['companies','contacts','deals','tickets']);
 assert.equal(meta.config.location,'crm.record.tab');
 assert.equal(quick.config.location,'crm.record.sidebar');
 assert.match(ui,/parameters:\{action:'load',recordType,recordId,week\}/);
 assert.match(ui,/action:form.id\?'update':'create',recordType,recordId/);
 assert.doesNotMatch(ui,/contactId/);
 assert.doesNotMatch(ui,/record\/2-143515197/);
});

test('Weekly timesheet saves and edits using the selected Company association',async()=>{
 const api=require('../src/app/functions/SiloyTime.js');
 const prevFetch=global.fetch,prevToken=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock-uat';
 const calls=[];
 global.fetch=async(url,opt={})=>{
  const target=String(url);calls.push({target,method:opt.method||'GET'});
  const data=target.includes('/associations/companies')?{results:[{toObjectId:'10001'}]}:
    opt.method==='POST'&&target.endsWith('/crm/v3/objects/2-143515197')?{id:'777001'}:{};
  return {ok:true,status:200,json:async()=>data};
 };
 try{
  const created=await api.main({parameters:{action:'create',recordType:'companies',recordId:'10001',
   entry:{date:'2026-11-13',start:'09:00',hours:'1',projectId:'20001',description:'Weekly work'}}});
  assert.equal(created.body.success,true);
  assert.equal(created.body.objectTypeId,'2-143515197');
  assert.ok(calls.some(c=>c.target.includes('/associations/default/companies/10001')));
  calls.length=0;
  const edited=await api.main({parameters:{action:'update',recordType:'companies',recordId:'10001',
   entry:{id:'777001',date:'2026-11-13',start:'10:00',hours:'1.25',description:'Edited'}}});
  assert.equal(edited.body.success,true);
  assert.deepEqual(calls.map(x=>x.method),['GET','PATCH']);
 }finally{
  global.fetch=prevFetch;
  if(prevToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=prevToken;
 }
});


test('Weekly timesheet has optional Project, correct record-scoped totals and guarded clearing',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/\[open,setOpen\]=useState\(false\)/);
 assert.match(ui,/<Heading>Week at a glance<\/Heading>/);
 assert.match(ui,/Project \(optional\)/);
 assert.match(ui,/dirty&&!resetArmed/);
 assert.doesNotMatch(ui,/\/ 40 h|\/ 8 h|Choose a HubSpot Project/);
});
test('Full weekly form creates a Company-linked entry without requiring Project',async()=>{
 const api=require('../src/app/functions/SiloyTime.js');
 const prevFetch=global.fetch,prevToken=process.env.PRIVATE_APP_ACCESS_TOKEN;
 process.env.PRIVATE_APP_ACCESS_TOKEN='mock-uat';
 const calls=[];
 global.fetch=async(url,opt={})=>{
  calls.push({url:String(url),method:opt.method||'GET'});
  return {ok:true,status:200,json:async()=>opt.method==='POST'?{id:'888001'}:{}};
 };
 try{
  const result=await api.main({parameters:{action:'create',recordType:'companies',recordId:'467489667321',
    entry:{date:'2026-11-16',start:'09:00',hours:'0.5',description:'Company time entry',billable:false}}});
  assert.equal(result.body.success,true);
  assert.equal(result.body.entryId,'888001');
  assert.deepEqual(calls.map(x=>x.method),['POST','PUT']);
  assert.match(calls[1].url,/associations\/default\/companies\/467489667321/);
 }finally{
  global.fetch=prevFetch;
  if(prevToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
  else process.env.PRIVATE_APP_ACCESS_TOKEN=prevToken;
 }
});


test('Time entries prioritise work description and allow one-tap durations',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/Describe the work carried out/);
 assert.match(ui,/e\.description\|\|'Time entry'/);
 assert.match(ui,/Quick durations/);
 assert.match(ui,/onClick=\{\(\)=>update\('hours',value\)\}/);
 assert.doesNotMatch(ui,/Project unassigned/);
});


test('Timesheet explains record-scoped totals and optional Project with native tooltips',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/,Tag,Tooltip,/);
 assert.match(ui,/overlay=\{<Tooltip placement="bottom">Totals include entries linked to this CRM record/);
 assert.match(ui,/Billable hours are entries marked Billable/);
 assert.match(ui,/variant=\{billable>0\?'success':'default'\}/);
 assert.match(ui,/Project field is optional/);
 assert.match(ui,/in 15-minute increments/);
});

test('Full timesheet uses a native accessible information icon rather than a corrupted text glyph',()=>{
 const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');
 assert.match(ui,/<Icon name="info" screenReaderText=/);
 assert.doesNotMatch(ui,/ⓘ/);
});
