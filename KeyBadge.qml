import QtQuick
import qs.Commons as Commons

// Letra da tecla impressa no canto de um item (spec §3.2). É sobreposição:
// quem usa posiciona (anchors) e ela nunca entra no layout. Só a letra, sem
// caixa: fica escondida fora do modo teclado e aparece no hover ou no foco.
//
// API pública:
//   letter: string        letra mostrada ("" esconde)
//   keyboardMode: bool    false = escondida (salvo strong/onFill), true = muted a 70%
//   strong: bool          item focado ou com hover: letra em fg
//   onFill: bool          item preenchido (ligado/armado): letra na cor do fundo
//   fg, bg, accent, muted cores do tema
//   fontFamily            fonte do tema (o Tile repassa a do Estilo)
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
    property string fontFamily: Commons.Style.fontFamily
    property Metrics metrics: Metrics {}

    readonly property color ink: onFill ? bg : (strong ? fg : Qt.rgba(muted.r, muted.g, muted.b, 0.7))
    readonly property real level: onFill || strong || keyboardMode ? 1 : 0

    // A opacidade da raiz fica livre para quem usa (a Faixa anima a dela);
    // o nível mora na letra.
    visible: letter !== "" && opacity > 0
    width: metrics.badge
    height: metrics.badge

    Text {
        anchors.centerIn: parent
        text: badge.letter
        textFormat: Text.PlainText
        font.family: badge.fontFamily
        font.pixelSize: 10
        font.weight: Font.DemiBold
        color: badge.ink
        opacity: badge.level
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(badge.metrics.msState); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(badge.metrics.msState); easing.type: Easing.OutCubic } }
    }
}
