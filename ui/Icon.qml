import QtQuick
import qs.Commons as Commons

// Ícone. name é uma ligadura Material (Icon { name: "wifi" }). glyph, quando
// preenchido, é o glifo cru do menu do Omarchy, na mesma fonte do shell
// (Commons.Style.font.family): uma atualização do menu não depende do recorte
// Material que vem com o plugin.
//
// - O nome Material é SEMPRE um literal de dev/icons.txt escrito no próprio
//   arquivo. dev/icons.py confere cada literal com HarfBuzz.
// - A caixa é size x size: o layout nunca depende da métrica do glifo.
// - "filled" anima o eixo FILL só na fonte Material (180 ms; 0 com reduzir
//   movimento). O glifo do Omarchy não tem esse eixo.
// - NativeRendering: o preenchimento Material usa contornos sobrepostos.
Text {
    id: root

    property string name: ""
    // Glifo do Omarchy (fonte do shell). Vazio: ligadura Material em name.
    property string glyph: ""
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
    text: root.glyph !== "" ? root.glyph : root.name
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
    font.family: root.glyph !== "" ? Commons.Style.font.family
        : (symbols.status === FontLoader.Ready ? symbols.name : "Material Symbols Rounded")
    font.pixelSize: Math.max(1, Math.round(root.size))
    font.variableAxes: root.glyph !== "" ? ({}) : ({ "FILL": root.fill, "wght": root.weight, "opsz": Math.max(20, Math.min(48, root.size)) })
}
