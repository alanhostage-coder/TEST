import React, { useEffect, useMemo, useState } from 'react';
import { Divider, Flex, Heading, Link, Select, Text, Tile, Button, hubspot } from '@hubspot/ui-extensions';
import {
  createPageRouter, PageRoutes, PageTitle,
  PageBreadcrumbs, PageLink
} from '@hubspot/ui-extensions/pages';

// The app function returns live CRM data. Grant/revoke writes are intentionally
// NOT part of this view until a transaction-safe allocation authority is deployed.
type Resource = {
  id: string; name: string; code: string; type: string; site: string;
  capacity: number; exclusive: boolean; status: string;
};
type Entitlement = {
  id: string; reference: string; type: string; status: string;
  start: string; end: string; notice: string; quantity: number;
  resourceCode: string; rights: string; monthlyFee: number;
};
type Register = { portalId: number; asOf: string; resources: Resource[];
  entitlements: Entitlement[]; truncated: boolean };

const recordUrl = (kind: 'resource' | 'entitlement', id: string) =>
  `https://app-eu1.hubspot.com/contacts/149783010/record/${kind === 'resource' ? '2-256878310' : '2-256878303'}/${id}`;
const gbp = (n: number) => `£${Number(n || 0).toLocaleString('en-GB', {maximumFractionDigits: 2})}`;
const typeName: Record<string,string> = {
  workspace_property:'Workspace & Property', furniture_equipment:'Furniture & Equipment',
  facilities_access:'Facilities & Access'
};
const dateUK = (key: string) => /^\d{4}-\d{2}-\d{2}$/.test(key) ? key.split('-').reverse().join('/') : '—';
const todayLondon = () => {
  const p = new Intl.DateTimeFormat('en-GB', {timeZone: 'Europe/London', year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());
  const get=(t:string)=>p.find(x=>x.type===t)?.value || '00';
  return `${get('year')}-${get('month')}-${get('day')}`;
};
const daysUntil = (date: string) => date
  ? Math.round((Date.parse(date+'T00:00:00Z')-Date.parse(todayLondon()+'T00:00:00Z'))/86400000)
  : null;

function useRegister() {
  const [data, setData] = useState<Register|null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string|null>(null);
  async function refresh() {
    setLoading(true);setError(null);
    try {
      const response = await hubspot.serverless('siloy_register_read') as Register;
      if (!response || response.portalId !== 149783010) throw new Error('Wrong portal response');
      setData(response);
    } catch(e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally { setLoading(false); }
  }
  useEffect(() => { void refresh(); }, []);
  return {data,loading,error,refresh};
}

const Intro = ({title}:{title:string}) => <>
  <PageBreadcrumbs>
    <PageBreadcrumbs.PageLink to="/">Siloy Licence</PageBreadcrumbs.PageLink>
    <PageBreadcrumbs.Current>{title}</PageBreadcrumbs.Current>
  </PageBreadcrumbs>
  <PageTitle>{title}</PageTitle>
</>;

const Loading = ({loading,error,refresh}:{loading:boolean,error:string|null,refresh:()=>Promise<void>}) => <>
  {loading && <Text>Loading live CRM records…</Text>}
  {error && <Text>Unable to load CRM data: {error}. Check private-app scopes and serverless logs.</Text>}
  <Button variant="secondary" onClick={()=>{void refresh();}}>Refresh HubSpot data</Button>
</>;

function Home() {
  const {data,loading,error,refresh}=useRegister();
  const stats=useMemo(()=>{
    if(!data)return null;
    const today=todayLondon();
    const active=data.entitlements.filter(e=>e.status==='active'&&e.start<=today&&e.end>=today);
    const due=data.entitlements.filter(e=>e.status==='active'&&e.notice&&e.notice>=today&&
      daysUntil(e.notice)!==null&&daysUntil(e.notice)! <= 30);
    return {active:active.length,due:due.length,resources:data.resources.length,
      total:data.entitlements.length,fees:active.reduce((n,e)=>n+e.monthlyFee,0)};
  },[data]);
  return <>
    <PageBreadcrumbs><PageBreadcrumbs.Current>Siloy Licence</PageBreadcrumbs.Current></PageBreadcrumbs>
    <PageTitle>Siloy Licence</PageTitle>
    <Text>Know who has the right to use what, where, and until when.</Text>
    <Divider/>
    <Loading loading={loading} error={error} refresh={refresh}/>
    {data&&stats&&<>
      <Flex direction="row" gap="md">
        <Tile><Heading>{stats.resources} resources</Heading><Text>Managed in HubSpot</Text></Tile>
        <Tile><Heading>{stats.active} active</Heading><Text>Current entitlements</Text></Tile>
        <Tile><Heading>{stats.due} due soon</Heading><Text>Notice deadlines in 30 days</Text></Tile>
        <Tile><Heading>{gbp(stats.fees)}</Heading><Text>Monthly fees of active records</Text></Tile>
      </Flex>
      <Divider/>
      <Flex direction="row" gap="md">
        <Tile><PageLink to="/entitlements">View entitlement register</PageLink></Tile>
        <Tile><PageLink to="/resources">View resource register</PageLink></Tile>
        <Tile><PageLink to="/availability">Check resource availability</PageLink></Tile>
        <Tile><PageLink to="/renewals">Review notice dates</PageLink></Tile>
        <Tile><PageLink to="/settings">Product settings and safety limits</PageLink></Tile>
      </Flex>
      <Text>Read directly from HubSpot at {data.asOf}.</Text>
      {data.truncated&&<Text>Showing a capped register. Enable API pagination for larger accounts.</Text>}
    </>}
  </>;
}

function Entitlements() {
  const {data,loading,error,refresh}=useRegister();
  const [filter,setFilter]=useState('all');
  const [typeFilter,setTypeFilter]=useState('all');
  const records=(data?.entitlements||[]).filter(e=>(filter==='all'||e.status===filter)&&(typeFilter==='all'||e.type===typeFilter));
  return <>
    <Intro title="Entitlement register"/>
    <Text>Live record visibility. Rights are linked to resources and their commercial context.</Text>
    <Loading loading={loading} error={error} refresh={refresh}/>
    <Select name="status" label="Lifecycle filter" value={filter} onChange={value=>setFilter(value as string)}
      options={[{label:'All',value:'all'},...['draft','pending','active','suspended','expired','revoked','released']
        .map(value=>({label:value[0].toUpperCase()+value.slice(1),value}))]}/>
    <Select name="industry-template" label="Industry template" value={typeFilter} onChange={v=>setTypeFilter(v as string)}
      options={[{label:'All templates',value:'all'}, ...Object.entries(typeName).map(([value,label])=>({value,label}))]}/>
    {records.map(e=><Tile key={e.id}>
      <Heading>{e.reference} · {e.status}</Heading>
      <Text>{typeName[e.type]||e.type} · {e.resourceCode||'No resource reference'} · {e.quantity} unit(s)</Text>
      <Text>{dateUK(e.start)} to {dateUK(e.end)} · Notice {dateUK(e.notice)}</Text>
      <Text>{gbp(e.monthlyFee)}/month · {e.rights||'No rights description'}</Text>
      <Link href={recordUrl('entitlement',e.id)}>Open entitlement in HubSpot</Link>
    </Tile>)}
    {!loading&&!error&&records.length===0&&<Text>No entitlements match this filter.</Text>}
    <Divider/>
    <Text>Grant, revoke and allocation controls require the transactional booking service. Editing records directly in CRM does not automatically validate booking conflicts.</Text>
  </>;
}

function Resources() {
  const {data,loading,error,refresh}=useRegister();
  const current=useMemo(()=>{
    const map:Record<string,number>={};
    const today=todayLondon();
    for(const e of data?.entitlements||[]){
      if(['pending','active','suspended'].includes(e.status)&&e.start<=today&&e.end>=today) {
        map[e.resourceCode]=(map[e.resourceCode]||0)+e.quantity;
      }
    }
    return map;
  },[data]);
  return <>
    <Intro title="Resource register"/>
    <Text>Spaces, furniture, equipment and access capacity are independent CRM records.</Text>
    <Loading loading={loading} error={error} refresh={refresh}/>
    {(data?.resources||[]).map(r=><Tile key={r.id}>
      <Heading>{r.name}</Heading>
      <Text>{r.site} · {r.code} · {r.status}</Text>
      <Text>Current allocated quantity: {current[r.code]||0} / {r.capacity} {r.exclusive?'(exclusive resource)':'(pooled capacity)'}</Text>
      <Text>Indicative current usage only; this is not a transaction-safe booking guarantee.</Text>
      <Link href={recordUrl('resource',r.id)}>Open resource in HubSpot</Link>
    </Tile>)}
  </>;
}


const nextDay = (date: string, count: number) => {
  const d = new Date(date + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() + count);
  return d.toISOString().slice(0,10);
};

function Availability() {
  const {data,loading,error,refresh}=useRegister();
  const [site,setSite]=useState('all');
  const [windowDays,setWindowDays]=useState('30');
  const start=todayLondon();
  const end=nextDay(start, Number(windowDays));
  const filtered=(data?.resources||[]).filter(r=>site==='all'||r.site===site);
  const allocationsFor=(r: Resource) => (data?.entitlements||[]).filter(e =>
    e.resourceCode===r.code && ['active','pending','suspended'].includes(e.status) && e.start<=end && e.end>=start
  );
  return <>
    <Intro title="Resource availability"/>
    <Text>Indicative allocations from live HubSpot records. This view does not reserve capacity or prevent competing requests.</Text>
    <Loading loading={loading} error={error} refresh={refresh}/>
    <Select name="site-filter" label="Location" value={site} onChange={v=>setSite(v as string)}
      options={[{label:'All sites',value:'all'},...Array.from(new Set((data?.resources||[]).map(r=>r.site)))
        .map(value=>({label:value,value}))]}/>
    <Select name="term-filter" label="Proposed period" value={windowDays} onChange={v=>setWindowDays(v as string)}
      options={[{label:'Today through next 30 days',value:'30'},{label:'Next 90 days',value:'90'},{label:'Next 180 days',value:'180'}]}/>
    <Text>Showing commitments overlapping {dateUK(start)} to {dateUK(end)}.</Text>
    {filtered.map(r=>{
      const overlaps=allocationsFor(r);
      const allocated=overlaps.reduce((n,e)=>n+e.quantity,0);
      const possible = r.status==='active' && allocated < r.capacity;
      return <Tile key={r.id}>
        <Heading>{r.name}</Heading>
        <Text>{r.site} · {r.code} · {r.type}</Text>
        <Text>{possible?'No full-capacity conflict identified':'Allocation already committed or resource unavailable'} · {allocated}/{r.capacity} allocated</Text>
        {overlaps.map(e=><Text key={e.id}>{e.reference} · {e.status} · {dateUK(e.start)} to {dateUK(e.end)}</Text>)}
        <Link href={recordUrl('resource',r.id)}>View resource in HubSpot</Link>
      </Tile>;
    })}
    {!loading&&!error&&filtered.length===0&&<Text>No resources match this site.</Text>}
    <Divider/>
    <Text>Shared pool capacity and exclusive suite allocations must be validated using a transaction-safe service before granting a new right.</Text>
  </>;
}

function Renewals(){
  const {data,loading,error,refresh}=useRegister();
  const [horizon,setHorizon]=useState('30');
  const now=todayLondon();
  const filtered=(data?.entitlements||[]).filter(e=>['active','pending'].includes(e.status) && e.notice && e.notice>=now)
    .filter(e=>horizon==='all'||(daysUntil(e.notice)!==null && daysUntil(e.notice)!<=Number(horizon)))
    .sort((a,b)=>a.notice.localeCompare(b.notice));
  return <>
    <Intro title="Notice and renewal"/>
    <Text>Notice deadlines from live CRM entitlements. Review the original agreement before taking action.</Text>
    <Loading loading={loading} error={error} refresh={refresh}/>
    <Select name="notice-horizon" label="Notice window" value={horizon} onChange={v=>setHorizon(v as string)}
      options={[{label:'Next 30 days',value:'30'},{label:'Next 90 days',value:'90'},
       {label:'Next 12 months',value:'365'},{label:'All future notices',value:'all'}]}/>
    <Text>{filtered.length} entitlements in this notice window.</Text>
    {filtered.map(e=><Tile key={e.id}>
      <Heading>{e.reference} · {dateUK(e.notice)}</Heading>
      <Text>{e.resourceCode} · {e.status} · {daysUntil(e.notice)} days remaining</Text>
      <Text>Term ends {dateUK(e.end)} · {gbp(e.monthlyFee)} per month</Text>
      <Link href={recordUrl('entitlement',e.id)}>Review entitlement in HubSpot</Link>
    </Tile>)}
    {!loading&&!error&&filtered.length===0&&<Text>No upcoming notice deadlines in the selected period.</Text>}
    <Divider/>
    <Text>Workflow reminders and a single assigned commercial follow-up require separate implementation and validation.</Text>
  </>;
}

function Settings() {
  return <>
    <Intro title="Configuration and safeguards"/>
    <Text>Templates: Workspace & Property, Furniture & Equipment, Facilities & Access.</Text>
    <Text>CRM system of record: Siloy Entitlements (2-256878303) and Siloy Resources (2-256878310).</Text>
    <Text>Portal: 149783010 · Reporting date zone: Europe/London.</Text>
    <Divider/>
    <Heading>Release boundaries</Heading>
    <Text>Live CRM read-only register. No simulated signatures, no automatic renewals, no grant/revoke buttons, and no claim of race-free double-booking protection until the allocation API is deployed with a shared transactional database.</Text>
    <Text>Commercial agreements remain separate from entitlements; native Contracts integration requires access approval.</Text>
  </>;
}
const Router=createPageRouter(<PageRoutes>
  <PageRoutes.IndexRoute component={Home}/>
  <PageRoutes.Route path="/entitlements" component={Entitlements}/>
  <PageRoutes.Route path="/resources" component={Resources}/>
  <PageRoutes.Route path="/settings" component={Settings}/>
  <PageRoutes.Route path="/availability" component={Availability}/>
  <PageRoutes.Route path="/renewals" component={Renewals}/>
</PageRoutes>);
hubspot.extend<'pages'>(()=><Router/>);
