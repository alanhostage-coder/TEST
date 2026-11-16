import React, { useCallback, useEffect, useState } from 'react';
import {
  hubspot, Heading, Text, Tag, Divider, Button, Input,
  TextArea, Flex, Link, LoadingSpinner, Tag, Tooltip, Icon, Image
} from '@hubspot/ui-extensions';
import { CORPUS_BRAND } from './brand-config';

const isSiloyBrand = /^https:\/\/(?:www\.)?siloy\.com(?:\/|$)/i.test(CORPUS_BRAND.websiteUrl || '');
const SILOY_HEADER_URL = 'https://raw.githubusercontent.com/alanhostage-coder/TEST/refs/heads/codex/corpus-note-hubspot-card/src/app/cards/assets/siloy-notes-header.svg';
const displayedBrandMark = isSiloyBrand ? SILOY_HEADER_URL : CORPUS_BRAND.logoUrl;
const RECORDS = {'0-2':'companies','0-1':'contacts','0-3':'deals','0-5':'tickets'};
const LABELS = {companies:'Company',contacts:'Contact',deals:'Deal',tickets:'Ticket'};

function day(value) {
  if (!value) return null;
  const raw = String(value);
  const time = /^\d+$/.test(raw) ? Number(raw) : Date.parse(raw);
  if (!Number.isFinite(time)) return null;
  const d = new Date(time);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}
function isDue(note) {
  const n = day(note.followup_date);
  return n !== null && n <= day(new Date().toISOString());
}
function clean(value) {
  return String(value || '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}
function unwrap(response) { return response && (response.body || response) || {}; }
function todayISO() { return new Date().toISOString().slice(0, 10); }

hubspot.extend(({ context, actions }) => (
  <CorpusQuickRail context={context} addAlert={actions.addAlert}
    copyTextToClipboard={actions.copyTextToClipboard} />
));

function CorpusQuickRail({ context, addAlert, copyTextToClipboard }) {
  const companyId = String(context?.crm?.objectId || '');
  const recordType = RECORDS[String(context?.crm?.objectTypeId || '0-2')] || '';
  const recordLabel = LABELS[recordType] || 'CRM record';
  const portalId = String(context?.portal?.id || '145209388');
  const [notes, setNotes] = useState([]);
  const [filter, setFilter] = useState('all');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [composer, setComposer] = useState(false);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [savedId, setSavedId] = useState('');
  const [associationNeeded, setAssociationNeeded] = useState(false);
  const [saveIssue, setSaveIssue] = useState('');
  const saveInFlight = React.useRef(false);
  const reload = useCallback(async () => {
    if (!recordType || !/^\d+$/.test(companyId)) { setLoading(false); setError('Open a supported CRM record.'); return; }
    setLoading(true);
    try {
      const result = unwrap(await hubspot.serverless('corpus_notes_api', {
        parameters: { action: 'list', recordType, recordId: companyId }
      }));
      if (!result.success) throw new Error(result.error || 'Unable to read linked notes.');
      setNotes(result.notes || []);
      setError('');
    } catch (e) {
      setError(String(e.message || e));
    } finally { setLoading(false); }
  }, [companyId, recordType]);
  useEffect(() => { reload(); }, [reload]);
  const due = notes.filter(isDue);
  const followups = notes.filter(note => day(note.followup_date) !== null);
  const risks = notes.filter(note => clean(note.risks));
  const current = filter === 'due' ? due : filter === 'followups' ? followups : filter === 'risks' ? risks : notes;
  const copyQuickDraft = async () => {
    if (!title.trim() && !body.trim()) {
      addAlert({ type: 'info', title: 'Nothing to copy yet',
        message: 'Write your internal update first.'});
      return;
    }
    try {
      if (typeof copyTextToClipboard !== 'function') throw new Error('Clipboard not available.');
      await copyTextToClipboard([
        'Siloy Notes · INTERNAL draft backup',
        recordLabel + ' record ID: ' + companyId,
        'Title: ' + (title.trim() || 'Internal update · ' + new Date().toLocaleDateString('en-GB')),
        'Internal note: ' + body
      ].join('\n'));
      addAlert({type: 'success', title: 'Draft copied', message: 'Paste into a secure location before refreshing.'});
    } catch (_) {
      addAlert({type: 'warning', title: 'Copy unavailable',
        message: 'Leave this card open until the note is saved.'});
    }
  };
  const save = async () => {
    if (saveInFlight.current) return;
    setSaveIssue('');
    const defaultTitle = 'Internal update · ' + new Date().toLocaleDateString('en-GB');
    const titleToSave = title.trim() || defaultTitle;
    if (!recordType || !/^\d+$/.test(companyId)) {
      setSaveIssue('Open a supported CRM record to save this note.');
      return;
    }
    if (!body.trim()) {
      setSaveIssue('Write your internal note before saving. A title is optional.');
      return;
    }
    saveInFlight.current = true;
    setBusy(true);
    try {
      const result = unwrap(await hubspot.serverless('corpus_notes_api', {
        parameters: {
          action: 'create',
          recordType,
          recordId: companyId,
          note: {
            note_title: titleToSave,
            internal_notes: body.trim(),
            note_type: 'internal_update',
            note_date: todayISO()
          }
        }
      }));
      if (result.partial && result.noteId) {
        setSavedId(result.noteId);
        setAssociationNeeded(true);
        setTitle('');
        setBody('');
        setComposer(false);
        addAlert({type:'danger', title:'Saved without CRM record link',message:'Open the saved note to complete the association.'});
        return;
      }
      if (!result.success || !result.noteId) throw new Error(result.error || 'HubSpot did not confirm the note was saved.');
      setSavedId(result.noteId);
      setAssociationNeeded(false);
      setTitle('');
      setBody('');
      setComposer(false);
      setFilter('all');
      addAlert({type:'success',title:'Internal note saved',message:'Saved to this ' + recordLabel + '.'});
      // Save is confirmed. Do not keep the save button busy while history refreshes.
      void reload();
    } catch(e) {
      const reason = String(e.message || e);
      setSaveIssue(reason);
      addAlert({type:'danger',title:'Could not save note',message:reason + ' Your draft is still available.'});
    } finally {
      saveInFlight.current = false;
      setBusy(false);
    }
  };

  const url = id => 'https://app-eu1.hubspot.com/contacts/' + portalId + '/record/2-256491528/' + id;
  return (
    <>
      <Flex direction="row" align="center" gap="small" wrap="wrap">
        {displayedBrandMark ? (
          <Image src={displayedBrandMark}
            alt={isSiloyBrand ? 'Siloy Notes' : CORPUS_BRAND.name + ' brand mark'}
            width={300} />
        ) : null}
        <Flex direction="column" gap="small">

          <Text variant="microcopy">Quick notes</Text>
        </Flex>
      </Flex>
      <Flex direction="row" gap="small" wrap="wrap">
        <Tag variant="warning" overlay={<Tooltip placement="bottom">This captures CRM-internal notes, not meeting invitation text. Check CRM and app permissions before adding confidential material.</Tooltip>}><Icon name="info" screenReaderText="Internal notes help" /> Internal only</Tag>
      </Flex>
      <Text variant="microcopy">Quick capture and follow-up cues for this {recordLabel}. Nothing is written to meeting invitations.</Text>
      <Divider />
      <Button variant={composer ? "secondary" : "primary"} disabled={busy} onClick={() => setComposer(v => !v)}>
        {composer ? 'Keep draft and close' : 'New internal note'}
      </Button>
      {!composer && (title.trim() || body.trim()) ? <Tag variant="warning">Unsaved draft retained until refresh</Tag> : null}
      {composer ? (
        <Tile>
          <Heading>Quick capture</Heading>
          <Input name="quickTitle" label="Note title (optional)" value={title}
            disabled={busy} onChange={v => { setTitle(v); setSaveIssue(''); }} placeholder="Auto-generated if empty" />
          <TextArea name="quickBody" label="Internal note" value={body}
            disabled={busy} onChange={v => { setBody(v); setSaveIssue(''); }} rows={3} />
          <Text variant="microcopy">Linked to the current {recordLabel}. For decisions, risks and follow-ups, use the full Siloy Notes workspace.</Text>
          {saveIssue ? <Text>{saveIssue}</Text> : null}
          <Button variant="primary" onClick={save} disabled={busy}>
            {busy ? 'Saving…' : 'Save internal note'}
          </Button>
          <Button variant="secondary" onClick={copyQuickDraft} disabled={busy}>
            Copy draft
          </Button>
          <Text variant="microcopy">Copy draft places text on your device clipboard. No automatic recovery after refreshing the page.</Text>
        </Tile>
      ) : null}
      {savedId ? (
        <Flex direction="column" gap="small">
          <Tag variant={associationNeeded ? 'warning' : 'success'}>{associationNeeded ? 'Created. CRM link needed.' : 'Saved and linked'}</Tag>
          <Link href={url(savedId)}>Open saved note</Link>
        </Flex>
      ) : null}
      <Divider />
      <Flex direction="row" gap="small" align="center" wrap="wrap">
        <Heading>Notes at a glance</Heading>
        <Tag variant="info" overlay={<Tooltip>These cues are calculated from saved Notes linked to this CRM record. They are not notifications or HubSpot Tasks.</Tooltip>}><Icon name="info" screenReaderText="Additional information" /> Help</Tag>
      </Flex>
      <Flex direction="row" gap="small" wrap="wrap">
        <Button variant={filter === 'due' ? 'primary' : 'secondary'}
          overlay={<Tooltip>Follow-ups due today or earlier.</Tooltip>}
          onClick={() => setFilter('due')}>Due ({due.length})</Button>
        <Button variant={filter === 'followups' ? 'primary' : 'secondary'}
          overlay={<Tooltip>All dated follow-ups, including future dates.</Tooltip>}
          onClick={() => setFilter('followups')}>Follow-ups ({followups.length})</Button>
        <Button variant={filter === 'risks' ? 'primary' : 'secondary'}
          overlay={<Tooltip>Notes with a recorded risk or concern.</Tooltip>}
          onClick={() => setFilter('risks')}>Risks ({risks.length})</Button>
        <Button variant={filter === 'all' ? 'primary' : 'secondary'}
          onClick={() => setFilter('all')}>All ({notes.length})</Button>
      </Flex>
      {loading ? <LoadingSpinner label="Loading Siloy Notes" /> : null}
      {error ? <Text>{error}</Text> : null}
      {!loading && !error && current.length === 0 ? (
        <Text variant="microcopy">{filter === 'due' ? 'No follow-ups due.' : filter === 'followups' ? 'No follow-ups recorded.' : filter === 'risks' ? 'No notes with risks.' : 'No saved notes yet.'}</Text>
      ) : null}
      {!loading && !error ? current.slice(0, 3).map(note => (
        <React.Fragment key={note.id}>
          <Divider />
          <Link href={url(note.id)}>{note.note_title || 'Untitled note'}</Link>
          <Text variant="microcopy">
            {isDue(note) ? 'Follow-up due · ' : ''}
            {clean(note.next_steps || note.risks || note.internal_notes).slice(0,110)}
          </Text>
          {day(note.followup_date) !== null ? (
            <Text variant="microcopy">Follow-up: {new Date(day(note.followup_date)).toLocaleDateString('en-GB',{timeZone:'UTC'})}</Text>
          ) : null}
        </React.Fragment>
      )) : null}
      {current.length > 3 ? <Text variant="microcopy">{current.length - 3} more in the full workspace.</Text> : null}
      <Divider />
      <Button variant="secondary" onClick={reload} disabled={loading}>Refresh cues</Button>
      <Text variant="microcopy">These are in-card cues, not push notifications. Internal-only labels do not override CRM permissions.</Text>
    </>
  );
}
