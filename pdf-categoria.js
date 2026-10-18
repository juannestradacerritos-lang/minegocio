// Descarga un PDF con las ventas agrupadas por categoría.
// Usa la categoría elegida en Resumen ("Todas" o una en particular) y el diseño compartido de pdf-comun.js.
(function () {
    function recopilar(filtro) {
        const grupos = {};
        let total = 0, unidades = 0;
        ventas.forEach(venta => {
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
            });
        });
        return { grupos, total, unidades };
    }

    const porcentaje = (parte, total) => (total > 0 ? parte / total * 100 : 0);

    function construirPDF(filtro) {
        const { grupos, total, unidades } = recopilar(filtro);
        const categorias = Object.keys(grupos).sort((a, b) => grupos[b].importe - grupos[a].importe);
        if (!categorias.length) return null;

        const totalProductos = categorias.reduce((t, c) => t + Object.keys(grupos[c].productos).length, 0);
        const doc = PDFInforme.crearDocumento({
            titulo: 'Ventas por categor\u00EDa',
            subtitulo: filtro === 'todas' ? 'Categor\u00EDa: todas las categor\u00EDas' : `Categor\u00EDa: ${filtro}`,
            etiquetaBanda: 'Informe de ventas',
            detalleBanda: PDFInforme.fechaGeneracion()
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
        doc.total('TOTAL VENDIDO', unidades, total);

        return doc.finalizar();
    }

    function descargarPDFCategoria() {
        const filtro = categoriaVentasSeleccionada;
        const bytes = construirPDF(filtro);
        if (!bytes) {
            mostrarAviso('No hay ventas en esta categor\u00EDa para descargar', 'error');
            return;
        }
        const slug = filtro === 'todas' ? 'todas' : filtro.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
        PDFInforme.descargar(bytes, `ventas-categoria-${slug}-${new Date().toISOString().slice(0, 10)}.pdf`);
        mostrarAviso('PDF descargado', 'exito');
    }

    document.getElementById('btn-pdf-categoria')?.addEventListener('click', descargarPDFCategoria);
})();
