'use strict';
// Read-only HubSpot App Function; uses the private app's injected secret.
// Do not expose an unfiltered API token or use this function for allocating resources.
const PORTAL_ID = 149783010;
const RESOURCE_TYPE = '2-256878310';
const ENTITLEMENT_TYPE = '2-256878303';
const API = 'https://api.hubapi.com/crm/v3/objects/';
const RESOURCE_PROPERTIES = ['resource_name','resource_code','sl_resource_type','sl_site',
 'sl_capacity','sl_exclusive','sl_operational_status'];
const ENTITLEMENT_PROPERTIES = ['entitlement_reference','entitlement_type','sl_status',
 'sl_start_date','sl_end_date','sl_notice_date','sl_quantity','sl_rights','sl_resource_code','sl_monthly_fee'];

async function searchAll(objectType, properties, token) {
  const out=[]; let after; let more=false;
  do {
    const response=await fetch(`${API}${objectType}/search`, {
      method:'POST',
      headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
      body:JSON.stringify({limit:100,properties,...(after?{after}:{})}),
    });
    if(!response.ok){
      throw new Error(`HubSpot ${objectType} search returned HTTP ${response.status}`);
    }
    const page=await response.json();
    out.push(...(page.results||[]));
    after=page.paging?.next?.after;
    more=!!after;
  } while(after && out.length<500);
  return {rows:out,truncated:more};
}
const num=x=>Number(x||0)||0;
const bool=x=>x===true||x==='true';
const resource=r=>({
 id:String(r.id),name:r.properties?.resource_name||'',code:r.properties?.resource_code||'',
 type:r.properties?.sl_resource_type||'',site:r.properties?.sl_site||'',
 capacity:num(r.properties?.sl_capacity),exclusive:bool(r.properties?.sl_exclusive),
 status:r.properties?.sl_operational_status||''
});
const entitlement=r=>({
 id:String(r.id),reference:r.properties?.entitlement_reference||'',
 type:r.properties?.entitlement_type||'',status:r.properties?.sl_status||'',
 start:r.properties?.sl_start_date||'',end:r.properties?.sl_end_date||'',
 notice:r.properties?.sl_notice_date||'',quantity:num(r.properties?.sl_quantity),
 rights:r.properties?.sl_rights||'',resourceCode:r.properties?.sl_resource_code||'',
 monthlyFee:num(r.properties?.sl_monthly_fee)
});
exports.main=async (context={})=>{
 if(context.accountId && Number(context.accountId)!==PORTAL_ID) {
   throw new Error('Siloy Licence developer portal mismatch');
 }
 const token=process.env.PRIVATE_APP_ACCESS_TOKEN;
 if(!token)throw new Error('Private app access token unavailable: install the app in account 149783010.');
 const [rr,er]=await Promise.all([
   searchAll(RESOURCE_TYPE,RESOURCE_PROPERTIES,token),
   searchAll(ENTITLEMENT_TYPE,ENTITLEMENT_PROPERTIES,token)
 ]);
 return {
   portalId:PORTAL_ID,
   asOf:new Date().toISOString(),
   resources:rr.rows.map(resource),
   entitlements:er.rows.map(entitlement),
   truncated:rr.truncated||er.truncated
 };
};
