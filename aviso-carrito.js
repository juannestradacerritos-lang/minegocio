// Confirma la cantidad acumulada sin confundirla con el último incremento.
(function () {
    const original = window.agregarAlCarrito;
    if (typeof original !== 'function') return;

    const cantidades = () => {
        const mapa = new Map();
        (carrito || []).forEach(item => {
            mapa.set(item.nombre, (mapa.get(item.nombre) || 0) + (Number(item.cantidad) || 0));
        });
        return mapa;
    };

    const formatear = n => String(Number(n.toFixed(2)));

    function avisarCambio(antes) {
        const despues = cantidades();
        let nombre = null, total = 0;
        despues.forEach((cantidad, clave) => {
            if (cantidad > (antes.get(clave) || 0)) { nombre = clave; total = cantidad; }
        });
        if (nombre !== null) mostrarAviso(`${nombre} · Ahora tienes ${formatear(total)} en el carrito`, 'exito');
    }

    window.agregarAlCarrito = function (...args) {
        const antes = cantidades();
        const resultado = original.apply(this, args);
        if (resultado && typeof resultado.then === 'function') {
            return resultado.then(valor => { avisarCambio(antes); return valor; });
        }
        avisarCambio(antes);
        return resultado;
    };
})();
