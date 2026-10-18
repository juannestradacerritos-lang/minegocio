// Categorías editables: se pueden agregar y eliminar desde los selectores de "Categoría"
// (Registrar producto y Editar producto). Se guardan en la cuenta del usuario.
(function () {
    const NUEVA = '__nueva__';
    const BASE = ['Verduras', 'Abarrotes', 'Plásticos para el hogar', 'Vajilla de porcelana', 'Granos y frijoles'];
    const IDS_SELECT = ['nuevo-categoria', 'editar-categoria'];
    let categorias = [...BASE];
    let selectOrigen = null;
    let desuscribir = null;

    const normalizar = s => String(s).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
    const claveLocal = () => `categorias_${auth.currentUser?.uid || 'anon'}`;
    const productosEn = nombre => inventario.filter(p => (p.categoria || 'Otros') === nombre).length;

    function sincronizar(select) {
        if (typeof sincronizarSelectorPersonalizado === 'function') sincronizarSelectorPersonalizado(select);
    }

    function poblarSelect(select) {
        const previo = select.value;
        select.replaceChildren();
        categorias.forEach(c => select.add(new Option(c, c)));
        // Conserva una categoría antigua mientras algún producto todavía la use.
        const conservar = previo && previo !== NUEVA && !categorias.includes(previo) && productosEn(previo) > 0;
        if (conservar) select.add(new Option(previo, previo));
        select.add(new Option('＋ Agregar nueva categoría…', NUEVA));
        const valido = [...select.options].some(o => o.value === previo && previo !== NUEVA);
        select.value = valido ? previo : select.options[0].value;
        sincronizar(select);
    }

    function aplicar() {
        // El filtro de Gráficos y el PDF por categoría usan esta misma lista.
        if (typeof categoriasVentasBase !== 'undefined') categoriasVentasBase.splice(0, categoriasVentasBase.length, ...categorias);
        IDS_SELECT.forEach(id => {
            const select = document.getElementById(id);
            if (select) poblarSelect(select);
        });
        if (typeof renderizarMenuCategorias === 'function') renderizarMenuCategorias();
        if (!document.getElementById('modal-categorias')?.classList.contains('hidden')) renderizarLista();
    }

    function guardar() {
        try { localStorage.setItem(claveLocal(), JSON.stringify(categorias)); } catch (e) { /* sin almacenamiento local */ }
        if (!auth.currentUser) return;
        coleccionUsuario('configuracion').doc('categorias').set({ lista: categorias })
            .catch(() => mostrarAviso('No se pudo sincronizar las categorías', 'error'));
    }

    // ---------- Ventana de administración ----------
    function crearModal() {
        const modal = document.createElement('div');
        modal.id = 'modal-categorias';
        modal.className = 'fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center z-50 hidden p-4';
        modal.setAttribute('role', 'dialog');
        modal.setAttribute('aria-modal', 'true');
        modal.setAttribute('aria-labelledby', 'titulo-categorias');
        modal.innerHTML = `
            <div class="bg-white p-6 w-full max-w-md shadow-2xl" style="max-height:calc(100dvh - 2rem);overflow-y:auto">
                <div class="flex items-start justify-between mb-1">
                    <div>
                        <p class="text-xs font-bold uppercase tracking-wider text-teal-600">Catálogo</p>
                        <h3 id="titulo-categorias" class="text-xl font-bold text-gray-800 mt-1">Categorías</h3>
                    </div>
                    <button type="button" id="btn-x-categorias" class="text-2xl text-gray-400" aria-label="Cerrar">×</button>
                </div>
                <p class="text-sm text-gray-500">Agrega categorías nuevas o elimina las que ya no uses.</p>
                <form id="form-categoria" class="flex gap-2 mt-4">
                    <input id="categoria-nueva-input" type="text" maxlength="40" autocomplete="off" class="min-w-0 flex-1 p-3 border border-gray-200" placeholder="Nombre de la nueva categoría" aria-label="Nombre de la nueva categoría">
                    <button type="submit" class="shrink-0 bg-teal-600 hover:bg-teal-700 text-white px-4 font-bold">Agregar</button>
                </form>
                <div id="lista-categorias" class="cat-list"></div>
                <p class="mt-3 text-xs text-gray-500">Solo se pueden eliminar categorías que no tengan productos.</p>
                <button type="button" id="btn-listo-categorias" class="w-full mt-5 bg-gray-100 text-gray-700 py-3 font-bold">Listo</button>
            </div>`;
        document.body.appendChild(modal);

        modal.addEventListener('click', e => { if (e.target === modal) cerrarModal(); });
        modal.querySelector('#btn-x-categorias').addEventListener('click', cerrarModal);
        modal.querySelector('#btn-listo-categorias').addEventListener('click', cerrarModal);
        modal.querySelector('#form-categoria').addEventListener('submit', agregarCategoria);
        document.addEventListener('keydown', e => {
            if (e.key !== 'Escape') return;
            // Si la confirmación está abierta, Escape solo cierra esa ventana.
            if (confirmacionAbierta()) return cerrarConfirmacion();
            if (!modal.classList.contains('hidden')) cerrarModal();
        });
        return modal;
    }

    function renderizarLista() {
        const lista = document.getElementById('lista-categorias');
        lista.replaceChildren();
        categorias.forEach(nombre => {
            const usados = productosEn(nombre);
            const fila = document.createElement('div');
            fila.className = 'cat-item';

            const info = document.createElement('div');
            info.className = 'min-w-0';
            const titulo = document.createElement('span');
            titulo.textContent = nombre;
            const detalle = document.createElement('small');
            detalle.textContent = usados ? `${usados} producto${usados === 1 ? '' : 's'}` : 'Sin productos';
            info.append(titulo, detalle);

            const borrar = document.createElement('button');
            borrar.type = 'button';
            borrar.className = 'cat-delete';
            borrar.textContent = 'Eliminar';
            borrar.disabled = usados > 0 || categorias.length <= 1;
            borrar.title = usados > 0 ? 'Tiene productos asignados' : categorias.length <= 1 ? 'Debe quedar al menos una categoría' : '';
            borrar.setAttribute('aria-label', `Eliminar la categoría ${nombre}`);
            borrar.addEventListener('click', () => eliminarCategoria(nombre));

            fila.append(info, borrar);
            lista.appendChild(fila);
        });
    }

    function abrirModal(select) {
        selectOrigen = select || null;
        const modal = document.getElementById('modal-categorias') || crearModal();
        renderizarLista();
        document.getElementById('categoria-nueva-input').value = '';
        modal.classList.remove('hidden');
        setTimeout(() => document.getElementById('categoria-nueva-input')?.focus(), 100);
    }

    function cerrarModal() {
        document.getElementById('modal-categorias')?.classList.add('hidden');
        selectOrigen = null;
    }

    function agregarCategoria(evento) {
        evento.preventDefault();
        const campo = document.getElementById('categoria-nueva-input');
        const nombre = campo.value.replace(/\s+/g, ' ').trim();
        if (!nombre) return mostrarAviso('Escribe el nombre de la categoría', 'error');
        if (categorias.some(c => normalizar(c) === normalizar(nombre))) {
            return mostrarAviso('Esa categoría ya existe', 'error');
        }
        categorias.push(nombre);
        guardar();
        aplicar();
        if (selectOrigen) {
            selectOrigen.value = nombre;
            selectOrigen.dataset.prev = nombre;
            sincronizar(selectOrigen);
        }
        campo.value = '';
        mostrarAviso(`Categoría “${nombre}” agregada`, 'exito');
    }

    // ---------- Confirmación para eliminar (ventana propia, sin el cuadro del navegador) ----------
    let categoriaPorEliminar = null;

    function confirmacionAbierta() {
        const m = document.getElementById('modal-confirmar-categoria');
        return Boolean(m) && !m.classList.contains('hidden');
    }

    function cerrarConfirmacion() {
        categoriaPorEliminar = null;
        document.getElementById('modal-confirmar-categoria')?.classList.add('hidden');
    }

    function crearModalConfirmacion() {
        const modal = document.createElement('div');
        modal.id = 'modal-confirmar-categoria';
        modal.className = 'fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center hidden p-4';
        modal.style.zIndex = '60';
        modal.setAttribute('role', 'alertdialog');
        modal.setAttribute('aria-modal', 'true');
        modal.setAttribute('aria-labelledby', 'titulo-confirmar-categoria');
        modal.innerHTML = `
            <div class="bg-white p-6 w-full max-w-sm text-center shadow-2xl">
                <div class="confirm-icon" aria-hidden="true">!</div>
                <p class="text-xs font-bold uppercase tracking-wider text-red-500 mb-2">Eliminar categoría</p>
                <h3 id="titulo-confirmar-categoria" class="text-xl font-bold text-gray-800">¿Eliminar esta categoría?</h3>
                <p id="texto-confirmar-categoria" class="mt-2 text-sm leading-relaxed text-gray-500"></p>
                <div class="flex gap-3 mt-5">
                    <button type="button" id="btn-cancelar-categoria" class="flex-1 bg-gray-100 hover:bg-gray-200 text-gray-700 py-3 font-bold">Cancelar</button>
                    <button type="button" id="btn-aceptar-categoria" class="flex-1 bg-red-600 hover:bg-red-700 text-white py-3 font-bold shadow-md">Aceptar</button>
                </div>
            </div>`;
        document.body.appendChild(modal);

        modal.addEventListener('click', e => { if (e.target === modal) cerrarConfirmacion(); });
        modal.querySelector('#btn-cancelar-categoria').addEventListener('click', cerrarConfirmacion);
        modal.querySelector('#btn-aceptar-categoria').addEventListener('click', () => {
            const nombre = categoriaPorEliminar;
            cerrarConfirmacion();
            if (nombre) borrarCategoria(nombre);
        });
        return modal;
    }

    function eliminarCategoria(nombre) {
        if (productosEn(nombre) > 0 || categorias.length <= 1) return;
        const modal = document.getElementById('modal-confirmar-categoria') || crearModalConfirmacion();
        categoriaPorEliminar = nombre;
        modal.querySelector('#texto-confirmar-categoria').textContent = `Se eliminará la categoría “${nombre}” de la lista.`;
        modal.classList.remove('hidden');
        setTimeout(() => modal.querySelector('#btn-cancelar-categoria')?.focus(), 100);
    }

    function borrarCategoria(nombre) {
        if (productosEn(nombre) > 0 || categorias.length <= 1) return;
        categorias = categorias.filter(c => c !== nombre);
        guardar();
        aplicar();
        mostrarAviso(`Categoría “${nombre}” eliminada`);
    }

    // ---------- Selectores ----------
    IDS_SELECT.forEach(id => {
        const select = document.getElementById(id);
        if (!select) return;
        // Recuerda el valor vigente antes de abrir la lista, para poder restaurarlo si se elige "Agregar nueva".
        select.closest('.app-select')?.querySelector('.app-select-trigger')
            ?.addEventListener('click', () => { select.dataset.prev = select.value; });
        select.addEventListener('change', () => {
            if (select.value !== NUEVA) return;
            const previo = select.dataset.prev;
            const valido = [...select.options].some(o => o.value === previo && previo !== NUEVA);
            select.value = valido ? previo : select.options[0].value;
            sincronizar(select);
            abrirModal(select);
        });
    });

    aplicar();

    // Carga las categorías guardadas de la cuenta y las mantiene sincronizadas.
    auth.onAuthStateChanged(async user => {
        if (desuscribir) { desuscribir(); desuscribir = null; }
        if (!user) {
            categorias = [...BASE];
            aplicar();
            return;
        }
        try {
            const guardadas = JSON.parse(localStorage.getItem(claveLocal()));
            if (Array.isArray(guardadas) && guardadas.length) categorias = guardadas;
        } catch (e) { /* datos locales inválidos */ }
        aplicar();

        await persistenciaFirestore;
        if (auth.currentUser !== user) return;
        desuscribir = coleccionUsuario('configuracion').doc('categorias').onSnapshot(snap => {
            const lista = snap.exists ? snap.data().lista : null;
            if (!Array.isArray(lista) || !lista.length) return;
            categorias = lista.filter(c => typeof c === 'string' && c.trim());
            try { localStorage.setItem(claveLocal(), JSON.stringify(categorias)); } catch (e) { /* sin almacenamiento local */ }
            aplicar();
        }, error => console.warn('No se pudieron leer las categorías:', error));
    });
})();
