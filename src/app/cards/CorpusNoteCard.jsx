import React, { useCallback, useEffect, useState } from 'react';
import {
  hubspot, Heading, Text, Input, TextArea, Select, Button, Link,
  Divider, LoadingSpinner, Flex, Tile, Tag, Image
} from '@hubspot/ui-extensions';
import { CORPUS_BRAND } from './brand-config';

// A public brand-only asset, never a people photograph or arbitrary website hero.
// Native CRM UI extensions do not support arbitrary CSS hex-colour borders.
const SILOY_COLOUR_RAIL_URL =
  'https://raw.githubusercontent.com/alanhostage-coder/TEST/refs/heads/codex/corpus-note-hubspot-card/src/app/cards/assets/siloy-colour-rail.svg';
const isSiloyBrand = /^https:\/\/(?:www\.)?siloy\.com(?:\/|$)/i.test(CORPUS_BRAND.websiteUrl || '');
const SILOY_SIGNAGE_MARK_URL =
  'https://raw.githubusercontent.com/alanhostage-coder/TEST/refs/heads/codex/corpus-note-hubspot-card/src/app/cards/assets/siloy-signage-mark.svg';
const displayedBrandMark = isSiloyBrand ? SILOY_SIGNAGE_MARK_URL : CORPUS_BRAND.logoUrl;

const OPTIONS = [
  { label: 'Meeting', value: 'meeting' },
  { label: 'Call', value: 'call' },
  { label: 'Discovery', value: 'discovery' },
  { label: 'Handover', value: 'handover' },
  { label: 'Internal update', value: 'internal_update' }
];
const WRITING_GUIDES = {
  meeting: 'Capture the discussion privately: what was decided, what is sensitive and who owns the next step?',
  call: 'Capture the context, what changed and the action to take next.',
  discovery: 'What did we learn, what is not yet confirmed and what is the next question?',
  handover: 'What must the next colleague know, what is unresolved and what happens next?',
  internal_update: 'What is the update, why does it matter and what needs attention?'
};
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
  <CorpusNoteCard context={context} addAlert={actions.addAlert}
    copyTextToClipboard={actions.copyTextToClipboard} />
));
function CorpusNoteCard({ context, addAlert, copyTextToClipboard }) {
  const companyId = String(context?.crm?.objectId || '');
  const portalId = String(context?.portal?.id || '145209388');
  const [notes, setNotes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const saveInFlight = React.useRef(false);
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
  const [saveIssue, setSaveIssue] = useState('');
  const [draftProtected, setDraftProtected] = useState(false);
  const [historyFilter, setHistoryFilter] = useState('all');
  const [historyQuery, setHistoryQuery] = useState('');
  const [focusWriting, setFocusWriting] = useState(false);
  const noteTypeLabel = OPTIONS.find(option => option.value === form.note_type)?.label || 'Internal note';
  const suggestedTitle = noteTypeLabel + ' · ' + (ukDate || isoToUK(today()));
  const effectiveTitle = form.note_title.trim() || suggestedTitle;
  const dueCount = notes.filter(hasDueFollowup).length;
  const followupCount = notes.filter(hasFollowup).length;
  const riskCount = notes.filter(n => String(n.risks || '').trim()).length;
  const decisionCount = notes.filter(n => String(n.decisions || '').trim()).length;
  const nextActionCount = notes.filter(n => String(n.next_steps || '').trim()).length;
  const visibleNotes = notes.filter(note => {
    const q = historyQuery.toLowerCase().trim();
    if (q && ![note.note_title, note.note_type, note.internal_notes, note.decisions, note.risks,
      note.next_steps].some(item => readable(item, 65000).toLowerCase().includes(q))) return false;
    if (historyFilter === 'due') return hasDueFollowup(note);
    if (historyFilter === 'followups') return hasFollowup(note);
    if (historyFilter === 'risks') return Boolean(String(note.risks || '').trim());
    if (historyFilter === 'decisions') return Boolean(String(note.decisions || '').trim());
    if (historyFilter === 'actions') return Boolean(String(note.next_steps || '').trim());
    return true;
  });
  const set = (key, value) => {
    setSaveIssue('');
    setDirty(true);
    setDiscardArmed(false);
    setForm(old => ({ ...old, [key]: value }));
  };
  const setDate = value => { setSaveIssue(''); setDirty(true); setUkDate(value); setDiscardArmed(false); };
  const setFollowDate = value => { setSaveIssue(''); setDirty(true); setUkFollowup(value); setDiscardArmed(false); };
  const noteUrl = id => 'https://app-eu1.hubspot.com/contacts/' + portalId +
    '/record/2-256491528/' + id;
  const recoveryText = () => [
    'Corpus Notes · INTERNAL draft backup',
    'Company record ID: ' + companyId,
    'Title: ' + effectiveTitle,
    'Type: ' + noteTypeLabel,
    'Note date: ' + ukDate,
    'Internal notes:', form.internal_notes || '(empty)',
    'Decisions:', form.decisions || '(none)',
    'Risks:', form.risks || '(none)',
    'Next steps:', form.next_steps || '(none)',
    'Follow-up date: ' + (ukFollowup || '(none)'),
    'Meeting reference (not an association): ' + (form.meeting_activity_id || '(none)')
  ].join('\n');
  const copyDraft = async () => {
    if (!form.internal_notes.trim() && !form.decisions.trim() && !form.risks.trim()
      && !form.next_steps.trim() && !form.note_title.trim()) {
      addAlert({ type: 'info', title: 'Nothing to copy yet',
        message: 'Write a note first, then use Copy recovery draft.' });
      return;
    }
    try {
      if (typeof copyTextToClipboard !== 'function') throw new Error('Clipboard action unavailable.');
      await copyTextToClipboard(recoveryText());
      addAlert({type: 'success', title: 'Recovery copy created',
        message: 'Your draft is on the device clipboard. Paste it into a secure location before refreshing.'});
    } catch (error) {
      addAlert({type: 'warning', title: 'Could not copy draft',
        message: 'Clipboard access was unavailable. Keep this card open until you have saved the note.'});
    }
  };
  const discard = () => {
    if (dirty && !discardArmed) { setDiscardArmed(true); return; }
    setForm(empty());
    setUkDate(isoToUK(today()));
    setUkFollowup('');
    setDirty(false);
    setDiscardArmed(false);
    setDetailsOpen(false);
    setDraftProtected(false);
    setSaveIssue('');
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
    if (saveInFlight.current) return;
    setSaveIssue('');
    const noteDate = ukToISO(ukDate);
    const followDate = ukFollowup ? ukToISO(ukFollowup) : '';
    const activityId = String(form.meeting_activity_id || '').trim();
    let problem = '';
    if (!/^\d+$/.test(companyId)) {
      problem = 'Open a Company record to save your note.';
    } else if (!form.internal_notes.trim()) {
      problem = 'Add your internal notes before saving. A title is optional.';
    } else if (!noteDate) {
      problem = 'Enter a valid note date (dd/mm/yyyy) in Add decisions, risks or next steps.';
      setDetailsOpen(true);
    } else if (ukFollowup && !followDate) {
      problem = 'Check the optional follow-up date (dd/mm/yyyy).';
      setDetailsOpen(true);
    } else if (activityId && !/^\d+$/.test(activityId)) {
      problem = 'Meeting activity ID must contain digits only. It is an optional reference.';
      setDetailsOpen(true);
    }
    if (problem) {
      setSaveIssue(problem);
      addAlert({type: 'danger', title: 'One thing to check', message: problem});
      return;
    }
    saveInFlight.current = true;
    setSaving(true);
    try {
      const result = unwrap(await hubspot.serverless('corpus_notes_api', {
        parameters: {
          action: 'create',
          companyId,
          note: { ...form, note_title: effectiveTitle, note_date: noteDate, followup_date: followDate }
        }
      }));
      if (result.partial && result.noteId) {
        setReceipt({ id: result.noteId, title: effectiveTitle, linked: false });
        setComposerOpen(false);
        setDirty(false);
        setDraftProtected(false);
        setFocusWriting(false);
        addAlert({
          type: 'danger', title: 'Note created, but not linked',
          message: 'Open the saved record and associate this Company. Do not save again or you could create a duplicate.'
        });
        return;
      }
      if (!result.success || !result.noteId)
        throw new Error(result.error || 'HubSpot did not confirm the saved note.');
      setReceipt({ id: result.noteId, title: effectiveTitle, linked: true });
      setForm(empty());
      setUkDate(isoToUK(today()));
      setUkFollowup('');
      setDirty(false);
      setDiscardArmed(false);
      setDetailsOpen(false);
      setComposerOpen(false);
      setDraftProtected(false);
      setFocusWriting(false);
      addAlert({
        type: 'success', title: 'Internal note saved',
        message: 'Your note is linked to this Company.'
      });
      // Saving and refreshing history are separate operations. The save is already confirmed;
      // a slow or failed history refresh must not turn it into an apparent save failure.
      void reload();
    } catch (err) {
      const reason = String(err.message || err);
      setSaveIssue(reason);
      addAlert({
        type: 'danger', title: 'Could not save this note',
        message: reason + ' Your draft is still here.'
      });
    } finally {
      saveInFlight.current = false;
      setSaving(false);
    }
  };

  return (
    <>
      <Tile>
        <Flex direction="row" align="center" gap="small" wrap="wrap">
          {displayedBrandMark ? (
            <Image src={displayedBrandMark}
              alt={isSiloyBrand ? 'Siloy official mark on UKI signage' : CORPUS_BRAND.name + ' brand mark'}
              width={180} />
          ) : null}
          <Flex direction="column" gap="small">
            <Heading>Corpus Notes</Heading>
            <Text variant="microcopy">Internal workspace · by Siloy UKI</Text>
          </Flex>
        </Flex>
        {isSiloyBrand ? (
          <Image src={SILOY_COLOUR_RAIL_URL}
            alt="Siloy brand accent colours: powder blue, yellow and mint" width={900} />
        ) : null}
        <Flex direction="row" wrap="wrap" gap="small">
          <Tag variant="warning">INTERNAL ONLY</Tag>
          <Tag variant="info">Never included in meeting invitations</Tag>
          {CORPUS_BRAND.name !== 'Siloy UKI' ? (
            <Tag variant="default">{CORPUS_BRAND.name} workspace</Tag>
          ) : null}
        </Flex>
      </Tile>
      <Text>Capture internal context, document decisions and keep the next action visible.</Text>
      <Text variant="microcopy">Notes created here are stored on the Company, never in a meeting invitation. CRM permissions still govern who can see them.</Text>
      <Flex direction="row" wrap="wrap" gap="small">
        <Button variant="secondary" onClick={() => { setComposerOpen(true); setReceipt(null); }}>
          Write a note
        </Button>
        <Button variant="secondary" onClick={() => { setHistoryFilter('due'); setHistoryExpanded(true); setFocusWriting(false); }}>
          Follow-ups due ({dueCount})
        </Button>
        <Button variant="secondary" onClick={() => setFocusWriting(v => !v)}>
          {focusWriting ? 'Show history' : 'Focus on writing'}
        </Button>
      </Flex>
      <Divider />

      {receipt ? (
        <Tile>
          <Tag variant={receipt.linked ? 'success' : 'warning'}>
            {receipt.linked ? 'Note saved and linked' : 'Note created, association needed'}
          </Tag>
          <Heading>{receipt.title}</Heading>
          <Text>{receipt.linked
            ? 'Your note was saved and linked to this Company.'
            : 'The note exists, but the Company link failed. Open the record and associate the Company. Do not save the same note again.'}</Text>
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
          <Flex direction="row" align="center" gap="small" wrap="wrap">
            <Tag variant="info">01 / Capture</Tag>
            <Heading>Write an internal note</Heading>
          </Flex>
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
            {draftProtected ? <Text variant="microcopy">Editing is paused, but you can still save your note. Unlock the editor to make changes. This is not a security control.</Text> : null}
            <Input name="noteTitle" label="Title (optional)" disabled={draftProtected || saving} value={form.note_title}
              onChange={v => set('note_title', v)} placeholder="e.g. Internal client review" />
            {!form.note_title.trim() ? <Text variant="microcopy">We'll name this note: {suggestedTitle}</Text> : null}
            <Select name="noteType" label="Note type" disabled={draftProtected || saving} options={OPTIONS}
              value={form.note_type} onChange={v => set('note_type', v)} />
            <Text variant="microcopy">{WRITING_GUIDES[form.note_type] || WRITING_GUIDES.internal_update}</Text>
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
            <Flex direction="row" gap="small" align="center" wrap="wrap">
              <Tag variant="success">03 / Save</Tag>
              <Heading>Save to Company</Heading>
            </Flex>
            <Text variant="microcopy">Save works even when the editor is protected. A blank title is automatically generated from the note type and date.</Text>
            {saveIssue ? <Text>{saveIssue}</Text> : null}
            <Flex direction="row" gap="small" wrap="wrap">
              <Button onClick={save} disabled={saving}>
                {saving ? 'Saving note…' : 'Save internal note'}
              </Button>
              <Button variant="secondary" onClick={copyDraft} disabled={saving}>
                Copy recovery draft
              </Button>
              <Button variant={dirty ? 'destructive' : 'secondary'} onClick={discard} disabled={saving || draftProtected}>
                {dirty && !discardArmed ? 'Discard draft' : dirty ? 'Confirm discard' : 'Clear'}
              </Button>
            </Flex>
            <Text variant="microcopy">Recovery copies are manual and stored in your device clipboard, not automatically saved by Corpus. Handle confidential text carefully.</Text>
            {discardArmed ? (
              <Text variant="microcopy">Select Confirm discard to permanently clear this unsaved draft.</Text>
            ) : null}
          </>
        ) : (
          <Text variant="microcopy">Select New note to open the editor. You can review the Company history below.</Text>
        )}
      </Tile>

      {!focusWriting ? (
      <>
      <Divider />
      <Tile>
        <Flex direction="row" justify="between" gap="small" wrap="wrap" align="center">
          <Flex direction="row" gap="small" align="center" wrap="wrap">
            <Tag variant="info">04 / Review</Tag>
            <Heading>Company notes and follow-ups</Heading>
          </Flex>
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
            <Input name="historySearch" label="Find in loaded notes" value={historyQuery}
              onChange={setHistoryQuery} placeholder="Search titles, decisions, risks or actions" />
            <Flex direction="row" gap="small" wrap="wrap">
              <Button variant={historyFilter === 'all' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('all'); setHistoryExpanded(false); }}>All</Button>
              <Button variant={historyFilter === 'due' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('due'); setHistoryExpanded(true); }}>Due ({dueCount})</Button>
              <Button variant={historyFilter === 'followups' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('followups'); setHistoryExpanded(true); }}>Follow-ups ({followupCount})</Button>
              <Button variant={historyFilter === 'risks' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('risks'); setHistoryExpanded(true); }}>Risks ({riskCount})</Button>
              <Button variant={historyFilter === 'decisions' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('decisions'); setHistoryExpanded(true); }}>Decisions ({decisionCount})</Button>
              <Button variant={historyFilter === 'actions' ? 'primary' : 'secondary'}
                onClick={() => { setHistoryFilter('actions'); setHistoryExpanded(true); }}>Next actions ({nextActionCount})</Button>
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
        <Text variant="microcopy">Search and follow-up indicators use loaded notes only (up to 100). They are not notifications or CRM tasks.</Text>
      </Tile>
      </>
      ) : (
        <Text variant="microcopy">Focus mode: history is hidden while you write. Select Show history to review saved notes.</Text>
      )}
      <Text variant="microcopy">
        Corpus Notes by Siloy UKI · {CORPUS_BRAND.name} workspace.
        Attachments are managed on each saved note. Verify app and CRM permissions before recording confidential information.
      </Text>
    </>
  );
}
