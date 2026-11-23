'use strict';

// Read-only source for Siloy Credit Heatmap. PRIVATE_APP_ACCESS_TOKEN is
// app-wide: restrict app installation and access to users authorised for
// account-wide consumption details. Do not expose it to front-end code.
const API = 'https://api.hubapi.com';
const TYPE = '2-256881483'; // Verified for Siloy UKI Apps portal 149783010 only.
const EXPECTED_PORTAL_ID = 149783010;
const FIELDS = [
  'usage_name', 'credits_used', 'credit_limit', 'feature_code',
  'comparator_type', 'data_method', 'heat_level', 'cost_drivers',
  'enrolments', 'billable_actions', 'email_actions', 'credit_rate',
  'estimated_credits_reconciled', 'hs_createdate'
];

function fail(statusCode, error) { return { statusCode, body: { success: false, error } }; }
function ok(body) { return { statusCode: 200, body: { success: true, ...body } }; }
function getNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}
function normalize(row) {
  const p = row.properties || {};
  return {
    id: String(row.id || p.hs_object_id || ''),
    name: String(p.usage_name || ''),
    feature: String(p.feature_code || 'unspecified'),
    credits: getNumber(p.credits_used),
    limit: getNumber(p.credit_limit),
    comparator: String(p.comparator_type || ''),
    method: String(p.data_method || 'unknown'),
    heat: String(p.heat_level || 'unknown'),
    costDrivers: String(p.cost_drivers || ''),
    periodKey: String(p.sl_period_key || ''),
    periodStart: String(p.sl_period_start || ''),
    periodEnd: String(p.sl_period_end || '')
  };
}
function analyze(rows, truncated = false) {
  const items = rows.map(normalize);
  const methods = {};
  let unperiodised = 0;
  for (const x of items) {
    methods[x.method] = (methods[x.method] || 0) + 1;
    if (!(x.periodKey && x.periodStart && x.periodEnd)) unperiodised++;
  }
  const periodised = unperiodised === 0 && items.length > 0 && !truncated;
  const hot = items.filter(x => x.heat === 'hot' || x.heat === 'critical')
    .sort((a, b) => (b.limit ? b.credits / b.limit : 0) - (a.limit ? a.credits / a.limit : 0));
  // Never aggregate across missing periods, overlapping feature and child records,
  // or claim that a record's `data_method=actual` establishes billing truth.
  return {
    records: items.length,
    methods,
    unperiodised,
    periodised,
    truncated,
    canDisplayBillingTotal: false,
    status: truncated ? 'INCOMPLETE' : (periodised ? 'AWAITING_SOURCE_VERIFICATION' : 'PERIODS_MISSING'),
    hotspots: hot.slice(0, 24),
    items: items.slice(0, 200),
    sourceNote: 'CRM snapshots. No native HubSpot billing reconciliation has been verified. Feature and child records can overlap.'
  };
}
async function readAll(token, maxPages = 5) {
  const rows = [];
  let after = '';
  for (let i = 0; i < maxPages; i++) {
    const params = new URLSearchParams({ limit: '100', properties: FIELDS.join(',') });
    if (after) params.set('after', after);
    const res = await fetch(API + '/crm/v3/objects/' + TYPE + '?' + params.toString(), {
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }
    });
    const body = await res.json();
    if (!res.ok) throw new Error('HubSpot CRM read failed: ' + res.status + ' ' + String(body.message || '').slice(0, 140));
    rows.push(...(body.results || []));
    after = body.paging && body.paging.next && body.paging.next.after || '';
    if (!after) return { rows, truncated: false };
  }
  return { rows, truncated: Boolean(after) };
}
exports.main = async (context = {}) => {
  const token = process.env.PRIVATE_APP_ACCESS_TOKEN;
  if (!token) return fail(503, 'Installed app access token unavailable.');
  const p = context.parameters || {};
  if (p.action !== 'snapshot') return fail(400, 'Unsupported action.');
  // Static private app is bound to one account by project config/installation;
  // this explicit guard prevents accidental reuse of this portal-specific schema.
  const actualHubId = Number(context.accountId || context.portalId || context.hubId || 0);
  if (actualHubId && actualHubId !== EXPECTED_PORTAL_ID)
    return fail(403, 'This build is bound to another HubSpot account.');
  try {
    const { rows, truncated } = await readAll(token);
    return ok(analyze(rows, truncated));
  } catch (err) {
    return fail(502, String(err.message || 'Unknown API error').slice(0, 260));
  }
};
exports._test = { normalize, analyze, readAll, EXPECTED_PORTAL_ID };
