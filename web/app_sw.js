// Fomra LandIQ app-shell service worker: lets the app open with no signal.
//
// Online it always prefers the network, so every deploy shows up at once
// (the reason Flutter's own worker is disabled in index.html). Each fresh
// copy is saved, and when the network fails or takes too long — no signal,
// or one weak bar in the field — the saved copy is served instead.
//
// Only the app's own files and Flutter's engine (CanvasKit / Firebase JS on
// gstatic) are handled. Data requests (Supabase, maps, APIs) pass straight
// through: offline data lives in the app's own outbox, not here.

const CACHE = 'fomra-app-shell-v1';
const NETWORK_TIMEOUT_MS = 6000;

// Saved as soon as the worker installs, so even the very first visit leaves
// enough behind to open offline next time. (Engine and font files are saved
// the first time the app loads them under this worker.)
const CORE = [
  '/',
  '/flutter_bootstrap.js',
  '/main.dart.js',
  '/manifest.json',
  '/assets/FontManifest.json',
  '/assets/AssetManifest.bin.json',
  '/assets/fonts/MaterialIcons-Regular.otf',
  '/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // One missing file must not stop the rest being saved.
    await Promise.all(CORE.map(async (path) => {
      try {
        const res = await fetch(path, { cache: 'no-store' });
        if (res.ok) await cache.put(path, res);
      } catch (_) {}
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter((k) => k.startsWith('fomra-app-shell-') && k !== CACHE)
        .map((k) => caches.delete(k)));
    await self.clients.claim();
  })());
});

function isEngineAsset(url) {
  if (url.hostname === 'www.gstatic.com') {
    return url.pathname.startsWith('/flutter-canvaskit/') ||
      url.pathname.startsWith('/firebasejs/');
  }
  // The Inter font (Google Fonts stylesheet + font files).
  return url.hostname === 'fonts.googleapis.com' ||
    url.hostname === 'fonts.gstatic.com';
}

function isAppFile(url) {
  if (url.origin !== self.location.origin) return false;
  // Server functions and the push worker are never cached.
  if (url.pathname.startsWith('/api/') || url.pathname === '/health') return false;
  if (url.pathname.endsWith('firebase-messaging-sw.js')) return false;
  if (url.pathname.endsWith('app_sw.js')) return false;
  return true;
}

// Network first; a fresh response replaces the saved copy. Falls back to the
// saved copy on failure or after NETWORK_TIMEOUT_MS.
async function networkFirst(request, cacheKey) {
  const cache = await caches.open(CACHE);
  const fromNetwork = fetch(request).then((res) => {
    if (res && res.ok) cache.put(cacheKey, res.clone());
    return res;
  });
  const timeout = new Promise((resolve) =>
    setTimeout(() => resolve(null), NETWORK_TIMEOUT_MS));
  try {
    const res = await Promise.race([fromNetwork, timeout]);
    if (res) return res;
  } catch (_) { /* offline: use the saved copy */ }
  const saved = await cache.match(cacheKey);
  if (saved) return saved;
  // Nothing saved yet: wait for the network after all.
  return fromNetwork;
}

// Engine files are versioned by URL, so a saved copy is always right.
async function cacheFirst(request) {
  const cache = await caches.open(CACHE);
  const saved = await cache.match(request);
  if (saved) return saved;
  const res = await fetch(request);
  if (res && (res.ok || res.type === 'opaque')) cache.put(request, res.clone());
  return res;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (isEngineAsset(url)) {
    event.respondWith(cacheFirst(request));
    return;
  }
  if (!isAppFile(url)) return;
  // Every page address serves the same app (index.html).
  const key = request.mode === 'navigate'
    ? new Request(new URL('/', self.location.origin).toString())
    : new Request(url.origin + url.pathname);
  event.respondWith(networkFirst(request, key));
});
