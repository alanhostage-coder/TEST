import React, { useCallback, useEffect, useState } from 'react';
import {
  hubspot, Heading, Text, Input, TextArea, Select, Button, Link,
  Divider, LoadingSpinner, Flex, Tile, Tag, Image
} from '@hubspot/ui-extensions';
import brandBanner from './assets/brand-banner.svg';
import { CORPUS_BRAND } from './brand-config';

const OPTIONS = [
  { label: 'Meeting', value: 'meeting' },
  { label: 'Call', value: 'call' },
  { label: 'Discovery', value: 'discovery' },
  { label: 'Handover', value: 'handover' },
  { label: 'Internal update', value: 'internal_update' }
];
function today() { return new Date().toISOString().slice(0, 10); }
function empty() {
  return {
    note_title: '', note_type: 'meeting', note_date: today(),
    internal_notes: '', meeting_activity_id: '', decisions: '',
    risks: '', next_steps: '', followup_date: ''
  };
}
function ukToISO(input) {
  const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(String(input || '').trim());
  if (!match) return null;
  const iso = match[3] + '-' + match[2] + '-' + match[1];
  const d = new Date(iso + 'T00:00:00Z');
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === iso
    ? iso : null;
}
function isoToUK(value) {
  if (!value) return '';
  const date = /^\d+$/.test(String(value))
    ? new Date(Number(value)) : new Date(value);
  return Number.isNaN(date.getTime())
    ? '' : date.toLocaleDateString('en-GB', { timeZone: 'UTC' });
}
function unwrap(response) { return response && (response.body || response) || {}; }

hubspot.extend(({ context, actions }) => (
  <CorpusNoteCard context={context} addAlert={actions.addAlert} />
));
function CorpusNoteCard({ context, addAlert }) {
  const companyId = String(context?.crm?.objectId || '');
  const portalId = String(context?.portal?.id || '145209388');
  const [notes, setNotes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [truncated, setTruncated] = useState(false);
  const [form, setForm] = useState(empty);
  const [ukDate, setUkDate] = useState(isoToUK(today()));
  const [ukFollowup, setUkFollowup] = useState('');
  const set = (key, value) => setForm(old => ({ ...old, [key]: value }));

  const reload = useCallback(async () => {
    if (!/^\d+$/.test(companyId)) {
      setLoading(false);
      setError('Open a Company record to use Corpus Note.');
      return;
    }
    setLoading(true);
    try {
      const result = unwrap(await hubspot.serverless('corpus_notes_api', {
        parameters: { action: 'list', companyId }
      }));
      if (!result.success) throw new Error(result.error || 'Could not load notes.');
      setNotes(result.notes || []);
      setTruncated(Boolean(result.truncated));
      setError('');
    } catch (err) {
      setError(String(err.message || err));
    } finally {
      setLoading(false);
    }
  }, [companyId]);

  useEffect(() => { reload(); }, [reload]);

  const save = async () => {
    const noteDate = ukToISO(ukDate);
    const followDate = ukFollowup ? ukToISO(ukFollowup) : '';
    if (!form.note_title.trim() || !form.internal_notes.trim() ||
        !noteDate || (ukFollowup && !followDate)) {
      addAlert({
        type: 'danger', title: 'Check required fields',
        message: 'A title, internal note and valid UK dates (dd/mm/yyyy) are required.'
      });
      return;
    }
    setSaving(true);
    try {
      const result = unwrap(await hubspot.serverless('corpus_notes_api', {
        parameters: {
          action: 'create', companyId,
          note: { ...form, note_date: noteDate, followup_date: followDate }
        }
      }));
      if (!result.success)
        throw new Error(result.error || 'Could not save this internal note.');
      addAlert({
        type: 'success', title: 'Corpus Note saved',
        message: 'Note ' + result.noteId + ' linked to this company.'
      });
      setForm(empty());
      setUkDate(isoToUK(today()));
      setUkFollowup('');
      await reload();
    } catch (err) {
      addAlert({
        type: 'danger', title: 'Save not completed',
        message: String(err.message || err)
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <Image src={brandBanner} alt={CORPUS_BRAND.name + ' Corpus Note, internal workflow'} width={900} />
      <Flex direction="row" wrap="wrap" gap="small">
        <Tag variant="warning">Internal only</Tag>
        <Tag variant="info">No invitation updates</Tag>
        <Tag variant="default">{CORPUS_BRAND.name}</Tag>
      </Flex>
      <Text variant="microcopy">Internal capture workflow. Notes are not inserted into meeting descriptions or attendee invitations. Record visibility still depends on HubSpot permissions.</Text>
      <Divider />
      <Tile>
      <Heading>Create an internal note</Heading>
      <Text variant="microcopy">Private working notes for this Company. Keep meeting attendee information in the normal calendar flow.</Text>
      <Input name="noteTitle" label="Title" required value={form.note_title}
        onChange={v => set('note_title', v)} placeholder="Portfolio review" />
      <Select name="noteType" label="Type" options={OPTIONS}
        value={form.note_type} onChange={v => set('note_type', v)} />
      <Input name="noteDate" label="Date (dd/mm/yyyy)" value={ukDate}
        onChange={setUkDate} placeholder="13/11/2026" />
      <TextArea name="noteBody" label="Internal notes" required rows={5}
        value={form.internal_notes} onChange={v => set('internal_notes', v)}
        placeholder="Confidential meeting summary..." />
      <Input name="meetingActivityId" label="Meeting activity ID (optional reference)"
        value={form.meeting_activity_id}
        onChange={v => set('meeting_activity_id', v)}
        placeholder="Digits only; reference, not association" />
      <TextArea name="decisions" label="Decisions" rows={2}
        value={form.decisions} onChange={v => set('decisions', v)} />
      <TextArea name="risks" label="Risks" rows={2}
        value={form.risks} onChange={v => set('risks', v)} />
      <TextArea name="nextSteps" label="Next steps" rows={2}
        value={form.next_steps} onChange={v => set('next_steps', v)} />
      <Input name="followupDate" label="Follow-up date (dd/mm/yyyy, optional)"
        value={ukFollowup} onChange={setUkFollowup} />
      <Button onClick={save} disabled={saving || !/^\d+$/.test(companyId)}>
        {saving ? 'Saving...' : 'Save confidential note'}
      </Button>
      </Tile>
      <Divider />
      <Tile>
      <Heading>Company note history</Heading>
      <Button variant="secondary" onClick={reload} disabled={loading}>Refresh notes</Button>
      {loading ? <LoadingSpinner label="Loading notes" /> : null}
      {error ? <Text>{error}</Text> : null}
      {!loading && !error && notes.length === 0
        ? <Text>No Corpus Notes are linked to this company yet.</Text> : null}
      {notes.map(note => (
        <React.Fragment key={note.id}>
          <Heading>{note.note_title || 'Untitled internal note'}</Heading>
          <Text>{isoToUK(note.note_date || note.hs_createdate)} | {note.note_type || 'Internal note'}</Text>
          <Text>{note.internal_notes || ''}</Text>
          {note.decisions ? <Text>Decision: {note.decisions}</Text> : null}
          {note.risks ? <Text>Risk: {note.risks}</Text> : null}
          {note.next_steps ? <Text>Next: {note.next_steps}</Text> : null}
          {note.meeting_activity_id
            ? <Text>Meeting reference: {note.meeting_activity_id}</Text> : null}
          <Link href={'https://app-eu1.hubspot.com/contacts/' + portalId +
            '/record/2-256491528/' + note.id}>Open Corpus Note</Link>
          <Divider />
        </React.Fragment>
      ))}
      {truncated ? <Text>Showing up to 100 linked notes. Open Corpus Notes for older history.</Text> : null}
      </Tile>
      <Text variant="microcopy">Attachments are managed on the Corpus Note record. Brand identity: {CORPUS_BRAND.name} ({CORPUS_BRAND.websiteUrl}).</Text>
    </>
  );
}
