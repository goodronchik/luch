/* Луч — Service Worker для установки PWA и офлайн-оболочки. */
const VERSION = 'luch-pwa-v0.0.2a';
const BASE = new URL('./', self.registration.scope).pathname;
const SHELL = [
  BASE,
  `${BASE}manifest.json`,
  `${BASE}favicon.png`,
  `${BASE}icons/Icon-192.png`,
  `${BASE}icons/Icon-512.png`,
  `${BASE}icons/Icon-maskable-512.png`,
  `${BASE}icons/apple-touch-icon.png`,
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(VERSION)
      .then((cache) => cache.addAll(SHELL))
      .then(() => self.skipWaiting())
      .catch(() => undefined),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (
    url.pathname.includes('/signal') ||
    url.pathname.includes('/api/') ||
    url.pathname.endsWith('/healthz')
  ) {
    return;
  }

  if (
    request.mode === 'navigate' ||
    url.pathname.endsWith('/flutter_bootstrap.js') ||
    url.pathname.endsWith('/version.json')
  ) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            void caches.open(VERSION).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(async () => (await caches.match(request)) ?? (await caches.match(BASE)) ?? Response.error()),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          void caches.open(VERSION).then((cache) => cache.put(request, copy));
        }
        return response;
      });
    }),
  );
});
