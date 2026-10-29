import QtQuick
import qs.Commons as Commons

// Botão redondo com um ícone Material Symbols (nome em "icon"). No hover ganha um fundo suave em
// cápsula contínua; ao tocar cede um pouco.
Item {
    id: button

    // Nome do ícone Material Symbols, por exemplo "tune".
    property string icon: ""
    property color fg: Commons.Color.bar.text
    property color accent: Commons.Color.accent
    // Destaca o botão (por exemplo, o estado aberto agora).
    property bool highlighted: false
    property int size: 30
    property int iconSize: 19
    // Nome para leitores de tela; quem usa passa um texto traduzido.
    property string label: ""

    readonly property bool hovered: hoverHandler.hovered

    signal tapped()

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Accessible.role: Accessible.Button
    Accessible.name: button.label

    ContinuousRect {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(button.fg.r, button.fg.g, button.fg.b, button.highlighted ? 0.14 : 0.10)
        opacity: hoverHandler.hovered || button.highlighted ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }
    }

    Icon {
        anchors.centerIn: parent
        name: button.icon
        size: button.iconSize
        filled: button.highlighted
        color: button.highlighted ? button.accent : button.fg
        opacity: hoverHandler.hovered || button.highlighted ? 1 : 0.82

        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }
    }

    scale: tapHandler.pressed ? 0.94 : 1

    Behavior on scale {
        NumberAnimation { duration: Commons.Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
    }

    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tapHandler
        onTapped: button.tapped()
    }
}
