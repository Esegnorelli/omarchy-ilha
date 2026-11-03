import QtQuick

// A forma da ilha: quatro canais de mola (w, h, top, cap). FINAL do Phase 0
// (dono: lead). É a ÚNICA coisa que anima a pílula; o retângulo da janela só
// lê os valores daqui.
//
//   to({w, h, top, cap}, motion)        campos ausentes mantêm o alvo atual
//   topTo(v, motion, atrasoMs)          só o topo (o mergulho do E)
//   heightTo(h, motion)                 só a altura (telas que mudam de altura)
//   snap({w, h, top, cap})              pula, sem animar
//
// radius = min(h/2, cap); inset = 0,2929·radius (o recorte seguro dos cantos).
// A pílula é sempre centrada em centerX; cresce para baixo e para os lados.
//
// É um QtObject (não Item): o Item do Qt 6.12 reserva top / left / right /
// bottom como propriedades FINAL das linhas de âncora.
QtObject {
    id: root

    // Centro horizontal da forma, em coordenadas da janela (cx da tela).
    property real centerX: 0

    readonly property real w: root.cw.value
    readonly property real h: root.ch.value
    readonly property real top: root.ct.value
    readonly property real cap: root.cc.value
    readonly property real radius: Math.max(0, Math.min(root.h / 2, root.cap))
    readonly property real left: root.centerX - root.w / 2
    readonly property real right: root.centerX + root.w / 2
    readonly property real bottom: root.top + root.h
    readonly property real centerY: root.top + root.h / 2
    readonly property real inset: 0.2929 * root.radius
    readonly property bool moving: root.cw.moving || root.ch.moving || root.ct.moving || root.cc.moving

    // O alvo atual (a máscara e a zona de hover usam isto, nunca o valor animado).
    readonly property var target: ({ w: root.cw.target, h: root.ch.target, top: root.ct.target, cap: root.cc.target })

    // Os quatro canais pararam.
    signal settled()

    function to(geom, motion) {
        if (!geom)
            return;
        if (geom.w !== undefined)
            root.cw.go(geom.w, motion);
        if (geom.h !== undefined)
            root.ch.go(geom.h, motion);
        if (geom.top !== undefined)
            root.ct.go(geom.top, motion);
        if (geom.cap !== undefined)
            root.cc.go(geom.cap, motion);
    }

    function topTo(v, motion, delayMs) {
        root.ct.go(v, motion, delayMs || 0);
    }

    function heightTo(hh, motion) {
        root.ch.go(hh, motion);
    }

    function snap(geom) {
        if (!geom)
            return;
        if (geom.w !== undefined)
            root.cw.snap(geom.w);
        if (geom.h !== undefined)
            root.ch.snap(geom.h);
        if (geom.top !== undefined)
            root.ct.snap(geom.top);
        if (geom.cap !== undefined)
            root.cc.snap(geom.cap);
    }

    onMovingChanged: if (!root.moving) root.settled()

    // Canais (internos).
    property SpringValue cw: SpringValue {}
    property SpringValue ch: SpringValue {}
    property SpringValue ct: SpringValue {}
    property SpringValue cc: SpringValue {}
}
