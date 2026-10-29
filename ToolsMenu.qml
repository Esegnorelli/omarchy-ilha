import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Commons as Commons

// Central de ferramentas: conexão de internet atual, atalhos para menus e
// utilitários do Omarchy, verificação de atualizações e lembretes rápidos.
Item {
    id: root

    // Cores do tema (o host passa os mesmos tokens).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    // Confirmação de ações destrutivas (limpar lembretes).
    property color danger: Commons.Color.urgent

    // O host liga enquanto este estado está visível.
    property bool active: false

    // Fachada PluginShellApi do host (summon dos painéis do Omarchy). Pode
    // ser null: todo uso é protegido.
    property var shell: null

    // Pede ao host para recolher a ilha.
    signal closeRequested()
    // Pede ao host para trocar de estado ("control", "launcher", ...).
    signal navigate(string target)

    implicitWidth: 400
    implicitHeight: content.implicitHeight

    readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.07)
    readonly property color surfaceHover: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    readonly property color dim: Commons.Color.muted
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // Troca %1, %2... numa passada só, para que um valor que contenha "%2"
    // não seja substituído de novo.
    function fmt(template, args) {
        return String(template).replace(/%(\d+)/g, (m, n) => {
            const i = parseInt(n) - 1;
            return i >= 0 && i < args.length ? String(args[i]) : m;
        });
    }

    // ---------- Execução ----------
    // Fecha a ilha e roda o comando um pouco depois, para que a janela
    // aberta (menu, terminal, seletor) não apareça por baixo da ilha.
    function launch(cmd) {
        root.closeRequested();
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$@\"", "sh"].concat(cmd));
    }

    // Abre um painel do Omarchy pelo host (que escolhe a implementação ativa).
    function summonPanel(id, payload) {
        if (!root.shell || typeof root.shell.summon !== "function") return;
        root.closeRequested();
        root.shell.summon(id, JSON.stringify(payload || {}));
    }

    // ---------- Internet ----------
    readonly property var netDevices: Networking.devices ? Networking.devices.values : []

    // Mesmo critério do painel de rede do Omarchy: prefere o conectado.
    function findDevice(type) {
        const devices = root.netDevices || [];
        let fallback = null;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (!d || d.type !== type) continue;
            if (d.connected) return d;
            if (!fallback) fallback = d;
        }
        return fallback;
    }

    function connectedNetwork(device) {
        if (!device || !device.networks) return null;
        const list = device.networks.values || [];
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].connected) return list[i];
        return null;
    }

    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wifiNetwork: connectedNetwork(wifiDevice)
    readonly property var wiredNetwork: connectedNetwork(wiredDevice)

    // Cabo tem prioridade quando os dois estão ligados (rota padrão).
    readonly property string netKind: {
        if (wiredDevice && wiredDevice.connected) return "ethernet";
        if (wifiNetwork || (wifiDevice && wifiDevice.connected)) return "wifi";
        return "disconnected";
    }
    readonly property var netDevice: netKind === "ethernet" ? wiredDevice : netKind === "wifi" ? wifiDevice : null
    readonly property string netIface: netDevice ? String(netDevice.name || "") : ""
    readonly property string netName: {
        if (netKind === "wifi") return wifiNetwork && wifiNetwork.name ? String(wifiNetwork.name) : "";
        if (netKind === "ethernet") return wiredNetwork && wiredNetwork.name ? String(wiredNetwork.name) : "";
        return "";
    }
    property string netAddress: ""

    // Endereço IPv4 da interface atual, lido só com o estado aberto.
    Process {
        id: ipProc
        property string forIface: ""
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let addr = "";
                try {
                    const data = JSON.parse(text);
                    for (let i = 0; i < data.length && addr === ""; i++) {
                        const infos = data[i].addr_info || [];
                        for (let j = 0; j < infos.length; j++) {
                            if (infos[j].family === "inet" && infos[j].local) {
                                addr = String(infos[j].local);
                                break;
                            }
                        }
                    }
                } catch (e) {
                    addr = "";
                }
                if (ipProc.forIface === root.netIface) root.netAddress = addr;
            }
        }
    }

    function refreshAddress() {
        if (!root.active) return;
        if (root.netIface === "") {
            root.netAddress = "";
            return;
        }
        if (ipProc.running) {
            ipReread.restart();
            return;
        }
        ipProc.forIface = root.netIface;
        ipProc.command = ["ip", "-j", "-4", "addr", "show", "dev", root.netIface];
        ipProc.running = true;
    }

    // Tenta de novo se a troca de interface chegou durante uma leitura.
    Timer {
        id: ipReread
        interval: 400
        onTriggered: root.refreshAddress()
    }

    onNetIfaceChanged: { root.netAddress = ""; refreshAddress(); }
    onNetKindChanged: refreshAddress()

    function openWifiQr() {
        const payload = {};
        if (root.netKind === "wifi" && root.netIface !== "") {
            payload.iface = root.netIface;
            if (root.netName !== "") payload.ssid = root.netName;
        }
        summonPanel("omarchy.wifiqr", payload);
    }

    function openSpeedTest() {
        let connection = "";
        if (root.netKind === "wifi") connection = root.netName || strings.t("tools.net.wifi");
        else if (root.netKind === "ethernet") connection = strings.t("tools.net.ethernet");
        summonPanel("omarchy.speedtest", connection !== "" ? { connection: connection } : {});
    }

    // ---------- Atualizações ----------
    property bool updatesChecking: false
    property int updatesExit: -1
    property string updatesText: ""
    readonly property var updateLines: updatesText.split("\n").map(l => l.trim()).filter(l => l.length > 0)
    readonly property bool hasUpdates: !updatesChecking && updatesExit === 0 && updateLines.length > 0

    // Deixa as linhas da verificação mais legíveis.
    function describeUpdate(line) {
        let m = line.match(/^omarchy-dev-checkout\s+(\d+)\s+new\s+commits?\s+on\s+(\S+)/);
        if (m) {
            const n = parseInt(m[1]);
            const commits = fmt(strings.tn("tools.updates.commits", n), [Commons.I18n.formatNumber(n)]);
            return fmt(strings.t("tools.updates.checkout"), [commits, m[2]]);
        }
        m = line.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
        if (m) return m[1] + "  " + m[2] + " → " + m[3];
        return line;
    }

    Process {
        id: updatesProc
        command: ["omarchy", "update", "available"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.updatesText = text
        }
        onExited: (exitCode, exitStatus) => {
            root.updatesExit = exitCode;
            root.updatesChecking = false;
        }
    }

    function refreshUpdates() {
        if (updatesProc.running) return;
        root.updatesChecking = true;
        updatesProc.running = true;
    }

    // ---------- Lembretes ----------
    property var reminders: []
    readonly property int reminderCount: reminders.length

    Process {
        id: remindersProc
        command: ["omarchy", "reminder", "show", "-j"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.reminders = Array.isArray(data.reminders) ? data.reminders : [];
                } catch (e) {
                    root.reminders = [];
                }
            }
        }
    }

    function refreshReminders() {
        if (!remindersProc.running) remindersProc.running = true;
    }

    // Releitura logo depois de criar ou limpar lembretes.
    Timer {
        id: reminderReread
        interval: 600
        onTriggered: root.refreshReminders()
    }

    // Mantém o tempo restante atualizado enquanto o painel está aberto.
    Timer {
        interval: 30000
        repeat: true
        running: root.active && root.reminderCount > 0
        onTriggered: root.refreshReminders()
    }

    // Ignora toques repetidos enquanto a releitura anterior não terminou,
    // para um toque duplo não criar dois lembretes.
    function addReminder(minutes) {
        if (reminderReread.running) return;
        Quickshell.execDetached(["omarchy", "reminder", String(minutes), strings.t("tools.reminders.defaultMessage")]);
        reminderReread.restart();
    }

    // Limpar pede dois toques: o primeiro arma (cor de perigo) por 3 s.
    property bool clearArmed: false

    Timer {
        id: clearDisarm
        interval: 3000
        onTriggered: root.clearArmed = false
    }

    function clearReminders() {
        if (!root.clearArmed) {
            root.clearArmed = true;
            clearDisarm.restart();
            return;
        }
        root.clearArmed = false;
        clearDisarm.stop();
        if (reminderReread.running) return;
        Quickshell.execDetached(["omarchy", "reminder", "clear"]);
        reminderReread.restart();
    }

    function refreshAll() {
        refreshAddress();
        refreshUpdates();
        refreshReminders();
    }

    onActiveChanged: {
        if (active) {
            refreshAll();
        } else {
            root.clearArmed = false;
            clearDisarm.stop();
        }
    }
    Component.onCompleted: if (active) refreshAll()

    // ---------- Componentes internos ----------
    component ToolButton: Item {
        id: tool
        property string icon: ""
        property string label: ""
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: 72

        ContinuousRect {
            anchors.fill: parent
            radius: 14
            color: root.surface
            scale: toolTap.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: Commons.Style.duration(140); easing.type: Easing.OutCubic } }

            ContinuousRect {
                anchors.fill: parent
                radius: 14
                color: root.surfaceHover
                opacity: toolHover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tool.icon
                    font.family: root.iconFont
                    font.pixelSize: 17
                    color: toolHover.hovered ? root.accent : root.fg
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tool.label
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: root.fg
                }
            }
        }

        HoverHandler { id: toolHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: toolTap; onTapped: tool.clicked() }
    }

    component Chip: Item {
        id: chip
        property string icon: ""
        property string label: ""
        property bool primary: false
        property bool warn: false
        signal clicked()

        readonly property color fill: warn ? root.danger : primary ? root.accent : root.surface
        readonly property color ink: (warn || primary) ? root.bg : root.fg

        implicitWidth: chipRow.implicitWidth + 26
        implicitHeight: 30

        ContinuousRect {
            anchors.fill: parent
            radius: height / 2
            color: chip.fill
            scale: chipTap.pressed ? 0.97 : 1
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: Commons.Style.duration(140); easing.type: Easing.OutCubic } }

            ContinuousRect {
                anchors.fill: parent
                radius: height / 2
                color: (chip.primary || chip.warn) ? root.bg : root.fg
                opacity: chipHover.hovered ? ((chip.primary || chip.warn) ? 0.14 : 0.08) : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic } }
            }

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 7
                Text {
                    visible: chip.icon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.icon
                    font.family: root.iconFont
                    font.pixelSize: 13
                    color: chip.ink
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.label
                    font.pixelSize: 13
                    font.weight: (chip.primary || chip.warn) ? Font.DemiBold : Font.Medium
                    color: chip.ink
                }
            }
        }

        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: chipTap; onTapped: chip.clicked() }
    }

    // Cartão com cantos contínuos e conteúdo em coluna.
    component Card: ContinuousRect {
        default property alias body: cardCol.data
        property alias spacing: cardCol.spacing

        Layout.fillWidth: true
        Layout.preferredHeight: cardCol.implicitHeight + 28
        radius: 16
        color: root.surface

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10
        }
    }

    // Ícone dentro de um quadradinho tingido.
    component CardIcon: ContinuousRect {
        property string glyph: ""
        property bool lit: false

        Layout.preferredWidth: 34
        Layout.preferredHeight: 34
        Layout.alignment: Qt.AlignVCenter
        radius: 11
        color: lit ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)

        Text {
            anchors.centerIn: parent
            text: parent.glyph
            font.family: root.iconFont
            font.pixelSize: 16
            color: parent.lit ? root.accent : root.dim
        }
    }

    // ---------- Layout ----------
    ColumnLayout {
        id: content
        width: root.implicitWidth
        spacing: 12

        // Cabeçalho: voltar + título
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Chip {
                icon: "\uF053" // nf-fa-chevron_left
                label: strings.t("tools.back")
                onClicked: root.navigate("control")
            }
            Text {
                Layout.fillWidth: true
                text: strings.t("tools.title")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignRight
                rightPadding: 4
                color: root.fg
            }
        }

        // Cartão de internet
        Card {
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                CardIcon {
                    lit: root.netKind !== "disconnected"
                    glyph: root.netKind === "ethernet" ? "\uDB80\uDE00" // nf-md-ethernet
                           : root.netKind === "wifi" ? "\uDB81\uDDA9" // nf-md-wifi
                           : "\uDB81\uDDAA" // nf-md-wifi_off
                }
                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: root.netKind === "disconnected" ? strings.t("tools.net.offline")
                              : root.netName !== "" ? root.netName
                              : root.netIface !== "" ? root.netIface
                              : root.netKind === "wifi" ? strings.t("tools.net.wifi") : strings.t("tools.net.ethernet")
                        textFormat: Text.PlainText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        color: root.fg
                    }
                    Text {
                        width: parent.width
                        text: {
                            if (root.netKind === "disconnected") return strings.t("tools.net.offlineHint");
                            const parts = [root.netKind === "wifi" ? strings.t("tools.net.wifi") : strings.t("tools.net.ethernet")];
                            if (root.netIface !== "" && root.netIface !== root.netName) parts.push(root.netIface);
                            parts.push(root.netAddress !== "" ? root.netAddress : strings.t("tools.net.noAddress"));
                            return parts.join("  ·  ");
                        }
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        color: root.dim
                    }
                }
            }

            Row {
                Layout.fillWidth: true
                visible: root.shell !== null && root.netKind !== "disconnected"
                spacing: 8
                Chip {
                    visible: root.netKind === "wifi"
                    icon: "\uF029" // nf-fa-qrcode
                    label: strings.t("tools.net.wifiQr")
                    onClicked: root.openWifiQr()
                }
                Chip {
                    icon: "\uDB81\uDCC5" // nf-md-speedometer
                    label: strings.t("tools.net.speedTest")
                    onClicked: root.openSpeedTest()
                }
            }
        }

        // Grade de ferramentas
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 10
            columnSpacing: 10

            ToolButton {
                icon: "\uF0EA" // nf-fa-clipboard
                label: strings.t("tools.clipboard")
                onClicked: root.launch(["omarchy", "menu", "clipboard"])
            }
            ToolButton {
                icon: "\uF118" // nf-fa-smile_o
                label: strings.t("tools.emoji")
                onClicked: root.launch(["omarchy", "menu", "emoji"])
            }
            ToolButton {
                icon: "\uF11C" // nf-fa-keyboard_o
                label: strings.t("tools.keybindings")
                onClicked: root.launch(["omarchy", "menu", "keybindings"])
            }
            ToolButton {
                icon: "\uF05A" // nf-fa-info_circle
                label: strings.t("tools.about")
                onClicked: root.launch(["omarchy", "launch", "about"])
            }
            ToolButton {
                icon: "\uF0AC" // nf-fa-globe
                label: strings.t("tools.timezone")
                onClicked: root.launch(["omarchy", "menu", "timezone"])
            }
            ToolButton {
                icon: "\uF0C9" // nf-fa-bars
                label: strings.t("tools.omarchyMenu")
                // "summon" sempre abre o menu principal (rota raiz), sem alternar.
                onClicked: root.launch(["omarchy", "menu", "summon"])
            }
        }

        // Cartão de atualizações
        Card {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                CardIcon {
                    lit: root.hasUpdates
                    glyph: root.hasUpdates ? "\uF021" // nf-fa-refresh
                           : root.updatesChecking ? "\uF017" // nf-fa-clock_o
                           : "\uF058" // nf-fa-check_circle
                }
                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: root.updatesChecking ? strings.t("tools.updates.checking")
                              : root.hasUpdates ? strings.t("tools.updates.available")
                              : strings.t("tools.updates.upToDate")
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        color: root.fg
                    }
                    Text {
                        width: parent.width
                        visible: root.hasUpdates
                        text: root.fmt(strings.tn("tools.updates.pending", root.updateLines.length),
                                       [Commons.I18n.formatNumber(root.updateLines.length)])
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        color: root.dim
                    }
                }
                Chip {
                    visible: root.hasUpdates
                    primary: true
                    label: strings.t("tools.updates.update")
                    // Mesmo caminho que o próprio Omarchy usa para atualizar.
                    onClicked: root.launch(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"])
                }
            }

            Repeater {
                model: root.hasUpdates ? root.updateLines.slice(0, 3) : []
                Text {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 46
                    text: root.describeUpdate(modelData)
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    color: root.dim
                }
            }
        }

        // Cartão de lembretes
        Card {
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                CardIcon {
                    lit: root.reminderCount > 0
                    glyph: "\uF0F3" // nf-fa-bell
                }
                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.reminderCount === 0 ? strings.t("tools.reminders.none")
                          : root.fmt(strings.tn("tools.reminders.active", root.reminderCount),
                                     [Commons.I18n.formatNumber(root.reminderCount)])
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: root.fg
                }
                Chip {
                    visible: root.reminderCount > 0
                    warn: root.clearArmed
                    icon: "\uF1F8" // nf-fa-trash
                    label: root.clearArmed ? strings.t("tools.reminders.confirmClear") : strings.t("tools.reminders.clear")
                    onClicked: root.clearReminders()
                }
            }

            Repeater {
                model: root.reminders.slice(0, 3)
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 46
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: String(modelData.label || modelData.message || strings.t("tools.reminders.defaultMessage"))
                        textFormat: Text.PlainText
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        color: root.fg
                    }
                    Text {
                        text: [String(modelData.remaining || ""),
                               modelData.atTime ? root.fmt(strings.t("tools.reminders.at"), [String(modelData.atTime)]) : ""]
                              .filter(s => s.length > 0).join(" · ")
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        color: root.dim
                    }
                }
            }

            // Atalhos de criação rápida
            Row {
                Layout.fillWidth: true
                spacing: 8
                Chip { label: strings.t("tools.reminders.in5"); onClicked: root.addReminder(5) }
                Chip { label: strings.t("tools.reminders.in15"); onClicked: root.addReminder(15) }
                Chip { label: strings.t("tools.reminders.in30"); onClicked: root.addReminder(30) }
                Chip { label: strings.t("tools.reminders.in60"); onClicked: root.addReminder(60) }
            }
        }
    }
}
