        // Tema: respeta la elección guardada y, si no hay ninguna, sigue el tema del dispositivo.
        function aplicarTema(oscuro) {
            document.body.classList.toggle('dark-mode', oscuro);
            const interruptor = document.getElementById('interruptor-modo-oscuro');
            if (interruptor) interruptor.checked = oscuro;
            // Colorea la barra del sistema en la PWA según el tema activo.
            document.querySelector('meta[name="theme-color"]')?.setAttribute('content', oscuro ? '#081b1b' : '#155a4c');
        }

        // El modo claro es el punto de partida; la preferencia guardada siempre se respeta.
        if (localStorage.getItem('modoOscuro') === null) localStorage.setItem('modoOscuro', 'false');
        aplicarTema(localStorage.getItem('modoOscuro') === 'true');

        const firebaseConfig = {
            apiKey: "AIzaSyC43cEVLZ106chtuuXlQ-HoWkUp34kzauE",
            authDomain: "negocio-69f46.firebaseapp.com",
            databaseURL: "https://negocio-69f46-default-rtdb.firebaseio.com",
            projectId: "negocio-69f46",
            storageBucket: "negocio-69f46.firebasestorage.app",
            messagingSenderId: "654149292832",
            appId: "1:654149292832:web:72b98d0316c44885b13d45",
            measurementId: "G-HF323F7V7C"
        };
        
        firebase.initializeApp(firebaseConfig);
        const db = firebase.firestore();
        const auth = firebase.auth();
        const provider = new firebase.auth.GoogleAuthProvider();
        // Después de cerrar sesión, deja elegir explícitamente qué cuenta usar.
        provider.setCustomParameters({ prompt: 'select_account' });

        // Cada cuenta guarda sus datos en una ruta independiente.
        function coleccionUsuario(nombre) {
            const usuario = auth.currentUser;
            if (!usuario) throw new Error('Debes iniciar sesión para acceder a los datos.');
            return db.collection('usuarios').doc(usuario.uid).collection(nombre);
        }

        // Conserva en el dispositivo los datos ya sincronizados para poder consultarlos sin conexión.
        const persistenciaFirestore = db.enablePersistence({ synchronizeTabs: true }).catch((error) => {
            if (error.code === 'failed-precondition') {
                console.warn('La persistencia sin conexión solo puede activarse en una pestaña a la vez.');
            } else if (error.code === 'unimplemented') {
                console.warn('Este navegador no admite almacenamiento local de Firestore.');
            } else {
                console.warn('No se pudo activar la persistencia sin conexión:', error);
            }
        });

        let inventario = [];
        let categoriaCatalogoSeleccionada = 'todas';
        let carrito = [];
        let productoAEliminar = null;
        let productoAEditar = null;
        let totalVentaActual = 0; 
        let unsubscribeFirestore = null;
        let unsubscribeVentas = null;
        let unsubscribeMovimientos = null;
        let ventas = [];
        let movimientos = [];
        let respaldoPendiente = null;
        const inicioCarga = performance.now();
        const DURACION_MINIMA_CARGA = 650;
        let temporizadorToast;

        function mostrarAviso(mensaje, tipo = '') {
            const toast = document.getElementById('app-toast');
            clearTimeout(temporizadorToast);
            toast.textContent = mensaje;
            toast.className = tipo ? `visible ${tipo}` : 'visible';
            temporizadorToast = setTimeout(() => toast.classList.remove('visible'), 2600);
        }

        function establecerCargaBoton(boton, cargando) {
            if (!boton) return;
            boton.disabled = cargando;
            boton.classList.toggle('btn-cargando', cargando);
            boton.setAttribute('aria-busy', cargando ? 'true' : 'false');
        }

        let selectorPersonalizadoAbierto = null;
        let contadorSelectoresPersonalizados = 0;

        function opcionesSelectorPersonalizado(select) {
            return [...select.options].map((opcion, indice) => ({
                indice,
                texto: opcion.textContent,
                seleccionada: opcion.selected,
                deshabilitada: opcion.disabled
            }));
        }

        function sincronizarSelectorPersonalizado(select) {
            const contenedor = select.closest('.app-select');
            if (!contenedor) return;
            const valor = contenedor.querySelector('.app-select-value');
            const opcion = select.options[select.selectedIndex];
            valor.textContent = opcion?.textContent || 'Selecciona una opción';
            contenedor.querySelector('.app-select-trigger').disabled = select.disabled;
        }

        function cerrarSelectorPersonalizado(devolverFoco = false) {
            if (!selectorPersonalizadoAbierto) return;
            const { contenedor, boton, menu } = selectorPersonalizadoAbierto;
            menu.classList.add('hidden');
            boton.setAttribute('aria-expanded', 'false');
            contenedor.classList.remove('abierto');
            selectorPersonalizadoAbierto = null;
            if (devolverFoco) boton.focus();
        }

        function posicionarSelectorPersonalizado(boton, menu) {
            const margen = 10;
            const separacion = 6;
            const rect = boton.getBoundingClientRect();
            const espacioAbajo = window.innerHeight - rect.bottom - margen;
            const espacioArriba = rect.top - margen;
            const abrirArriba = espacioAbajo < 190 && espacioArriba > espacioAbajo;
            const altoDisponible = Math.max(110, Math.min(320, (abrirArriba ? espacioArriba : espacioAbajo) - separacion));
            const ancho = Math.min(Math.max(rect.width, 220), window.innerWidth - margen * 2);
            const izquierda = Math.min(Math.max(margen, rect.left), window.innerWidth - ancho - margen);

            menu.style.width = `${ancho}px`;
            menu.style.maxHeight = `${altoDisponible}px`;
            menu.style.left = `${izquierda}px`;
            menu.style.top = abrirArriba ? 'auto' : `${rect.bottom + separacion}px`;
            menu.style.bottom = abrirArriba ? `${window.innerHeight - rect.top + separacion}px` : 'auto';
        }

        function construirOpcionesSelector(select, menu) {
            menu.replaceChildren();
            opcionesSelectorPersonalizado(select).forEach(opcion => {
                const botonOpcion = document.createElement('button');
                botonOpcion.type = 'button';
                botonOpcion.className = 'app-select-option';
                botonOpcion.setAttribute('role', 'option');
                botonOpcion.setAttribute('aria-selected', String(opcion.seleccionada));
                botonOpcion.disabled = opcion.deshabilitada;

                const texto = document.createElement('span');
                texto.textContent = opcion.texto;
                const marca = document.createElement('span');
                marca.className = 'app-select-check';
                marca.setAttribute('aria-hidden', 'true');
                marca.textContent = opcion.seleccionada ? '✓' : '';
                botonOpcion.append(texto, marca);

                botonOpcion.addEventListener('click', () => {
                    select.selectedIndex = opcion.indice;
                    select.dispatchEvent(new Event('change', { bubbles: true }));
                    sincronizarSelectorPersonalizado(select);
                    cerrarSelectorPersonalizado(true);
                });
                menu.appendChild(botonOpcion);
            });
        }

        function abrirSelectorPersonalizado(contenedor) {
            const select = contenedor.querySelector('select');
            const boton = contenedor.querySelector('.app-select-trigger');
            const menu = document.getElementById(boton.getAttribute('aria-controls'));
            if (select.disabled) return;
            if (selectorPersonalizadoAbierto?.contenedor === contenedor) {
                cerrarSelectorPersonalizado();
                return;
            }
            cerrarSelectorPersonalizado();
            sincronizarSelectorPersonalizado(select);
            construirOpcionesSelector(select, menu);
            menu.classList.remove('hidden');
            boton.setAttribute('aria-expanded', 'true');
            contenedor.classList.add('abierto');
            selectorPersonalizadoAbierto = { contenedor, boton, menu };
            posicionarSelectorPersonalizado(boton, menu);
            requestAnimationFrame(() => menu.querySelector('[aria-selected="true"]:not(:disabled)')?.focus());
        }

        function moverFocoOpcion(menu, direccion) {
            const opciones = [...menu.querySelectorAll('.app-select-option:not(:disabled)')];
            if (!opciones.length) return;
            const actual = opciones.indexOf(document.activeElement);
            const siguiente = actual < 0 ? 0 : (actual + direccion + opciones.length) % opciones.length;
            opciones[siguiente].focus();
        }

        function convertirSelectPersonalizado(select) {
            if (select.closest('.app-select') || select.multiple) return;
            const contenedor = document.createElement('div');
            contenedor.className = 'app-select';
            [...select.classList]
                .filter(clase => /^m[trblxy]?-[\w.\[\]-]+$/.test(clase))
                .forEach(clase => contenedor.classList.add(clase));
            select.parentNode.insertBefore(contenedor, select);
            contenedor.appendChild(select);
            select.classList.add('app-select-native');
            select.tabIndex = -1;

            const idMenu = `app-select-menu-${++contadorSelectoresPersonalizados}`;
            const boton = document.createElement('button');
            boton.type = 'button';
            boton.className = 'app-select-trigger';
            boton.setAttribute('aria-haspopup', 'listbox');
            boton.setAttribute('aria-expanded', 'false');
            boton.setAttribute('aria-controls', idMenu);
            const etiqueta = select.id ? document.querySelector(`label[for="${select.id}"]`) : null;
            boton.setAttribute('aria-label', etiqueta?.textContent.trim() || select.getAttribute('aria-label') || 'Seleccionar opción');
            boton.innerHTML = '<span class="app-select-value"></span><span class="app-select-chevron" aria-hidden="true">⌄</span>';

            const menu = document.createElement('div');
            menu.id = idMenu;
            menu.className = 'app-select-menu hidden';
            menu.setAttribute('role', 'listbox');
            contenedor.appendChild(boton);
            document.body.appendChild(menu);

            boton.addEventListener('click', () => abrirSelectorPersonalizado(contenedor));
            boton.addEventListener('keydown', event => {
                if (['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(event.key)) {
                    event.preventDefault();
                    abrirSelectorPersonalizado(contenedor);
                }
            });
            menu.addEventListener('keydown', event => {
                if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                    event.preventDefault();
                    moverFocoOpcion(menu, event.key === 'ArrowDown' ? 1 : -1);
                } else if (event.key === 'Home' || event.key === 'End') {
                    event.preventDefault();
                    const opciones = [...menu.querySelectorAll('.app-select-option:not(:disabled)')];
                    opciones[event.key === 'Home' ? 0 : opciones.length - 1]?.focus();
                } else if (event.key === 'Escape') {
                    event.preventDefault();
                    cerrarSelectorPersonalizado(true);
                }
            });
            select.addEventListener('change', () => sincronizarSelectorPersonalizado(select));
            sincronizarSelectorPersonalizado(select);
        }

        function inicializarSelectoresPersonalizados() {
            document.querySelectorAll('select:not([multiple])').forEach(convertirSelectPersonalizado);
        }

        document.addEventListener('click', event => {
            if (selectorPersonalizadoAbierto && !selectorPersonalizadoAbierto.contenedor.contains(event.target) && !selectorPersonalizadoAbierto.menu.contains(event.target)) {
                cerrarSelectorPersonalizado();
            }
        });
        document.addEventListener('keydown', event => {
            if (event.key === 'Escape' && selectorPersonalizadoAbierto) cerrarSelectorPersonalizado(true);
        });
        document.addEventListener('reset', event => {
            setTimeout(() => event.target.querySelectorAll('select').forEach(sincronizarSelectorPersonalizado));
        });
        window.addEventListener('resize', () => cerrarSelectorPersonalizado());
        window.addEventListener('scroll', () => cerrarSelectorPersonalizado(), true);
        inicializarSelectoresPersonalizados();
        
        auth.onAuthStateChanged(async (user) => {
            const startupScreen = document.getElementById('startup-screen');
            const loginScreen = document.getElementById('login-screen');
            const appContent = document.getElementById('app-content');

            // Conserva el arranque el tiempo suficiente para que la transición sea perceptible.
            const tiempoRestante = Math.max(0, DURACION_MINIMA_CARGA - (performance.now() - inicioCarga));
            if (tiempoRestante) await new Promise(resolve => setTimeout(resolve, tiempoRestante));

            if (user) {
                loginScreen.classList.add('hidden');
                appContent.classList.remove('hidden');
                
                const avatar = document.getElementById('user-avatar');
                if(user.photoURL) {
                    avatar.src = user.photoURL;
                    avatar.classList.remove('hidden');
                }

                // Espera la activación del almacenamiento local antes de abrir las suscripciones.
                await persistenciaFirestore;
                iniciarLecturaInventario();
                iniciarLecturaVentas();
                iniciarLecturaMovimientos();
            } else {
                loginScreen.classList.remove('hidden');
                appContent.classList.add('hidden');
                
                if(unsubscribeFirestore) unsubscribeFirestore();
                if(unsubscribeVentas) unsubscribeVentas();
                if(unsubscribeMovimientos) unsubscribeMovimientos();
                
                inventario = [];
                ventas = [];
                movimientos = [];
                carrito = [];
                actualizarResumen();
                renderizarCatalogo();
                renderizarListaVenta();
                renderizarCarrito();
                renderizarFaltantes();
            }

            // Retira el arranque con un fundido y después lo saca del flujo visual.
            startupScreen.classList.add('saliendo');
            startupScreen.setAttribute('aria-hidden', 'true');
            setTimeout(() => startupScreen.classList.add('hidden'), 550);
        });

        // NUEVO MÉTODO (IGUAL AL DEL PANEL UNIVERSITARIO)
        function loginConGoogle() {
            auth.signInWithPopup(provider).catch((error) => {
                alert("Error al iniciar sesión: " + error.message);
            });
        }

        function iniciarModoPrueba() {
            auth.signInAnonymously().catch((error) => {
                alert("No se pudo iniciar el modo de prueba: " + error.message);
            });
        }

        async function cerrarSesion() {
            cerrarMenuAjustes();
            try {
                await auth.signOut();
            } catch (error) {
                console.error('No se pudo cerrar la sesión:', error);
                alert('No se pudo cerrar la sesión. Revisa tu conexión e inténtalo de nuevo.');
            }
        }

        function iniciarLecturaInventario() {
            unsubscribeFirestore = coleccionUsuario("productos").onSnapshot((querySnapshot) => {
                inventario = [];
                querySnapshot.forEach((doc) => {
                    inventario.push({ id: doc.id, ...doc.data() });
                });
                
                inventario.sort((a, b) => a.nombre.localeCompare(b.nombre));
                carrito.forEach(item => {
                    item.stock = Number(inventario.find(p => p.id === item.id)?.stock) || 0;
                });
                renderizarCarrito();
                actualizarResumen();
                renderizarCatalogo();
                renderizarListaVenta();
                renderizarFaltantes();
            });
        }

        function iniciarLecturaVentas() {
            unsubscribeVentas = coleccionUsuario("ventas").onSnapshot({ includeMetadataChanges: true }, (querySnapshot) => {
                ventas = [];
                querySnapshot.forEach((doc) => ventas.push({ id: doc.id, ...doc.data({ serverTimestamps: 'estimate' }), pendiente: doc.metadata.hasPendingWrites }));
                actualizarResumen();
                renderizarGraficos();
            });
        }

        function iniciarLecturaMovimientos() {
            unsubscribeMovimientos = coleccionUsuario('movimientos').orderBy('fecha', 'desc').limit(200).onSnapshot(querySnapshot => {
                movimientos = querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
                renderizarMovimientos();
            });
        }

        function registrarMovimiento(datos, batch = null) {
            const referencia = coleccionUsuario('movimientos').doc();
            const movimiento = { ...datos, fecha: firebase.firestore.FieldValue.serverTimestamp() };
            if (batch) batch.set(referencia, movimiento);
            else return referencia.set(movimiento);
        }

        function abrirModalMovimientos() {
            renderizarMovimientos();
            document.getElementById('modal-movimientos').classList.remove('hidden');
        }

        function cerrarModalMovimientos() {
            document.getElementById('modal-movimientos').classList.add('hidden');
        }

        function renderizarMovimientos() {
            const contenedor = document.getElementById('lista-movimientos');
            if (!contenedor) return;
            if (!movimientos.length) {
                contenedor.innerHTML = '<p class="text-center text-gray-400 py-8">Aún no hay movimientos registrados.</p>';
                return;
            }
            contenedor.innerHTML = movimientos.map(movimiento => {
                const fecha = obtenerFechaVenta(movimiento.fecha);
                const cantidad = Number(movimiento.cantidad) || 0;
                const signo = cantidad > 0 ? '+' : '';
                return `<div class="movement-item"><div><strong class="block text-sm text-gray-700">${escaparHTML(movimiento.producto || 'Producto')}</strong><span class="block text-xs text-gray-500 mt-1">${escaparHTML(movimiento.detalle || movimiento.tipo || 'Movimiento')}</span><span class="block text-[11px] text-gray-400 mt-1">${fecha ? fecha.toLocaleString('es-GT') : 'Sincronizando…'}</span></div><strong class="${cantidad < 0 ? 'text-red-500' : 'text-teal-600'}">${signo}${cantidad.toFixed(2).replace(/\.00$/, '')}</strong></div>`;
            }).join('');
        }

        const categoriasVentasBase = [
            'Verduras',
            'Abarrotes',
            'Plásticos para el hogar',
            'Vajilla de porcelana',
            'Granos y frijoles',
            'Otros'
        ];
        let categoriaVentasSeleccionada = 'todas';
        let opcionesCategoriasVentas = [];

        function obtenerCategoriasVentas() {
            const categoriasInventario = inventario.map(producto => producto.categoria || 'Otros');
            return [...new Set([...categoriasVentasBase, ...categoriasInventario])];
        }

        // Selección de categoría solo para el PDF: botones visibles, sin desplegable.
        function renderizarMenuCategorias() {
            const contenedor = document.getElementById('filtro-categoria-chips');
            if (!contenedor) return;
            const categorias = obtenerCategoriasVentas();
            if (categoriaVentasSeleccionada !== 'todas' && !categorias.includes(categoriaVentasSeleccionada)) {
                categoriaVentasSeleccionada = 'todas';
            }
            opcionesCategoriasVentas = [{ valor: 'todas', texto: 'Todas' }, ...categorias.map(categoria => ({ valor: categoria, texto: categoria }))];
            contenedor.innerHTML = opcionesCategoriasVentas.map((opcion, indice) => {
                const activa = opcion.valor === categoriaVentasSeleccionada;
                return `<button type="button" class="category-chip${activa ? ' activa' : ''}" role="radio" aria-checked="${activa}" onclick="seleccionarCategoriaVentasPorIndice(${indice})">${escaparHTML(opcion.texto)}</button>`;
            }).join('');
            if (typeof window.renderizarVentasCategoria === 'function') window.renderizarVentasCategoria();
        }

        function seleccionarCategoriaVentasPorIndice(indice) {
            const opcion = opcionesCategoriasVentas[indice];
            if (!opcion) return;
            categoriaVentasSeleccionada = opcion.valor;
            renderizarMenuCategorias();
        }

        function renderizarGraficos() {
            const porProducto = {};
            const porDia = {};
            let totalVentas = 0;
            let unidadesVendidas = 0;
            renderizarMenuCategorias();
            // Los gráficos siempre muestran todas las ventas; la categoría elegida solo afecta al PDF.
            const filtro = 'todas';

            ventas.forEach(venta => {
                const fecha = obtenerFechaVenta(venta.fecha);
                (venta.items || []).forEach(item => {
                    const nombreBase = String(item.nombre || '').replace(/ \((mediano|grande)\)$/i, '');
                    const producto = inventario.find(p => p.id === item.productoId) || inventario.find(p => p.nombre === nombreBase);
                    const categoria = item.categoria || producto?.categoria || 'Otros';
                    if (filtro !== 'todas' && categoria !== filtro) return;
                    const cantidad = Number(item.cantidad) || 0;
                    const importe = (Number(item.precio) || 0) * cantidad;
                    totalVentas += importe;
                    unidadesVendidas += cantidad;
                    if (!porProducto[item.nombre]) porProducto[item.nombre] = { importe: 0, cantidad: 0, categoria };
                    porProducto[item.nombre].importe += importe;
                    porProducto[item.nombre].cantidad += cantidad;
                    if (fecha) {
                        const clave = fecha.toISOString().slice(0, 10);
                        porDia[clave] = (porDia[clave] || 0) + importe;
                    }
                });
            });

            document.getElementById('grafico-total-ventas').innerText = `Q${totalVentas.toFixed(2)}`;
            document.getElementById('grafico-unidades-vendidas').innerText = unidadesVendidas.toFixed(2).replace(/\.00$/, '');

            const productos = Object.entries(porProducto).map(([nombre, valor]) => ({ nombre, ...valor }));
            const ordenados = [...productos].sort((a, b) => b.cantidad - a.cantidad);
            const dias = Object.entries(porDia).sort(([a], [b]) => a.localeCompare(b)).slice(-10)
                .map(([fecha, total]) => ({ nombre: formatearFechaCorta(fecha), valor: total }));

            dibujarBarras('grafico-barras', [...productos].sort((a, b) => b.importe - a.importe).slice(0, 6));
            dibujarLinea('grafico-lineal', dias);
            dibujarPastel('grafico-pastel', ordenados.slice(0, 6));
        }

        function fechaLocalActual() {
            const hoy = new Date();
            return `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-${String(hoy.getDate()).padStart(2, '0')}`;
        }

        let ultimoDiaResumen = fechaLocalActual();
        let seguirHoy = true;

        function actualizarDiaResumen() {
            const hoy = fechaLocalActual();
            const selector = document.getElementById('categoria-fecha-dia');
            if (hoy !== ultimoDiaResumen && seguirHoy && selector) {
                selector.value = hoy;
                selector.dispatchEvent(new Event('change', { bubbles: true }));
            }
            ultimoDiaResumen = hoy;
            renderizarVentasHoy();
        }

        document.getElementById('categoria-fecha-dia').addEventListener('change', event => {
            seguirHoy = !event.target.value || event.target.value === fechaLocalActual();
            renderizarVentasHoy();
        });
        setInterval(actualizarDiaResumen, 60000);
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden) actualizarDiaResumen();
        });

        function formatearCantidades(unidades, libras) {
            const cantidadUnidades = Number(unidades.toFixed(2));
            const cantidadLibras = Number(libras.toFixed(2));
            return `${cantidadUnidades} ${cantidadUnidades === 1 ? 'unidad' : 'unidades'} · ${cantidadLibras} ${cantidadLibras === 1 ? 'libra' : 'libras'}`;
        }

        // La lista diaria comparte el día de las descargas, sin filtrar por categoría.
        function renderizarVentasHoy() {
            const lista = document.getElementById('lista-ventas-hoy');
            if (!lista) return;
            const selector = document.getElementById('categoria-fecha-dia');
            if (!selector.value) selector.value = fechaLocalActual();
            const esHoy = selector.value === fechaLocalActual();
            const inicio = new Date(`${selector.value}T00:00:00`);
            document.getElementById('ventas-dia-titulo').textContent = esHoy ? 'Ventas de hoy' : 'Ventas del día seleccionado';
            document.getElementById('ventas-dia-total-etiqueta').textContent = esHoy ? 'Total de ventas de hoy' : 'Total de ventas del día';
            const fin = new Date(inicio);
            fin.setDate(fin.getDate() + 1);

            const deHoy = ventas
                .map(venta => ({ venta, fecha: obtenerFechaVenta(venta.fecha) || obtenerFechaVenta(venta.fechaLocal) }))
                .filter(({ fecha }) => fecha && fecha >= inicio && fecha < fin)
                .sort((a, b) => b.fecha - a.fecha);

            let total = 0;
            let unidades = 0, libras = 0;
            deHoy.forEach(({ venta }) => {
                total += Number(venta.total) || 0;
                (venta.items || []).forEach(item => {
                    if (item.unidadVenta === 'libra') libras += Number(item.cantidad) || 0;
                    else unidades += Number(item.cantidad) || 0;
                });
            });

            document.getElementById('ventas-hoy-fecha').textContent = inicio.toLocaleDateString('es-GT', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' });
            document.getElementById('ventas-hoy-total').textContent = `Q${total.toFixed(2)}`;
            document.getElementById('ventas-hoy-total-final').textContent = `Q${total.toFixed(2)}`;
            document.getElementById('ventas-hoy-cantidad').textContent = deHoy.length;
            document.getElementById('ventas-hoy-unidades').textContent = formatearCantidades(unidades, libras);

            if (!deHoy.length) {
                lista.innerHTML = `<p class="text-center text-gray-400 py-6">${esHoy ? 'Aún no hay ventas hoy.' : 'No hay ventas registradas este día.'}</p>`;
                return;
            }
            lista.innerHTML = deHoy.map(({ venta, fecha }) => {
                const detalle = (venta.items || []).map(item => `${escaparHTML(item.nombre || 'Producto')} × ${(Number(item.cantidad) || 0).toFixed(2).replace(/\.00$/, '')} ${item.unidadVenta === 'libra' ? 'lb' : 'unid.'}`).join(', ');
                const hora = fecha.toLocaleTimeString('es-GT', { hour: '2-digit', minute: '2-digit' }) + (venta.pendiente ? ' · Sincronizando…' : '');
                return `<div class="movement-item"><div class="min-w-0"><strong class="block text-sm text-gray-700">${hora}</strong><span class="block text-xs text-gray-500 mt-1">${detalle}</span></div><strong class="text-teal-600 shrink-0">Q${(Number(venta.total) || 0).toFixed(2)}</strong></div>`;
            }).join('');
        }


        // Datos compartidos por las descargas de imagen y PDF por categoría.
        function obtenerResumenCategoriaDia() {
            const selector = document.getElementById('categoria-fecha-dia');
            const dia = selector?.value || fechaLocalActual();
            const filtro = categoriaVentasSeleccionada || 'todas';
            const acumulados = new Map();
            const ventasIncluidas = new Set();
            let cantidadTotal = 0;
            let importeTotal = 0;

            const claveFecha = fecha => {
                if (typeof fecha === 'string' && fecha.length === 10 && fecha[4] === '-' && fecha[7] === '-') return fecha;
                const fechaValida = obtenerFechaVenta(fecha);
                if (!fechaValida) return '';
                return `${fechaValida.getFullYear()}-${String(fechaValida.getMonth() + 1).padStart(2, '0')}-${String(fechaValida.getDate()).padStart(2, '0')}`;
            };

            ventas.forEach((venta, indiceVenta) => {
                if (claveFecha(venta.fechaLocal || venta.fecha) !== dia) return;
                let ventaAporta = false;
                (venta.items || []).forEach(item => {
                    const nombreOriginal = String(item.nombre || 'Producto');
                    const nombreBase = nombreOriginal.replace(/ \((mediano|grande)\)$/i, '');
                    const producto = inventario.find(p => p.id === item.productoId) || inventario.find(p => p.nombre === nombreBase);
                    const categoria = item.categoria || producto?.categoria || 'Otros';
                    if (filtro !== 'todas' && categoria !== filtro) return;
                    const cantidad = Number(item.cantidad) || 0;
                    const importe = (Number(item.precio) || 0) * cantidad;
                    if (!acumulados.has(nombreOriginal)) acumulados.set(nombreOriginal, { nombre: nombreOriginal, categoria, cantidad: 0, importe: 0 });
                    const fila = acumulados.get(nombreOriginal);
                    fila.cantidad += cantidad;
                    fila.importe += importe;
                    cantidadTotal += cantidad;
                    importeTotal += importe;
                    ventaAporta = true;
                });
                if (ventaAporta) ventasIncluidas.add(venta.id || indiceVenta);
            });

            const fecha = new Date(`${dia}T00:00:00`);
            const categoriaTexto = filtro === 'todas' ? 'Todas las categorías' : filtro;
            const fechaTexto = Number.isNaN(fecha.getTime())
                ? dia
                : fecha.toLocaleDateString('es-GT', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' });
            return {
                dia, fechaTexto, categoriaTexto,
                ventas: ventasIncluidas.size,
                cantidad: cantidadTotal,
                total: importeTotal,
                productos: [...acumulados.values()].sort((a, b) => b.importe - a.importe)
            };
        }

        function renderizarVentasCategoria() {
            const etiqueta = document.getElementById('categoria-periodo');
            if (!etiqueta) return;
            const resumen = obtenerResumenCategoriaDia();
            etiqueta.textContent = resumen.productos.length
                ? `${resumen.productos.length} productos · ${resumen.ventas} ventas · Total: Q${resumen.total.toFixed(2)} · ${resumen.fechaTexto}`
                : `Sin ventas para ${resumen.categoriaTexto.toLowerCase()} el ${resumen.fechaTexto}.`;
        }
        window.renderizarVentasCategoria = renderizarVentasCategoria;

        function nombreArchivoCategoria(resumen, extension) {
            const nombre = resumen.categoriaTexto.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
                .replace(/[^a-zA-Z0-9]+/g, '_').replace(/^_|_$/g, '') || 'Todas';
            return `Ventas_${nombre}_${resumen.dia}.${extension}`;
        }

        function descargarImagenCategoria() {
            const resumen = obtenerResumenCategoriaDia();
            const ancho = 1200;
            const alto = 470 + Math.max(1, resumen.productos.length) * 62;
            const canvas = document.createElement('canvas');
            canvas.width = ancho;
            canvas.height = alto;
            const ctx = canvas.getContext('2d');
            if (!ctx) return mostrarAviso('No se pudo crear la imagen', 'error');

            ctx.fillStyle = '#f3f6f5';
            ctx.fillRect(0, 0, ancho, alto);
            ctx.fillStyle = '#155a4c';
            ctx.fillRect(0, 0, ancho, 220);
            ctx.fillStyle = '#ffffff';
            ctx.font = '700 28px system-ui, sans-serif';
            ctx.fillText('MI NEGOCIO  ·  REPORTE DE VENTAS', 64, 68);
            ctx.font = '700 42px system-ui, sans-serif';
            ctx.fillText('Ventas por categoría', 64, 132);
            ctx.font = '22px system-ui, sans-serif';
            ctx.fillStyle = '#d9eee6';
            ctx.fillText(`${resumen.categoriaTexto}  ·  ${resumen.fechaTexto}`, 64, 176);

            const tarjetas = [
                { label: 'VENTAS', value: String(resumen.ventas) },
                { label: 'PRODUCTOS', value: String(resumen.productos.length) },
                { label: 'TOTAL VENDIDO', value: `Q${resumen.total.toFixed(2)}` }
            ];
            const cardY = 246, cardW = 336, gap = 32;
            tarjetas.forEach((tarjeta, i) => {
                const x = 64 + i * (cardW + gap);
                ctx.fillStyle = '#ffffff';
                ctx.beginPath(); ctx.roundRect(x, cardY, cardW, 112, 18); ctx.fill();
                ctx.fillStyle = '#6a7d74'; ctx.font = '700 17px system-ui, sans-serif';
                ctx.fillText(tarjeta.label, x + 22, cardY + 38);
                ctx.fillStyle = '#176b57'; ctx.font = '800 32px system-ui, sans-serif';
                ctx.fillText(tarjeta.value, x + 22, cardY + 82);
            });

            const tablaY = 400;
            ctx.fillStyle = '#e3ece7';
            ctx.beginPath(); ctx.roundRect(64, tablaY, ancho - 128, 50, 10); ctx.fill();
            ctx.fillStyle = '#40564c'; ctx.font = '700 17px system-ui, sans-serif';
            ctx.fillText('PRODUCTO', 88, tablaY + 32);
            ctx.fillText('CANTIDAD', 780, tablaY + 32);
            ctx.textAlign = 'right';
            ctx.fillText('IMPORTE', ancho - 88, tablaY + 32);
            ctx.textAlign = 'left';

            if (!resumen.productos.length) {
                ctx.fillStyle = '#6a7d74'; ctx.font = '22px system-ui, sans-serif';
                ctx.fillText('No hay ventas registradas para esta selección.', 88, tablaY + 100);
            } else {
                resumen.productos.forEach((producto, i) => {
                    const y = tablaY + 50 + i * 62;
                    ctx.fillStyle = i % 2 ? '#f7faf8' : '#ffffff';
                    ctx.fillRect(64, y, ancho - 128, 62);
                    ctx.fillStyle = '#1c3029'; ctx.font = '600 19px system-ui, sans-serif';
                    ctx.fillText(producto.nombre, 88, y + 38, 620);
                    ctx.fillStyle = '#40564c'; ctx.font = '18px system-ui, sans-serif';
                    ctx.fillText(Number(producto.cantidad.toFixed(2)).toString(), 780, y + 38);
                    ctx.fillStyle = '#176b57'; ctx.font = '700 19px system-ui, sans-serif';
                    ctx.textAlign = 'right';
                    ctx.fillText(`Q${producto.importe.toFixed(2)}`, ancho - 88, y + 38);
                    ctx.textAlign = 'left';
                });
            }

            canvas.toBlob(blob => {
                if (!blob) return mostrarAviso('No se pudo crear la imagen', 'error');
                const url = URL.createObjectURL(blob);
                const enlace = document.createElement('a');
                enlace.href = url;
                enlace.download = nombreArchivoCategoria(resumen, 'png');
                document.body.appendChild(enlace);
                enlace.click();
                enlace.remove();
                setTimeout(() => URL.revokeObjectURL(url), 1500);
                mostrarAviso('Imagen descargada');
            }, 'image/png');
        }

        function descargarPDFCategoria() {
            const resumen = obtenerResumenCategoriaDia();
            if (!window.PDFInforme) return mostrarAviso('El generador de PDF no está disponible. Recarga la página.', 'error');
            const doc = window.PDFInforme.crearDocumento({
                titulo: 'Ventas por categoría',
                subtitulo: `${resumen.categoriaTexto} · ${resumen.fechaTexto}`,
                etiquetaBanda: 'Resumen diario',
                detalleBanda: window.PDFInforme.fechaGeneracion()
            });
            doc.tarjetas([
                { etiqueta: 'VENTAS', valor: String(resumen.ventas) },
                { etiqueta: 'PRODUCTOS', valor: String(resumen.productos.length), color: '0.31 0.47 0.64' },
                { etiqueta: 'TOTAL VENDIDO', valor: window.PDFInforme.dinero(resumen.total), color: '0.835 0.659 0.294' }
            ]);
            doc.seccion('Detalle por producto', resumen.productos.length ? resumen.categoriaTexto : '');
            if (!resumen.productos.length) {
                doc.vacio('Sin ventas para la categoría y fecha elegidas');
            } else {
                doc.tabla('PRODUCTO');
                resumen.productos.forEach((producto, indice) => doc.fila({
                    n: indice + 1,
                    nombre: producto.nombre,
                    cantidad: producto.cantidad,
                    importe: producto.importe,
                    pct: resumen.total > 0 ? producto.importe / resumen.total * 100 : 0,
                    par: indice % 2 === 0
                }));
                doc.total('TOTAL DEL DÍA', resumen.cantidad, resumen.total);
            }
            window.PDFInforme.descargar(doc.finalizar(), nombreArchivoCategoria(resumen, 'pdf'));
            mostrarAviso('PDF descargado');
        }

        document.getElementById('btn-imagen-categoria')?.addEventListener('click', descargarImagenCategoria);
        document.getElementById('btn-pdf-categoria')?.addEventListener('click', descargarPDFCategoria);
        document.getElementById('categoria-fecha-dia')?.addEventListener('change', renderizarVentasCategoria);
        renderizarVentasCategoria();

        function obtenerFechaVenta(fecha) {
            if (!fecha) return null;
            const valor = typeof fecha.toDate === 'function' ? fecha.toDate() : new Date(fecha);
            return Number.isNaN(valor.getTime()) ? null : valor;
        }

        function formatearFechaCorta(fecha) {
            return new Date(`${fecha}T00:00:00`).toLocaleDateString('es-GT', { day: '2-digit', month: 'short' });
        }

        function prepararCanvas(id) {
            const canvas = document.getElementById(id);
            if (!canvas) return null;
            const rect = canvas.parentElement.getBoundingClientRect();
            const escala = window.devicePixelRatio || 1;
            canvas.width = Math.max(1, Math.round(rect.width * escala));
            canvas.height = Math.max(1, Math.round(rect.height * escala));
            const ctx = canvas.getContext('2d');
            ctx.setTransform(escala, 0, 0, escala, 0, 0);
            ctx.clearRect(0, 0, rect.width, rect.height);
            return { canvas, ctx, ancho: rect.width, alto: rect.height };
        }

        function coloresGrafico() {
            const oscuro = document.body.classList.contains('dark-mode');
            return oscuro
                ? { cuadricula: '#294354', texto: '#9fb2c0', titulo: '#dce8ee', fondo: '#102331' }
                : { cuadricula: '#e1e8ed', texto: '#5b6f81', titulo: '#16324f', fondo: '#fff' };
        }

        function mensajeGrafico(ctx, ancho, alto) {
            ctx.fillStyle = coloresGrafico().texto;
            ctx.font = '13px Inter, sans-serif';
            ctx.textAlign = 'center';
            ctx.fillText('Aún no hay ventas registradas', ancho / 2, alto / 2);
        }

        function dibujarBarras(id, datos) {
            const grafico = prepararCanvas(id);
            if (!grafico) return;
            const { ctx, ancho, alto } = grafico;
            if (!datos.length) return mensajeGrafico(ctx, ancho, alto);

            const margen = { arriba: 16, derecha: 12, abajo: 58, izquierda: 48 };
            const w = ancho - margen.izquierda - margen.derecha;
            const h = alto - margen.arriba - margen.abajo;
            const maximo = Math.max(...datos.map(d => d.importe), 1);
            const tema = coloresGrafico();
            ctx.font = '11px Inter, sans-serif';
            ctx.strokeStyle = tema.cuadricula;
            ctx.fillStyle = tema.texto;
            ctx.textAlign = 'right';

            for (let i = 0; i <= 4; i++) {
                const y = margen.arriba + h - (h * i / 4);
                ctx.beginPath(); ctx.moveTo(margen.izquierda, y); ctx.lineTo(ancho - margen.derecha, y); ctx.stroke();
                ctx.fillText(`Q${Math.round(maximo * i / 4)}`, margen.izquierda - 7, y + 4);
            }

            const espacio = w / datos.length;
            const barra = Math.min(44, espacio * .58);
            datos.forEach((dato, i) => {
                const x = margen.izquierda + i * espacio + (espacio - barra) / 2;
                const altura = dato.importe / maximo * h;
                ctx.fillStyle = '#168c86';
                ctx.fillRect(x, margen.arriba + h - altura, barra, altura);
                ctx.fillStyle = tema.texto;
                ctx.textAlign = 'center';
                const nombre = dato.nombre.length > 10 ? `${dato.nombre.slice(0, 9)}…` : dato.nombre;
                ctx.fillText(nombre, x + barra / 2, alto - 32);
                ctx.fillStyle = tema.titulo;
                ctx.font = '600 10px Inter, sans-serif';
                ctx.fillText(`Q${dato.importe.toFixed(0)}`, x + barra / 2, margen.arriba + h - altura - 7);
                ctx.font = '11px Inter, sans-serif';
            });
        }

        function dibujarLinea(id, datos) {
            const grafico = prepararCanvas(id);
            if (!grafico) return;
            const { ctx, ancho, alto } = grafico;
            if (!datos.length) return mensajeGrafico(ctx, ancho, alto);

            const margen = { arriba: 24, derecha: 18, abajo: 45, izquierda: 48 };
            const w = ancho - margen.izquierda - margen.derecha;
            const h = alto - margen.arriba - margen.abajo;
            const maximo = Math.max(...datos.map(d => d.valor), 1);
            const tema = coloresGrafico();
            ctx.font = '11px Inter, sans-serif';
            for (let i = 0; i <= 4; i++) {
                const y = margen.arriba + h - h * i / 4;
                ctx.strokeStyle = tema.cuadricula;
                ctx.beginPath(); ctx.moveTo(margen.izquierda, y); ctx.lineTo(ancho - margen.derecha, y); ctx.stroke();
                ctx.fillStyle = tema.texto; ctx.textAlign = 'right';
                ctx.fillText(`Q${Math.round(maximo * i / 4)}`, margen.izquierda - 7, y + 4);
            }

            const puntos = datos.map((dato, i) => ({
                x: margen.izquierda + (datos.length === 1 ? w / 2 : i * w / (datos.length - 1)),
                y: margen.arriba + h - dato.valor / maximo * h,
                ...dato
            }));
            const relleno = ctx.createLinearGradient(0, margen.arriba, 0, margen.arriba + h);
            relleno.addColorStop(0, 'rgba(22,140,134,.25)'); relleno.addColorStop(1, 'rgba(22,140,134,0)');
            ctx.beginPath(); ctx.moveTo(puntos[0].x, margen.arriba + h);
            puntos.forEach(p => ctx.lineTo(p.x, p.y));
            ctx.lineTo(puntos[puntos.length - 1].x, margen.arriba + h); ctx.closePath();
            ctx.fillStyle = relleno; ctx.fill();
            ctx.beginPath(); puntos.forEach((p, i) => i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y));
            ctx.strokeStyle = '#168c86'; ctx.lineWidth = 3; ctx.lineJoin = 'round'; ctx.stroke();
            puntos.forEach(p => {
                ctx.beginPath(); ctx.arc(p.x, p.y, 4, 0, Math.PI * 2); ctx.fillStyle = tema.fondo; ctx.fill();
                ctx.strokeStyle = '#168c86'; ctx.lineWidth = 2; ctx.stroke();
                ctx.fillStyle = tema.texto; ctx.textAlign = 'center'; ctx.font = '10px Inter, sans-serif';
                ctx.fillText(p.nombre, p.x, alto - 20);
            });
        }

        function dibujarPastel(id, datos) {
            const grafico = prepararCanvas(id);
            if (!grafico) return;
            const { ctx, ancho, alto } = grafico;
            const leyenda = document.getElementById('leyenda-pastel');
            leyenda.innerHTML = '';
            if (!datos.length) return mensajeGrafico(ctx, ancho, alto);

            const colores = ['#168c86', '#d5a84b', '#4f78a3', '#d97979', '#7667a8', '#65a46e'];
            const total = datos.reduce((suma, dato) => suma + dato.cantidad, 0);
            const radio = Math.min(ancho, alto) * .37;
            const centroX = ancho / 2, centroY = alto / 2;
            let angulo = -Math.PI / 2;
            datos.forEach((dato, i) => {
                const porcion = dato.cantidad / total * Math.PI * 2;
                ctx.beginPath(); ctx.moveTo(centroX, centroY); ctx.arc(centroX, centroY, radio, angulo, angulo + porcion); ctx.closePath();
                ctx.fillStyle = colores[i % colores.length]; ctx.fill();
                ctx.strokeStyle = coloresGrafico().fondo; ctx.lineWidth = 3; ctx.stroke();
                if (porcion > .35) {
                    const medio = angulo + porcion / 2;
                    ctx.fillStyle = '#fff'; ctx.font = '700 12px Inter, sans-serif'; ctx.textAlign = 'center';
                    ctx.fillText(`${Math.round(dato.cantidad / total * 100)}%`, centroX + Math.cos(medio) * radio * .65, centroY + Math.sin(medio) * radio * .65 + 4);
                }
                angulo += porcion;
            });
            leyenda.innerHTML = datos.map((dato, i) => `<span class="leyenda-item"><i class="leyenda-color" style="background:${colores[i % colores.length]}"></i>${escaparHTML(dato.nombre)} · ${dato.cantidad.toFixed(2).replace(/\.00$/, '')}</span>`).join('');
        }

        let temporizadorGraficos;
        window.addEventListener('resize', () => {
            if (document.getElementById('tab-graficos')?.classList.contains('hidden')) return;
            clearTimeout(temporizadorGraficos);
            temporizadorGraficos = setTimeout(renderizarGraficos, 150);
        });

        function cerrarMenuAjustes() {
            // Ajustes ahora es una sección completa; se conserva por compatibilidad.
        }

        let tabAnteriorAjustes = 'resumen';

        function volverDesdeAjustes() {
            const destino = tabAnteriorAjustes || 'resumen';
            const boton = document.querySelector(`.nav-btn[onclick*="'${destino}'"]`);
            cambiarTab(destino, boton || undefined);
        }

        function cambiarModoOscuro(activar) {
            // Activa una transición corta solo durante el cambio de tema.
            const raiz = document.documentElement;
            raiz.classList.add('cambiando-tema');
            setTimeout(() => raiz.classList.remove('cambiando-tema'), 450);
            aplicarTema(activar);
            localStorage.setItem('modoOscuro', activar ? 'true' : 'false');

            // Redibuja los lienzos con colores adecuados al tema seleccionado.
            if (!document.getElementById('tab-graficos').classList.contains('hidden')) {
                requestAnimationFrame(renderizarGraficos);
            }
        }

        function cambiarTab(tabId, elementoBtn) {
            const seccionActual = document.querySelector('main > section:not(.hidden)');
            if (tabId === 'ajustes' && seccionActual?.id !== 'tab-ajustes') {
                tabAnteriorAjustes = seccionActual?.id.replace('tab-', '') || 'resumen';
            }
            cerrarMenuAjustes();
            cerrarLectorCodigo();
            document.querySelectorAll('main > section').forEach(sec => sec.classList.add('hidden'));
            document.getElementById('tab-' + tabId).classList.remove('hidden');
            if (tabId === 'graficos') renderizarGraficos();

            document.querySelectorAll('.nav-btn').forEach(btn => {
                btn.classList.remove('text-blue-600');
                btn.classList.add('text-gray-400');
                btn.querySelector('span:last-child').classList.remove('font-semibold');
                btn.querySelector('span:last-child').classList.add('font-medium');
            });

            // Las secciones abiertas desde Ajustes no tienen botón inferior.
            if (elementoBtn) {
                elementoBtn.classList.remove('text-gray-400');
                elementoBtn.classList.add('text-blue-600');
                elementoBtn.querySelector('span:last-child').classList.remove('font-medium');
                elementoBtn.querySelector('span:last-child').classList.add('font-semibold');
            }

            // Evita conservar una posición incómoda al cambiar de pantalla.
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        function actualizarResumen() {
            let totalUnidades = 0, totalLibras = 0, costoTotal = 0, ventaTotal = 0;
            inventario.forEach(p => {
                const stock = Number(p.stock);
                const costo = Number(p.costo);
                const precio = Number(p.tieneTamanos && p.unidadVenta !== 'ambas' ? p.precioMediano : p.precio);
                const stockValido = Number.isFinite(stock) ? stock : 0;

                if (p.unidadVenta === 'libra' || p.unidadVenta === 'ambas') totalLibras += stockValido;
                else totalUnidades += stockValido;
                costoTotal += (Number.isFinite(costo) ? costo : 0) * stockValido;
                ventaTotal += (Number.isFinite(precio) ? precio : 0) * stockValido;
            });

            document.getElementById('resumen-variedad').innerText = inventario.length;
            document.getElementById('resumen-unidades').innerText = formatearCantidades(totalUnidades, totalLibras);
            const ventasRealizadas = ventas.reduce((total, venta) => {
                const importe = Number(venta.total);
                return total + (Number.isFinite(importe) ? importe : 0);
            }, 0);
            document.getElementById('resumen-costo').innerText = `Q${costoTotal.toFixed(2)}`;
            document.getElementById('resumen-venta').innerText = `Q${ventasRealizadas.toFixed(2)}`;
            document.getElementById('resumen-ganancia').innerText = `Q${(ventaTotal - costoTotal).toFixed(2)}`;
            renderizarVentasHoy();
            renderizarMenuCategorias();
        }

        function renderizarFaltantes() {
            const contenedor = document.getElementById('lista-faltantes');
            if(!contenedor) return;
            contenedor.innerHTML = '';
            
            const faltantes = inventario.filter(p => Number(p.stock) <= limiteStock(p));
            faltantes.sort((a, b) => a.stock - b.stock);

            if(faltantes.length === 0) {
                contenedor.innerHTML = `
                    <div class="col-span-full bg-green-50 p-6 rounded-2xl text-center border border-green-100 shadow-sm mt-4">
                        <div class="text-4xl mb-2">✅</div>
                        <p class="text-green-700 font-bold text-lg">¡Inventario Sano!</p>
                        <p class="text-green-600 text-sm mt-1">No tienes productos agotados ni por terminarse.</p>
                    </div>`;
                return;
            }

            faltantes.forEach(p => {
                const isAgotado = p.stock === 0;
                const bgCard = isAgotado ? 'bg-red-50 border-red-200' : 'bg-orange-50 border-orange-200';
                const textColor = isAgotado ? 'text-red-700' : 'text-orange-700';
                const icon = isAgotado ? '❌ AGOTADO' : '⚠ POR TERMINAR';

                contenedor.innerHTML += `
                    <div class="${bgCard} border p-4 rounded-xl shadow-sm flex justify-between items-center mb-1">
                        <div>
                            <span class="text-[10px] font-bold uppercase ${textColor} tracking-wider bg-white px-2 py-0.5 rounded-md shadow-sm">${icon}</span>
                            <h3 class="font-bold text-gray-800 text-lg leading-tight mt-2">${escaparHTML(p.nombre)}</h3>
                            <p class="text-xs text-gray-500 mt-1">Categoría: ${escaparHTML(p.categoria || 'Otros')}</p>
                        </div>
                        <div class="text-center bg-white px-4 py-2 rounded-lg shadow-sm border border-white/50">
                            <p class="text-[10px] text-gray-400 font-bold">STOCK</p>
                            <p class="text-2xl font-black ${textColor}">${p.stock}</p>
                        </div>
                    </div>
                `;
            });
        }

        function renderizarCatalogo() {
            cerrarAccionesCatalogo();
            const contenedor = document.getElementById('lista-catalogo');
            const campoBusqueda = document.getElementById('buscar-producto');
            const busqueda = (campoBusqueda?.value || '').trim().toLocaleLowerCase();
            contenedor.innerHTML = '';

            const categorias = [...new Set(inventario.map(p => p.categoria || 'Otros'))]
                .sort((a, b) => a.localeCompare(b, 'es', { sensitivity: 'base' }));
            if (categoriaCatalogoSeleccionada !== 'todas' && !categorias.includes(categoriaCatalogoSeleccionada)) {
                categoriaCatalogoSeleccionada = 'todas';
            }

            const filtros = document.getElementById('catalogo-categorias');
            if (filtros) {
                filtros.replaceChildren();
                [['todas', 'Todas'], ...categorias.map(categoria => [categoria, categoria])].forEach(([valor, etiqueta]) => {
                    const boton = document.createElement('button');
                    boton.type = 'button';
                    boton.className = `catalog-category-chip${categoriaCatalogoSeleccionada === valor ? ' activo' : ''}`;
                    boton.textContent = etiqueta;
                    boton.setAttribute('aria-pressed', String(categoriaCatalogoSeleccionada === valor));
                    boton.addEventListener('click', () => {
                        categoriaCatalogoSeleccionada = valor;
                        renderizarCatalogo();
                    });
                    filtros.appendChild(boton);
                });
            }

            const filtrados = inventario.filter(p => {
                const nombre = String(p.nombre || '').toLocaleLowerCase();
                const codigo = String(p.codigo || '').toLocaleLowerCase();
                const coincideCategoria = categoriaCatalogoSeleccionada === 'todas' || (p.categoria || 'Otros') === categoriaCatalogoSeleccionada;
                return coincideCategoria && (nombre.includes(busqueda) || codigo.includes(busqueda));
            });
            const contador = document.getElementById('catalogo-cantidad');
            if (contador) contador.textContent = `${filtrados.length} ${filtrados.length === 1 ? 'producto' : 'productos'}`;

            if(filtrados.length === 0) {
                const sinProductos = inventario.length === 0;
                contenedor.innerHTML = `<div class="catalog-empty-state"><span aria-hidden="true">${sinProductos ? '📦' : '🔎'}</span><strong>${sinProductos ? 'Aún no hay productos' : 'No encontramos productos'}</strong><p>${sinProductos ? 'Agrega tu primer producto para comenzar a organizar el inventario.' : 'Prueba con otro nombre, código o categoría.'}</p>${sinProductos ? '<button type="button" onclick="cambiarTab(\'nuevo\')">Agregar producto</button>' : ''}</div>`;
                return;
            }

            filtrados.forEach(p => {
                const bgStock = p.stock === 0 ? 'bg-red-100 text-red-700' : p.stock <= limiteStock(p) ? 'bg-orange-100 text-orange-700' : 'bg-green-100 text-green-700';
                
                contenedor.innerHTML += `
                    <div class="bg-white p-5 rounded-2xl shadow-sm border border-gray-100">
                        <div class="flex justify-between items-start mb-3 gap-3">
                            <div class="min-w-0">
                                <span class="text-xs font-bold uppercase text-gray-400 tracking-wider">${escaparHTML(p.categoria || 'Otros')}</span>
                                <h3 class="font-bold text-gray-800 text-lg leading-tight mt-1">${escaparHTML(p.nombre)}</h3>
                                <p class="text-xs text-gray-500 mt-2 font-mono break-all">Código: ${escaparHTML(p.codigo || 'Sin código')}</p>
                            </div>
                            <div class="catalog-actions">
                                <button type="button" class="catalog-actions-trigger" onclick="alternarAccionesCatalogo(event, '${p.id}')" aria-label="Acciones para ${escaparHTML(p.nombre)}" aria-haspopup="menu" aria-expanded="false">⋮</button>
                                <div id="acciones-catalogo-${p.id}" class="catalog-actions-menu hidden" role="menu">
                                    <button type="button" class="catalog-action" role="menuitem" onclick="editarDesdeMenuCatalogo(event, '${p.id}')">
                                        <span class="catalog-action-icon" aria-hidden="true">✎</span><span>Editar producto</span>
                                    </button>
                                    <button type="button" class="catalog-action catalog-action-danger" role="menuitem" onclick="eliminarDesdeMenuCatalogo(event, '${p.id}')">
                                        <span class="catalog-action-icon" aria-hidden="true">🗑</span><span>Eliminar producto</span>
                                    </button>
                                </div>
                            </div>
                        </div>
                        
                        <div class="flex justify-between items-center mb-4">
                            <span class="text-sm text-gray-500">Costo: Q${p.costo.toFixed(2)}</span>
                            <span class="font-black text-blue-600 text-lg">${p.tieneTamanos ? `${p.unidadVenta === 'ambas' ? `Q${Number(p.precioLibra ?? p.precio).toFixed(2)}/lb · ` : ''}Med. Q${Number(p.precioMediano).toFixed(2)} · Gde. Q${Number(p.precioGrande).toFixed(2)}` : p.unidadVenta === 'ambas' ? `Q${p.precio.toFixed(2)}/lb · Q${Number(p.precioUnidad).toFixed(2)}/unidad` : `Q${p.precio.toFixed(2)} / ${p.unidadVenta === 'libra' ? 'lb' : 'unidad'}`}</span>
                        </div>

                        <div class="flex justify-between items-center bg-gray-50 p-2 rounded-xl">
                            <span class="text-xs font-bold px-3 py-1 rounded-lg ${bgStock}">Stock: ${p.stock} ${p.unidadVenta === 'unidad' ? 'unid.' : 'lb'}</span>
                            <div class="flex space-x-2">
                                <button onclick="ajustarStock('${p.id}', -1)" class="w-8 h-8 rounded-lg bg-white border border-gray-200 text-gray-700 font-bold shadow-sm active:bg-gray-100">-</button>
                                <button onclick="ajustarStock('${p.id}', 1)" class="w-8 h-8 rounded-lg bg-white border border-gray-200 text-gray-700 font-bold shadow-sm active:bg-gray-100">+</button>
                            </div>
                        </div>
                    </div>
                `;
            });
        }

        let menuCatalogoAbierto = null;

        function cerrarAccionesCatalogo() {
            if (!menuCatalogoAbierto) return;
            menuCatalogoAbierto.menu.classList.add('hidden');
            menuCatalogoAbierto.boton.setAttribute('aria-expanded', 'false');
            menuCatalogoAbierto = null;
        }

        function alternarAccionesCatalogo(event, id) {
            event.stopPropagation();
            const boton = event.currentTarget;
            const menu = document.getElementById(`acciones-catalogo-${id}`);
            const yaEstaAbierto = menuCatalogoAbierto?.menu === menu;
            cerrarAccionesCatalogo();
            if (yaEstaAbierto || !menu) return;
            menu.classList.remove('hidden');
            boton.setAttribute('aria-expanded', 'true');
            menuCatalogoAbierto = { menu, boton };
        }

        function editarDesdeMenuCatalogo(event, id) {
            event.stopPropagation();
            cerrarAccionesCatalogo();
            abrirModalEditar(id);
        }

        function eliminarDesdeMenuCatalogo(event, id) {
            event.stopPropagation();
            cerrarAccionesCatalogo();
            abrirModalEliminar(id);
        }

        document.addEventListener('click', event => {
            if (menuCatalogoAbierto && !menuCatalogoAbierto.menu.parentElement.contains(event.target)) cerrarAccionesCatalogo();
        });

        document.addEventListener('keydown', event => {
            if (event.key === 'Escape' && menuCatalogoAbierto) {
                const boton = menuCatalogoAbierto.boton;
                cerrarAccionesCatalogo();
                boton.focus();
            }
        });

        function abrirModalEditar(id) {
            const producto = inventario.find(p => p.id === id);
            if (!producto) return mostrarAviso('No se encontró el producto. Actualiza el catálogo.', 'error');

            const modal = document.getElementById('modal-editar');
            if (!modal) return mostrarAviso('No se encontró el formulario de edición. Actualiza la aplicación.', 'error');
            const asignar = (idCampo, valor) => {
                const campo = document.getElementById(idCampo);
                if (campo) campo.value = valor;
            };
            productoAEditar = id;
            const stock = Number(producto.stock) || 0;
            const costoUnitario = Number(producto.costo) || 0;
            asignar('editar-stock-minimo', limiteStock(producto));
            asignar('reposicion-cantidad', '');
            asignar('reposicion-costo', '');
            asignar('editar-codigo', producto.codigo || '');
            asignar('editar-nombre', producto.nombre || '');
            asignar('editar-unidad-venta', producto.unidadVenta || 'unidad');
            asignar('editar-stock', stock);
            asignar('editar-costo', (costoUnitario * stock).toFixed(2));
            asignar('editar-precio', Number(producto.precio) || 0);
            asignar('editar-precio-unidad', producto.precioUnidad ?? '');
            asignar('editar-tamanos', producto.tieneTamanos ? 'si' : 'no');
            asignar('editar-precio-mediano', producto.precioMediano ?? '');
            asignar('editar-precio-grande', producto.precioGrande ?? '');

            const selectorCategoria = document.getElementById('editar-categoria');
            const categoria = producto.categoria || 'Otros';
            if (selectorCategoria) {
                if (![...selectorCategoria.options].some(opcion => opcion.value === categoria)) {
                    selectorCategoria.add(new Option(categoria, categoria));
                }
                selectorCategoria.value = categoria;
            }
            // Una etiqueta auxiliar ausente no debe impedir abrir y completar el formulario.
            modal.classList.remove('hidden');
            const actualizaciones = [
                () => actualizarEtiquetasUnidadEdicion(),
                () => actualizarCamposTamanos('editar'),
                () => actualizarCostoUnitarioEdicion(),
                ...['editar-categoria', 'editar-unidad-venta', 'editar-tamanos'].map(idCampo => () => {
                    const campo = document.getElementById(idCampo);
                    if (campo) sincronizarSelectorPersonalizado(campo);
                })
            ];
            actualizaciones.forEach(actualizar => {
                try {
                    actualizar();
                } catch (error) {
                    console.warn('No se pudo actualizar un elemento auxiliar de la edición:', error);
                }
            });
        }

        function cerrarModalEditar() {
            productoAEditar = null;
            document.getElementById('modal-editar').classList.add('hidden');
            document.getElementById('form-editar').reset();
        }

        async function guardarEdicionProducto(event) {
            event.preventDefault();
            if (!productoAEditar) return;

            const codigo = document.getElementById('editar-codigo').value.trim();
            const codigoDuplicado = codigo && inventario.find(producto =>
                producto.id !== productoAEditar && String(producto.codigo || '') === codigo
            );
            if (codigoDuplicado) {
                alert(`El código ${codigo} ya pertenece a “${codigoDuplicado.nombre}”.`);
                return;
            }

            const stock = parseFloat(document.getElementById('editar-stock').value);
            const costoPaquete = parseFloat(document.getElementById('editar-costo').value);
            const precioIngresado = parseFloat(document.getElementById('editar-precio').value);
            const unidadVenta = document.getElementById('editar-unidad-venta').value;
            const precioUnidad = parseFloat(document.getElementById('editar-precio-unidad').value);
            const tieneTamanos = document.getElementById('editar-tamanos').value === 'si';
            const precioMediano = parseFloat(document.getElementById('editar-precio-mediano').value);
            const precioGrande = parseFloat(document.getElementById('editar-precio-grande').value);
            const precio = tieneTamanos && unidadVenta !== 'ambas' ? precioMediano : precioIngresado;
            const stockMinimoInput = document.getElementById('editar-stock-minimo');
            const stockMinimo = stockMinimoInput ? Number(stockMinimoInput.value) : 5;

            if ((unidadVenta === 'unidad' && !Number.isInteger(stock)) || !Number.isFinite(stockMinimo) || stockMinimo < 0) {
                mostrarAviso('Las unidades deben ser enteras y el límite de alerta válido', 'error');
                return;
            }
            const cambios = {
                codigo,
                stockMinimo,
                nombre: document.getElementById('editar-nombre').value.trim(),
                categoria: document.getElementById('editar-categoria').value,
                unidadVenta,
                stock,
                costoPaquete,
                costo: stock > 0 ? costoPaquete / stock : 0,
                precio,
                precioLibra: unidadVenta === 'ambas' ? precio : null,
                tieneTamanos,
                precioMediano: tieneTamanos ? precioMediano : null,
                precioGrande: tieneTamanos ? precioGrande : null,
                precioUnidad: unidadVenta === 'ambas' && !tieneTamanos ? precioUnidad : null,
                pesoUnidad: null
            };
            const datosAmbosInvalidos = unidadVenta === 'ambas' && !tieneTamanos && (!Number.isFinite(precioUnidad) || precioUnidad < 0);
            const tamanosInvalidos = tieneTamanos && (!Number.isFinite(precioMediano) || precioMediano < 0 || !Number.isFinite(precioGrande) || precioGrande < 0);
            const precioBaseInvalido = (!tieneTamanos || unidadVenta === 'ambas') && (!Number.isFinite(precio) || precio < 0);
            if (!cambios.nombre || !Number.isFinite(stock) || stock < 0 || !Number.isFinite(costoPaquete) || costoPaquete < 0 || precioBaseInvalido || tamanosInvalidos || datosAmbosInvalidos) {
                alert('Completa todos los campos con valores válidos.');
                return;
            }

            const boton = document.getElementById('btn-guardar-edicion');
            establecerCargaBoton(boton, true);
            try {
                const anterior = inventario.find(producto => producto.id === productoAEditar);
                const batch = db.batch();
                batch.update(coleccionUsuario('productos').doc(productoAEditar), cambios);
                const diferencia = stock - (Number(anterior?.stock) || 0);
                if (diferencia) registrarMovimiento({ productoId: productoAEditar, producto: cambios.nombre, categoria: cambios.categoria, tipo: 'ajuste', detalle: 'Cambio desde edición', cantidad: diferencia }, batch);
                await batch.commit();
                cerrarModalEditar();
                mostrarAviso('Producto actualizado correctamente', 'exito');
            } catch (error) {
                alert('No se pudo actualizar el producto: ' + error.message);
            } finally {
                establecerCargaBoton(boton, false);
            }
        }

        async function ajustarStock(id, cantidad) {
            const prod = inventario.find(p => p.id === id);
            if (!prod) return;
            const nuevoStock = Math.max(0, Number(prod.stock) + cantidad);
            const cambioReal = nuevoStock - Number(prod.stock);
            if (!cambioReal) return;
            const batch = db.batch();
            batch.update(coleccionUsuario('productos').doc(id), { stock: nuevoStock });
            registrarMovimiento({ productoId: id, producto: prod.nombre, categoria: prod.categoria || 'Otros', tipo: 'ajuste', detalle: cambioReal > 0 ? 'Entrada manual' : 'Salida manual', cantidad: cambioReal }, batch);
            await batch.commit().catch(error => mostrarAviso('No se pudo ajustar el stock', 'error'));
        }

        function abrirModalEliminar(id) {
            productoAEliminar = id;
            document.getElementById('modal-eliminar').classList.remove('hidden');
        }

        function cerrarModalEliminar() {
            productoAEliminar = null;
            document.getElementById('modal-eliminar').classList.add('hidden');
        }

        document.getElementById('btn-confirmar-eliminar').addEventListener('click', () => {
            if(productoAEliminar) {
                coleccionUsuario("productos").doc(productoAEliminar).delete().then(() => {
                    cerrarModalEliminar();
                });
            }
        });

        let streamLector = null;
        let detectorCodigo = null;
        let lectorActivo = false;
        let linternaActiva = false;
        let cuadroLector = null;
        let destinoLector = 'nuevo';
        let productoEscaneadoActual = null;
        let presentacionEscaneadaSeleccionada = null;

        async function abrirLectorCodigo(destino = 'nuevo') {
            destinoLector = destino;
            const modal = document.getElementById('modal-lector');
            const estado = document.getElementById('estado-lector');

            if (!navigator.mediaDevices?.getUserMedia) {
                alert('Este navegador no permite acceder a la cámara. Abre la aplicación en Chrome o Safari mediante una conexión segura (HTTPS).');
                return;
            }
            if (!('BarcodeDetector' in window)) {
                alert('El lector automático no está disponible en este navegador. Usa Chrome en Android o escribe el código manualmente.');
                return;
            }

            modal.classList.remove('hidden');
            estado.textContent = 'Solicitando permiso para usar la cámara…';

            try {
                const formatosDisponibles = await BarcodeDetector.getSupportedFormats();
                const formatosDeseados = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39', 'codabar', 'itf'];
                const formatos = formatosDeseados.filter(formato => formatosDisponibles.includes(formato));
                detectorCodigo = new BarcodeDetector(formatos.length ? { formats: formatos } : undefined);
                streamLector = await navigator.mediaDevices.getUserMedia({
                    audio: false,
                    video: {
                        facingMode: { ideal: 'environment' },
                        width: { ideal: 1920 },
                        height: { ideal: 1080 },
                        focusMode: { ideal: 'continuous' }
                    }
                });

                const video = document.getElementById('video-lector');
                video.srcObject = streamLector;
                await video.play();
                lectorActivo = true;
                estado.textContent = 'Apunta al código de barras.';

                const pista = streamLector.getVideoTracks()[0];
                const capacidades = pista.getCapabilities?.() || {};
                document.getElementById('btn-linterna').classList.toggle('hidden', !capacidades.torch);
                detectarCodigoEnCamara();
            } catch (error) {
                cerrarLectorCodigo();
                const mensaje = error.name === 'NotAllowedError'
                    ? 'Debes permitir el acceso a la cámara desde los ajustes del navegador.'
                    : 'No se pudo abrir la cámara. Comprueba que ninguna otra aplicación la esté usando.';
                alert(mensaje);
            }
        }

        async function detectarCodigoEnCamara() {
            if (!lectorActivo || !detectorCodigo) return;
            const video = document.getElementById('video-lector');
            try {
                if (video.readyState >= 2) {
                    const codigos = await detectorCodigo.detect(video);
                    if (codigos.length && codigos[0].rawValue) {
                        registrarCodigoEscaneado(codigos[0].rawValue);
                        return;
                    }
                }
            } catch (error) {
                console.warn('No se pudo analizar este cuadro:', error);
            }
            cuadroLector = requestAnimationFrame(detectarCodigoEnCamara);
        }

        function registrarCodigoEscaneado(valor) {
            const codigo = String(valor).trim();
            if (!codigo) return;
            const existente = inventario.find(producto => String(producto.codigo || '') === codigo);
            cerrarLectorCodigo();

            if (destinoLector === 'vender') {
                if (!existente) {
                    navigator.vibrate?.([100, 60, 100]);
                    alert(`No se encontró ningún producto con el código ${codigo}.`);
                    return;
                }
                mostrarProductoEscaneado(existente);
                navigator.vibrate?.(100);
                return;
            }

            document.getElementById('nuevo-codigo').value = codigo;
            const estado = document.getElementById('estado-codigo');
            if (existente) {
                estado.textContent = `Este código ya pertenece a “${existente.nombre}”.`;
                estado.className = 'mt-2 text-xs text-red-600 font-semibold';
                navigator.vibrate?.([100, 60, 100]);
            } else {
                estado.textContent = `✓ Código detectado: ${codigo}`;
                estado.className = 'mt-2 text-xs text-green-600 font-semibold';
                navigator.vibrate?.(100);
            }
        }

        function mostrarProductoEscaneado(producto) {
            productoEscaneadoActual = producto;
            document.getElementById('titulo-producto-escaneado').textContent = producto.nombre;
            document.getElementById('codigo-producto-escaneado').textContent = `Código: ${producto.codigo || 'Sin código'}`;
            const ventaDoble = producto.unidadVenta === 'ambas';
            const tieneTamanos = Boolean(producto.tieneTamanos);
            document.getElementById('precio-producto-escaneado').innerHTML = tieneTamanos
                ? `${ventaDoble ? `Q${Number(producto.precioLibra ?? producto.precio).toFixed(2)} / lb<br>` : ''}Mediano Q${Number(producto.precioMediano).toFixed(2)}<br><span class="text-2xl text-blue-600">Grande Q${Number(producto.precioGrande).toFixed(2)}</span>`
                : ventaDoble
                    ? `Q${Number(producto.precio).toFixed(2)} / lb<br><span class="text-2xl text-blue-600">Q${Number(producto.precioUnidad).toFixed(2)} / unidad</span>`
                    : `Q${Number(producto.precio).toFixed(2)} / ${producto.unidadVenta === 'libra' ? 'libra' : 'unidad'}`;
            document.getElementById('stock-producto-escaneado').textContent = producto.stock > 0
                ? `Disponible después del carrito: ${Number(stockDisponibleProducto(producto.id).toFixed(2))} ${producto.unidadVenta === 'unidad' ? 'unidades' : 'lb'}`
                : 'Producto agotado';

            const cantidad = document.getElementById('cantidad-producto-escaneado');
            cantidad.value = '1';
            if (ventaDoble) {
                cantidad.dataset.modo = 'ambas';
                cantidad.step = '0.01';
                cantidad.min = '0.01';
                cantidad.max = Number(producto.stock);
                document.getElementById('label-cantidad-escaneada').textContent = 'Cantidad a agregar';
                document.getElementById('ayuda-cantidad-escaneada').textContent = 'Elige primero la presentación y luego indica la cantidad.';
            } else {
                configurarCantidadEscaneada(producto.unidadVenta);
            }

            presentacionEscaneadaSeleccionada = (!ventaDoble && !tieneTamanos)
                ? { modoVenta: producto.unidadVenta, tamano: '' }
                : null;
            cantidad.disabled = !presentacionEscaneadaSeleccionada;
            const boton = document.getElementById('btn-agregar-escaneado');
            const opciones = document.getElementById('opciones-producto-escaneado');
            const opcionesTamano = document.getElementById('opciones-tamano-escaneado');
            opciones.classList.toggle('hidden', !ventaDoble || tieneTamanos);
            opcionesTamano.classList.toggle('hidden', !tieneTamanos);
            opcionesTamano.classList.toggle('three-options', tieneTamanos && ventaDoble);
            document.getElementById('bloque-presentacion-escaneada').classList.toggle('hidden', !ventaDoble && !tieneTamanos);
            boton.classList.remove('hidden');

            const botonLibra = document.getElementById('btn-agregar-libra-escaneada');
            const botonUnidad = document.getElementById('btn-agregar-unidad-escaneada');
            botonLibra.querySelector('small').textContent = `Q${Number(producto.precioLibra ?? producto.precio).toFixed(2)} / lb`;
            botonUnidad.querySelector('small').textContent = `Q${Number(producto.precioUnidad).toFixed(2)} c/u`;
            botonLibra.onclick = () => seleccionarPresentacionEscaneada('libra', '', botonLibra);
            botonUnidad.onclick = () => seleccionarPresentacionEscaneada('unidad', '', botonUnidad);
            const modoTamano = producto.unidadVenta === 'ambas' ? 'unidad' : producto.unidadVenta;
            const botonLibraTamano = document.getElementById('btn-agregar-libra-tamano-escaneada');
            const botonMediano = document.getElementById('btn-agregar-mediano-escaneado');
            const botonGrande = document.getElementById('btn-agregar-grande-escaneado');
            botonLibraTamano.classList.toggle('hidden', !ventaDoble);
            botonLibraTamano.querySelector('small').textContent = `Q${Number(producto.precioLibra ?? producto.precio).toFixed(2)} / lb`;
            botonLibraTamano.onclick = () => seleccionarPresentacionEscaneada('libra', '', botonLibraTamano);
            botonMediano.querySelector('small').textContent = `Q${Number(producto.precioMediano).toFixed(2)} c/u`;
            botonGrande.querySelector('small').textContent = `Q${Number(producto.precioGrande).toFixed(2)} c/u`;
            botonMediano.onclick = () => seleccionarPresentacionEscaneada(modoTamano, 'mediano', botonMediano);
            botonGrande.onclick = () => seleccionarPresentacionEscaneada(modoTamano, 'grande', botonGrande);
            document.querySelectorAll('#modal-producto-escaneado .product-choice-button').forEach(opcion => opcion.classList.remove('seleccionada'));
            validarCantidadEscaneada();
            document.getElementById('modal-producto-escaneado').classList.remove('hidden');
            setTimeout(() => {
                if (!cantidad.disabled) cantidad.focus();
            }, 100);
        }

        function configurarCantidadEscaneada(modoVenta) {
            const producto = productoEscaneadoActual;
            if (!producto) return;
            const esLibra = modoVenta === 'libra';
            const campo = document.getElementById('cantidad-producto-escaneado');
            campo.step = esLibra ? '0.01' : '1';
            campo.min = esLibra ? '0.01' : '1';
            const maximo = esLibra
                ? stockDisponibleProducto(producto.id)
                : Math.floor(stockDisponibleProducto(producto.id));
            campo.max = Math.max(0, maximo);
            document.getElementById('label-cantidad-escaneada').textContent = esLibra ? 'Libras a agregar' : 'Unidades a agregar';
            document.getElementById('ayuda-cantidad-escaneada').textContent = esLibra
                ? `Puedes ingresar decimales. Máximo: ${maximo.toFixed(2)} lb.`
                : `Ingresa una cantidad entera. Máximo: ${maximo}.`;
            validarCantidadEscaneada();
        }

        function validarCantidadEscaneada() {
            const producto = productoEscaneadoActual;
            if (!producto) return false;
            const campo = document.getElementById('cantidad-producto-escaneado');
            const cantidad = Number(campo.value);
            const maximo = stockDisponibleProducto(producto.id);
            const esLibra = presentacionEscaneadaSeleccionada?.modoVenta === 'libra';
            const valida = maximo > 0 && Number.isFinite(cantidad) && cantidad >= (esLibra ? 0.01 : 1) && cantidad <= maximo && (esLibra || Number.isInteger(cantidad));
            ['btn-agregar-libra-escaneada', 'btn-agregar-unidad-escaneada', 'btn-agregar-libra-tamano-escaneada', 'btn-agregar-mediano-escaneado', 'btn-agregar-grande-escaneado'].forEach(id => {
                const boton = document.getElementById(id);
                boton.disabled = maximo <= 0;
                boton.classList.toggle('opacity-50', maximo <= 0);
                boton.classList.toggle('cursor-not-allowed', maximo <= 0);
            });
            const botonAceptar = document.getElementById('btn-agregar-escaneado');
            const puedeAceptar = valida && Boolean(presentacionEscaneadaSeleccionada);
            botonAceptar.disabled = !puedeAceptar;
            botonAceptar.classList.toggle('opacity-50', !puedeAceptar);
            botonAceptar.classList.toggle('cursor-not-allowed', !puedeAceptar);
            return valida;
        }

        function seleccionarPresentacionEscaneada(modoVenta, tamano, boton) {
            presentacionEscaneadaSeleccionada = { modoVenta, tamano };
            document.getElementById('cantidad-producto-escaneado').disabled = false;
            document.querySelectorAll('#modal-producto-escaneado .product-choice-button').forEach(opcion => opcion.classList.remove('seleccionada'));
            boton.classList.add('seleccionada');
            configurarCantidadEscaneada(modoVenta);
        }

        function aceptarProductoEscaneado() {
            if (!productoEscaneadoActual) return;
            if (!presentacionEscaneadaSeleccionada) {
                mostrarAviso('Selecciona una presentación', 'error');
                return;
            }
            agregarEscaneado(
                productoEscaneadoActual.id,
                presentacionEscaneadaSeleccionada.modoVenta,
                presentacionEscaneadaSeleccionada.tamano
            );
        }

        function agregarEscaneado(id, modoVenta, tamano = '') {
            configurarCantidadEscaneada(modoVenta);
            if (!validarCantidadEscaneada()) {
                alert('Ingresa una cantidad válida que no supere las existencias.');
                return;
            }
            const cantidad = Number(document.getElementById('cantidad-producto-escaneado').value);
            agregarAlCarrito(id, modoVenta, cantidad, tamano);
            cerrarProductoEscaneado();
        }

        function cerrarProductoEscaneado() {
            productoEscaneadoActual = null;
            presentacionEscaneadaSeleccionada = null;
            document.getElementById('modal-producto-escaneado').classList.add('hidden');
        }

        async function alternarLinterna() {
            const pista = streamLector?.getVideoTracks()[0];
            if (!pista) return;
            try {
                linternaActiva = !linternaActiva;
                await pista.applyConstraints({ advanced: [{ torch: linternaActiva }] });
                document.getElementById('btn-linterna').textContent = linternaActiva ? '🔦 Apagar' : '🔦 Luz';
            } catch (error) {
                linternaActiva = false;
            }
        }

        function cerrarLectorCodigo() {
            lectorActivo = false;
            if (cuadroLector) cancelAnimationFrame(cuadroLector);
            cuadroLector = null;
            streamLector?.getTracks().forEach(pista => pista.stop());
            streamLector = null;
            detectorCodigo = null;
            linternaActiva = false;
            const video = document.getElementById('video-lector');
            if (video) video.srcObject = null;
            document.getElementById('btn-linterna')?.classList.add('hidden');
            document.getElementById('modal-lector')?.classList.add('hidden');
        }

        document.addEventListener('visibilitychange', () => {
            if (document.hidden) cerrarLectorCodigo();
        });
    
        function prepararMejorasInterfaz() {
            // 1. Proteger la sección de resumen de manera completamente segura
            const resumen = document.getElementById('tab-resumen');
            const listaVentasHoy = document.getElementById('lista-ventas-hoy');
            const selectorDia = document.getElementById('categoria-fecha-dia');

            if (listaVentasHoy && selectorDia && resumen) {
                const diaria = listaVentasHoy.parentElement;
                const contenedorSelector = selectorDia.parentElement;
                if (diaria && contenedorSelector) {
                    if (diaria.firstElementChild && diaria.firstElementChild !== contenedorSelector) {
                        try {
                            diaria.insertBefore(contenedorSelector, diaria.firstElementChild);
                        } catch (e) {
                            diaria.appendChild(contenedorSelector);
                        }
                    }
                    diaria.id = 'resumen-diario';
                    if (!resumen.contains(diaria) && resumen.children[1]) {
                        try {
                            resumen.insertBefore(diaria, resumen.children[1]);
                        } catch (e) {
                            resumen.appendChild(diaria);
                        }
                    }
                }
            }

            // 2. Textos de unidades con validación de existencia
            const unidadesEl = document.getElementById('resumen-unidades');
            if (unidadesEl && unidadesEl.previousElementSibling) {
                unidadesEl.previousElementSibling.textContent = 'Existencias';
            }
            const ventasHoyUnidadesEl = document.getElementById('ventas-hoy-unidades');
            if (ventasHoyUnidadesEl && ventasHoyUnidadesEl.nextElementSibling) {
                ventasHoyUnidadesEl.nextElementSibling.textContent = 'Cantidades vendidas';
            }

            // 3. Bloques de escaneo protegidos
            const cantidadEscaneada = document.getElementById('cantidad-producto-escaneado');
            if (cantidadEscaneada && cantidadEscaneada.parentElement) {
                const cantidad = cantidadEscaneada.parentElement;
                cantidad.id = 'bloque-cantidad-escaneada';
                const stepCantidad = cantidad.querySelector('.product-choice-step');
                if (stepCantidad) stepCantidad.innerHTML = '<span>2</span> Indica la cantidad';
            }

            const presentacionEscaneada = document.getElementById('bloque-presentacion-escaneada');
            if (presentacionEscaneada && presentacionEscaneada.parentElement && cantidadEscaneada) {
                const presentacion = presentacionEscaneada;
                const cantidad = cantidadEscaneada.parentElement;
                if (presentacion.parentElement === cantidad.parentElement) {
                    try {
                        if (cantidad.previousSibling !== presentacion) {
                            presentacion.parentElement.insertBefore(presentacion, cantidad);
                        }
                    } catch (e) {
                        // Ignorar conflicto de nodos
                    }
                }
                const stepPresentacion = presentacion.querySelector('.product-choice-step');
                if (stepPresentacion) stepPresentacion.innerHTML = '<span>1</span> Elige la presentación';
            }

            // 4. Agregar campos de stock mínimo dinámicamente si el formulario existe
            ['nuevo', 'editar'].forEach(prefijo => {
                const form = document.getElementById(`form-${prefijo}`);
                if (form && !document.getElementById(`${prefijo}-stock-minimo`)) {
                    const bloque = document.createElement('div');
                    bloque.className = 'mb-5';
                    bloque.innerHTML = `<label for="${prefijo}-stock-minimo" class="block text-sm mb-2">Avisar cuando el stock llegue a</label><input id="${prefijo}-stock-minimo" type="number" min="0" step="0.01" value="5" class="w-full p-3 border border-gray-200" required>`;
                    const btnSubmit = form.querySelector('button[type="submit"]');
                    if (btnSubmit && btnSubmit.parentNode === form) {
                        form.insertBefore(bloque, btnSubmit);
                    } else {
                        form.appendChild(bloque);
                    }
                }
            });

            // 5. Agregar reposición al formulario de edición si existe
            const formEditar = document.getElementById('form-editar');
            if (formEditar && !document.getElementById('reposicion-cantidad')) {
                const reposicion = document.createElement('div');
                reposicion.className = 'mb-5';
                reposicion.innerHTML = '<details><summary class="font-bold text-teal-600">Registrar nueva compra</summary><p class="text-xs text-gray-500 my-2">Se suma al stock y calcula el costo promedio. No cambia el costo de la compra anterior.</p><label for="reposicion-cantidad">Cantidad recibida</label><input id="reposicion-cantidad" type="number" min="0.01" step="0.01" class="w-full p-3 mb-2"><label for="reposicion-costo">Costo de esta compra (Q)</label><input id="reposicion-costo" type="number" min="0" step="0.01" class="w-full p-3 mb-2"><button type="button" onclick="aplicarReposicionEdicion()" class="bg-teal-600 text-white p-3 w-full">Aplicar compra a la edición</button><p class="text-xs text-gray-500 mt-2">Después pulsa Guardar para confirmar.</p></details>';
                const btnSubmit = formEditar.querySelector('button[type="submit"]');
                if (btnSubmit && btnSubmit.parentNode === formEditar) {
                    formEditar.insertBefore(reposicion, btnSubmit);
                } else {
                    formEditar.appendChild(reposicion);
                }
            }

            // 6. Etiqueta de costo en edición
            const costoEdicion = document.getElementById('editar-costo');
            if (costoEdicion) {
                const etiquetaCosto = document.querySelector('label[for="editar-costo"]') || costoEdicion.closest('.relative')?.previousElementSibling;
                if (etiquetaCosto) etiquetaCosto.textContent = 'Costo del stock restante (Q)';
            }

            if (typeof actualizarEtiquetasUnidad === 'function') {
                actualizarEtiquetasUnidad();
            }
        }
        
        function aplicarReposicionEdicion() {
            const cantidad = Number(document.getElementById('reposicion-cantidad').value);
            const costoCampo = document.getElementById('reposicion-costo');
            const costo = Number(costoCampo.value);
            const esUnidad = document.getElementById('editar-unidad-venta').value === 'unidad';
            if (!Number.isFinite(cantidad) || cantidad <= 0 || (esUnidad && !Number.isInteger(cantidad)) || !costoCampo.value || !Number.isFinite(costo) || costo < 0) {
                mostrarAviso('Indica cantidad y costo válidos para la compra', 'error');
                return;
            }
            const stockCampo = document.getElementById('editar-stock');
            const costoTotal = document.getElementById('editar-costo');
            stockCampo.value = Number((Number(stockCampo.value) + cantidad).toFixed(2));
            costoTotal.value = (Number(costoTotal.value) + costo).toFixed(2);
            document.getElementById('reposicion-cantidad').value = '';
            costoCampo.value = '';
            actualizarCostoUnitarioEdicion();
            mostrarAviso('Compra aplicada; guarda la edición para confirmar');
        }

        prepararMejorasInterfaz();

        function actualizarCamposTamanos(prefijo) {
            const tieneTamanos = document.getElementById(`${prefijo}-tamanos`).value === 'si';
            const ventaDoble = document.getElementById(`${prefijo}-unidad-venta`).value === 'ambas';
            document.getElementById(`${prefijo}-precios-tamanos`).classList.toggle('hidden', !tieneTamanos);
            // En venta doble, el precio base sigue visible porque corresponde al precio por libra.
            document.getElementById(`${prefijo}-precio-base-wrap`).classList.toggle('hidden', tieneTamanos && !ventaDoble);
            // Con tamaños, cada unidad usa el precio mediano o grande; no hace falta otro precio por unidad.
            document.getElementById(`${prefijo}-datos-ambas`).classList.toggle('hidden', !ventaDoble || tieneTamanos);
            document.getElementById(`${prefijo}-precio-unidad`).required = ventaDoble && !tieneTamanos;
            document.getElementById(`${prefijo}-precio`).required = !tieneTamanos || ventaDoble;
            document.getElementById(`${prefijo}-precio-mediano`).required = tieneTamanos;
            document.getElementById(`${prefijo}-precio-grande`).required = tieneTamanos;
            document.getElementById(`${prefijo}-precio`).disabled = tieneTamanos && !ventaDoble;
            document.getElementById(`${prefijo}-precio-unidad`).disabled = !ventaDoble || tieneTamanos;
            document.getElementById(`${prefijo}-precio-mediano`).disabled = !tieneTamanos;
            document.getElementById(`${prefijo}-precio-grande`).disabled = !tieneTamanos;
        }

        function actualizarEtiquetasUnidad() {
            const tipo = document.getElementById('nuevo-unidad-venta').value;
            const usaLibras = tipo === 'libra' || tipo === 'ambas';
            const stock = document.getElementById('nuevo-stock');
            stock.step = usaLibras ? '0.01' : '1';
            stock.min = usaLibras ? '0.01' : '1';
            stock.inputMode = usaLibras ? 'decimal' : 'numeric';
            document.getElementById('nuevo-stock-label').textContent = usaLibras ? 'Libras disponibles' : 'Unidades disponibles';
            document.getElementById('nuevo-precio-label').textContent = usaLibras ? '¿A cuánto venderás cada libra?' : '¿A cuánto venderás cada unidad?';
            document.getElementById('nuevo-costo-unidad-texto').textContent = usaLibras ? 'libra' : 'unidad';
            document.getElementById('nuevo-unidad-ayuda').textContent = tipo === 'ambas'
                ? 'Registra las existencias disponibles; una venta por unidad descuenta 1 y una venta por libra descuenta la cantidad indicada.'
                : usaLibras ? 'Puedes registrar cantidades con decimales, por ejemplo 12.5 libras.' : 'Existencias disponibles en unidades.';
            document.getElementById('nuevo-datos-ambas').classList.toggle('hidden', tipo !== 'ambas');
            actualizarCamposTamanos('nuevo');
        }

        function actualizarEtiquetasUnidadEdicion() {
            const tipo = document.getElementById('editar-unidad-venta').value;
            const usaLibras = tipo === 'libra' || tipo === 'ambas';
            document.getElementById('editar-stock').step = usaLibras ? '0.01' : '1';
            document.getElementById('reposicion-cantidad').step = usaLibras ? '0.01' : '1';
            document.getElementById('editar-stock-label').textContent = usaLibras ? 'Libras disponibles' : 'Unidades disponibles';
            document.getElementById('editar-precio-label').textContent = usaLibras ? 'Precio de venta por libra' : 'Precio de venta por unidad';
            document.getElementById('editar-costo-unidad-texto').textContent = usaLibras ? 'libra' : 'unidad';
            document.getElementById('editar-datos-ambas').classList.toggle('hidden', tipo !== 'ambas');
            actualizarCamposTamanos('editar');
        }

        function actualizarCostoUnitario() {
            const unidades = parseFloat(document.getElementById('nuevo-stock').value) || 0;
            const costoPaquete = parseFloat(document.getElementById('nuevo-costo').value) || 0;
            const costoUnitario = unidades > 0 ? costoPaquete / unidades : 0;
            document.getElementById('nuevo-costo-unitario').textContent = `Q${costoUnitario.toFixed(2)}`;
        }

        function actualizarCostoUnitarioEdicion() {
            const unidades = parseFloat(document.getElementById('editar-stock').value) || 0;
            const costoPaquete = parseFloat(document.getElementById('editar-costo').value) || 0;
            const costoUnitario = unidades > 0 ? costoPaquete / unidades : 0;
            document.getElementById('editar-costo-unitario').textContent = `Q${costoUnitario.toFixed(2)}`;
        }

        async function guardarProducto(e) {
            e.preventDefault();
            const codigo = document.getElementById('nuevo-codigo').value.trim();
            const existente = codigo && inventario.find(producto => String(producto.codigo || '') === codigo);
            if (existente) {
                alert(`El código ${codigo} ya pertenece a “${existente.nombre}”.`);
                return;
            }

            const stock = parseFloat(document.getElementById('nuevo-stock').value);
            const costoPaquete = parseFloat(document.getElementById('nuevo-costo').value);
            const precioIngresado = parseFloat(document.getElementById('nuevo-precio').value);
            const unidadVenta = document.getElementById('nuevo-unidad-venta').value;
            const precioUnidad = parseFloat(document.getElementById('nuevo-precio-unidad').value);
            const tieneTamanos = document.getElementById('nuevo-tamanos').value === 'si';
            const precioMediano = parseFloat(document.getElementById('nuevo-precio-mediano').value);
            const precioGrande = parseFloat(document.getElementById('nuevo-precio-grande').value);
            const precio = tieneTamanos && unidadVenta !== 'ambas' ? precioMediano : precioIngresado;
            const nombre = document.getElementById('nuevo-nombre').value.trim();
            const stockMinimo = Number(document.getElementById('nuevo-stock-minimo').value);
            if (!nombre || (unidadVenta === 'unidad' && !Number.isInteger(stock)) || !Number.isFinite(stockMinimo) || stockMinimo < 0) {
                mostrarAviso('Revisa el nombre, las unidades enteras y el límite de alerta', 'error');
                return;
            }
            const datosAmbosInvalidos = unidadVenta === 'ambas' && !tieneTamanos && (!Number.isFinite(precioUnidad) || precioUnidad < 0);
            const tamanosInvalidos = tieneTamanos && (!Number.isFinite(precioMediano) || precioMediano < 0 || !Number.isFinite(precioGrande) || precioGrande < 0);
            const precioBaseInvalido = (!tieneTamanos || unidadVenta === 'ambas') && (!Number.isFinite(precio) || precio < 0);
            if (!Number.isFinite(stock) || stock <= 0 || !Number.isFinite(costoPaquete) || costoPaquete < 0 || precioBaseInvalido || tamanosInvalidos || datosAmbosInvalidos) {
                alert('Ingresa existencias, costo y precios válidos.');
                return;
            }

            const nuevo = {
                codigo,
                stockMinimo,
                nombre: document.getElementById('nuevo-nombre').value.trim(),
                categoria: document.getElementById('nuevo-categoria').value,
                unidadVenta,
                costo: costoPaquete / stock,
                costoPaquete,
                precio,
                precioLibra: unidadVenta === 'ambas' ? precio : null,
                tieneTamanos,
                precioMediano: tieneTamanos ? precioMediano : null,
                precioGrande: tieneTamanos ? precioGrande : null,
                precioUnidad: unidadVenta === 'ambas' && !tieneTamanos ? precioUnidad : null,
                stock
            };

            const botonGuardar = document.querySelector('#form-nuevo button[type="submit"]');
            establecerCargaBoton(botonGuardar, true);
            try {
                const referenciaProducto = coleccionUsuario('productos').doc();
                const batch = db.batch();
                batch.set(referenciaProducto, nuevo);
                registrarMovimiento({ productoId: referenciaProducto.id, producto: nuevo.nombre, categoria: nuevo.categoria, tipo: 'entrada', detalle: 'Registro inicial', cantidad: stock }, batch);
                await batch.commit();
                document.getElementById('form-nuevo').reset();
                actualizarEtiquetasUnidad();
                actualizarCamposTamanos('nuevo');
                actualizarCostoUnitario();
                const estado = document.getElementById('estado-codigo');
                estado.textContent = 'Puedes usar la cámara trasera o escribir el número.';
                estado.className = 'mt-2 text-xs text-gray-500';
                document.getElementById('nombre-producto-agregado').textContent = `“${nuevo.nombre}” se guardó correctamente.`;
                document.getElementById('modal-producto-agregado').classList.remove('hidden');
            } catch (error) {
                alert('No se pudo guardar el producto: ' + error.message);
            } finally {
                establecerCargaBoton(botonGuardar, false);
            }
        }

        function cerrarProductoAgregado() {
            document.getElementById('modal-producto-agregado').classList.add('hidden');
            // No se enfoca ningún campo para que el teclado del móvil no se abra solo.
            if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        function stockDisponibleProducto(id) {
            const producto = inventario.find(p => p.id === id);
            const reservado = carrito.filter(item => item.id === id)
                .reduce((total, item) => total + item.cantidad * (item.descuentoStock || 1), 0);
            return Math.max(0, (Number(producto?.stock) || 0) - reservado);
        }

        function limiteStock(producto) {
            const limite = Number(producto.stockMinimo ?? 5);
            return Number.isFinite(limite) && limite >= 0 ? limite : 5;
        }

        function renderizarListaVenta() {
            const contenedor = document.getElementById('lista-vender');
            contenedor.innerHTML = '';
            const busqueda = (document.getElementById('buscar-venta')?.value || '').trim().toLowerCase();
            const conStock = inventario.filter(p => p.stock > 0 && (
                String(p.nombre || '').toLowerCase().includes(busqueda) ||
                String(p.codigo || '').toLowerCase().includes(busqueda)
            ));
            
            if(conStock.length === 0) {
                if (busqueda) {
                    contenedor.innerHTML = '<div class="sale-empty-state"><span class="sale-empty-icon" aria-hidden="true">⌕</span><strong>No encontramos ese producto</strong><p>Prueba con otro nombre o código.</p></div>';
                } else if (inventario.length === 0) {
                    contenedor.innerHTML = '<div class="sale-empty-state"><span class="sale-empty-icon" aria-hidden="true">🧺</span><strong>Aún no hay productos</strong><p>Agrega un producto para empezar a registrar ventas.</p><button type="button" onclick="cambiarTab(\'nuevo\')">Agregar primer producto</button></div>';
                } else {
                    contenedor.innerHTML = '<div class="sale-empty-state"><span class="sale-empty-icon" aria-hidden="true">📦</span><strong>No hay productos disponibles</strong><p>Revisa el inventario para ver cuáles necesitan reposición.</p><button type="button" onclick="cambiarTab(\'catalogo\', document.getElementById(\'nav-catalogo\'))">Ver inventario</button></div>';
                }
                return;
            }

            conStock.forEach(p => {
                const ventaDoble = p.unidadVenta === 'ambas';
                const requiereEleccion = ventaDoble || p.tieneTamanos;
                const unidad = p.unidadVenta === 'libra' ? 'lb' : 'unidad';
                contenedor.innerHTML += `
                    <div onclick="${requiereEleccion ? `mostrarProductoEscaneado(inventario.find(producto => producto.id === '${p.id}'))` : `agregarAlCarrito('${p.id}')`}" class="flex-shrink-0 w-36 bg-white border border-gray-200 rounded-xl p-3 text-center shadow-sm active:border-blue-500 cursor-pointer">
                        <p class="text-sm font-bold text-gray-700 truncate">${escaparHTML(p.nombre)}</p>
                        <p class="text-blue-600 font-black mt-1">${p.tieneTamanos ? `${ventaDoble ? `Q${Number(p.precioLibra ?? p.precio).toFixed(2)}/lb<br>` : ''}Med. Q${Number(p.precioMediano).toFixed(2)}<br>Gde. Q${Number(p.precioGrande).toFixed(2)}` : ventaDoble ? `Q${p.precio.toFixed(2)}/lb<br>Q${Number(p.precioUnidad).toFixed(2)}/unidad` : `Q${p.precio.toFixed(2)} / ${unidad}`}</p>
                        <p class="text-[10px] text-gray-400 mt-1">Queda: ${Number(stockDisponibleProducto(p.id).toFixed(2))} ${p.unidadVenta === 'unidad' ? '' : 'lb'}</p>
                    </div>
                `;
            });
        }

        function agregarAlCarrito(id, modoVenta, cantidadSolicitada = 1, tamano = '') {
            const prod = inventario.find(p => p.id === id);
            if(!prod || prod.stock <= 0) return;
            const modo = prod.unidadVenta === 'ambas' ? modoVenta : prod.unidadVenta;
            // La venta por libra no necesita elegir tamaño; mediano y grande aplican a unidades.
            if (prod.tieneTamanos && modo !== 'libra' && !['mediano', 'grande'].includes(tamano)) return mostrarProductoEscaneado(prod);
            if (prod.unidadVenta === 'ambas' && !['libra', 'unidad'].includes(modo)) return mostrarProductoEscaneado(prod);
            const claveCarrito = `${id}-${modo}-${tamano || 'normal'}`;
            const itemExistente = carrito.find(item => item.claveCarrito === claveCarrito);
            const descuentoStock = 1;
            const cantidad = Number(cantidadSolicitada);
            if (modo !== 'libra' && !Number.isInteger(cantidad)) {
                mostrarAviso('Ingresa una cantidad entera de unidades', 'error');
                return;
            }
            const incremento = cantidad;
            if (!Number.isFinite(incremento) || incremento <= 0) return;
            const stockUsado = incremento * descuentoStock;
            const stockReservado = carrito
                .filter(item => item.id === id)
                .reduce((total, item) => total + item.cantidad * (item.descuentoStock || 1), 0);

            if(itemExistente) {
                if(stockReservado + stockUsado <= prod.stock) itemExistente.cantidad += incremento;
                else alert('Stock máximo alcanzado');
            } else if (stockReservado + stockUsado <= prod.stock) {
                carrito.push({
                    ...prod,
                    claveCarrito,
                    modoVenta: modo,
                    tamano,
                    cantidad: incremento,
                    precio: tamano === 'grande'
                        ? Number(prod.precioGrande)
                        : tamano === 'mediano'
                            ? Number(prod.precioMediano)
                            : modo === 'unidad' && prod.unidadVenta === 'ambas'
                                ? Number(prod.precioUnidad)
                                : modo === 'libra' && prod.unidadVenta === 'ambas'
                                    ? Number(prod.precioLibra ?? prod.precio)
                                    : Number(prod.precio),
                    descuentoStock
                });
            } else {
                alert('No hay suficiente stock para esa cantidad.');
            }
            renderizarCarrito();
        }

        function cambiarCantidadCarrito(index, valor) {
            const item = carrito[index];
            const cantidad = Number(valor);
            if (!item || !Number.isFinite(cantidad)) return;
            const esPeso = (item.modoVenta || item.unidadVenta) === 'libra';
            const reservadoPorOtros = carrito.reduce((total, otro, otroIndice) =>
                otroIndice !== index && otro.id === item.id ? total + otro.cantidad * (otro.descuentoStock || 1) : total, 0);
            const disponible = Math.max(0, item.stock - reservadoPorOtros);
            const maximo = esPeso ? disponible : Math.floor(disponible / (item.descuentoStock || 1));
            item.cantidad = Math.min(maximo, Math.max(esPeso ? 0.01 : 1, esPeso ? cantidad : Math.floor(cantidad)));
            renderizarCarrito();
        }

        // Actualiza subtotal y total mientras se escribe, sin redibujar el carrito (así el campo no pierde el foco).
        function actualizarCantidadCarritoEnVivo(index, campo) {
            const item = carrito[index];
            if (!item) return;
            const cantidad = Number(campo.value);
            if (!Number.isFinite(cantidad) || cantidad <= 0) return;

            const reservadoPorOtros = carrito.reduce((total, otro, otroIndice) =>
                otroIndice !== index && otro.id === item.id ? total + otro.cantidad * (otro.descuentoStock || 1) : total, 0);
            const maximo = Math.max(0, item.stock - reservadoPorOtros);
            item.cantidad = Math.min(cantidad, maximo);
            if (cantidad > maximo) campo.value = maximo;

            const subtotal = document.getElementById(`carrito-subtotal-${index}`);
            if (subtotal) subtotal.textContent = `Q${(item.precio * item.cantidad).toFixed(2)}`;

            totalVentaActual = carrito.reduce((suma, actual) => suma + actual.precio * actual.cantidad, 0);
            document.getElementById('carrito-total').innerText = `Q${totalVentaActual.toFixed(2)}`;
        }

        function renderizarCarrito() {
            renderizarListaVenta();
            const contenedor = document.getElementById('carrito-items');
            totalVentaActual = 0;

            const badge = document.getElementById('carrito-cantidad');
            const botonVaciar = document.getElementById('btn-vaciar-carrito');
            badge.textContent = carrito.length;
            badge.classList.toggle('hidden', carrito.length === 0);
            botonVaciar.classList.toggle('hidden', carrito.length === 0);

            if(carrito.length === 0) {
                contenedor.innerHTML = '<div class="cart-empty"><span aria-hidden="true">🛒</span><p>El carrito está vacío</p><small>Toca un producto o escanea su código para agregarlo.</small></div>';
                document.getElementById('carrito-total').innerText = 'Q0.00';
                return;
            }

            contenedor.innerHTML = carrito.map((item, index) => {
                const subtotal = item.precio * item.cantidad;
                totalVentaActual += subtotal;
                const esLibra = (item.modoVenta || item.unidadVenta) === 'libra';
                const nombre = escaparHTML(item.nombre) + (item.tamano ? ` · ${item.tamano[0].toUpperCase()}${item.tamano.slice(1)}` : '');
                const control = esLibra ? `
                    <div class="cart-weight">
                        <input type="number" min="0.01" max="${item.stock}" step="0.01" inputmode="decimal" value="${item.cantidad}" oninput="actualizarCantidadCarritoEnVivo(${index}, this)" onchange="cambiarCantidadCarrito(${index}, this.value)" aria-label="Peso vendido en libras de ${escaparHTML(item.nombre)}">
                        <span>lb</span>
                    </div>
                    <p class="cart-item-price">Q${item.precio.toFixed(2)} por libra</p>
                ` : `
                    <div class="cart-stepper">
                        <button type="button" onclick="cambiarCantidadCarrito(${index}, ${item.cantidad - 1})" aria-label="Quitar una unidad">−</button>
                        <strong>${item.cantidad}</strong>
                        <button type="button" onclick="cambiarCantidadCarrito(${index}, ${item.cantidad + 1})" aria-label="Agregar una unidad">+</button>
                    </div>
                    <p class="cart-item-price">Q${item.precio.toFixed(2)} c/u</p>
                `;
                return `
                    <div class="cart-item">
                        <div class="cart-item-main">
                            <p class="cart-item-name">${nombre}</p>
                            ${control}
                        </div>
                        <div class="cart-item-side">
                            <button type="button" onclick="quitarDelCarrito(${index})" class="cart-remove" aria-label="Quitar ${escaparHTML(item.nombre)} del carrito">×</button>
                            <span id="carrito-subtotal-${index}" class="cart-item-subtotal">Q${subtotal.toFixed(2)}</span>
                        </div>
                    </div>
                `;
            }).join('');

            document.getElementById('carrito-total').innerText = `Q${totalVentaActual.toFixed(2)}`;
        }

        function vaciarCarrito() {
            if (!carrito.length) return;
            carrito = [];
            renderizarCarrito();
            mostrarAviso('Carrito vaciado');
        }

        function quitarDelCarrito(index) {
            carrito.splice(index, 1);
            renderizarCarrito();
        }

        function abrirModalCobro() {
            if (carrito.length === 0) return abrirModalCarritoVacio();
            
            document.getElementById('modal-total-cobro').innerText = `Q${totalVentaActual.toFixed(2)}`;
            document.getElementById('input-efectivo').value = '';
            document.getElementById('modal-vuelto').innerText = 'Q0.00';
            document.getElementById('modal-vuelto').className = "text-2xl font-black text-green-500";
            
            const btn = document.getElementById('btn-finalizar-venta');
            btn.disabled = true;
            btn.classList.add('opacity-50', 'cursor-not-allowed');

            renderizarEfectivoRapido();
            document.body.classList.add('cobro-abierto');
            document.getElementById('modal-cobrar').classList.remove('hidden');
            ajustarModalCobroTeclado();
            // En teléfonos no se abre el teclado solo: se eligen montos rápidos o se toca el campo.
            if (!window.matchMedia('(pointer: coarse)').matches) {
                setTimeout(() => document.getElementById('input-efectivo').focus(), 100);
            }
        }

        // Botones con billetes habituales para no depender del teclado.
        function renderizarEfectivoRapido() {
            const contenedor = document.getElementById('cobro-rapido');
            if (!contenedor) return;
            const total = Math.round(totalVentaActual * 100) / 100;
            const montos = [...new Set([5, 10, 20, 50, 100, 200].map(b => Math.ceil(total / b) * b))]
                .filter(m => m > total)
                .sort((a, b) => a - b)
                .slice(0, 3);
            const opciones = [{ valor: total, etiqueta: `Q${total.toFixed(2).replace(/\.00$/, '')}`, nota: 'Exacto' },
                ...montos.map(m => ({ valor: m, etiqueta: `Q${m}`, nota: 'Billete' }))];
            contenedor.innerHTML = opciones.map(o =>
                `<button type="button" class="cobro-chip" data-valor="${o.valor}" onclick="establecerEfectivoRapido(${o.valor})"><small>${o.nota}</small>${o.etiqueta}</button>`
            ).join('');
        }

        function establecerEfectivoRapido(valor) {
            const campo = document.getElementById('input-efectivo');
            campo.value = String(valor);
            campo.blur();
            calcularVuelto();
            navigator.vibrate?.(10);
        }

        function marcarEfectivoRapido(efectivo) {
            document.querySelectorAll('#cobro-rapido .cobro-chip').forEach(chip => {
                chip.classList.toggle('activo', Math.abs(Number(chip.dataset.valor) - efectivo) < 0.005);
            });
        }

        // Mantiene la hoja visible por encima del teclado en móviles (PWA).
        function ajustarModalCobroTeclado() {
            const modal = document.getElementById('modal-cobrar');
            const vv = window.visualViewport;
            if (!modal || !vv || modal.classList.contains('hidden')) return;
            modal.style.top = `${vv.offsetTop}px`;
            modal.style.height = `${vv.height}px`;
            modal.style.bottom = 'auto';
        }

        if (window.visualViewport) {
            window.visualViewport.addEventListener('resize', ajustarModalCobroTeclado);
            window.visualViewport.addEventListener('scroll', ajustarModalCobroTeclado);
        }

        function abrirModalCarritoVacio() {
            document.getElementById('modal-carrito-vacio').classList.remove('hidden');
            setTimeout(() => document.getElementById('btn-cerrar-carrito-vacio')?.focus(), 100);
        }

        function cerrarModalCarritoVacio() {
            document.getElementById('modal-carrito-vacio').classList.add('hidden');
        }

        function cerrarModalCobro() {
            const modal = document.getElementById('modal-cobrar');
            modal.classList.add('hidden');
            modal.style.top = modal.style.height = modal.style.bottom = '';
            document.body.classList.remove('cobro-abierto');
        }

        function cerrarTecladoYCobrar(event) {
            event.preventDefault();
            document.getElementById('input-efectivo').blur();
            calcularVuelto();
            if (!document.getElementById('btn-finalizar-venta').disabled) confirmarVenta();
        }

        function calcularVuelto() {
            const campoEfectivo = document.getElementById('input-efectivo');
            // Algunos teclados móviles usan coma decimal.
            const efectivo = parseFloat(campoEfectivo.value.replace(',', '.')) || 0;
            marcarEfectivoRapido(efectivo);
            const vuelto = efectivo - totalVentaActual;
            const textoVuelto = document.getElementById('modal-vuelto');
            const btn = document.getElementById('btn-finalizar-venta');

            if (efectivo >= totalVentaActual) {
                textoVuelto.innerText = `Q${vuelto.toFixed(2)}`;
                textoVuelto.classList.remove('text-red-500');
                textoVuelto.classList.add('text-green-500');
                
                btn.disabled = false;
                btn.classList.remove('opacity-50', 'cursor-not-allowed');
            } else {
                textoVuelto.innerText = `Falta Q${Math.abs(vuelto).toFixed(2)}`;
                textoVuelto.classList.remove('text-green-500');
                textoVuelto.classList.add('text-red-500');
                
                btn.disabled = true;
                btn.classList.add('opacity-50', 'cursor-not-allowed');
            }
        }

        function confirmarVenta() {
            const venta = {
                total: totalVentaActual,
                fechaLocal: new Date().toISOString(),
                fecha: firebase.firestore.FieldValue.serverTimestamp(),
                items: carrito.map(item => ({
                    productoId: item.id,
                    nombre: item.tamano ? `${item.nombre} (${item.tamano})` : item.nombre,
                    categoria: item.categoria || 'Otros',
                    precio: item.precio,
                    cantidad: item.cantidad,
                    unidadVenta: item.modoVenta || item.unidadVenta || 'unidad',
                    tamano: item.tamano || null
                }))
            };

            const batch = db.batch();
            const descuentosPorProducto = carrito.reduce((totales, item) => {
                totales[item.id] = (totales[item.id] || 0) + item.cantidad * (item.descuentoStock || 1);
                return totales;
            }, {});
            Object.entries(descuentosPorProducto).forEach(([id, descuento]) => {
                const prodRef = coleccionUsuario("productos").doc(id);
                const prodReal = inventario.find(p => p.id === id);
                if (prodReal) {
                    batch.update(prodRef, { stock: Math.max(0, prodReal.stock - descuento) });
                    registrarMovimiento({ productoId: id, producto: prodReal.nombre, categoria: prodReal.categoria || 'Otros', tipo: 'venta', detalle: 'Salida por venta', cantidad: -descuento }, batch);
                }
            });
            batch.set(coleccionUsuario("ventas").doc(), venta);

            const boton = document.getElementById('btn-finalizar-venta');
            establecerCargaBoton(boton, true);
            batch.commit().then(() => {
                carrito = [];
                renderizarCarrito();
                cerrarModalCobro();
                mostrarAviso('Venta cobrada e inventario actualizado', 'exito');
            }).catch(error => {
                alert('No se pudo registrar la venta: ' + error.message);
            }).finally(() => establecerCargaBoton(boton, false));
        }

        let periodoReporte = 'diario';

        function abrirModalReportes() {
            periodoReporte = 'diario';
            document.querySelectorAll('.reporte-periodo').forEach(btn => btn.classList.toggle('activo', btn.dataset.periodo === periodoReporte));
            const ahora = new Date();
            const fechaLocal = new Date(ahora.getTime() - ahora.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
            document.getElementById('fecha-reporte').value = fechaLocal;
            document.getElementById('estado-reporte').classList.add('hidden');
            document.getElementById('modal-reportes').classList.remove('hidden');
        }

        function cerrarModalReportes() {
            document.getElementById('modal-reportes').classList.add('hidden');
        }

        function seleccionarPeriodoReporte(periodo, boton) {
            periodoReporte = periodo;
            document.querySelectorAll('.reporte-periodo').forEach(btn => btn.classList.remove('activo'));
            boton.classList.add('activo');
        }

        function obtenerRangoReporte(periodo, valorFecha) {
            const referencia = new Date(`${valorFecha}T12:00:00`);
            let inicio = new Date(referencia);
            let fin;

            if (periodo === 'semanal') {
                const distanciaLunes = (inicio.getDay() + 6) % 7;
                inicio.setDate(inicio.getDate() - distanciaLunes);
            } else if (periodo === 'mensual') {
                inicio = new Date(inicio.getFullYear(), inicio.getMonth(), 1, 12);
            }
            inicio.setHours(0, 0, 0, 0);

            if (periodo === 'diario') {
                fin = new Date(inicio);
                fin.setDate(fin.getDate() + 1);
            } else if (periodo === 'semanal') {
                fin = new Date(inicio);
                fin.setDate(fin.getDate() + 7);
            } else {
                fin = new Date(inicio.getFullYear(), inicio.getMonth() + 1, 1);
            }
            return { inicio, fin };
        }

        function escaparHTML(valor) {
            return String(valor).replace(/[&<>'"]/g, caracter => ({
                '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
            })[caracter]);
        }

        function limpiarTextoPDF(valor) {
            return String(valor)
                .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
                .replace(/[^\x20-\x7E]/g, ' ')
                .replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
        }

        function descargarReportePDF(reporte) {
            const ancho = 595;
            const alto = 842;
            const margen = 42;
            const productos = reporte.productos.length
                ? reporte.productos
                : [{ nombre: 'Sin ventas registradas en este periodo', cantidad: 0, total: 0 }];
            const paginas = [];
            const filasPrimeraPagina = 17;
            const filasSiguientes = 23;

            paginas.push(productos.slice(0, filasPrimeraPagina));
            for (let i = filasPrimeraPagina; i < productos.length; i += filasSiguientes) {
                paginas.push(productos.slice(i, i + filasSiguientes));
            }

            const objetos = [null];
            const agregarObjeto = contenido => { objetos.push(contenido); return objetos.length - 1; };
            const catalogoId = agregarObjeto('');
            const paginasId = agregarObjeto('');
            const fuenteId = agregarObjeto('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
            const fuenteNegritaId = agregarObjeto('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>');
            const idsPaginas = [];
            const fechaGeneracion = new Date().toLocaleString('es-GT', { dateStyle: 'medium', timeStyle: 'short' });
            const unidadesTexto = reporte.unidades.toFixed(2).replace(/\.00$/, '');

            paginas.forEach((productosPagina, indicePagina) => {
                const comandos = [];
                const color = (r, g, b) => comandos.push(`${r} ${g} ${b} rg`);
                const rectangulo = (x, y, w, h, r, g, b) => comandos.push(`${r} ${g} ${b} rg ${x} ${y} ${w} ${h} re f`);
                const linea = (x1, y1, x2, y2, r = .86, g = .89, b = .91) => {
                    comandos.push(`${r} ${g} ${b} RG .7 w ${x1} ${y1} m ${x2} ${y2} l S`);
                };
                const texto = (x, y, tamano, contenido, negrita = false, alineacion = 'izquierda') => {
                    const limpio = limpiarTextoPDF(contenido);
                    const anchoEstimado = limpio.length * tamano * (negrita ? .56 : .5);
                    let posicionX = x;
                    if (alineacion === 'derecha') posicionX = x - anchoEstimado;
                    if (alineacion === 'centro') posicionX = x - anchoEstimado / 2;
                    comandos.push(`BT /${negrita ? 'F2' : 'F1'} ${tamano} Tf ${posicionX.toFixed(1)} ${y} Td (${limpio}) Tj ET`);
                };

                // Encabezado corporativo.
                rectangulo(0, 744, ancho, 98, .063, .149, .239);
                rectangulo(0, 740, ancho, 4, .835, .659, .294);
                rectangulo(margen, 775, 40, 40, .086, .549, .525);
                color(1, 1, 1);
                texto(62, 790, 13, 'MN', true, 'centro');
                texto(96, 804, 9, 'MI NEGOCIO', true);
                color(.72, .82, .86);
                texto(96, 786, 8, 'CONTROL DE INVENTARIO Y VENTAS');
                color(1, 1, 1);
                texto(553, 800, 9, reporte.titulo.toUpperCase(), true, 'derecha');
                color(.72, .82, .86);
                texto(553, 782, 8, reporte.rangoTexto, false, 'derecha');

                let inicioTabla;
                if (indicePagina === 0) {
                    color(.063, .149, .239);
                    texto(margen, 708, 18, 'Resumen del periodo', true);
                    color(.40, .48, .55);
                    texto(margen, 691, 9, 'Resultados consolidados de las ventas registradas');

                    const tarjetas = [
                        { x: 42, titulo: 'VENTAS', valor: String(reporte.numeroVentas), color: [.086, .549, .525] },
                        { x: 216, titulo: 'UNIDADES', valor: unidadesTexto, color: [.31, .47, .64] },
                        { x: 390, titulo: 'TOTAL VENDIDO', valor: `Q${reporte.total.toFixed(2)}`, color: [.835, .659, .294] }
                    ];
                    tarjetas.forEach(tarjeta => {
                        rectangulo(tarjeta.x, 622, 163, 54, .96, .97, .98);
                        rectangulo(tarjeta.x, 622, 4, 54, ...tarjeta.color);
                        color(.42, .49, .55);
                        texto(tarjeta.x + 15, 656, 7, tarjeta.titulo, true);
                        color(.063, .149, .239);
                        texto(tarjeta.x + 15, 635, 15, tarjeta.valor, true);
                    });
                    inicioTabla = 585;
                } else {
                    color(.063, .149, .239);
                    texto(margen, 708, 15, 'Detalle de productos', true);
                    color(.40, .48, .55);
                    texto(553, 708, 9, 'Continuacion', false, 'derecha');
                    inicioTabla = 680;
                }

                // Tabla de productos.
                rectangulo(margen, inicioTabla, 511, 30, .063, .149, .239);
                color(1, 1, 1);
                texto(54, inicioTabla + 11, 8, 'PRODUCTO', true);
                texto(420, inicioTabla + 11, 8, 'UNIDADES', true, 'derecha');
                texto(541, inicioTabla + 11, 8, 'IMPORTE', true, 'derecha');

                let y = inicioTabla - 26;
                productosPagina.forEach((item, fila) => {
                    if (fila % 2 === 0) rectangulo(margen, y - 9, 511, 27, .965, .973, .978);
                    color(.145, .22, .29);
                    const nombre = item.nombre.length > 50 ? `${item.nombre.slice(0, 49)}...` : item.nombre;
                    texto(54, y, 9, nombre, fila === 0 && !reporte.productos.length);
                    texto(420, y, 9, item.cantidad.toFixed(2).replace(/\.00$/, ''), false, 'derecha');
                    texto(541, y, 9, `Q${item.total.toFixed(2)}`, true, 'derecha');
                    linea(margen, y - 10, 553, y - 10);
                    y -= 28;
                });

                if (indicePagina === paginas.length - 1 && reporte.productos.length) {
                    y -= 5;
                    rectangulo(366, y - 12, 187, 34, .91, .95, .95);
                    color(.086, .549, .525);
                    texto(381, y, 9, 'TOTAL DEL PERIODO', true);
                    color(.063, .149, .239);
                    texto(541, y, 11, `Q${reporte.total.toFixed(2)}`, true, 'derecha');
                }

                // Pie de pagina consistente.
                linea(margen, 51, 553, 51, .78, .83, .86);
                color(.40, .48, .55);
                texto(margen, 33, 7, `Generado: ${fechaGeneracion}`);
                texto(ancho / 2, 33, 7, 'Documento generado por Mi Negocio', false, 'centro');
                color(.063, .149, .239);
                texto(553, 33, 7, `PAGINA ${indicePagina + 1} / ${paginas.length}`, true, 'derecha');

                const contenido = comandos.join('\n');
                const contenidoId = agregarObjeto(`<< /Length ${contenido.length} >>\nstream\n${contenido}\nendstream`);
                const paginaId = agregarObjeto(`<< /Type /Page /Parent ${paginasId} 0 R /MediaBox [0 0 ${ancho} ${alto}] /Resources << /Font << /F1 ${fuenteId} 0 R /F2 ${fuenteNegritaId} 0 R >> >> /Contents ${contenidoId} 0 R >>`);
                idsPaginas.push(paginaId);
            });

            objetos[catalogoId] = `<< /Type /Catalog /Pages ${paginasId} 0 R >>`;
            objetos[paginasId] = `<< /Type /Pages /Kids [${idsPaginas.map(id => `${id} 0 R`).join(' ')}] /Count ${idsPaginas.length} >>`;

            let pdf = '%PDF-1.4\n';
            const offsets = [0];
            for (let i = 1; i < objetos.length; i++) {
                offsets[i] = pdf.length;
                pdf += `${i} 0 obj\n${objetos[i]}\nendobj\n`;
            }
            const inicioXref = pdf.length;
            pdf += `xref\n0 ${objetos.length}\n0000000000 65535 f \n`;
            for (let i = 1; i < objetos.length; i++) pdf += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
            pdf += `trailer\n<< /Size ${objetos.length} /Root ${catalogoId} 0 R >>\nstartxref\n${inicioXref}\n%%EOF`;

            const blob = new Blob([pdf], { type: 'application/pdf' });
            const url = URL.createObjectURL(blob);
            const enlace = document.createElement('a');
            enlace.href = url;
            enlace.download = `Reporte_${reporte.tipo}_${document.getElementById('fecha-reporte').value}.pdf`;
            document.body.appendChild(enlace);
            enlace.click();
            enlace.remove();
            setTimeout(() => URL.revokeObjectURL(url), 1000);
        }

        async function generarReporteVentas() {
            const fecha = document.getElementById('fecha-reporte').value;
            if (!fecha) return alert('Selecciona una fecha de referencia.');

            const { inicio, fin } = obtenerRangoReporte(periodoReporte, fecha);
            const ventasPeriodo = ventas.filter(venta => {
                const fechaVenta = obtenerFechaVenta(venta.fecha);
                return fechaVenta && fechaVenta >= inicio && fechaVenta < fin;
            });
            const productos = {};
            let total = 0;
            let unidades = 0;
            ventasPeriodo.forEach(venta => {
                total += Number(venta.total) || 0;
                (venta.items || []).forEach(item => {
                    const nombre = item.nombre || 'Producto';
                    if (!productos[nombre]) productos[nombre] = { nombre, cantidad: 0, total: 0 };
                    const cantidad = Number(item.cantidad) || 0;
                    productos[nombre].cantidad += cantidad;
                    productos[nombre].total += cantidad * (Number(item.precio) || 0);
                    unidades += cantidad;
                });
            });

            const nombresPeriodo = { diario: 'Reporte diario', semanal: 'Reporte semanal', mensual: 'Reporte de fin de mes' };
            const finVisible = new Date(fin);
            finVisible.setDate(finVisible.getDate() - 1);
            const formatoFecha = { day: '2-digit', month: 'long', year: 'numeric' };
            const reporte = {
                tipo: periodoReporte,
                titulo: nombresPeriodo[periodoReporte],
                rangoTexto: `${inicio.toLocaleDateString('es-GT', formatoFecha)} — ${finVisible.toLocaleDateString('es-GT', formatoFecha)}`,
                inicio: firebase.firestore.Timestamp.fromDate(inicio),
                fin: firebase.firestore.Timestamp.fromDate(fin),
                total,
                unidades,
                numeroVentas: ventasPeriodo.length,
                productos: Object.values(productos).sort((a, b) => b.total - a.total),
                creadoEn: firebase.firestore.FieldValue.serverTimestamp(),
                creadoPor: auth.currentUser ? auth.currentUser.uid : null
            };

            const boton = document.getElementById('btn-generar-reporte');
            const estado = document.getElementById('estado-reporte');
            boton.disabled = true;
            boton.classList.add('opacity-50');
            estado.textContent = 'Guardando reporte en la nube…';
            estado.classList.remove('hidden');

            // La descarga se inicia dentro del clic para que también funcione en móviles.
            descargarReportePDF(reporte);

            try {
                await coleccionUsuario('reportesVentas').add(reporte);
                estado.textContent = '✓ PDF descargado y reporte guardado en la nube.';
            } catch (error) {
                estado.textContent = 'El PDF se descargó, pero no se pudo guardar en la nube.';
                alert('El PDF fue descargado. Error al guardar en la nube: ' + error.message);
            } finally {
                boton.disabled = false;
                boton.classList.remove('opacity-50');
            }
        }

        function abrirSelectorRestauracion() {
            const campo = document.getElementById('archivo-restauracion');
            campo.value = '';
            campo.click();
        }

        async function prepararRestauracion(event) {
            const archivo = event.target.files?.[0];
            if (!archivo) return;
            try {
                const datos = JSON.parse(await archivo.text());
                if (!datos || !Array.isArray(datos.inventario) || !Array.isArray(datos.ventas)) throw new Error('Formato inválido');
                respaldoPendiente = {
                    inventario: datos.inventario,
                    ventas: datos.ventas,
                    reportesVentas: Array.isArray(datos.reportesVentas) ? datos.reportesVentas : [],
                    movimientos: Array.isArray(datos.movimientos) ? datos.movimientos : []
                };
                document.getElementById('restaurar-productos').textContent = respaldoPendiente.inventario.length;
                document.getElementById('restaurar-ventas').textContent = respaldoPendiente.ventas.length;
                document.getElementById('restaurar-reportes').textContent = respaldoPendiente.reportesVentas.length;
                document.getElementById('resumen-restauracion').textContent = `Archivo: ${archivo.name}. Revisa el contenido y elige cómo recuperarlo.`;
                document.getElementById('modal-restaurar').classList.remove('hidden');
            } catch (error) {
                respaldoPendiente = null;
                mostrarAviso('El archivo no es un respaldo válido', 'error');
            }
        }

        function cerrarModalRestaurar() {
            respaldoPendiente = null;
            document.getElementById('modal-restaurar').classList.add('hidden');
        }

        function prepararDatoFirestore(valor, clave = '') {
            if (Array.isArray(valor)) return valor.map(dato => prepararDatoFirestore(dato));
            if (valor && typeof valor === 'object') return Object.fromEntries(Object.entries(valor).map(([k, dato]) => [k, prepararDatoFirestore(dato, k)]));
            if (typeof valor === 'string' && ['fecha', 'creadoEn', 'inicio', 'fin'].includes(clave)) {
                const fecha = new Date(valor);
                if (!Number.isNaN(fecha.getTime())) return firebase.firestore.Timestamp.fromDate(fecha);
            }
            return valor;
        }

        async function guardarColeccionRestaurada(nombre, registros) {
            for (let i = 0; i < registros.length; i += 400) {
                const batch = db.batch();
                registros.slice(i, i + 400).forEach(registro => {
                    const { id, ...datos } = registro || {};
                    const referencia = id ? coleccionUsuario(nombre).doc(String(id)) : coleccionUsuario(nombre).doc();
                    batch.set(referencia, prepararDatoFirestore(datos), { merge: true });
                });
                await batch.commit();
            }
        }

        async function confirmarRestauracion() {
            if (!respaldoPendiente) return;
            const reemplazar = document.getElementById('modo-restauracion').value === 'reemplazar';
            if (reemplazar && !confirm('Se borrarán los datos actuales antes de restaurar. ¿Deseas continuar?')) return;
            const boton = document.getElementById('btn-confirmar-restauracion');
            establecerCargaBoton(boton, true);
            try {
                const colecciones = ['productos', 'ventas', 'reportesVentas', 'movimientos'];
                if (reemplazar) {
                    for (const nombre of colecciones) await borrarColeccion(nombre);
                }
                await guardarColeccionRestaurada('productos', respaldoPendiente.inventario);
                await guardarColeccionRestaurada('ventas', respaldoPendiente.ventas);
                await guardarColeccionRestaurada('reportesVentas', respaldoPendiente.reportesVentas);
                await guardarColeccionRestaurada('movimientos', respaldoPendiente.movimientos);
                cerrarModalRestaurar();
                mostrarAviso('Respaldo restaurado correctamente', 'exito');
            } catch (error) {
                mostrarAviso('No se pudo completar la restauración', 'error');
                console.error('Error al restaurar:', error);
            } finally {
                establecerCargaBoton(boton, false);
            }
        }

        function abrirModalRespaldo() {
            document.getElementById('respaldo-productos').textContent = inventario.length;
            document.getElementById('respaldo-ventas').textContent = ventas.length;
            document.getElementById('respaldo-reportes').textContent = 'Se consultarán al guardar';
            document.getElementById('estado-respaldo').classList.add('hidden');
            document.getElementById('modal-respaldo').classList.remove('hidden');
        }

        function cerrarModalRespaldo() {
            document.getElementById('modal-respaldo').classList.add('hidden');
        }

        function convertirDatoRespaldo(valor) {
            if (valor?.toDate instanceof Function) return valor.toDate().toISOString();
            if (valor instanceof Date) return valor.toISOString();
            if (Array.isArray(valor)) return valor.map(convertirDatoRespaldo);
            if (valor && typeof valor === 'object') {
                return Object.fromEntries(Object.entries(valor).map(([clave, dato]) => [clave, convertirDatoRespaldo(dato)]));
            }
            return valor;
        }

        async function descargarRespaldoCompleto() {
            const boton = document.getElementById('btn-crear-respaldo');
            const estado = document.getElementById('estado-respaldo');
            establecerCargaBoton(boton, true);
            estado.textContent = 'Preparando todos los datos…';
            estado.classList.remove('hidden');

            try {
                const consultaReportes = await coleccionUsuario('reportesVentas').get();
                const reportes = consultaReportes.docs.map(doc => ({ id: doc.id, ...doc.data() }));
                document.getElementById('respaldo-reportes').textContent = reportes.length;

                const respaldo = convertirDatoRespaldo({
                    version: 1,
                    aplicacion: 'Mi Negocio',
                    creadoEn: new Date().toISOString(),
                    usuario: {
                        uid: auth.currentUser?.uid || null,
                        correo: auth.currentUser?.email || null
                    },
                    inventario,
                    ventas,
                    movimientos,
                    reportesVentas: reportes
                });
                const blob = new Blob([JSON.stringify(respaldo, null, 2)], { type: 'application/json;charset=utf-8' });
                const url = URL.createObjectURL(blob);
                const enlace = document.createElement('a');
                enlace.href = url;
                enlace.download = `Respaldo_Mi_Negocio_${new Date().toISOString().slice(0, 10)}.json`;
                document.body.appendChild(enlace);
                enlace.click();
                enlace.remove();
                setTimeout(() => URL.revokeObjectURL(url), 1000);
                cerrarModalRespaldo();
                mostrarAviso('Respaldo completo guardado correctamente', 'exito');
            } catch (error) {
                estado.textContent = 'No se pudo crear el respaldo.';
                mostrarAviso('No se pudo guardar el respaldo', 'error');
                console.error('Error al crear el respaldo:', error);
            } finally {
                establecerCargaBoton(boton, false);
            }
        }

        function abrirModalExportarInventario() {
            if (inventario.length === 0) {
                mostrarAviso('No hay productos para descargar', 'error');
                return;
            }
            document.getElementById('total-productos-exportar').textContent = inventario.length;
            document.getElementById('modal-exportar-inventario').classList.remove('hidden');
        }

        function cerrarModalExportarInventario() {
            document.getElementById('modal-exportar-inventario').classList.add('hidden');
        }

        function exportarCSV() {
            if (inventario.length === 0) {
                cerrarModalExportarInventario();
                mostrarAviso('No hay productos para descargar', 'error');
                return;
            }

            const escaparCSV = valor => `"${String(valor ?? '').replace(/"/g, '""')}"`;
            let csv = '\uFEFFNombre,Categoria,Costo,Precio,Stock\r\n';
            inventario.forEach(p => {
                csv += [p.nombre, p.categoria, p.costo, p.precio, p.stock].map(escaparCSV).join(',') + '\r\n';
            });

            const boton = document.getElementById('btn-descargar-inventario');
            establecerCargaBoton(boton, true);
            try {
                const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
                const url = URL.createObjectURL(blob);
                const enlace = document.createElement('a');
                enlace.href = url;
                enlace.download = `Inventario_${new Date().toISOString().slice(0, 10)}.csv`;
                document.body.appendChild(enlace);
                enlace.click();
                enlace.remove();
                setTimeout(() => URL.revokeObjectURL(url), 1000);
                cerrarModalExportarInventario();
                mostrarAviso('Inventario descargado correctamente', 'exito');
            } catch (error) {
                mostrarAviso('No se pudo descargar el inventario', 'error');
                console.error('Error al exportar el inventario:', error);
            } finally {
                establecerCargaBoton(boton, false);
            }
        }

        function borrarColeccion(nombreColeccion) {
            return coleccionUsuario(nombreColeccion).get().then((querySnapshot) => {
                const documentos = querySnapshot.docs;
                const eliminaciones = [];

                // Firestore permite un máximo de 500 operaciones por lote.
                for (let i = 0; i < documentos.length; i += 500) {
                    const batch = db.batch();
                    documentos.slice(i, i + 500).forEach(doc => batch.delete(doc.ref));
                    eliminaciones.push(batch.commit());
                }
                return Promise.all(eliminaciones);
            });
        }

        let accionBorradoPendiente = null;

        function abrirConfirmacionBorrado(tipo) {
            const esInventario = tipo === 'inventario';
            accionBorradoPendiente = tipo;
            document.getElementById('titulo-confirmar-borrado').textContent = esInventario
                ? '¿Borrar todo el inventario?'
                : '¿Borrar todas las ventas?';
            document.getElementById('texto-confirmar-borrado').textContent = esInventario
                ? 'Se eliminarán todos los productos y existencias registrados.'
                : 'Se eliminará permanentemente todo el historial de ventas.';
            document.getElementById('detalle-confirmar-borrado').textContent = 'Esta acción no se puede deshacer.';
            document.getElementById('btn-confirmar-borrado').onclick = confirmarBorradoDatos;
            document.getElementById('modal-confirmar-borrado').classList.remove('hidden');
        }

        function cerrarConfirmacionBorrado() {
            accionBorradoPendiente = null;
            document.getElementById('modal-confirmar-borrado').classList.add('hidden');
        }

        async function confirmarBorradoDatos() {
            const tipo = accionBorradoPendiente;
            if (!tipo) return;
            const boton = document.getElementById('btn-confirmar-borrado');
            establecerCargaBoton(boton, true);

            try {
                await borrarColeccion(tipo === 'inventario' ? 'productos' : 'ventas');
                if (tipo === 'inventario') {
                    carrito = [];
                    renderizarCarrito();
                }
                cerrarConfirmacionBorrado();
                mostrarAviso(tipo === 'inventario' ? 'Inventario eliminado correctamente' : 'Historial de ventas eliminado correctamente', 'exito');
            } catch (error) {
                mostrarAviso('No se pudieron borrar los datos', 'error');
                console.error('Error al borrar datos:', error);
            } finally {
                establecerCargaBoton(boton, false);
            }
        }

        function limpiarInventario() {
            abrirConfirmacionBorrado('inventario');
        }

        function limpiarVentas() {
            abrirConfirmacionBorrado('ventas');
        }

        // Registro del service worker: instalación como aplicación y aviso de nuevas versiones.
        if ('serviceWorker' in navigator) {
            const teniaControlador = Boolean(navigator.serviceWorker.controller);
            let recargando = false;
            let registroSW = null;

            const banner = document.getElementById('update-banner');
            const mostrarBannerActualizacion = () => banner?.classList.remove('hidden');
            const ocultarBannerActualizacion = () => banner?.classList.add('hidden');

            // Cuando la versión nueva toma el control, recarga una sola vez para usarla.
            navigator.serviceWorker.addEventListener('controllerchange', () => {
                if (!teniaControlador || recargando) return;
                recargando = true;
                window.location.reload();
            });

            document.getElementById('btn-actualizar-app')?.addEventListener('click', event => {
                const espera = registroSW?.waiting;
                if (!espera) return window.location.reload();
                establecerCargaBoton(event.currentTarget, true);
                espera.postMessage({ type: 'SKIP_WAITING' });
            });
            document.getElementById('btn-posponer-actualizacion')?.addEventListener('click', ocultarBannerActualizacion);

            function vigilarInstalacion(worker) {
                worker?.addEventListener('statechange', () => {
                    // Solo avisa si ya había una versión anterior controlando la página.
                    if (worker.state === 'installed' && navigator.serviceWorker.controller) mostrarBannerActualizacion();
                });
            }

            window.addEventListener('load', () => {
                navigator.serviceWorker.register('./sw.js').then(registro => {
                    registroSW = registro;
                    if (registro.waiting && navigator.serviceWorker.controller) mostrarBannerActualizacion();
                    vigilarInstalacion(registro.installing);
                    registro.addEventListener('updatefound', () => vigilarInstalacion(registro.installing));

                    // Busca versiones nuevas al volver a la app y cada 30 minutos.
                    const buscarActualizacion = () => registro.update().catch(() => undefined);
                    document.addEventListener('visibilitychange', () => {
                        if (!document.hidden) buscarActualizacion();
                    });
                    setInterval(buscarActualizacion, 30 * 60 * 1000);
                }).catch(error => {
                    console.warn('No se pudo registrar el modo sin conexión:', error);
                });
            });
        }

