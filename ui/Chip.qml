import QtQuick
import "Motion.js" as Motion

// Ficha de escolha (escala da tela "1.0×"): cápsula de 30 de altura,
// 10 px de folga, rótulo 12.5/600. FINAL do Phase 0 (dono: lead).
//
//   Chip { theme: …; text: "1.25×"; selected: …; onClicked: … }
//
// Sem seleção: chipFill / ink. Selecionada: accent / onAccent.
Item {
    id: root

    property Theme theme: null
    property string text: ""
    property bool selected: false
    property bool focused: false

    readonly property bool hovered: area.containsMouse

    signal clicked()

    implicitHeight: 30
    implicitWidth: Math.ceil(metrics.advanceWidth) + 20

    Accessible.role: Accessible.RadioButton
    Accessible.name: root.text
    Accessible.checked: root.selected

    IlhaMetrics {
        id: metrics
        theme: root.theme
        size: 12.5
        weight: 600
        text: root.text
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: !root.theme ? "transparent"
            : root.selected ? root.theme.accent
            : (root.hovered ? root.theme.mix(root.theme.chipFill, root.theme.ink, 0.06) : root.theme.chipFill)
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
    }

    IlhaText {
        anchors.centerIn: parent
        theme: root.theme
        size: 12.5
        weight: 600
        color: root.theme ? (root.selected ? root.theme.onAccent : root.theme.ink) : "white"
        text: root.text
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    FocusRing {
        theme: root.theme
        shown: root.focused
        itemRadius: root.height / 2
    }
}
