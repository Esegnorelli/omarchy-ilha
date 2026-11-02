import QtQuick
import qs.Commons as Commons

// Letra da tecla impressa no canto de um item (spec §3.2). É sobreposição:
// quem usa posiciona (anchors) e ela nunca entra no layout. Só a letra, sem
// caixa: fica escondida fora do modo teclado e aparece no hover ou no foco.
//
// API pública:
//   letter: string        letra mostrada ("" esconde)
//   keyboardMode: bool    false = escondida (salvo strong/onFill), true = metrics.textKey
//                         (muted um degrau e meio acima, para ler sobre o cartão)
//   strong: bool          item focado ou com hover: letra em fg
//   onFill: bool          item preenchido (ligado/armado): letra na cor do fundo a 85%
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

    // muted fica aqui por compatibilidade (quem usa ainda repassa); a letra
    // em repouso lê metrics.textKey, que já parte do muted do tema.
    readonly property color ink: onFill ? Qt.rgba(bg.r, bg.g, bg.b, 0.85)
                                        : (strong ? fg : metrics.textKey)
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
        font.pixelSize: 11
        font.weight: Font.Bold
        color: badge.ink
        opacity: badge.level
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(badge.metrics.msState); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(badge.metrics.msState); easing.type: Easing.OutCubic } }
    }
}
