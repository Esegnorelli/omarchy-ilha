import QtQuick
import qs.Commons as Commons

// Botão redondo com um ícone Nerd Font. No hover ganha um fundo suave em
// cápsula contínua; ao tocar cede um pouco.
Item {
    id: button

    property string icon: ""
    property color fg: Commons.Color.bar.text
    property color accent: Commons.Color.accent
    // Destaca o botão (por exemplo, o estado aberto agora).
    property bool highlighted: false
    property int size: 30
    property int iconSize: 15
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

    Text {
        anchors.centerIn: parent
        text: button.icon
        color: button.highlighted ? button.accent : button.fg
        opacity: hoverHandler.hovered || button.highlighted ? 1 : 0.82
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: button.iconSize
        textFormat: Text.PlainText

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
