import React,{useEffect,useState} from 'react';
import {Button,Divider,Flex,Heading,Text,Tile,hubspot} from '@hubspot/ui-extensions';
import {PageTitle} from '@hubspot/ui-extensions/pages';
type Deal={id:string;dealname?:string;dealstage?:string;sri_risk_priority?:string;sri_risk_level?:string;sri_assessment_status?:string};
type Response={deals:Deal[];total:number;nextCursor?:string|null};
export const OverviewPage=()=>{
  const [deals,setDeals]=useState<Deal[]>([]);
  const [total,setTotal]=useState(0),[cursor,setCursor]=useState<string|null>(null);
  const [busy,setBusy]=useState(false),[error,setError]=useState('');
  async function load(next:string|null=null){
    setBusy(true);setError('');
    try{
      const data=await hubspot.serverless('sri_list_deals',{parameters:{after:next,limit:20}}) as Response;
      setDeals(data.deals||[]);setTotal(data.total||0);setCursor(data.nextCursor||null);
    }catch(e){setError(String(e));}finally{setBusy(false);}
  }
  useEffect(()=>{void load();},[]);
  return <Flex direction="column" gap="md">
    <PageTitle>Siloy Revenue Intelligence</PageTitle>
    <Text>Find · Insight · Action. Action is available; Find and Insight are roadmap modules.</Text>
    <Divider/><Heading>Action · Deal attention queue</Heading>
    <Text>{'Deals: '+total+'. Scores are written only after a user saves an assessment on a Deal.'}</Text>
    {busy&&<Text>Loading…</Text>}
    {error&&<Text>{'Unable to load: '+error}</Text>}
    {!busy&&!error&&!deals.length&&<Tile><Text>No deals in this portal yet. Approved UAT data is needed for end-to-end validation.</Text></Tile>}
    {deals.map(d=><Tile key={d.id}><Flex direction="column" gap="xs">
      <Heading>{d.dealname||'Deal '+d.id}</Heading>
      <Text>{'Priority: '+(d.sri_risk_priority??'Not assessed')+' | Level: '+(d.sri_risk_level||'Not assessed')+' | Review: '+(d.sri_assessment_status||'Not assessed')}</Text>
      <Text>{'Stage: '+(d.dealstage||'Unknown')+' | Deal ID: '+d.id}</Text>
    </Flex></Tile>)}
    <Flex direction="row" gap="sm">
      <Button variant="secondary" onClick={()=>void load()} disabled={busy}>Refresh</Button>
      {cursor&&<Button variant="primary" onClick={()=>void load(cursor)} disabled={busy}>Next page</Button>}
    </Flex>
    <Divider/><Heading>Find</Heading><Text>Roadmap: target-account coverage and prospect signals, using existing HubSpot entitlements.</Text>
    <Heading>Insight</Heading><Text>Roadmap: pipeline leakage, conversion and marketing contribution reporting.</Text>
  </Flex>;
};
