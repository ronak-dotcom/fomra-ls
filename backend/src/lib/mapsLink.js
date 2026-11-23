// Reads the pin from a Google Maps link. Short links (maps.app.goo.gl) are
// followed one redirect at a time, only ever to Google hosts, so the server
// can't be pointed anywhere else.

const ALLOWED_HOSTS = new Set([
  'maps.app.goo.gl',
  'goo.gl',
  'g.co',
  'maps.google.com',
  'www.google.com',
  'google.com',
  'www.google.co.in',
  'google.co.in',
  'maps.google.co.in',
]);

function isAllowed(url) {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && ALLOWED_HOSTS.has(u.hostname.toLowerCase());
  } catch (_) {
    return false;
  }
}

const valid = (lat, lng) =>
  Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

/** { lat, lng } from a full Google Maps URL, or null. */
function pinFromUrl(url) {
  const s = decodeURIComponent(String(url || ''));
  // The place itself (!3d<lat>!4d<lng>) beats the map's centre (@lat,lng).
  const patterns = [
    /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/,
    /[?&](?:q|query|ll|destination|center)=(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)/,
    /\/(?:place|search|dir)\/(-?\d+(?:\.\d+)?)\s*,\s*\+?(-?\d+(?:\.\d+)?)/,
    /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/,
  ];
  for (const re of patterns) {
    const m = re.exec(s);
    if (m) {
      const lat = Number(m[1]);
      const lng = Number(m[2]);
      if (valid(lat, lng)) return { lat, lng };
    }
  }
  return null;
}

/** Follows a short link to the full URL and reads the pin. */
async function resolveMapsLink(url, { fetchImpl = fetch, maxHops = 6 } = {}) {
  let current = String(url || '').trim();
  if (!isAllowed(current)) {
    const err = new Error('Only Google Maps links can be read.');
    err.status = 400;
    throw err;
  }
  for (let hop = 0; hop <= maxHops; hop++) {
    const pin = pinFromUrl(current);
    if (pin) return { ...pin, url: current };
    if (hop === maxHops) break;
    const r = await fetchImpl(current, {
      method: 'GET',
      redirect: 'manual',
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; FomraLandIQ/1.0)' },
    });
    const next = r.headers.get('location');
    if (!next) break;
    const absolute = new URL(next, current).toString();
    if (!isAllowed(absolute)) break;
    current = absolute;
  }
  return null;
}

module.exports = { pinFromUrl, resolveMapsLink, isAllowed };
