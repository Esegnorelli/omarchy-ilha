import QtQuick
import qs.Commons as Commons

// Botão redondo com um ícone Material Symbols (nome em "icon"). No hover ganha um fundo suave em
// cápsula contínua; ao tocar cede um pouco. "highlighted" é a pílula do estado
// aberto (spec §2): accent a 18%, ícone em accent e preenchido.
//
// API pública: icon, label, highlighted, size (36), iconSize (20), fg, accent,
// readonly hovered, readonly pressed; sinal tapped().
Item {
    id: button

    // Nome do ícone Material Symbols, por exemplo "tune".
    property string icon: ""
    property color fg: Commons.Color.bar.text
    property color accent: Commons.Color.accent
    // Destaca o botão (por exemplo, o estado aberto agora).
    property bool highlighted: false
    property int size: 36
    property int iconSize: 20
    // Nome para leitores de tela; quem usa passa um texto traduzido.
    property string label: ""
    // Legenda pequena embaixo do ícone (o dígito da categoria); "" esconde.
    // Com legenda, o ícone sobe para dar lugar a ela dentro da pílula.
    property string caption: ""
    property color muted: Commons.Color.muted

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: tapHandler.pressed

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
        color: button.highlighted ? Qt.rgba(button.accent.r, button.accent.g, button.accent.b, 0.18)
                                  : Qt.rgba(button.fg.r, button.fg.g, button.fg.b, 0.10)
        opacity: hoverHandler.hovered || button.highlighted ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
        }
    }

    Icon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: button.caption !== "" ? -5 : 0
        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }
        name: button.icon
        size: button.iconSize
        filled: button.highlighted
        color: button.highlighted ? button.accent : button.fg
        opacity: hoverHandler.hovered || button.highlighted ? 1 : 0.82

        Behavior on color {
            ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        text: button.caption
        textFormat: Text.PlainText
        font.family: "monospace"
        font.pixelSize: 9
        font.weight: Font.DemiBold
        color: button.highlighted ? button.accent : button.muted
        opacity: button.caption !== "" ? 1 : 0
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
