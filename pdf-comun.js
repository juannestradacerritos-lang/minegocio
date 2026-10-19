// Generador de PDF compartido (sin librerías, Helvetica estándar).
// Lo usan "Ventas por categoría" y "Reporte de ventas" para que ambos tengan el mismo diseño y orden:
// encabezado, tarjetas de resumen, tabla numerada con participación, fila de total y pie con paginación.
(function () {
    const W = 595, H = 842, M = 42, ANCHO = W - M * 2, ALTO_FILA = 24;
    const NAVY = '0.063 0.149 0.239';
    const TEAL = '0.086 0.549 0.525';
    const TEAL_CLARO = '0.88 0.95 0.94';
    const TEAL_OSCURO = '0.06 0.37 0.35';
    const GOLD = '0.835 0.659 0.294';
    const TEXTO = '0.15 0.22 0.30';
    const SUAVE = '0.40 0.47 0.54';
    const CLARO = '0.72 0.82 0.88';
    const ZEBRA = '0.962 0.972 0.978';
    const LINEA = '0.85 0.89 0.92';
    const BLANCO = '1 1 1';

    // Posiciones de las columnas de las tablas.
    const X = { n: M + 18, nombre: M + 40, cant: 335, barra: 352, barraAncho: 90, pct: 486, importe: W - M - 10 };

    const AN = { ' ': 278, '.': 278, ',': 278, ':': 278, ';': 278, '/': 278, 'i': 222, 'j': 222, 'l': 222, 't': 278, 'f': 278, 'r': 333, 'I': 278,
        '(': 333, ')': 333, '-': 333, 'm': 833, 'w': 722, 'M': 833, 'W': 944, 'Q': 778, '%': 889, '\u00B7': 278 };
    const anchoTexto = (s, size, negrita) =>
        [...limpiar(s)].reduce((t, c) => t + (AN[c] ?? (c >= 'A' && c <= 'Z' ? 667 : 556)), 0) * size / 1000 * (negrita ? 1.06 : 1);

    function limpiar(s) {
        return String(s)
            .replace(/[\u201C\u201D]/g, '"').replace(/[\u2018\u2019]/g, "'")
            .replace(/[\u2013\u2014]/g, '-').replace(/\u2026/g, '...')
            .replace(/[^\x20-\xFF]/g, '?');
    }
    const escapar = s => limpiar(s).replace(/[\\()]/g, '\\$&');

    const dinero = n => 'Q' + (Number(n) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    const cantidad = n => (Number(n) || 0).toLocaleString('en-US', { maximumFractionDigits: 2 });

    function ajustar(s, size, max, negrita) {
        s = String(s);
        if (anchoTexto(s, size, negrita) <= max) return s;
        while (s.length > 1 && anchoTexto(s + '...', size, negrita) > max) s = s.slice(0, -1);
        return s.trimEnd() + '...';
    }

    function crearDocumento({ titulo, subtitulo, etiquetaBanda, detalleBanda }) {
        const paginas = [];
        let ops = [];
        let numero = 0;
        let columnas = null;
        const doc = { y: 0 };

        const texto = (x, y, s, { size = 9.5, negrita = false, color = TEXTO, alinear = 'izq' } = {}) => {
            const w = anchoTexto(s, size, negrita);
            const px = alinear === 'der' ? x - w : alinear === 'centro' ? x - w / 2 : x;
            ops.push(`BT /${negrita ? 'F2' : 'F1'} ${size} Tf ${color} rg ${px.toFixed(2)} ${y.toFixed(2)} Td (${escapar(s)}) Tj ET`);
        };
        const rect = (x, y, w, h, color) => ops.push(`${color} rg ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re f`);
        const linea = (x1, y1, x2, y2, color = LINEA, grosor = .6) =>
            ops.push(`${color} RG ${grosor} w ${x1} ${y1} m ${x2} ${y2} l S`);

        function encabezadoPrimera() {
            rect(0, H - 100, W, 100, NAVY);
            rect(0, H - 104, W, 4, GOLD);
            rect(M, H - 72, 40, 40, TEAL);
            texto(M + 20, H - 57, 'MN', { size: 13, negrita: true, color: BLANCO, alinear: 'centro' });
            texto(M + 54, H - 50, 'MI NEGOCIO', { size: 11, negrita: true, color: BLANCO });
            texto(M + 54, H - 64, 'Control de inventario y ventas', { size: 8, color: CLARO });
            texto(W - M, H - 50, String(etiquetaBanda).toUpperCase(), { size: 9, negrita: true, color: BLANCO, alinear: 'der' });
            texto(W - M, H - 64, detalleBanda, { size: 8, color: CLARO, alinear: 'der' });
            texto(M, H - 138, titulo, { size: 21, negrita: true, color: NAVY });
            texto(M, H - 156, subtitulo, { size: 9.5, color: SUAVE });
            linea(M, H - 168, W - M, H - 168);
            doc.y = H - 198;
        }

        function encabezadoCompacto() {
            rect(0, H - 38, W, 38, NAVY);
            rect(0, H - 41, W, 3, GOLD);
            texto(M, H - 24, 'MI NEGOCIO', { size: 9, negrita: true, color: BLANCO });
            texto(W - M, H - 24, `${titulo} (continuaci\u00F3n)`, { size: 8.5, color: CLARO, alinear: 'der' });
            doc.y = H - 74;
        }

        function cabeceraTabla() {
            rect(M, doc.y - 8, ANCHO, ALTO_FILA, NAVY);
            columnas.forEach(c => texto(c.x, doc.y + 1.5, c.t, { size: 7.5, negrita: true, color: BLANCO, alinear: c.al }));
            doc.y -= ALTO_FILA;
        }

        function nuevaPagina() {
            if (ops.length) paginas.push(ops.join('\n'));
            ops = [];
            numero++;
            if (numero === 1) encabezadoPrimera();
            else {
                encabezadoCompacto();
                if (columnas) cabeceraTabla();
            }
        }

        // Pasa a una página nueva si no queda espacio para el bloque que sigue.
        function asegurar(alto) {
            if (doc.y - alto < 72) nuevaPagina();
        }

        nuevaPagina();

        doc.tarjetas = items => {
            const hueco = 10, h = 58;
            const w = (ANCHO - hueco * (items.length - 1)) / items.length;
            items.forEach((it, i) => {
                const x = M + i * (w + hueco);
                rect(x, doc.y - h, w, h, '0.95 0.968 0.975');
                rect(x, doc.y - h, 4, h, it.color || TEAL);
                texto(x + 16, doc.y - 19, it.etiqueta, { size: 7, negrita: true, color: SUAVE });
                let size = 16;
                while (size > 9 && anchoTexto(it.valor, size, true) > w - 26) size -= 1;
                texto(x + 16, doc.y - 43, it.valor, { size, negrita: true, color: NAVY });
            });
            doc.y -= h + 30;
        };

        doc.seccion = (titulo, detalle) => {
            columnas = null;
            asegurar(90);
            rect(M, doc.y - 3, 4, 17, TEAL);
            texto(M + 13, doc.y, titulo, { size: 12.5, negrita: true, color: NAVY });
            if (detalle) texto(W - M, doc.y, detalle, { size: 8.5, color: SUAVE, alinear: 'der' });
            doc.y -= 26;
        };

        // Encabezado de tabla estándar: #, nombre, cantidad, participación e importe.
        doc.tabla = primeraColumna => {
            columnas = [
                { t: '#', x: X.n, al: 'centro' },
                { t: primeraColumna, x: X.nombre, al: 'izq' },
                { t: 'CANTIDAD', x: X.cant, al: 'der' },
                { t: 'PARTICIPACI\u00D3N', x: X.barra, al: 'izq' },
                { t: 'IMPORTE', x: X.importe, al: 'der' }
            ];
            asegurar(ALTO_FILA * 3);
            cabeceraTabla();
        };

        doc.fila = ({ n, nombre, cantidad: cant, pct, importe, par }) => {
            asegurar(ALTO_FILA);
            const y = doc.y;
            if (par) rect(M, y - 8, ANCHO, ALTO_FILA, ZEBRA);
            texto(X.n, y, String(n), { size: 8.5, color: SUAVE, alinear: 'centro' });
            texto(X.nombre, y, ajustar(nombre, 9.5, X.cant - 50 - X.nombre), { size: 9.5 });
            texto(X.cant, y, cantidad(cant), { size: 9.5, alinear: 'der' });
            rect(X.barra, y + 0.5, X.barraAncho, 5, '0.89 0.92 0.94');
            if (pct > 0) rect(X.barra, y + 0.5, Math.max(2, X.barraAncho * Math.min(pct, 100) / 100), 5, TEAL);
            texto(X.pct, y, `${pct.toFixed(1)}%`, { size: 8.5, color: SUAVE, alinear: 'der' });
            texto(X.importe, y, dinero(importe), { size: 9.5, negrita: true, alinear: 'der' });
            linea(M, y - 8, W - M, y - 8, '0.9 0.93 0.95', .4);
            doc.y -= ALTO_FILA;
        };

        // Fila de encabezado de una categoría (agrupa los productos que siguen).
        doc.grupo = ({ nombre, detalle, cantidad: cant, pct, importe }) => {
            asegurar(ALTO_FILA * 2 + 14);
            doc.y -= 10;
            const y = doc.y;
            rect(M, y - 8, ANCHO, ALTO_FILA, TEAL_CLARO);
            rect(M, y - 8, 4, ALTO_FILA, TEAL);
            const nombreAjustado = ajustar(nombre, 10.5, 200, true);
            texto(M + 14, y, nombreAjustado, { size: 10.5, negrita: true, color: TEAL_OSCURO });
            if (detalle) texto(M + 14 + anchoTexto(nombreAjustado, 10.5, true) + 8, y, detalle, { size: 8, color: SUAVE });
            texto(X.cant, y, cantidad(cant), { size: 10, negrita: true, color: TEAL_OSCURO, alinear: 'der' });
            texto(X.pct, y, `${pct.toFixed(1)}%`, { size: 9, negrita: true, color: TEAL_OSCURO, alinear: 'der' });
            texto(X.importe, y, dinero(importe), { size: 10, negrita: true, color: TEAL_OSCURO, alinear: 'der' });
            doc.y -= ALTO_FILA;
        };

        doc.total = (etiqueta, cant, importe) => {
            asegurar(ALTO_FILA + 24);
            doc.y -= 12;
            const y = doc.y;
            rect(M, y - 10, ANCHO, 30, NAVY);
            rect(M, y - 10, 4, 30, GOLD);
            texto(M + 16, y + 1, etiqueta, { size: 9.5, negrita: true, color: BLANCO });
            texto(X.cant, y + 1, cantidad(cant), { size: 10, negrita: true, color: BLANCO, alinear: 'der' });
            texto(X.importe, y + 1, dinero(importe), { size: 12, negrita: true, color: BLANCO, alinear: 'der' });
            doc.y -= 40;
        };

        doc.vacio = mensaje => {
            asegurar(90);
            rect(M, doc.y - 40, ANCHO, 56, '0.955 0.968 0.975');
            texto(W / 2, doc.y - 14, mensaje, { size: 11, negrita: true, color: SUAVE, alinear: 'centro' });
            texto(W / 2, doc.y - 30, 'Cuando registres ventas aparecer\u00E1n aqu\u00ED.', { size: 8.5, color: SUAVE, alinear: 'centro' });
            doc.y -= 70;
        };

        doc.finalizar = () => {
            paginas.push(ops.join('\n'));
            const fecha = new Date().toLocaleString('es-GT', { dateStyle: 'medium', timeStyle: 'short' });
            const contenidos = paginas.map((contenido, i) => {
                ops = [];
                linea(M, 52, W - M, 52, '0.78 0.83 0.86');
                texto(M, 36, `Generado: ${fecha}`, { size: 7.5, color: SUAVE });
                texto(W / 2, 36, 'Documento generado por Mi Negocio', { size: 7.5, color: SUAVE, alinear: 'centro' });
                texto(W - M, 36, `P\u00E1gina ${i + 1} de ${paginas.length}`, { size: 7.5, negrita: true, color: NAVY, alinear: 'der' });
                return `${contenido}\n${ops.join('\n')}`;
            });

            const objetos = [];
            const idPagina = i => 5 + i * 2;
            objetos[1] = '<< /Type /Catalog /Pages 2 0 R >>';
            objetos[2] = `<< /Type /Pages /Kids [${contenidos.map((_, i) => `${idPagina(i)} 0 R`).join(' ')}] /Count ${contenidos.length} >>`;
            objetos[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
            objetos[4] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';
            contenidos.forEach((contenido, i) => {
                objetos[idPagina(i)] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${W} ${H}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${idPagina(i) + 1} 0 R >>`;
                objetos[idPagina(i) + 1] = `<< /Length ${contenido.length} >>\nstream\n${contenido}\nendstream`;
            });

            let salida = '%PDF-1.4\n';
            const posiciones = [];
            for (let i = 1; i < objetos.length; i++) {
                posiciones[i] = salida.length;
                salida += `${i} 0 obj\n${objetos[i]}\nendobj\n`;
            }
            const inicioXref = salida.length;
            salida += `xref\n0 ${objetos.length}\n0000000000 65535 f \n`;
            for (let i = 1; i < objetos.length; i++) salida += `${String(posiciones[i]).padStart(10, '0')} 00000 n \n`;
            salida += `trailer\n<< /Size ${objetos.length} /Root 1 0 R >>\nstartxref\n${inicioXref}\n%%EOF`;

            const bytes = new Uint8Array(salida.length);
            for (let i = 0; i < salida.length; i++) bytes[i] = salida.charCodeAt(i) & 255;
            return bytes;
        };

        return doc;
    }

    function descargar(bytes, nombreArchivo) {
        const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
        const enlace = document.createElement('a');
        enlace.href = url;
        enlace.download = nombreArchivo;
        document.body.appendChild(enlace);
        enlace.click();
        enlace.remove();
        setTimeout(() => URL.revokeObjectURL(url), 2000);
    }

    const fechaGeneracion = () => {
        const ahora = new Date();
        return `Generado el ${ahora.toLocaleDateString('es-GT', { day: '2-digit', month: 'long', year: 'numeric' })}, ${ahora.toLocaleTimeString('es-GT', { hour: '2-digit', minute: '2-digit' })}`;
    };

    window.PDFInforme = { crearDocumento, descargar, dinero, cantidad, fechaGeneracion };

    // Abrir el formulario no depende de consultas a la nube ni de elementos auxiliares.
    window.abrirModalReportes = function () {
        const modal = document.getElementById('modal-reportes');
        if (!modal) return;
        const fecha = modal.querySelector('#fecha-reporte');
        if (fecha) {
            const hoy = new Date();
            fecha.value = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-${String(hoy.getDate()).padStart(2, '0')}`;
        }
        const estado = modal.querySelector('#estado-reporte');
        if (estado) {
            estado.textContent = '';
            estado.classList.add('hidden');
        }
        modal.classList.remove('hidden');
        fecha?.focus({ preventScroll: true });
    };

    // Reemplaza el PDF del "Reporte de ventas" de Ajustes por el diseño compartido.
    window.descargarReportePDF = function (reporte) {
        const partes = String(reporte.rangoTexto || '').split(' \u2014 ');
        const rango = partes.length === 2 && partes[0] === partes[1] ? partes[0] : partes.join(' al ');
        const doc = crearDocumento({
            titulo: reporte.titulo,
            subtitulo: `Periodo: ${rango}`,
            etiquetaBanda: 'Informe de ventas',
            detalleBanda: fechaGeneracion()
        });

        const productos = [...reporte.productos].sort((a, b) => b.total - a.total);
        const promedio = reporte.numeroVentas ? reporte.total / reporte.numeroVentas : 0;
        doc.tarjetas([
            { etiqueta: 'VENTAS', valor: String(reporte.numeroVentas), color: TEAL },
            { etiqueta: 'UNIDADES / LIBRAS', valor: cantidad(reporte.unidades), color: '0.31 0.47 0.64' },
            { etiqueta: 'TOTAL VENDIDO', valor: dinero(reporte.total), color: GOLD },
            { etiqueta: 'PROMEDIO POR VENTA', valor: dinero(promedio), color: '0.46 0.40 0.66' }
        ]);

        doc.seccion('Detalle por producto', productos.length ? `${productos.length} producto${productos.length === 1 ? '' : 's'} \u00B7 de mayor a menor importe` : '');
        if (!productos.length) {
            doc.vacio('Sin ventas registradas en este periodo');
        } else {
            doc.tabla('PRODUCTO');
            const suma = productos.reduce((t, p) => t + p.total, 0);
            productos.forEach((p, i) => doc.fila({
                n: i + 1, nombre: p.nombre, cantidad: p.cantidad, importe: p.total,
                pct: suma > 0 ? p.total / suma * 100 : 0, par: i % 2 === 0
            }));
            doc.total('TOTAL DEL PERIODO', reporte.unidades, reporte.total);
        }

        const fechaArchivo = document.getElementById('fecha-reporte')?.value || new Date().toISOString().slice(0, 10);
        descargar(doc.finalizar(), `Reporte_${reporte.tipo}_${fechaArchivo}.pdf`);
    };
})();
