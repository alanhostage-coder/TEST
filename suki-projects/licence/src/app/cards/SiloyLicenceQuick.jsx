import React from 'react';
import {hubspot,Heading,Text,Link,Button,Tile,Tag,Flex,Image} from '@hubspot/ui-extensions';
import {useAssociations} from '@hubspot/ui-extensions/crm';
import brandBanner from './assets/siloy-licence-header.svg';
import {ENTITLEMENT_TYPE,LICENCE_PROPERTIES,PORTAL_ID,RECORD_BASE,rowsFromAssociations,todayLondon,isCurrent,isDue,daysUntil,uk} from './licence-utils';
// Sits beside the existing Notes and Time quick actions on Company records.
hubspot.extend(({context})=><QuickLicence context={context}/>);
function QuickLicence({context}) {
  const portal=String(context?.portal?.id||'');
  const {results,error,isLoading,refetch}=useAssociations({
    toObjectType:ENTITLEMENT_TYPE,properties:LICENCE_PROPERTIES,pageLength:100
  });
  if(portal&&portal!==PORTAL_ID)return <Text>Available in Siloy UKI Apps only.</Text>;
  const rows=rowsFromAssociations(results);
  const today=todayLondon();
  const active=rows.filter(r=>isCurrent(r,today));
  const due=rows.filter(r=>isDue(r,today)).sort((a,b)=>a.notice.localeCompare(b.notice));
  return <>
    <Image src={brandBanner} alt="Siloy Licence" width={240}/>
    <Heading>Siloy Licence | Quick View</Heading>
    <Text>Entitlements linked to this Company</Text>
    <Flex direction="row" gap="sm">
      <Tile><Heading>{active.length}</Heading><Text>Active</Text></Tile>
      <Tile><Heading>{due.length}</Heading><Text>Due soon</Text></Tile>
    </Flex>
    {isLoading&&<Text>Loading…</Text>}
    {error&&<Text>Could not retrieve Licence associations.</Text>}
    {due[0]&&<Tile>
      <Tag variant="warning">Notice deadline</Tag>
      <Text>{due[0].reference} · {uk(due[0].notice)} · {daysUntil(due[0].notice,today)} days</Text>
      <Link href={`${RECORD_BASE}/${due[0].id}`}>Review entitlement</Link>
    </Tile>}
    {!isLoading&&!error&&rows.length===0&&<Text>No licences linked. Open the Siloy Apps tab to review the licence workspace.</Text>}
    <Button variant="secondary" onClick={()=>refetch?.()}>Refresh</Button>
    <Text>Read-only preview. No grant or revoke action from this card.</Text>
  </>;
}
