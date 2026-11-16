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

test('main Company card never silently blocks saving a blank-title or protected draft',()=>{
  const fs=require('node:fs');
  const ui=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  assert.match(ui,/<Button onClick=\{save\} disabled=\{saving\}>/);
  assert.doesNotMatch(ui,/if \(saving \|\| draftProtected\) return/);
  assert.match(ui,/note_title: effectiveTitle/);
  assert.match(ui,/const effectiveTitle = form\.note_title\.trim\(\) \|\| suggestedTitle/);
  assert.match(ui,/setSaveIssue\(problem\)/);
  assert.match(ui,/result\.partial && result\.noteId/);
  assert.match(ui,/saveInFlight\.current = true/);
});
test('sidebar quick capture keeps Save available and provides validation',()=>{
  const fs=require('node:fs');
  const ui=fs.readFileSync(require.resolve('../src/app/cards/CorpusQuickRail.jsx'),'utf8');
  assert.match(ui,/<Button onClick=\{save\} disabled=\{busy\}>/);
  assert.match(ui,/const titleToSave = title\.trim\(\) \|\| defaultTitle/);
  assert.match(ui,/Write your internal note before saving/);
  assert.match(ui,/result\.partial && result\.noteId/);
});

test('draft rescue uses HubSpot clipboard only on explicit user action',()=>{
  const fs=require('node:fs');
  const main=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  const rail=fs.readFileSync(require.resolve('../src/app/cards/CorpusQuickRail.jsx'),'utf8');
  assert.match(main,/copyTextToClipboard=\{actions\.copyTextToClipboard\}/);
  assert.match(main,/await copyTextToClipboard\(recoveryText\(\)\)/);
  assert.match(main,/onClick=\{copyDraft\}/);
  assert.match(main,/Recovery copies are manual/);
  assert.match(rail,/onClick=\{copyQuickDraft\}/);
  assert.match(rail,/await copyTextToClipboard\(\[/);
  assert.doesNotMatch(main,/navigator\.clipboard|localStorage|sessionStorage/);
  assert.doesNotMatch(rail,/navigator\.clipboard|localStorage|sessionStorage/);
});
test('confirmed save does not wait for a history reload',()=>{
  const fs=require('node:fs');
  const main=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  const rail=fs.readFileSync(require.resolve('../src/app/cards/CorpusQuickRail.jsx'),'utf8');
  assert.match(main,/void reload\(\);/);
  assert.match(rail,/void reload\(\);/);
  assert.match(main,/setReceipt\(\{ id: result\.noteId, title: effectiveTitle, linked: true \}\)/);
});
test('an unlinked saved note is recoverable without resubmitting its draft',()=>{
  const fs=require('node:fs');
  const main=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  const rail=fs.readFileSync(require.resolve('../src/app/cards/CorpusQuickRail.jsx'),'utf8');
  assert.match(main,/result\.partial && result\.noteId[\s\S]*?linked: false[\s\S]*?setForm\(empty\(\)\)[\s\S]*?return;/);
  assert.match(rail,/result\.partial && result\.noteId[\s\S]*?setAssociationNeeded\(true\)[\s\S]*?setTitle\(''\);\s*setBody\(''\);\s*setComposer\(false\);/);
  assert.match(rail,/variant=\{associationNeeded \? 'warning' : 'success'\}[\s\S]*?url\(savedId\)/);
});
test('writing focus and cognitive signposting remain present',()=>{
  const fs=require('node:fs');
  const main=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  assert.match(main,/const WRITING_GUIDES =/);
  assert.match(main,/Focus on writing/);
  assert.match(main,/Find in loaded notes/);
  assert.match(main,/Next actions \(\{nextActionCount\}\)/);
  assert.match(main,/Decisions \(\{decisionCount\}\)/);
  assert.doesNotMatch(main,/<Image src=\{CORPUS_BANNER_DATA_URI\}/);
  assert.match(main,/SILOY_HEADER_URL/);
  assert.match(main,/CORPUS_BRAND\.logoUrl/);
  assert.match(main,/Internal notes/);
});

test('brand importer uses a bounded HTML stream rather than rejecting a large site by Content-Length',()=>{
  const fs=require('node:fs');
  const generator=fs.readFileSync(require.resolve('../scripts/configure-corpus-brand.mjs'),'utf8');
  const ui=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  assert.match(generator,/async function fetchHtmlHead/);
  assert.match(generator,/getReader\(\)/);
  assert.match(generator,/html = await fetchHtmlHead\(site\.href\)/);
  assert.match(generator,/logoUrl/);
  assert.match(ui,/CORPUS_BRAND\.logoUrl/);
  assert.match(ui,/Internal notes/);
});

test('Siloy logo detection does not treat generic photography as a brand mark',()=>{
  const fs=require('node:fs');
  const generator=fs.readFileSync(require.resolve('../scripts/configure-corpus-brand.mjs'),'utf8');
  assert.match(generator,/brandmark/);
  assert.match(generator,/const alt = valueOf\(tag,'alt'\)\.trim\(\)/);
  assert.match(generator,/officialVector/);
  assert.match(generator,/Never inline remote SVG/);
  assert.doesNotMatch(generator,/\/\\bsiloy\\b\|\\blogo\\b\/i\.test/);
});

test('Siloy lockup keeps official mark, app name and brand-only colour rail without photographs',()=>{
  const fs=require('node:fs');
  const main=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  const rail=fs.readFileSync(require.resolve('../src/app/cards/CorpusQuickRail.jsx'),'utf8');
  const stripe=fs.readFileSync(require.resolve('../src/app/cards/assets/siloy-colour-rail.svg'),'utf8');
  assert.match(main,/Siloy Notes/);
  assert.match(rail,/Siloy Notes/);
  assert.match(main,/<Image src=\{displayedBrandMark\}/);
  assert.match(rail,/<Image src=\{displayedBrandMark\}/);
  assert.match(main,/SILOY_HEADER_URL/);
  assert.match(rail,/SILOY_HEADER_URL/);
  assert.match(stripe,/#010103/);
  assert.match(stripe,/#DAEAFF/);
  assert.match(stripe,/#FEF5AC/);
  assert.match(stripe,/#EAFDD6/);
  assert.doesNotMatch(main,/cover-photo|cover-image|hero-photo|siloy-cover/);
  assert.doesNotMatch(rail,/cover-photo|cover-image|hero-photo|siloy-cover/);
});

test('Siloy branding uses official supplied vector wordmark instead of photographed signage',()=>{
  const fs=require('node:fs');
  const path=require('node:path');
  const main=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  const rail=fs.readFileSync(require.resolve('../src/app/cards/CorpusQuickRail.jsx'),'utf8');
  const logo=fs.readFileSync(path.resolve(__dirname,'../src/app/cards/assets/siloy-official-logo-black.svg'),'utf8');
  assert.ok(main.includes('siloy-notes-header.svg'));
  assert.ok(rail.includes('siloy-notes-header.svg'));
  assert.match(logo,/viewBox="0 0 1000 300"/);
  assert.match(logo,/<path/);
  assert.ok(!main.includes('siloy-signage-mark.svg'));
  assert.ok(!rail.includes('siloy-signage-mark.svg'));
});


test('Refined Notes workspace stays compact until authoring and focus mode opens editor',()=>{
  const fs=require('node:fs');
  const main=fs.readFileSync(require.resolve('../src/app/cards/CorpusNoteCard.jsx'),'utf8');
  assert.match(main,/const \[composerOpen, setComposerOpen\] = useState\(false\)/);
  assert.match(main,/width=\{440\}/);
  assert.match(main,/if \(!focusWriting\) setComposerOpen\(true\)/);
  assert.match(main,/Never included in meeting invitations/);
});
test('Notes rail defaults to useful recent notes and has clear no-alert states',()=>{
  const fs=require('node:fs');
  const rail=fs.readFileSync(require.resolve('../src/app/cards/CorpusQuickRail.jsx'),'utf8');
  assert.match(rail,/const \[filter, setFilter\] = useState\('all'\)/);
  assert.match(rail,/Notes at a glance/);
  assert.match(rail,/No follow-ups due/);
  assert.match(rail,/No notes with risks/);
  assert.match(rail,/Saved and linked/);
});
