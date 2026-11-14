'use strict';
/* Siloy Time, independent of Siloy Notes. POC model: 2-143515197 (STT Time Logs). */
const TYPE=process.env.SILOY_TIME_OBJECT_TYPE||'2-143515197';
const PROJECT='0-970',API='https://api.hubapi.com';
const FIELDS=['start_time','end_time','total_hours_spent','total_minutes_spent','description','is_billable','type','hs_object_id'];
const validId=v=>/^\d{1,20}$/.test(String(v||''));
function date(s){if(!/^\d{4}-\d{2}-\d{2}$/.test(String(s||'')))return null;const d=new Date(s+'T00:00:00Z');return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===s?s:null;}
function monday(s){if(!date(s))return null;const d=new Date(s+'T00:00:00Z');d.setUTCDate(d.getUTCDate()-(d.getUTCDay()+6)%7);return d.toISOString().slice(0,10);}
function duration(h){const n=Number(h);return Number.isFinite(n)&&n>=0.25&&n<=16&&Math.abs(n*4-Math.round(n*4))<0.0001?Math.round(n*60):null;}
function properties(raw){
 const d=date(raw.date),time=String(raw.start||''),mins=duration(raw.hours);
 if(!d||!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)||mins===null)throw Object.assign(new Error('Enter a valid day, start time and 15-minute duration.'),{status:400});
 const start=Date.parse(d+'T'+time+':00Z');
 return {start_time:new Date(start).toISOString(),end_time:new Date(start+mins*60000).toISOString(),total_hours_spent:String(mins/60),total_minutes_spent:String(mins),description:String(raw.description||'').trim().slice(0,2000),is_billable:String(raw.billable)==='true'?'true':'false',type:'manual'};
}
function ok(data){return {statusCode:200,body:{success:true,...data}};}
function fail(statusCode,error,extra={}){return {statusCode,body:{success:false,error,...extra}};}
async function api(token,path,opt={}){
 const r=await fetch(API+path,{method:opt.method||'GET',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(opt.body?{body:JSON.stringify(opt.body)}:{})});
 let data={};try{data=await r.json();}catch{}
 if(!r.ok)throw Object.assign(new Error('HubSpot '+r.status+': '+String(data.message||'Request failed').slice(0,160)),{status:r.status});
 return data;
}
async function ids(token,from,id,to,max=10){
 const results=[];let after;
 for(let page=0;page<max;page++){
  const d=await api(token,'/crm/v4/objects/'+from+'/'+id+'/associations/'+to+'?limit=100'+(after?'&after='+encodeURIComponent(after):''));
  for(const row of d.results||[])if(validId(row.toObjectId))results.push(String(row.toObjectId));
  after=d.paging?.next?.after;if(!after)break;
 }
 return results;
}
async function projects(token){
 const result=[];let after;
 for(let i=0;i<3;i++){
  const d=await api(token,'/crm/v3/objects/'+PROJECT+'?properties=hs_name&limit=100'+(after?'&after='+encodeURIComponent(after):''));
  for(const r of d.results||[])result.push({id:String(r.id),name:r.properties?.hs_name||'Project '+r.id});
  after=d.paging?.next?.after;if(!after)break;
 }
 return result.sort((a,b)=>a.name.localeCompare(b.name));
}
async function load(token,contactId,week){
 const from=monday(week);if(!from)return fail(400,'Invalid week.');
 const to=new Date(Date.parse(from+'T00:00:00Z')+7*86400000).toISOString().slice(0,10);
 const allIds=await ids(token,'contacts',contactId,TYPE),entries=[];
 for(let pos=0;pos<allIds.length;pos+=100){
  const d=await api(token,'/crm/v3/objects/'+TYPE+'/batch/read',{method:'POST',body:{inputs:allIds.slice(pos,pos+100).map(id=>({id})),properties:FIELDS}});
  for(const r of d.results||[]){
   const p=r.properties||{},dt=String(p.start_time||'').slice(0,10);
   if(dt<from||dt>=to)continue;
   const minutes=Number(p.total_minutes_spent);
   entries.push({id:String(r.id),date:dt,start:String(p.start_time||'').slice(11,16),hours:Number.isFinite(minutes)&&minutes>0?minutes/60:Number(p.total_hours_spent)||0,description:p.description||'',billable:String(p.is_billable)==='true',projectId:''});
  }
 }
 if(entries.length){
  try{
   const d=await api(token,'/crm/v4/associations/'+TYPE+'/'+PROJECT+'/batch/read',{method:'POST',body:{inputs:entries.map(x=>({id:x.id}))}});
   const map=new Map((d.results||[]).map(x=>[String(x.from?.id),String(x.to?.[0]?.toObjectId||'')]));
   for(const e of entries)e.projectId=map.get(e.id)||'';
  }catch{}
 }
 let projectList=[],projectsError='';
 try{projectList=await projects(token);}catch(e){projectsError='Project picker unavailable: '+e.message;}
 entries.sort((a,b)=>a.date.localeCompare(b.date)||a.start.localeCompare(b.start));
 return ok({entries,projects:projectList,projectsError,truncated:allIds.length>=1000});
}
async function save(token,contactId,params){
 const input=params.entry||{},props=properties(input);
 if(params.action==='create'){
  const projectId=String(input.projectId||'');
  if(!validId(projectId))return fail(400,'Choose a HubSpot Project.');
  await api(token,'/crm/v3/objects/'+PROJECT+'/'+projectId+'?properties=hs_name');
  const r=await api(token,'/crm/v3/objects/'+TYPE,{method:'POST',body:{properties:props}});
  if(!validId(r.id))return fail(502,'Time Log ID missing.');
  try{
   await api(token,'/crm/v4/objects/'+TYPE+'/'+r.id+'/associations/default/contacts/'+contactId,{method:'PUT'});
   await api(token,'/crm/v4/objects/'+TYPE+'/'+r.id+'/associations/default/'+PROJECT+'/'+projectId,{method:'PUT'});
  }catch(e){return fail(207,'Log '+r.id+' was saved but association failed. Do not retry blindly.',{partial:true,entryId:String(r.id)});}
  return ok({entryId:String(r.id)});
 }
 const entryId=String(input.id||'');
 if(!validId(entryId))return fail(400,'Invalid entry ID.');
 if(!(await ids(token,TYPE,entryId,'contacts',2)).includes(contactId))return fail(403,'Entry is not linked to this Contact.');
 await api(token,'/crm/v3/objects/'+TYPE+'/'+entryId,{method:'PATCH',body:{properties:props}});
 return ok({entryId});
}
exports.main=async context=>{
 const token=process.env.PRIVATE_APP_ACCESS_TOKEN,p=context?.parameters||{},contactId=String(p.contactId||'');
 if(!token)return fail(503,'App not installed.');
 if(!validId(contactId))return fail(400,'Open a Contact record.');
 try{
  if(p.action==='load')return await load(token,contactId,p.week);
  if(p.action==='create'||p.action==='update')return await save(token,contactId,p);
  return fail(400,'Unsupported action.');
 }catch(e){return fail(e.status>=400&&e.status<500?e.status:502,String(e.message||e).slice(0,260));}
};
exports._test={date,monday,duration,properties,validId};
