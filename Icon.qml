import QtQuick
import qs.Commons as Commons

// Ícone Material Symbols Rounded pelo nome (ligadura): Icon { name: "wifi" }.
// "filled" preenche o ícone com animação — use para estados ligados.
Text {
    id: root

    property string name: ""
    property bool filled: false
    property int size: 18
    property int weight: 400

    // Eixo FILL animado de 0 a 1.
    property real fill: filled ? 1 : 0
    Behavior on fill {
        NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
    }

    text: name
    textFormat: Text.PlainText
    // O preenchimento usa contornos sobrepostos; o render padrão (distance
    // field) deixa buracos neles, o nativo desenha sólido.
    renderType: Text.NativeRendering
    font.family: "Material Symbols Rounded"
    font.pixelSize: size
    font.variableAxes: ({ "FILL": root.fill, "wght": root.weight, "opsz": Math.max(20, Math.min(48, root.size)) })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
