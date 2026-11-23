import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  hubspot, Heading, Text, Flex, Tile, Button, Tag,
  LoadingSpinner, Divider, Table, TableHead, TableRow,
  TableHeader, TableBody, TableCell
} from '@hubspot/ui-extensions';
import { createPageRouter, PageRoutes, PageTitle, PageBreadcrumbs } from '@hubspot/ui-extensions/pages';

const fmt = n => (Number(n) || 0).toLocaleString('en-GB', { maximumFractionDigits: 1 });
const pct = row => row.limit > 0 ? Math.round(100 * row.credits / row.limit) : null;
const unwrap = r => r && (r.body || r) || {};
const typeName = s => s === 'actual' ? 'Source-labelled actual' :
  s === 'reconciled_estimate' ? 'Reconciled estimate' :
  s === 'reported_child' ? 'Reported child usage' : 'Not specified';

function AppHomePage() {
  const [snapshot, setSnapshot] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(true);
  const [view, setView] = useState('hot');
  const load = useCallback(async () => {
    setBusy(true); setError('');
    try {
      const r = unwrap(await hubspot.serverless('siloy_credit_usage_api', { parameters: { action: 'snapshot' } }));
      if (!r.success) throw new Error(r.error || 'Snapshot is unavailable.');
      setSnapshot(r);
    } catch (e) { setError(String(e.message || e)); }
    finally { setBusy(false); }
  }, []);
  useEffect(() => { load(); }, [load]);
  const shown = useMemo(() => {
    if (!snapshot) return [];
    if (view === 'all') return snapshot.items.slice().sort((a, b) => b.credits - a.credits).slice(0, 35);
    if (view === 'method') return snapshot.items.filter(x => x.method !== 'actual').slice(0, 35);
    return snapshot.hotspots;
  }, [snapshot, view]);
  return (
    <Flex direction="column" gap="medium">
      <PageBreadcrumbs><PageBreadcrumbs.Current>Credit Heatmap</PageBreadcrumbs.Current></PageBreadcrumbs>
      <PageTitle>Siloy Credit Heatmap</PageTitle>
      <Text>Revenue operations / usage intelligence</Text>
      <Flex direction="row" gap="small" align="center" wrap="wrap">
        <Tag variant="warning">Snapshot data, not verified billing</Tag>
        <Tag variant="default">SILOY UKI · 149783010</Tag>
        <Button variant="secondary" onClick={load} disabled={busy}>Refresh CRM snapshot</Button>
      </Flex>
      <Divider />
      {busy ? <LoadingSpinner label="Reading Siloy Credit Usage records" showLabel={true} size="md" /> : null}
      {error ? <Tile><Heading>Error loading data</Heading><Text>{error}</Text><Button onClick={load}>Try again</Button></Tile> : null}
      {snapshot ? <>
        {snapshot.illustrativeCount > 0 ? <Text>Illustrative usage model; figures are not actual billing.</Text> : null}
        <Flex direction="row" wrap="wrap" gap="medium">
          <Tile><Text>Credit usage records</Text><Heading>{fmt(snapshot.records)}</Heading><Text>Fetched from custom object</Text></Tile>
          <Tile><Text>Source-labelled actual</Text><Heading>{fmt(snapshot.methods.actual || 0)}</Heading><Text>Not billing-verified</Text></Tile>
          <Tile><Text>Workflow estimates</Text><Heading>{fmt(snapshot.methods.reconciled_estimate || 0)}</Heading><Text>Reconciled estimates</Text></Tile>
          <Tile><Text>Period identification</Text><Heading>{snapshot.periodised ? 'Present' : 'Missing'}</Heading><Text>{fmt(snapshot.unperiodised)} records need period keys</Text></Tile>
        </Flex>
        <Tile>
          <Heading>Credit consumption confidence</Heading>
          <Text>{snapshot.sourceNote}</Text>
          <Text>Billing total intentionally hidden: currently overlapping feature, agent and workflow nodes cannot be summed safely.</Text>
          <Text>Compare like-for-like time periods only after the source ledger and period dimensions have been reconciled.</Text>
        </Tile>
        <Heading>Heat watch</Heading>
        <Flex direction="row" wrap="wrap" gap="small">
          <Button variant={view === 'hot' ? 'primary' : 'secondary'} onClick={() => setView('hot')}>Hot + critical</Button>
          <Button variant={view === 'all' ? 'primary' : 'secondary'} onClick={() => setView('all')}>Top records</Button>
          <Button variant={view === 'method' ? 'primary' : 'secondary'} onClick={() => setView('method')}>Estimated sources</Button>
        </Flex>
        <Table bordered={true}>
          <TableHead><TableRow>
            <TableHeader>Driver</TableHeader><TableHeader>Credits</TableHeader>
            <TableHeader>Reference limit</TableHeader><TableHeader>Utilisation</TableHeader><TableHeader>Evidence</TableHeader>
          </TableRow></TableHead>
          <TableBody>
            {shown.length ? shown.map(x => (
              <TableRow key={x.id}>
                <TableCell>{x.name || x.id}</TableCell>
                <TableCell>{fmt(x.credits)}</TableCell>
                <TableCell>{x.limit ? fmt(x.limit) : 'None'}</TableCell>
                <TableCell>{pct(x) === null ? 'N/A' : pct(x) + '%'}</TableCell>
                <TableCell>{x.illustrative ? 'Illustrative model' : typeName(x.method)}</TableCell>
              </TableRow>
            )) : <TableRow><TableCell colSpan={5}>No matching records.</TableCell></TableRow>}
          </TableBody>
        </Table>
        <Tile>
          <Heading>3D network</Heading>
          <Text>Your original 3D network has been preserved in the source package. The HubSpot sandbox requires supported React components, so this native page currently provides the live CRM-backed heat watch and data-quality controls, not the original 3D canvas.</Text>
          <Text>To publish the original interactive 3D view, first make an approved, authenticated internal hosting endpoint and feed it properly periodised data. Do not publish internal usage data on a public CMS page.</Text>
        </Tile>
      </> : null}
    </Flex>
  );
}
const PageRouter = createPageRouter(
  <PageRoutes><PageRoutes.IndexRoute component={AppHomePage} /></PageRoutes>
);
hubspot.extend(() => <PageRouter />);
