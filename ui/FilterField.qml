import QtQuick
import QtQuick.Controls as QQC
import "Motion.js" as Motion

// Campo de busca das telas (Apps, Temas): QQC.TextField sem fundo, com o
// cursor accent da Ilha. FINAL do Phase 0 (dono: lead).
//
//   FilterField { id: field; theme: …; placeholder: strings.t("launcher.search")
//                 fontSize: 15; onNavKey: e => screen.handleNav(e); onTextEdited: … }
//   field.text / field.clear() / field.focusField()
//
// - Teclas de navegação são tiradas do TextInput no Keys.onPressed (aceitas)
//   e vão para navKey(event): Left, Right, Up, Down, Home, End, PgUp, PgDn,
//   Return/Enter, Tab/Backtab e Escape. Assim Left/Right sempre andam a faixa.
//   `forwarded` troca a lista, se uma tela precisar.
// - Cursor 2 x 13 accentInk: fixo por 600 ms depois de abrir ou de uma
//   tecla, depois pulsa em 750 ms (aceso 250, some 180, 25% por 150, volta 180).
// - Placeholder inkFaint; texto ink 15/400.
FocusScope {
    id: root

    property Theme theme: null
    property string placeholder: ""
    property real fontSize: 15
    property var forwarded: [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End,
        Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Escape]

    readonly property string text: field.text

    signal navKey(var event)
    signal textEdited()

    function clear() {
        field.clear();
        root.textEdited();
    }

    function focusField() {
        field.forceActiveFocus();
        caret.restartSolid();
    }

    implicitWidth: 300
    implicitHeight: Math.ceil(root.fontSize * 1.6)

    Accessible.role: Accessible.EditableText
    Accessible.name: root.placeholder

    QQC.TextField {
        id: field
        anchors.fill: parent
        focus: true
        padding: 0
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        background: Item {}
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignLeft
        color: root.theme ? root.theme.ink : "white"
        placeholderText: root.placeholder
        placeholderTextColor: root.theme ? root.theme.inkFaint : "gray"
        selectionColor: root.theme ? root.theme.alpha(root.theme.accent, 0.35) : "gray"
        selectedTextColor: root.theme ? root.theme.ink : "white"
        selectByMouse: true
        renderType: Text.QtRendering
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: Math.max(1, Math.round(root.fontSize))
        font.variableAxes: ({ "wght": 400 })

        onTextEdited: {
            caret.restartSolid();
            root.textEdited();
        }

        Keys.onPressed: event => {
            if (root.forwarded.indexOf(event.key) !== -1) {
                event.accepted = true;
                caret.restartSolid();
                root.navKey(event);
            }
        }

        cursorDelegate: Rectangle {
            id: caretRect
            width: 2
            height: 13
            radius: 1
            color: root.theme ? root.theme.accentInk : "white"
            visible: field.activeFocus
            opacity: caret.level
        }
    }

    // Pulso do cursor (um objeto só, lido pelo delegado).
    QtObject {
        id: caret
        property real level: 1

        function restartSolid() {
            pulse.stop();
            caret.level = 1;
            solid.restart();
        }
    }

    Timer {
        id: solid
        interval: Motion.FADE.CARET.solid
        running: field.activeFocus
        onTriggered: if (!(root.theme && root.theme.reduceMotion)) pulse.start()
    }

    SequentialAnimation {
        id: pulse
        loops: Animation.Infinite
        PauseAnimation { duration: Motion.FADE.CARET.on }
        NumberAnimation { target: caret; property: "level"; to: Motion.FADE.CARET.lowOpacity; duration: Motion.FADE.CARET.fade; easing.type: Easing.InOutSine }
        PauseAnimation { duration: Motion.FADE.CARET.low }
        NumberAnimation { target: caret; property: "level"; to: 1; duration: Motion.FADE.CARET.fade; easing.type: Easing.InOutSine }
    }

    Connections {
        target: field
        function onActiveFocusChanged() {
            if (field.activeFocus)
                caret.restartSolid();
            else
                pulse.stop();
        }
    }
}
