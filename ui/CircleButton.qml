import QtQuick
import "Motion.js" as Motion

// Botão circular pequeno (seta da Central, voltar das subpáginas, ajustes do
// cartão de notificações, fechar linha). FINAL do Phase 0 (dono: lead).
//
//   CircleButton { theme: …; icon: "chevron_right"; size: 24; glyphSize: 14
//                  fill: theme.raised; hoverFill: theme.mix(theme.surface, theme.ink, 0.17)
//                  glyphColor: theme.inkMuted; onClicked: … }
//
// - accent: true pinta accent / onAccent (ignora fill e glyphColor).
// - hoverFill / hoverGlyphColor: vazios ("transparent" / glyphColor) mantêm
//   o fill com a sobreposição de 10% de tinta.
// - flip: espelha o glifo na horizontal (setas em RTL: flip: theme.rtl).
Item {
    id: root

    property Theme theme: null
    property string icon: ""
    // Glifo do Omarchy. Vazio: ligadura Material em icon.
    property string glyph: ""
    property real size: 24
    property real glyphSize: 14
    property bool filled: false
    property bool accent: false
    property color fill: root.theme ? root.theme.raised : "transparent"
    property color hoverFill: "transparent"
    property color glyphColor: root.theme ? root.theme.inkMuted : "white"
    property color hoverGlyphColor: "transparent"
    property bool flip: false
    property bool focused: false
    property string accessibleName: ""
    // Secundário: opacidade da face (fundo, glifo, anel), nunca do botão. A
    // opacity do botão é das origens da Central (chevronOpacity, settingsOpacity).
    // O clique vale mesmo com veil 0.
    property real veil: 1

    readonly property bool hovered: area.containsMouse
    readonly property bool pressed: area.pressed

    signal clicked()

    implicitWidth: root.size
    implicitHeight: root.size

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName

    Item {
        id: face
        anchors.fill: parent
        opacity: root.veil
        Behavior on opacity {
            NumberAnimation {
                duration: root.theme ? root.theme.dur(root.veil > 0 ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: !root.theme ? "transparent"
                : root.accent ? (root.hovered ? root.theme.mix(root.theme.accent, root.theme.ink, 0.06) : root.theme.accent)
                : root.hovered ? (root.hoverFill.a > 0 ? root.hoverFill : root.theme.mix(root.fill.a > 0 ? root.fill : root.theme.surface, root.theme.ink, 0.10))
                : root.fill
            Behavior on color {
                ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
            }
        }

        Icon {
            anchors.centerIn: parent
            name: root.glyph !== "" ? "" : root.icon
            glyph: root.glyph
            size: root.glyphSize
            filled: root.filled
            color: !root.theme ? "white"
                : root.accent ? root.theme.onAccent
                : (root.hovered && root.hoverGlyphColor.a > 0) ? root.hoverGlyphColor
                : root.glyphColor
            transform: Scale {
                origin.x: root.glyphSize / 2
                xScale: root.flip ? -1 : 1
            }
            Behavior on color {
                ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
            }
        }

        FocusRing {
            theme: root.theme
            shown: root.focused
            itemRadius: root.width / 2
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
