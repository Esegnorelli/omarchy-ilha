import QtQuick
import "Motion.js" as Motion

// Interruptor 43 x 24 (Wi-Fi, Bluetooth, Luz noturna, Ilha). FINAL do Phase 0
// (dono: lead).
//
//   IlhaSwitch { theme: …; checked: net.wifiEnabled; onToggled: net.setWifiEnabled(!net.wifiEnabled) }
//
// - Não guarda estado: toggled() pede a troca e quem chama muda `checked`.
// - Ligado: trilho accent, bolinha onAccent. Desligado: chipFill, bolinha surface.
// - Bolinha 16 a 4 px da borda; anda em 140 ms OutCubic.
// - mirrored (RTL): ligado fica à esquerda.
Item {
    id: root

    property Theme theme: null
    property bool checked: false
    property bool focused: false
    property bool mirrored: root.theme ? root.theme.rtl : false
    property string accessibleName: ""

    signal toggled()

    implicitWidth: 43
    implicitHeight: 24
    opacity: root.enabled ? 1 : 0.4

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.checkable: true
    Accessible.checked: root.checked

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.theme ? (root.checked ? root.theme.accent : root.theme.chipFill) : "gray"
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.SWITCH) : 0 }
        }
    }

    Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        readonly property real onX: root.width - 4 - width
        readonly property real offX: 4
        x: (root.checked !== root.mirrored) ? onX : offX
        color: root.theme ? (root.checked ? root.theme.onAccent : root.theme.surface) : "white"
        Behavior on x {
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.SWITCH) : 0; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.SWITCH) : 0 }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    FocusRing {
        theme: root.theme
        shown: root.focused
        itemRadius: root.height / 2
    }
}
