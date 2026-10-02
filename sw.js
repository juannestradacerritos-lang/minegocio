const CACHE_NAME = 'mi-negocio-cache-v31';
const urlsToCache = [
  './',
  './index.html',
  './manifest.json?v=2',
  './icon.svg' // Asegúrate de tener tu icono en la misma carpeta que estos archivos
];

// Instalación: Guardar los archivos principales para uso offline
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        return cache.addAll(urlsToCache);
      })
  );
});

// Activación: Limpiar cachés de versiones anteriores
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheName !== CACHE_NAME) {
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});

// Intercepción de peticiones (Fetch)
self.addEventListener('fetch', event => {
  // Omitimos interceptar a Firebase para que él mismo maneje sus datos offline 
  // (gracias a db.enablePersistence() en tu index.html)
  if (event.request.url.includes('firestore.googleapis.com') || 
      event.request.url.includes('identitytoolkit.googleapis.com')) {
      return;
  }

  // Para todo lo demás, intentar responder con la caché, si no, ir a la red
  event.respondWith(
    caches.match(event.request)
      .then(response => {
        if (response) {
          return response;
        }
        return fetch(event.request);
      })
  );
});
