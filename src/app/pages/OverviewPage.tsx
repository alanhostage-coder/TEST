import React,{useEffect,useState} from 'react';
import {Button,Divider,Flex,Heading,Link,Select,Text,Tile,hubspot} from '@hubspot/ui-extensions';
import {PageTitle} from '@hubspot/ui-extensions/pages';
type Risk='high'|'medium'|'low';
type Deal={id:string;name:string;amount:number;stage:string;pipeline:string;priority:number;level:Risk;
  recommendation:string;leadingFactor:string;storedStatus:string|null;dataQuality:string[]};
type Report={deals:Deal[];summary:{assessed:number;high:number;medium:number;low:number;attentionValue:number};
  totalOpen:number;scanned:number;incomplete:boolean;scope:string;assessedAt:string;mode:string};
const PREVIEW:Deal[]=[
  {id:'preview-1',name:'Eastbank Academy Expansion',amount:168000,stage:'Decision',pipeline:'Preview',priority:85,level:'high',leadingFactor:'Close date overdue',recommendation:'Confirm procurement approval and reset the close date.',storedStatus:null,dataQuality:[]},
  {id:'preview-2',name:'Northshore Science Labs Fit-Out',amount:245000,stage:'Proposal',pipeline:'Preview',priority:65,level:'high',leadingFactor:'No follow-up and no recent contact',recommendation:'Call the project lead to confirm the tender milestone.',storedStatus:null,dataQuality:[]},
  {id:'preview-3',name:'Cedarfield Learning Trust Furniture',amount:87000,stage:'Discovery',pipeline:'Preview',priority:45,level:'medium',leadingFactor:'Missing next activity',recommendation:'Book an evaluation meeting with the facilities team.',storedStatus:null,dataQuality:[]},
  {id:'preview-4',name:'Westmere College Renewal',amount:76500,stage:'Qualification',pipeline:'Preview',priority:30,level:'medium',leadingFactor:'No next step logged',recommendation:'Confirm budget holder and agree the next step.',storedStatus:null,dataQuality:[]},
  {id:'preview-5',name:'Portland Campus Classroom Refresh',amount:42000,stage:'Proposal',pipeline:'Preview',priority:10,level:'low',leadingFactor:'No material escalation',recommendation:'Maintain the agreed follow-up date.',storedStatus:null,dataQuality:[]}
];
const formatPounds=(n:number)=>'£'+(Number.isFinite(n)?n:0).toLocaleString('en-GB',{maximumFractionDigits:0});
export const OverviewPage=()=>{
  const [report,setReport]=useState<Report|null>(null);
  const [busy,setBusy]=useState(false),[error,setError]=useState('');
  const [filter,setFilter]=useState('all'),[previewMode,setPreviewMode]=useState(false);
  async function load(){
    setBusy(true);setError('');
    try{
      const data=await hubspot.serverless('sri_triage_queue') as Report;
      setReport(data);
      // Scenario preview is opt-in and never represented as HubSpot data.
      setPreviewMode(false);
    }catch(e){setError('Unable to load live deals: '+String(e));}
    finally{setBusy(false);}
  }
  useEffect(()=>{void load();},[]);
  const real=report?.deals||[];
  const isPreview=previewMode&&real.length===0&&!error;
  const all=isPreview?PREVIEW:real;
  const shown=all.filter(d=>filter==='all'||d.level===filter);
  const high=all.filter(d=>d.level==='high');
  const highValue=high.reduce((s,d)=>s+d.amount,0);
  return <Flex direction="column" gap="md">
    <PageTitle>Siloy Revenue Intelligence</PageTitle>
    <Text>Commercial decisions. Grounded in your CRM.</Text>
    <Flex direction="row" gap="sm">
      <Tile><Heading>Find</Heading><Text>Prospect coverage · Planned</Text></Tile>
      <Tile><Heading>Insight</Heading><Text>Pipeline patterns · Planned</Text></Tile>
      <Tile><Heading>Action</Heading><Text>Deal triage · Available</Text></Tile>
    </Flex>
    <Divider/>
    <Heading>Action · Live Triage</Heading>
    <Text>Read-only on-demand assessment, ranked by attention needed. Not a win probability or predicted loss.</Text>
    {busy&&<Text>Loading live CRM snapshot…</Text>}
    {error&&<Text>{error}</Text>}
    {report&&!busy&&!error&&<>
      <Text>{'Live CRM: '+report.totalOpen+' open Deals · '+report.scanned+' scanned · Last loaded '+new Date(report.assessedAt).toLocaleString('en-GB')}</Text>
      {report.incomplete&&<Text>Coverage notice: at most 100 recently modified open Deals are scored, so this is a sample, not a whole-pipeline ranking.</Text>}
      <Text>Contact-association risk is excluded from this queue because bulk-search association counts are unavailable. The in-record card performs a fuller assessment.</Text>
    </>}
    {report&&!busy&&!error&&real.length===0&&<>
      <Tile><Heading>Your portal has no open Deals</Heading><Text>The application is installed, but live scoring cannot be demonstrated on an actual opportunity without an approved CRM record.</Text></Tile>
      <Button variant="secondary" onClick={()=>{setPreviewMode(v=>!v);setFilter('all');}}>
        {previewMode?'Hide scenario preview':'Explore a five-opportunity scenario preview'}
      </Button>
    </>}
    {isPreview&&<Text>SCENARIO PREVIEW ONLY · These opportunities are illustrative and do not exist in HubSpot. No CRM records are created.</Text>}
    {(all.length>0&&!busy)&&<>
      <Flex direction="row" gap="sm">
        <Tile><Heading>{String(all.length)}</Heading><Text>{isPreview?'Example opportunities':'Open Deals scanned'}</Text></Tile>
        <Tile><Heading>{String(high.length)}</Heading><Text>High attention</Text></Tile>
        <Tile><Heading>{formatPounds(highValue)}</Heading><Text>High-attention deal value, not forecast loss</Text></Tile>
      </Flex>
      <Select label="Attention filter" name="priorityFilter" value={filter} onChange={v=>setFilter(v as string)}
        options={[{label:'All attention levels',value:'all'},{label:'High',value:'high'},{label:'Medium',value:'medium'},{label:'Low',value:'low'}]}/>
      {shown.length===0&&<Text>No opportunities match this filter.</Text>}
      {shown.map((d,index)=><Tile key={d.id}>
        <Flex direction="column" gap="xs">
          <Heading>{(index+1)+'. '+d.name}</Heading>
          <Text>{d.priority+'/100 · '+d.level.toUpperCase()+' attention · '+formatPounds(d.amount)+' · '+d.stage}</Text>
          <Text>{'Leading factor: '+d.leadingFactor}</Text>
          <Text>{'Suggested action: '+d.recommendation}</Text>
          {!isPreview&&<Text>{'Saved review: '+(d.storedStatus||'Not assessed')}</Text>}
          {!isPreview&&<Link href={'https://app-eu1.hubspot.com/contacts/149783010/record/0-3/'+d.id}>Open deal to inspect and save assessment</Link>}
        </Flex>
      </Tile>)}
    </>}
    <Button variant="secondary" disabled={busy} onClick={()=>void load()}>Refresh live snapshot</Button>
    <Divider/>
    <Heading>Operational safeguards</Heading>
    <Text>Routine triage consumes zero HubSpot AI credits. Scores are calculated on demand without modifying Deal records. A user must deliberately save an assessment on its Deal card; tasks and emails are never sent automatically.</Text>
  </Flex>;
};
