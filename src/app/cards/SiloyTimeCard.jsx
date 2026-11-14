import React,{useCallback,useEffect,useRef,useState} from 'react';
import {hubspot,Heading,Text,Input,TextArea,Select,Button,Divider,Flex,Tile,Tag,Image,LoadingSpinner} from '@hubspot/ui-extensions';
import {CORPUS_BRAND} from './brand-config';
const RAIL='https://raw.githubusercontent.com/alanhostage-coder/TEST/refs/heads/codex/siloy-time-enterprise/src/app/cards/assets/siloy-colour-rail.svg';
const SILOY_MARK='https://raw.githubusercontent.com/alanhostage-coder/TEST/refs/heads/codex/siloy-time-enterprise/src/app/cards/assets/siloy-signage-mark.svg';
const isSiloyBrand=/^https:\/\/(?:www\.)?siloy\.com(?:\/|$)/i.test(CORPUS_BRAND.websiteUrl||'');
const displayedBrandMark=isSiloyBrand?SILOY_MARK:CORPUS_BRAND.logoUrl;
const NAMES=['Monday','Tuesday','Wednesday','Thursday','Friday'];
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
 const contactId=String(context?.crm?.objectId||'');
 const [week,setWeek]=useState(()=>monday(iso(new Date())));
 const [rows,setRows]=useState([]),[projects,setProjects]=useState([]);
 const [projectsError,setProjectsError]=useState(''),[error,setError]=useState('');
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false);
 const [receipt,setReceipt]=useState(''),[open,setOpen]=useState(true),[dirty,setDirty]=useState(false);
 const [form,setForm]=useState(()=>blank(monday(iso(new Date()))));
 const [truncated,setTruncated]=useState(false);
 const pending=useRef(false);
 const days=NAMES.map((name,i)=>({name,date:shift(week,i)}));
 const hours=total(rows),billable=total(rows.filter(r=>r.billable));
 const update=(k,v)=>{setForm(old=>({...old,[k]:v}));setDirty(true);setError('');setReceipt('');};
 const reload=useCallback(async()=>{
  if(!/^\d+$/.test(contactId)){setError('Open a Contact record to use Siloy Time.');setLoading(false);return;}
  setLoading(true);
  try{
   const out=unwrap(await hubspot.serverless('siloy_time_api',{parameters:{action:'load',contactId,week}}));
   if(!out.success)throw new Error(out.error||'Unable to load timesheets.');
   setRows(out.entries||[]);setProjects(out.projects||[]);setProjectsError(out.projectsError||'');
   setTruncated(Boolean(out.truncated));setError('');
  }catch(e){setError(String(e.message||e));}finally{setLoading(false);}
 },[contactId,week]);
 useEffect(()=>{reload();},[reload]);
 const fresh=date=>{
  if(dirty){alert({type:'warning',title:'Unsaved time',message:'Save or clear the form before adding another entry.'});return;}
  setForm(blank(date));setDirty(false);setReceipt('');setOpen(true);
 };
 const edit=row=>{
  if(dirty){alert({type:'warning',title:'Unsaved time',message:'Save or clear the form before editing a different entry.'});return;}
  setForm({id:row.id,date:row.date,start:row.start||'09:00',projectId:row.projectId,
   hours:String(row.hours||1),description:row.description||'',billable:String(row.billable)});
  setDirty(false);setError('');setReceipt('');setOpen(true);
 };
 const navigate=n=>{
  if(dirty){alert({type:'warning',title:'Unsaved time',message:'Save or clear the form before changing weeks.'});return;}
  const target=n===0?monday(iso(new Date())):shift(week,n*7);
  setWeek(target);setForm(blank(target));setReceipt('');setOpen(false);
 };
 const save=async()=>{
  if(pending.current)return;
  let issue='';
  if(!/^\d+$/.test(contactId))issue='Open a Contact first.';
  else if(!form.id&&!/^\d+$/.test(form.projectId))issue='Choose a HubSpot Project.';
  else if(!days.some(d=>d.date===form.date))issue='Choose a day in this week.';
  else if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(form.start))issue='Enter start time as HH:MM.';
  else if(!Number.isFinite(Number(form.hours))||Number(form.hours)<0.25||Number(form.hours)>16||Math.abs(Number(form.hours)*4-Math.round(Number(form.hours)*4))>0.0001)issue='Hours must be 0.25 to 16, in 15-minute increments.';
  if(issue){setError(issue);alert({type:'danger',title:'Check the entry',message:issue});return;}
  pending.current=true;setSaving(true);setError('');setReceipt('');
  try{
   const out=unwrap(await hubspot.serverless('siloy_time_api',{parameters:{
    action:form.id?'update':'create',contactId,entry:{...form,billable:form.billable==='true'}
   }}));
   if(!out.success){
    if(out.partial)setReceipt('Time Log '+out.entryId+' created; association requires review. Do not retry blindly.');
    throw new Error(out.error||'Save not confirmed.');
   }
   setReceipt('Saved HubSpot Time Log #'+out.entryId);setDirty(false);setOpen(false);
   setForm(blank(form.date));await reload();
   alert({type:'success',title:'Time saved',message:'Saved to HubSpot and associated with the Contact.'});
  }catch(e){const msg=String(e.message||e);setError(msg);alert({type:'danger',title:'Save not confirmed',message:msg});}
  finally{setSaving(false);pending.current=false;}
 };
 return <>
  <Tile>
   <Flex direction="row" gap="medium" align="center" wrap="wrap">
    {displayedBrandMark?<Image src={displayedBrandMark} alt="Official Siloy brand mark" width={64}/>:null}
    <Flex direction="column" gap="small">
     <Heading>Siloy Time</Heading>
     <Text variant="microcopy">by Siloy UKI · Enterprise timesheets</Text>
    </Flex>
   </Flex>
   <Image src={RAIL} width={900} alt="Siloy blue, yellow and mint brand colours"/>
   <Flex direction="row" wrap="wrap" gap="small"><Tag variant="info">PROJECT TIME</Tag><Tag variant="default">Contact workspace</Tag><Tag variant="success">Independent app</Tag></Flex>
  </Tile>
  <Text>Log project work and keep track of the week without leaving HubSpot.</Text>
  <Divider/>
  <Tile>
   <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
    <Heading>01 / Your week</Heading>
    <Flex direction="row" gap="small" wrap="wrap">
     <Button variant="secondary" onClick={()=>navigate(-1)}>Previous</Button>
     <Button variant="secondary" onClick={()=>navigate(0)}>This week</Button>
     <Button variant="secondary" onClick={()=>navigate(1)}>Next</Button>
    </Flex>
   </Flex>
   <Text>{uk(week)} to {uk(shift(week,4))}</Text>
   <Flex direction="row" gap="small" wrap="wrap">
    <Tag variant={hours>=40?'success':'info'}>{display(hours)} / 40 h</Tag>
    <Tag variant="default">{display(billable)} billable</Tag>
    <Tag variant="default">{rows.length} entries</Tag>
   </Flex>
   {loading?<LoadingSpinner label="Loading time records"/>:null}
   {error?<Text>{error}</Text>:null}
   {projectsError?<Text>{projectsError}</Text>:null}
   {truncated?<Text>More than 1,000 associated records. Older entries may require pagination.</Text>:null}
  </Tile>
  <Divider/>
  <Tile>
   <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
    <Heading>02 / Daily allocation</Heading>
    <Button variant="secondary" disabled={loading} onClick={reload}>Refresh</Button>
   </Flex>
   {days.map(d=>{
    const items=rows.filter(row=>row.date===d.date),used=total(items);
    return <React.Fragment key={d.date}>
     <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
      <Text>{d.name} · {uk(d.date)}</Text>
      <Tag variant={used>=8?'success':'default'}>{display(used)} / 8 h</Tag>
      <Button variant="secondary" onClick={()=>fresh(d.date)}>Add time</Button>
     </Flex>
     {items.length?items.map(e=><Flex key={e.id} direction="row" gap="small" justify="between" align="center" wrap="wrap">
       <Flex direction="column" gap="small">
        <Text>{projects.find(p=>p.id===e.projectId)?.name||'Project unassigned'} · {display(e.hours)}</Text>
        <Text variant="microcopy">{e.start} · {e.billable?'Billable':'Non-billable'}{e.description?' · '+e.description:''}</Text>
       </Flex>
       <Button variant="secondary" onClick={()=>edit(e)}>Edit</Button>
      </Flex>):<Text variant="microcopy">No entries yet</Text>}
     <Divider/>
    </React.Fragment>;
   })}
  </Tile>
  <Tile>
   <Flex direction="row" gap="small" justify="between" align="center" wrap="wrap">
    <Heading>03 / {form.id?'Edit entry':'Record time'}</Heading>
    <Button variant="secondary" onClick={()=>setOpen(v=>!v)}>{open?'Hide form':'Open form'}</Button>
   </Flex>
   {receipt?<Tag variant="success">{receipt}</Tag>:null}
   {open?<>
    <Select label="Day" options={days.map(d=>({label:d.name+' · '+uk(d.date),value:d.date}))} value={form.date} onChange={v=>update('date',v)}/>
    <Select label="HubSpot Project" value={form.projectId} onChange={v=>update('projectId',v)}
     options={[{label:'Select a project',value:''},...projects.map(p=>({label:p.name,value:p.id}))]}
     disabled={Boolean(form.id)}/>
    {form.id?<Text variant="microcopy">Project assignment cannot be changed when editing. Use a new entry for another project.</Text>:null}
    <Flex direction="row" gap="small" wrap="wrap">
     <Input label="Start time (HH:MM)" value={form.start} onChange={v=>update('start',v)}/>
     <Input label="Hours" value={form.hours} onChange={v=>update('hours',v)}/>
    </Flex>
    <Select label="Billing" value={form.billable} onChange={v=>update('billable',v)}
     options={[{label:'Billable',value:'true'},{label:'Non-billable',value:'false'}]}/>
    <TextArea label="Work carried out" value={form.description} onChange={v=>update('description',v)}/>
    <Flex direction="row" gap="small" wrap="wrap">
     <Button variant="primary" disabled={saving||loading} onClick={save}>{saving?'Saving...':form.id?'Save changes':'Save time'}</Button>
     <Button variant="secondary" disabled={saving} onClick={()=>{setForm(blank(form.date));setDirty(false);setError('');}}>Clear form</Button>
    </Flex>
    <Text variant="microcopy">Stored as an STT Time Log linked to this Contact and to a HubSpot Project. Native CRM permissions apply.</Text>
   </>:null}
  </Tile>
 </>;
}
