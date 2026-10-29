import QtQuick
import QtQuick.Shapes

// Forma de notch: colada na borda de cima, com curvas côncavas onde encontra
// a tela e cantos de baixo contínuos. Desenhada na GPU pelo CurveRenderer.
//
//   ‾‾\              /‾‾   <- flare: a borda de cima entra na forma
//      |            |
//       \__________/       <- cantos de baixo contínuos
Item {
    id: root

    property color color: "transparent"
    // Raio dos cantos de baixo.
    property real radius: 18
    // Tamanho da curva côncava de cada lado do topo.
    property real flare: 10
    // Suavização dos cantos de baixo (0 = arco de círculo).
    property real smoothing: 0.6

    // O corpo do notch fica entre as duas curvas do topo.
    readonly property real bodyWidth: Math.max(0, width - 2 * f)
    readonly property real f: Math.max(0, Math.min(flare, width / 4, height))
    readonly property real r: Math.max(0, Math.min(radius, bodyWidth / 2, height - f))
    readonly property real reach: Math.min(r * (1 + smoothing), bodyWidth / 2, height - f)
    readonly property real handle: reach * (0.45 - 0.2 * smoothing)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            strokeWidth: 0

            startX: 0
            startY: 0

            // Curva côncava da esquerda, do topo até o corpo.
            PathQuad { x: root.f; y: root.f; controlX: root.f; controlY: 0 }
            PathLine { x: root.f; y: root.height - root.reach }
            PathCubic {
                x: root.f + root.reach; y: root.height
                control1X: root.f; control1Y: root.height - root.handle
                control2X: root.f + root.handle; control2Y: root.height
            }
            PathLine { x: root.width - root.f - root.reach; y: root.height }
            PathCubic {
                x: root.width - root.f; y: root.height - root.reach
                control1X: root.width - root.f - root.handle; control1Y: root.height
                control2X: root.width - root.f; control2Y: root.height - root.handle
            }
            PathLine { x: root.width - root.f; y: root.f }
            // Curva côncava da direita, de volta ao topo.
            PathQuad { x: root.width; y: 0; controlX: root.width - root.f; controlY: 0 }
            PathLine { x: 0; y: 0 }
        }
    }
}
