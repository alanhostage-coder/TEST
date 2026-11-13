// Website-to-brand generator for Corpus. Runs during deployment only.
import fs from 'node:fs/promises';
const DEFAULT_URL = 'https://www.prosperohub.com';
const OUTPUT = new URL('../src/app/cards/', import.meta.url);
function escapeXml(v) {
  return String(v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
}
function brandUrl(raw) {
  const input = String(raw || DEFAULT_URL).trim();
  const url = new URL(/^https?:\/\//i.test(input) ? input : 'https://' + input);
  const host = url.hostname.toLowerCase();
  if (url.protocol !== 'https:' || url.username || url.password || (url.port && url.port !== '443') ||
    !host.includes('.') || /[^a-z0-9.-]/.test(host) || /^\d+\.\d+\.\d+\.\d+$/.test(host) ||
    /\.(?:local|localhost|internal|test|invalid|example)$/.test(host) || host === 'localhost') {
    throw Error('Enter a public HTTPS website, without credentials or non-standard ports.');
  }
  url.hash = '';
  return url;
}
function valueOf(tag, attr) {
  const pattern = new RegExp('\\b' + attr + '\\s*=\\s*(?:"([^"]*)"|\\x27([^\\x27]*)\\x27|([^\\s>]+))', 'i');
  const match = pattern.exec(tag);
  return match ? (match[1] || match[2] || match[3] || '') : '';
}
function meta(html, key) {
  for (const tag of html.match(/<meta\b[^>]*>/gi) || []) {
    if ([valueOf(tag,'name'),valueOf(tag,'property')].some(s => s.toLowerCase() === key))
      return valueOf(tag,'content');
  }
  return '';
}
function hexColour(raw) {
  let c = String(raw || '').trim();
  if (!/^#[0-9a-f]{3}(?:[0-9a-f]{3})?$/i.test(c)) c = '#DAEAFF';
  if (c.length === 4) c = '#' + c.slice(1).split('').map(x => x+x).join('');
  return c.toUpperCase();
}
function readableInk(hex) {
  const a = [1,3,5].map(i => parseInt(hex.slice(i,i+2),16)/255).map(x => x<=0.04045 ? x/12.92 : ((x+0.055)/1.055)**2.4);
  return a[0]*0.2126 + a[1]*0.7152 + a[2]*0.0722 > 0.32 ? '#010103' : '#FFFFFF';
}
async function fetchBounded(url, maximum, accept) {
  const res = await fetch(url,{redirect:'error',signal:AbortSignal.timeout(6500),headers:{Accept:accept}});
  if (!res.ok) throw Error('Website response ' + res.status);
  const size = Number(res.headers.get('content-length') || 0);
  if (size > maximum) throw Error('Brand metadata too large');
  const data = new Uint8Array(await res.arrayBuffer());
  if (data.byteLength > maximum) throw Error('Brand metadata too large');
  return {data, type: (res.headers.get('content-type') || '').split(';')[0].trim().toLowerCase()};
}
async function siteIcon(html,site) {
  const tags = html.match(/<link\b[^>]*>/gi) || [];
  const tag = tags.find(x => /apple-touch-icon/i.test(valueOf(x,'rel')) && valueOf(x,'href')) ||
    tags.find(x => /\bicon\b/i.test(valueOf(x,'rel')) && /\.png(?:[?#]|$)/i.test(valueOf(x,'href')));
  if (!tag) return '';
  const uri = new URL(valueOf(tag,'href'),site);
  if (uri.protocol !== 'https:' || uri.hostname !== site.hostname || (uri.port && uri.port !== '443')) return '';
  try {
    const result = await fetchBounded(uri.href,100000,'image/png,image/jpeg,image/webp');
    if (!['image/png','image/jpeg','image/webp'].includes(result.type)) return '';
    return 'data:' + result.type + ';base64,' + Buffer.from(result.data).toString('base64');
  } catch { return ''; }
}
async function main() {
  const site = brandUrl(process.env.CORPUS_BRAND_URL || process.argv[2]);
  let html = '', logo = '', detected = false;
  try {
    const page = await fetchBounded(site.href,400000,'text/html');
    if (page.type !== 'text/html') throw Error('Not an HTML site');
    html = new TextDecoder().decode(page.data);
    detected = true;
    logo = await siteIcon(html,site);
  } catch (error) {
    console.warn('Website branding unavailable, using safe defaults:', error.message);
  }
  const domainKey = site.hostname.replace(/^www\./,'').split('.')[0];
  const domainName = domainKey.toLowerCase() === 'prosperohub' ? 'ProsperoHub' :
    domainKey.slice(0,1).toUpperCase() + domainKey.slice(1);
  const fromTitle = ((/<title[^>]*>([^<]+)/i.exec(html) || [,''])[1]).split(/[|–—-]/)[0];
  const siteName = meta(html,'og:site_name').replace(/,\s+(?:a|an|the)\s+.+$/i,'').trim();
  const name = String(process.env.CORPUS_BRAND_NAME || siteName ||
    fromTitle || domainName || 'ProsperoHub').replace(/[\u0000-\u001f<>]/g,'').trim().slice(0,32);
  const inlineColor = (/--(?:brand|primary)(?:-[\w]+)?\s*:\s*(#[0-9a-f]{3}(?:[0-9a-f]{3})?)\b/i.exec(html) || [,''])[1];
  const accent = hexColour(process.env.CORPUS_BRAND_ACCENT || meta(html,'theme-color') || inlineColor);
  const ink = readableInk(accent);
  const initials = (name.match(/\b[A-Za-z0-9]/g) || ['C']).slice(0,2).join('').toUpperCase();
  const logoArt = logo ?
    '<image href="' + logo + '" x="56" y="48" width="68" height="68" preserveAspectRatio="xMidYMid meet"/>' :
    '<text x="90" y="96" font-family="Arial,Helvetica,sans-serif" font-size="36" font-weight="700" text-anchor="middle" fill="' + ink + '">' + escapeXml(initials) + '</text>';
  const graphic = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="164" viewBox="0 0 1120 164">',
    '<rect width="1120" height="164" rx="16" fill="#010103"/>',
    '<rect width="10" height="164" fill="' + accent + '"/>',
    '<rect x="40" y="30" width="100" height="100" rx="14" fill="' + accent + '"/>',
    logoArt,
    '<text x="162" y="61" font-family="Arial,Helvetica,sans-serif" font-size="23" font-weight="600" fill="#DAEAFF">' + escapeXml(name.toUpperCase()) + '</text>',
    '<text x="162" y="111" font-family="Arial,Helvetica,sans-serif" font-size="47" font-weight="700" fill="#FFFFFF">Corpus Note</text>',
    '<rect x="852" y="32" width="234" height="54" rx="11" fill="#FEF5AC"/>',
    '<text x="969" y="66" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-size="23" font-weight="700" fill="#010103">INTERNAL ONLY</text>',
    '<text x="852" y="119" font-family="Arial,Helvetica,sans-serif" font-size="17" fill="#CFD3DC">Not added to invitations</text>',
    '</svg>'
  ].join('\n');
  const config = '// Generated at build time from public website metadata.\n' +
    'export const CORPUS_BRAND = Object.freeze(' + JSON.stringify({name,websiteUrl:site.href,accentHex:accent,metadataDetected:detected},null,2) + ');\n';
  await fs.mkdir(new URL('assets/',OUTPUT),{recursive:true});
  await fs.writeFile(new URL('assets/brand-banner.svg',OUTPUT),graphic);
  await fs.writeFile(new URL('brand-config.js',OUTPUT),config);
  console.log('Corpus brand:',name,site.hostname,'accent:',accent,'website data:',detected,'favicon:',Boolean(logo));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
