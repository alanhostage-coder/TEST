const test=require('node:test');
const assert=require('node:assert/strict');
const app=require('../src/app/functions/CorpusNotes.js');
const {isRecordId,dateMs}=app._test;
const oldFetch=global.fetch;
const oldToken=process.env.PRIVATE_APP_ACCESS_TOKEN;
test.after(()=>{global.fetch=oldFetch;if(oldToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;else process.env.PRIVATE_APP_ACCESS_TOKEN=oldToken;});
test('IDs and dates',()=>{
  assert.equal(isRecordId('465468643550'),true);
  assert.equal(isRecordId('abc/123'),false);
  assert.equal(dateMs('2026-02-29'),null);
  assert.equal(dateMs('2024-02-29'),String(Date.UTC(2024,1,29)));
});
test('rejects incomplete notes without API calls',async()=>{
  process.env.PRIVATE_APP_ACCESS_TOKEN='test-only';
  let hits=0;global.fetch=async()=>{hits++;throw Error('unexpected');};
  const r=await app.main({parameters:{action:'create',companyId:'123',note:{note_title:'Review'}}});
  assert.equal(r.statusCode,400);assert.equal(hits,0);
});
test('lists empty Company associations',async()=>{
  process.env.PRIVATE_APP_ACCESS_TOKEN='test-only';
  const calls=[];global.fetch=async(url,options)=>{
    calls.push(url);return {ok:true,status:200,text:async()=>JSON.stringify({results:[]})};
  };
  const r=await app.main({parameters:{action:'list',companyId:'123'}});
  assert.equal(r.body.success,true);assert.deepEqual(r.body.notes,[]);
  assert.equal(calls.length,1);assert.match(calls[0],/associations\/2-256491528/);
});
test('creates associated note and never writes a meeting',async()=>{
  process.env.PRIVATE_APP_ACCESS_TOKEN='test-only';
  const urls=[];global.fetch=async(url,options)=>{
    urls.push(options.method+' '+url);
    return {ok:true,status:200,text:async()=>JSON.stringify(options.method==='POST'?{id:'3456'}:{})};
  };
  const r=await app.main({parameters:{action:'create',companyId:'123',note:{
    note_title:'Review',note_type:'meeting',note_date:'2026-11-13',internal_notes:'Private'
  }}});
  assert.equal(r.body.success,true);assert.equal(r.body.noteId,'3456');
  assert.equal(urls.length,2);
  assert.ok(urls.every(x=>!x.includes('/meetings')&&!x.includes('/engagements')));
  assert.match(urls[1],/\/associations\/default\/companies\/123/);
});
test('association failure reveals created note ID',async()=>{
  process.env.PRIVATE_APP_ACCESS_TOKEN='test-only';
  global.fetch=async(url,options)=>options.method==='POST'
    ?{ok:true,status:201,text:async()=>JSON.stringify({id:'3456'})}
    :{ok:false,status:403,text:async()=>JSON.stringify({message:'Denied'})};
  const r=await app.main({parameters:{action:'create',companyId:'123',note:{
    note_title:'Review',note_type:'meeting',note_date:'2026-11-13',internal_notes:'Private'
  }}});
  assert.equal(r.statusCode,207);assert.equal(r.body.partial,true);assert.equal(r.body.noteId,'3456');
});
test('invalid date avoids mutation',async()=>{
  process.env.PRIVATE_APP_ACCESS_TOKEN='test-only';
  let hits=0;global.fetch=async()=>{hits++;throw Error('unexpected');};
  const r=await app.main({parameters:{action:'create',companyId:'123',note:{
    note_title:'Review',note_type:'meeting',note_date:'2026-02-29',internal_notes:'Private'
  }}});
  assert.equal(r.statusCode,400);assert.equal(hits,0);
});
