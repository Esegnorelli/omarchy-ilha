import QtQuick
import qs.Commons as Commons

// Texto da Ilha: Inter Ilha2 com peso pelo eixo wght. FINAL do Phase 0
// (dono: lead). Use sempre este no lugar de Text: o Qt não aplica
// font.weight à fonte variável, só font.variableAxes.
//
//   IlhaText { theme: island.theme; size: 14.5; weight: 600; text: … }
//
// - size em px lógicos; frações arredondam (o Qt arredonda do mesmo jeito).
// - tnum: algarismos de largura fixa (relógio, porcentagens, contadores).
// - Cor padrão: theme.ink. Texto simples (PlainText), QtRendering.
// - Para medir a largura de um texto igual a este, use IlhaMetrics com os
//   mesmos size / weight / tnum (regra 4 do anti-glitch).
Text {
    id: root

    property Theme theme: null
    property real size: 13
    property int weight: 500
    property bool tnum: false

    color: root.theme ? root.theme.ink : "white"
    textFormat: Text.PlainText
    renderType: Text.QtRendering
    font.family: root.theme ? root.theme.fontFamily : Commons.Style.fontFamily
    font.pixelSize: Math.max(1, Math.round(root.size))
    font.variableAxes: ({ "wght": root.weight })
    font.features: root.tnum ? ({ "tnum": 1 }) : ({})
}
