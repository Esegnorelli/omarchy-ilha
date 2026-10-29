import QtQuick
import qs.Commons as Commons
import "TileArm.js" as TileArm

// Coluna de linhas de um painel (spec §3.2, §4): GridRow, LabeledRow, InfoRow
// ou um bloco qualquer de altura fixa, com 8 px entre elas. Conta as linhas
// com tecla (até 3) e cuida do teclado.
//
// API pública:
//   filhos: as linhas, em ordem
//   keyboardMode: bool      repassado às linhas (anel de foco e letras cheias)
//   strings                 Commons.Translations repassado (o estado passa o seu)
//   fg, bg, accent, danger, muted, metrics   repassados às linhas
// Funções:
//   handleKey(event) → bool
//       Q W E R / A S D F / Z X C V (por event.key, vale em QWERTY e ABNT2)
//       → ativa o item da linha com tecla 0/1/2 que cobre a coluna 1–4
//       (um tile com span responde a todas as colunas que ocupa);
//       setas → foco 2-D pela geometria (o item focado pode tratar ←→ antes,
//       via handleArrow(key, event) → bool, como slider e chips);
//       Enter/Return/Space → ativa o item focado.
//       Ctrl/Alt/Meta/Shift + letra e auto-repetição não ativam (o estado trata
//       atalhos como ⇧Q antes de chamar aqui). Não liga keyboardMode: quem chama liga.
//   handleEscape() → bool   desarma um confirm armado; true se consumiu
//   focusFirst()            foca o item Q (ou o primeiro focável)
//   itemAtKey(row, col) → Item | null
//   focusItems() → [Item]   todos os itens focáveis, em ordem
//   disarmAll(), hasArmed() → bool   (o registro de armados é global: TileArm.js)
//   relayout()
Item {
    id: grid

    property bool keyboardMode: false
    property var strings: null
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property Metrics metrics: Metrics {}

    default property alias rows: column.data

    implicitWidth: metrics.content
    implicitHeight: column.implicitHeight
    width: implicitWidth

    // ---------- Linhas ----------
    property var _wired: []
    function relayout() { Qt.callLater(grid._assign); }

    function _rows() {
        const out = [];
        for (let i = 0; i < column.children.length; i++) {
            const r = column.children[i];
            if (r.visible) out.push(r);
        }
        return out;
    }

    function _assign() {
        let n = 0;
        for (let i = 0; i < column.children.length; i++) {
            const r = column.children[i];
            if (grid._wired.indexOf(r) < 0) {
                grid._wired.push(r);
                r.visibleChanged.connect(grid.relayout);
                if (r.keyableChanged) r.keyableChanged.connect(grid.relayout);
                for (const p of ["fg", "bg", "accent", "danger", "muted", "metrics", "keyboardMode", "strings"])
                    if (p in r) r[p] = Qt.binding(() => grid[p]);
            }
            if (!r.visible || !("autoKeyRow" in r)) continue;
            if (r.keyable) {
                r.autoKeyRow = n < 3 ? n : -1;
                n++;
            } else {
                r.autoKeyRow = -1;
            }
        }
    }

    Component.onCompleted: _assign()

    // ---------- Foco e teclas ----------
    function focusItems() {
        const out = [];
        for (const r of grid._rows()) {
            if (typeof r.focusItems !== "function") continue;
            for (const it of r.focusItems())
                if (it && it.visible && it.activeFocusOnTab) out.push(it);
        }
        return out;
    }

    function itemAtKey(row, col) {
        for (const r of grid._rows()) {
            if (typeof r.focusItems !== "function") continue;
            for (const it of r.focusItems()) {
                if (!it || !it.visible || typeof it.activate !== "function") continue;
                if (!("keyRow" in it) || it.keyRow !== row || it.keyCol < 0) continue;
                const span = it.keySpan || 1;
                if (col >= it.keyCol && col < it.keyCol + span) return it;
            }
        }
        return null;
    }

    function focusedItem() {
        for (const it of grid.focusItems())
            if (it.activeFocus) return it;
        return null;
    }

    function focusFirst() {
        const q = grid.itemAtKey(0, 0);
        const target = q && q.activeFocusOnTab ? q : grid.focusItems()[0];
        if (target) target.forceActiveFocus(Qt.TabFocusReason);
        return !!target;
    }

    function disarmAll() { return TileArm.disarmAll(); }
    function handleEscape() { return TileArm.disarmAll(); }
    function hasArmed() { return TileArm.current() !== null; }

    readonly property var _letters: ({
        [Qt.Key_Q]: [0, 0], [Qt.Key_W]: [0, 1], [Qt.Key_E]: [0, 2], [Qt.Key_R]: [0, 3],
        [Qt.Key_A]: [1, 0], [Qt.Key_S]: [1, 1], [Qt.Key_D]: [1, 2], [Qt.Key_F]: [1, 3],
        [Qt.Key_Z]: [2, 0], [Qt.Key_X]: [2, 1], [Qt.Key_C]: [2, 2], [Qt.Key_V]: [2, 3]
    })

    function _center(it) {
        const p = it.mapToItem(grid, it.width / 2, it.height / 2);
        return { x: p.x, y: p.y, w: it.width, h: it.height };
    }

    // Vizinho mais próximo na direção: só candidatos à frente; sobreposição no
    // eixo cruzado conta como alinhado; empate fica com o primeiro na ordem.
    function moveFocus(key) {
        const items = grid.focusItems();
        if (items.length === 0) return false;
        const cur = grid.focusedItem();
        if (!cur) return grid.focusFirst();
        const a = grid._center(cur);
        let best = null, bestScore = Infinity;
        for (const it of items) {
            if (it === cur) continue;
            const b = grid._center(it);
            const dx = b.x - a.x, dy = b.y - a.y;
            let primary, cross;
            if (key === Qt.Key_Left || key === Qt.Key_Right) {
                primary = key === Qt.Key_Left ? -dx : dx;
                const overlap = Math.abs(dy) < (a.h + b.h) / 2 - 1;
                cross = overlap ? 0 : Math.abs(dy);
            } else {
                primary = key === Qt.Key_Up ? -dy : dy;
                const overlap = Math.abs(dx) < (a.w + b.w) / 2 - 1;
                cross = overlap ? Math.abs(dx) * 0.1 : Math.abs(dx);
            }
            if (primary <= 1) continue;
            const score = primary + cross * 3;
            if (score < bestScore - 0.5) { best = it; bestScore = score; }
        }
        if (best) best.forceActiveFocus(Qt.TabFocusReason);
        return !!best;
    }

    function handleKey(event) {
        const k = event.key;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier);

        if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down) {
            if (mods) return false;
            const cur = grid.focusedItem();
            if (cur && typeof cur.handleArrow === "function" && cur.handleArrow(k, event)) return true;
            grid.moveFocus(k);
            return true;
        }

        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (mods & ~Qt.ShiftModifier) return false;
            const cur = grid.focusedItem();
            if (!cur || typeof cur.activate !== "function") return false;
            if (event.isAutoRepeat) return true;
            cur.activate();
            return true;
        }

        const pos = grid._letters[k];
        if (pos === undefined || mods) return false;
        const it = grid.itemAtKey(pos[0], pos[1]);
        if (!it) return false;
        if (event.isAutoRepeat) return true;
        if (it.activeFocusOnTab) it.forceActiveFocus(Qt.ShortcutFocusReason);
        it.activate();
        return true;
    }

    Column {
        id: column
        width: parent.width
        spacing: grid.metrics.gap
        onChildrenChanged: grid.relayout()
    }
}
