import QtQuick
import "Motion.js" as Motion

// Bloco de alternância da Central: 202 x 57, cápsula com círculo de ícone à
// esquerda e duas linhas de texto. FINAL do Phase 0 (dono: lead).
//
//   ToggleTile { theme: …; title: …; subtitle: …; icon: active ? "wifi" : "wifi_off"
//                active: …; focused: keyboardMode && …; onClicked: …; onIconClicked: … }
//
// - clicked(): corpo do bloco (abre o popover, ou alterna quando a tela quer).
// - iconClicked(): o círculo de 43 (liga/desliga o rádio). Quem quer que o
//   bloco inteiro alterne liga os dois sinais à mesma ação.
// - Ativo: círculo accent com glifo onAccent 15 cheio. Inativo: iconIdle com
//   glifo ink 14 vazado. Hover: card -> tileHover em 110 ms; mãozinha.
// - RTL: as âncoras espelham com o LayoutMirroring herdado da janela.
Item {
    id: root

    property Theme theme: null
    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property bool active: false
    property bool focused: false
    // Some com a entrada do popover (K): só o conteúdo some, o bloco fica.
    property real contentOpacity: 1

    readonly property bool hovered: body.containsMouse || circleArea.containsMouse
    readonly property real radius: height / 2

    signal clicked()
    signal iconClicked()

    implicitWidth: 202
    implicitHeight: 57

    Accessible.role: Accessible.Button
    Accessible.name: root.title
    Accessible.description: root.subtitle

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: root.theme ? (root.hovered ? root.theme.tileHover : root.theme.card) : "transparent"
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
    }

    MouseArea {
        id: body
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Item {
        anchors.fill: parent
        opacity: root.contentOpacity

        Rectangle {
            id: circle
            width: 43
            height: 43
            radius: 21.5
            anchors.left: parent.left
            anchors.leftMargin: 8.5
            anchors.verticalCenter: parent.verticalCenter
            color: root.theme ? (root.active ? root.theme.accent : (circleArea.containsMouse ? root.theme.mix(root.theme.iconIdle, root.theme.ink, 0.06) : root.theme.iconIdle)) : "transparent"
            Behavior on color {
                ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
            }

            Icon {
                anchors.centerIn: parent
                name: root.icon
                size: root.active ? 15 : 14
                filled: root.active
                color: root.theme ? (root.active ? root.theme.onAccent : root.theme.ink) : "white"
            }

            MouseArea {
                id: circleArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.iconClicked()
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 63
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            IlhaText {
                width: parent.width
                theme: root.theme
                size: 15
                weight: 600
                text: root.title
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }
            IlhaText {
                width: parent.width
                theme: root.theme
                size: 11.5
                weight: 400
                color: root.theme ? root.theme.inkMuted : "gray"
                text: root.subtitle
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    FocusRing {
        theme: root.theme
        shown: root.focused
        itemRadius: root.radius
    }
}
