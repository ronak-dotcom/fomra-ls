// Background fill of saved infrastructure scores (lead_infra_scores).
//
// The database scheduler (pg_cron + pg_net) calls POST /api/poi/fill-next
// every couple of minutes with a shared secret kept in Supabase Vault. Each
// call claims the next lead + radius that has no score (or an old one) via
// infra_score_claim(), which also checks the secret and leases the job so two
// calls never fetch the same lead. Leads are taken open ones first, 2 km
// (what the app opens on) before 5 and 10 km. A failed fetch is retried later
// with growing gaps, so busy map servers only delay a score.

const { parseLeadGps, parseRoadWidthFt } = require('./leadGps');

// Start another job only while there is time left for a slow one; the
// function may run 60 s and one map query can take up to ~45 s.
const START_BUDGET_MS = 12000;

/** Minutes before retrying after [failures] failed fetches in a row. */
function retryAfterMinutes(failures) {
  return Math.min(15 * 2 ** Math.max(0, failures - 1), 24 * 60);
}

const UNREADABLE_GPS_RETRY_MIN = 7 * 24 * 60;

function supabase() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    const err = new Error('missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY');
    err.status = 500;
    throw err;
  }
  return async (path, { method = 'GET', body, prefer } = {}) => {
    const r = await fetch(`${url}/rest/v1/${path}`, {
      method,
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
        ...(prefer ? { Prefer: prefer } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await r.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch (_) { /* not JSON */ }
    if (!r.ok) {
      const err = new Error(`${method} ${path.split('?')[0]}: HTTP ${r.status} ${json?.message || text}`.trim());
      err.status = r.status === 401 || r.status === 403 ? 401 : 502;
      throw err;
    }
    return json;
  };
}

/**
 * Runs jobs until the time budget is used. [fetchInfrastructure] is
 * (lat, lon, radiusKm, roadWidthFt) => payload with a non-empty `scores`.
 * Returns what was done, e.g. { filled: [...], failed: [...], idle: false }.
 */
async function fillNext({ secret, fetchInfrastructure, db = supabase(), now = () => Date.now() }) {
  if (!secret) {
    const err = new Error('not allowed');
    err.status = 401;
    throw err;
  }
  const started = now();
  const filled = [];
  const failed = [];
  let idle = false;

  while (now() - started < START_BUDGET_MS) {
    const jobs = await db('rpc/infra_score_claim', {
      method: 'POST',
      body: { p_secret: secret, p_limit: 1 },
    });
    const job = Array.isArray(jobs) ? jobs[0] : null;
    if (!job) {
      idle = true;
      break;
    }
    const id = { leadId: job.lead_id, radiusKm: job.radius_km };
    const where = `lead_id=eq.${encodeURIComponent(job.lead_id)}&radius_km=eq.${job.radius_km}`;

    const reportFailure = async (message, retryMin) => {
      const at = new Date(now());
      await db('lead_infra_score_attempts?on_conflict=lead_id,radius_km', {
        method: 'POST',
        prefer: 'resolution=merge-duplicates,return=minimal',
        body: {
          lead_id: job.lead_id,
          radius_km: job.radius_km,
          failures: (job.failures || 0) + 1,
          last_error: String(message).slice(0, 500),
          last_attempt_at: at.toISOString(),
          next_try_at: new Date(at.getTime() + retryMin * 60000).toISOString(),
        },
      });
      failed.push({ ...id, error: String(message).slice(0, 200) });
    };

    const pin = parseLeadGps(job.gps);
    if (!pin) {
      await reportFailure('GPS not readable', UNREADABLE_GPS_RETRY_MIN);
      continue;
    }

    let payload;
    try {
      payload = await fetchInfrastructure(
        pin.lat, pin.lon, job.radius_km, parseRoadWidthFt(job.road_width) ?? undefined);
      if (!payload?.scores || Object.keys(payload.scores).length === 0) {
        throw new Error('no scores in the answer');
      }
    } catch (e) {
      await reportFailure(e.message || e, retryAfterMinutes((job.failures || 0) + 1));
      // The map servers are busy; leave the rest for the next call.
      break;
    }

    await db('lead_infra_scores?on_conflict=lead_id,radius_km', {
      method: 'POST',
      prefer: 'resolution=merge-duplicates,return=minimal',
      body: {
        lead_id: job.lead_id,
        radius_km: job.radius_km,
        lat: pin.lat,
        lon: pin.lon,
        payload,
        fetched_at: new Date(now()).toISOString(),
      },
    });
    await db(`lead_infra_score_attempts?${where}`, {
      method: 'DELETE',
      prefer: 'return=minimal',
    });
    filled.push(id);
  }

  return { filled, failed, idle };
}

module.exports = { fillNext, retryAfterMinutes, START_BUDGET_MS };
