import QtQuick
import "Motion.js" as Motion

// Barra de ajuste da Central (volume, brilho, temperatura): trilho em
// cápsula, preenchimento accent sem botão e um glifo dentro do
// preenchimento. FINAL do Phase 0 (dono: lead).
//
//   IlhaSlider { theme: …; width: 466; value: audio.volume; glyph: "volume_up"
//                onMoved: v => audio.setVolume(v); onCommitted: v => …
//                onGlyphTapped: audio.toggleMute() }
//
// - value em 0..1. Mudanças externas animam 120 ms; ao arrastar, nada anima.
// - moved(v) durante o arraste / clique / roda; committed(v) ao soltar (e a
//   cada passo da roda ou de nudge()).
// - Toque no glifo (primeiros 30 px, movimento < 3 px): glyphTapped(), sem
//   mudar o valor.
// - Roda: ±0,02 por entalhe (step é o passo de nudge() para o teclado).
// - enabled: false -> opacidade 0,4 e sem entrada.
// - mirrored: o preenchimento cresce da direita (RTL). O padrão segue o
//   tema; a barra de progresso da mídia nunca usa este componente.
Item {
    id: root

    property Theme theme: null
    property real value: 0
    property string glyph: ""
    property bool glyphFilled: false
    property real glyphSize: 16
    property real barHeight: 24
    property color trackColor: root.theme ? root.theme.track : "black"
    property color fillColor: root.theme ? root.theme.accent : "white"
    property color glyphColor: root.theme ? root.theme.onAccent : "black"
    property real step: 0.05
    property bool mirrored: root.theme ? root.theme.rtl : false
    property bool focused: false
    property string accessibleName: ""

    readonly property bool dragging: priv.dragging
    readonly property bool hovered: area.containsMouse
    // Valor mostrado agora (o do arraste enquanto arrasta).
    readonly property real shownValue: priv.dragging ? priv.dragValue : root.value

    signal moved(real v)
    signal committed(real v)
    signal glyphTapped()

    // Passo de teclado (±step) ou qualquer delta: emite moved e committed.
    function nudge(delta) {
        const v = Math.max(0, Math.min(1, root.value + delta));
        root.moved(v);
        root.committed(v);
    }

    implicitWidth: 200
    implicitHeight: root.barHeight
    opacity: root.enabled ? 1 : 0.4

    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName

    QtObject {
        id: priv
        property bool dragging: false
        property real dragValue: 0
        property real pressX: 0
        property bool glyphPress: false
        property bool moved: false
        // Largura mínima do preenchimento: o glifo sempre fica em cima do accent.
        readonly property real minFill: root.barHeight + 6

        function valueAt(x) {
            const w = Math.max(1, root.width);
            const lx = root.mirrored ? w - x : x;
            return Math.max(0, Math.min(1, lx / w));
        }
    }

    // Largura visual do preenchimento (anima só mudanças externas).
    property real fillWidth: Math.max(priv.minFill, root.shownValue * root.width)
    Behavior on fillWidth {
        enabled: !priv.dragging
        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.SLIDER) : 0; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
    }

    Rectangle {
        id: fill
        height: parent.height
        width: Math.min(root.width, root.fillWidth)
        x: root.mirrored ? root.width - width : 0
        radius: height / 2
        color: root.fillColor
    }

    Icon {
        name: root.glyph
        size: root.glyphSize
        filled: root.glyphFilled
        color: root.glyphColor
        anchors.verticalCenter: parent.verticalCenter
        x: root.mirrored ? root.width - 6 - width : 6
        visible: root.glyph !== ""
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        onPressed: mouse => {
            priv.pressX = mouse.x;
            priv.moved = false;
            const lx = root.mirrored ? root.width - mouse.x : mouse.x;
            priv.glyphPress = root.glyph !== "" && lx <= 30;
            if (!priv.glyphPress) {
                priv.dragging = true;
                priv.dragValue = priv.valueAt(mouse.x);
                root.moved(priv.dragValue);
            }
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            if (Math.abs(mouse.x - priv.pressX) >= 3)
                priv.moved = true;
            if (priv.glyphPress && priv.moved) {
                priv.glyphPress = false;
                priv.dragging = true;
            }
            if (priv.dragging) {
                priv.dragValue = priv.valueAt(mouse.x);
                root.moved(priv.dragValue);
            }
        }
        onReleased: mouse => {
            if (priv.glyphPress && !priv.moved) {
                priv.glyphPress = false;
                root.glyphTapped();
                return;
            }
            if (priv.dragging) {
                const v = priv.dragValue;
                priv.dragging = false;
                root.committed(v);
            }
        }
        onCanceled: {
            if (priv.dragging) {
                const v = priv.dragValue;
                priv.dragging = false;
                root.committed(v);
            }
            priv.glyphPress = false;
        }
        onWheel: wheel => {
            const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
            if (d === 0)
                return;
            root.nudge(d > 0 ? 0.02 : -0.02);
        }
    }

    FocusRing {
        theme: root.theme
        shown: root.focused
        itemRadius: root.height / 2
    }
}
