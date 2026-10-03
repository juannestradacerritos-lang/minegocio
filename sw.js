const CACHE_NAME = 'mi-negocio-v47';
const APP_SHELL = ['./', './index.html', './manifest.json', './icon.svg'];
const RECURSOS_EXTERNOS = [
  'https://cdn.tailwindcss.com',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-auth-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-firestore-compat.js'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async cache => {
      await cache.addAll(APP_SHELL);
      // Los recursos externos se intentan guardar, pero no bloquean la instalación.
      await Promise.allSettled(RECURSOS_EXTERNOS.map(url => cache.add(url)));
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  const esNavegacion = event.request.mode === 'navigate';
  const esRecursoApp = url.origin === self.location.origin;
  const esDependencia = RECURSOS_EXTERNOS.includes(url.href);

  if (esNavegacion) {
    event.respondWith(
      fetch(event.request)
        .then(response => {
          if (response.ok) {
            const copia = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put('./index.html', copia));
          }
          return response;
        })
        .catch(() => caches.match('./index.html'))
    );
    return;
  }

  if (esRecursoApp || esDependencia) {
    event.respondWith(
      caches.match(event.request).then(cached => {
        const actualizar = fetch(event.request).then(response => {
          if (response.ok) {
            const copia = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(event.request, copia));
          }
          return response;
        });

        if (cached) {
          event.waitUntil(actualizar.catch(() => undefined));
          return cached;
        }
        return actualizar.catch(() => Response.error());
      })
    );
  }
});
