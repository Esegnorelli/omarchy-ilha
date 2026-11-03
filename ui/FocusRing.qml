import QtQuick

// Anel de foco do modo teclado: 2 px de accent a 2 px de folga, em volta do
// pai (anchors.fill do pai, com margem negativa). FINAL do Phase 0 (dono: lead).
//
//   FocusRing { theme: root.theme; shown: root.focused; radius: root.radius }
//
// Só aparece no modo teclado: quem chama passa `focused` já combinado com
// keyboardMode. Nunca muda o tamanho de nada (opacidade).
Rectangle {
    id: root

    property Theme theme: null
    property bool shown: false
    // Raio do item envolvido; o anel soma a folga.
    property real itemRadius: 0

    readonly property real gap: root.theme ? root.theme.focusRingGap : 2

    anchors.fill: parent
    anchors.margins: -(root.gap + border.width)
    radius: root.itemRadius > 0 ? root.itemRadius + root.gap + border.width : 0
    color: "transparent"
    border.width: root.theme ? root.theme.focusRingWidth : 2
    border.color: root.theme ? root.theme.focusRing : "white"
    opacity: root.shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation { duration: root.theme ? root.theme.dur(110) : 0; easing.type: Easing.OutCubic }
    }
}
