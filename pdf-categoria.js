// Descarga un PDF con las ventas agrupadas por categoría.
// Usa la categoría elegida en Resumen ("Todas" o una en particular) y el diseño compartido de pdf-comun.js.
(function () {
    function periodoSeleccionado() {
        const selector = document.getElementById('categoria-fecha-dia');
        if (!selector.value) selector.value = fechaLocalActual();
        const desde = selector.value;
        const hasta = desde;
        const inicio = desde ? new Date(`${desde}T00:00:00`) : null;
        const fin = hasta ? new Date(`${hasta}T00:00:00`) : null;
        if (fin) fin.setDate(fin.getDate() + 1);
        const formato = valor => new Date(`${valor}T00:00:00`).toLocaleDateString('es-GT');
        const texto = formato(desde);
        return { desde, hasta, inicio, fin, texto, valido: !desde || !hasta || desde <= hasta };
    }

    function recopilar(filtro, periodo) {
        const grupos = {};
        const detalle = [];
        let total = 0, unidades = 0;
        ventas.forEach(venta => {
            const fecha = obtenerFechaVenta(venta.fecha);
            if ((periodo.inicio || periodo.fin) && (!fecha || (periodo.inicio && fecha < periodo.inicio) || (periodo.fin && fecha >= periodo.fin))) return;
            const items = [];
            let totalFila = 0;
            (venta.items || []).forEach(item => {
                const nombreBase = String(item.nombre || '').replace(/ \((mediano|grande)\)$/i, '');
                const producto = inventario.find(p => p.id === item.productoId) || inventario.find(p => p.nombre === nombreBase);
                const categoria = item.categoria || producto?.categoria || 'Otros';
                if (filtro !== 'todas' && categoria !== filtro) return;
                const cantidad = Number(item.cantidad) || 0;
                const importe = (Number(item.precio) || 0) * cantidad;
                const grupo = grupos[categoria] || (grupos[categoria] = { productos: {}, importe: 0, cantidad: 0 });
                const nombre = item.nombre || 'Producto';
                const fila = grupo.productos[nombre] || (grupo.productos[nombre] = { importe: 0, cantidad: 0 });
                fila.importe += importe; fila.cantidad += cantidad;
                grupo.importe += importe; grupo.cantidad += cantidad;
                total += importe; unidades += cantidad;
                totalFila += importe;
                items.push({ nombre, cantidad, importe });
            });
            if (items.length) detalle.push({ fecha, items, total: totalFila });
        });
        detalle.sort((a, b) => (b.fecha?.getTime() || 0) - (a.fecha?.getTime() || 0));
        return { grupos, total, unidades, detalle };
    }

    const porcentaje = (parte, total) => (total > 0 ? parte / total * 100 : 0);

    function renderizarVentasCategoria() {
        const periodo = periodoSeleccionado();
        const estadoPeriodo = document.getElementById('categoria-periodo');
        estadoPeriodo.textContent = periodo.valido ? '' : 'La fecha Desde no puede ser posterior a Hasta.';
        estadoPeriodo.classList.toggle('hidden', periodo.valido);
        document.getElementById('btn-pdf-categoria').disabled = !periodo.valido;
        document.getElementById('btn-imagen-categoria').disabled = !periodo.valido;
    }

    function construirPDF(filtro, periodo) {
        const { grupos, total, unidades, detalle } = recopilar(filtro, periodo);
        const categorias = Object.keys(grupos).sort((a, b) => grupos[b].importe - grupos[a].importe);
        if (!categorias.length) return null;

        const totalProductos = categorias.reduce((t, c) => t + Object.keys(grupos[c].productos).length, 0);
        const doc = PDFInforme.crearDocumento({
            titulo: 'Ventas por categor\u00EDa',
            subtitulo: filtro === 'todas' ? 'Categor\u00EDa: todas las categor\u00EDas' : `Categor\u00EDa: ${filtro}`,
            etiquetaBanda: 'Informe de ventas',
            detalleBanda: periodo.texto
        });

        doc.tarjetas([
            { etiqueta: 'TOTAL VENDIDO', valor: PDFInforme.dinero(total), color: '0.835 0.659 0.294' },
            { etiqueta: 'UNIDADES / LIBRAS', valor: PDFInforme.cantidad(unidades), color: '0.31 0.47 0.64' },
            { etiqueta: 'CATEGOR\u00CDAS', valor: String(categorias.length), color: '0.086 0.549 0.525' },
            { etiqueta: 'PRODUCTOS', valor: String(totalProductos), color: '0.46 0.40 0.66' }
        ]);

        // Con varias categorías, primero un resumen comparativo.
        if (categorias.length > 1) {
            doc.seccion('Resumen por categor\u00EDa', 'de mayor a menor venta');
            doc.tabla('CATEGOR\u00CDA');
            categorias.forEach((nombre, i) => doc.fila({
                n: i + 1, nombre, cantidad: grupos[nombre].cantidad, importe: grupos[nombre].importe,
                pct: porcentaje(grupos[nombre].importe, total), par: i % 2 === 0
            }));
        }

        doc.seccion(categorias.length > 1 ? 'Detalle por categor\u00EDa' : 'Detalle de productos', 'productos de mayor a menor importe');
        doc.tabla('PRODUCTO');
        categorias.forEach(nombre => {
            const grupo = grupos[nombre];
            const productos = Object.entries(grupo.productos).sort(([, a], [, b]) => b.importe - a.importe);
            // Barra de la categoría con su subtotal, seguida de sus productos.
            doc.grupo({
                nombre,
                detalle: `${productos.length} producto${productos.length === 1 ? '' : 's'}`,
                cantidad: grupo.cantidad,
                importe: grupo.importe,
                pct: porcentaje(grupo.importe, total)
            });
            productos.forEach(([producto, fila], i) => doc.fila({
                n: i + 1, nombre: producto, cantidad: fila.cantidad, importe: fila.importe,
                pct: porcentaje(fila.importe, total), par: i % 2 === 1
            }));
        });
        doc.seccion('Ventas del periodo', `${detalle.length} ventas`);
        doc.tabla('FECHA / PRODUCTOS');
        detalle.forEach((venta, i) => {
            const fecha = venta.fecha ? venta.fecha.toLocaleDateString('es-GT') : 'Sin fecha';
            doc.grupo({ nombre: fecha, detalle: `Venta ${i + 1}`, cantidad: venta.items.reduce((s, item) => s + item.cantidad, 0), importe: venta.total, pct: porcentaje(venta.total, total) });
            // Los importes de cada producto ya están en el detalle agrupado anterior.
            venta.items.forEach((item, j) => {
                doc.fila({ n: j + 1, nombre: item.nombre, cantidad: item.cantidad, importe: item.importe, pct: porcentaje(item.importe, total), par: j % 2 === 0 });
            });
        });
        doc.total('TOTAL DE VENTAS', unidades, total);

        return doc.finalizar();
    }

    function descargarPDFCategoria() {
        const filtro = categoriaVentasSeleccionada;
        const periodo = periodoSeleccionado();
        if (!periodo.valido) return mostrarAviso('Revisa el rango de fechas', 'error');
        const bytes = construirPDF(filtro, periodo);
        if (!bytes) {
            mostrarAviso('No hay ventas en esta categor\u00EDa para descargar', 'error');
            return;
        }
        const slug = filtro === 'todas' ? 'todas' : filtro.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
        PDFInforme.descargar(bytes, `ventas-categoria-${slug}-${periodo.desde || 'inicio'}-${periodo.hasta || 'actualidad'}.pdf`);
        mostrarAviso('PDF descargado', 'exito');
    }

    let urlsImagen = [];

    function cerrarImagenCategoria() {
        document.getElementById('modal-imagen-categoria').classList.add('hidden');
        document.getElementById('vista-imagen-categoria').replaceChildren();
        urlsImagen.forEach(url => URL.revokeObjectURL(url));
        urlsImagen = [];
    }

    function mostrarImagenCategoria(descargar) {
        const periodo = periodoSeleccionado();
        if (!periodo.valido) return mostrarAviso('Revisa el rango de fechas', 'error');
        const filtro = categoriaVentasSeleccionada;
        const { detalle, total, unidades } = recopilar(filtro, periodo);
        if (!detalle.length) return mostrarAviso('No hay ventas en este periodo', 'error');
        const filas = [];
        detalle.forEach((venta, i) => {
            filas.push({ nombre: `Venta ${i + 1} · ${venta.fecha ? venta.fecha.toLocaleDateString('es-GT') : 'Sin fecha'}`, importe: venta.total, grupo: true });
            venta.items.forEach(item => filas.push(item));
        });
        cerrarImagenCategoria();
        const vista = document.getElementById('vista-imagen-categoria');
        const paginas = Math.ceil(filas.length / 32);
        const slug = filtro.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-zA-Z0-9]+/g, '-');
        for (let pagina = 0; pagina < paginas; pagina++) {
            const bloque = filas.slice(pagina * 32, (pagina + 1) * 32);
            const canvas = document.createElement('canvas');
            canvas.width = 1080;
            canvas.height = 420 + bloque.length * 64;
            const ctx = canvas.getContext('2d');
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            const texto = (valor, x, y, color = '#16324f', font = '24px sans-serif', alineacion = 'left') => {
                ctx.fillStyle = color; ctx.font = font; ctx.textAlign = alineacion;
                ctx.fillText(String(valor), x, y);
            };
            ctx.fillStyle = '#10263d'; ctx.fillRect(0, 0, 1080, 130);
            texto('MI NEGOCIO · Ventas por categoría', 48, 55, '#ffffff', 'bold 32px sans-serif');
            texto(periodo.texto, 48, 99, '#d4e1eb');
            texto(filtro === 'todas' ? 'Todas las categorías' : filtro, 48, 175, '#16324f', 'bold 28px sans-serif');
            texto(`${detalle.length} ventas · ${PDFInforme.cantidad(unidades)} unidades / libras`, 48, 218);
            texto('PRODUCTO / FECHA', 48, 270, '#64748b', 'bold 20px sans-serif');
            texto('CANTIDAD', 815, 270, '#64748b', 'bold 20px sans-serif', 'right');
            texto('IMPORTE', 1032, 270, '#64748b', 'bold 20px sans-serif', 'right');
            bloque.forEach((fila, i) => {
                const y = 290 + i * 64;
                ctx.fillStyle = fila.grupo ? '#dcf0ec' : i % 2 ? '#f3f6f8' : '#ffffff';
                ctx.fillRect(32, y, 1016, 64);
                ctx.font = `${fila.grupo ? 'bold ' : ''}24px sans-serif`;
                let nombre = fila.nombre;
                while (nombre.length > 1 && ctx.measureText(nombre).width > 620) nombre = nombre.slice(0, -1);
                if (nombre !== fila.nombre) nombre = nombre.slice(0, -3) + '…';
                texto(nombre, 48, y + 40, '#16324f', ctx.font);
                if (!fila.grupo) texto(PDFInforme.cantidad(fila.cantidad), 815, y + 40, '#16324f', '24px sans-serif', 'right');
                texto(PDFInforme.dinero(fila.importe), 1032, y + 40, '#16324f', 'bold 24px sans-serif', 'right');
            });
            const yTotal = 302 + bloque.length * 64;
            ctx.fillStyle = '#10263d'; ctx.fillRect(32, yTotal, 1016, 60);
            texto('TOTAL DE VENTAS DEL PERIODO', 48, yTotal + 39, '#ffffff', 'bold 24px sans-serif');
            texto(PDFInforme.dinero(total), 1032, yTotal + 39, '#ffffff', 'bold 28px sans-serif', 'right');
            texto(`Página ${pagina + 1} de ${paginas}`, 1032, canvas.height - 20, '#64748b', '20px sans-serif', 'right');
            const contenedor = document.createElement('div');
            vista.appendChild(contenedor);
            canvas.toBlob(blob => {
                if (!blob || !contenedor.isConnected) return;
                const url = URL.createObjectURL(blob);
                urlsImagen.push(url);
                const imagen = document.createElement('img');
                imagen.src = url; imagen.alt = `Ventas por categoría, página ${pagina + 1}`;
                imagen.className = 'imagen-reporte';
                const enlace = document.createElement('a');
                enlace.href = url;
                enlace.download = `ventas-${slug}-${periodo.desde || 'inicio'}-${periodo.hasta || 'actualidad'}-${pagina + 1}.png`;
                enlace.textContent = `Descargar imagen${paginas > 1 ? ` ${pagina + 1}` : ''} (PNG)`;
                enlace.className = 'pdf-category-btn';
                contenedor.append(imagen, enlace);
                // Un informe largo conserva enlaces individuales para evitar bloqueos de descargas múltiples.
                if (descargar && paginas === 1) enlace.click();
            }, 'image/png');
        }
        document.getElementById('modal-imagen-categoria').classList.remove('hidden');
        if (descargar && paginas > 1) mostrarAviso('Descarga cada página con su botón de imagen', 'exito');
    }

    document.getElementById('btn-imagen-categoria').addEventListener('click', () => mostrarImagenCategoria(true));
    document.getElementById('btn-cerrar-imagen-categoria').addEventListener('click', cerrarImagenCategoria);

    window.renderizarVentasCategoria = renderizarVentasCategoria;
    document.getElementById('categoria-fecha-dia').addEventListener('change', () => {
        renderizarVentasCategoria();
        renderizarVentasHoy();
    });
    renderizarVentasHoy();
    document.getElementById('btn-pdf-categoria')?.addEventListener('click', descargarPDFCategoria);
    renderizarVentasCategoria();
})();
