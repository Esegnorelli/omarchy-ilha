import QtQuick
import Quickshell
import qs.Commons as Commons

// Apps (spec §3.4): linha de busca de 40 px + 8 + lista de altura fixa
// (6 linhas de 52 = 312; rola quando há mais). Sem resultado, o aviso fica
// centrado no bloco. A altura nunca muda: 360.
//
// Teclas no campo: ↑↓ e Tab/⇧Tab escolhem, ↵ abre, Esc limpa a busca
// (o 2º Esc sobe para o host e fecha). Alt+dígito e Ctrl+Tab sobem para o
// host (troca de categoria); letras e dígitos simples digitam.
//
// Contrato de estado: active (ou open, semântica antiga), fg/bg/accent/danger,
// metrics, keyboardMode, footerStatus, footerHints, handleKey(event) → bool,
// handleEscape() → bool, focusFirst(), closeRequested(), navigate(target).
Item {
    id: root

    // Cores do tema (o host passa as mesmas).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    // Fonte do Estilo (o host liga quando a propriedade existe).
    property string fontFamily: Commons.Style.fontFamily

    // `open` (semântica antiga) e `active` (contrato de estado) fazem o mesmo.
    property bool open: false
    property bool active: false
    readonly property bool shown: open || active

    property var shell: null
    property Metrics metrics: Metrics {}
    property bool keyboardMode: false

    signal closeRequested()
    signal navigate(string target)

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    readonly property int visibleRows: 6
    readonly property int rowHeight: metrics.listRow
    readonly property int searchHeight: 40
    readonly property int listHeight: visibleRows * rowHeight

    implicitWidth: metrics.content
    implicitHeight: searchHeight + metrics.gap + listHeight

    property string query: ""
    property int selectedIndex: 0

    // ---------- Contrato ----------
    readonly property string footerStatus: results.length === 0 ? strings.t("launcher.countNone")
                                         : strings.tn("launcher.count", results.length).arg(Commons.I18n.formatNumber(results.length))
    readonly property string footerHints: strings.t("hint.apps")

    // Letras digitam no campo: nada é atalho aqui.
    function handleKey(event) { return false; }
    // Esc limpa a busca primeiro; com o campo vazio, o host fecha.
    function handleEscape() {
        if (input.text.length === 0 && root.query.length === 0) return false;
        input.text = "";
        root.query = "";
        return true;
    }
    function focusFirst() { input.forceActiveFocus(); return true; }

    // ---------- Apps ----------
    readonly property int appCount: allApps.length

    readonly property var allApps: {
        const values = DesktopEntries.applications.values || [];
        const out = [];
        for (let i = 0; i < values.length; i++) {
            const e = values[i];
            if (e && !e.noDisplay && e.name) out.push(e);
        }
        return out;
    }

    // Todos os que casam, do melhor para o pior (a lista rola).
    readonly property var results: {
        const q = root.query.trim().toLowerCase();
        const scored = [];
        for (const e of root.allApps) {
            const name = String(e.name || "").toLowerCase();
            let score = -1;
            if (q.length === 0) score = 0;
            else if (name.indexOf(q) === 0) score = 3;
            else if (name.indexOf(q) >= 0) score = 2;
            else if (String(e.genericName || "").toLowerCase().indexOf(q) >= 0) score = 1;
            else {
                const kws = e.keywords || [];
                for (let k = 0; k < kws.length; k++)
                    if (String(kws[k]).toLowerCase().indexOf(q) >= 0) { score = 1; break; }
            }
            if (score >= 0) scored.push({ entry: e, score: score, name: name });
        }
        scored.sort((a, b) => a.score !== b.score ? b.score - a.score : a.name.localeCompare(b.name));
        return scored.map(s => s.entry);
    }

    onResultsChanged: {
        root.selectedIndex = 0;
        list.currentIndex = 0;
        list.positionViewAtBeginning();
    }
    onSelectedIndexChanged: list.currentIndex = root.selectedIndex

    function select(delta) {
        const n = root.results.length;
        if (n === 0) return;
        root.selectedIndex = (root.selectedIndex + delta + n) % n;
    }

    function reset() {
        input.text = "";
        root.query = "";
        root.selectedIndex = 0;
        list.currentIndex = 0;
        list.positionViewAtBeginning();
        input.forceActiveFocus();
    }

    onShownChanged: if (shown) reset()
    Component.onCompleted: if (shown) input.forceActiveFocus()

    function launch(index) {
        const e = results[index];
        if (!e) return;
        root.closeRequested();
        e.execute();
    }

    // ---------- Linha de busca (40) ----------
    // Sem placa nem borda: só a lupa, o texto e um fio de 1 px embaixo.
    ContinuousRect {
        id: searchBox
        width: root.implicitWidth
        height: root.searchHeight
        radius: root.metrics.fit(height / 2)
        color: "transparent"
        borderWidth: 0

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
        }

        Icon {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: 18
            filled: input.text.length > 0
            color: input.text.length > 0 ? root.fg : root.muted
        }

        TextInput {
            id: input
            anchors.left: searchIcon.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            color: root.fg
            selectionColor: root.accent
            selectedTextColor: root.bg
            font.family: root.fontFamily
            font.pixelSize: 15
            clip: true
            onTextChanged: root.query = text
            Accessible.role: Accessible.EditableText
            Accessible.name: strings.t("launcher.placeholder")

            // Alt+dígito é do host (troca de categoria). Somente leitura por
            // um instante, o campo ignora a tecla e ela sobe sem virar texto.
            Keys.onPressed: event => {
                if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                    input.readOnly = true;
                    Qt.callLater(() => input.readOnly = false);
                    event.accepted = false;
                }
            }
            Keys.onUpPressed: event => { root.select(-1); event.accepted = true; }
            Keys.onDownPressed: event => { root.select(1); event.accepted = true; }
            // Ctrl+Tab / Ctrl+⇧Tab sobem para o host; Tab simples escolhe.
            Keys.onTabPressed: event => {
                if (event.modifiers & Qt.ControlModifier) { event.accepted = false; return; }
                root.select(1);
                event.accepted = true;
            }
            Keys.onBacktabPressed: event => {
                if (event.modifiers & Qt.ControlModifier) { event.accepted = false; return; }
                root.select(-1);
                event.accepted = true;
            }
            Keys.onReturnPressed: event => { root.launch(root.selectedIndex); event.accepted = true; }
            Keys.onEnterPressed: event => { root.launch(root.selectedIndex); event.accepted = true; }
            // 1º Esc limpa; com o campo vazio sobe para o host fechar.
            Keys.onEscapePressed: event => { event.accepted = root.handleEscape(); }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: strings.t("launcher.placeholder")
                textFormat: Text.PlainText
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 15
                elide: Text.ElideRight
                visible: input.text.length === 0
            }
        }
    }

    // ---------- Lista (6 × 52, fixa) ----------
    ListView {
        id: list
        y: root.searchHeight + root.metrics.gap
        width: root.implicitWidth
        height: root.listHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.results
        currentIndex: 0
        keyNavigationEnabled: false
        highlightFollowsCurrentItem: true
        highlightMoveDuration: Commons.Style.duration(root.metrics.msState)
        highlightMoveVelocity: -1
        highlightResizeDuration: 0
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: height

        // A roda rolou a seleção para fora: escolhe a primeira linha à vista,
        // para o Enter nunca abrir um app escondido.
        onMovementEnded: {
            if (count === 0) return;
            const top = root.selectedIndex * root.rowHeight;
            if (top >= contentY - 1 && top + root.rowHeight <= contentY + height + 1) return;
            const i = indexAt(10, contentY + root.rowHeight / 2);
            if (i >= 0) root.selectedIndex = i;
        }

        // Seleção: placa neutra um pouco mais clara, com a barrinha de accent
        // que desliza junto.
        highlight: Item {
            width: list.width
            height: root.rowHeight
            ContinuousRect {
                anchors.fill: parent
                radius: root.metrics.rowRadius
                color: root.metrics.plate(root.fg, root.metrics.alphaHover)
            }
            ContinuousRect {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 16
                radius: root.metrics.fit(1.5)
                color: root.accent
            }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool selected: index === root.selectedIndex

            width: list.width
            height: root.rowHeight

            ContinuousRect {
                anchors.fill: parent
                radius: root.metrics.rowRadius
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
                opacity: hover.hovered && !row.selected ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
            }

            // O hover só destaca; não move a seleção. As linhas são recriadas a
            // cada tecla, e um cursor parado roubaria a seleção (Enter abriria o
            // app errado).
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.launch(row.index) }

            // Ícone do app numa placa de 36, como no desenho da lista.
            ContinuousRect {
                id: iconBox
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 36
                height: 36
                radius: root.metrics.fit(10)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)

                readonly property string src: {
                    const v = String(row.modelData.icon || "");
                    if (v.length === 0) return "";
                    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v;
                    if (v.charAt(0) === "/") return "file://" + v;
                    return Quickshell.iconPath(v, true);
                }

                Image {
                    id: img
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    source: iconBox.src
                    sourceSize.width: 44
                    sourceSize.height: 44
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: status === Image.Ready
                }
                // Reserva quando o app não tem ícone.
                Icon {
                    anchors.centerIn: parent
                    visible: img.status !== Image.Ready
                    name: "apps"
                    size: 20
                    filled: row.selected
                    color: root.fg
                }
            }

            // Nome em cima, descrição apagada embaixo.
            Column {
                anchors.left: iconBox.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(row.modelData.name || "")
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    id: descText
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(row.modelData.genericName || row.modelData.comment || "")
                    visible: text.length > 0
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        // Indicador de rolagem, no pad à direita.
        ContinuousRect {
            parent: root
            visible: list.contentHeight > list.height + 1
            x: list.width + 6
            y: list.y + list.visibleArea.yPosition * list.height
            width: 3
            height: Math.max(20, list.visibleArea.heightRatio * list.height)
            radius: root.metrics.fit(width / 2)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaPill)
        }
    }

    // Sem resultado: aviso centrado no bloco da lista.
    Column {
        visible: root.results.length === 0
        anchors.horizontalCenter: list.horizontalCenter
        y: list.y + (list.height - height) / 2
        spacing: 8
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "search_off"
            size: 28
            color: root.muted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: strings.t("launcher.empty")
            textFormat: Text.PlainText
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 13
        }
    }
}
