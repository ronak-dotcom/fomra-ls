// node --test backend/test
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseLeadGps, parseRoadWidthFt } = require('../src/lib/leadGps');
const { fillNext, retryAfterMinutes } = require('../src/lib/infraScoreFill');

test('reads every GPS format the app saves', () => {
  assert.deepEqual(parseLeadGps('LIVE|13.015317|79.954763|44.9|2026-11-16T05:24:46.067Z'),
    { lat: 13.015317, lon: 79.954763 });
  assert.deepEqual(parseLeadGps('12.889331° N, 80.042852° E'), { lat: 12.889331, lon: 80.042852 });
  assert.deepEqual(parseLeadGps('13.119083, 80.281389'), { lat: 13.119083, lon: 80.281389 });
  assert.deepEqual(parseLeadGps('13.119083 80.281389'), { lat: 13.119083, lon: 80.281389 });
  const dms = parseLeadGps('13°07\'08.7"N 80°16\'53.0"E');
  assert.ok(Math.abs(dms.lat - 13.119083) < 1e-5 && Math.abs(dms.lon - 80.281389) < 1e-5);
  assert.equal(parseLeadGps(''), null);
  assert.equal(parseLeadGps('near the temple'), null);
  assert.equal(parseLeadGps('200, 80'), null);
});

test('road width is the first number', () => {
  assert.equal(parseRoadWidthFt('40 ft'), 40);
  assert.equal(parseRoadWidthFt(''), null);
  assert.equal(parseRoadWidthFt('about 22.5 feet'), 22.5);
});

test('retry gaps grow and cap at a day', () => {
  assert.deepEqual([1, 2, 3, 4, 10].map(retryAfterMinutes), [15, 30, 60, 120, 1440]);
});

function fakeDb(jobs) {
  const calls = [];
  const db = async (path, opts = {}) => {
    calls.push({ path, ...opts });
    if (path === 'rpc/infra_score_claim') return jobs.length ? [jobs.shift()] : [];
    return null;
  };
  return { db, calls };
}

test('fills jobs, saves the score and clears the retry row', async () => {
  const { db, calls } = fakeDb([
    { lead_id: '132', radius_km: 2, gps: 'LIVE|13.015317|79.954763|44.9|x', road_width: '40 ft', failures: 0 },
  ]);
  const seen = [];
  const out = await fillNext({
    secret: 's', db,
    fetchInfrastructure: async (...a) => { seen.push(a); return { scores: { Education: 80 } }; },
  });
  assert.deepEqual(out, { filled: [{ leadId: '132', radiusKm: 2 }], failed: [], idle: true });
  assert.deepEqual(seen, [[13.015317, 79.954763, 2, 40]]);
  const save = calls.find((c) => c.path.startsWith('lead_infra_scores'));
  assert.equal(save.body.lat, 13.015317);
  assert.equal(save.body.payload.scores.Education, 80);
  assert.ok(calls.some((c) => c.method === 'DELETE' && c.path.includes('lead_id=eq.132')));
});

test('a busy map server records a retry and stops for this call', async () => {
  const { db, calls } = fakeDb([
    { lead_id: '7', radius_km: 5, gps: '12.9, 80.1', road_width: '', failures: 2 },
    { lead_id: '8', radius_km: 5, gps: '12.9, 80.1', road_width: '', failures: 0 },
  ]);
  const t0 = Date.parse('2026-11-19T06:00:00Z');
  const out = await fillNext({
    secret: 's', db, now: () => t0,
    fetchInfrastructure: async () => { throw new Error('Map data servers are busy'); },
  });
  assert.equal(out.filled.length, 0);
  assert.equal(out.failed.length, 1);
  const retry = calls.find((c) => c.path.startsWith('lead_infra_score_attempts?on_conflict'));
  assert.equal(retry.body.failures, 3);
  assert.equal(retry.body.next_try_at, new Date(t0 + 60 * 60000).toISOString());
  assert.equal(calls.filter((c) => c.path === 'rpc/infra_score_claim').length, 1);
});

test('unreadable GPS is parked for a week and the next lead is tried', async () => {
  const { db, calls } = fakeDb([
    { lead_id: '9', radius_km: 2, gps: 'opp. bus stand', road_width: '', failures: 0 },
  ]);
  const t0 = Date.parse('2026-11-19T06:00:00Z');
  const out = await fillNext({ secret: 's', db, now: () => t0, fetchInfrastructure: async () => assert.fail() });
  assert.equal(out.failed[0].error, 'GPS not readable');
  assert.equal(out.idle, true);
  const retry = calls.find((c) => c.path.startsWith('lead_infra_score_attempts?on_conflict'));
  assert.equal(retry.body.next_try_at, new Date(t0 + 7 * 24 * 60 * 60000).toISOString());
});

test('no secret is refused before touching the database', async () => {
  const { db, calls } = fakeDb([]);
  await assert.rejects(fillNext({ secret: '', db, fetchInfrastructure: async () => ({}) }), /not allowed/);
  assert.equal(calls.length, 0);
});
