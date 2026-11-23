import React, { useEffect, useState } from 'react';
import { hubspot, Heading, Text, Flex, Tile, Tag, Button, LoadingSpinner } from '@hubspot/ui-extensions';

const unwrap = r => r && (r.body || r) || {};
hubspot.extend(() => <CreditPulseCard />);

function CreditPulseCard() {
  const [snapshot, setSnapshot] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  async function load() {
    setLoading(true); setError('');
    try {
      const r = unwrap(await hubspot.serverless('siloy_credit_usage_api', {parameters:{ action:'snapshot' }}));
      if (!r.success) throw new Error(r.error || 'Credit Usage source unavailable');
      setSnapshot(r);
    } catch (e) { setError(String(e.message || e)); }
    finally { setLoading(false); }
  }
  useEffect(() => { load(); }, []);
  return (
    <Flex direction="column" gap="small">
      <Heading>Siloy Credit Heatmap</Heading>
      <Tag variant="warning">Account-wide • unverified billing</Tag>
      <Text>Record-side account intelligence. Not usage attributed to this particular company or deal.</Text>
      {loading ? <LoadingSpinner label="Reading account snapshots" showLabel={true} size="sm" /> : null}
      {error ? <Text>{error}</Text> : null}
      {snapshot ? <>
        <Tile>
          <Text>{snapshot.records} Credit Usage entries</Text>
          <Text>{snapshot.unperiodised} missing period identifiers</Text>
          <Text>{snapshot.hotspots.length} hot or critical entries</Text>
        </Tile>
        {snapshot.hotspots.slice(0, 4).map(x => <Flex key={x.id} direction="row" gap="small" align="center" wrap="wrap">
          <Text>{x.name}:</Text>
          <Text>{x.limit ? Math.round(100 * x.credits / x.limit) + '% of reference' : 'no reference limit'}</Text>
        </Flex>)}
        <Text>Open Siloy Credit Heatmap from the HubSpot Marketplace app menu for the full heat watch.</Text>
      </> : null}
      <Button variant="secondary" disabled={loading} onClick={load}>Refresh</Button>
    </Flex>
  );
}
