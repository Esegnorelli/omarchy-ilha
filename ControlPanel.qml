import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons as Commons

// Central de controle: data/hora, Wi-Fi, Bluetooth, microfone, alternâncias
// do Omarchy (luz noturna, não perturbe, manter acordado, animações, modo
// jogo), volume, bateria (só em notebook) e atalhos para outros estados da ilha.
//
// Luz noturna, Não perturbe e Manter acordado usam os proxies do host
// (shell.firstPartyServiceFor) quando `shell` existe; sem ele, caem nos
// comandos `omarchy toggle ...` e releem o status.
Item {
    id: root

    // Cores do tema (o host passa as mesmas).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent

    // Fachada PluginShellApi do host (pode ser null no modo avulso).
    property var shell: null

    // Verdadeiro enquanto este estado está visível na ilha (definido pelo host).
    property bool active: false

    // Pede ao host para recolher a ilha.
    signal closeRequested()
    // Pede ao host para trocar de estado ("capture", "style", "tools", "power"...).
    signal navigate(string target)

    implicitWidth: 400
    implicitHeight: content.implicitHeight

    readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.07)
    readonly property color surfaceHover: Qt.rgba(fg.r, fg.g, fg.b, 0.13)
    readonly property color dim: Commons.Color.muted

    Commons.Translations {
        id: strings
        directory: Qt.resolvedUrl("i18n")
    }

    // ---------- Relógio ----------
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    readonly property var locale: Qt.locale(Commons.I18n.formatLocale)
    readonly property string dateText: clock.date.toLocaleString(locale, strings.t("control.dateFormat")).replace("-feira", "")
    readonly property string timeText: clock.date.toLocaleString(locale, strings.t("control.timeFormat"))

    // ---------- Wi-Fi (Quickshell.Networking) ----------
    readonly property var netDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: {
        let fallback = null;
        for (const d of netDevices) {
            if (!d || d.type !== DeviceType.Wifi) continue;
            if (d.connected) return d;
            if (!fallback) fallback = d;
        }
        return fallback;
    }
    readonly property bool hasWifi: wifiDevice !== null
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property string wifiSsid: {
        if (!wifiDevice || !wifiDevice.networks) return "";
        for (const n of wifiDevice.networks.values) {
            if (n && n.connected) return n.name;
        }
        return "";
    }

    function toggleWifi() {
        Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]);
    }

    // ---------- Bluetooth ----------
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool hasBluetooth: btAdapter !== null
    readonly property bool btOn: btAdapter ? btAdapter.enabled : false
    readonly property int btConnected: {
        const devs = Bluetooth.devices ? Bluetooth.devices.values : [];
        let c = 0;
        for (const d of devs) if (d && d.connected) c++;
        return c;
    }

    function toggleBluetooth() {
        if (root.btAdapter) root.btAdapter.enabled = !root.btAdapter.enabled;
    }

    // ---------- Áudio (Pipewire) ----------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    PwObjectTracker {
        objects: [root.sink, root.source].filter(o => o !== null)
    }
    readonly property bool sinkReady: sink !== null && sink.audio !== null
    readonly property real volume: sinkReady ? sink.audio.volume : 0
    readonly property bool sinkMuted: sinkReady ? sink.audio.muted : false
    readonly property bool hasMic: source !== null && source.audio !== null
    readonly property bool micMuted: hasMic ? source.audio.muted : true

    function setVolume(v) {
        if (root.sinkReady) root.sink.audio.volume = Math.max(0, Math.min(1, v));
    }
    function toggleSinkMute() {
        if (root.sinkReady) root.sink.audio.muted = !root.sink.audio.muted;
    }
    function toggleMic() {
        if (root.hasMic) root.source.audio.muted = !root.source.audio.muted;
    }

    // ---------- Bateria (UPower) ----------
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.ready && battery.isLaptopBattery && battery.isPresent
    readonly property real batteryLevel: hasBattery ? battery.percentage : 0
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging
                                                     || battery.state === UPowerDeviceState.FullyCharged
                                                     || battery.state === UPowerDeviceState.PendingCharge)

    // ---------- Proxies do host ----------
    function serviceFor(id) {
        if (!root.shell || typeof root.shell.firstPartyServiceFor !== "function") return null;
        try { return root.shell.firstPartyServiceFor(id) || null; } catch (e) { return null; }
    }
    readonly property var nightService: shell ? serviceFor("omarchy.nightlight") : null
    readonly property var dndService: shell ? serviceFor("omarchy.notifications") : null
    readonly property var idleService: shell ? serviceFor("omarchy.idle") : null

    // ---------- Alternâncias do Omarchy ----------
    // Com proxy: o estado vem dele. Sem proxy: lido dos comandos de status ao
    // abrir o painel e ~0,6 s depois de cada toque.
    property bool _nightLocal: false
    property bool _dndLocal: false
    property bool _stayAwakeLocal: false
    readonly property bool nightOn: nightService ? nightService.enabled === true : _nightLocal
    readonly property bool dndOn: dndService ? dndService.doNotDisturb === true : _dndLocal
    // Verdadeiro = ociosidade bloqueada (o proxy chama de stayAwake).
    readonly property bool stayAwake: idleService ? idleService.stayAwake === true : _stayAwakeLocal
    property bool animationsOn: true

    Process {
        id: nightProc
        command: ["omarchy", "toggle", "nightlight", "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root._nightLocal = JSON.parse(text).enabled === true; } catch (e) {}
            }
        }
    }
    Process {
        id: idleProc
        command: ["omarchy", "toggle", "idle", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                // enabled = modo "manter acordado" ligado (ociosidade bloqueada).
                try { root._stayAwakeLocal = JSON.parse(text).enabled === true; } catch (e) {}
            }
        }
    }
    Process {
        id: dndProc
        command: ["omarchy-shell", "notifications", "isDnd"]
        stdout: StdioCollector {
            onStreamFinished: root._dndLocal = text.trim() === "on"
        }
    }
    Process {
        id: animProc
        // Código de saída 0 significa que as animações estão desligadas.
        command: ["omarchy-hyprland-toggle-enabled", "no-animations"]
        onExited: (exitCode, exitStatus) => root.animationsOn = exitCode !== 0
    }

    function refreshToggles() {
        if (!root.nightService) nightProc.running = true;
        if (!root.idleService) idleProc.running = true;
        if (!root.dndService) dndProc.running = true;
        animProc.running = true;
    }

    // Relê o estado real depois que o comando de alternância terminar.
    Timer {
        id: rereadTimer
        interval: 600
        onTriggered: if (root.active) root.refreshToggles()
    }

    function runToggle(cmd) {
        Quickshell.execDetached(cmd);
        rereadTimer.restart();
    }

    function toggleNight() {
        if (root.nightService) {
            root.nightService.setNightlight(!root.nightOn);
        } else {
            root._nightLocal = !root._nightLocal;
            root.runToggle(["omarchy", "toggle", "nightlight"]);
        }
    }
    function toggleDnd() {
        if (root.dndService) {
            root.dndService.setDoNotDisturb(!root.dndOn);
        } else {
            root._dndLocal = !root._dndLocal;
            root.runToggle(["omarchy", "toggle", "notification", "silencing"]);
        }
    }
    function toggleStayAwake() {
        if (root.idleService) {
            // setIdleEnabled(true) desliga o "manter acordado"; false liga.
            root.idleService.setIdleEnabled(root.stayAwake);
        } else {
            root._stayAwakeLocal = !root._stayAwakeLocal;
            root.runToggle(["omarchy", "toggle", "idle"]);
        }
    }
    function toggleAnimations() {
        root.animationsOn = !root.animationsOn;
        root.runToggle(["omarchy", "toggle", "animations"]);
    }

    // ---------- Modo jogo ----------
    // Ligar: salva animações, espaçamento e transparência atuais em
    // game-mode.json e desliga o que estiver ligado. Desligar: lê o arquivo,
    // devolve só o que foi mudado e apaga o arquivo. Ligado = o arquivo existe.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/esegnorelli.ilha"
    readonly property string gameModeFile: stateDir + "/game-mode.json"
    property bool gameModeOn: false
    property bool gameBusy: false

    // Estado lido antes de ligar.
    property bool _gmAnim: true
    property bool _gmGaps: true

    // Fila de comandos executados um por vez (cada um recarrega o Hyprland).
    property var _gmQueue: []
    property bool _gmStepIsSave: false

    Process {
        id: gmExistsProc
        command: ["test", "-f", root.gameModeFile]
        onExited: (exitCode, exitStatus) => root.gameModeOn = exitCode === 0
    }
    Process {
        id: gmAnimProc
        // Código 0 = animações desligadas.
        command: ["omarchy-hyprland-toggle-enabled", "no-animations"]
        onExited: (exitCode, exitStatus) => {
            root._gmAnim = exitCode !== 0;
            gmGapsProc.running = true;
        }
    }
    Process {
        id: gmGapsProc
        // Código 0 = espaçamento desligado.
        command: ["omarchy-hyprland-toggle-enabled", "window-no-gaps"]
        onExited: (exitCode, exitStatus) => {
            root._gmGaps = exitCode !== 0;
            gmTransProc.running = true;
        }
    }
    Process {
        id: gmTransProc
        command: ["omarchy", "hyprland", "window", "transparency"]
        stdout: StdioCollector {
            onStreamFinished: root._gmEnable(text.trim())
        }
    }
    Process {
        id: gmReadProc
        command: ["cat", root.gameModeFile]
        stdout: StdioCollector {
            onStreamFinished: root._gmDisable(text)
        }
    }
    Process {
        id: gmStepProc
        onExited: (exitCode, exitStatus) => {
            // Sem o arquivo salvo não há como desfazer: não muda mais nada.
            if (exitCode !== 0 && root._gmStepIsSave) {
                root._gmQueue = [];
                root.gameModeOn = false;
            }
            Qt.callLater(root._gmNext);
        }
    }
    // Garante que a alternância não fica presa se algum passo não terminar.
    Timer {
        id: gmWatchdog
        interval: 30000
        onTriggered: {
            root._gmQueue = [];
            root._gmFinish();
        }
    }
    Timer {
        id: gmRecheckTimer
        interval: 400
        onTriggered: {
            gmExistsProc.running = true;
            root.refreshToggles();
        }
    }

    function _isMode(m) {
        return m === "opaque" || m === "transparent" || m === "glassy";
    }

    function toggleGameMode() {
        if (root.gameBusy) return;
        root.gameBusy = true;
        // Cobre também as leituras: se uma não terminar, o bloco não fica preso.
        gmWatchdog.restart();
        if (root.gameModeOn) gmReadProc.running = true;
        else gmAnimProc.running = true;
    }

    // Passos para ligar, a partir do estado lido (sem executar nada).
    function gameModeOnSteps(anim, gaps, mode) {
        if (!root._isMode(mode)) return [];
        // JSON montado só com booleanos e um valor conhecido.
        const json = JSON.stringify({ animations: anim === true, gaps: gaps === true, transparency: mode });
        const steps = [["sh", "-c", "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/game-mode.json\"", "sh", root.stateDir, json]];
        if (anim) steps.push(["omarchy", "toggle", "animations", "off"]);
        if (gaps) steps.push(["omarchy-hyprland-toggle", "window-no-gaps", "on"]);
        if (mode !== "opaque") steps.push(["omarchy", "hyprland", "window", "transparency", "opaque"]);
        return steps;
    }

    // Passos para desligar, a partir do conteúdo de game-mode.json.
    function gameModeOffSteps(text) {
        let saved = null;
        try { saved = JSON.parse(text); } catch (e) {}
        const steps = [];
        if (saved && typeof saved === "object") {
            if (saved.animations === true) steps.push(["omarchy", "toggle", "animations", "on"]);
            if (saved.gaps === true) steps.push(["omarchy-hyprland-toggle", "window-no-gaps", "off"]);
            if (root._isMode(saved.transparency) && saved.transparency !== "opaque")
                steps.push(["omarchy", "hyprland", "window", "transparency", saved.transparency]);
        }
        steps.push(["rm", "-f", root.gameModeFile]);
        return steps;
    }

    function _gmEnable(mode) {
        const steps = root.gameModeOnSteps(root._gmAnim, root._gmGaps, mode);
        if (steps.length === 0) { root._gmFinish(); return; }
        root.gameModeOn = true;
        root._gmRun(steps);
    }

    function _gmDisable(text) {
        root.gameModeOn = false;
        root._gmRun(root.gameModeOffSteps(text));
    }

    function _gmRun(steps) {
        root._gmQueue = steps;
        gmWatchdog.restart();
        root._gmNext();
    }

    function _gmNext() {
        if (root._gmQueue.length === 0) { root._gmFinish(); return; }
        const q = root._gmQueue.slice();
        const cmd = q.shift();
        root._gmStepIsSave = cmd[0] === "sh"; // único passo via sh: gravar o arquivo
        gmStepProc.command = cmd;
        root._gmQueue = q;
        gmStepProc.running = true;
    }

    function _gmFinish() {
        gmWatchdog.stop();
        root.gameBusy = false;
        gmRecheckTimer.restart();
    }

    onActiveChanged: {
        if (active) {
            refreshToggles();
            if (!gameBusy) gmExistsProc.running = true;
        } else {
            rereadTimer.stop();
        }
    }
    Component.onCompleted: if (active) { refreshToggles(); gmExistsProc.running = true; }

    // ---------- Componentes internos ----------
    component Tile: ContinuousRect {
        id: tile
        property bool on: false
        property string icon: ""
        property string label: ""
        property string sublabel: ""
        property int tileHeight: 64
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: tileHeight
        radius: 16
        color: on ? root.accent : (tileHover.hovered ? root.surfaceHover : root.surface)
        Behavior on color {
            ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }
        scale: tileTap.pressed ? 0.97 : 1
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }

        property color ink: on ? root.bg : root.fg
        Behavior on ink {
            ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                name: tile.icon
                size: 22
                filled: tile.on
                color: tile.ink
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                spacing: 2
                Text {
                    width: parent.width
                    text: tile.label
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: tile.ink
                }
                Text {
                    width: parent.width
                    text: tile.sublabel
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    color: tile.ink
                    opacity: 0.72
                }
            }
        }

        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: tileTap; onTapped: tile.clicked() }
    }

    component NavChip: ContinuousRect {
        id: chip
        property string icon: ""
        property string label: ""
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredWidth: chipRow.implicitWidth + 20
        Layout.preferredHeight: 36
        radius: height / 2
        color: chipHover.hovered ? root.surfaceHover : root.surface
        Behavior on color {
            ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }
        scale: chipTap.pressed ? 0.97 : 1
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: chip.icon
                size: 17
                filled: chipHover.hovered
                color: chipHover.hovered ? root.accent : root.fg
                Behavior on color {
                    ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                font.pixelSize: 12
                color: root.fg
            }
        }

        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: chipTap; onTapped: chip.clicked() }
    }

    // ---------- Layout ----------
    ColumnLayout {
        id: content
        width: root.implicitWidth
        spacing: 12

        // Cabeçalho: data e hora
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Text {
                Layout.fillWidth: true
                text: root.dateText
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: root.fg
            }
            Text {
                text: root.timeText
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: root.accent
            }
        }

        // Blocos de liga/desliga
        RowLayout {
            Layout.fillWidth: true
            visible: root.hasWifi || root.hasBluetooth || root.hasMic
            spacing: 8

            Tile {
                visible: root.hasWifi
                on: root.wifiOn
                icon: root.wifiOn ? "wifi" : "wifi_off"
                label: strings.t("control.wifi")
                sublabel: !root.wifiOn ? strings.t("control.off")
                          : (root.wifiSsid !== "" ? root.wifiSsid : strings.t("control.noConnection"))
                onClicked: root.toggleWifi()
            }
            Tile {
                visible: root.hasBluetooth
                on: root.btOn
                icon: root.btOn ? "bluetooth" : "bluetooth_disabled"
                label: strings.t("control.bluetooth")
                sublabel: !root.btOn ? strings.t("control.off")
                          : (root.btConnected > 0
                             ? strings.tn("control.connected", root.btConnected).arg(Commons.I18n.formatNumber(root.btConnected))
                             : strings.t("control.on"))
                onClicked: root.toggleBluetooth()
            }
            Tile {
                visible: root.hasMic
                on: !root.micMuted
                icon: root.micMuted ? "mic_off" : "mic"
                label: strings.t("control.microphone")
                sublabel: root.micMuted ? strings.t("control.micMuted") : strings.t("control.micActive")
                onClicked: root.toggleMic()
            }
        }

        // Alternâncias do Omarchy (grade de 2 colunas)
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            Tile {
                tileHeight: 56
                on: root.nightOn
                icon: "dark_mode"
                label: strings.t("control.nightlight")
                sublabel: root.nightOn ? strings.t("control.nightlightOn") : strings.t("control.nightlightOff")
                onClicked: root.toggleNight()
            }
            Tile {
                tileHeight: 56
                on: root.dndOn
                icon: "notifications_off"
                label: strings.t("control.dnd")
                sublabel: root.dndOn ? strings.t("control.dndOn") : strings.t("control.off")
                onClicked: root.toggleDnd()
            }
            Tile {
                tileHeight: 56
                on: root.stayAwake
                icon: "coffee"
                label: strings.t("control.stayAwake")
                sublabel: root.stayAwake ? strings.t("control.stayAwakeOn") : strings.t("control.off")
                onClicked: root.toggleStayAwake()
            }
            Tile {
                tileHeight: 56
                on: root.animationsOn
                icon: "animation"
                label: strings.t("control.animations")
                sublabel: root.animationsOn ? strings.t("control.animationsOn") : strings.t("control.animationsOff")
                onClicked: root.toggleAnimations()
            }
            Tile {
                Layout.columnSpan: 2
                tileHeight: 56
                on: root.gameModeOn
                icon: "sports_esports"
                label: strings.t("control.gameMode")
                sublabel: root.gameBusy ? strings.t("control.applying")
                          : root.gameModeOn ? strings.t("control.gameModeOn") : strings.t("control.off")
                onClicked: root.toggleGameMode()
            }
        }

        // Volume
        ContinuousRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            visible: root.sinkReady
            radius: 16
            color: root.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 16
                spacing: 10

                // Ícone: alterna mudo
                ContinuousRect {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: height / 2
                    color: muteHover.hovered ? root.surfaceHover : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: root.sinkMuted || root.volume === 0 ? "volume_off"
                              : root.volume < 0.5 ? "volume_down"
                              : "volume_up"
                        size: 20
                        filled: !root.sinkMuted
                        color: root.sinkMuted ? root.dim : root.fg
                    }
                    HoverHandler { id: muteHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.toggleSinkMute() }
                }

                // Trilho do volume
                Item {
                    id: slider
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    function setFromX(x) { root.setVolume(x / width); }

                    ContinuousRect {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 8
                        radius: height / 2
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

                        ContinuousRect {
                            height: parent.height
                            radius: height / 2
                            width: Math.max(height, track.width * Math.min(1, root.volume))
                            color: root.sinkMuted ? root.dim : root.accent
                            Behavior on width {
                                enabled: !sliderDrag.active
                                NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic }
                            }
                            Behavior on color {
                                ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    ContinuousRect {
                        id: knob
                        width: 16
                        height: 16
                        radius: height / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.min(1, root.volume) * (slider.width - width)
                        color: root.fg
                        scale: sliderHover.hovered || sliderDrag.active ? 1.15 : 1
                        Behavior on scale {
                            NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                        }
                        Behavior on x {
                            enabled: !sliderDrag.active
                            NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic }
                        }
                    }

                    HoverHandler { id: sliderHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: (eventPoint) => slider.setFromX(eventPoint.position.x)
                    }
                    DragHandler {
                        id: sliderDrag
                        target: null
                        xAxis.enabled: true
                        yAxis.enabled: false
                        onCentroidChanged: if (active) slider.setFromX(centroid.position.x)
                    }
                }

                Text {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: strings.t("control.percent").arg(Math.round(root.volume * 100))
                    font.pixelSize: 13
                    color: root.sinkMuted ? root.dim : root.fg
                }
            }
        }

        // Bateria (só em notebook)
        ContinuousRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            visible: root.hasBattery
            radius: 16
            color: root.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 10
                Icon {
                    name: root.charging ? "battery_charging_full"
                          : root.batteryLevel > 0.85 ? "battery_full"
                          : root.batteryLevel > 0.6 ? "battery_5_bar"
                          : root.batteryLevel > 0.35 ? "battery_3_bar"
                          : root.batteryLevel > 0.1 ? "battery_2_bar"
                          : "battery_alert"
                    size: 20
                    filled: true
                    color: root.batteryLevel <= 0.1 && !root.charging ? root.danger : root.fg
                }
                Text {
                    Layout.fillWidth: true
                    text: root.charging ? strings.t("control.batteryCharging") : strings.t("control.battery")
                    font.pixelSize: 13
                    color: root.fg
                }
                Text {
                    text: strings.t("control.percent").arg(Math.round(root.batteryLevel * 100))
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: root.fg
                }
            }
        }

        // Atalhos para outros estados da ilha
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            NavChip {
                icon: "photo_camera"
                label: strings.t("control.navCapture")
                onClicked: root.navigate("capture")
            }
            NavChip {
                icon: "palette"
                label: strings.t("control.navStyle")
                onClicked: root.navigate("style")
            }
            NavChip {
                icon: "build"
                label: strings.t("control.navTools")
                onClicked: root.navigate("tools")
            }
            NavChip {
                icon: "power_settings_new"
                label: strings.t("control.navPower")
                onClicked: root.navigate("power")
            }
        }
    }
}
