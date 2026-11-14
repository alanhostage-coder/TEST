// Website-to-brand generator for Corpus. Runs during deployment only.
import fs from 'node:fs/promises';
const DEFAULT_URL = 'https://siloy.com/brand';
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
// Read the head of a large public brand page without rejecting it because its
// full Content-Length exceeds our former 400 KB limit.
async function fetchHtmlHead(url, maximum = 2000000) {
  const res = await fetch(url, {
    redirect: 'error',
    signal: AbortSignal.timeout(12000),
    headers: { Accept: 'text/html' }
  });
  if (!res.ok) throw Error('Website response ' + res.status);
  const type = (res.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  if (type !== 'text/html') throw Error('Brand URL did not return HTML');
  if (!res.body) throw Error('No website body');
  const reader = res.body.getReader();
  const chunks = [];
  let count = 0;
  try {
    while (count < maximum) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = value.slice(0, maximum - count);
      chunks.push(chunk);
      count += chunk.byteLength;
      if (chunk.byteLength < value.byteLength) break;
    }
  } finally {
    try { await reader.cancel(); } catch {}
  }
  const data = new Uint8Array(count);
  let offset = 0;
  for (const c of chunks) { data.set(c, offset); offset += c.byteLength; }
  return new TextDecoder().decode(data);
}
function allowedPublicLogoHost(host, brandHost) {
  const a = host.toLowerCase().replace(/^www\./,'');
  const b = brandHost.toLowerCase().replace(/^www\./,'');
  return a === b || /(?:^|\.)(?:hubspot\.net|hs-cdn\.com|hubspotusercontent\d*\.net)$/.test(a);
}
async function siteIcon(html,site) {
  const links = html.match(/<link\b[^>]*>/gi) || [];
  const images = html.match(/<img\b[^>]*>/gi) || [];
  // Do not treat Siloy-themed photography or customers' logos as the Siloy brand mark.
  // Require an explicit brand identity label, then fall back to the site's icon.
  const imagesWithIdentity = images.filter(tag => {
    const alt = valueOf(tag,'alt').trim();
    return /^siloy(?:\s+(?:logo|wordmark|brandmark))?$/i.test(alt) ||
      /^siloy\s+(?:logo|wordmark|brandmark)\b/i.test(alt);
  });
  const candidates = [
    ...imagesWithIdentity.map(tag=>valueOf(tag,'src')),
    ...links.filter(tag=>/apple-touch-icon|\bicon\b/i.test(valueOf(tag,'rel'))).map(tag=>valueOf(tag,'href'))
  ].filter(Boolean);
  const audit = candidates.slice(0, 12).map(path=>{
    try {
      const u = new URL(path,site);
      return u.protocol === 'https:' ? u.origin + u.pathname.slice(0,90) : '(non-HTTPS)';
    } catch { return '(invalid URL)'; }
  });
  console.log('Public Siloy brand logo candidates:',JSON.stringify(audit));
  for (const path of candidates.slice(0, 16)) {
    let src;
    try { src = new URL(path,site); }
    catch { continue; }
    if (src.protocol !== 'https:' || !allowedPublicLogoHost(src.hostname,site.hostname) ||
      (src.port && src.port !== '443')) continue;
    try {
      const result = await fetchBounded(src.href,160000,'image/png,image/jpeg,image/webp,image/svg+xml');
      const raster = ['image/png','image/jpeg','image/webp'].includes(result.type);
      const officialVector = result.type === 'image/svg+xml' &&
        src.hostname.replace(/^www\./,'') === site.hostname.replace(/^www\./,'') &&
        /(?:favicon|siloy[-_]?logo|siloy[-_]?mark|wordmark)\.svg(?:$|[?#])/i.test(src.href);
      if (!raster && !officialVector) continue;
      return {
        src:src.href,
        // Never inline remote SVG into generated markup.
        embedded:raster ? 'data:' + result.type + ';base64,' + Buffer.from(result.data).toString('base64') : ''
      };
    } catch {}
  }
  return null;
}
async function siteLogoOverride(raw, site) {
  if (!raw) return '';
  const uri = brandUrl(new URL(raw, site).href);
  if (uri.hostname !== site.hostname) {
    throw Error('For safety, the custom logo URL must be hosted on the same domain as the brand website.');
  }
  const image = await fetchBounded(uri.href, 160000, 'image/png,image/jpeg,image/webp');
  if (!['image/png','image/jpeg','image/webp'].includes(image.type)) {
    throw Error('Custom logo must be a public PNG, JPEG or WebP file.');
  }
  return 'data:' + image.type + ';base64,' + Buffer.from(image.data).toString('base64');
}
async function main() {
  const site = brandUrl(process.env.CORPUS_BRAND_URL || process.argv[2]);
  let html = '', logo = '', logoUrl = '', detected = false;
  try {
    html = await fetchHtmlHead(site.href);
    detected = true;
    let candidate = await siteIcon(html,site);
    if (!candidate && /(^|\.)siloy\.com$/i.test(site.hostname)) {
      try {
        const homeHtml = await fetchHtmlHead(new URL('/',site).href);
        candidate = await siteIcon(homeHtml,new URL('/',site));
      } catch (error) {
        console.warn('Siloy home logo lookup unavailable:',error.message);
      }
    }
    if (candidate) { logo = candidate.embedded; logoUrl = candidate.src; }
  } catch (error) {
    console.warn('Website branding unavailable, using safe defaults:', error.message);
  }
  const domainKey = site.hostname.replace(/^www\./,'').split('.')[0];
  const domainName = domainKey.toLowerCase() === 'prosperohub' ? 'ProsperoHub' :
    domainKey.slice(0,1).toUpperCase() + domainKey.slice(1);
  const fromTitle = ((/<title[^>]*>([^<]+)/i.exec(html) || [,''])[1]).split(/[|–—-]/)[0];
  const siteName = meta(html,'og:site_name').replace(/,\s+(?:a|an|the)\s+.+$/i,'').trim();
  const siloy = /(^|\.)siloy\.com$/i.test(site.hostname);
  const name = String(process.env.CORPUS_BRAND_NAME || (siloy ? 'Siloy UKI' : '') ||
    siteName || fromTitle || domainName || 'Siloy UKI')
    .replace(/[\u0000-\u001f<>]/g,'').trim().slice(0,32);
  if (process.env.CORPUS_BRAND_LOGO_URL) {
    try {
      logo = await siteLogoOverride(process.env.CORPUS_BRAND_LOGO_URL, site);
      logoUrl = new URL(process.env.CORPUS_BRAND_LOGO_URL, site).href;
    }
    catch (error) { throw Error('Invalid configured logo: ' + error.message); }
  }
  const inlineColor = (/--(?:brand|primary)(?:-[\w]+)?\s*:\s*(#[0-9a-f]{3}(?:[0-9a-f]{3})?)\b/i.exec(html) || [,''])[1];
  const accent = hexColour(process.env.CORPUS_BRAND_ACCENT ||
    (siloy ? '#DAEAFF' : '') || meta(html,'theme-color') || inlineColor);
  const background = hexColour(process.env.CORPUS_BRAND_BACKGROUND || '#010103');
  const highlight = hexColour(process.env.CORPUS_BRAND_HIGHLIGHT || '#FEF5AC');
  const ink = readableInk(accent);
  const headlineInk = readableInk(background);
  const badgeInk = readableInk(highlight);
  const initials = (name.match(/\b[A-Za-z0-9]/g) || ['C']).slice(0,2).join('').toUpperCase();
  const logoArt = logo ?
    '<image href="' + logo + '" x="56" y="48" width="68" height="68" preserveAspectRatio="xMidYMid meet"/>' :
    '<text x="90" y="96" font-family="Arial,Helvetica,sans-serif" font-size="36" font-weight="700" text-anchor="middle" fill="' + ink + '">' + escapeXml(initials) + '</text>';
  const graphic = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="188" viewBox="0 0 1120 188">',
    '<rect width="1120" height="188" rx="18" fill="' + background + '"/>',
    '<rect x="0" y="0" width="12" height="188" fill="' + accent + '"/>',
    '<rect x="43" y="44" width="102" height="102" rx="16" fill="' + accent + '"/>',
    logoArt,
    '<rect x="169" y="31" width="120" height="5" rx="2.5" fill="' + accent + '"/>',
    '<text x="168" y="70" font-family="Arial,Helvetica,sans-serif" font-size="24" font-weight="500" fill="' + accent + '">' + escapeXml(name) + '</text>',
    '<text x="168" y="122" font-family="Arial,Helvetica,sans-serif" font-size="48" font-weight="700" letter-spacing="0.8" fill="' + headlineInk + '">Siloy Time</text>',
    '<text x="169" y="154" font-family="Arial,Helvetica,sans-serif" font-size="20" fill="' + headlineInk + '">Internal workspace</text>',
    '<rect x="828" y="44" width="258" height="61" rx="12" fill="' + highlight + '"/>',
    '<text x="957" y="81" text-anchor="middle" font-family="Arial,Helvetica,sans-serif" font-size="24" font-weight="700" fill="' + badgeInk + '">INTERNAL ONLY</text>',
    '<text x="828" y="140" font-family="Arial,Helvetica,sans-serif" font-size="18" fill="' + headlineInk + '">Time you can account for</text>',
    '</svg>'
  ].join('\n');
  const config = '// Generated at build time from public website metadata.\n' +
    'export const CORPUS_BRAND = Object.freeze(' + JSON.stringify({name,websiteUrl:site.href,accentHex:accent,backgroundHex:background,highlightHex:highlight,logoUrl,metadataDetected:detected},null,2) + ');\n';
  await fs.mkdir(new URL('assets/',OUTPUT),{recursive:true});
  // HubSpot UI Extensions bundle SVG imports without an image URL in production.
  // Export a valid data URI from a JavaScript module instead of importing an .svg asset.
  const imageSource = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(graphic);
  const imageModule = '// Generated by configure-corpus-brand.mjs during deployment.\n' +
    'export const CORPUS_BANNER_DATA_URI = ' + JSON.stringify(imageSource) + ';\n';
  await fs.writeFile(new URL('assets/brand-banner.svg',OUTPUT),graphic);
  await fs.writeFile(new URL('brand-banner.js',OUTPUT),imageModule);
  await fs.writeFile(new URL('brand-config.js',OUTPUT),config);
  console.log('Corpus brand:',name,site.hostname,'accent:',accent,'background:',background,'highlight:',highlight,'website data:',detected,'logo:',Boolean(logo),'logo URL present:',Boolean(logoUrl));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
