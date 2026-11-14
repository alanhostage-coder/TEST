'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const fn=require('../src/app/functions/SiloyTime.js')._test;
test('week normalisation and date guards',()=>{assert.equal(fn.monday('2026-11-14'),'2026-11-09');assert.equal(fn.date('2026-02-30'),null);});
test('valid time increments',()=>{assert.equal(fn.duration('1.25'),75);assert.equal(fn.duration('1.33'),null);});
test('maps duration to CRM properties',()=>{const p=fn.properties({date:'2026-11-13',start:'09:15',hours:'1.75',billable:true});assert.equal(p.end_time,'2026-11-13T11:00:00.000Z');assert.equal(p.total_minutes_spent,'105');});
test('independent from Notes',()=>{const a=JSON.parse(fs.readFileSync('src/app/app-hsmeta.json'));const ui=fs.readFileSync('src/app/cards/SiloyTimeCard.jsx','utf8');assert.equal(a.config.name,'Siloy Time');assert.match(ui,/<Heading>Siloy Time<\/Heading>/);assert.doesNotMatch(ui,/corpus_notes_api|CorpusNoteCard/);});
