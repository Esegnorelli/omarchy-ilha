import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons as Commons
import "TileArm.js" as TileArm

// Ilha: plugin de barra (kind "bar") que substitui a barra do Omarchy por uma
// pílula só, no topo, que muda de forma.
//
// Em repouso não aparece nada (só uma bolinha de 8 px se houver indicador
// ligado). Uma faixa invisível de 3 px nos 600 px do centro da borda de cima
// revela a pílula: a bolinha desce, estica até virar a pílula e o conteúdo
// entra. Os painéis (Apps, Controle, Captura, Estilo, Ferramentas, Tempo,
// Energia) e o OSD são estados da mesma pílula.
//
// Layout (spec §3.3): largura fixa de 568 em hover e em todo painel (o OSD
// tem a sua). Coluna = Strip (46, relógio no centro exato da tela) + estado
// ativo + PanelFooter. Clicar num ícone abre o painel e liga o "modo menu":
// repousar 150 ms noutro ícone troca de painel, descer o ponteiro cancela,
// clicar no ícone ativo volta à faixa e sair com o ponteiro não fecha.
//
// Teclado (spec §4): o estado trata a tecla primeiro (handleKey); depois vêm
// 0–6 / Alt+0–6 (categorias), Ctrl+Tab / Ctrl+Shift+Tab e a cadeia do Esc
// (handleEscape do estado → fechar). keyboardMode liga ao abrir por IPC ou
// atalho e na primeira tecla; mover o ponteiro mais de 8 px desliga.
//
// Contrato com o host (shell.qml do Omarchy): as propriedades injetadas,
// o estado publicado (barHidden, barSize, screenBarSizes, fontFamily,
// position, barSizeFor), os atalhos de painel (summonBarWidget e afins) e os
// alvos de IPC que a barra padrão registrava.
Item {
    id: island

    // ---- Injetado pelo host (só é preenchido se estiver declarado) ----
    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var barWidgetRegistry: null
    property var pluginRegistry: null
    property var barConfig: null

    // ---- Estado publicado para o host e para as notificações ----
    property bool barHidden: false
    // Altura de repouso informada: a faixa de ativação e a folga da bolinha.
    // Precisa ser maior que zero, senão as notificações usam o tamanho padrão.
    // Em repouso a ilha fica sempre visível: um notch compacto só com o relógio.
    readonly property int restHeight: 30
    readonly property int restWidth: 104
    readonly property int barSize: restHeight
    readonly property var screenBarSizes: {
        const sizes = ({})
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            sizes[screens[i].name] = island.barHidden ? 0 : island.barSize
        return sizes
    }
    readonly property string fontFamily: Commons.Style.fontFamily
    readonly property string position: "top"

    function barSizeFor(screenName) {
        const size = screenBarSizes[String(screenName || "")]
        return size !== undefined ? size : (barHidden ? 0 : barSize)
    }

    // ---- Cores do tema (o host repassa as mesmas aos estados) ----
    readonly property color fg: Commons.Color.bar.text
    readonly property color bg: Commons.Color.bar.background
    readonly property color accent: Commons.Color.accent
    readonly property color danger: Commons.Color.urgent

    // Para testes fora do shell: onde fica a flag bar-off e se checa
    // atualizações (faz git fetch).
    property string hiddenFlagPath: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/bar-off"
    property bool checkUpdates: true

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    // Outro nome para repassar: dentro de Strip { strings: … } o nome
    // "strings" seria a própria propriedade da faixa.
    readonly property var translations: strings

    // Medidas da grade, repassadas aos estados (StateSlot.wire).
    property Metrics metrics: Metrics {}

    // ---- Teclado ----
    // Modo teclado: anel de foco, letras cheias e dígitos na faixa.
    property bool keyboardMode: false
    // Alt segurado mostra os dígitos da faixa.
    property bool altHeld: false
    // Último painel aberto (Super+Z → "toggle last").
    property string lastView: "control"
    // Tecla pendente de "run <estado> <tecla>": { view, event }.
    property var pendingRun: null

    // A notch "respira" (1.0 → 1.015 → 1.0) quando um indicador liga ou chega um OSD.
    signal breathe()

    // ---- Estados ----
    // Painel aberto: "" ou um destes.
    property string view: ""
    readonly property var views: ["launcher", "control", "capture", "style", "tools", "calendar", "power"]
    // Ordem da faixa: 0 = Tempo, 1–6 = Apps … Energia (dígitos e Ctrl+Tab).
    readonly property var categoryOrder: ["calendar", "launcher", "control", "capture", "style", "tools", "power"]
    // Monitor que mostra painéis, OSD e eventos (só um por vez).
    property string panelScreen: ""

    property var osdPayload: ({})
    property bool osdShown: false
    readonly property bool eventShown: eventTimer.running

    // Atalhos de painel do Omarchy (Super+Ctrl+…) que a ilha atende.
    readonly property var widgetViews: ({
        "omarchy.audio": "control",
        "omarchy.bluetooth": "control",
        "omarchy.network": "control",
        "omarchy.clock": "calendar",
        "omarchy.power": "power"
    })

    function focusedScreenName() {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            return String(Hyprland.focusedMonitor.name)
        const screens = Quickshell.screens
        return screens.length > 0 ? String(screens[0].name) : ""
    }

    // "last" vira o último painel aberto.
    function resolveView(target) {
        const t = String(target || "")
        return t === "last" ? lastView : t
    }

    // Abre um estado num monitor (o focado, se não for dito).
    function show(target, screenName) {
        target = resolveView(target)
        if (views.indexOf(target) < 0)
            return false
        panelScreen = screenName && screenName !== "" ? screenName : focusedScreenName()
        view = target
        return true
    }

    // Alterna: abrir o que já está aberto fecha.
    function toggle(target, screenName) {
        target = resolveView(target)
        if (views.indexOf(target) < 0)
            return false
        if (view === target) {
            close()
            return true
        }
        return show(target, screenName)
    }

    function close() {
        view = ""
    }

    onViewChanged: {
        if (view !== "")
            lastView = view
        else
            altHeld = false
        // Nenhum confirm fica armado ao trocar de painel.
        TileArm.disarmAll()
    }

    // Clique na faixa: abre; clicar no ativo volta à faixa sozinha.
    function categoryClick(target, screenName) {
        keyboardMode = false
        if (view === target && panelScreen === screenName) {
            close()
            return
        }
        show(target, screenName)
    }

    // Dígito ou Alt+dígito: abre; o dígito do painel aberto volta à faixa
    // (que fica um instante, como num evento).
    function categoryKey(target) {
        if (view === target) {
            close()
            revealEvent()
            return
        }
        show(target, panelScreen)
    }

    // Ctrl+Tab (+1) / Ctrl+Shift+Tab (-1), na ordem da faixa, com volta.
    function cycle(step) {
        const n = categoryOrder.length
        const at = categoryOrder.indexOf(view)
        const from = at < 0 ? categoryOrder.indexOf(lastView) : at
        show(categoryOrder[((from + step) % n + n) % n], panelScreen)
    }

    // "Q", "shift+Q", "⇧Q", "enter", "pgdn"… → evento sintético para handleKey.
    function parseKey(name) {
        let raw = String(name || "").trim()
        let mods = 0
        const parts = raw.split("+")
        if (parts.length > 1 && parts[parts.length - 1] !== "") {
            raw = parts.pop()
            for (const m of parts) {
                const lower = m.toLowerCase()
                if (lower === "shift") mods |= Qt.ShiftModifier
                else if (lower === "ctrl" || lower === "control") mods |= Qt.ControlModifier
                else if (lower === "alt") mods |= Qt.AltModifier
                else return null
            }
        }
        if (raw.indexOf("⇧") === 0) {
            mods |= Qt.ShiftModifier
            raw = raw.slice(1)
        }
        const named = {
            "enter": Qt.Key_Return, "return": Qt.Key_Return, "space": Qt.Key_Space,
            "esc": Qt.Key_Escape, "escape": Qt.Key_Escape, "tab": Qt.Key_Tab,
            "up": Qt.Key_Up, "down": Qt.Key_Down, "left": Qt.Key_Left, "right": Qt.Key_Right,
            "pgup": Qt.Key_PageUp, "pageup": Qt.Key_PageUp, "pgdn": Qt.Key_PageDown,
            "pagedown": Qt.Key_PageDown, "home": Qt.Key_Home, "end": Qt.Key_End
        }
        let key = named[raw.toLowerCase()]
        let text = raw === "space" ? " " : ""
        if (key === undefined) {
            if (raw.length !== 1)
                return null
            const code = raw.toUpperCase().charCodeAt(0)
            // Qt.Key_A…Z, 0…9, "-", "=", "[", "]" têm o código ASCII da tecla.
            if (code < 0x20 || code > 0x7e)
                return null
            key = code
            text = (mods & Qt.ShiftModifier) ? raw.toUpperCase() : raw.toLowerCase()
        }
        return { key: key, modifiers: mods, text: text, isAutoRepeat: false, accepted: false, synthetic: true }
    }

    // run <estado> <tecla>: abre no modo teclado e manda a tecla quando o
    // estado estiver na tela.
    function runKey(target, keyName) {
        target = resolveView(target)
        if (views.indexOf(target) < 0)
            return "unknown"
        const event = parseKey(keyName)
        if (!event)
            return "invalid-key"
        keyboardMode = true
        if (view !== target)
            show(target, "")
        pendingRun = { view: target, event: event, at: Date.now() }
        return "ok"
    }

    function showOsd(payloadJson) {
        let payload
        try {
            payload = JSON.parse(String(payloadJson || "{}"))
        } catch (e) {
            return false
        }
        if (!payload || typeof payload !== "object" || Array.isArray(payload))
            return false
        if (view === "")
            panelScreen = focusedScreenName()
        osdPayload = payload
        osdShown = true
        island.breathe()
        const parsed = parseInt(payload.duration !== undefined && String(payload.duration) !== "" ? payload.duration : "1200", 10)
        const duration = isNaN(parsed) ? 1200 : Math.max(0, parsed)
        if (duration > 0) {
            osdTimer.interval = duration
            osdTimer.restart()
        } else {
            osdTimer.stop()
        }
        return true
    }

    function closeOsd() {
        osdTimer.stop()
        osdShown = false
    }

    // Revela a pílula sozinha por um instante (indicador novo, por exemplo).
    function revealEvent() {
        if (view === "")
            panelScreen = focusedScreenName()
        eventTimer.restart()
    }

    // ---- Contrato de painéis do host ----
    function summonBarWidget(pluginId) {
        const target = widgetViews[String(pluginId || "")]
        if (!target) {
            console.log("ilha: no pill state for " + pluginId)
            return false
        }
        keyboardMode = true
        return show(target, focusedScreenName())
    }

    function hideBarWidget(pluginId) {
        const target = widgetViews[String(pluginId || "")]
        if (!target)
            return false
        if (view === target)
            close()
        return true
    }

    function isBarWidgetOpen(pluginId) {
        const target = widgetViews[String(pluginId || "")]
        return !!target && view === target
    }

    // Super+Ctrl+1..9: a N-ésima entrada de cada seção, contando de 1.
    function panelWidgetIdAt(section, index) {
        const sections = {
            "center": ["omarchy.clock"],
            "right": ["omarchy.audio", "omarchy.network", "omarchy.power"]
        }
        const list = sections[String(section || "")] || []
        const item = list[Math.round(Number(index)) - 1]
        return item ? item : ""
    }

    // A ilha não tem fundo transparente/vidro para alternar.
    function cycleBackground() {
        console.log("ilha: cycleBackground is not supported")
    }

    function debugBarGeometry() {
        return JSON.stringify({
            id: "esegnorelli.ilha",
            barHidden: barHidden,
            barSize: barSize,
            screenBarSizes: screenBarSizes,
            view: view,
            lastView: lastView,
            keyboardMode: keyboardMode,
            panelScreen: panelScreen,
            osd: osdShown
        })
    }

    Component.onCompleted: panelScreen = focusedScreenName()

    Timer {
        id: osdTimer
        interval: 1200
        onTriggered: island.osdShown = false
    }

    Timer {
        id: eventTimer
        interval: 2600
    }

    // ---- Indicadores: uma fonte só, espelhada em cada monitor ----
    // (repassada por este nome: em Strip { indicatorSource: … } o nome
    // "indicatorSource" seria a propriedade da própria faixa)
    readonly property var sharedIndicators: indicatorSource
    Indicators {
        id: indicatorSource
        visible: false
        shell: island.shell
        checkUpdates: island.checkUpdates
        onBecameActive: what => {
            if (what !== "notifications")
                island.revealEvent()
            island.breathe()
        }
    }

    // ---- Barra escondida (omarchy toggle bar): flag bar-off ----
    Process {
        id: hiddenProbe
        running: true
        command: ["sh", "-c", "if [ -f \"$1\" ]; then echo yes; else echo no; fi", "sh", island.hiddenFlagPath]
        stdout: SplitParser {
            onRead: line => island.barHidden = String(line).trim() === "yes"
        }
    }

    // A FileView não vigia arquivo que ainda não existe; vigia a pasta.
    FileView {
        path: island.hiddenFlagPath.replace(/\/[^\/]*$/, "")
        watchChanges: true
        printErrors: false
        onFileChanged: hiddenProbe.running = true
    }

    // ---- IPC: os alvos que a barra padrão registrava ----
    Commons.ShellIpc {
        target: "omarchy.bar"

        function syncHidden(): void {
            hiddenProbe.running = true
        }
    }

    Commons.ShellIpc {
        target: "omarchy.indicators"

        function refresh(): void {
            indicatorSource.refresh()
        }
    }

    Commons.ShellIpc {
        target: "omarchy.system-update"

        function refresh(): void {
            indicatorSource.refreshUpdates()
        }

        function clear(): void {
            indicatorSource.clearUpdates()
        }
    }

    Commons.ShellIpc {
        target: "omarchy.workspaces"

        function refresh(): void {
            Hyprland.refreshWorkspaces()
        }
    }

    Commons.ShellIpc {
        target: "omarchy.clock"

        function refresh(): void {
            clock.enabled = false
            clock.enabled = true
        }

        function open(): void { island.keyboardMode = true; island.show("calendar", "") }
        function close(): void { if (island.view === "calendar") island.close() }
        function show(): void { island.keyboardMode = true; island.show("calendar", "") }
        function hide(): void { if (island.view === "calendar") island.close() }
        function toggle(): void { island.keyboardMode = true; island.toggle("calendar", "") }
    }

    // Alvo próprio: omarchy-shell ilha open <estado|last> | toggle <estado|last>
    // | run <estado> <tecla> | close | osd <json> | state
    Commons.ShellIpc {
        target: "ilha"

        // Como antes: abrir o que já está aberto fecha.
        function open(target: string): string {
            island.keyboardMode = true
            return island.toggle(String(target), "") ? "ok" : "unknown"
        }

        function toggle(target: string): string {
            island.keyboardMode = true
            return island.toggle(String(target), "") ? "ok" : "unknown"
        }

        // Abre o painel no modo teclado e manda a tecla: ilha run capture Q
        function run(target: string, key: string): string {
            return island.runKey(String(target), String(key))
        }

        function close(): string {
            island.close()
            return "ok"
        }

        function osd(payloadJson: string): string {
            return island.showOsd(payloadJson) ? "ok" : "invalid"
        }

        function closeOsd(): string {
            island.closeOsd()
            return "ok"
        }

        function state(): string {
            return JSON.stringify({ view: island.view, lastView: island.lastView, keyboard: island.keyboardMode, osd: island.osdShown, hidden: island.barHidden, screen: island.panelScreen })
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }


    // ---- Uma janela por monitor ----
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            readonly property string screenName: String(modelData.name)
            readonly property bool isTarget: island.panelScreen === screenName
            readonly property Metrics metrics: island.metrics

            anchors.top: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "omarchy-bar"
            // OnDemand: com Exclusive o compositor derruba o HyprlandFocusGrab.
            WlrLayershell.keyboardFocus: win.isTarget && island.view !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            // Grande o bastante para o maior estado; a máscara limita o mouse.
            implicitWidth: 760
            implicitHeight: Math.min(modelData.height, 820)

            // ---- O que esta janela mostra ----
            readonly property bool hoverAllowed: !island.barHidden
            readonly property bool hovered: hoverAllowed && (surfaceHover.hovered || closeDelay.running)
            // Com painel aberto (modo menu) o ponteiro sair não fecha: o modo
            // segue a view; só o modo hover depende do ponteiro.
            readonly property string mode: isTarget && island.view !== "" ? island.view
                : isTarget && island.osdShown ? "osd"
                : hovered ? "hover"
                : isTarget && island.eventShown ? "hover"
                : "rest"
            readonly property bool revealed: mode !== "rest"
            readonly property bool dotVisible: !island.barHidden && indicatorSource.anyActive

            // Estado (painel ou OSD) na tela; nulo em hover e repouso.
            readonly property Item modeItem: {
                switch (mode) {
                case "launcher": return launcherSlot
                case "control": return controlSlot
                case "capture": return captureSlot
                case "style": return styleSlot
                case "tools": return toolsSlot
                case "calendar": return calendarSlot
                case "power": return powerSlot
                case "osd": return osdSlot
                default: return null
                }
            }
            readonly property bool isPanel: island.views.indexOf(mode) >= 0
            // A faixa fica em hover e em todo painel, sempre no mesmo lugar.
            readonly property bool hasStrip: mode === "hover" || isPanel
            // Largura constante (568) em hover e painéis; o OSD tem a sua.
            readonly property real targetWidth: mode === "rest" ? 12
                : mode === "osd" ? (modeItem ? modeItem.implicitWidth + 32 : 12)
                : metrics.width
            // faixa 46 (+ 8 + estado + 8 + rodapé 20 + 12 nos painéis).
            readonly property real targetHeight: mode === "rest" ? 12
                : mode === "osd" ? (modeItem ? modeItem.implicitHeight + 16 : 12)
                : mode === "hover" ? metrics.strip
                : Math.min(metrics.chrome + (modeItem ? modeItem.implicitHeight : 0), win.height - 16)

            // ---- Coreografia ----
            // 0: repouso (sumida ou bolinha); 1: bolinha de 12 px no lugar;
            // 2: esticada no estado atual.
            property int phase: 0
            property bool contentLatched: false
            property string pendingStep: ""
            readonly property bool animate: Commons.Style.duration(1) > 0
            readonly property bool shrinking: phase < 2 || !revealed
            readonly property bool contentOn: phase === 2 && revealed && contentLatched
            // A faixa só depende da largura (constante entre hover e painéis):
            // trocar de painel não a faz piscar.
            readonly property bool stripOn: phase === 2 && revealed && hasStrip
                && pill.width >= (targetWidth + 2 * flare) * 0.8 && pill.height >= metrics.strip * 0.8

            function checkLatch() {
                if (phase === 2 && revealed && pill.width >= targetWidth * 0.8 && pill.height >= targetHeight * 0.8)
                    contentLatched = true
            }

            function step(name, ms) {
                pendingStep = name
                stepTimer.interval = Commons.Style.duration(ms)
                stepTimer.restart()
            }

            onRevealedChanged: {
                stepTimer.stop()
                if (revealed) {
                    // O notch compacto do relógio se estica direto até o estado.
                    phase = 2
                    Qt.callLater(checkLatch)
                } else {
                    // Conteúdo some primeiro, depois encolhe de volta ao relógio.
                    contentLatched = false
                    if (phase === 2)
                        step("shrink", 120)
                    else
                        step("rise", 0)
                }
            }

            onModeChanged: {
                contentLatched = false
                Qt.callLater(checkLatch)
            }
            onTargetWidthChanged: Qt.callLater(checkLatch)
            onTargetHeightChanged: Qt.callLater(checkLatch)

            // O rodapé mostra o estado que está de fato na tela (não troca de
            // texto antes do conteúdo novo entrar).
            property Item footerSlot: null
            onContentOnChanged: {
                if (!contentOn)
                    return
                if (isPanel)
                    footerSlot = modeItem
                // Depois que o slot reavaliar "enabled" (senão o tile Q ainda
                // não aceita foco).
                Qt.callLater(focusState)
            }

            Timer {
                id: stepTimer
                onTriggered: {
                    const name = win.pendingStep
                    win.pendingStep = ""
                    if (name === "expand") {
                        win.phase = 2
                        Qt.callLater(win.checkLatch)
                    } else if (name === "shrink") {
                        win.phase = 0
                    } else if (name === "rise") {
                        win.phase = 0
                    }
                }
            }

            // Folga antes de esconder, para o mouse poder voltar.
            Timer {
                id: closeDelay
                interval: 300
            }

            // ---- Respiro: 1.0 → 1.015 → 1.0 em ~260 ms, sempre desacelerando ----
            property real breath: 1

            SequentialAnimation {
                id: breathAnim
                NumberAnimation {
                    target: win; property: "breath"; to: win.metrics.breathScale
                    duration: Commons.Style.duration(Math.round(win.metrics.msBreath * 0.4))
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: win; property: "breath"; to: 1
                    duration: Commons.Style.duration(Math.round(win.metrics.msBreath * 0.6))
                    easing.type: Easing.OutCubic
                }
            }

            Connections {
                target: island
                function onBreathe() {
                    if (win.animate && (win.revealed || win.dotVisible))
                        breathAnim.restart()
                }
                // Modo teclado novo: a próxima posição do ponteiro vira a âncora.
                function onKeyboardModeChanged() { win.kbAnchored = false }
            }

            // ---- Teclado ----
            property point kbAnchor: Qt.point(0, 0)
            property bool kbAnchored: false

            function currentState() {
                return isPanel && modeItem && modeItem.item ? modeItem.item : null
            }

            // Ao entrar um painel: foco no item Q (focusFirst) ou no estado.
            // O lançador foca o próprio campo; um campo já focado não é roubado.
            function focusState() {
                if (!isTarget || !isPanel || mode === "launcher")
                    return
                const state = currentState()
                if (!state) {
                    keys.forceActiveFocus()
                    return
                }
                let focused = keys.Window.activeFocusItem
                while (focused && focused !== state)
                    focused = focused.parent
                if (focused)
                    return
                state.forceActiveFocus()
                if (typeof state.focusFirst === "function")
                    state.focusFirst()
            }

            // Tecla vinda da superfície (ou sintetizada por "run").
            function dispatchKey(event) {
                const k = event.key
                if (k === Qt.Key_Alt || k === Qt.Key_AltGr) {
                    island.altHeld = true
                    return false
                }
                if (k === Qt.Key_Shift || k === Qt.Key_Control || k === Qt.Key_Meta
                        || k === Qt.Key_Super_L || k === Qt.Key_Super_R)
                    return false
                island.keyboardMode = true
                const state = currentState()
                if (state && typeof state.handleKey === "function" && state.handleKey(event))
                    return true
                return globalKey(event)
            }

            function globalKey(event) {
                const k = event.key
                const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)
                if (k >= Qt.Key_0 && k <= Qt.Key_6 && (mods === 0 || mods === Qt.AltModifier)) {
                    if (!event.isAutoRepeat)
                        island.categoryKey(island.categoryOrder[k - Qt.Key_0])
                    return true
                }
                if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && (mods & Qt.ControlModifier)) {
                    island.cycle(k === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1)
                    return true
                }
                if (k === Qt.Key_Escape) {
                    // Cadeia: desarmar → limpar a busca (o estado decide) → fechar.
                    const state = currentState()
                    if (state && typeof state.handleEscape === "function" && state.handleEscape())
                        return true
                    island.close()
                    return true
                }
                return false
            }

            // "run <estado> <tecla>": espera o estado entrar e manda a tecla.
            function tryRun() {
                const p = island.pendingRun
                if (!p)
                    return
                if (Date.now() - p.at > 3000) {
                    island.pendingRun = null
                    return
                }
                const slot = win.modeItem
                if (win.mode !== p.view || !slot || !slot.item || !slot.shown)
                    return
                island.pendingRun = null
                win.focusState()
                win.dispatchKey(p.event)
            }

            Timer {
                interval: 40
                repeat: true
                running: win.isTarget && island.pendingRun !== null
                onTriggered: win.tryRun()
            }

            // ---- Entrada: faixa de ativação + a pílula ----
            // Curva côncava de cada lado do notch, onde ele encontra a tela.
            readonly property real flare: 10
            readonly property int stripWidth: 600
            readonly property int stripHeight: 3
            // A área de entrada segue o tamanho final do estado, não a pílula
            // animada: trocar a máscara a cada quadro faz o compositor mandar
            // saída/entrada do ponteiro e o hover piscar.
            readonly property int inputWidth: revealed ? Math.ceil(targetWidth + 2 * flare) : hoverAllowed ? island.restWidth + 2 * flare : 0
            readonly property int inputHeight: revealed ? Math.ceil(targetHeight) : hoverAllowed ? island.restHeight : 0

            mask: Region {
                Region {
                    x: Math.round((win.width - win.stripWidth) / 2)
                    y: 0
                    width: win.hoverAllowed ? win.stripWidth : 0
                    height: win.hoverAllowed ? win.stripHeight : 0
                }
                Region {
                    x: Math.floor((win.width - win.inputWidth) / 2)
                    y: 0
                    width: win.inputWidth
                    height: win.inputHeight
                }
            }

            // Clicar fora fecha o painel.
            HyprlandFocusGrab {
                windows: [win]
                active: win.isTarget && island.view !== ""
                onCleared: island.close()
            }

            Item {
                id: surface
                anchors.fill: parent

                HoverHandler {
                    id: surfaceHover
                    onHoveredChanged: if (!hovered) closeDelay.restart()
                    // Mover o ponteiro mais de 8 px sai do modo teclado.
                    onPointChanged: {
                        if (!island.keyboardMode || !win.isTarget || !hovered)
                            return
                        const p = point.position
                        if (!win.kbAnchored) {
                            win.kbAnchor = Qt.point(p.x, p.y)
                            win.kbAnchored = true
                            return
                        }
                        if (Math.hypot(p.x - win.kbAnchor.x, p.y - win.kbAnchor.y) > win.metrics.pointerModeThreshold)
                            island.keyboardMode = false
                    }
                }

                // Tratador central: fica na superfície, ancestral de todos os
                // estados, então recebe toda tecla que o item focado não aceitou.
                Keys.onPressed: event => {
                    if (win.dispatchKey(event))
                        event.accepted = true
                }
                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr)
                        island.altHeld = false
                }

                // Alt+0…6 e Ctrl+Tab valem até dentro do campo do lançador
                // (onde os dígitos digitam): atalhos passam antes do foco.
                Shortcut { sequence: "Alt+0"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(0) }
                Shortcut { sequence: "Alt+1"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(1) }
                Shortcut { sequence: "Alt+2"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(2) }
                Shortcut { sequence: "Alt+3"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(3) }
                Shortcut { sequence: "Alt+4"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(4) }
                Shortcut { sequence: "Alt+5"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(5) }
                Shortcut { sequence: "Alt+6"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(6) }
                Shortcut {
                    sequence: "Ctrl+Tab"
                    enabled: win.isTarget && island.view !== ""
                    onActivated: { island.keyboardMode = true; island.cycle(1) }
                }
                Shortcut {
                    sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]
                    enabled: win.isTarget && island.view !== ""
                    onActivated: { island.keyboardMode = true; island.cycle(-1) }
                }

                // Foco de reserva quando o estado não tem item carregado.
                Item {
                    id: keys
                    focus: true
                }

                Item {
                    id: pill

                    // Em repouso: notch compacto só com o relógio (e a marquinha).
                    readonly property bool atRest: win.phase !== 2
                    readonly property bool asDot: false

                    anchors.horizontalCenter: parent.horizontalCenter
                    // Largura do corpo + as duas curvas côncavas do topo.
                    width: (win.phase === 2 ? win.targetWidth : island.restWidth) + 2 * win.flare
                    height: win.phase === 2 ? win.targetHeight : island.restHeight
                    // Sempre colado na borda de cima; só some com a barra escondida.
                    y: 0
                    opacity: win.hoverAllowed ? 1 : 0
                    clip: true
                    // Respiro preso à borda de cima: o centro (e o relógio) não sai do lugar.
                    transformOrigin: Item.Top
                    scale: win.breath

                    onWidthChanged: win.checkLatch()
                    onHeightChanged: win.checkLatch()

                    Behavior on width {
                        enabled: win.animate
                        SpringAnimation {
                            spring: win.shrinking ? 12 : 6
                            damping: win.shrinking ? 0.9 : 0.5
                            epsilon: 0.25
                        }
                    }

                    Behavior on height {
                        enabled: win.animate
                        SpringAnimation {
                            spring: win.shrinking ? 12 : 6
                            damping: win.shrinking ? 0.9 : 0.5
                            epsilon: 0.25
                        }
                    }

                    Behavior on y {
                        NumberAnimation {
                            duration: Commons.Style.duration(win.phase === 0 ? 100 : 140)
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Commons.Style.duration(win.phase === 0 ? 100 : 140)
                            easing.type: Easing.OutCubic
                        }
                    }

                    NotchShape {
                        anchors.fill: parent
                        radius: Math.min(height / 2, 24)
                        flare: Math.min(win.flare, height)
                        color: island.bg

                        Behavior on color {
                            ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                        }
                    }

                    // ---- Repouso: relógio compacto + marquinha de indicador ----
                    Item {
                        id: restClock
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        width: island.restWidth
                        height: island.restHeight
                        opacity: pill.atRest && !win.revealed ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(pill.atRest ? 160 : 90); easing.type: Easing.OutCubic }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Qt.locale(Commons.I18n.formatLocale).toString(clock.date, "HH:mm")
                            textFormat: Text.PlainText
                            font.family: Commons.Style.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: island.fg
                        }

                        // Indicador ativo (gravando, Não perturbe…): ponto na cor do aviso.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            width: 6
                            height: 6
                            radius: 3
                            color: indicatorSource.dotColor
                            opacity: win.dotVisible ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    // ---- Faixa: workspaces · app · indicadores | relógio | 6 ícones ----
                    Strip {
                        id: strip

                        // Preso ao centro da pílula (e a pílula ao centro da tela): o
                        // relógio fica no centro exato mesmo enquanto a mola da
                        // largura passa do alvo ao revelar.
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        screenName: win.screenName
                        activeView: win.isTarget ? island.view : ""
                        menuMode: win.isTarget && island.view !== ""
                        keyboardMode: win.isTarget && island.view !== "" && island.keyboardMode
                        altHeld: win.isTarget && island.altHeld
                        indicatorSource: island.sharedIndicators
                        shell: island.shell
                        strings: island.translations
                        now: clock.date
                        fg: island.fg
                        bg: island.bg
                        accent: island.accent
                        danger: island.danger
                        metrics: win.metrics

                        opacity: win.stripOn ? 1 : 0
                        scale: win.stripOn ? 1 : 0.97
                        visible: opacity > 0
                        enabled: win.stripOn

                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(win.stripOn ? 180 : 120); easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: Commons.Style.duration(win.stripOn ? 180 : 120); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                        }

                        onCategoryClicked: target => island.categoryClick(target, win.screenName)
                        onCategoryDwelled: target => {
                            if (win.isTarget && island.view !== "")
                                island.show(target, win.screenName)
                        }
                        onWorkspaceClicked: island.close()
                        onIndicatorNavigate: target => {
                            island.keyboardMode = false
                            island.show(target, win.screenName)
                        }
                    }

                    // ---- Estados (painéis e OSD) ----
                    StateSlot { id: launcherSlot; hostWindow: win; hostIsland: island; name: "launcher"; source: "Launcher.qml" }
                    StateSlot { id: controlSlot; hostWindow: win; hostIsland: island; name: "control"; source: "ControlPanel.qml" }
                    StateSlot { id: captureSlot; hostWindow: win; hostIsland: island; name: "capture"; source: "CaptureMenu.qml" }
                    StateSlot { id: styleSlot; hostWindow: win; hostIsland: island; name: "style"; source: "StyleMenu.qml" }
                    StateSlot { id: toolsSlot; hostWindow: win; hostIsland: island; name: "tools"; source: "ToolsMenu.qml" }
                    StateSlot { id: calendarSlot; hostWindow: win; hostIsland: island; name: "calendar"; source: "CalendarView.qml" }
                    StateSlot { id: powerSlot; hostWindow: win; hostIsland: island; name: "power"; source: "PowerMenu.qml" }
                    StateSlot { id: osdSlot; hostWindow: win; hostIsland: island; name: "osd"; source: "OsdView.qml" }

                    // ---- Rodapé: estado à esquerda, dicas à direita ----
                    PanelFooter {
                        id: footer
                        readonly property bool shown: win.isPanel && win.contentOn && win.footerSlot !== null

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: win.metrics.strip + win.metrics.padTop
                            + (win.footerSlot ? win.footerSlot.implicitHeight : 0) + win.metrics.gap
                        status: win.footerSlot ? win.footerSlot.footerStatus : ""
                        hints: win.footerSlot ? win.footerSlot.footerHints : ""
                        alert: win.footerSlot ? win.footerSlot.footerAlert : false
                        fg: island.fg
                        danger: island.danger
                        metrics: win.metrics
                        opacity: shown ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(footer.shown ? win.metrics.msFadeIn : win.metrics.msFadeOut); easing.type: Easing.OutCubic }
                        }
                    }
                }

                // ---- Dica da faixa ("Captura · 3"), por baixo do notch ----
                Item {
                    id: tip
                    readonly property bool shown: strip.tooltipShown && win.stripOn && strip.tooltipX >= 0
                    property string text: ""
                    property real centerX: 0

                    // Guarda o último texto para o fade de saída não piscar vazio.
                    onShownChanged: if (shown) { text = strip.tooltipText; centerX = strip.tooltipX }
                    Connections {
                        target: strip
                        function onTooltipTextChanged() { if (tip.shown) tip.text = strip.tooltipText }
                        function onTooltipXChanged() { if (tip.shown) tip.centerX = strip.tooltipX }
                    }

                    width: tipText.implicitWidth + 20
                    height: 26
                    x: Math.max(4, Math.min(surface.width - width - 4, pill.x + strip.x + centerX - width / 2))
                    y: pill.y + win.metrics.strip + 6
                    opacity: shown ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: Commons.Style.duration(tip.shown ? 160 : 120); easing.type: Easing.OutCubic }
                    }

                    ContinuousRect {
                        anchors.fill: parent
                        radius: height / 2
                        color: island.bg
                        borderWidth: 1
                        borderColor: Qt.rgba(island.fg.r, island.fg.g, island.fg.b, 0.12)
                    }

                    Text {
                        id: tipText
                        anchors.centerIn: parent
                        text: tip.text
                        color: island.fg
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                }
            }

            function shortcutCategory(digit) {
                island.keyboardMode = true
                island.categoryKey(island.categoryOrder[digit])
            }
        }
    }

    // Um estado carregado de arquivo. Se o arquivo faltar ou quebrar, só
    // aquele estado some; a barra continua de pé.
    //
    // Contrato (tudo opcional além de active/closeRequested/navigate):
    //   entra:  active, fg, bg, accent, danger, shell, metrics, keyboardMode,
//           checkUpdates
    //           (payload no OSD)
    //   sai:    closeRequested(), navigate(target) = trocar de categoria,
    //           footerStatus, footerHints, footerAlert (lidos pelo rodapé),
    //           handleKey(event) → bool, handleEscape() → bool, focusFirst()
    component StateSlot: Item {
        id: slot

        // A janela e a ilha donas (componentes inline não enxergam ids de fora).
        required property var hostWindow
        required property var hostIsland

        property string name: ""
        property string source: ""
        // Só carrega depois que win e island chegaram.
        property bool ready: false
        Component.onCompleted: ready = true
        readonly property Item item: loader.item
        readonly property bool current: slot.hostWindow.mode === name
        readonly property bool shown: current && slot.hostWindow.contentOn

        // Rodapé do painel (vazio se o estado não publicar).
        readonly property string footerStatus: item && item.footerStatus !== undefined ? String(item.footerStatus) : ""
        readonly property string footerHints: item && item.footerHints !== undefined ? String(item.footerHints) : ""
        readonly property bool footerAlert: !!(item && item.footerAlert)

        anchors.horizontalCenter: parent.horizontalCenter
        // Painéis começam abaixo da faixa; o OSD fica centrado na pílula.
        y: name === "osd" ? Math.round((parent.height - height) / 2)
            : slot.hostIsland.metrics.strip + slot.hostIsland.metrics.padTop
        implicitWidth: loader.item ? loader.item.implicitWidth : 0
        implicitHeight: loader.item ? loader.item.implicitHeight : 0
        width: implicitWidth
        height: implicitHeight
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.97
        // Visível já ao entrar (o fade ainda em 0): focusFirst só acha itens visíveis.
        visible: shown || opacity > 0
        enabled: shown

        // Troca de painel: 120 ms saindo, 160 ms entrando.
        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(slot.shown ? slot.hostIsland.metrics.msFadeIn : slot.hostIsland.metrics.msFadeOut); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(slot.shown ? slot.hostIsland.metrics.msFadeIn : slot.hostIsland.metrics.msFadeOut); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }

        Loader {
            id: loader
            anchors.centerIn: parent
            // Só o monitor que mostra painéis mantém os estados.
            active: slot.ready && slot.hostWindow.isTarget && slot.source !== ""
            source: active ? Qt.resolvedUrl(slot.source) : ""
            onLoaded: slot.wire(item)
            onStatusChanged: if (status === Loader.Error) console.warn("ilha: state " + slot.source + " failed to load")
        }

        function bindIfPresent(target, prop, getter) {
            if (prop in target)
                target[prop] = Qt.binding(getter)
        }

        function wire(target) {
            if (!target)
                return
            bindIfPresent(target, "active", () => slot.current)
            // Versão antiga do lançador usa "open" em vez de "active".
            if ("open" in target && typeof target.open !== "function")
                target.open = Qt.binding(() => slot.current)
            bindIfPresent(target, "fg", () => slot.hostIsland.fg)
            bindIfPresent(target, "bg", () => slot.hostIsland.bg)
            bindIfPresent(target, "accent", () => slot.hostIsland.accent)
            bindIfPresent(target, "danger", () => slot.hostIsland.danger)
            bindIfPresent(target, "shell", () => slot.hostIsland.shell)
            bindIfPresent(target, "metrics", () => slot.hostIsland.metrics)
            bindIfPresent(target, "keyboardMode", () => slot.hostIsland.keyboardMode)
            // Testes fora do shell desligam a checagem de atualizações (git fetch).
            bindIfPresent(target, "checkUpdates", () => slot.hostIsland.checkUpdates)
            if (slot.name === "osd")
                bindIfPresent(target, "payload", () => slot.hostIsland.osdPayload)
            if (target.closeRequested)
                target.closeRequested.connect(() => {
                    if (slot.name === "osd")
                        slot.hostIsland.closeOsd()
                    else if (slot.hostIsland.view === slot.name)
                        slot.hostIsland.close()
                })
            // navigate(target) = trocar de categoria (como clicar na faixa).
            if (target.navigate)
                target.navigate.connect(dest => {
                    if (!slot.hostIsland.show(String(dest), slot.hostWindow.screenName))
                        slot.hostIsland.close()
                })
        }
    }
}
