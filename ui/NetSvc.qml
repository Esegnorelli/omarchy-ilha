import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "Motion.js" as Motion

// Conectividade da Ilha: Wi-Fi e cabo (Quickshell.Networking, backend do
// NetworkManager) e Bluetooth (adaptador padrão do BlueZ). Segue as regras
// dos painéis de rede e de Bluetooth do Omarchy (shell/plugins/panels/
// network e bluetooth), portadas para um serviço só, dono do Ilha.qml.
//
// Dono: Agent D. A API pública é a congelada no Phase 0; o que vem marcado
// "(extra)" é acréscimo para os cartões e não muda nada do que já existia.
//
// WI-FI
// - wifiDevice / wiredDevice: o dispositivo de cada tipo (prefere o conectado).
// - wifiAvailable: há NetworkManager e um rádio Wi-Fi.
// - wifiEnabled: o rádio ligado. Depois de setWifiEnabled o valor pedido vale
//   na hora (otimista) até o NetworkManager confirmar ou 4 s passarem.
// - connected, ssid, signal (0..100), security ("WPA2", "WPA3", "WPA",
//   "WEP", "LEAP", "OWE"; "" para rede aberta ou desconhecida, ver
//   securityOpen), bars (0..4 do L1/L2).
// - wired, wiredIface (extra), wiredIp (IPv4 lido com `ip -j`).
// - networks: [{ssid, signal, secured, known, active, enterprise}], só
//   primitivos (nunca o objeto do Quickshell: o painel do Omarchy documenta
//   o segfault que isso causa). Ordem: a conectada, as conhecidas, depois
//   por barras (0..4) e nome. Ordenar pela barra, não pelo sinal cru, evita
//   que as linhas troquem de lugar a cada leitura do rádio.
// - scanning (gravável): o popover liga enquanto está aberto. Liga o
//   scanner do dispositivo com o adiamento de 100 ms do Omarchy (o primeiro
//   quadro não trava na enxurrada de APs) e solta ao fechar.
// - scanDone: a primeira varredura desta abertura terminou (1,5 s).
// - connectingSsid, lastError ("" | "wrong-password" | "failed"),
//   errorSsid (extra), busy / busySsid / busyKind (extra; "connect" |
//   "disconnect" | "forget"). Uma ação por vez, com limite de 30 s (mais que
//   os 25 s do supplicant, para a senha errada chegar a tempo).
// - setWifiEnabled(b), connect(net, psk), disconnect(), forget(net),
//   connectInTerminal(ssid) (extra: rede corporativa 802.1X, que pede
//   usuário; abre o nmtui no terminal do Omarchy depois de a ilha fechar).
//
// BLUETOOTH
// - btAvailable, btEnabled (otimista como o Wi-Fi, até 8 s), saved e nearby:
//   [{address, name, icon, connected, paired, battery (-1 sem), pending}];
//   icon é um literal de dev/icons.txt; pending é "" | "connecting" |
//   "pairing" | "disconnecting" | "forgetting".
// - saved = conectados e lembrados (pareados, ligados ou confiáveis), os
//   conectados primeiro; nearby = os descobertos com nome de gente, só
//   enquanto `discovering`.
// - discovering (gravável): o popover liga enquanto está aberto. A descoberta
//   do BlueZ é religada a cada 1 s se cair e, ao fechar, desligada por um
//   Timer preso ao estado confirmado (sem ele o rádio ficava em inquiry até
//   reiniciar o shell e o áudio A2DP engasgava).
// - setBtEnabled(b) via omarchy-bluetooth-power (bloqueio rfkill, que vale
//   depois do boot); connectDevice / disconnectDevice / pairDevice via
//   omarchy-bluetooth-device. Conectar um fone troca a saída de áudio para
//   ele (até 8 tentativas a cada 500 ms, como o painel do Omarchy).
QtObject {
    id: root

    // ---- Entradas ----
    property var shell: null

    // ======================================================================
    // Wi-Fi e cabo
    // ======================================================================

    readonly property bool nmAvailable: Networking.backend === NetworkBackendType.NetworkManager
    // Harness (ILHA_DEV=1): leitura real, ações só no log. Nunca liga, desliga
    // nem conecta nada de verdade, como o AudioSvc e o MonitorSvc.
    readonly property bool dry: Quickshell.env("ILHA_DEV") === "1"
    readonly property var netDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: root.findDevice(DeviceType.Wifi)
    readonly property var wiredDevice: root.findDevice(DeviceType.Wired)
    readonly property var wifiNetworkObjects: root.wifiDevice && root.wifiDevice.networks ? root.wifiDevice.networks.values : []
    readonly property var connectedNetwork: {
        const list = root.wifiNetworkObjects || [];
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].connected)
                return list[i];
        return null;
    }

    readonly property bool wifiAvailable: root.nmAvailable && !!root.wifiDevice
    readonly property bool wifiHardwareEnabled: Networking.wifiHardwareEnabled
    readonly property bool wifiEnabled: priv.wifiWant >= 0 ? priv.wifiWant === 1 : Networking.wifiEnabled
    // O NetworkManager pode deixar o perfil ativo fora da lista (rede OWE de
    // transição entre varreduras): aí vale o estado do próprio dispositivo.
    readonly property bool connected: root.wifiEnabled && (root.connectedNetwork !== null || (!!root.wifiDevice && root.wifiDevice.connected === true))
    // Conectando sozinho (autoconnect) ou por nós. (extra)
    readonly property bool wifiConnecting: root.wifiEnabled && !root.connected && !!root.wifiDevice && root.wifiDevice.state === ConnectionState.Connecting
    readonly property string ssid: root.connected && root.connectedNetwork ? String(root.connectedNetwork.name || "") : ""
    readonly property int signal: root.connected ? root.connectedSignal(root.connectedNetwork ? root.connectedNetwork.signalStrength : 0, priv.activeApSignal) : 0
    readonly property string security: root.connectedNetwork ? root.securityLabel(root.connectedNetwork.security) : ""
    // (extra) A rede conectada não pede senha (aberta ou OWE).
    readonly property bool securityOpen: !!root.connectedNetwork && !root.requiresCredentials(root.connectedNetwork.security)
    readonly property int bars: root.connected ? Math.max(1, Math.min(4, Math.ceil(root.signal / 25))) : 0

    readonly property bool wired: !!root.wiredDevice && root.wiredDevice.connected === true
    readonly property string wiredIface: root.wired ? String(root.wiredDevice.name || "") : ""
    readonly property string wiredIp: priv.wiredIp

    // Linhas da lista, ao vivo (a ligação relê sinal, conectado e conhecido
    // de cada rede). Redes ocultas (sem nome) ficam de fora.
    readonly property var networks: {
        const rows = [];
        const list = root.wifiEnabled ? (root.wifiNetworkObjects || []) : [];
        for (let i = 0; i < list.length; i++) {
            const n = list[i];
            if (!n)
                continue;
            const name = String(n.name || "");
            if (name === "")
                continue;
            const sec = n.security;
            rows.push({
                ssid: name,
                signal: Math.round((n.signalStrength || 0) * 100),
                secured: root.requiresCredentials(sec),
                known: !!n.known,
                active: !!n.connected,
                enterprise: sec === WifiSecurityType.Wpa2Eap || sec === WifiSecurityType.WpaEap
            });
        }
        rows.sort((a, b) => {
            if (a.active !== b.active)
                return a.active ? -1 : 1;
            if (a.known !== b.known)
                return a.known ? -1 : 1;
            const ba = root.barsFor(a.signal), bb = root.barsFor(b.signal);
            if (ba !== bb)
                return bb - ba;
            return a.ssid.localeCompare(b.ssid);
        });
        return rows;
    }

    property bool scanning: false
    readonly property bool scanDone: priv.scanDone

    readonly property string connectingSsid: priv.actionKind === "connect" ? priv.actionSsid : ""
    readonly property string lastError: priv.lastError
    readonly property string errorSsid: priv.errorSsid
    readonly property bool busy: priv.actionKind !== ""
    readonly property string busySsid: priv.actionSsid
    readonly property string busyKind: priv.actionKind

    // ---- Funções puras ----

    function findDevice(type) {
        const devices = root.netDevices || [];
        let fallback = null;
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i];
            if (!d || d.type !== type)
                continue;
            if (d.connected)
                return d;
            if (!fallback)
                fallback = d;
        }
        return fallback;
    }

    function networkForSsid(ssid) {
        const list = root.wifiNetworkObjects || [];
        for (let i = 0; i < list.length; i++)
            if (list[i] && String(list[i].name || "") === ssid)
                return list[i];
        return null;
    }

    // Força da rede conectada: a do grupo de APs do Quickshell; sem ela (OWE
    // de transição), a do AP em uso lida pelo nmcli (Model.js do Omarchy).
    function connectedSignal(networkStrength, activeApSignal) {
        const s = Math.round((networkStrength || 0) * 100);
        if (s > 0)
            return s;
        return activeApSignal > 0 ? activeApSignal : s;
    }

    function barsFor(signal) {
        return signal <= 0 ? 0 : Math.max(1, Math.min(4, Math.ceil(signal / 25)));
    }

    // Glifo de barras para um sinal 0..100 (linhas de rede, L1/L2).
    function signalIcon(signal) {
        const b = root.barsFor(signal);
        if (b >= 4)
            return "signal_wifi_4_bar";
        if (b === 3)
            return "network_wifi_3_bar";
        if (b === 2)
            return "network_wifi_2_bar";
        return "network_wifi_1_bar";
    }

    // Só os tipos sem credencial pulam a senha; desconhecido pede senha
    // (fallback conservador do Model.requiresCredentials do Omarchy).
    function requiresCredentials(sec) {
        return sec !== WifiSecurityType.Open && sec !== WifiSecurityType.Owe;
    }

    function securityLabel(sec) {
        switch (sec) {
        case WifiSecurityType.Sae:
        case WifiSecurityType.Wpa3SuiteB192:
            return "WPA3";
        case WifiSecurityType.Wpa2Psk:
        case WifiSecurityType.Wpa2Eap:
            return "WPA2";
        case WifiSecurityType.WpaPsk:
        case WifiSecurityType.WpaEap:
            return "WPA";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep:
            return "WEP";
        case WifiSecurityType.Leap:
            return "LEAP";
        case WifiSecurityType.Owe:
            return "OWE";
        default:
            return "";
        }
    }

    // ---- Ações de Wi-Fi ----

    function setWifiEnabled(on) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.setWifiEnabled ignorado");
            return;
        }
        if (!root.nmAvailable)
            return;
        const want = !!on;
        priv.wifiWant = want ? 1 : 0;
        wifiWantTimer.restart();
        Networking.wifiEnabled = want;
        if (Networking.wifiEnabled === want) {
            priv.wifiWant = -1;
            wifiWantTimer.stop();
        }
    }

    // net: uma linha de `networks` (ou o SSID). psk vazio = perfil salvo ou
    // rede aberta. A senha vai direto ao NetworkManager pelo D-Bus, nunca
    // por argv.
    function connect(net, psk) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.connect ignorado");
            return false;
        }
        const ssid = net && typeof net === "object" ? String(net.ssid || "") : String(net || "");
        if (ssid === "" || priv.actionKind !== "")
            return false;
        const n = root.networkForSsid(ssid);
        if (!n)
            return false;
        root.beginAction("connect", ssid);
        const secret = psk === undefined || psk === null ? "" : String(psk);
        if (secret !== "")
            n.connectWithPsk(secret);
        else
            n.connect();
        return true;
    }

    function disconnect() {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.disconnect ignorado");
            return false;
        }
        if (priv.actionKind !== "")
            return false;
        const n = root.connectedNetwork;
        if (n) {
            root.beginAction("disconnect", String(n.name || ""));
            n.disconnect();
            return true;
        }
        if (root.wifiDevice && root.wifiDevice.connected) {
            root.wifiDevice.disconnect();
            return true;
        }
        return false;
    }

    // Só uma rede conhecida e fora de uso pode ser esquecida.
    function forget(net) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.forget ignorado");
            return false;
        }
        const ssid = net && typeof net === "object" ? String(net.ssid || "") : String(net || "");
        if (ssid === "" || priv.actionKind !== "")
            return false;
        const n = root.networkForSsid(ssid);
        if (!n || !n.known || n.connected)
            return false;
        root.beginAction("forget", ssid);
        n.forget();
        return true;
    }

    // 802.1X pede usuário e senha: o nmtui do NetworkManager pergunta os
    // dois. Quem chama fecha a ilha antes; aqui só espera o fechamento.
    function connectInTerminal(ssid) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.connectInTerminal ignorado");
            return;
        }
        priv.terminalSsid = String(ssid || "");
        terminalTimer.restart();
    }

    function beginAction(kind, ssid) {
        priv.actionKind = kind;
        priv.actionSsid = ssid;
        priv.lastError = "";
        priv.errorSsid = "";
        actionTimeout.restart();
    }

    function finishAction() {
        actionTimeout.stop();
        priv.actionKind = "";
        priv.actionSsid = "";
    }

    function failAction(error) {
        const ssid = priv.actionSsid;
        root.finishAction();
        priv.errorSsid = ssid;
        priv.lastError = error;
    }

    // Fim da ação pelo estado da rede (chamado quando a lista muda e pelos
    // sinais da rede da ação).
    function checkAction() {
        if (priv.actionKind === "")
            return;
        const n = root.networkForSsid(priv.actionSsid);
        const kind = priv.actionKind;
        if (kind === "connect" && n && n.connected)
            root.finishAction();
        else if (kind === "disconnect" && (!n || (!n.connected && !n.stateChanging)))
            root.finishAction();
        else if (kind === "forget" && (!n || (!n.known && !n.stateChanging)))
            root.finishAction();
    }

    onNetworksChanged: root.checkAction()

    // ---- Varredura (só com o popover aberto) ----

    function setScanner(on) {
        const next = root.scanning ? root.wifiDevice : null;
        if (priv.scannerDevice && priv.scannerDevice !== next)
            priv.scannerDevice.scannerEnabled = false;
        priv.scannerDevice = next;
        if (priv.scannerDevice)
            priv.scannerDevice.scannerEnabled = !!on;
    }

    function applyScan() {
        if (root.scanning && root.wifiDevice && root.wifiEnabled) {
            priv.scanDone = false;
            root.setScanner(false);
            scanRestart.restart();
        } else {
            scanRestart.stop();
            scanDoneTimer.stop();
            root.setScanner(false);
            priv.scanDone = false;
        }
        if (!root.scanning) {
            // Fechou: o erro da última tentativa não volta na próxima abertura.
            priv.lastError = "";
            priv.errorSsid = "";
        } else {
            root.refreshIp();
        }
    }

    onScanningChanged: root.applyScan()
    onWifiDeviceChanged: {
        priv.activeApSignal = -1;
        if (root.scanning)
            root.applyScan();
    }
    onWifiEnabledChanged: {
        // Rádio desligado no meio de uma ação: não há mais o que esperar.
        if (!root.wifiEnabled && priv.actionKind !== "")
            root.finishAction();
        if (root.scanning)
            root.applyScan();
    }

    // ---- Endereço do cabo ----

    function refreshIp() {
        const iface = root.wiredIface;
        if (iface === "") {
            priv.wiredIp = "";
            return;
        }
        if (ipProc.running) {
            ipRetry.restart();
            return;
        }
        ipProc.forIface = iface;
        ipProc.command = ["ip", "-j", "-4", "addr", "show", "dev", iface];
        ipProc.running = true;
    }

    function finishIp(raw) {
        if (ipProc.forIface !== root.wiredIface)
            return;
        let addr = "";
        try {
            const data = JSON.parse(raw || "[]");
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
        priv.wiredIp = addr;
        // O DHCP pode ainda não ter respondido: tenta de novo algumas vezes.
        if (addr === "" && root.wired && priv.ipAttempts < 5) {
            priv.ipAttempts += 1;
            ipRetry.restart();
        }
    }

    onWiredIfaceChanged: {
        priv.wiredIp = "";
        priv.ipAttempts = 0;
        root.refreshIp();
    }

    // ======================================================================
    // Bluetooth
    // ======================================================================

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btAvailable: root.adapter !== null
    readonly property bool btPowered: !!root.adapter && root.adapter.enabled
    readonly property bool btEnabled: priv.btWant >= 0 ? priv.btWant === 1 : root.btPowered
    readonly property var btDeviceObjects: Bluetooth.devices ? Bluetooth.devices.values : []
    property bool discovering: false

    // Grupos com primitivos (Model.deviceLists do Omarchy): só aparelhos com
    // nome de gente (nada de UUID ou endereço no lugar do nome).
    readonly property var btGroups: {
        const out = { connected: [], known: [], discovered: [] };
        const list = root.btDeviceObjects || [];
        const pending = priv.pending;
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (!d || !root.hasHumanName(d))
                continue;
            const address = String(d.address || "");
            const row = {
                address: address,
                name: root.deviceLabel(d),
                icon: root.deviceIcon(d.icon),
                connected: !!d.connected,
                paired: !!(d.paired || d.bonded || d.trusted),
                battery: d.batteryAvailable ? Math.round((d.battery || 0) * 100) : -1,
                pending: Object.prototype.hasOwnProperty.call(pending, address) ? String(pending[address]) : ""
            };
            if (row.connected)
                out.connected.push(row);
            else if (row.paired)
                out.known.push(row);
            else
                out.discovered.push(row);
        }
        const byName = (a, b) => a.name.localeCompare(b.name);
        out.connected.sort(byName);
        out.known.sort(byName);
        out.discovered.sort(byName);
        return out;
    }

    readonly property var saved: root.btGroups.connected.concat(root.btGroups.known)
    readonly property var nearby: root.discovering ? root.btGroups.discovered : []
    readonly property int connectedCount: root.btGroups.connected.length
    readonly property string connectedName: root.btGroups.connected.length > 0 ? root.btGroups.connected[0].name : ""
    // (extra) endereço -> ação pendente.
    readonly property var btPending: priv.pending

    function deviceLabel(d) {
        return d ? String(d.deviceName || d.name || "").trim() : "";
    }

    function isUuidLike(value) {
        const text = String(value || "").trim();
        if (text === "")
            return false;
        return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
            || /^[0-9a-f]{32}$/i.test(text)
            || /^0x[0-9a-f]{4,32}$/i.test(text);
    }

    function isAddressLike(value) {
        return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(String(value || "").trim());
    }

    function hasHumanName(d) {
        const label = root.deviceLabel(d);
        return label !== "" && !root.isUuidLike(label) && !root.isAddressLike(label);
    }

    // Ícone freedesktop do BlueZ -> literal de dev/icons.txt.
    function deviceIcon(icon) {
        const s = String(icon || "");
        if (s.indexOf("headset") >= 0 || s.indexOf("headphone") >= 0)
            return "headphones";
        if (s === "audio-card" || s.indexOf("speaker") >= 0)
            return "speaker";
        if (s.indexOf("keyboard") >= 0)
            return "keyboard";
        if (s.indexOf("mouse") >= 0)
            return "mouse";
        if (s.indexOf("phone") >= 0)
            return "mobile";
        if (s === "computer" || s.indexOf("display") >= 0)
            return "desktop_windows";
        return "bluetooth";
    }

    function deviceFor(address) {
        const list = root.btDeviceObjects || [];
        for (let i = 0; i < list.length; i++)
            if (list[i] && String(list[i].address || "") === address)
                return list[i];
        return null;
    }

    // ---- Ações de Bluetooth ----

    // Pede uma direção, nunca "toggle": o helper roda solto e o interruptor
    // só anda quando o BlueZ alcança; um segundo clique leria o estado velho.
    function setBtEnabled(on) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.setBtEnabled ignorado");
            return;
        }
        const want = !!on;
        priv.btWant = want === root.btPowered ? -1 : (want ? 1 : 0);
        if (priv.btWant >= 0)
            btWantTimer.restart();
        Quickshell.execDetached(["omarchy-bluetooth-power", want ? "on" : "off"]);
    }

    function setPending(address, action) {
        const next = Object.assign({}, priv.pending);
        if (action)
            next[address] = action;
        else
            delete next[address];
        priv.pending = next;
        if (action)
            pendingTimeout.restart();
    }

    function connectDevice(address) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.connectDevice ignorado");
            return;
        }
        const d = root.deviceFor(String(address || ""));
        if (!d || d.connected)
            return;
        const paired = !!(d.paired || d.bonded || d.trusted);
        root.setPending(String(d.address), paired ? "connecting" : "pairing");
        Quickshell.execDetached(["omarchy-bluetooth-device", paired ? "connect" : "pair", String(d.address)]);
    }

    function disconnectDevice(address) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.disconnectDevice ignorado");
            return;
        }
        const d = root.deviceFor(String(address || ""));
        if (!d || !d.connected)
            return;
        root.setPending(String(d.address), "disconnecting");
        d.disconnect();
        Quickshell.execDetached(["omarchy-bluetooth-device", "disconnect", String(d.address)]);
    }

    function pairDevice(address) {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.pairDevice ignorado");
            return;
        }
        const d = root.deviceFor(String(address || ""));
        if (!d || d.connected)
            return;
        root.setPending(String(d.address), "pairing");
        Quickshell.execDetached(["omarchy-bluetooth-device", "pair", String(d.address)]);
    }

    // Fecha as ações pendentes que o BlueZ já concluiu.
    function syncPending() {
        const next = Object.assign({}, priv.pending);
        let changed = false;
        for (const address in next) {
            const action = next[address];
            const d = root.deviceFor(address);
            const paired = !!d && !!(d.paired || d.bonded || d.trusted);
            const doneConnecting = (action === "connecting" || action === "pairing") && !!d && d.connected;
            if (doneConnecting
                    || (action === "disconnecting" && (!d || !d.connected))
                    || (action === "forgetting" && (!d || !paired))) {
                if (doneConnecting)
                    root.scheduleAudioSwitch(d);
                delete next[address];
                changed = true;
            }
        }
        if (changed)
            priv.pending = next;
    }

    onBtGroupsChanged: root.syncPending()

    // ---- Saída de áudio do fone recém-conectado (Panel.qml do Omarchy) ----

    function nodeText(node) {
        const props = node && node.ready && node.properties ? node.properties : {};
        return [
            node ? node.name : "", node ? node.description : "", node ? node.nickname : "",
            props["node.name"], props["node.description"], props["node.nick"],
            props["device.name"], props["device.description"], props["device.product.name"],
            props["device.alias"], props["device.string"], props["api.bluez5.address"],
            props["bluez5.address"], props["media.name"]
        ].join(" ").toLowerCase();
    }

    function normalizedAddress(value) {
        return String(value || "").trim().toLowerCase().replace(/[^0-9a-f]/g, "");
    }

    function sinkMatches(node, dev) {
        if (!node || !node.isSink || node.isStream || !dev)
            return false;
        const text = root.nodeText(node);
        const address = root.normalizedAddress(dev.address);
        if (address !== "" && root.normalizedAddress(text).indexOf(address) !== -1)
            return true;
        const label = String(dev.label || "").toLowerCase();
        return label !== "" && text.indexOf(label) !== -1;
    }

    function scheduleAudioSwitch(d) {
        priv.audioDevice = { address: String(d.address || ""), label: root.deviceLabel(d) };
        priv.audioAttempts = 0;
        audioTimer.restart();
    }

    function switchAudio() {
        if (root.dry) {
            console.log("ilha: harness, NetSvc.switchAudio ignorado");
            return;
        }
        const dev = priv.audioDevice;
        if (!dev)
            return;
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            if (root.sinkMatches(node, dev)) {
                Pipewire.preferredDefaultAudioSink = node;
                if (node.id !== undefined && node.name)
                    Quickshell.execDetached(["omarchy-audio-output-set-default", String(node.id), String(node.name)]);
                priv.audioDevice = null;
                return;
            }
        }
        priv.audioAttempts += 1;
        if (priv.audioAttempts >= 8) {
            priv.audioDevice = null;
            return;
        }
        audioTimer.restart();
    }

    onDiscoveringChanged: {
        // Assume uma descoberta que já corria: o fechamento acerta as contas.
        if (root.discovering && root.adapter && root.adapter.discovering)
            priv.owesStop = true;
    }

    Component.onDestruction: {
        if (priv.scannerDevice)
            priv.scannerDevice.scannerEnabled = false;
        if (priv.owesStop && root.adapter && root.adapter.discovering)
            root.adapter.discovering = false;
    }

    // ======================================================================
    // Estado interno e temporizadores
    // ======================================================================

    property QtObject _priv: QtObject {
        id: priv
        // Wi-Fi
        property int wifiWant: -1          // -1 nada pedido; 0 desligar; 1 ligar
        property QtObject scannerDevice: null
        property bool scanDone: false
        property int activeApSignal: -1
        property string actionKind: ""
        property string actionSsid: ""
        property string lastError: ""
        property string errorSsid: ""
        property string wiredIp: ""
        property int ipAttempts: 0
        property string terminalSsid: ""
        // Bluetooth
        property int btWant: -1
        property bool owesStop: false
        property var pending: ({})
        property var audioDevice: null
        property int audioAttempts: 0
    }

    // O pedido otimista acaba quando o host confirma (ou no limite).
    property Connections _networkingWatch: Connections {
        target: Networking
        function onWifiEnabledChanged() {
            if (priv.wifiWant >= 0 && (priv.wifiWant === 1) === Networking.wifiEnabled) {
                priv.wifiWant = -1;
                wifiWantTimer.stop();
            }
        }
    }

    property Timer _wifiWantTimer: Timer {
        id: wifiWantTimer
        interval: 4000
        onTriggered: priv.wifiWant = -1
    }

    onBtPoweredChanged: {
        if (priv.btWant >= 0 && (priv.btWant === 1) === root.btPowered) {
            priv.btWant = -1;
            btWantTimer.stop();
        }
    }

    property Timer _btWantTimer: Timer {
        id: btWantTimer
        // omarchy-bluetooth-power espera até 2 s, mais 5 s do bluetoothctl.
        interval: 8000
        onTriggered: priv.btWant = -1
    }

    // Falha de conexão da rede da ação (o autoconnect do fundo também dispara
    // isto; só conta a conexão que nós pedimos).
    readonly property QtObject actionNetwork: priv.actionKind !== "" ? root.networkForSsid(priv.actionSsid) : null

    property Connections _actionWatch: Connections {
        target: root.actionNetwork
        ignoreUnknownSignals: true
        function onConnectionFailed(reason) {
            if (priv.actionKind !== "connect")
                return;
            const n = root.actionNetwork;
            const needs = !!n && root.requiresCredentials(n.security);
            const wrong = needs && (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout);
            root.failAction(wrong ? "wrong-password" : "failed");
        }
        function onStateChangingChanged() {
            root.checkAction();
        }
        function onConnectedChanged() {
            root.checkAction();
        }
        function onKnownChanged() {
            root.checkAction();
        }
    }

    property Timer _actionTimeout: Timer {
        id: actionTimeout
        // Mais que os 25 s do supplicant: a senha salva errada falha com
        // WifiAuthTimeout perto disso e precisa chegar com a ação ainda viva.
        interval: 30000
        onTriggered: {
            if (priv.actionKind === "connect")
                root.failAction("failed");
            else
                root.finishAction();
        }
    }

    property Timer _scanRestart: Timer {
        id: scanRestart
        interval: 100
        onTriggered: {
            if (root.scanning && root.wifiDevice && root.wifiEnabled) {
                root.setScanner(true);
                scanDoneTimer.restart();
            }
        }
    }

    property Timer _scanDoneTimer: Timer {
        id: scanDoneTimer
        interval: 1500
        onTriggered: priv.scanDone = true
    }

    // Força do AP em uso pelo nmcli, só enquanto a rede conectada não tem a
    // sua (OWE de transição), sem disparar varredura.
    readonly property bool needsActiveApSignal: root.connected && !(root.connectedNetwork && root.connectedNetwork.signalStrength > 0)

    property Process _apSignalProc: Process {
        id: apSignalProc
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "ifname",
            root.wifiDevice ? String(root.wifiDevice.name || "") : "", "--rescan", "no"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                let value = -1;
                const lines = String(text || "").split(/\r?\n/);
                for (let i = 0; i < lines.length; i++) {
                    const m = /^\*:(\d+)$/.exec(lines[i].trim());
                    if (m) {
                        value = parseInt(m[1], 10);
                        break;
                    }
                }
                priv.activeApSignal = root.needsActiveApSignal ? value : -1;
            }
        }
    }

    property Timer _apSignalPoll: Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.needsActiveApSignal
        onTriggered: if (!apSignalProc.running) apSignalProc.running = true
        onRunningChanged: if (!running) priv.activeApSignal = -1
    }

    property Process _ipProc: Process {
        id: ipProc
        property string forIface: ""
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.finishIp(text)
        }
    }

    property Timer _ipRetry: Timer {
        id: ipRetry
        interval: 2000
        onTriggered: root.refreshIp()
    }

    property Timer _terminalTimer: Timer {
        id: terminalTimer
        interval: Motion.TIMING.CLOSE_THEN_RUN_MS
        onTriggered: {
            if (priv.terminalSsid === "")
                return;
            Quickshell.execDetached(["omarchy-launch-tui", "--app-id=org.omarchy.nmtui", "nmtui", "connect", priv.terminalSsid]);
            priv.terminalSsid = "";
        }
    }

    // ---- Descoberta do Bluetooth ----

    // O BlueZ recusa StartDiscovery enquanto o adaptador sobe, e a descoberta
    // também expira sozinha: com o popover aberto, religa a cada 1 s.
    property Timer _discoveryRetry: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.discovering && root.adapter !== null && root.adapter.enabled && !root.adapter.discovering
        onTriggered: {
            priv.owesStop = true;
            root.adapter.discovering = true;
        }
    }

    // A volta: presa ao estado confirmado, não a uma escrita no fechamento.
    // O Quickshell só repassa uma escrita diferente do último estado que o
    // BlueZ informou; um stop durante um start ainda sem confirmação seria
    // engolido e a sessão vazaria. Tentativas limitadas: uma sessão de outro
    // cliente do BlueZ não leva StopDiscovery para sempre.
    property Timer _discoveryStop: Timer {
        id: discoveryStop
        property int attempts: 0
        interval: 1000
        repeat: true
        running: !root.discovering && priv.owesStop && root.adapter !== null && root.adapter.discovering === true
        onRunningChanged: if (running) attempts = 0
        onTriggered: {
            attempts += 1;
            if (attempts > 3) {
                priv.owesStop = false;
                return;
            }
            root.adapter.discovering = false;
        }
    }

    property Connections _adapterWatch: Connections {
        target: root.adapter
        function onDiscoveringChanged() {
            if (root.adapter && !root.adapter.discovering)
                priv.owesStop = false;
        }
    }

    property Timer _pendingTimeout: Timer {
        id: pendingTimeout
        interval: 20000
        onTriggered: priv.pending = ({})
    }

    property Timer _audioTimer: Timer {
        id: audioTimer
        interval: 500
        onTriggered: root.switchAudio()
    }
}
