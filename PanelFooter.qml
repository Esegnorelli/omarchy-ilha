import QtQuick
import qs.Commons as Commons

// Rodapé de 20 px de todo painel (spec §3.1): estado à esquerda, dicas de
// teclado à direita, ambos 11 px muted. As dicas cedem espaço ao estado.
//
// API pública:
//   status: string    estado ao vivo ("Bateria 82% · carregando", "Pronto"…)
//   hints: string     dica do painel ("Q–F alternar · −/= volume · M mudo")
//   alert: bool       estado em danger (por exemplo um confirm armado)
//   fg, danger, muted, metrics
Item {
    id: footer

    property string status: ""
    property string hints: ""
    property bool alert: false

    property color fg: Commons.Color.bar.text
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property Metrics metrics: Metrics {}

    implicitWidth: metrics.content
    implicitHeight: metrics.footer
    width: implicitWidth
    height: implicitHeight

    Text {
        id: statusText
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, footer.width - 2 - (hintsText.text !== "" ? Math.min(hintsText.implicitWidth, footer.width * 0.55) + 16 : 0))
        text: footer.status
        textFormat: Text.PlainText
        font.pixelSize: footer.metrics.footerText
        font.weight: footer.alert ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        color: footer.alert ? footer.danger : footer.muted
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(footer.metrics.msState); easing.type: Easing.OutCubic } }
    }

    Text {
        id: hintsText
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, footer.width - statusText.width - 18)
        horizontalAlignment: Text.AlignRight
        text: footer.hints
        textFormat: Text.PlainText
        font.pixelSize: footer.metrics.footerText
        elide: Text.ElideLeft
        color: footer.muted
        opacity: 0.85
    }
}
