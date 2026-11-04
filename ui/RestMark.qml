pragma ComponentBehavior: Bound
import QtQuick
import "Motion.js" as Motion

// Marca do repouso (amendments §4): o ícone do indicador mais importante
// ligado (StatusSvc.markKey), o tempo da gravação ao lado e, com música
// tocando, três barrinhas paradas encostadas no relógio. Fica DENTRO do
// HoverBar, em coordenadas da janela; o HoverBar faz os fades de entrada e
// saída desta camada inteira (A, B, E, H, I, N, P) mexendo em `opacity`.
//
// Geometria publicada (ALVO, para geometryFor ctx.markW, a coluna da marca e
// o toque; nunca anima):
//   iconPart = markKey !== "" ? 16 : 0
//   timePart = gravando com tempo ? 4 + timeW : 0       (timeW: IlhaMetrics 12/600 tnum)
//   barsPart = barras ? (iconPart + timePart > 0 ? 5 : 0) + 9 : 0
//   markW    = iconPart + timePart + barsPart            (0 = sem marca)
//   LTR: mark.right = clockLeft − 8 | RTL: mark.left = clockRight + 8
//
// Desenho: o conteúdo é montado a partir do lado do relógio (as barrinhas
// sempre encostam nele; em RTL a ordem interna inverte e o tempo segue LTR)
// e acompanha o relógio VIVO: uma mola "hover" igual à restDxSpring da janela
// segue o centro do relógio. Assim, quando o tempo ganha um algarismo
// (9:59 -> 10:00), a marca desliza junto com o relógio, sem fade. Com a marca
// invisível (fora do repouso) a mola pula direto para o alvo: ela reaparece
// no lugar final.
//
// Troca de conteúdo (R): o que está desenhado é uma cópia (`shown`); quando
// a chave, o tempo visível ou as barrinhas mudam, o conteúdo antigo sai em
// 60 ms e o novo entra em 90 ms depois de 60 ms (MARK_SWAP).
//
//   hitTest(x, y) em coordenadas da janela -> "mark" | "mark:media" | ""
Item {
    id: root

    property Theme theme: null
    property var strings: null
    property var status: null
    property var media: null
    property var morph: null
    property bool rtl: false
    // Bordas do relógio no repouso (ALVO, já com restDx), em coordenadas da janela.
    property real clockLeft: 0
    property real clockRight: 0
    // Ponteiro na coluna da marca (markHold): destaque.
    property bool highlighted: false

    // ---- Conteúdo vivo (alvo) ----
    // Repouso = só a hora. A única exceção é a gravação (privacidade); o resto
    // dos estados aparece no aviso ao vivo e no nível 2.
    readonly property string markKey: root.status && root.status.isOn("recording") ? "recording" : ""
    readonly property bool recTimeShown: root.markKey === "recording" && !!root.status && root.status.recordingSeconds >= 0
    readonly property bool barsShown: false
    readonly property real iconPartW: root.markKey !== "" ? priv.px("MARK_ICON", 16) : 0
    readonly property real timePartW: root.recTimeShown ? priv.px("MARK_TIME_GAP", 4) + Math.ceil(timeMetrics.advanceWidth) : 0
    readonly property real barsPartW: root.barsShown ? ((root.iconPartW + root.timePartW > 0) ? priv.px("MARK_BARS_GAP", 5) : 0) + priv.px("MARK_BARS_W", 9) : 0
    readonly property real markW: root.iconPartW + root.timePartW + root.barsPartW

    // Retângulo da marca (alvo) em coordenadas da janela.
    readonly property real markLeft: root.rtl ? root.clockRight + priv.px("MARK_GAP", 8) : root.clockLeft - priv.px("MARK_GAP", 8) - root.markW
    readonly property real centerY: root.morph ? root.morph.bandY : 26
    // Barrinhas ± 3 px (para "mark:media"), em coordenadas da janela.
    readonly property rect barsRect: {
        if (!root.barsShown)
            return Qt.rect(0, 0, 0, 0);
        const bw = priv.px("MARK_BARS_W", 9);
        const bx = root.rtl ? root.markLeft : root.markLeft + root.markW - bw;
        return Qt.rect(bx - 3, 0, bw + 6, priv.px("ZONE_REST_H", 46));
    }

    // "mark:media" nas barrinhas (± 3 px, divisa no meio do vão de 5 px); sem
    // ícone nem tempo, a marca inteira é "mark:media". "" fora da marca.
    function hitTest(x, y) {
        if (root.markW <= 0)
            return "";
        if (y < 0 || y > priv.px("ZONE_REST_H", 46))
            return "";
        if (x < root.markLeft - 6 || x > root.markLeft + root.markW + 6)
            return "";
        if (root.barsShown) {
            if (root.iconPartW + root.timePartW <= 0)
                return "mark:media";
            const half = priv.px("MARK_BARS_GAP", 5) / 2;
            const bw = priv.px("MARK_BARS_W", 9);
            const split = root.rtl ? root.markLeft + bw + half : root.markLeft + root.markW - bw - half;
            if (root.rtl ? x <= split : x >= split)
                return "mark:media";
        }
        return "mark";
    }

    // Nome acessível do que a marca diz agora.
    readonly property string accessibleText: {
        if (root.markKey === "nightlight")
            return root.strings ? root.strings.t("peek.nightLightOn") : "";
        if (root.markKey !== "" && root.status) {
            const line = root.status.statusFor(root.markKey);
            return line && line.text ? String(line.text) : "";
        }
        if (root.barsShown && root.strings)
            return priv.fmt(root.strings.t("bar.nowPlaying"), [root.media.title]);
        return "";
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleText
    Accessible.ignored: root.markW <= 0

    QtObject {
        id: priv

        function px(name, fallback) {
            return root.theme && root.theme.px[name] !== undefined ? root.theme.px[name] : fallback;
        }

        // %1, %2… sem avisos quando o catálogo não tem o marcador.
        function fmt(pattern, args) {
            return String(pattern || "").replace(/%(\d)/g, (m, n) => args[Number(n) - 1] !== undefined ? String(args[Number(n) - 1]) : m);
        }

        // Último tempo de gravação não vazio (o conteúdo que sai não perde o texto).
        property string lastClock: ""
    }

    Connections {
        target: root.status
        function onRecordingClockChanged() {
            if (root.status.recordingClock !== "")
                priv.lastClock = root.status.recordingClock;
        }
    }

    IlhaMetrics {
        id: timeMetrics
        theme: root.theme
        size: 12
        weight: 600
        tnum: true
        text: root.status ? root.status.recordingClock : ""
    }

    // ---- O que está desenhado (cópia para a troca R) ----
    QtObject {
        id: shown
        property string key: ""
        property bool rec: false
        property bool bars: false
    }

    readonly property string signature: root.markKey + "|" + root.recTimeShown + "|" + root.barsShown

    function applyShown() {
        shown.key = root.markKey;
        shown.rec = root.recTimeShown;
        shown.bars = root.barsShown;
        if (root.status && root.status.recordingClock !== "")
            priv.lastClock = root.status.recordingClock;
    }

    onSignatureChanged: {
        // Invisível (fora do repouso) ou sem movimento: troca direto.
        if (root.opacity <= 0.01 || !root.theme || root.theme.reduceMotion) {
            swapAnim.stop();
            root.applyShown();
            content.opacity = 1;
            return;
        }
        swapAnim.restart();
    }

    SequentialAnimation {
        id: swapAnim
        NumberAnimation {
            target: content
            property: "opacity"
            to: 0
            duration: Motion.FADE.MARK_SWAP.out
            easing.type: Easing.OutCubic
        }
        ScriptAction { script: root.applyShown() }
        NumberAnimation {
            target: content
            property: "opacity"
            to: 1
            duration: Motion.FADE.MARK_SWAP.inDur
            easing.type: Easing.OutCubic
        }
    }

    // ---- Larguras do que está desenhado ----
    IlhaMetrics {
        id: drawTimeMetrics
        theme: root.theme
        size: 12
        weight: 600
        tnum: true
        text: priv.lastClock
    }
    readonly property real drawIconW: shown.key !== "" ? priv.px("MARK_ICON", 16) : 0
    readonly property real drawTimeW: shown.rec ? Math.ceil(drawTimeMetrics.advanceWidth) : 0
    readonly property real drawTimePartW: shown.rec ? priv.px("MARK_TIME_GAP", 4) + root.drawTimeW : 0
    readonly property real drawBarsPartW: shown.bars ? ((root.drawIconW + root.drawTimePartW > 0) ? priv.px("MARK_BARS_GAP", 5) : 0) + priv.px("MARK_BARS_W", 9) : 0
    readonly property real drawW: root.drawIconW + root.drawTimePartW + root.drawBarsPartW

    // ---- Relógio vivo: centro alvo seguido por uma mola "hover" ----
    readonly property real clockCenterTarget: (root.clockLeft + root.clockRight) / 2
    readonly property real clockHalf: Math.max(0, (root.clockRight - root.clockLeft) / 2)

    SpringValue { id: follow }

    // Desliza só quando visível e por pouco (restDx muda dezenas de px); um
    // salto grande (a primeira medida, outra tela) pula direto.
    onClockCenterTargetChanged: {
        if (root.opacity > 0.01 && Math.abs(follow.value - root.clockCenterTarget) < 120)
            follow.go(root.clockCenterTarget, "hover");
        else
            follow.snap(root.clockCenterTarget);
    }
    onOpacityChanged: {
        if (root.opacity <= 0.01 && follow.target !== root.clockCenterTarget)
            follow.snap(root.clockCenterTarget);
    }
    Component.onCompleted: {
        follow.snap(root.clockCenterTarget);
        root.applyShown();
    }

    // Borda da marca do lado do relógio (LTR: a direita; RTL: a esquerda).
    readonly property real edge: root.rtl ? follow.value + root.clockHalf + priv.px("MARK_GAP", 8)
                                          : follow.value - root.clockHalf - priv.px("MARK_GAP", 8)
    readonly property real drawLeft: root.rtl ? root.edge : root.edge - root.drawW

    // Posições internas, a partir do lado do relógio.
    readonly property real barsX: root.rtl ? root.edge : root.edge - priv.px("MARK_BARS_W", 9)
    readonly property real afterBars: shown.bars ? priv.px("MARK_BARS_W", 9) + priv.px("MARK_BARS_GAP", 5) : 0
    readonly property real timeX: root.rtl ? root.edge + root.afterBars : root.edge - root.afterBars - root.drawTimeW
    readonly property real afterTime: shown.rec ? root.drawTimeW + priv.px("MARK_TIME_GAP", 4) : 0
    readonly property real iconBoxX: root.rtl ? root.edge + root.afterBars + root.afterTime
                                              : root.edge - root.afterBars - root.afterTime - priv.px("MARK_ICON", 16)

    // ---- Destaque com o ponteiro na coluna da marca ----
    Rectangle {
        x: root.drawLeft - 6
        width: root.drawW + 12
        height: 24
        y: root.centerY - 12
        radius: 12
        color: root.theme ? root.theme.hoverOverlay : "transparent"
        opacity: root.highlighted && root.drawW > 0 ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: root.theme ? root.theme.dur(root.highlighted ? Motion.FADE.MARK_HIGHLIGHT_IN : Motion.FADE.MARK_HIGHLIGHT_OUT) : 0
                easing.type: Easing.OutCubic
            }
        }
    }

    // ---- Conteúdo (opacidade da troca R) ----
    Item {
        id: content
        anchors.fill: parent

        // Ícone 14 numa caixa de 16, na cor do tom.
        Icon {
            x: root.iconBoxX + (priv.px("MARK_ICON", 16) - width) / 2
            y: root.centerY - height / 2
            size: priv.px("MARK_GLYPH", 14)
            name: root.status && shown.key !== "" ? root.status.iconFor(shown.key) : ""
            filled: !!root.status && root.status.filledFor(shown.key)
            color: root.theme && root.status ? root.theme.toneColor(root.status.toneFor(shown.key)) : "white"
            opacity: shown.key !== "" ? 1 : 0
        }

        // Tempo da gravação: 12/600 tnum em danger, sempre LTR.
        IlhaText {
            LayoutMirroring.enabled: false
            x: root.timeX
            width: root.drawTimeW
            y: root.centerY - height / 2
            theme: root.theme
            size: 12
            weight: 600
            tnum: true
            horizontalAlignment: Text.AlignLeft
            color: root.theme ? root.theme.danger : "red"
            text: priv.lastClock
            opacity: shown.rec ? 1 : 0
        }

        // Três barras de 2 px, vão 1,5, alturas 6 / 10 / 7, PARADAS (animar
        // redesenharia a janela inteira a 60 qps enquanto a música toca),
        // base numa caixa de 10 centrada em centerY.
        Item {
            LayoutMirroring.enabled: false
            x: root.barsX
            y: root.centerY - 5
            width: priv.px("MARK_BARS_W", 9)
            height: 10
            opacity: shown.bars ? 1 : 0
            Repeater {
                model: [6, 10, 7]
                Rectangle {
                    required property var modelData
                    required property int index
                    x: index * 3.5
                    y: 10 - height
                    width: 2
                    height: modelData
                    radius: 1
                    color: root.theme ? root.theme.accent : "white"
                }
            }
        }
    }
}
