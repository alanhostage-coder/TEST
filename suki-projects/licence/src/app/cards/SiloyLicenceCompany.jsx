import React, {useMemo,useState} from 'react';
import {hubspot,Heading,Text,Button,Link,Divider,Flex,Tile,Tag,Image,Input} from '@hubspot/ui-extensions';
import {useAssociations} from '@hubspot/ui-extensions/crm';
import brandBanner from './assets/siloy-licence-header.svg';
import {ENTITLEMENT_TYPE,LICENCE_PROPERTIES,PORTAL_ID,RECORD_BASE,rowsFromAssociations,todayLondon,daysUntil,gbp,uk,isCurrent,isDue} from './licence-utils';
// A third middle-column card within the existing Company > Siloy Apps tab.
// This is a read-only entitlement view, deliberately not a second agreement system.
const templateLabel={workspace_property:'Workspace & Property',furniture_equipment:'Furniture & Equipment',facilities_access:'Facilities & Access'};
hubspot.extend(({context})=><CompanyLicence context={context}/>);
function CompanyLicence({context}) {
  const companyId=String(context?.crm?.objectId||'');
  const portal=String(context?.portal?.id||'');
  const {results,error,isLoading,refetch,pagination}=useAssociations({
    toObjectType:ENTITLEMENT_TYPE,properties:LICENCE_PROPERTIES,pageLength:100
  });
  const [filter,setFilter]=useState('all');
  const [search,setSearch]=useState('');
  const rows=useMemo(()=>rowsFromAssociations(results),[results]);
  const today=todayLondon();
  const current=rows.filter(r=>isCurrent(r,today));
  const due=rows.filter(r=>isDue(r,today));
  const selected=rows.filter(r=>
    (filter==='all'||(filter==='due'?isDue(r,today):r.status===filter))&&
    (!search||`${r.reference} ${r.resource} ${r.rights}`.toLowerCase().includes(search.toLowerCase()))
  );
  if(portal&&portal!==PORTAL_ID) return <Text>Siloy Licence is restricted to the Siloy UKI Apps test portal.</Text>;
  if(!companyId) return <Text>Open a Company record to view its licences.</Text>;
  return <>
    <Tile>
      <Image src={brandBanner} alt="Siloy Licence" width={480}/>
      <Flex direction="row" align="center" justify="between" gap="sm">
        <Heading>Siloy Licence</Heading><Tag variant="default">Customer entitlements</Tag>
      </Flex>
      <Text>Know who has the right to use what, where, and until when.</Text>
      <Text>Rights attached to this Company. Legal agreements remain separate.</Text>
    </Tile>
    <Flex direction="row" gap="sm">
      <Tile><Heading>{current.length}</Heading><Text>Active</Text></Tile>
      <Tile><Heading>{due.length}</Heading><Text>Notice due (30 days)</Text></Tile>
      <Tile><Heading>{rows.length}</Heading><Text>Total linked</Text></Tile>
    </Flex>
    <Flex direction="row" gap="sm">
      <Button variant="secondary" onClick={()=>refetch?.()}>Refresh</Button>
      <Button variant="secondary" onClick={()=>setFilter('due')}>Notices due ({due.length})</Button>
      <Button variant="secondary" onClick={()=>{setFilter('all');setSearch('');}}>All entitlements</Button>
    </Flex>
    <Divider />
    <Heading>Customer licence register</Heading>
    <Input label="Find licence" name="licence_search" value={search} onChange={setSearch} placeholder="Reference, resource or right"/>
    {isLoading&&<Text>Loading associated HubSpot entitlements…</Text>}
    {error&&<Text>Could not load associated entitlements: {String(error)}</Text>}
    {!isLoading&&!error&&selected.length===0&&<Tile>
      <Text>{rows.length===0?'No entitlements are associated with this Company yet.':'No licences match these filters.'}</Text>
      <Text>Use the Licence object association to link an approved entitlement. A company with no rights must not inherit unrelated demo licences.</Text>
    </Tile>}
    {selected.map(row=><Tile key={row.id}>
      <Flex direction="row" justify="between" align="center">
        <Heading>{row.reference}</Heading><Tag variant={row.status==='active'?'success':row.status==='pending'?'warning':'default'}>{row.status}</Tag>
      </Flex>
      <Text>{templateLabel[row.type]||row.type} · {row.resource} · {row.quantity} unit(s)</Text>
      <Text>{uk(row.start)} to {uk(row.end)} · Notice {uk(row.notice)}</Text>
      <Text>{gbp(row.fee)}/month</Text>
      {isDue(row,today)&&<Text>Notice review due in {daysUntil(row.notice,today)} days</Text>}
      <Link href={`${RECORD_BASE}/${row.id}`}>Open entitlement record</Link>
    </Tile>)}
    {pagination?.nextCursor&&<Text>More associated licences may exist. Review the native association list before making decisions.</Text>}
    <Divider />
    <Text>Only Company-associated entitlements appear here. Licence grant, revoke, booking and signature actions remain disabled until transactional controls and UAT are complete.</Text>
  </>;
}
