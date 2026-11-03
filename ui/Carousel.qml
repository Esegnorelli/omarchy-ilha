pragma ComponentBehavior: Bound
import QtQuick
import "Motion.js" as Motion

// Faixa horizontal dos seletores de tema e papel de parede (dono: Agent G).
// O escolhido fica sempre no centro: a faixa anda, o destaque não.
//
// - offset: o índice contínuo no centro agora. Anda 300 ms OutQuad até o
//   índice; uma tecla nova no meio redireciona do valor atual (teclas
//   seguradas deslizam). Nada anima com `snapping` ou reduzir movimento.
// - Além das pontas a faixa rebate 24 px e volta (300 ms, OutBack 1,2).
// - delegate: Component; cada instância recebe `index`, `d` (distância
//   contínua ao centro, em cartões: 0 no centro, ±1 nos vizinhos) e, se
//   declarar, `selected` (index === carousel.index, muda no quadro da tecla).
// - dir: +1 LTR, −1 RTL (o próximo fica à esquerda). A tela troca as setas.
// - Clique num cartão o centraliza; clique no do centro, ou duplo clique em
//   qualquer um, emite activated(i). Roda: um passo a cada 120 unidades
//   (o resto some depois de 200 ms parado).
// - moved() avisa quando o mouse andou a faixa (a tela para de recentrar).
// - Sem laço e sem esmaecer nas bordas: o recorte é duro (clip), como no vídeo.
Item {
    id: root

    property int count: 0
    property int index: 0
    property real pitch: 194
    property real itemWidth: 187
    property real itemHeight: 98
    property Component delegate: null
    property int dir: 1
    property bool snapping: false
    // A tela liga theme.reduceMotion: tudo pula.
    property bool reduceMotion: false

    readonly property real offset: priv.offset
    // Até que distância |d| um cartão pode aparecer na faixa (o resto não desenha).
    readonly property int reach: Math.ceil(root.width / Math.max(1, root.pitch) / 2) + 1

    signal activated(int i)
    // O usuário andou a faixa pelo mouse (clique que centraliza, roda).
    signal moved()

    function clampIndex(i) {
        return root.count > 0 ? Math.max(0, Math.min(root.count - 1, Math.round(i))) : 0;
    }

    // n cartões para frente (negativo: para trás). Na ponta, rebate.
    function step(n) {
        if (root.count === 0 || n === 0)
            return;
        const j = root.clampIndex(root.index + n);
        if (j === root.index) {
            priv.rebound(n < 0 ? -1 : 1);
            return;
        }
        root.jump(j, true);
    }

    // Vai ao índice i; animate false pula (abrir, filtrar).
    function jump(i, animate) {
        const j = root.clampIndex(i);
        priv.snap = !animate;
        priv.own = true;
        root.index = j;
        priv.own = false;
        priv.offset = j;
        priv.snap = false;
    }

    // Uma atribuição de fora (index: …) também anda a faixa.
    onIndexChanged: {
        if (priv.own)
            return;
        const j = root.clampIndex(root.index);
        if (j !== root.index) {
            root.index = j;
            return;
        }
        priv.offset = j;
    }

    // A lista mudou de tamanho (filtro): o índice fica dentro e a faixa pula.
    onCountChanged: root.jump(root.index, false)

    QtObject {
        id: priv
        property real offset: 0
        property bool snap: false
        property bool own: false
        // Rebate da ponta, em px (translação da faixa inteira).
        property real bump: 0
        // Toque: o cartão do primeiro toque, para o duplo clique.
        property int tapIndex: -1
        property bool tapFired: false
        // Roda
        property real wheelAcc: 0
        property real wheelAt: 0

        readonly property bool still: priv.snap || root.snapping || root.reduceMotion

        function rebound(sign) {
            if (root.reduceMotion || root.snapping)
                return;
            // Começo (sign −1): a faixa passa um pouco para o lado do anterior.
            bumpOut.to = -root.dir * sign * Motion.FADE.CAROUSEL_REBOUND.px;
            rebounce.restart();
        }

        // Índice do cartão sob o ponto (coordenadas da faixa), ou −1.
        function hitIndex(px, py) {
            const cx = root.width / 2 + priv.bump;
            const rel = (px - cx) * root.dir / root.pitch;
            const i = Math.round(priv.offset + rel);
            if (i < 0 || i >= root.count)
                return -1;
            const ix = cx + root.dir * (i - priv.offset) * root.pitch;
            if (Math.abs(px - ix) > root.itemWidth / 2 + 2)
                return -1;
            // Folga vertical para o cartão levantado do tema (8 px).
            if (Math.abs(py - root.height / 2) > root.itemHeight / 2 + 10)
                return -1;
            return i;
        }

        Behavior on offset {
            enabled: !priv.still
            NumberAnimation {
                duration: Motion.FADE.CAROUSEL.dur
                easing.type: Easing.OutQuad
            }
        }
    }

    SequentialAnimation {
        id: rebounce
        NumberAnimation {
            id: bumpOut
            target: priv
            property: "bump"
            duration: 90
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: priv
            property: "bump"
            to: 0
            duration: Motion.FADE.CAROUSEL_REBOUND.dur - 90
            easing.type: Easing.OutBack
            easing.overshoot: Motion.FADE.CAROUSEL_REBOUND.overshoot
        }
    }

    clip: true
    Accessible.role: Accessible.List

    Item {
        id: strip
        x: priv.bump
        width: root.width
        height: root.height

        Repeater {
            model: root.count

            Loader {
                id: cell
                required property int index
                readonly property real d: cell.index - priv.offset
                readonly property bool near: Math.abs(cell.d) <= root.reach

                sourceComponent: root.delegate
                width: root.itemWidth
                height: root.itemHeight
                x: root.width / 2 - root.itemWidth / 2 + root.dir * cell.d * root.pitch
                y: (root.height - root.itemHeight) / 2
                // Fora da faixa não desenha (não muda tamanho de nada).
                visible: cell.near

                onLoaded: {
                    const it = cell.item;
                    if (!it)
                        return;
                    if ("index" in it)
                        it.index = Qt.binding(() => cell.index);
                    if ("d" in it)
                        it.d = Qt.binding(() => cell.d);
                    if ("selected" in it)
                        it.selected = Qt.binding(() => cell.index === root.index);
                }
            }
        }
    }

    HoverHandler {
        cursorShape: root.count > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: eventPoint => {
            const p = eventPoint.position;
            // Segundo toque da sequência: aplica o cartão do primeiro.
            if (tap.tapCount >= 2 && priv.tapIndex >= 0) {
                if (!priv.tapFired) {
                    priv.tapFired = true;
                    root.activated(priv.tapIndex);
                }
                return;
            }
            const i = priv.hitIndex(p.x, p.y);
            priv.tapIndex = i;
            priv.tapFired = false;
            if (i < 0)
                return;
            if (i === root.index) {
                priv.tapFired = true;
                root.activated(i);
            } else {
                root.jump(i, true);
                root.moved();
            }
        }
    }

    WheelHandler {
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const dy = event.angleDelta.y;
            const dx = event.angleDelta.x;
            const delta = Math.abs(dy) >= Math.abs(dx) ? dy : dx;
            if (delta === 0)
                return;
            const now = Date.now();
            if (now - priv.wheelAt > Motion.TIMING.WHEEL_DECAY_MS || (priv.wheelAcc !== 0 && Math.sign(priv.wheelAcc) !== Math.sign(delta)))
                priv.wheelAcc = 0;
            priv.wheelAt = now;
            priv.wheelAcc += delta;
            while (Math.abs(priv.wheelAcc) >= Motion.TIMING.WHEEL_STEP) {
                // Roda para baixo (negativo) = próximo.
                const s = priv.wheelAcc < 0 ? 1 : -1;
                priv.wheelAcc += s * Motion.TIMING.WHEEL_STEP;
                root.step(s);
                root.moved();
            }
        }
    }
}
