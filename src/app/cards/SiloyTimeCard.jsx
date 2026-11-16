import React,{useCallback,useEffect,useRef,useState} from 'react';
import {hubspot,Heading,Text,Input,TextArea,Select,Button,Divider,Flex,Tile,Tag,Tooltip,Image,Link,LoadingSpinner} from '@hubspot/ui-extensions';
import {CORPUS_BRAND} from './brand-config';
const isSiloyBrand=/^https:\/\/(?:www\.)?siloy\.com(?:\/|$)/i.test(CORPUS_BRAND.websiteUrl||'');
const SILOY_HEADER='https://raw.githubusercontent.com/alanhostage-coder/TEST/refs/heads/codex/siloy-time-enterprise/src/app/cards/assets/siloy-time-header.svg';
const displayedBrandMark=isSiloyBrand?SILOY_HEADER:CORPUS_BRAND.logoUrl;
const NAMES=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
const TYPES={'0-1':'contacts','0-2':'companies','0-3':'deals','0-5':'tickets'};
const LABELS={contacts:'Contact',companies:'Company',deals:'Deal',tickets:'Ticket'};
function iso(d){return d.toISOString().slice(0,10);}
function monday(v){const d=new Date(v.slice(0,10)+'T00:00:00Z');d.setUTCDate(d.getUTCDate()-(d.getUTCDay()+6)%7);return iso(d);}
function shift(v,n){const d=new Date(v+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return iso(d);}
function uk(v){return new Date(v+'T00:00:00Z').toLocaleDateString('en-GB',{timeZone:'UTC'});}
function blank(date){return {date,start:'09:00',projectId:'',hours:'1',description:'',billable:'true',id:''};}
function unwrap(v){return v?.body||v||{};}
function total(rows){return rows.reduce((sum,e)=>sum+Number(e.hours||0),0);}
function display(v){return Math.round(v*100)/100+' h';}
hubspot.extend(({context,actions})=><TimeCard context={context} alert={actions.addAlert}/>);
function TimeCard({context,alert}){
 const recordType=TYPES[String(context?.crm?.objectTypeId||'')]||'';
 const recordId=String(context?.crm?.objectId||'');
 const portalId=String(context?.portal?.id||'149783010');
 const [week,setWeek]=useState(()=>monday(iso(new Date())));
 const [rows,setRows]=useState([]),[projects,setProjects]=useState([]);
 const [projectsError,setProjectsError]=useState(''),[error,setError]=useState('');
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false);
 const [receipt,setReceipt]=useState(null),[open,setOpen]=useState(false),[dirty,setDirty]=useState(false);
 const [resetArmed,setResetArmed]=useState(false);
 const [form,setForm]=useState(()=>blank(monday(iso(new Date()))));
 const [truncated,setTruncated]=useState(false);
 const pending=useRef(false);
 const latestLoad=useRef(0);
 const days=NAMES.map((name,i)=>({name,date:shift(week,i)}));
 const hours=total(rows),billable=total(rows.filter(r=>r.billable));
 const update=(k,v)=>{setForm(old=>({...old,[k]:v}));setDirty(true);setResetArmed(false);setError('');};
 const reload=useCallback(async()=>{
  const request=++latestLoad.current;
  if(!recordType||!/^\d+$/.test(recordId)){setError('Open a supported CRM record to use Siloy Time.');setLoading(false);return;}
  setLoading(true);
  try{
   const out=unwrap(await hubspot.serverless('siloy_time_api',{parameters:{action:'load',recordType,recordId,week}}));
   if(request!==latestLoad.current)return;
   if(!out.success)throw new Error(out.error||'Unable to load timesheets.');
   setRows(out.entries||[]);setProjects(out.projects||[]);setProjectsError(out.projectsError||'');
   setTruncated(Boolean(out.truncated));setError('');
  }catch(e){if(request===latestLoad.current)setError(String(e.message||e));}
  finally{if(request===latestLoad.current)setLoading(false);}
 },[recordType,recordId,week]);
 useEffect(()=>{reload();},[reload]);
 const fresh=date=>{
  if(dirty){alert({type:'warning',title:'Unsaved time',message:'Save or clear the form before adding another entry.'});return;}
  setForm(blank(date));setDirty(false);setResetArmed(false);setOpen(true);
 };
 const edit=row=>{
  if(dirty){alert({type:'warning',title:'Unsaved time',message:'Save or clear the form before editing a different entry.'});return;}
  setForm({id:row.id,date:row.date,start:row.start||'09:00',projectId:row.projectId,
   hours:String(row.hours||1),description:row.description||'',billable:String(row.billable)});
  setDirty(false);setResetArmed(false);setError('');setOpen(true);
 };
 const navigate=n=>{
  if(dirty){alert({type:'warning',title:'Unsaved time',message:'Save or clear the form before changing weeks.'});return;}
  const target=n===0?monday(iso(new Date())):shift(week,n*7);
  if(target===week)return;
  latestLoad.current++;
  setLoading(true);setRows([]);setTruncated(false);setError('');
  setWeek(target);setForm(blank(target));setOpen(false);setResetArmed(false);
 };
 const clear=()=>{
  if(dirty&&!resetArmed){setResetArmed(true);return;}
  setForm(blank(form.date));setDirty(false);setResetArmed(false);setError('');
 };
 const save=async()=>{
  if(pending.current)return;
  let issue='';
  if(!recordType||!/^\d+$/.test(recordId))issue='Open a supported CRM record first.';
  else if(!String(form.description||'').trim())issue='Describe the work carried out.';
  else if(!days.some(d=>d.date===form.date))issue='Choose a day in this week.';
  else if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(form.start))issue='Enter start time as HH:MM.';
  else if(!Number.isFinite(Number(form.hours))||Number(form.hours)<0.25||Number(form.hours)>16||Math.abs(Number(form.hours)*4-Math.round(Number(form.hours)*4))>0.0001)issue='Hours must be 0.25 to 16, in 15-minute increments.';
  if(issue){setError(issue);alert({type:'danger',title:'Check the entry',message:issue});return;}
  pending.current=true;setSaving(true);setError('');
  try{
   const out=unwrap(await hubspot.serverless('siloy_time_api',{parameters:{
    action:form.id?'update':'create',recordType,recordId,entry:{...form,billable:form.billable==='true'}
   }}));
   if((!out.success&&!out.partial)||!out.entryId)throw new Error(out.error||'Save not confirmed.');
   setReceipt({id:out.entryId,partial:Boolean(out.partial),objectTypeId:out.objectTypeId||''});
   setDirty(false);setResetArmed(false);setOpen(false);setForm(blank(form.date));
   alert(out.partial
    ?{type:'warning',title:'Time Log created',message:'Open the saved record to review its CRM and Project links.'}
    :{type:'success',title:'Time saved',message:'The timesheet entry is saved.'});
   void reload();
  }catch(e){const msg=String(e.message||e);setError(msg);alert({type:'danger',title:'Save not confirmed',message:msg});}
  finally{setSaving(false);pending.current=false;}
 };
 return <>
  <Tile>
   <Flex direction="row" gap="medium" align="center" wrap="wrap">
    {displayedBrandMark?<Image src={displayedBrandMark} alt="Siloy Time" width={440}/>:null}
    <Flex direction="column" gap="small">

     <Text variant="microcopy">Weekly timesheet</Text>
    </Flex>
   </Flex>
  </Tile>
  <Text variant="microcopy">Time linked to this {LABELS[recordType]||'CRM record'} · Monday to Sunday</Text>
  <Divider/>
  <Tile>
   <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
    <Heading>Week at a glance</Heading>
    <Tag variant="info" overlay={<Tooltip placement="bottom">Totals include entries linked to this CRM record for the selected week. They are not individual utilisation targets.</Tooltip>}>About totals</Tag>
    <Flex direction="row" gap="small" wrap="wrap">
     <Button variant="secondary" disabled={saving} onClick={()=>navigate(-1)}>Previous</Button>
     <Button variant="secondary" disabled={saving} onClick={()=>navigate(0)}>This week</Button>
     <Button variant="secondary" disabled={saving} onClick={()=>navigate(1)}>Next</Button>
    </Flex>
   </Flex>
   <Text>{uk(week)} to {uk(shift(week,6))}</Text>
   <Flex direction="row" gap="small" wrap="wrap">
    <Tag variant="info">{display(hours)} total</Tag>
    <Tag variant={billable>0?'success':'default'} overlay={<Tooltip placement="bottom">Billable hours are entries marked Billable on this record, not invoiced amounts.</Tooltip>}>{display(billable)} billable</Tag>
    <Tag variant="default">{rows.length} {rows.length===1?'entry':'entries'}</Tag>
   </Flex>
   {loading?<LoadingSpinner label="Loading time records"/>:null}
   {error?<Text>{error}</Text>:null}
   {projectsError?<Text>{projectsError}</Text>:null}
   {truncated?<Text>More than 1,000 associated records. Older entries may require pagination.</Text>:null}
  </Tile>
  <Divider/>
  <Tile>
   <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
    <Heading>Daily allocation</Heading>
    <Button variant="secondary" disabled={loading} onClick={reload}>Refresh</Button>
   </Flex>
   {days.map(d=>{
    const items=rows.filter(row=>row.date===d.date),used=total(items);
    return <React.Fragment key={d.date}>
     <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
      <Text>{d.name} · {uk(d.date)}</Text>
      <Tag variant="default">{display(used)}</Tag>
      <Button variant="secondary" disabled={saving} onClick={()=>fresh(d.date)}>Add time</Button>
     </Flex>
     {items.map(e=><Flex key={e.id} direction="row" gap="small" justify="between" align="center" wrap="wrap">
       <Flex direction="column" gap="small">
        <Text>{e.description||'Time entry'} · {display(e.hours)}</Text>
        <Text variant="microcopy">{e.start} · {e.billable?'Billable':'Non-billable'}{e.projectId?' · '+(projects.find(p=>p.id===e.projectId)?.name||'Linked Project'):''}</Text>
       </Flex>
       <Button variant="secondary" disabled={saving} onClick={()=>edit(e)}>Edit</Button>
      </Flex>)}
     <Divider/>
    </React.Fragment>;
   })}
  </Tile>
  <Tile>
   <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
    <Heading>{form.id?'Edit entry':'Record time'}</Heading>
    {!open&&dirty?<Tag variant="warning">Draft retained</Tag>:null}
    <Button variant="secondary" onClick={()=>setOpen(v=>!v)}>{open?'Hide form':'Open form'}</Button>
   </Flex>
   {receipt?<Flex direction="row" gap="small" align="center" wrap="wrap">
    <Tag variant={receipt.partial?'warning':'success'}>{receipt.partial?'Created. Check record associations.':'Time saved'}</Tag>
    {/^2-\d+$/.test(receipt.objectTypeId)?<Link href={'https://app-eu1.hubspot.com/contacts/'+portalId+'/record/'+receipt.objectTypeId+'/'+receipt.id}>Open Time Log</Link>:null}
   </Flex>:null}
   {open?<>
    <Select label="Day" disabled={saving} options={days.map(d=>({label:d.name+' · '+uk(d.date),value:d.date}))} value={form.date} onChange={v=>update('date',v)}/>
    <Select label="Project (optional)" value={form.projectId} onChange={v=>update('projectId',v)}
     options={[{label:'No Project',value:''},...projects.map(p=>({label:p.name,value:p.id}))]}
     disabled={saving||Boolean(form.id)}/>
    <Tag variant="info" overlay={<Tooltip>The Project field is optional. This time entry is linked to the current CRM record whether or not a Project is chosen.</Tooltip>}>About projects</Tag>
    {form.id?<Text variant="microcopy">Project assignment cannot be changed when editing. Use a new entry for another project.</Text>:null}
    <Flex direction="row" gap="small" wrap="wrap">
     <Input label="Start time (HH:MM)" disabled={saving} value={form.start} onChange={v=>update('start',v)}/>
     <Input label="Hours" disabled={saving} value={form.hours} onChange={v=>update('hours',v)}/>
    </Flex>
    <Flex direction="row" gap="small" align="center" wrap="wrap">
     <Text variant="microcopy">Quick durations</Text>
     <Tag variant="info" overlay={<Tooltip>Choose a preset or enter a custom duration in 15-minute increments.</Tooltip>}>About durations</Tag>
     {['0.25','0.5','1','2'].map(value=><Button key={value} variant="secondary" disabled={saving} onClick={()=>update('hours',value)}>{value} h</Button>)}
    </Flex>
    <Select label="Billing" disabled={saving} value={form.billable} onChange={v=>update('billable',v)}
     options={[{label:'Billable',value:'true'},{label:'Non-billable',value:'false'}]}/>
    <TextArea label="Work carried out" disabled={saving} value={form.description} onChange={v=>update('description',v)}/>
    <Flex direction="row" gap="small" wrap="wrap">
     <Button variant="primary" disabled={saving||loading} onClick={save}>{saving?'Saving...':form.id?'Save changes':'Save time'}</Button>
     <Button variant="secondary" disabled={saving} onClick={clear}>{dirty&&resetArmed?'Confirm clear':'Clear form'}</Button>
    </Flex>
    <Text variant="microcopy">Stored as a Siloy Time entry linked to this {LABELS[recordType]||'CRM record'}. A HubSpot Project link is optional. User-level access control is not yet enabled. Administrators must restrict this pilot to authorised staff.</Text>
   </>:null}
  </Tile>
 </>;
}
