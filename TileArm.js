.pragma library

// Registro único dos Tiles de confirmação armados (compartilhado por todas as
// instâncias de Tile.qml, em qualquer painel e monitor). Armar um desarma o
// anterior; Esc chama disarmAll().
//
//   arm(tile)      registra tile como o armado e desarma o anterior
//   release(tile)  esquece tile se ele for o armado (sem chamar disarm)
//   disarmAll()    desarma o armado; devolve true se havia um
//   current()      o tile armado agora, ou null

var armed = null;

function arm(tile) {
    if (armed && armed !== tile) {
        const prev = armed;
        armed = null;
        try { prev.disarm(); } catch (e) { /* tile já destruído */ }
    }
    armed = tile;
}

function release(tile) {
    if (armed === tile) armed = null;
}

function disarmAll() {
    if (!armed) return false;
    const prev = armed;
    armed = null;
    try { prev.disarm(); } catch (e) { return false; }
    return true;
}

function current() {
    return armed;
}
