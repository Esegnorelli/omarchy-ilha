import QtQuick
import "Motion.js" as Motion

// Botão redondo de 60 da Central (Bloquear, Luz noturna). FINAL do Phase 0
// (dono: lead).
//
//   IlhaRoundButton { theme: …; icon: "dark_mode"; filled: true; active: …
//                     focused: …; onClicked: …; onRightClicked: … }
//
// - Inativo: fill card, glifo ink. Ativo: fill accent, glifo onAccent.
// - Hover: card -> tileHover (ativo: accent clareia 6% para a tinta), 110 ms.
Item {
    id: root

    property Theme theme: null
    property string icon: ""
    property bool filled: false
    property bool active: false
    property bool focused: false
    property real glyphSize: 18
    property string accessibleName: ""

    readonly property bool hovered: area.containsMouse

    signal clicked()
    signal rightClicked()

    implicitWidth: 60
    implicitHeight: 60

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: !root.theme ? "transparent"
            : root.active ? (root.hovered ? root.theme.mix(root.theme.accent, root.theme.ink, 0.06) : root.theme.accent)
            : (root.hovered ? root.theme.tileHover : root.theme.card)
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: root.glyphSize
        filled: root.filled
        color: root.theme ? (root.active ? root.theme.onAccent : root.theme.ink) : "white"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }

    FocusRing {
        theme: root.theme
        shown: root.focused
        itemRadius: root.width / 2
    }
}
