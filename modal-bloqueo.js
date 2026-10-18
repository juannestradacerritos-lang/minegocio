// Bloquea el desplazamiento de la página mientras haya algún modal abierto.
// Detecta cualquier elemento con id "modal-*" que deje de tener la clase "hidden".
(function () {
    // Solo las ventanas reales (clase "fixed"); ids como "modal-total-cobro" son simples textos.
    const SELECTOR_ABIERTO = '.fixed[id^="modal-"]:not(.hidden)';
    let bloqueado = false;
    let posicion = 0;

    function actualizar() {
        const hayModal = Boolean(document.querySelector(SELECTOR_ABIERTO));
        if (hayModal && !bloqueado) {
            // Se congela el body en su posición actual; así tampoco se mueve en iOS.
            posicion = window.scrollY;
            document.body.style.top = `-${posicion}px`;
            document.body.classList.add('modal-abierto');
            bloqueado = true;
        } else if (!hayModal && bloqueado) {
            document.body.classList.remove('modal-abierto');
            document.body.style.top = '';
            window.scrollTo({ top: posicion, behavior: 'instant' });
            bloqueado = false;
        }
    }

    new MutationObserver(mutaciones => {
        if (mutaciones.some(m => m.target.id && m.target.id.startsWith('modal-') && m.target.classList.contains('fixed'))) actualizar();
    }).observe(document.body, { attributes: true, attributeFilter: ['class'], subtree: true });

    actualizar();
})();
