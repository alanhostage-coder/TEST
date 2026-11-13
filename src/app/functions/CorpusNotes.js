'use strict';

/**
 * Portal 145209388, Corpus Notes 2-256491528.
 * This code never updates meetings, calendar entries or invitations.
 * PRIVATE_APP_ACCESS_TOKEN is app-wide; configure CRM record access accordingly.
 */
const TYPE = '2-256491528';
const API = 'https://api.hubapi.com';
const FIELDS = ['note_title', 'note_type', 'note_date', 'internal_notes',
  'meeting_activity_id', 'decisions', 'risks', 'next_steps', 'followup_date',
  'hs_createdate', 'hs_object_id'];
const TYPES = new Set(['meeting', 'call', 'discovery', 'handover', 'internal_update']);

function clean(value, max = 65000) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}
function isRecordId(value) {
  return /^\d{1,20}$/.test(String(value || ''));
}
function dateMs(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const date = new Date(value + 'T00:00:00.000Z');
  return Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value
    ? null : String(date.getTime());
}
function fail(statusCode, error) {
  return { statusCode, body: { success: false, error } };
}
function ok(data) {
  return { statusCode: 200, body: Object.assign({ success: true }, data) };
}
async function api(token, path, options = {}) {
  const response = await fetch(API + path, {
    method: options.method || 'GET',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json'
    },
    ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) })
  });
  const raw = await response.text();
  let data = {};
  if (raw) {
    try { data = JSON.parse(raw); }
    catch { data = { message: 'Unexpected API response' }; }
  }
  if (!response.ok) {
    const error = new Error('HubSpot API ' + response.status + ': ' +
      String(data.message || 'Request failed').slice(0, 240));
    error.status = response.status;
    throw error;
  }
  return data;
}
async function listNotes(token, companyId) {
  const ids = [];
  let after;
  for (let page = 0; page < 5; page++) {
    const path = '/crm/v4/objects/companies/' + companyId + '/associations/' + TYPE +
      '?limit=100' + (after ? '&after=' + encodeURIComponent(after) : '');
    const associations = await api(token, path);
    for (const item of associations.results || []) {
      if (isRecordId(item.toObjectId)) ids.push(String(item.toObjectId));
    }
    after = associations.paging && associations.paging.next && associations.paging.next.after;
    if (!after) break;
  }
  if (!ids.length) {
    return { notes: [], totalAssociated: 0, truncated: false };
  }
  const data = await api(token, '/crm/v3/objects/' + TYPE + '/batch/read', {
    method: 'POST',
    body: { inputs: ids.slice(0, 100).map(id => ({ id })), properties: FIELDS }
  });
  const notes = (data.results || []).map(row => Object.assign({ id: row.id }, row.properties));
  notes.sort((a, b) => {
    const ms = v => {
      if (!v) return 0;
      const n = Number(v);
      return Number.isFinite(n) && n > 0 ? n : Date.parse(v) || 0;
    };
    return ms(b.note_date || b.hs_createdate) - ms(a.note_date || a.hs_createdate);
  });
  return {
    notes,
    totalAssociated: ids.length,
    truncated: Boolean(after || ids.length > 100)
  };
}
async function createNote(token, companyId, input) {
  const title = clean(input.note_title, 255);
  const details = clean(input.internal_notes);
  const type = clean(input.note_type, 40);
  const noteDate = dateMs(input.note_date);
  const follow = clean(input.followup_date, 10);
  const followDate = follow ? dateMs(follow) : null;
  const meetingActivityId = clean(input.meeting_activity_id, 30);
  if (!title || !details) return fail(400, 'Title and internal note are required.');
  if (!TYPES.has(type)) return fail(400, 'Choose a valid note type.');
  if (!noteDate) return fail(400, 'Enter a valid note date.');
  if (follow && !followDate) return fail(400, 'Enter a valid follow-up date.');
  if (meetingActivityId && !isRecordId(meetingActivityId))
    return fail(400, 'Meeting activity ID must be digits only.');

  const properties = {
    note_title: title,
    note_type: type,
    note_date: noteDate,
    internal_notes: details,
    decisions: clean(input.decisions),
    risks: clean(input.risks),
    next_steps: clean(input.next_steps)
  };
  if (followDate) properties.followup_date = followDate;
  if (meetingActivityId) properties.meeting_activity_id = meetingActivityId;

  const created = await api(token, '/crm/v3/objects/' + TYPE, {
    method: 'POST', body: { properties }
  });
  if (!isRecordId(created.id)) return fail(502, 'HubSpot did not return a note ID.');
  try {
    await api(token, '/crm/v4/objects/' + TYPE + '/' + created.id +
      '/associations/default/companies/' + companyId, { method: 'PUT' });
  } catch (error) {
    return {
      statusCode: 207,
      body: {
        success: false, partial: true, noteId: created.id,
        error: 'Note ' + created.id + ' was created but its Company association failed: ' + error.message
      }
    };
  }
  return ok({ noteId: created.id, linkedCompanyId: companyId });
}
exports.main = async (context = {}) => {
  const token = process.env.PRIVATE_APP_ACCESS_TOKEN;
  if (!token) return fail(503, 'App access token is missing. Install this app.');
  const params = context.parameters || {};
  const companyId = String(params.companyId || '');
  if (!isRecordId(companyId)) return fail(400, 'Valid company record required.');
  try {
    if (params.action === 'list') return ok(await listNotes(token, companyId));
    if (params.action === 'create') return await createNote(token, companyId, params.note || {});
    return fail(400, 'Unsupported action.');
  } catch (error) {
    const status = error.status >= 400 && error.status < 500 ? error.status : 502;
    return fail(status, error.status === 403
      ? 'The installed app is missing CRM scopes.'
      : String(error.message || 'Unexpected error').slice(0, 260));
  }
};
exports._test = { isRecordId, dateMs, clean, listNotes, createNote, FIELDS, TYPE };
