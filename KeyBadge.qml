import QtQuick
import qs.Commons as Commons

// Letra da tecla impressa no canto de um item (spec §3.2). É sobreposição:
// quem usa posiciona (anchors) e ela nunca entra no layout.
//
// API pública:
//   letter: string        letra mostrada ("" esconde)
//   keyboardMode: bool    false = apagada (muted a 40%), true = muted cheio
//   strong: bool          item focado ou com hover: cor de destaque
//   onFill: bool          item preenchido (ligado/armado): letra na cor do fundo
//   fg, bg, accent, muted cores do tema
//   metrics: Metrics
Item {
    id: badge

    property string letter: ""
    property bool keyboardMode: false
    property bool strong: false
    property bool onFill: false

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color muted: Commons.Color.muted
    property Metrics metrics: Metrics {}

    visible: letter !== ""
    width: metrics.badge
    height: metrics.badge

    readonly property color ink: onFill ? bg : (strong ? accent : muted)
    readonly property real level: onFill || strong || keyboardMode ? 1 : metrics.opacityBadgeFaint

    // Tecla: contorno fino de cápsula contínua, mesmo tom da letra.
    ContinuousRect {
        anchors.fill: parent
        radius: 4
        color: "transparent"
        borderWidth: 1
        borderColor: Qt.rgba(badge.ink.r, badge.ink.g, badge.ink.b, 0.45)
        opacity: badge.level
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(badge.metrics.msState); easing.type: Easing.OutCubic } }
    }

    Text {
        anchors.centerIn: parent
        text: badge.letter
        textFormat: Text.PlainText
        font.family: "monospace"
        font.pixelSize: 10
        font.weight: Font.DemiBold
        color: badge.ink
        opacity: badge.level
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(badge.metrics.msState); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(badge.metrics.msState); easing.type: Easing.OutCubic } }
    }
}
