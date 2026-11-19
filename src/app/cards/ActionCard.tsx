import React, { useEffect, useState } from 'react';
import { hubspot, Button, Divider, Flex, Heading, Text, Tile } from '@hubspot/ui-extensions';
type Factor={id:string;points:number;detail:string;recommendation:string};
type Assessment={dealId:string;dealName:string;score:number;level:string;flags:Factor[];recommendation:string;dataQuality:string[];status:string};
hubspot.extend<'crm.record.sidebar'>(({context})=><ActionCard dealId={String(context.crm.objectId||'')}/>);
function ActionCard({dealId}:{dealId:string}){
  const [assessment,setAssessment]=useState<Assessment|null>(null);
  const [loading,setLoading]=useState(false),[saving,setSaving]=useState(false);
  const [message,setMessage]=useState(''),[error,setError]=useState('');
  async function refresh(){
    if(!dealId)return;setLoading(true);setError('');setMessage('');
    try{setAssessment(await hubspot.serverless('sri_score_deal',{parameters:{dealId}}) as Assessment);}
    catch(e){setError('Could not assess deal: '+String(e));}
    finally{setLoading(false);}
  }
  useEffect(()=>{void refresh();},[dealId]);
  async function save(){
    setSaving(true);setError('');setMessage('');
    try {
      const res=await hubspot.serverless('sri_save_assessment',{parameters:{dealId}}) as Assessment&{saved:boolean;reviewStatus:string;reason?:string};
      if(res.saved){setAssessment(res);setMessage('Saved to six SRI Deal properties. Review: '+res.reviewStatus);}
      else setMessage(res.reason||'No changes saved.');
    } catch(e){setError('Save failed: '+String(e));} finally{setSaving(false);}
  }
  return <Flex direction="column" gap="sm">
    <Heading>Siloy Action</Heading>
    <Text>Explainable deal attention. This is not a close probability.</Text>
    {loading&&<Text>Assessing deal…</Text>}
    {error&&<Text>{error}</Text>}
    {assessment&&!loading&&<>
      <Tile><Heading>{assessment.status==='excluded'?'Closed deal':assessment.score+'/100 · '+assessment.level.toUpperCase()+' attention'}</Heading><Text>{assessment.dealName}</Text></Tile>
      {assessment.flags.slice(0,5).map(f=><Text key={f.id}>{f.points+' pts · '+f.detail}</Text>)}
      <Divider/>
      <Heading>Recommended next action</Heading>
      <Text>{assessment.recommendation}</Text>
      {!!assessment.dataQuality.length&&<Text>{'Data caveats: '+assessment.dataQuality.join(' ')}</Text>}
      <Text>Saving only updates Siloy assessment properties. It does not create tasks or send emails.</Text>
      <Button variant="primary" disabled={saving||assessment.status==='excluded'} onClick={()=>void save()}>{saving?'Saving…':'Save assessment to deal'}</Button>
    </>}
    {message&&<Text>{message}</Text>}
    <Button variant="secondary" disabled={loading||saving} onClick={()=>void refresh()}>Refresh assessment</Button>
  </Flex>;
}
