import React, {useState} from 'react';
import {hubspot, Heading, Text, Flex, Button, Divider, Tag} from '@hubspot/ui-extensions';

const guides = {
  Notes: {
    purpose: 'Keep internal context, decisions, risks and follow-ups with the CRM record.',
    steps: ['Choose New note or New internal note.', 'Add a title and your notes, decisions or next steps. Set a follow-up date when needed.', 'Save, then use the history and follow-up filters to find it again.'],
    tip: 'Internal-only labels do not replace HubSpot permissions. Check access before adding sensitive information.'
  },
  Time: {
    purpose: 'Record work against a company and review time in the weekly timesheet.',
    steps: ['In Quick Log, describe the work and choose the duration.', 'Open More details for additional options, then save the entry.', 'Use Weekly timesheet to review days and totals or add time.'],
    tip: 'Check the selected record, date and billable details before saving.'
  },
  Licence: {
    purpose: 'See the entitlements and rights associated with a company.',
    steps: ['Find Licence in the Siloy Apps tab or Quick View in the sidebar.', 'Review linked rights, dates and notice deadlines; search by reference or resource.', 'Open an entitlement record for full details.'],
    tip: 'The current cards are read-only. Check the source agreement and authorised process before changing rights.'
  },
  Credit: {
    purpose: 'Explore account-wide credit usage snapshots and potential hotspots.',
    steps: ['Open Account Pulse in the right sidebar.', 'Review hotspots and the reporting period, then open the Credit Heatmap app for the wider view.', 'Refresh to retrieve the latest available CRM snapshot.'],
    tip: 'Figures are account-wide, not attributed to the company on screen. The current model is illustrative and is not verified billing.'
  },
  'More apps': {
    purpose: 'Other Siloy tools support commercial prioritisation and work management.',
    steps: ['Open Revenue Intelligence where available to review and prioritise deal signals.', 'Use Quest Missions on the record to view associated missions and their context.', 'Access depends on the installed app, record layout and your HubSpot permissions.'],
    tip: 'Available actions and data vary by app and record.'
  }
};
hubspot.extend(() => <Guide />);
function Guide() {
  const [active, setActive] = useState('Notes');
  const guide = guides[active];
  return <Flex direction="column" gap="small">
    <Flex direction="row" align="center" gap="small"><Heading>Siloy Apps | Quick guide</Heading><Tag variant="default">Start here</Tag></Flex>
    <Text>Choose an app for a short guide. Your company record keeps the relevant information together.</Text>
    <Flex direction="row" wrap="wrap" gap="small">
      {Object.keys(guides).map(name => <Button key={name} variant={active===name?'primary':'secondary'} onClick={()=>setActive(name)}>{name}</Button>)}
    </Flex>
    <Divider/>
    <Heading>{active}</Heading>
    <Text>{guide.purpose}</Text>
    {guide.steps.map((step,i)=><Text key={step}>{i+1}. {step}</Text>)}
    <Text>{guide.tip}</Text>
  </Flex>;
}
