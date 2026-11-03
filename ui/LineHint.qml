import QtQuick
import QtQuick.Effects
import "Motion.js" as Motion

// Dica da linha (amendments §7): uma cápsula pequena abaixo do L1 na
// primeira vez que a linha abre na sessão ("Clique: mais · Botão direito ou
// segurar: telas · Alt+1–6: trocar"). Desenhada pela IslandWindow FORA do
// recorte do conteúdo e fora da máscara (a entrada passa por ela).
//
// O gatilho e o tempo (HINT_IN.delay, HINT_MS) são da IslandWindow; aqui
// ficam o desenho e o fade:
// - Entra em 120 ms (OutCubic) descendo 4 px até o lugar.
// - Sai em 150 ms quando a face volta ao repouso; em 60 ms (fast) quando vai
//   para qualquer outra face. A IslandWindow liga `fast` ANTES de desligar
//   `shown`, então a duração certa vale já no quadro da troca.
//
// - Centro x = cx; topo = 22 + 42 + 8 = 72 (topY: o Item reserva `top`); altura 26; raio 13.
// - Largura = clamp(texto + 24, 120, min(560, telaW − 48)).
// - Texto 12 / 500, tinta a 85%, uma linha; encolhe até 10 px e só então corta.
Item {
    id: root

    property Theme theme: null
    property var strings: null
    property bool glassy: false
    property bool shown: false
    property real cx: 960
    property real topY: 72
    property real screenW: 1920
    property bool fast: false

    readonly property string text: root.strings ? root.strings.t("hint.line") : ""
    implicitWidth: Math.max(root.theme ? root.theme.px.HINT_MIN_W : 120,
        Math.min(Math.min(root.theme ? root.theme.px.HINT_MAX_W : 560, root.screenW - 48), Math.ceil(metrics.advanceWidth) + 24))
    implicitHeight: root.theme ? root.theme.px.HINT_H : 26

    // Deslocamento vertical da entrada (−4 -> 0); a saída não se mexe.
    property real dy: 0

    x: root.cx - root.implicitWidth / 2
    y: root.topY + root.dy
    width: root.implicitWidth
    height: root.implicitHeight
    opacity: 0
    visible: root.opacity > 0

    Accessible.role: Accessible.StaticText
    Accessible.name: root.text
    Accessible.ignored: !root.shown

    onShownChanged: {
        fadeIn.stop();
        fadeOut.stop();
        if (!root.theme || root.theme.reduceMotion) {
            root.dy = 0;
            root.opacity = root.shown ? 1 : 0;
            return;
        }
        if (root.shown) {
            root.dy = Motion.FADE.HINT_IN.dyFrom * (1 - root.opacity);
            fadeIn.start();
        } else {
            fadeOut.duration = root.fast ? Motion.FADE.HINT_OUT_FAST : Motion.FADE.HINT_OUT;
            fadeOut.start();
        }
    }

    ParallelAnimation {
        id: fadeIn
        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: Motion.FADE.HINT_IN.dur
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "dy"
            to: 0
            duration: Motion.FADE.HINT_IN.dur
            easing.type: Easing.OutCubic
        }
    }

    NumberAnimation {
        id: fadeOut
        target: root
        property: "opacity"
        to: 0
        duration: Motion.FADE.HINT_OUT
        easing.type: Easing.OutCubic
    }

    IlhaMetrics {
        id: metrics
        theme: root.theme
        size: 12
        weight: 500
        text: root.text
    }

    RectangularShadow {
        anchors.fill: bg
        radius: bg.radius
        blur: 18
        offset.y: 3
        spread: 0
        color: Qt.rgba(0, 0, 0, root.glassy ? 0.30 : 0.40)
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.height / 2
        antialiasing: true
        color: root.theme ? root.theme.surface : "black"
        border.width: 1
        border.color: root.theme ? root.theme.rim : "transparent"
    }

    IlhaText {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        theme: root.theme
        size: 12
        weight: 500
        color: root.theme ? root.theme.alpha(root.theme.ink, 0.85) : "white"
        text: root.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 10
        elide: Text.ElideRight
        maximumLineCount: 1
    }
}
