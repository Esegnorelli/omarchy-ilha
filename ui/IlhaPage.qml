pragma ComponentBehavior: Bound
import QtQuick
import "Motion.js" as Motion

// Subpágina "Ilha" da Central (amendments §12.1): as duas chaves da Ilha
// (focusedOnly, livePeek), gravadas no shell.json do Omarchy pelo PrefsSvc
// (shell.mutateShellConfig -> bar.ilha.*), a versão e, sem host, o aviso de
// que a escolha vale até o shell reiniciar. Abre pelo botão Ajustes da Ilha
// da faixa do cartão de notificações (transformação J a partir do botão de
// 26), por `ilha open settings` ou pelo payload { sub: "ilha" }.
//
// Coordenadas do cartão (a Central põe em x 22, y 21, w 470, raio 21, card):
// - Voltar (CircleButton 24, chevron_left espelhado em RTL) centrado em (26, 34).
// - Título "Ilha" em x 52, topo das maiúsculas 26, 18,5 / 600.
// - Versão (12 inkFaint) à direita, margem 16, centrada em y 34.
// - Linhas 442 x 60 em x 14, y 68 (focusedOnly) e y 136 (livePeek); raio
//   12,5, fill raised, hover rowHover em 110 ms. Título 14,5 / 600 em x 16,
//   topo das maiúsculas 13; dica 12 / 400 inkMuted, topo 33; ambos cortam em
//   357. IlhaSwitch 43 x 24 à direita (14), centrado. Clicar na linha ou no
//   interruptor chama prefs.toggle(chave). O chevron e a versão são secundários (hover do cabeçalho). A dica de cada linha é secundária (hover da linha ou foco nela).
// - Só sem host (!prefs.canPersist): a nota ilha.localOnly, 12 inkFaint,
//   x 16, topo das maiúsculas 210. cardH = 212, ou 234 com a nota.
// - RTL: tudo por âncoras (espelham com o LayoutMirroring herdado).
//
// Teclado: Cima/Baixo (e Tab) entre as linhas; Enter ou Espaço alternam;
// Esc volta. Anéis só no modo teclado.
Item {
    id: root

    property var island: null
    property Theme theme: null
    property var strings: null
    property bool keyboardMode: false
    property real maxHeight: 900
    property var prefs: null

    signal back()

    function opened() {
        priv.focus = root.keyboardMode ? 0 : -1;
    }

    function closed() {
        priv.focus = -1;
    }

    function handleKey(event) {
        const k = event.key;
        const mods = event.modifiers || 0;
        if (mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        const n = priv.keys.length;
        switch (k) {
        case Qt.Key_Up:
        case Qt.Key_Down:
        case Qt.Key_Tab:
        case Qt.Key_Backtab: {
            const back = k === Qt.Key_Up || k === Qt.Key_Backtab || (k === Qt.Key_Tab && (mods & Qt.ShiftModifier));
            if (priv.focus < 0)
                priv.focus = 0;
            else
                priv.focus = Math.max(0, Math.min(n - 1, priv.focus + (back ? -1 : 1)));
            return true;
        }
        case Qt.Key_Home:
            priv.focus = 0;
            return true;
        case Qt.Key_End:
            priv.focus = n - 1;
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (priv.focus < 0) {
                priv.focus = 0;
                return true;
            }
            root.toggle(priv.keys[priv.focus]);
            return true;
        default:
            return false;
        }
    }

    function handleEscape() {
        root.back();
        return true;
    }

    function toggle(key) {
        if (root.prefs)
            root.prefs.toggle(key);
    }

    function t(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    width: 470
    implicitWidth: 470
    implicitHeight: root.prefs && !root.prefs.canPersist ? 234 : 212

    QtObject {
        id: priv
        // Linha focada pelo teclado (-1 = nenhuma).
        property int focus: -1
        readonly property var keys: ["focusedOnly", "livePeek"]
    }

    // Cabeçalho: o hover dele mostra o chevron de voltar (secundário; Esc, Alt+←, a navegação e o toque fora também voltam).
    Item {
        id: headerBand
        anchors.left: parent.left
        anchors.right: parent.right
        y: 0
        height: 60
        HoverHandler { id: headerHover }
    }
    CircleButton {
        id: backBtn
        anchors.left: parent.left
        anchors.leftMargin: 26 - 12
        y: 34 - 12
        theme: root.theme
        icon: "chevron_left"
        flip: !!root.theme && root.theme.rtl
        size: 24
        glyphSize: 14
        accessibleName: root.t("common.back")
        veil: (headerHover.hovered || backBtn.hovered) ? 1 : 0
        onClicked: root.back()
    }

    IlhaText {
        id: title
        anchors.left: parent.left
        anchors.leftMargin: 52
        y: 26 - (title.baselineOffset - 0.7275 * title.font.pixelSize)
        theme: root.theme
        size: 18.5
        weight: 600
        text: root.t("ilha.title")
    }

    IlhaText {
        id: version
        anchors.right: parent.right
        anchors.rightMargin: 16
        // Centro das maiúsculas em y 34.
        y: 34 - version.baselineOffset + 0.3638 * version.font.pixelSize
        theme: root.theme
        size: 12
        weight: 400
        color: root.theme ? root.theme.inkFaint : "gray"
        text: root.t("ilha.version").arg(root.island ? (root.island.manifestVersion || root.island.codeVersion) : "")
        readonly property bool reveal: headerHover.hovered
        opacity: reveal ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: root.theme ? root.theme.dur(reveal ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                easing.type: Easing.OutCubic
            }
        }
    }

    Repeater {
        model: [
            { key: "focusedOnly", y: 68, title: "ilha.focusedOnly", hint: "ilha.focusedOnlyHint" },
            { key: "livePeek", y: 136, title: "ilha.livePeek", hint: "ilha.livePeekHint" }
        ]

        Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool on: root.prefs ? !!root.prefs[row.modelData.key] : false

            anchors.left: parent.left
            anchors.leftMargin: 14
            y: row.modelData.y
            width: 442
            height: 60
            radius: 12.5
            color: root.theme ? (area.containsMouse ? root.theme.rowHover : root.theme.raised) : "transparent"
            Behavior on color {
                ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
            }

            Accessible.role: Accessible.CheckBox
            Accessible.name: rowTitle.text
            Accessible.description: rowHint.text
            Accessible.checkable: true
            Accessible.checked: row.on

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggle(row.modelData.key)
            }

            IlhaText {
                id: rowTitle
                anchors.left: parent.left
                anchors.leftMargin: 16
                y: 13 - (rowTitle.baselineOffset - 0.7275 * rowTitle.font.pixelSize)
                width: 357
                theme: root.theme
                size: 14.5
                weight: 600
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                text: root.t(row.modelData.title)
            }
            IlhaText {
                id: rowHint
                anchors.left: parent.left
                anchors.leftMargin: 16
                y: 33 - (rowHint.baselineOffset - 0.7275 * rowHint.font.pixelSize)
                width: 357
                theme: root.theme
                size: 12
                weight: 400
                color: root.theme ? root.theme.inkMuted : "gray"
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                text: root.t(row.modelData.hint)
                readonly property bool reveal: area.containsMouse || (root.keyboardMode && priv.focus === row.index)
                opacity: reveal ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.theme ? root.theme.dur(reveal ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                        easing.type: Easing.OutCubic
                    }
                }
            }

            IlhaSwitch {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                checked: row.on
                accessibleName: rowTitle.text
                onToggled: root.toggle(row.modelData.key)
            }

            FocusRing {
                theme: root.theme
                shown: root.keyboardMode && priv.focus === row.index
                itemRadius: 12.5
            }
        }
    }

    IlhaText {
        id: note
        anchors.left: parent.left
        anchors.leftMargin: 16
        y: 210 - (note.baselineOffset - 0.7275 * note.font.pixelSize)
        visible: !!root.prefs && !root.prefs.canPersist
        width: 470 - 32
        theme: root.theme
        size: 12
        weight: 400
        color: root.theme ? root.theme.inkFaint : "gray"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("ilha.localOnly")
    }
}
