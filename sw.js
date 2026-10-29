const CACHE_NAME = 'mi-negocio-v120';
const APP_SHELL = ['./', './index.html', './styles.css', './app.js', './aviso-carrito.js', './pdf-comun.js', './pdf-categoria.js', './categorias.js', './modal-bloqueo.js', './manifest.json', './icon.svg'];
const PAGINA_OFFLINE = './index.html';
const RECURSOS_EXTERNOS = [
  'https://cdn.tailwindcss.com',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-auth-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-firestore-compat.js'
];

function respuestaValida(response) {
  return response && (response.ok || response.type === 'opaque');
}

async function guardarEnCache(request, response) {
  if (!respuestaValida(response)) return;
  const cache = await caches.open(CACHE_NAME);
  await cache.put(request, response.clone());
}

async function actualizarPaginaEnCache() {
  try {
    const response = await fetch(new Request(PAGINA_OFFLINE, { cache: 'reload' }));
    if (response.ok) await guardarEnCache(PAGINA_OFFLINE, response);
  } catch (error) {
    // Sin conexión: se conserva la página que ya está guardada.
  }
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);

    // No activar una versión incompleta: HTML, estilos, lógica e iconos deben estar disponibles offline.
    await cache.addAll(APP_SHELL.map(recurso => new Request(recurso, { cache: 'reload' })));

    // Los scripts externos se guardan como recursos no-CORS para poder reutilizarlos offline.
    await Promise.allSettled(RECURSOS_EXTERNOS.map(async recurso => {
      const peticion = new Request(recurso, { mode: 'no-cors', cache: 'reload' });
      const respuesta = await fetch(peticion);
      if (respuestaValida(respuesta)) await cache.put(peticion, respuesta);
    }));
    // La versión queda en espera hasta que el usuario pulse "Actualizar".
  })());
});

self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  const esNavegacion = event.request.mode === 'navigate';
  const esRecursoApp = url.origin === self.location.origin;
  const esDependencia = RECURSOS_EXTERNOS.includes(url.href);

  if (esNavegacion) {
    event.respondWith((async () => {
      const paginaGuardada = await caches.match(PAGINA_OFFLINE) || await caches.match('./');
      if (paginaGuardada) {
        // Abrir primero la versión local permite entrar aunque el Wi-Fi esté lento o caído.
        event.waitUntil(actualizarPaginaEnCache());
        return paginaGuardada;
      }
      try {
        const response = await fetch(event.request);
        await guardarEnCache(PAGINA_OFFLINE, response);
        return response;
      } catch (error) {
        return new Response('Abre Mi Negocio una vez con internet para guardar la aplicación y poder usarla sin conexión.', {
          status: 503,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' }
        });
      }
    })());
    return;
  }

  if (esRecursoApp || esDependencia) {
    event.respondWith((async () => {
      const cached = await caches.match(event.request, { ignoreSearch: esRecursoApp });
      const actualizar = fetch(event.request).then(async response => {
        await guardarEnCache(event.request, response);
        return response;
      });

      if (cached) {
        event.waitUntil(actualizar.catch(() => undefined));
        return cached;
      }
      try {
        return await actualizar;
      } catch (error) {
        return new Response('', { status: 504, statusText: 'Sin conexión' });
      }
    })());
  }
});
