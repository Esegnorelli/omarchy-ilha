import QtQuick
import qs.Commons as Commons

// Ícone Material Symbols Rounded pelo nome (ligadura): Icon { name: "wifi" }.
// FINAL do Phase 0 (dono: lead).
//
// - O nome é SEMPRE um literal de dev/icons.txt escrito no próprio arquivo
//   (condicional como `cond ? "a" : "b"`, nunca concatenado). dev/icons.py
//   confere cada literal com HarfBuzz; um ícone novo passa pelo lead.
// - A caixa é size x size: o layout nunca depende da métrica do glifo.
// - "filled" anima o eixo FILL (180 ms; 0 com reduzir movimento).
// - NativeRendering: o preenchimento usa contornos sobrepostos e o render
//   padrão deixa buracos. Um glifo que muda de tamanho entre L1 e L2 é
//   desenhado no tamanho maior e só escalado para baixo.
// - A fonte vem com o plugin (fonts/MaterialSymbolsRoundedIlha2.ttf): o
//   Omarchy não instala Material Symbols.
Text {
    id: root

    property string name: ""
    property real size: 18
    property bool filled: false
    property int weight: 400

    // Eixo FILL animado de 0 a 1.
    property real fill: root.filled ? 1 : 0
    Behavior on fill {
        NumberAnimation { duration: Commons.Style.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic }
    }

    width: root.size
    height: root.size
    text: root.name
    textFormat: Text.PlainText
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: "white"
    Accessible.ignored: true

    FontLoader {
        id: symbols
        source: Qt.resolvedUrl("../fonts/MaterialSymbolsRoundedIlha2.ttf")
    }
    font.family: symbols.status === FontLoader.Ready ? symbols.name : "Material Symbols Rounded"
    font.pixelSize: Math.max(1, Math.round(root.size))
    font.variableAxes: ({ "FILL": root.fill, "wght": root.weight, "opsz": Math.max(20, Math.min(48, root.size)) })
}
