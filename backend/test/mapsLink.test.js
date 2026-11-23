const test = require('node:test');
const assert = require('node:assert');
const { pinFromUrl, resolveMapsLink, isAllowed } = require('../src/lib/mapsLink');

test('reads the place pin before the map centre', () => {
  const url = 'https://www.google.com/maps/place/Mark+Avenue/@12.91,80.03,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d12.9142547!4d80.0324985';
  assert.deepStrictEqual(pinFromUrl(url), { lat: 12.9142547, lng: 80.0324985 });
});

test('reads q= and @ forms', () => {
  assert.deepStrictEqual(pinFromUrl('https://maps.google.com/?q=12.86,79.98'), { lat: 12.86, lng: 79.98 });
  assert.deepStrictEqual(pinFromUrl('https://www.google.com/maps/@12.5,80.1,15z'), { lat: 12.5, lng: 80.1 });
  assert.strictEqual(pinFromUrl('https://maps.app.goo.gl/abc'), null);
});

test('only Google hosts are allowed', () => {
  assert.ok(isAllowed('https://maps.app.goo.gl/Yg7d68zrWJemKMRRA'));
  assert.ok(!isAllowed('https://evil.example.com/maps'));
  assert.ok(!isAllowed('http://maps.app.goo.gl/x'));
});

test('follows a short link to the full URL', async () => {
  const hops = {
    'https://maps.app.goo.gl/abc': 'https://www.google.com/maps/place/X/data=!3d12.1!4d80.2',
  };
  const fetchImpl = async (u) => ({ headers: { get: (h) => (h === 'location' ? hops[u] : null) } });
  const pin = await resolveMapsLink('https://maps.app.goo.gl/abc', { fetchImpl });
  assert.strictEqual(pin.lat, 12.1);
  assert.strictEqual(pin.lng, 80.2);
});

test('stops when a redirect leaves Google', async () => {
  const fetchImpl = async () => ({ headers: { get: () => 'https://evil.example.com/?q=1,2' } });
  assert.strictEqual(await resolveMapsLink('https://maps.app.goo.gl/abc', { fetchImpl }), null);
  await assert.rejects(resolveMapsLink('https://evil.example.com/x', { fetchImpl }));
});
