// Shared, read-only helpers for the two Company cards.
export const ENTITLEMENT_TYPE = '2-256878303';
export const PORTAL_ID = '149783010';
export const RECORD_BASE = `https://app-eu1.hubspot.com/contacts/${PORTAL_ID}/record/${ENTITLEMENT_TYPE}`;
export const LICENCE_PROPERTIES = [
  'entitlement_reference','entitlement_type','sl_status',
  'sl_start_date','sl_end_date','sl_notice_date',
  'sl_quantity','sl_resource_code','sl_monthly_fee','sl_rights'
];
export const todayLondon = () => {
  const parts=new Intl.DateTimeFormat('en-GB',{
    timeZone:'Europe/London',year:'numeric',month:'2-digit',day:'2-digit'
  }).formatToParts(new Date());
  const part=type=>parts.find(p=>p.type===type)?.value||'';
  return `${part('year')}-${part('month')}-${part('day')}`;
};
export const daysUntil = (date, today=todayLondon()) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date||'')) return null;
  return Math.round((Date.parse(date+'T00:00:00Z')-Date.parse(today+'T00:00:00Z'))/86400000);
};
export const uk = value => /^\d{4}-\d{2}-\d{2}$/.test(value||'')
  ? value.split('-').reverse().join('/') : 'Not set';
export const gbp = value => '£'+Number(value||0).toLocaleString('en-GB',{
  minimumFractionDigits:0,maximumFractionDigits:2});
export const rowsFromAssociations = results => (results||[]).map(a=>({
  id:String(a.toObjectId||''), reference:String(a.properties?.entitlement_reference||`Record ${a.toObjectId}`),
  status:String(a.properties?.sl_status||'unspecified'),
  type:String(a.properties?.entitlement_type||'unspecified'),
  resource:String(a.properties?.sl_resource_code||'Unassigned'),
  start:String(a.properties?.sl_start_date||''),end:String(a.properties?.sl_end_date||''),
  notice:String(a.properties?.sl_notice_date||''),
  quantity:Number(a.properties?.sl_quantity||0),
  fee:Number(a.properties?.sl_monthly_fee||0),rights:String(a.properties?.sl_rights||'')
}));
export const isCurrent = (row,today=todayLondon()) => row.status==='active'&&row.start<=today&&row.end>=today;
export const isDue = (row,today=todayLondon()) => {
  const n=daysUntil(row.notice,today);
  return row.status==='active'&&n!==null&&n>=0&&n<=30;
};
