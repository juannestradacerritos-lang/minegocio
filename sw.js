const CACHE_NAME = 'mi-negocio-v106';
const APP_SHELL = ['./', './index.html', './styles.css', './app.js', './aviso-carrito.js', './pdf-comun.js', './pdf-categoria.js', './categorias.js', './modal-bloqueo.js', './manifest.json', './icon.svg'];
const PAGINA_OFFLINE = './index.html';
const RECURSOS_EXTERNOS = [
  'https://cdn.tailwindcss.com',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-auth-compat.js',
  'https://www.gstatic.com/firebasejs/10.8.1/firebase-firestore-compat.js'
];

function respuestaValida(response) {
  // Las respuestas opacas de otros dominios tienen status 0, pero sí se pueden reutilizar desde Cache Storage.
  return response && (response.ok || response.type === 'opaque');
}

async function guardarEnCache(request, response) {
  if (!respuestaValida(response)) return;
  const cache = await caches.open(CACHE_NAME);
  await cache.put(request, response.clone());
}

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);

    // Cada archivo se guarda por separado para que un fallo no invalide toda la instalación.
    const resultadosLocales = await Promise.allSettled(
      // 'reload' evita que la caché HTTP del navegador entregue archivos viejos al instalar una versión nueva.
      APP_SHELL.map(recurso => cache.add(new Request(recurso, { cache: 'reload' })))
    );

    // index.html es imprescindible para mostrar la aplicación sin conexión.
    const indice = APP_SHELL.indexOf(PAGINA_OFFLINE);
    if (resultadosLocales[indice]?.status === 'rejected') {
      throw resultadosLocales[indice].reason;
    }

    // Las bibliotecas externas también se intentan guardar sin bloquear la instalación.
    await Promise.allSettled(RECURSOS_EXTERNOS.map(recurso => cache.add(recurso)));
    // No se llama a skipWaiting() aquí: la versión nueva queda en espera hasta que el usuario
    // pulse "Actualizar" en la aplicación (mensaje SKIP_WAITING).
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
      try {
        const response = await fetch(event.request);
        await guardarEnCache(PAGINA_OFFLINE, response);
        return response;
      } catch (error) {
        const paginaGuardada = await caches.match(PAGINA_OFFLINE);
        if (paginaGuardada) return paginaGuardada;
        return new Response('La aplicación no está disponible sin conexión todavía.', {
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

