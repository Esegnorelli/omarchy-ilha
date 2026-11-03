import QtQuick
import qs.Commons as Commons

// Medida de texto igual à de IlhaText (mesma família, tamanho, peso e tnum).
// FINAL do Phase 0 (dono: lead). Larguras-alvo vêm daqui, nunca de Row.
//
//   IlhaMetrics { id: m; theme: island.theme; size: 16; weight: 500; tnum: true; text: "12:34" }
//   … m.advanceWidth
TextMetrics {
    id: root

    property Theme theme: null
    property real size: 13
    property int weight: 500
    property bool tnum: false

    font.family: root.theme ? root.theme.fontFamily : Commons.Style.fontFamily
    font.pixelSize: Math.max(1, Math.round(root.size))
    font.variableAxes: ({ "wght": root.weight })
    font.features: root.tnum ? ({ "tnum": 1 }) : ({})
}
