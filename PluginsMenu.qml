import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Plugins: busca e a lista do shell. O clique liga ou desliga.
// Uma barra pede um segundo toque, porque ela substitui a Ilha.
// O id só segue se for um identificador simples, e vai como argumento,
// nunca interpolado num comando.
//
// Contrato de estado: active, fg/bg/accent/danger, metrics, keyboardMode,
// footerStatus, footerHints, footerAlert, handleKey, handleEscape,
// focusFirst, closeRequested, navigate.
Item {
    id: root

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted

    property bool active: false
    property var shell: null
    property Metrics metrics: Metrics {}
    property bool keyboardMode: false

    signal closeRequested()
    signal navigate(string target)

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    readonly property int visibleRows: 8
    readonly property int rowHeight: 40
    readonly property int searchHeight: 40
    readonly property int listHeight: visibleRows * rowHeight

    implicitWidth: metrics.content
    implicitHeight: searchHeight + metrics.gap + listHeight

    property string query: ""
    property int selectedIndex: 0
    property var plugins: []
    property var pending: ({})
    property bool loaded: false
    property bool refreshQueued: false
    property string busyId: ""
    property string armedId: ""

    readonly property var filtered: {
        const q = root.query.trim().toLowerCase();
        if (q.length === 0) return root.plugins;
        return root.plugins.filter(p => p.name.toLowerCase().indexOf(q) >= 0 || p.id.toLowerCase().indexOf(q) >= 0);
    }

    readonly property string footerStatus: root.armedId !== "" ? strings.t("plugins.confirmBar")
                                         : !root.loaded ? strings.t("plugins.loading")
                                         : root.filtered.length === 0 ? strings.t("plugins.countNone")
                                         : strings.tn("plugins.count", root.filtered.length).arg(Commons.I18n.formatNumber(root.filtered.length))
    readonly property bool footerAlert: root.armedId !== ""
    readonly property string footerHints: strings.t("hint.plugins")

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods) return false;
        if (event.key === Qt.Key_Up) { root.select(-1); return true; }
        if (event.key === Qt.Key_Down) { root.select(1); return true; }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.selectedIndex);
            return true;
        }
        return false;
    }
    function handleEscape() {
        if (root.armedId !== "") {
            root.armedId = "";
            armTimer.stop();
            return true;
        }
        if (input.text.length === 0 && root.query.length === 0) return false;
        input.text = "";
        root.query = "";
        return true;
    }
    function focusFirst() { input.forceActiveFocus(); return true; }

    function safeId(id) {
        const s = String(id || "");
        return /^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$/.test(s) ? s : "";
    }
    function isBar(plugin) {
        return plugin && plugin.kinds.indexOf("bar") >= 0;
    }
    function shownEnabled(plugin) {
        if (plugin && Object.prototype.hasOwnProperty.call(root.pending, plugin.id))
            return root.pending[plugin.id] === true;
        return !!(plugin && plugin.enabled);
    }
    function kindText(kinds) {
        const mapped = {
            "bar": "plugins.kind.bar",
            "bar-widget": "plugins.kind.barWidget",
            "service": "plugins.kind.service",
            "overlay": "plugins.kind.overlay",
            "panel": "plugins.kind.panel",
            "menu": "plugins.kind.menu"
        };
        const names = [];
        for (let i = 0; i < kinds.length; i++) {
            const key = mapped[kinds[i]];
            names.push(key ? strings.t(key) : kinds[i]);
        }
        return names.join(" · ");
    }
    function kindIcon(kinds) {
        const first = kinds.length > 0 ? kinds[0] : "";
        if (first === "bar") return "dock_to_bottom";
        if (first === "bar-widget") return "widgets";
        if (first === "service") return "settings";
        if (first === "overlay") return "layers";
        if (first === "panel") return "dashboard";
        if (first === "menu") return "menu";
        return "extension";
    }

    function takePlugins(raw) {
        let parsed = [];
        try {
            const value = JSON.parse(String(raw || "[]"));
            if (Array.isArray(value)) parsed = value;
        } catch (e) {
            parsed = [];
        }
        const out = [];
        for (let i = 0; i < parsed.length && out.length < 200; i++) {
            const row = parsed[i];
            if (!row || typeof row !== "object") continue;
            const id = root.safeId(row.id);
            const name = String(row.name || id).replace(/[\u0000-\u001f<>]/g, "").slice(0, 80);
            if (id === "" || name === "") continue;
            const kinds = [];
            const source = Array.isArray(row.kinds) ? row.kinds : [];
            for (let k = 0; k < source.length && kinds.length < 4; k++) {
                const kind = String(source[k] || "");
                if (/^[a-z0-9-]{1,24}$/.test(kind)) kinds.push(kind);
            }
            out.push({
                id: id,
                name: name,
                enabled: row.enabled === true,
                canDisable: row.canDisable === true,
                active: row.active === true,
                kinds: kinds
            });
        }
        out.sort((a, b) => a.name.localeCompare(b.name));
        return out;
    }

    function ingest(raw) {
        const list = root.takePlugins(raw);
        const next = {};
        for (const id in root.pending) {
            const row = list.find(p => p.id === id);
            if (row && row.enabled !== (root.pending[id] === true))
                next[id] = root.pending[id] === true;
        }
        root.pending = next;
        root.plugins = list;
        root.loaded = true;
        if (root.busyId !== "" && !Object.prototype.hasOwnProperty.call(next, root.busyId))
            root.busyId = "";
        if (root.selectedIndex >= root.filtered.length)
            root.selectedIndex = Math.max(0, root.filtered.length - 1);
    }

    function refresh() {
        if (listProc.running) {
            root.refreshQueued = true;
            return;
        }
        listProc.running = true;
    }

    function select(delta) {
        const n = root.filtered.length;
        if (n === 0) return;
        const next = root.selectedIndex + delta;
        if (next < 0 || next >= n) return;
        root.selectedIndex = next;
    }

    function activate(index) {
        const plugin = root.filtered[index];
        if (!plugin || root.busyId === plugin.id) return;
        const on = root.shownEnabled(plugin);
        if (root.isBar(plugin)) {
            if (on) return;
            if (root.armedId !== plugin.id) {
                root.armedId = plugin.id;
                armTimer.restart();
                return;
            }
            root.armedId = "";
            armTimer.stop();
        } else if (on && !plugin.canDisable) {
            return;
        } else {
            root.armedId = "";
            armTimer.stop();
        }
        const want = !on;
        const copy = Object.assign({}, root.pending);
        copy[plugin.id] = want;
        root.pending = copy;
        root.busyId = plugin.id;
        Quickshell.execDetached(["omarchy", "plugin", want ? "enable" : "disable", plugin.id]);
        refreshTimer.restart();
    }

    onQueryChanged: root.selectedIndex = 0
    onSelectedIndexChanged: {
        if (list.count === 0) return;
        list.currentIndex = root.selectedIndex;
        list.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }
    onActiveChanged: if (active) root.refresh()
    Component.onCompleted: if (active) root.refresh()

    Timer {
        id: armTimer
        interval: 4000
        onTriggered: root.armedId = ""
    }
    Timer {
        id: refreshTimer
        interval: 450
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: ["omarchy", "plugin", "list", "--json"]
        stdout: StdioCollector {
            id: listOut
            waitForEnd: true
            onStreamFinished: root.ingest(text)
        }
        onExited: (exitCode, exitStatus) => {
            if (!root.refreshQueued) return;
            root.refreshQueued = false;
            root.refresh();
        }
    }

    ContinuousRect {
        id: searchBox
        width: root.implicitWidth
        height: root.searchHeight
        radius: root.metrics.fit(height / 2)
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
        borderWidth: input.activeFocus ? root.metrics.ring - 1 : 0
        borderColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)

        Icon {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: 20
            filled: input.text.length > 0
            color: root.accent
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
            font.pixelSize: 14
            clip: true
            onTextChanged: root.query = text
            Accessible.role: Accessible.EditableText
            Accessible.name: strings.t("plugins.search")

            Keys.onPressed: event => {
                if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                    input.readOnly = true;
                    Qt.callLater(() => input.readOnly = false);
                    event.accepted = false;
                }
            }
            Keys.onUpPressed: event => { root.select(-1); event.accepted = true; }
            Keys.onDownPressed: event => { root.select(1); event.accepted = true; }
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
            Keys.onReturnPressed: event => { root.activate(root.selectedIndex); event.accepted = true; }
            Keys.onEnterPressed: event => { root.activate(root.selectedIndex); event.accepted = true; }
            Keys.onEscapePressed: event => { event.accepted = root.handleEscape(); }
        }

        Text {
            anchors.left: input.left
            anchors.right: input.right
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("plugins.search")
            textFormat: Text.PlainText
            color: root.muted
            font.pixelSize: 14
            elide: Text.ElideRight
            visible: input.text.length === 0
        }
    }

    ListView {
        id: list
        y: root.searchHeight + root.metrics.gap
        width: root.implicitWidth
        height: root.listHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.filtered
        currentIndex: 0
        keyNavigationEnabled: false
        highlightFollowsCurrentItem: true
        highlightMoveDuration: Commons.Style.duration(root.metrics.msState)
        highlightMoveVelocity: -1
        highlightResizeDuration: 0
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: height

        highlight: Item {
            width: list.width
            height: root.rowHeight
            ContinuousRect {
                anchors.fill: parent
                radius: root.metrics.rowRadius
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.metrics.alphaPill)
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
            readonly property bool on: root.shownEnabled(modelData)
            readonly property bool inUse: root.isBar(modelData) && on
            readonly property bool busy: root.busyId === modelData.id

            width: list.width
            height: root.rowHeight
            opacity: busy ? root.metrics.opacityBusy : 1

            ContinuousRect {
                anchors.fill: parent
                radius: root.metrics.rowRadius
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
                opacity: hover.hovered && !row.selected ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
            }

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.activate(row.index) }

            Icon {
                id: mark
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                name: row.busy ? "sync" : root.kindIcon(modelData.kinds)
                size: 20
                filled: row.selected || row.on
                color: row.selected ? root.accent : root.fg
            }

            Text {
                id: nameText
                anchors.left: mark.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, row.width - 210)
                text: modelData.name
                textFormat: Text.PlainText
                color: row.selected ? root.accent : root.fg
                font.pixelSize: 13
                font.weight: row.selected || row.on ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.left: nameText.right
                anchors.leftMargin: 10
                anchors.right: status.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.kindText(modelData.kinds)
                textFormat: Text.PlainText
                color: root.muted
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Item {
                id: status
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: row.inUse ? inUseText.implicitWidth : 18
                height: 18

                Text {
                    id: inUseText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.inUse
                    text: strings.t("plugins.inUse")
                    textFormat: Text.PlainText
                    color: root.accent
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Icon {
                    anchors.centerIn: parent
                    visible: !row.inUse
                    name: row.on ? "check" : "radio_button_unchecked"
                    size: 16
                    color: row.on ? root.accent : root.muted
                }
            }
        }
    }

    Text {
        anchors.centerIn: list
        visible: root.loaded && root.filtered.length === 0
        text: strings.t("plugins.countNone")
        textFormat: Text.PlainText
        color: root.muted
        font.pixelSize: 13
    }
}
