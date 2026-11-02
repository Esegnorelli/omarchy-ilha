import QtQuick
import qs.Commons as Commons

// Rodapé de 20 px de todo painel (spec §3.1): estado à esquerda, dicas de
// teclado à direita, 11 px na fonte do tema: estado em metrics.textSecondary,
// dicas em fg a 55%. As dicas cedem espaço ao estado (ficam com pelo menos 45%
// da largura) e cortam no fim, com um respiro fixo (hintGap) entre os dois.
//
// API pública:
//   status: string    estado ao vivo ("Bateria 82% · carregando", "Pronto"…)
//   hints: string     dica do painel ("Q–F alternar · −/= volume · M mudo")
//   alert: bool       estado em danger (por exemplo um confirm armado)
//   fg, danger, muted, metrics, fontFamily
Item {
    id: footer

    property string status: ""
    property string hints: ""
    property bool alert: false

    property color fg: Commons.Color.bar.text
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property string fontFamily: Commons.Style.fontFamily
    property Metrics metrics: Metrics {}

    // Respiro entre o estado e as dicas: os dois nunca encostam.
    readonly property int hintGap: 24

    // RTL (ar, fa, he, ur): dicas e estado que começam com letras latinas de
    // tecla ("Q–F …") ganhariam direção base LTR e embaralhariam os trechos.
    // O U+200F (RIGHT-TO-LEFT MARK) no início força a base RTL, e cada texto
    // fica alinhado à direita, para cada trecho ficar junto da sua tecla.
    readonly property bool rtl: Commons.I18n.rightToLeft
    function bidi(s) { return footer.rtl && s !== "" ? "\u200F" + s : s; }
    // Alinhamento explícito é espelhado pelo LayoutMirroring herdado da ilha;
    // este valor dá direita na tela com ou sem espelhamento.
    readonly property int alignRight: LayoutMirroring.enabled ? Text.AlignLeft : Text.AlignRight

    implicitWidth: metrics.content
    implicitHeight: metrics.footer
    width: implicitWidth
    height: implicitHeight

    Text {
        id: statusText
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, footer.width - 4 - (hintsText.text !== "" ? Math.min(hintsText.implicitWidth, footer.width * 0.55) + footer.hintGap : 0)))
        horizontalAlignment: footer.rtl ? footer.alignRight : Text.AlignLeft
        text: footer.bidi(footer.status)
        textFormat: Text.PlainText
        font.family: footer.fontFamily
        font.pixelSize: footer.metrics.footerText
        font.weight: footer.alert ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        color: footer.alert ? footer.danger : footer.metrics.textSecondary
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(footer.metrics.msState); easing.type: Easing.OutCubic } }
    }

    Text {
        id: hintsText
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, footer.width - 4 - (statusText.text !== "" ? statusText.width + footer.hintGap : 0)))
        horizontalAlignment: footer.alignRight
        text: footer.bidi(footer.hints)
        textFormat: Text.PlainText
        font.family: footer.fontFamily
        font.pixelSize: footer.metrics.footerText
        // Corta no fim: o começo da dica é o que importa ("Q–F alternar…").
        elide: Text.ElideRight
        color: Qt.rgba(footer.fg.r, footer.fg.g, footer.fg.b, 0.55)
    }
}
