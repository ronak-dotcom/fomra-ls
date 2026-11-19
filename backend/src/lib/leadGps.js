// Reads a lead's saved GPS text the same way the app does
// (lib/utils/lead_location_parser.dart parseLeadGps), so a score filled on
// the server is found by the app for the same pin.
//
// Formats:
//   LIVE|<lat>|<lng>|<accuracy>|<iso8601>
//   13°07'08.7"N 80°16'53.0"E          (DMS)
//   13.119083° N, 80.281389° E         (decimal with labels)
//   13.119083, 80.281389               (plain)

function num(s) {
  if (s == null) return null;
  const t = String(s).trim();
  if (!t) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

const valid = (lat, lng) => lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

function parseLive(t) {
  if (!t.startsWith('LIVE|')) return null;
  const parts = t.split('|');
  if (parts.length < 5) return null;
  const lat = num(parts[1]);
  const lng = num(parts[2]);
  return lat != null && lng != null ? { lat, lon: lng } : null;
}

const DMS = new RegExp(
  '(\\d+(?:\\.\\d+)?)\\s*°\\s*'
  + "(\\d+(?:\\.\\d+)?)?\\s*'?\\s*"
  + '(\\d+(?:\\.\\d+)?)?\\s*"?\\s*'
  + '([NS])\\D*'
  + '(\\d+(?:\\.\\d+)?)\\s*°\\s*'
  + "(\\d+(?:\\.\\d+)?)?\\s*'?\\s*"
  + '(\\d+(?:\\.\\d+)?)?\\s*"?\\s*'
  + '([EW])',
  'i',
);

function dmsToDecimal(d, m, s, hemisphere) {
  let v = d + m / 60 + s / 3600;
  const h = hemisphere.toUpperCase();
  if (h === 'S' || h === 'W') v = -v;
  return v;
}

function parseDms(input) {
  if (!input.includes('°')) return null;
  const normalized = input
    .replace(/′/g, "'")
    .replace(/’/g, "'")
    .replace(/″/g, '"')
    .replace(/“/g, '"')
    .replace(/”/g, '"')
    .trim();
  const m = DMS.exec(normalized);
  if (!m) return null;
  const lat = dmsToDecimal(Number(m[1]), num(m[2]) ?? 0, num(m[3]) ?? 0, m[4]);
  const lng = dmsToDecimal(Number(m[5]), num(m[6]) ?? 0, num(m[7]) ?? 0, m[8]);
  return valid(lat, lng) ? { lat, lon: lng } : null;
}

const LABELED = /(-?\d+(?:\.\d+)?)\s*°?\s*([NS]).*?(-?\d+(?:\.\d+)?)\s*°?\s*([EW])/i;

function parseLabeledDecimal(input) {
  if (input.includes("'") || input.includes('"')) return null;
  const m = LABELED.exec(input);
  if (!m) return null;
  const lat = num(m[1]);
  const lng = num(m[3]);
  if (lat == null || lng == null) return null;
  // Same as the app: the values are taken as written (absolute).
  const a = Math.abs(lat);
  const b = Math.abs(lng);
  return valid(a, b) ? { lat: a, lon: b } : null;
}

function parsePair(a, b) {
  const lat = num(String(a).replace(/[^\d.\-]/g, ''));
  const lng = num(String(b).replace(/[^\d.\-]/g, ''));
  return lat != null && lng != null && valid(lat, lng) ? { lat, lon: lng } : null;
}

/** { lat, lon } or null when the text can't be read. */
function parseLeadGps(raw) {
  const t = String(raw ?? '').trim();
  if (!t) return null;
  const live = parseLive(t);
  if (live) return live;
  const dms = parseDms(t);
  if (dms) return dms;
  const labeled = parseLabeledDecimal(t);
  if (labeled) return labeled;
  const comma = t.split(',');
  if (comma.length >= 2) {
    const p = parsePair(comma[0], comma[1]);
    if (p) return p;
  }
  const space = t.split(/\s+/);
  if (space.length >= 2) {
    const p = parsePair(space[0], space[1]);
    if (p) return p;
  }
  return null;
}

/** First number in the road width text ("40 ft" → 40), or null. */
function parseRoadWidthFt(raw) {
  const m = /([\d.]+)/.exec(String(raw ?? '').trim());
  return m ? num(m[1]) : null;
}

module.exports = { parseLeadGps, parseRoadWidthFt };
