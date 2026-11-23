'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const entry=path.join(__dirname,'RegisterRead.js');
const main=require(entry).main;
const sample=(id,props)=>({id:String(id),properties:props});
(async()=>{
  const originalFetch=global.fetch;
  const originalToken=process.env.PRIVATE_APP_ACCESS_TOKEN;
  try{
    delete process.env.PRIVATE_APP_ACCESS_TOKEN;
    await assert.rejects(main({accountId:149783010}),/Private app access token unavailable/);
    process.env.PRIVATE_APP_ACCESS_TOKEN='local-unit-test-token';
    await assert.rejects(main({accountId:100000}),/developer portal mismatch/);
    let count=0;
    global.fetch=async (url,opts)=>{
      count++;
      assert.match(url,/https:\/\/api\.hubapi\.com\/crm\/v3\/objects\/2-2568783/);
      assert.equal(opts.method,'POST');
      assert.equal(opts.headers.Authorization,'Bearer local-unit-test-token');
      const body=JSON.parse(opts.body);
      assert.equal(body.limit,100);
      const kind=url.includes('2-256878310')?'resources':'entitlements';
      return {ok:true, json:async()=>({results:kind==='resources'?
        [sample(5,{resource_name:'Suite 1.01',resource_code:'SHORE-1.01',sl_capacity:'1',sl_exclusive:'true',sl_operational_status:'active'})]:
        [sample(9,{entitlement_reference:'LIC-0142',entitlement_type:'workspace_property',sl_quantity:'1',sl_status:'active',sl_monthly_fee:'1200',sl_resource_code:'SHORE-1.01'})]})};
    };
    const result=await main({accountId:'149783010'});
    assert.equal(count,2);
    assert.equal(result.portalId,149783010);
    assert.equal(result.resources.length,1);
    assert.equal(result.entitlements.length,1);
    assert.equal(result.resources[0].exclusive,true);
    assert.equal(result.entitlements[0].monthlyFee,1200);
    assert.equal(result.entitlements[0].reference,'LIC-0142');
    assert.equal(JSON.stringify(result).includes('local-unit-test-token'),false);
    assert.equal(result.truncated,false);
    global.fetch=async()=>({ok:false,status:403});
    await assert.rejects(main({accountId:149783010}),/HTTP 403/);
    // Paged result handling: returns the subsequent page rather than only the first 100.
    let page=0;
    global.fetch=async (_,opts)=>{
      const after=JSON.parse(opts.body).after;
      if(!after) return {ok:true,json:async()=>({results:[sample(1,{})],paging:{next:{after:'page2'}}})};
      assert.equal(after,'page2'); page++;
      return {ok:true,json:async()=>({results:[sample(2,{})]})};
    };
    const paged=await main({accountId:149783010});
    assert.equal(page,2);
    assert.equal(paged.resources.length,2);
    assert.equal(paged.entitlements.length,2);
    console.log('PASS 9 assertions groups: auth guard, wrong portal, API request, normalization, no secret leak, error path, pagination.');
  }finally{
    global.fetch=originalFetch;
    if(originalToken===undefined)delete process.env.PRIVATE_APP_ACCESS_TOKEN;
    else process.env.PRIVATE_APP_ACCESS_TOKEN=originalToken;
  }
})().catch(e=>{console.error(e);process.exitCode=1});
