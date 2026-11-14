import React, { useCallback, useEffect, useState } from 'react';
import {
  hubspot, Heading, Text, Input, TextArea, Select, Button, Link,
  Divider, LoadingSpinner, Flex, Tile, Tag, Image
} from '@hubspot/ui-extensions';
import { CORPUS_BANNER_DATA_URI } from './brand-banner';
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
function toDay(value) {
  if (!value) return null;
  const n = /^\d+$/.test(String(value)) ? Number(value) : Date.parse(String(value));
  if (!Number.isFinite(n)) return null;
  const date = new Date(n);
  return Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate());
}
function hasDueFollowup(note) {
  const d = toDay(note.followup_date);
  return d !== null && d <= toDay(new Date().toISOString());
}
function hasFollowup(note) { return toDay(note.followup_date) !== null; }
function readable(value, limit = 600) {
  const plain = String(value || '').replace(/<[^>]*>/g, ' ').replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&').replace(/\s+/g, ' ').trim();
  return plain.length > limit ? plain.slice(0, limit).trimEnd() + '…' : plain;
}

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
  const [composerOpen, setComposerOpen] = useState(true);
  const [detailsOpen, setDetailsOpen] = useState(false);
  const [historyExpanded, setHistoryExpanded] = useState(false);
  const [receipt, setReceipt] = useState(null);
  const [discardArmed, setDiscardArmed] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [draftProtected, setDraftProtected] = useState(false);
  const [historyFilter, setHistoryFilter] = useState('all');
  const dueCount = notes.filter(hasDueFollowup).length;
  const followupCount = notes.filter(hasFollowup).length;
  const riskCount = notes.filter(n => String(n.risks || '').trim()).length;
  const visibleNotes = notes.filter(note => {
    if (historyFilter === 'due') return hasDueFollowup(note);
    if (historyFilter === 'followups') return hasFollowup(note);
    if (historyFilter === 'risks') return Boolean(String(note.risks || '').trim());
    if (historyFilter === 'decisions') return Boolean(String(note.decisions || '').trim());
    return true;
  });
  const set = (key, value) => {
    setDirty(true);
    setDiscardArmed(false);
    setForm(old => ({ ...old, [key]: value }));
  };
  const setDate = value => { setDirty(true); setUkDate(value); setDiscardArmed(false); };
  const setFollowDate = value => { setDirty(true); setUkFollowup(value); setDiscardArmed(false); };
  const noteUrl = id => 'https://app-eu1.hubspot.com/contacts/' + portalId +
    '/record/2-256491528/' + id;
  const discard = () => {
    if (dirty && !discardArmed) { setDiscardArmed(true); return; }
    setForm(empty());
    setUkDate(isoToUK(today()));
    setUkFollowup('');
    setDirty(false);
    setDiscardArmed(false);
    setDetailsOpen(false);
    setDraftProtected(false);
  };

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
    if (saving || draftProtected) return;
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
      setReceipt({ id: result.noteId, title: form.note_title.trim() });
      setDirty(false);
      setDiscardArmed(false);
      setDetailsOpen(false);
      setComposerOpen(false);
      setDraftProtected(false);
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
      <Image src={CORPUS_BANNER_DATA_URI}
        alt={'Corpus Notes by ' + CORPUS_BRAND.name + '. Internal workspace.'} width={900} />
      <Heading>Corpus Notes</Heading>
      <Flex direction="row" wrap="wrap" gap="small">
        <Tag variant="default">by Siloy UKI</Tag>
        <Tag variant="warning">INTERNAL ONLY</Tag>
        <Tag variant="info">No attendee invitations</Tag>
        <Tag variant="default">Workspace: {CORPUS_BRAND.name}</Tag>
      </Flex>
      <Text>Capture internal context, document decisions and keep the next action visible.</Text>
      <Text variant="microcopy">Notes created here are stored on the Company, never in a meeting invitation. CRM permissions still govern who can see them.</Text>
      <Flex direction="row" wrap="wrap" gap="small">
        <Button variant="secondary" onClick={() => { setComposerOpen(true); setReceipt(null); }}>
          Write a note
        </Button>
        <Button variant="secondary" onClick={() => { setHistoryFilter('due'); setHistoryExpanded(true); }}>
          Follow-ups due ({dueCount})
        </Button>
      </Flex>
      <Divider />

      {receipt ? (
        <Tile>
          <Tag variant="success">Note saved</Tag>
          <Heading>{receipt.title}</Heading>
          <Text>Saved to Corpus Notes and linked to this Company record.</Text>
          <Flex direction="row" gap="small" wrap="wrap">
            <Link href={noteUrl(receipt.id)}>Open saved note</Link>
            <Button variant="secondary" onClick={() => { setReceipt(null); setComposerOpen(true); }}>
              Write another note
            </Button>
          </Flex>
        </Tile>
      ) : null}

      <Tile>
        <Flex direction="row" justify="between" gap="small" align="center" wrap="wrap">
          <Heading>01 · Capture the note</Heading>
          <Button variant="secondary" onClick={() => setComposerOpen(v => !v)}>
            {composerOpen ? 'Hide editor' : 'New note'}
          </Button>
        </Flex>
        {!composerOpen && dirty ? <Text variant="microcopy">Your unsaved draft is retained while this card is open.</Text> : null}
        {composerOpen ? (
          <>
            <Text variant="microcopy">
              Start with the essentials. Keep decisions, risks and next actions separate so they can be found later.
            </Text>
            <Flex direction="row" gap="small" wrap="wrap">
              <Button variant="secondary" onClick={() => setDraftProtected(v => !v)} disabled={saving}>
                {draftProtected ? 'Unlock editor' : 'Protect draft'}
              </Button>
              {draftProtected ? <Tag variant="warning">Editing paused</Tag> : null}
            </Flex>
            {draftProtected ? <Text variant="microcopy">Draft protection prevents accidental edits in this open card only. It is not a security lock or persisted setting.</Text> : null}
            <Input name="noteTitle" label="Title" required disabled={draftProtected || saving} value={form.note_title}
              onChange={v => set('note_title', v)} placeholder="e.g. Internal client review" />
            <Select name="noteType" label="Note type" disabled={draftProtected || saving} options={OPTIONS}
              value={form.note_type} onChange={v => set('note_type', v)} />
            <TextArea name="noteBody" label="Your internal notes" required rows={5} disabled={draftProtected || saving}
              value={form.internal_notes} onChange={v => set('internal_notes', v)}
              placeholder="What happened, what matters, and what needs attention..." />
            <Flex direction="row" gap="small" wrap="wrap">
              <Tag variant="default">{dirty ? 'Unsaved changes' : 'Ready to write'}</Tag>
              <Text variant="microcopy">Save to the Company, not to an invitation.</Text>
            </Flex>
            <Divider />
            <Button variant="secondary" onClick={() => setDetailsOpen(v => !v)}>
              {detailsOpen ? '02 · Hide context' : '02 · Add decisions, risks or next steps'}
            </Button>
            {detailsOpen ? (
              <>
                <Input name="noteDate" disabled={draftProtected || saving} label="Note date (dd/mm/yyyy)" value={ukDate}
                  onChange={setDate} placeholder="13/11/2026" />
                <TextArea name="decisions" disabled={draftProtected || saving} label="Decisions" rows={2}
                  value={form.decisions} onChange={v => set('decisions', v)}
                  placeholder="What was agreed?" />
                <TextArea name="risks" disabled={draftProtected || saving} label="Risks and concerns" rows={2}
                  value={form.risks} onChange={v => set('risks', v)}
                  placeholder="What needs watching?" />
                <TextArea name="nextSteps" disabled={draftProtected || saving} label="Next actions" rows={2}
                  value={form.next_steps} onChange={v => set('next_steps', v)}
                  placeholder="Who is doing what?" />
                <Input name="followupDate" disabled={draftProtected || saving} label="Follow-up date (dd/mm/yyyy)" value={ukFollowup}
                  onChange={setFollowDate} placeholder="Optional" />
                <Input name="meetingActivityId" disabled={draftProtected || saving} label="Meeting activity ID (optional reference only)"
                  value={form.meeting_activity_id}
                  onChange={v => set('meeting_activity_id', v)}
                  placeholder="Digits only. Not a meeting association." />
              </>
            ) : null}
            <Divider />
            <Heading>03 · Save to Company</Heading>
            <Text variant="microcopy">This action creates a new Corpus Note linked to the current Company. It does not edit the calendar event.</Text>
            <Flex direction="row" gap="small" wrap="wrap">
              <Button onClick={save}
                disabled={saving || draftProtected || !/^\d+$/.test(companyId) || !form.note_title.trim() || !form.internal_notes.trim()}>
                {saving ? 'Saving note…' : 'Save internal note'}
              </Button>
              <Button variant={dirty ? 'destructive' : 'secondary'} onClick={discard} disabled={saving || draftProtected}>
                {dirty && !discardArmed ? 'Discard draft' : dirty ? 'Confirm discard' : 'Clear'}
              </Button>
            </Flex>
            {discardArmed ? (
              <Text variant="microcopy">Select Confirm discard to permanently clear this unsaved draft.</Text>
            ) : null}
          </>
        ) : (
          <Text variant="microcopy">Select New note to open the editor. You can review the Company history below.</Text>
        )}
      </Tile>

      <Divider />
      <Tile>
        <Flex direction="row" justify="between" gap="small" wrap="wrap" align="center">
          <Heading>04 · Review and follow up</Heading>
          <Button variant="secondary" onClick={reload} disabled={loading}>
            {loading ? 'Refreshing…' : 'Refresh'}
          </Button>
        </Flex>
        {loading ? <LoadingSpinner label="Loading saved notes" /> : null}
        {error ? <Text>{error}</Text> : null}
        {!loading && !error && notes.length === 0 ? (
          <Text>No linked Corpus Notes yet. Create the first internal note above.</Text>
        ) : null}
        {!loading && !error && notes.length > 0 ? (
          <>
            <Text variant="microcopy">{notes.length}{truncated ? '+' : ''} saved notes · {dueCount} follow-ups due · {riskCount} with risks</Text>
            <Flex direction="row" gap="small" wrap="wrap">
              <Button variant={historyFilter === 'all' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('all'); setHistoryExpanded(false); }}>All</Button>
              <Button variant={historyFilter === 'due' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('due'); setHistoryExpanded(true); }}>Due ({dueCount})</Button>
              <Button variant={historyFilter === 'followups' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('followups'); setHistoryExpanded(true); }}>Follow-ups ({followupCount})</Button>
              <Button variant={historyFilter === 'risks' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('risks'); setHistoryExpanded(true); }}>Risks ({riskCount})</Button>
            </Flex>
            {visibleNotes.length === 0 ? <Text>No notes match this filter. Choose All to see the full Company history.</Text> : null}
            {visibleNotes.slice(0, historyExpanded ? visibleNotes.length : 3).map(note => (
              <React.Fragment key={note.id}>
                <Divider />
                <Heading>{note.note_title || 'Untitled internal note'}</Heading>
                <Flex direction="row" gap="small" wrap="wrap">
                  <Tag variant="default">{note.note_type || 'Internal'}</Tag>
                  {hasDueFollowup(note) ? <Tag variant="warning">Follow-up due</Tag> : null}
                  <Text variant="microcopy">{isoToUK(note.note_date || note.hs_createdate)}</Text>
                </Flex>
                <Text>{readable(note.internal_notes, 240)}</Text>
                {note.decisions ? <Text>Decision: {readable(note.decisions, 180)}</Text> : null}
                {note.risks ? <Text>Risk: {readable(note.risks, 160)}</Text> : null}
                {note.next_steps ? <Text>Next action: {readable(note.next_steps, 180)}</Text> : null}
                {hasFollowup(note) ? <Text variant="microcopy">Follow-up: {isoToUK(note.followup_date)}</Text> : null}
                <Link href={noteUrl(note.id)}>Open full note</Link>
              </React.Fragment>
            ))}
            {visibleNotes.length > 3 ? (
              <Button variant="secondary" onClick={() => setHistoryExpanded(v => !v)}>
                {historyExpanded ? 'Show first three' : 'Show all ' + visibleNotes.length + ' matching notes'}
              </Button>
            ) : null}
          </>
        ) : null}
        {truncated ? <Text variant="microcopy">Showing up to 100 notes. Older records can be found in Corpus Notes. Filter counts only cover loaded notes.</Text> : null}
        <Text variant="microcopy">Follow-up indicators update when the card loads or refreshes. No emails, push notifications or CRM tasks are sent.</Text>
      </Tile>
      <Text variant="microcopy">
        Corpus Notes by Siloy UKI · {CORPUS_BRAND.name} workspace.
        Attachments are managed on each saved note. Verify app and CRM permissions before recording confidential information.
      </Text>
    </>
  );
}
