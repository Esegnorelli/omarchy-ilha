import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons as Commons

// Controle (spec §3.4, painel 2): ligar, ajustar, conectar.
//   Duas linhas de 60 px: duas cápsulas (círculo do ícone + nome + estado) e
//   dois círculos (só o ícone; nome e estado no rodapé com o hover).
//   Q Wi-Fi* · W Não perturbe · E Microfone · R Manter acordado
//   A Bluetooth* · S Modo jogo · D Luz noturna · F Animações
//     (* sem Wi-Fi a vaga vira Proteção de tela; sem Bluetooth, Suspensão)
//   Ligado acende só o círculo do ícone em accent; o corpo fica neutro.
//   Wi-Fi com o rádio ligado e sem rede (e Bluetooth ligado sem aparelho
//   conectado) fica em standby: véu de accent no círculo e o ícone em accent,
//   para não parecer conectado.
//   Som: LabeledRow "bar" de 80 px (−/= ±5%, M mudo; tocar no ícone = mudo;
//     › ou Enter na barra abre a subpágina Som: saídas e entrada)
//   Rede: InfoRow (interface · tipo, IPv4) com C QR do Wi-Fi* e V Velocidade
//     (fora do Wi-Fi: Velocidade ocupa c3–c4)
//   Rodapé: bateria (notebook) e o resumo do que está ligado, ou "Tudo normal".
// A altura é a mesma em qualquer máquina: o microfone ausente fica cinza no lugar.
//
// Luz noturna, Não perturbe e Manter acordado usam os proxies do host
// (shell.firstPartyServiceFor) quando `shell` existe; sem ele, caem nos
// comandos `omarchy toggle ...` e releem o status.
//
// Contrato de estado: active, shell, closeRequested(), navigate(target),
// fg/bg/accent/danger, metrics, keyboardMode, footerStatus, footerHints,
// footerAlert, handleKey(event) → bool, handleEscape() → bool, focusFirst().
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
    property Metrics metrics: Metrics {}
    property bool keyboardMode: false
    // Fonte do Estilo (o host passa a mesma da ilha).
    property string fontFamily: Commons.Style.fontFamily

    // Subpágina aberta: "" = grade principal, "sound" = saídas e entrada.
    property string page: ""

    // Pede ao host para recolher a ilha.
    signal closeRequested()
    // Pede ao host para trocar de estado.
    signal navigate(string target)

    implicitWidth: metrics.content
    // A altura segue a página visível, e o host acompanha.
    implicitHeight: page === "sound" ? soundPage.implicitHeight : grid.implicitHeight

    Commons.Translations {
        id: strings
        directory: Qt.resolvedUrl("i18n")
    }

    // Texto do catálogo; enquanto a chave não existir, cai no texto embutido.
    function tr(key, pt, en) {
        const v = strings.t(key, "");
        if (v !== "") return v;
        return String(strings.language || "").toLowerCase().indexOf("pt") === 0 ? pt : en;
    }

    // Troca %1, %2... numa passada só (um SSID com "%2" não é trocado de novo).
    function fmt(template, args) {
        return String(template).replace(/%(\d+)/g, (m, n) => {
            const i = parseInt(n) - 1;
            return i >= 0 && i < args.length ? String(args[i]) : m;
        });
    }

    // Abre um painel do Omarchy pelo host (que escolhe a implementação ativa).
    function summonPanel(id, payload) {
        if (!root.shell || typeof root.shell.summon !== "function") return;
        root.closeRequested();
        root.shell.summon(id, JSON.stringify(payload || {}));
    }

    // ---------- Rede (Quickshell.Networking) ----------
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

    readonly property bool hasWifi: wifiDevice !== null
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property string wifiSsid: wifiNetwork && wifiNetwork.name ? String(wifiNetwork.name) : ""
    // Conectado de fato (o rádio ligado sozinho não conta).
    readonly property bool wifiLinked: wifiNetwork !== null || (wifiDevice !== null && wifiDevice.connected === true)

    // Cabo tem prioridade quando os dois estão ligados (rota padrão).
    readonly property string netKind: {
        if (wiredDevice && wiredDevice.connected) return "ethernet";
        if (wifiNetwork || (wifiDevice && wifiDevice.connected)) return "wifi";
        return "disconnected";
    }
    readonly property var netDevice: netKind === "ethernet" ? wiredDevice : netKind === "wifi" ? wifiDevice : null
    readonly property string netIface: netDevice ? String(netDevice.name || "") : ""
    readonly property string netName: {
        if (netKind === "wifi") return wifiSsid;
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
    Connections {
        target: root
        function onActiveChanged() { if (root.active) root.refreshAddress(); }
    }
    QtObject { Component.onCompleted: root.refreshAddress() }

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
        if (root.netKind === "wifi") connection = root.netName || strings.t("control.net.wifi");
        else if (root.netKind === "ethernet") connection = strings.t("control.net.ethernet");
        summonPanel("omarchy.speedtest", connection !== "" ? { connection: connection } : {});
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
    readonly property real micVolume: hasMic ? source.audio.volume : 0

    function setMicVolume(v) {
        if (!root.hasMic) return;
        const cap = Math.max(1, root.micVolume);
        root.source.audio.volume = Math.max(0, Math.min(cap, v));
    }

    // Saídas reais (sem streams nem os medidores do próprio shell).
    readonly property var sinks: {
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
        return nodes.filter(n => n && n.audio && n.isSink && !n.isStream
                                 && !Commons.AudioNodes.isShellLevelMeter(n.name));
    }
    function sinkName(n) {
        return n ? String(n.description || n.nickname || n.name || "") : "";
    }
    function isDefaultSink(n) {
        return !!n && !!root.sink && n.id === root.sink.id;
    }
    function selectSink(n) {
        if (n) Pipewire.preferredDefaultAudioSink = n;
    }

    // Nunca corta um volume acima de 100% (o pavucontrol deixa passar):
    // o teto é o maior entre 100% e o atual.
    function setVolume(v) {
        if (!root.sinkReady) return;
        const cap = Math.max(1, root.volume);
        root.sink.audio.volume = Math.max(0, Math.min(cap, v));
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
    property bool screensaverOn: true
    property bool suspendOn: true
    Process {
        id: saverProc
        command: ["omarchy-toggle-enabled", "screensaver-off"]
        onExited: (exitCode, exitStatus) => root.screensaverOn = exitCode !== 0
    }
    Process {
        id: suspendProc
        command: ["omarchy-toggle-enabled", "suspend-off"]
        onExited: (exitCode, exitStatus) => root.suspendOn = exitCode !== 0
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
        saverProc.running = true;
        suspendProc.running = true;
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
    function toggleScreensaver() {
        root.screensaverOn = !root.screensaverOn;
        root.runToggle(["omarchy", "toggle", "screensaver"]);
    }
    function toggleSuspend() {
        root.suspendOn = !root.suspendOn;
        root.runToggle(["omarchy", "toggle", "suspend"]);
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
            // Reabrir o Controle sempre começa na grade.
            page = "";
        }
    }
    Component.onCompleted: if (active) { refreshToggles(); gmExistsProc.running = true; }

    // ---------- Hardware (lido uma vez) ----------
    // Os dispositivos chegam aos poucos depois de carregar; depois de visto, o
    // bloco fica. Assim a grade não muda de forma enquanto o painel está aberto.
    property bool hwWifi: false
    property bool hwBluetooth: false
    onHasWifiChanged: if (hasWifi) hwWifi = true
    onHasBluetoothChanged: if (hasBluetooth) hwBluetooth = true
    QtObject {
        Component.onCompleted: {
            if (root.hasWifi) root.hwWifi = true;
            if (root.hasBluetooth) root.hwBluetooth = true;
        }
    }

    // ---------- Rodapé ----------
    readonly property bool batteryLow: hasBattery && batteryLevel <= 0.1 && !charging
    readonly property string batteryText: {
        if (!hasBattery) return "";
        const pct = strings.t("control.percent").arg(Math.round(batteryLevel * 100));
        return fmt(charging ? strings.t("control.footer.batteryCharging") : strings.t("control.footer.battery"), [pct]);
    }
    // Nomes do que está ligado e muda o comportamento do sistema.
    readonly property var activeNames: {
        const out = [];
        if (dndOn) out.push(strings.t("control.dnd"));
        if (nightOn) out.push(strings.t("control.nightlight"));
        if (stayAwake) out.push(strings.t("control.stayAwake"));
        if (gameModeOn) out.push(strings.t("control.gameMode"));
        if (!animationsOn) out.push(strings.t("control.animations") + " " + strings.t("control.animationsOff").toLowerCase());
        if (hasMic && micMuted) out.push(strings.t("control.footer.micMuted"));
        return out;
    }
    // Os círculos não têm texto: com o hover, o nome e o estado vão ao rodapé.
    readonly property string hoverNote: micTile.noteShown ? micTile.hoverNote
                                      : awakeTile.noteShown ? awakeTile.hoverNote
                                      : nightTile.noteShown ? nightTile.hoverNote
                                      : animTile.noteShown ? animTile.hoverNote
                                      : ""
    readonly property string footerStatus: {
        if (root.page === "" && root.hoverNote !== "") return root.hoverNote;
        const parts = [];
        if (batteryText !== "") parts.push(batteryText);
        if (activeNames.length > 0) parts.push(activeNames.join(", "));
        return parts.length > 0 ? parts.join(" · ") : strings.t("control.footer.allNormal");
    }
    readonly property bool footerAlert: batteryLow && !(root.page === "" && root.hoverNote !== "")
    readonly property string footerHints: root.page === "sound"
        ? root.tr("hint.subpage", "↑↓ escolher · Enter usar · Esc voltar", "↑↓ choose · Enter select · Esc back")
        : root.tr("hint.toggleMore", "Q–F alternar · −/= volume · M mudo · Enter no som: mais",
                  "Q–F toggle · −/= volume · M mute · Enter on sound: more")

    // ---------- Subpágina Som ----------
    // Linha marcada pelo teclado na lista de saídas (começa na saída padrão).
    property int soundIndex: -1
    function openSound() {
        root.page = "sound";
    }
    onPageChanged: {
        if (page === "sound") {
            let i = -1;
            for (let k = 0; k < root.sinks.length; k++)
                if (root.isDefaultSink(root.sinks[k])) { i = k; break; }
            root.soundIndex = i;
        }
    }

    // ---------- Teclado ----------
    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (!mods) {
            const k = event.key;
            if (k === Qt.Key_Minus || k === Qt.Key_Underscore) {
                root.setVolume(root.volume - 0.05);
                return true;
            }
            if (k === Qt.Key_Equal || k === Qt.Key_Plus) {
                root.setVolume(root.volume + 0.05);
                return true;
            }
            if (k === Qt.Key_M && !(event.modifiers & Qt.ShiftModifier)) {
                if (!event.isAutoRepeat) root.toggleSinkMute();
                return true;
            }
        }
        if (root.page === "sound") return root.handleSoundKey(event);
        return grid.handleKey(event);
    }
    function handleSoundKey(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)) return false;
        const k = event.key;
        const n = root.sinks.length;
        if (k === Qt.Key_Up || k === Qt.Key_Down) {
            if (n === 0) return true;
            const d = k === Qt.Key_Down ? 1 : -1;
            root.soundIndex = root.soundIndex < 0 ? (d > 0 ? 0 : n - 1)
                                                  : Math.max(0, Math.min(n - 1, root.soundIndex + d));
            return true;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (event.isAutoRepeat) return true;
            if (root.soundIndex >= 0 && root.soundIndex < n) root.selectSink(root.sinks[root.soundIndex]);
            return true;
        }
        if (k === Qt.Key_Left) {
            root.page = "";
            return true;
        }
        return false;
    }
    function handleEscape() {
        if (root.page !== "") {
            root.page = "";
            return true;
        }
        return grid.handleEscape();
    }
    function focusFirst() { return grid.focusFirst(); }

    // ---------- Layout ----------
    PanelGrid {
        id: grid
        metrics: root.metrics
        strings: strings
        keyboardMode: root.keyboardMode
        fontFamily: root.fontFamily
        fg: root.fg
        bg: root.bg
        accent: root.accent
        danger: root.danger

        // As duas páginas se cruzam em fade; só a visível conta para o foco.
        opacity: root.page === "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.page === "" ? root.metrics.msFadeIn : root.metrics.msFadeOut); easing.type: Easing.OutCubic } }

        GridRow {
            tileHeight: root.metrics.capsuleTile

            Tile {
                visible: root.hwWifi
                shape: "capsule"
                kind: "toggle"
                on: root.wifiOn
                // Rádio ligado sem rede: véu de accent, não o círculo sólido.
                standby: root.wifiOn && !root.wifiLinked
                icon: root.wifiOn ? "wifi" : "wifi_off"
                label: strings.t("control.wifi")
                sublabel: !root.wifiOn ? strings.t("control.off")
                          : (root.wifiSsid !== "" ? root.wifiSsid : strings.t("control.noConnection"))
                onActivated: root.toggleWifi()
            }
            // Sem Wi-Fi na máquina, a vaga vira um toggle útil.
            Tile {
                visible: !root.hwWifi
                shape: "capsule"
                kind: "toggle"
                on: root.screensaverOn
                icon: "screenshot_monitor"
                label: strings.t("control.screensaver")
                sublabel: root.screensaverOn ? strings.t("control.on") : strings.t("control.off")
                onActivated: root.toggleScreensaver()
            }
            Tile {
                shape: "capsule"
                kind: "toggle"
                on: root.dndOn
                icon: root.dndOn ? "notifications_off" : "notifications"
                label: strings.t("control.dnd")
                sublabel: root.dndOn ? strings.t("control.dndOn") : strings.t("control.off")
                onActivated: root.toggleDnd()
            }
            Tile {
                id: micTile
                shape: "round"
                kind: "toggle"
                on: root.hasMic && !root.micMuted
                available: root.hasMic
                icon: root.hasMic && !root.micMuted ? "mic" : "mic_off"
                label: strings.t("control.microphone")
                sublabel: root.micMuted ? strings.t("control.micMuted") : strings.t("control.micActive")
                unavailableText: strings.t("control.noMic")
                onActivated: root.toggleMic()
            }
            Tile {
                id: awakeTile
                shape: "round"
                kind: "toggle"
                on: root.stayAwake
                icon: "coffee"
                label: strings.t("control.stayAwake")
                sublabel: root.stayAwake ? strings.t("control.stayAwakeOn") : strings.t("control.off")
                onActivated: root.toggleStayAwake()
            }
        }

        GridRow {
            tileHeight: root.metrics.capsuleTile

            Tile {
                visible: root.hwBluetooth
                shape: "capsule"
                kind: "toggle"
                on: root.btOn
                // Ligado sem nenhum aparelho conectado: o mesmo standby do Wi-Fi.
                standby: root.btOn && root.btConnected === 0
                icon: root.btOn ? "bluetooth" : "bluetooth_disabled"
                label: strings.t("control.bluetooth")
                sublabel: !root.btOn ? strings.t("control.off")
                          : (root.btConnected > 0
                             ? strings.tn("control.connected", root.btConnected).arg(Commons.I18n.formatNumber(root.btConnected))
                             : strings.t("control.on"))
                onActivated: root.toggleBluetooth()
            }
            // Sem Bluetooth na máquina, a vaga vira a Suspensão.
            Tile {
                visible: !root.hwBluetooth
                shape: "capsule"
                kind: "toggle"
                on: root.suspendOn
                icon: "bedtime"
                label: strings.t("control.suspend")
                sublabel: root.suspendOn ? strings.t("control.suspendOn") : strings.t("control.off")
                onActivated: root.toggleSuspend()
            }
            Tile {
                shape: "capsule"
                kind: "toggle"
                on: root.gameModeOn
                busy: root.gameBusy
                icon: "sports_esports"
                label: strings.t("control.gameMode")
                sublabel: root.gameModeOn ? strings.t("control.gameModeOn") : strings.t("control.off")
                onActivated: root.toggleGameMode()
            }
            Tile {
                id: nightTile
                shape: "round"
                kind: "toggle"
                on: root.nightOn
                icon: "nightlight"
                label: strings.t("control.nightlight")
                sublabel: root.nightOn ? strings.t("control.nightlightOn") : strings.t("control.nightlightOff")
                onActivated: root.toggleNight()
            }
            Tile {
                id: animTile
                shape: "round"
                kind: "toggle"
                on: root.animationsOn
                icon: "animation"
                label: strings.t("control.animations")
                sublabel: root.animationsOn ? strings.t("control.animationsOn") : strings.t("control.animationsOff")
                onActivated: root.toggleAnimations()
            }
        }

        LabeledRow {
            variant: "bar"
            icon: !root.sinkReady || root.sinkMuted || root.volume === 0 ? "volume_off"
                  : root.volume < 0.5 ? "volume_down" : "volume_up"
            label: root.tr("control.sound", "Som", "Sound")
            value: !root.sinkReady ? strings.t("control.noOutput")
                   : root.sinkMuted ? strings.t("control.micMuted")
                   : strings.t("control.percent").arg(Math.round(root.volume * 100))
            sliderValue: Math.min(1, root.volume)
            stepBase: root.volume
            dimmed: !root.sinkReady || root.sinkMuted
            hasMore: true
            onMoved: v => root.setVolume(v)
            onLabelTapped: root.toggleSinkMute()
            onMoreTapped: root.openSound()
        }

        InfoRow {
            Accessible.name: strings.t("control.network")
            icon: root.netKind === "ethernet" ? "lan" : root.netKind === "wifi" ? "wifi" : "wifi_off"
            alert: root.netKind === "disconnected"
            title: {
                if (root.netKind === "disconnected") return strings.t("control.net.offline");
                const kind = root.netKind === "wifi" ? strings.t("control.net.wifi") : strings.t("control.net.ethernet");
                const name = root.netKind === "wifi" && root.netName !== "" ? root.netName : root.netIface;
                return name !== "" ? root.fmt(strings.t("control.net.title"), [name, kind]) : kind;
            }
            detail: root.netKind === "disconnected" ? strings.t("control.net.offlineHint")
                    : root.netAddress !== "" ? root.netAddress : strings.t("control.net.noAddress")

            Tile {
                visible: root.hwWifi && root.netKind === "wifi"
                // Dois botões de 122 px: só o texto cabe (como na spec).
                label: strings.t("control.net.wifiQr")
                available: root.shell !== null
                closesIsland: true
                onActivated: root.openWifiQr()
            }
            Tile {
                stretch: true
                icon: "speed"
                label: strings.t("control.net.speedTest")
                available: root.shell !== null && root.netKind !== "disconnected"
                closesIsland: true
                onActivated: root.openSpeedTest()
            }
        }
    }

    // Legenda de seção da página Som (frase, 12 Medium, fg a 60%).
    component Caption: Text {
        width: parent ? parent.width : 0
        height: root.metrics.caption
        leftPadding: 2
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.Medium
        elide: Text.ElideRight
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)
    }

    // ---------- Página Som: saídas e entrada ----------
    Column {
        id: soundPage
        width: root.metrics.content
        spacing: root.metrics.gap
        opacity: root.page === "sound" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.page === "sound" ? root.metrics.msFadeIn : root.metrics.msFadeOut); easing.type: Easing.OutCubic } }

        // Cabeçalho: ‹ redondo e o título.
        Item {
            width: parent.width
            height: 32
            IconButton {
                id: backButton
                solid: true
                size: 32
                iconSize: 18
                icon: "chevron_left"
                label: root.tr("grid.back", "Voltar", "Back")
                fg: root.fg
                accent: root.accent
                fontFamily: root.fontFamily
                metrics: root.metrics
                onTapped: root.page = ""
            }
            Text {
                anchors.left: backButton.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr("control.sound", "Som", "Sound")
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: root.fg
            }
        }

        Column {
            width: parent.width
            spacing: root.metrics.captionGap

            Caption { text: root.tr("control.output", "Saída", "Output") }

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.sinks
                    delegate: Item {
                        id: sinkRow
                        required property var modelData
                        required property int index
                        readonly property bool current: root.isDefaultSink(modelData)
                        readonly property bool marked: root.soundIndex === index && root.keyboardMode
                        width: parent.width
                        height: 44
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: root.sinkName(modelData)
                        Accessible.checked: current

                        // Seleção e hover: preenchimento neutro, nunca accent.
                        ContinuousRect {
                            anchors.fill: parent
                            radius: root.metrics.fit(height / 2)
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
                                           sinkRow.marked || sinkTap.pressed ? root.metrics.alphaPressed
                                           : sinkHover.hovered ? root.metrics.alphaHover
                                           : sinkRow.current ? root.metrics.alphaIdle : 0)
                            Behavior on color { ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                        }
                        Icon {
                            id: sinkIcon
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            name: "volume_up"
                            size: 18
                            color: root.fg
                        }
                        Text {
                            anchors.left: sinkIcon.right
                            anchors.leftMargin: 12
                            anchors.right: sinkCheck.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sinkName(sinkRow.modelData)
                            textFormat: Text.PlainText
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.weight: sinkRow.current ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            color: root.fg
                        }
                        Icon {
                            id: sinkCheck
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            name: "check"
                            size: 18
                            color: root.accent
                            opacity: sinkRow.current ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                        }
                        HoverHandler { id: sinkHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: sinkTap
                            onTapped: {
                                root.soundIndex = sinkRow.index;
                                root.selectSink(sinkRow.modelData);
                            }
                        }
                    }
                }

                Text {
                    visible: root.sinks.length === 0
                    width: parent.width
                    height: 44
                    leftPadding: 14
                    verticalAlignment: Text.AlignVCenter
                    text: strings.t("control.noOutput")
                    textFormat: Text.PlainText
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    color: root.metrics.textSecondary
                }
            }
        }

        Column {
            width: parent.width
            spacing: root.metrics.captionGap

            Caption { text: root.tr("control.input", "Entrada", "Input") }

            LabeledRow {
                variant: "bar"
                metrics: root.metrics
                strings: strings
                fontFamily: root.fontFamily
                fg: root.fg
                bg: root.bg
                accent: root.accent
                danger: root.danger
                icon: root.hasMic && !root.micMuted ? "mic" : "mic_off"
                label: root.hasMic ? (root.source.description || root.source.nickname || strings.t("control.microphone"))
                                   : strings.t("control.noMic")
                value: !root.hasMic ? ""
                       : root.micMuted ? strings.t("control.micMuted")
                       : strings.t("control.percent").arg(Math.round(root.micVolume * 100))
                sliderValue: Math.min(1, root.micVolume)
                stepBase: root.micVolume
                dimmed: !root.hasMic || root.micMuted
                onMoved: v => root.setMicVolume(v)
                onLabelTapped: root.toggleMic()
            }
        }
    }
}
