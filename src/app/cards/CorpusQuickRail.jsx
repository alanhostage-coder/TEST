import React, { useCallback, useEffect, useState } from 'react';
import {
  hubspot, Heading, Text, Tag, Divider, Button, Input,
  TextArea, Flex, Link, LoadingSpinner, Tile
} from '@hubspot/ui-extensions';

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
  const portalId = String(context?.portal?.id || '145209388');
  const [notes, setNotes] = useState([]);
  const [filter, setFilter] = useState('due');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [composer, setComposer] = useState(false);
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [savedId, setSavedId] = useState('');
  const [saveIssue, setSaveIssue] = useState('');
  const saveInFlight = React.useRef(false);
  const reload = useCallback(async () => {
    if (!/^\d+$/.test(companyId)) { setLoading(false); setError('Open a Company record.'); return; }
    setLoading(true);
    try {
      const result = unwrap(await hubspot.serverless('corpus_notes_api', {
        parameters: { action: 'list', companyId }
      }));
      if (!result.success) throw new Error(result.error || 'Unable to read linked notes.');
      setNotes(result.notes || []);
      setError('');
    } catch (e) {
      setError(String(e.message || e));
    } finally { setLoading(false); }
  }, [companyId]);
  useEffect(() => { reload(); }, [reload]);
  const due = notes.filter(isDue);
  const risks = notes.filter(note => clean(note.risks));
  const current = filter === 'due' ? due : filter === 'risks' ? risks : notes;
  const copyQuickDraft = async () => {
    if (!title.trim() && !body.trim()) {
      addAlert({ type: 'info', title: 'Nothing to copy yet',
        message: 'Write your internal update first.'});
      return;
    }
    try {
      if (typeof copyTextToClipboard !== 'function') throw new Error('Clipboard not available.');
      await copyTextToClipboard([
        'Corpus Notes · INTERNAL draft backup',
        'Company record ID: ' + companyId,
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
    if (!/^\d+$/.test(companyId)) {
      setSaveIssue('Open a Company record to save this note.');
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
          companyId,
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
        setComposer(false);
        setSaveIssue('Note was created but not linked to this Company. Open the saved note and link it manually. Do not save it twice.');
        addAlert({type:'danger', title:'Saved without Company link',message:'Open the saved note to complete the association.'});
        return;
      }
      if (!result.success || !result.noteId) throw new Error(result.error || 'HubSpot did not confirm the note was saved.');
      setSavedId(result.noteId);
      setTitle('');
      setBody('');
      setComposer(false);
      setFilter('all');
      addAlert({type:'success',title:'Internal note saved',message:'Saved to this Company.'});
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
      <Heading>Corpus Notes</Heading>
      <Flex direction="row" gap="small" wrap="wrap">
        <Tag variant="warning">INTERNAL ONLY</Tag>
        <Tag variant="default">Siloy UKI</Tag>
      </Flex>
      <Text variant="microcopy">Quick capture and follow-up cues for this Company. Nothing is written to meeting invitations.</Text>
      <Divider />
      <Button onClick={() => setComposer(v => !v)}>
        {composer ? 'Close quick capture' : '+ Quick internal note'}
      </Button>
      {composer ? (
        <Tile>
          <Heading>01 · Quick capture</Heading>
          <Input name="quickTitle" label="Note title (optional)" value={title}
            disabled={busy} onChange={v => { setTitle(v); setSaveIssue(''); }} placeholder="Auto-generated if empty" />
          <TextArea name="quickBody" label="Internal note" value={body}
            disabled={busy} onChange={v => { setBody(v); setSaveIssue(''); }} rows={3} />
          <Text variant="microcopy">Linked only to the current Company. For decisions, risks and dates, use the full Corpus Notes workspace.</Text>
          {saveIssue ? <Text>{saveIssue}</Text> : null}
          <Button onClick={save} disabled={busy}>
            {busy ? 'Saving…' : 'Save internal note'}
          </Button>
          <Button variant="secondary" onClick={copyQuickDraft} disabled={busy}>
            Copy draft
          </Button>
          <Button variant="secondary" onClick={() => setComposer(false)} disabled={busy}>
            Keep draft and close
          </Button>
          <Text variant="microcopy">Copy draft places text on your device clipboard. No automatic recovery after refreshing the page.</Text>
        </Tile>
      ) : null}
      {savedId ? <Text><Link href={url(savedId)}>Open the note just saved</Link></Text> : null}
      <Divider />
      <Heading>02 · What needs attention?</Heading>
      <Flex direction="row" gap="small" wrap="wrap">
        <Button variant={filter === 'due' ? 'primary' : 'secondary'}
          onClick={() => setFilter('due')}>Due ({due.length})</Button>
        <Button variant={filter === 'risks' ? 'primary' : 'secondary'}
          onClick={() => setFilter('risks')}>Risks ({risks.length})</Button>
        <Button variant={filter === 'all' ? 'primary' : 'secondary'}
          onClick={() => setFilter('all')}>All ({notes.length})</Button>
      </Flex>
      {loading ? <LoadingSpinner label="Loading Corpus Notes" /> : null}
      {error ? <Text>{error}</Text> : null}
      {!loading && !error && current.length === 0 ? (
        <Text variant="microcopy">Nothing in this view. Use another quick filter to review notes.</Text>
      ) : null}
      {!loading && !error ? current.slice(0, 3).map(note => (
        <React.Fragment key={note.id}>
          <Divider />
          <Link href={url(note.id)}>{note.note_title || 'Untitled note'}</Link>
          <Text variant="microcopy">
            {isDue(note) ? 'Follow-up due · ' : ''}
            {clean(note.next_steps || note.risks || note.internal_notes).slice(0,110)}
          </Text>
        </React.Fragment>
      )) : null}
      {current.length > 3 ? <Text variant="microcopy">{current.length - 3} more in the full workspace.</Text> : null}
      <Divider />
      <Button variant="secondary" onClick={reload} disabled={loading}>Refresh cues</Button>
      <Text variant="microcopy">These are in-card cues, not push notifications. Internal-only labels do not override CRM permissions.</Text>
    </>
  );
}
