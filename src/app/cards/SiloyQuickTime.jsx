import React, { useCallback, useEffect, useRef, useState } from 'react';
import { hubspot, Heading, Text, Input, TextArea, Select, Button, Flex, Tile, Tag, Image, Link, Divider, LoadingSpinner } from '@hubspot/ui-extensions';
import { CORPUS_BRAND } from './brand-config';

const MARK = 'https://raw.githubusercontent.com/alanhostage-coder/TEST/refs/heads/codex/siloy-time-enterprise/src/app/cards/assets/siloy-time-header.svg';
const TYPES = { '0-1': 'contacts', '0-2': 'companies', '0-3': 'deals', '0-5': 'tickets' };
const LABELS = { contacts: 'Contact', companies: 'Company', deals: 'Deal', tickets: 'Ticket' };
const today = () => new Date().toISOString().slice(0, 10);
const now = () => new Date().toTimeString().slice(0, 5);
const monday = d => {
  const date = new Date(d + 'T00:00:00Z');
  date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7);
  return date.toISOString().slice(0, 10);
};
const unwrap = response => response?.body || response || {};
const fmt = value => (Math.round(Number(value || 0) * 100) / 100) + ' h';

hubspot.extend(({ context, actions }) => (
  <SiloyQuickTime context={context} addAlert={actions.addAlert} />
));

function SiloyQuickTime({ context, addAlert }) {
  const recordType = TYPES[String(context?.crm?.objectTypeId || '')] || '';
  const recordId = String(context?.crm?.objectId || '');
  const portalId = String(context?.portal?.id || '149783010');
  const [description, setDescription] = useState('');
  const [hours, setHours] = useState('0.5');
  const [date, setDate] = useState(today);
  const [start, setStart] = useState(now);
  const [projectId, setProjectId] = useState('');
  const [billable, setBillable] = useState('false');
  const [advanced, setAdvanced] = useState(false);
  const [projects, setProjects] = useState([]);
  const [entries, setEntries] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [receipt, setReceipt] = useState(null);
  const lock = useRef(false);
  const reload = useCallback(async () => {
    if (!recordType || !/^\d+$/.test(recordId)) {
      setLoading(false); setError('Open a supported CRM record to log time.'); return;
    }
    setLoading(true);
    try {
      const out = unwrap(await hubspot.serverless('siloy_time_api', {
        parameters: { action: 'load', recordType, recordId, week: monday(today()) }
      }));
      if (!out.success) throw new Error(out.error || 'Could not load time entries.');
      setEntries(out.entries || []);
      setProjects(out.projects || []);
      setError('');
    } catch (err) { setError(String(err.message || err)); }
    finally { setLoading(false); }
  }, [recordType, recordId]);
  useEffect(() => { reload(); }, [reload]);

  const save = async () => {
    if (lock.current) return;
    if (!recordType || !/^\d+$/.test(recordId)) {
      setError('Open a supported CRM record first.'); return;
    }
    const quantity = Number(hours);
    if (!description.trim()) { setError('Describe the work before saving.'); return; }
    if (!Number.isFinite(quantity) || quantity < 0.25 || quantity > 16 ||
        Math.abs(quantity * 4 - Math.round(quantity * 4)) > 0.0001) {
      setError('Use 0.25 to 16 hours in 15-minute increments.'); return;
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        !/^([01]\d|2[0-3]):[0-5]\d$/.test(start)) {
      setError('Check the date and start time.'); return;
    }
    lock.current = true; setSaving(true); setError(''); setReceipt(null);
    try {
      const out = unwrap(await hubspot.serverless('siloy_time_api', {
        parameters: { action: 'quickCreate', recordType, recordId,
          entry: { date, start, hours, description: description.trim(), projectId,
            billable: billable === 'true' } }
      }));
      if ((!out.success && !out.partial) || !out.entryId)
        throw new Error(out.error || 'Save not confirmed.');
      setReceipt({ id: out.entryId, partial: Boolean(out.partial) });
      if (out.success) { setDescription(''); setHours('0.5'); }
      addAlert(out.partial
        ? {type: 'warning', title: 'Time entry created', message: 'Check its CRM associations before retrying.'}
        : {type: 'success', title: 'Time recorded', message: 'Saved to Siloy Time and linked to this ' + LABELS[recordType] + '.'});
      if (out.success) void reload();
    } catch (err) {
      const message = String(err.message || err);
      setError(message);
      addAlert({type:'danger',title:'Time not saved',message});
    } finally { lock.current = false; setSaving(false); }
  };

  const total = entries.reduce((sum,e) => sum + Number(e.hours || 0), 0);
  return (
    <>
      <Flex direction="row" align="center" gap="small" wrap="wrap">
        <Image src={MARK} width={300} alt="Siloy Time"/>
        <Flex direction="column" gap="small">

          <Text variant="microcopy">Quick time log</Text>
        </Flex>
      </Flex>
      <Text variant="microcopy">Add time against this {LABELS[recordType] || 'record'}. Appears in the same Siloy Time history as the weekly timesheet.</Text>
      {loading ? <LoadingSpinner label="Loading time log"/> : <Tag variant="info">{fmt(total)} logged this week</Tag>}
      {error ? <Text>{error}</Text> : null}
      {receipt ? (
        <Flex direction="column" gap="small">
          <Tag variant={receipt.partial ? 'warning' : 'success'}>{receipt.partial ? 'Created; review links' : 'Time saved'}</Tag>
          <Link href={'https://app-eu1.hubspot.com/contacts/' + portalId + '/record/2-143515197/' + receipt.id}>Open time entry</Link>
        </Flex>
      ) : null}
      <Tile>
        <TextArea label="Work carried out" name="quickTimeDescription" rows={2} value={description}
          onChange={setDescription} disabled={saving} placeholder="What did you work on?"/>
        <Input label="Hours" name="quickTimeHours" value={hours} onChange={setHours}
          disabled={saving} placeholder="0.5"/>
        <Button variant="secondary" disabled={saving} onClick={() => setAdvanced(x => !x)}>
          {advanced ? 'Hide details' : 'More details (optional)'}
        </Button>
        {advanced ? (
          <>
            <Input label="Date (YYYY-MM-DD)" name="quickTimeDate" value={date} onChange={setDate} disabled={saving}/>
            <Input label="Start (HH:MM)" name="quickTimeStart" value={start} onChange={setStart} disabled={saving}/>
            <Select label="Project (optional)" name="quickTimeProject"
              value={projectId} onChange={setProjectId} disabled={saving}
              options={[{label:'No Project',value:''}, ...projects.map(p => ({label:p.name,value:p.id}))]}/>
            <Select label="Billing" name="quickTimeBillable" value={billable}
              onChange={setBillable} disabled={saving}
              options={[{label:'Non-billable',value:'false'},{label:'Billable',value:'true'}]}/>
          </>
        ) : null}
        <Button variant="primary" disabled={saving || loading || !description.trim()} onClick={save}>
          {saving ? 'Saving…' : 'Save time'}
        </Button>
      </Tile>
      <Divider/>
      <Flex direction="row" justify="between" align="center" gap="small">
        <Text variant="microcopy">Recent entries · this week</Text>
        <Button variant="secondary" disabled={loading || saving} onClick={reload}>Refresh</Button>
      </Flex>
      {entries.slice(-3).reverse().map(e => (
        <Flex key={e.id} direction="row" gap="small" justify="between" align="center">
          <Text>{(e.description || 'Time entry').slice(0,65)}</Text>
          <Tag variant="default">{fmt(e.hours)}</Tag>
        </Flex>
      ))}
      {!entries.length && !loading ? <Text variant="microcopy">No entries for this record yet.</Text> : null}
      <Text variant="microcopy">App-level access permissions apply. Restrict this pilot to authorised users.</Text>
    </>
  );
}
