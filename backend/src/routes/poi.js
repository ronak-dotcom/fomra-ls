const express = require('express');
const https   = require('https');
const router  = express.Router();
const {
  buildInfrastructureQuery,
  parseInfrastructureElements,
  computeInfrastructureScores,
} = require('../lib/overpassInfrastructure');

// Public Overpass servers, tried together; the first good answer wins.
// (overpass.kumi.systems and overpass.openstreetmap.ru stopped answering
// reliably, which is what broke the infrastructure score.)
const MIRRORS = [
  { hostname: 'overpass-api.de',         path: '/api/interpreter' },
  { hostname: 'overpass.private.coffee', path: '/api/interpreter' },
  { hostname: 'maps.mail.ru',            path: '/osm/tools/overpass/api/interpreter' },
  { hostname: 'overpass.kumi.systems',   path: '/api/interpreter' },
];

/** Short-lived cache — repeated taps / refreshes return instantly. */
const infraCache = new Map();
const CACHE_TTL_MS = 12 * 60 * 1000;

function infraCacheKey(lat, lon, radiusKm) {
  return `${lat.toFixed(4)},${lon.toFixed(4)},${radiusKm}`;
}

function getCachedInfrastructure(lat, lon, radiusKm) {
  const key = infraCacheKey(lat, lon, radiusKm);
  const hit = infraCache.get(key);
  if (!hit) return null;
  if (Date.now() - hit.at > CACHE_TTL_MS) {
    infraCache.delete(key);
    return null;
  }
  return hit.payload;
}

function setCachedInfrastructure(lat, lon, radiusKm, payload) {
  infraCache.set(infraCacheKey(lat, lon, radiusKm), { at: Date.now(), payload });
}

function queryMirror(mirror, body) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: mirror.hostname,
      path:     mirror.path,
      method:   'POST',
      headers:  {
        'Content-Type':   'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
        'User-Agent':     'FomraLS/1.0 (fomra.digital26@gmail.com)',
        'Accept':         'application/json',
      },
      timeout: 45000,
    };

    const req = https.request(options, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf8');
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode} from ${mirror.hostname}`));
        }
        try {
          resolve(JSON.parse(raw));
        } catch (_) {
          reject(new Error(`Invalid JSON from ${mirror.hostname}`));
        }
      });
      res.on('error', reject);
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error(`Timeout from ${mirror.hostname}`));
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// POST /api/poi
// Body: { query: string }  — raw Overpass QL query string
router.post('/', async (req, res) => {
  const { query } = req.body;
  if (!query || typeof query !== 'string') {
    return res.status(400).json({ error: 'query field is required' });
  }

  const body = `data=${encodeURIComponent(query)}`;
  let lastErr = 'All Overpass mirrors failed';

  for (const mirror of MIRRORS) {
    try {
      const data = await queryMirror(mirror, body);
      return res.json(data);
    } catch (err) {
      lastErr = err.message;
      // try next mirror
    }
  }

  res.status(502).json({ error: lastErr });
});

async function runOverpassQuery(query) {
  const body = `data=${encodeURIComponent(query)}`;
  const attempts = MIRRORS.map((mirror) => queryMirror(mirror, body));

  try {
    return await Promise.any(attempts);
  } catch (agg) {
    // Say why each server failed, so the error a user reports is useful.
    const reasons = (agg.errors || []).map((e) => e.message).join('; ');
    const err = new Error(
      `Map data servers are busy — try again in a minute (${reasons || 'no answer'})`);
    err.status = 502;
    throw err;
  }
}

// POST /api/poi/infrastructure
// Body: { lat, lon, radiusKm } — Overpass POI + highway scoring
router.post('/infrastructure', async (req, res) => {
  const lat = parseFloat(req.body?.lat);
  const lon = parseFloat(req.body?.lon);
  const radiusKm = parseInt(req.body?.radiusKm, 10) || 2;
  const roadWidthFt = parseFloat(req.body?.roadWidthFt);

  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return res.status(400).json({ error: 'lat and lon are required' });
  }
  if (![2, 5, 10].includes(radiusKm)) {
    return res.status(400).json({ error: 'radiusKm must be 2, 5, or 10' });
  }

  try {
    const cached = getCachedInfrastructure(lat, lon, radiusKm);
    if (cached) {
      return res.json({ ...cached, cached: true });
    }

    const radiusMeters = radiusKm * 1000;
    const query = buildInfrastructureQuery(lat, lon, radiusMeters);
    const data = await runOverpassQuery(query);
    const elements = data.elements || [];

    if (data.remark && elements.length === 0) {
      return res.status(502).json({ error: String(data.remark) });
    }

    const { counts, places, roadCounts, roadNearest } = parseInfrastructureElements(elements, lat, lon);
    const scores = computeInfrastructureScores(
      counts,
      places,
      roadCounts,
      roadNearest,
      radiusKm,
      Number.isFinite(roadWidthFt) ? roadWidthFt : undefined,
    );

    const payload = {
      source:    'OpenStreetMap Overpass API',
      lat,
      lon,
      radiusKm,
      counts,
      places,
      roadCounts,
      scores,
    };

    setCachedInfrastructure(lat, lon, radiusKm, payload);
    return res.json(payload);
  } catch (err) {
    return res.status(err.status || 502).json({ error: err.message });
  }
});

module.exports = router;
