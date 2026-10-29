import QtQuick
import QtQuick.Shapes

// Retângulo com cantos contínuos: a curva começa antes e entra suave na
// reta, em vez do arco de círculo do Rectangle.radius. Com radius igual a
// metade da altura vira uma cápsula.
Item {
    id: root

    property color color: "transparent"
    property color borderColor: "transparent"
    property real borderWidth: 0
    property real radius: 0
    // Quanto a curva se estende pela reta (0 = arco de círculo).
    property real smoothing: 0.6

    // A curva ocupa radius * (1 + smoothing) de cada lado, limitada à metade
    // do lado menor para não se cruzar.
    readonly property real r: Math.max(0, Math.min(radius, width / 2, height / 2))
    readonly property real reach: Math.min(r * (1 + smoothing), width / 2, height / 2)
    // Pontos de controle: perto da quina para o canto ficar cheio.
    readonly property real handle: reach * (0.45 - 0.2 * smoothing)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            strokeWidth: root.borderWidth

            startX: root.reach
            startY: 0

            PathLine { x: root.width - root.reach; y: 0 }
            PathCubic {
                x: root.width; y: root.reach
                control1X: root.width - root.handle; control1Y: 0
                control2X: root.width; control2Y: root.handle
            }
            PathLine { x: root.width; y: root.height - root.reach }
            PathCubic {
                x: root.width - root.reach; y: root.height
                control1X: root.width; control1Y: root.height - root.handle
                control2X: root.width - root.handle; control2Y: root.height
            }
            PathLine { x: root.reach; y: root.height }
            PathCubic {
                x: 0; y: root.height - root.reach
                control1X: root.handle; control1Y: root.height
                control2X: 0; control2Y: root.height - root.handle
            }
            PathLine { x: 0; y: root.reach }
            PathCubic {
                x: root.reach; y: 0
                control1X: 0; control1Y: root.handle
                control2X: root.handle; control2Y: 0
            }
        }
    }
}
