pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons as Commons
import "Motion.js" as Motion

// Ilha 2.0: plugin de barra (kind "bar") que troca a barra do Omarchy por uma
// ilha flutuante por monitor. Em repouso é uma pílula com a hora (e a marca
// do indicador mais importante); no hover cresce para a linha dos
// workspaces (L1) e, num clique, para a linha completa (L2); um atalho, o
// seletor ou o IPC abre uma tela no lugar da pílula (Central, Apps,
// Energia, Temas, Papéis, Mídia). OSDs e avisos ao vivo também moram nela.
//
// Dono: Agent A. Aqui ficam o contrato com o host, o estado de navegação, os
// serviços (um de cada), as preferências, o seletor, o aviso, o IPC, o
// registro de faces e o aviso de reinício. As choreografias são da
// IslandWindow; o conteúdo das telas, da ScreenStack.
//
// Exclusividade (amendments §1): abrir uma tela fecha o seletor, encerra o
// aviso e limpa o L2; abrir o seletor limpa o L2 e encerra o aviso (nunca com
// tela aberta); o L2 fecha o seletor e encerra o aviso.
//
// Contrato com o host (shell.qml do Omarchy):
// - Injetado depois de criar (ligar de forma reativa; `shell` é nulo no
//   harness): omarchyPath, shell, manifest, barWidgetRegistry,
//   pluginRegistry, barConfig. Para plugin de terceiros, `shell` é o
//   PluginShellApi e barConfig é uma cópia (reatribuída a cada mudança).
// - Publicado: barHidden, barSize (48), screenBarSizes, barSizeFor(name),
//   fontFamily (Commons.Style.fontFamily; a Inter é interna), position "top".
// - Funções do host: summonBarWidget, hideBarWidget, isBarWidgetOpen,
//   panelWidgetIdAt, cycleBackground, debugBarGeometry (objeto).
//
// ILHA_DEV=1 (harness): zona exclusiva 0, takeovers desligados, só a
// primeira tela, janelas escondidas até `ilha-dev reveal 1` (dev/harness.sh
// shot) e ILHA_DEV_TOP desloca a ilha para baixo (não briga com a barra real).
Item {
    id: island

    // ---- Injetado pelo host ----
    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var barWidgetRegistry: null
    property var pluginRegistry: null
    property var barConfig: null

    // ---- Versão ----
    readonly property string codeVersion: "2.3.0"
    readonly property string manifestVersion: island.manifest && island.manifest.version ? String(island.manifest.version) : ""

    // Referência à raiz para objetos que têm uma propriedade `island` própria
    // (em `island: island` o nome resolveria para a do próprio objeto).
    readonly property Item ilhaRoot: island

    // ---- Harness ----
    readonly property bool dev: Quickshell.env("ILHA_DEV") === "1"
    readonly property int devTop: island.dev ? (Number(Quickshell.env("ILHA_DEV_TOP")) || 0) : 0
    property bool devShown: !island.dev

    // ---- Publicado para o host ----
    property bool barHidden: false
    readonly property int barSize: 48
    readonly property var screenBarSizes: {
        const sizes = ({});
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            sizes[screens[i].name] = island.barHidden ? 0 : island.barSize;
        return sizes;
    }
    readonly property string fontFamily: Commons.Style.fontFamily
    readonly property string position: "top"

    function barSizeFor(name) {
        const size = island.screenBarSizes[String(name || "")];
        return size !== undefined ? size : (island.barHidden ? 0 : island.barSize);
    }

    // ---- Navegação ----
    // Tela aberta: "" | control | launcher | power | themes | wallpapers | media
    property string screen: ""
    // Subpágina / popover da Central: "" | sound | display | wifi | bluetooth | ilha
    property string screenSub: ""
    property string screenOutput: ""
    property var screenPayload: ({})
    property bool keyboardMode: false
    property string lastScreen: "control"
    // Telas por onde se passou desde a abertura ({id, payload}), a mais
    // recente no fim. Voltar desempilha; fechar limpa.
    property var screenHistory: []
    readonly property bool canGoBack: island.screenHistory.length > 0
    // Monitor com o L2 aberto ("" = nenhum) e a linha fixada (amendments §5.1).
    property string expandedOutput: ""
    property string expandedPin: ""
    // Seletor de telas: monitor onde está aberto ("" = fechado).
    property string pickerOutput: ""
    // Dica da linha: uma vez por sessão (nunca gravada).
    property bool lineHintSeen: false
    // Face de cada janela (reportFace): {output: face}.
    readonly property var faces: priv.faces
    // Hover forçado pelo IPC `ilha hover 1` (testes): monitor e nível.
    property string hoverOutput: ""

    readonly property var screenIds: ["control", "launcher", "power", "themes", "media"]
    readonly property var subIds: ["sound", "display", "wifi", "bluetooth", "ilha"]
    readonly property var aliases: ({ apps: "launcher", theme: "themes", look: "themes", cc: "control", controls: "control" })
    // Papel de parede: a tela de temas, já na fileira de baixo.
    readonly property var wallpaperAliases: ["wallpapers", "wallpaper", "background", "backgrounds"]

    // ---- Objetos compartilhados ----
    property Theme theme: Theme {
        glassy: island.glassy
    }
    Commons.Translations {
        id: translations
        directory: Qt.resolvedUrl("../i18n")
    }
    readonly property var strings: translations
    readonly property bool rtl: Commons.I18n.rightToLeft
    // Hora alinhada ao minuto.
    readonly property var now: clock.date
    // 12 h quando o formato do omarchy.clock no barConfig tem AP.
    readonly property bool clock12: island.clockFormatIs12h(island.barConfig)
    // Arquivo do toggle bar-glassy ou window-glassy presente.
    readonly property bool glassy: priv.barGlassy || priv.windowGlassy

    // Telas: URLs (Loader.setSource com propriedades iniciais) e componentes
    // pré-compilados na partida (Qt.createComponent assíncrono).
    readonly property var screenUrls: ({
        control: Qt.resolvedUrl("ControlCenter.qml"),
        launcher: Qt.resolvedUrl("LauncherScreen.qml"),
        power: Qt.resolvedUrl("PowerScreen.qml"),
        // Tema e papel de parede numa tela só.
        themes: Qt.resolvedUrl("LookScreen.qml"),
        media: Qt.resolvedUrl("MediaScreen.qml")
    })
    property var components: ({})

    // ---- Serviços (um de cada, donos aqui) ----
    property StateStore store: StateStore {}
    property MediaSvc media: MediaSvc {
        shell: island.shell
        // Um estado só para todas as janelas: abrir Mídia noutro monitor não
        // congela a posição, e um monitor desligado não deixa o timer ligado.
        positionPolling: island.screen === "media"
    }
    property StatusSvc status: StatusSvc {
        shell: island.shell
        strings: island.strings
        media: island.media
        store: island.store
    }
    property AudioSvc audio: AudioSvc {
        shell: island.shell
    }
    property MonitorSvc monitors: MonitorSvc {
        shell: island.shell
    }
    property NetSvc net: NetSvc {
        shell: island.shell
    }
    property AppsSvc apps: AppsSvc {
        omarchyPath: island.omarchyPath
        strings: island.strings
    }
    property ThemesSvc themes: ThemesSvc {
        omarchyPath: island.omarchyPath
    }
    property OsdBridge osd: OsdBridge {
        island: ilhaRoot
        shell: island.shell
        takeover: !island.dev
    }
    property PickerBridge pickers: PickerBridge {
        island: ilhaRoot
        shell: island.shell
        takeoverBackgrounds: !island.dev
        takeoverThemes: !island.dev
    }
    property PrefsSvc prefs: PrefsSvc {
        shell: island.shell
        barConfig: island.barConfig
    }
    property PeekBridge peek: PeekBridge {
        island: ilhaRoot
        status: island.status
        prefs: island.prefs
    }

    Connections {
        target: island.status
        function onActivated(key) {
            island.peek.raise(key, null);
        }
        function onUrgentArrived(row) {
            island.peek.raise("urgent", row);
        }
    }

    // ---- Funções de navegação ----

    function focusedOutput() {
        const screens = Quickshell.screens;
        if (island.dev)
            return screens.length > 0 ? String(screens[0].name) : "";
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            return String(Hyprland.focusedMonitor.name);
        return screens.length > 0 ? String(screens[0].name) : "";
    }

    function screenFor(output) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (String(screens[i].name) === String(output))
                return screens[i];
        }
        return screens.length > 0 ? screens[0] : null;
    }

    // Tamanho lógico de um monitor: {w, h}.
    function screenGeometry(output) {
        const s = island.screenFor(output);
        return s ? { w: s.width, h: s.height, screenW: s.width, screenH: s.height } : { w: 1920, h: 1080, screenW: 1920, screenH: 1080 };
    }

    function fullscreenOn(output) {
        const s = island.screenFor(output);
        const m = s ? Hyprland.monitorFor(s) : null;
        return !!(m && m.activeWorkspace && m.activeWorkspace.hasFullscreen);
    }

    // "sound" -> {id: "control", payload: {sub: "sound"}}; "last" -> a última; null se desconhecido.
    function resolveScreen(alias) {
        let t = String(alias || "").trim().toLowerCase();
        if (t === "last")
            t = island.lastScreen;
        if (island.aliases[t] !== undefined)
            t = island.aliases[t];
        if (t === "settings")
            return { id: "control", payload: { sub: "ilha" } };
        if (island.wallpaperAliases.indexOf(t) !== -1)
            return { id: "themes", payload: { row: "walls" } };
        if (island.subIds.indexOf(t) !== -1)
            return { id: "control", payload: { sub: t } };
        if (island.screenIds.indexOf(t) !== -1)
            return { id: t, payload: ({}) };
        return null;
    }

    function open(id, output, payload) {
        const r = island.resolveScreen(id);
        if (!r)
            return false;
        const p = Object.assign({}, r.payload, payload || ({}));
        // Troca entre telas diferentes: guarda a de agora para o Voltar.
        if (!priv.goingBack && island.screen !== "" && island.screen !== r.id) {
            const h = island.screenHistory.slice(-9);
            h.push({ id: island.screen, payload: island.screenPayload });
            island.screenHistory = h;
        }
        island.closePicker();
        island.peek.end();
        island.expandedOutput = "";
        island.expandedPin = "";
        island.hoverOutput = "";
        const out = output && String(output) !== "" ? String(output) : island.focusedOutput();
        // Outro monitor com uma tela aberta: fecha antes, senão o monitor novo
        // mostra por um instante a tela velha (opened/closed espúrios).
        if (island.screen !== "" && island.screenOutput !== out)
            island.screen = "";
        island.screenOutput = out;
        island.screenPayload = p;
        island.screenSub = p.sub ? String(p.sub) : "";
        island.screen = r.id;
        island.lastScreen = r.id;
        return true;
    }

    function toggle(id, output) {
        const r = island.resolveScreen(id);
        if (!r)
            return false;
        const sub = r.payload.sub ? String(r.payload.sub) : "";
        if (island.screen === r.id && island.screenSub === sub) {
            island.close();
            return true;
        }
        return island.open(id, output);
    }

    // Voltar (navegação, Alt+←, botão "voltar" do mouse): a tela anterior
    // com o payload dela; sem histórico, fecha.
    function back() {
        if (island.screen === "")
            return false;
        const h = island.screenHistory.slice();
        const prev = h.pop();
        if (!prev) {
            island.close();
            return true;
        }
        island.screenHistory = h;
        priv.goingBack = true;
        island.open(prev.id, island.screenOutput, prev.payload);
        priv.goingBack = false;
        return true;
    }

    // O Voltar da janela da tela (a subpágina da Central fecha antes).
    function navBack() {
        const win = priv.windows[island.screenOutput];
        if (win && typeof win.navBack === "function")
            return win.navBack();
        return island.back();
    }

    function close() {
        island.screenHistory = [];
        island.screen = "";
        island.screenSub = "";
        island.screenPayload = ({});
        island.closePicker();
    }

    // Ctrl+Tab (+1) / Ctrl+Shift+Tab (−1) e a roda: SCREEN_ORDER, Mídia pula sem player.
    function cycle(step) {
        const order = island.theme.px.SCREEN_ORDER;
        const n = order.length;
        const at = order.indexOf(island.screen !== "" ? island.screen : island.lastScreen);
        let next = at < 0 ? 0 : at;
        for (let tries = 0; tries < n; tries++) {
            next = ((next + step) % n + n) % n;
            if (order[next] !== "media" || island.media.players.length > 0)
                break;
        }
        island.open(order[next], island.screenOutput !== "" ? island.screenOutput : island.focusedOutput());
    }

    // L2 ligado/desligado num monitor; pin fixa uma linha de estado (amendments §5.1).
    function setExpanded(output, on, pin) {
        const out = output && String(output) !== "" ? String(output) : island.focusedOutput();
        if (on) {
            // Com uma tela aberta o L2 ficaria guardado e invisível, e surgiria
            // sozinho depois do Esc: o atalho do relógio fecha a tela primeiro.
            if (island.screen !== "")
                island.close();
            island.closePicker();
            island.peek.end();
            island.expandedOutput = out;
            island.expandedPin = pin ? String(pin) : "";
        } else if (island.expandedOutput === out) {
            island.expandedOutput = "";
            island.expandedPin = "";
        }
        return true;
    }

    // ---- Seletor de telas (amendments §6.1) ----
    function openPicker(output) {
        const out = output && String(output) !== "" ? String(output) : island.focusedOutput();
        if (island.screen !== "" || island.barHidden)
            return false;
        const win = priv.windows[out];
        if (win && win.drawsPill === false)
            return false;
        island.expandedOutput = "";
        island.expandedPin = "";
        island.peek.end();
        island.keyboardMode = false;
        island.pickerOutput = out;
        return true;
    }

    function closePicker() {
        island.pickerOutput = "";
    }

    // O mesmo monitor fecha; outro monitor leva o seletor.
    function togglePicker(output) {
        const out = output && String(output) !== "" ? String(output) : island.focusedOutput();
        if (island.pickerOutput === out) {
            island.closePicker();
            return true;
        }
        return island.openPicker(out);
    }

    // ---- Faces ----
    function reportFace(output, face) {
        const key = String(output || "");
        if (priv.faces[key] === face)
            return;
        const next = Object.assign({}, priv.faces);
        next[key] = String(face || "");
        priv.faces = next;
    }

    function faceOf(output) {
        return priv.faces[String(output || "")] || "rest";
    }

    function registerWindow(output, win) {
        const next = Object.assign({}, priv.windows);
        next[String(output)] = win;
        priv.windows = next;
    }

    // O monitor saiu: o que estava nele fecha (tela, L2, seletor, hover forçado).
    function unregisterWindow(output, win) {
        const out = String(output);
        if (priv.windows[out] !== win)
            return;
        const next = Object.assign({}, priv.windows);
        delete next[out];
        priv.windows = next;
        const f = Object.assign({}, priv.faces);
        delete f[out];
        priv.faces = f;
        if (island.screenOutput === out && island.screen !== "")
            island.close();
        if (island.expandedOutput === out) {
            island.expandedOutput = "";
            island.expandedPin = "";
        }
        if (island.pickerOutput === out)
            island.closePicker();
        if (island.hoverOutput === out)
            island.hoverOutput = "";
    }

    // ---- Roda (amendments §8.2): porte do Strip.wheelPanels da 1.x ----
    function wheelStep(delta) {
        const now = Date.now();
        const d = Number(delta) || 0;
        if (d === 0)
            return;
        if (now - priv.wheelAt > Motion.TIMING.WHEEL_DECAY_MS || (priv.wheelAcc !== 0 && Math.sign(priv.wheelAcc) !== Math.sign(d)))
            priv.wheelAcc = 0;
        priv.wheelAt = now;
        priv.wheelAcc += d;
        if (priv.wheelAcc <= -Motion.TIMING.WHEEL_STEP) {
            priv.wheelAcc = 0;
            island.cycle(1);
        } else if (priv.wheelAcc >= Motion.TIMING.WHEEL_STEP) {
            priv.wheelAcc = 0;
            island.cycle(-1);
        }
    }

    // ---- Teclas sintéticas (ilha run <tela> <tecla>) ----
    // "Q", "shift+Q", "⇧Q", "enter", "pgdn"… -> evento para handleKey.
    function parseKey(name) {
        let raw = String(name || "").trim();
        let mods = 0;
        const parts = raw.split("+");
        if (parts.length > 1 && parts[parts.length - 1] !== "") {
            raw = parts.pop();
            for (const m of parts) {
                const lower = m.toLowerCase();
                if (lower === "shift")
                    mods |= Qt.ShiftModifier;
                else if (lower === "ctrl" || lower === "control")
                    mods |= Qt.ControlModifier;
                else if (lower === "alt")
                    mods |= Qt.AltModifier;
                else
                    return null;
            }
        }
        if (raw.indexOf("⇧") === 0) {
            mods |= Qt.ShiftModifier;
            raw = raw.slice(1);
        }
        const named = {
            "enter": Qt.Key_Return, "return": Qt.Key_Return, "space": Qt.Key_Space,
            "esc": Qt.Key_Escape, "escape": Qt.Key_Escape, "tab": Qt.Key_Tab,
            "up": Qt.Key_Up, "down": Qt.Key_Down, "left": Qt.Key_Left, "right": Qt.Key_Right,
            "pgup": Qt.Key_PageUp, "pageup": Qt.Key_PageUp, "pgdn": Qt.Key_PageDown,
            "pagedown": Qt.Key_PageDown, "home": Qt.Key_Home, "end": Qt.Key_End,
            "delete": Qt.Key_Delete, "del": Qt.Key_Delete
        };
        let key = named[raw.toLowerCase()];
        let text = raw.toLowerCase() === "space" ? " " : "";
        if (key === undefined) {
            if (raw.length !== 1)
                return null;
            const code = raw.toUpperCase().charCodeAt(0);
            if (code < 0x20 || code > 0x7e)
                return null;
            key = code;
            text = (mods & Qt.ShiftModifier) ? raw.toUpperCase() : raw.toLowerCase();
        }
        return { key: key, modifiers: mods, text: text, isAutoRepeat: false, accepted: false, synthetic: true };
    }

    // Abre no modo teclado e manda a tecla quando a tela estiver pronta (3 s).
    function runKey(target, keyName) {
        const r = island.resolveScreen(target);
        if (!r)
            return "unknown";
        const event = island.parseKey(keyName);
        if (!event)
            return "invalid-key";
        island.keyboardMode = true;
        if (island.screen !== r.id)
            island.open(target, "");
        priv.pendingRun = { id: r.id, event: event, at: Date.now() };
        return "ok";
    }

    // A janela ativa pega a tecla pendente quando a tela está pronta.
    function takePendingRun(id) {
        const p = priv.pendingRun;
        if (!p)
            return null;
        if (Date.now() - p.at > Motion.TIMING.RUN_TIMEOUT_MS) {
            priv.pendingRun = null;
            return null;
        }
        if (p.id !== id)
            return null;
        priv.pendingRun = null;
        return p.event;
    }
    readonly property bool runPending: priv.pendingRun !== null

    // ---- Contrato de painéis do host ----
    readonly property var widgetScreens: ({
        "omarchy.audio": { id: "control", sub: "sound" },
        "omarchy.bluetooth": { id: "control", sub: "bluetooth" },
        "omarchy.network": { id: "control", sub: "wifi" },
        "omarchy.monitor": { id: "control", sub: "display" },
        "omarchy.power": { id: "power", sub: "" },
        "omarchy.media": { id: "media", sub: "" },
        "omarchy.elsewhen": { id: "control", sub: "" }
    })

    function summonBarWidget(pluginId) {
        const id = String(pluginId || "");
        if (id === "omarchy.clock") {
            island.keyboardMode = true;
            return island.setExpanded(island.focusedOutput(), true);
        }
        const t = island.widgetScreens[id];
        if (!t) {
            console.log("ilha: no island screen for " + id);
            return false;
        }
        island.keyboardMode = true;
        return island.open(t.id, island.focusedOutput(), t.sub !== "" ? { sub: t.sub, keyboard: true } : { keyboard: true }) === true;
    }

    function hideBarWidget(pluginId) {
        const id = String(pluginId || "");
        if (id === "omarchy.clock")
            return island.setExpanded(island.focusedOutput(), false);
        const t = island.widgetScreens[id];
        if (!t)
            return false;
        if (island.isBarWidgetOpen(id))
            island.close();
        return true;
    }

    function isBarWidgetOpen(pluginId) {
        const id = String(pluginId || "");
        if (id === "omarchy.clock")
            return island.expandedOutput !== "" && island.expandedOutput === island.focusedOutput();
        const t = island.widgetScreens[id];
        return !!t && island.screen === t.id && island.screenSub === t.sub;
    }

    // Super+Ctrl+1..4: a N-ésima entrada de cada seção, contando de 1.
    function panelWidgetIdAt(section, index) {
        const sections = {
            "center": ["omarchy.clock"],
            "right": ["omarchy.audio", "omarchy.network", "omarchy.power", "omarchy.media"]
        };
        const list = sections[String(section || "")] || [];
        const item = list[Math.round(Number(index)) - 1];
        return item ? item : "";
    }

    function cycleBackground() {
        console.log("ilha: cycleBackground is unsupported");
        return false;
    }

    function debugBarGeometry() {
        const wins = {};
        for (const out in priv.windows) {
            const w = priv.windows[out];
            if (w && w.debugState)
                wins[out] = w.debugState();
        }
        return {
            id: "esegnorelli.ilha",
            version: island.manifestVersion,
            codeVersion: island.codeVersion,
            dev: island.dev,
            barHidden: island.barHidden,
            barSize: island.barSize,
            screenBarSizes: island.screenBarSizes,
            screen: island.screen,
            sub: island.screenSub,
            history: island.screenHistory.map(e => e.id),
            output: island.screenOutput,
            faces: island.faces,
            expanded: island.expandedOutput,
            expandedPin: island.expandedPin,
            osd: { showing: island.osd.showing, output: island.osd.output, lastShownAt: island.osd.lastShownAt },
            keyboardMode: island.keyboardMode,
            takeovers: { osd: island.osd.takeover, backgrounds: island.pickers.takeoverBackgrounds, themes: island.pickers.takeoverThemes },
            prefs: { focusedOnly: island.prefs.focusedOnly, livePeek: island.prefs.livePeek, reserveTop: island.prefs.reserveTop, canPersist: island.prefs.canPersist },
            peek: { showing: island.peek.showing, key: island.peek.key, output: island.peek.output, pending: island.peek.pending },
            picker: island.pickerOutput,
            lineHintSeen: island.lineHintSeen,
            restartNotice: { showing: island.restartNoticeShowing },
            windows: wins
        };
    }

    // ---- Aviso de reinício (screens §15) ----
    // Quem dispara e trata o toque é o OsdBridge (uma vez por sessão, quando o
    // manifest injetado não bate com codeVersion). Aqui só o estado, para a
    // dica da linha não aparecer junto.
    readonly property bool restartNoticeShowing: island.osd.internal === "restart"

    function clockFormatIs12h(config) {
        const layout = config && config.layout;
        if (!layout || typeof layout !== "object")
            return false;
        for (const section in layout) {
            const list = layout[section];
            if (!Array.isArray(list))
                continue;
            for (let i = 0; i < list.length; i++) {
                const e = list[i];
                if (e && e.id === "omarchy.clock" && /ap/i.test(String(e.format || "")))
                    return true;
            }
        }
        return false;
    }

    QtObject {
        id: priv
        // back() em curso: o open() dele não empilha a tela de agora.
        property bool goingBack: false
        property var faces: ({})
        property var windows: ({})
        property var pendingRun: null
        property real wheelAcc: 0
        property real wheelAt: 0
        property bool barGlassy: false
        property bool windowGlassy: false
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Component.onCompleted: {
        const next = {};
        for (const id in island.screenUrls)
            next[id] = Qt.createComponent(island.screenUrls[id], Component.Asynchronous);
        island.components = next;
        island.screenOutput = island.focusedOutput();
    }

    // ---- Barra escondida (omarchy toggle bar): flag bar-off ----
    readonly property string home: Quickshell.env("HOME")
    readonly property string togglesDir: island.home + "/.local/state/omarchy/toggles"

    Process {
        id: hiddenProbe
        running: true
        command: ["sh", "-c", "if [ -f \"$1\" ]; then echo yes; else echo no; fi", "sh", island.togglesDir + "/bar-off"]
        stdout: SplitParser {
            onRead: line => island.barHidden = String(line).trim() === "yes"
        }
    }

    // A FileView não vigia arquivo que ainda não existe; vigia a pasta.
    FileView {
        path: island.togglesDir
        watchChanges: true
        printErrors: false
        onFileChanged: hiddenProbe.running = true
    }

    FileView {
        path: island.togglesDir + "/hypr/bar-glassy.lua"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: priv.barGlassy = true
        onLoadFailed: priv.barGlassy = false
    }
    FileView {
        path: island.togglesDir + "/hypr/window-glassy.lua"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: priv.windowGlassy = true
        onLoadFailed: priv.windowGlassy = false
    }

    // ---- IPC: os alvos que a barra padrão registrava ----
    Commons.ShellIpc {
        target: "omarchy.bar"
        function syncHidden(): void {
            hiddenProbe.running = true;
        }
    }

    Commons.ShellIpc {
        target: "omarchy.indicators"
        function refresh(): void {
            island.status.refresh();
        }
    }

    Commons.ShellIpc {
        target: "omarchy.system-update"
        function refresh(): void {
            island.status.refreshUpdates();
        }
        function clear(): void {
            island.status.clearUpdates();
        }
    }

    Commons.ShellIpc {
        target: "omarchy.workspaces"
        function refresh(): void {
            Hyprland.refreshWorkspaces();
        }
    }

    Commons.ShellIpc {
        target: "omarchy.clock"
        function refresh(): void {
            clock.enabled = false;
            clock.enabled = true;
        }
        function open(): void {
            island.setExpanded(island.focusedOutput(), true);
        }
        function show(): void {
            island.setExpanded(island.focusedOutput(), true);
        }
        function close(): void {
            island.setExpanded(island.focusedOutput(), false);
        }
        function hide(): void {
            island.setExpanded(island.focusedOutput(), false);
        }
        function toggle(): void {
            const out = island.focusedOutput();
            island.setExpanded(out, island.expandedOutput !== out);
        }
    }

    // Alvo próprio: omarchy-shell ilha <função> …
    Commons.ShellIpc {
        target: "ilha"

        function open(target: string): string {
            island.keyboardMode = true;
            return island.open(String(target), "", { keyboard: true }) ? "ok" : "unknown";
        }
        function toggle(target: string): string {
            island.keyboardMode = true;
            return island.toggle(String(target), "") ? "ok" : "unknown";
        }
        function close(): string {
            island.close();
            return "ok";
        }
        // Voltar: subpágina da Central, tela anterior ou fechar.
        function back(): string {
            return island.navBack() ? "ok" : "closed";
        }
        function run(target: string, key: string): string {
            return island.runKey(String(target), String(key));
        }
        function osd(payloadJson: string): string {
            return island.osd.show(String(payloadJson));
        }
        function closeOsd(): string {
            island.osd.hide();
            return "ok";
        }
        // 0 repouso, 1 linha (L1), 2 linha completa (L2), no monitor focado.
        function hover(level: string): string {
            const out = island.focusedOutput();
            const n = String(level).trim();
            if (n === "0") {
                island.hoverOutput = "";
                island.setExpanded(out, false);
            } else if (n === "1") {
                island.setExpanded(out, false);
                island.hoverOutput = out;
            } else if (n === "2") {
                island.hoverOutput = out;
                island.setExpanded(out, true);
            } else {
                return "invalid";
            }
            return "ok";
        }
        function state(): string {
            return JSON.stringify(island.debugBarGeometry());
        }
        // Alterna o seletor no monitor focado.
        function picker(): string {
            const out = island.focusedOutput();
            if (island.pickerOutput === out) {
                island.closePicker();
                return "closed";
            }
            return island.openPicker(out) ? "open" : "busy";
        }
        // Mostra um aviso ao vivo mesmo com o indicador desligado (force).
        function peek(key: string): string {
            const k = String(key).trim();
            let row = null;
            if (k === "urgent") {
                const live = island.status.live;
                if (!live || live.length === 0)
                    return "empty";
                row = live[0];
            }
            return island.peek.raise(k, row, true);
        }
        // focusedOnly | livePeek ; true | false | toggle
        function setting(key: string, value: string): string {
            const k = String(key).trim();
            if (!Object.prototype.hasOwnProperty.call(island.prefs.defaults, k))
                return "unknown";
            const v = String(value).trim().toLowerCase();
            if (v === "toggle")
                return island.prefs.toggle(k) ? "ok" : "unknown";
            if (v !== "true" && v !== "false")
                return "invalid";
            return island.prefs.set(k, v === "true") ? "ok" : "unknown";
        }
    }

    // Só no harness: mostra / esconde as janelas (dev/harness.sh shot).
    Commons.ShellIpc {
        target: island.dev ? "ilha-dev" : ""
        function reveal(on: string): string {
            island.devShown = String(on).trim() === "1";
            return island.devShown ? "shown" : "hidden";
        }
    }

    // ---- Uma janela por monitor ----
    Variants {
        id: windows
        // A raiz, vista de dentro do delegate (que tem o próprio `island`).
        readonly property Item owner: island
        model: island.dev ? (Quickshell.screens.length > 0 ? [Quickshell.screens[0]] : []) : Quickshell.screens
        delegate: IslandWindow {
            island: windows.owner
        }
    }
}
