'use strict';
const assert = require('node:assert/strict');
const x = require('../src/app/functions/CreditUsage.js')._test;
const rows = [
  {id:'1',properties:{usage_name:'Example',credits_used:'125',credit_limit:'100',data_method:'reconciled_estimate',heat_level:'hot'}},
  {id:'2',properties:{usage_name:'Example',credits_used:'125',credit_limit:'100',data_method:'actual',heat_level:'hot'}}
];
const a = x.analyze(rows);
assert.equal(a.records,2);
assert.equal(a.unperiodised,2);
assert.equal(a.canDisplayBillingTotal,false);
assert.equal(a.status,'PERIODS_MISSING');
assert.equal(a.hotspots.length,2);
const b = x.analyze(rows,true);
assert.equal(b.status,'INCOMPLETE');
const c = x.analyze([{id:'3',properties:{usage_name:'X',period_key:'90d',period_start:'2026-08-22',period_end:'2026-11-19',is_sample:'true'}}]);
assert.equal(c.periodised,true);
assert.equal(c.illustrativeCount,1);
assert.equal(c.canDisplayBillingTotal,false);
console.log('PASS backend snapshot provenance and anti-double-count guards');
