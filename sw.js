// Aumentamos a v36 para forzar al navegador a notar el cambio
const CACHE_NAME = 'mi-negocio-cache-v42'; 
const urlsToCache = [
  './',
  './index.html',
  './manifest.json?v=5',
  './icon.svg'
];

self.addEventListener('install', event => {
  // Obliga al Service Worker nuevo a instalarse de inmediato y patear al viejo
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(urlsToCache))
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheName !== CACHE_NAME) {
            console.log('Borrando caché antigua:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => self.clients.claim()) // Toma el control de la página al instante
  );
});

self.addEventListener('fetch', event => {
  // Omitimos interceptar a Firebase
  if (event.request.url.includes('firestore.googleapis.com') || 
      event.request.url.includes('identitytoolkit.googleapis.com')) {
      return;
  }

  // ESTRATEGIA CORREGIDA: Network First (Red primero, si falla va a la caché)
  event.respondWith(
    fetch(event.request)
      .then(networkResponse => {
        // Si hay internet y Netlify responde con código nuevo, actualizamos la caché en silencio
        return caches.open(CACHE_NAME).then(cache => {
          cache.put(event.request, networkResponse.clone());
          return networkResponse;
        });
      })
      .catch(() => {
        // Si no hay internet (offline), entonces sí sacamos los archivos de la caché
        return caches.match(event.request);
      })
  );
});
