import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons as Commons

// Ilha: plugin de barra (kind "bar") que substitui a barra do Omarchy por uma
// pílula só, no topo, que muda de forma.
//
// Em repouso não aparece nada (só uma bolinha de 8 px se houver indicador
// ligado). Uma faixa invisível de 3 px nos 600 px do centro da borda de cima
// revela a pílula: a bolinha desce, estica até virar a pílula e o conteúdo
// entra. Os painéis (Apps, Controle, Captura, Estilo, Ferramentas,
// Calendário, Energia) e o OSD são estados da mesma pílula.
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
    readonly property int restHeight: 12
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

    // ---- Estados ----
    // Painel aberto: "" ou um destes.
    property string view: ""
    readonly property var views: ["launcher", "control", "capture", "style", "tools", "calendar", "power"]
    // Monitor que mostra painéis, OSD e eventos (só um por vez).
    property string panelScreen: ""

    property var osdPayload: ({})
    property bool osdShown: false
    readonly property bool eventShown: eventTimer.running

    // Atalhos de painel do Omarchy (Super+Ctrl+…) que a ilha atende.
    readonly property var widgetViews: ({
        "omarchy.audio": "control",
        "omarchy.bluetooth": "control",
        "omarchy.network": "tools",
        "omarchy.clock": "calendar",
        "omarchy.power": "power"
    })

    function focusedScreenName() {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            return String(Hyprland.focusedMonitor.name)
        const screens = Quickshell.screens
        return screens.length > 0 ? String(screens[0].name) : ""
    }

    // Abre um estado num monitor (o focado, se não for dito).
    function show(target, screenName) {
        if (views.indexOf(target) < 0)
            return false
        panelScreen = screenName && screenName !== "" ? screenName : focusedScreenName()
        view = target
        return true
    }

    // Alterna: abrir o que já está aberto fecha.
    function toggle(target, screenName) {
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
    Indicators {
        id: indicatorSource
        visible: false
        shell: island.shell
        checkUpdates: island.checkUpdates
        onBecameActive: what => {
            if (what !== "notifications")
                island.revealEvent()
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

        function open(): void { island.show("calendar", "") }
        function close(): void { if (island.view === "calendar") island.close() }
        function show(): void { island.show("calendar", "") }
        function hide(): void { if (island.view === "calendar") island.close() }
        function toggle(): void { island.toggle("calendar", "") }
    }

    // Alvo próprio: omarchy-shell ilha open <estado> | close | osd <json> | state
    Commons.ShellIpc {
        target: "ilha"

        function open(target: string): string {
            return island.toggle(String(target), "") ? "ok" : "unknown"
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
            return JSON.stringify({ view: island.view, osd: island.osdShown, hidden: island.barHidden, screen: island.panelScreen })
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
            readonly property string mode: isTarget && island.view !== "" ? island.view
                : isTarget && island.osdShown ? "osd"
                : hovered ? "hover"
                : isTarget && island.eventShown ? "hover"
                : "rest"
            readonly property bool revealed: mode !== "rest"
            readonly property bool dotVisible: !island.barHidden && indicatorSource.anyActive

            // Tamanho do estado atual.
            readonly property Item modeItem: {
                switch (mode) {
                case "hover": return hoverContent
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
            readonly property bool isPanel: mode !== "hover" && mode !== "osd" && mode !== "rest"
            readonly property real targetWidth: !modeItem ? 12
                : mode === "hover" ? hoverContent.implicitWidth + 32
                : mode === "osd" ? modeItem.implicitWidth + 32
                : modeItem.implicitWidth + 40
            readonly property real targetHeight: !modeItem ? 12
                : mode === "hover" ? 50
                : mode === "osd" ? modeItem.implicitHeight + 16
                : Math.min(modeItem.implicitHeight + 40, win.height - 16)

            // ---- Coreografia ----
            // 0: repouso (sumida ou bolinha); 1: bolinha de 12 px no lugar;
            // 2: esticada no estado atual.
            property int phase: 0
            property bool contentLatched: false
            property string pendingStep: ""
            readonly property bool animate: Commons.Style.duration(1) > 0
            readonly property bool shrinking: phase < 2 || !revealed
            readonly property bool contentOn: phase === 2 && revealed && contentLatched

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
                    if (phase === 0) {
                        phase = 1
                        step("expand", 140)
                    } else {
                        phase = 2
                        Qt.callLater(checkLatch)
                    }
                } else {
                    // Conteúdo some primeiro, depois encolhe e sobe.
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

            Timer {
                id: stepTimer
                onTriggered: {
                    const name = win.pendingStep
                    win.pendingStep = ""
                    if (name === "expand") {
                        win.phase = 2
                        Qt.callLater(win.checkLatch)
                    } else if (name === "shrink") {
                        win.phase = 1
                        win.step("rise", 180)
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

            // ---- Entrada: faixa de ativação + a pílula ----
            // Curva côncava de cada lado do notch, onde ele encontra a tela.
            readonly property real flare: 10
            readonly property int stripWidth: 600
            readonly property int stripHeight: 3
            // A área de entrada segue o tamanho final do estado, não a pílula
            // animada: trocar a máscara a cada quadro faz o compositor mandar
            // saída/entrada do ponteiro e o hover piscar.
            readonly property int inputWidth: revealed ? Math.ceil(targetWidth + 2 * flare) : dotVisible ? 48 : 0
            readonly property int inputHeight: revealed ? Math.ceil(targetHeight) : dotVisible ? 10 : 0

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
                }

                // Esc fecha qualquer painel. Fica na superfície, que é ancestral
                // de todos os estados: um Esc que o estado não tratar sobe até
                // aqui. O lançador trata o Esc no próprio campo.
                Keys.onEscapePressed: island.close()

                // Foco de reserva quando o estado não tem item carregado.
                Item {
                    id: keys
                    focus: true
                }

                // Ao abrir um painel, o foco vai para o próprio estado (setas
                // do calendário, por exemplo); o lançador foca o campo sozinho.
                Connections {
                    target: win
                    function onModeChanged() {
                        if (!win.isTarget || island.view === "" || island.view === "launcher")
                            return
                        Qt.callLater(() => {
                            const slot = win.modeItem
                            const state = slot && slot.item ? slot.item : null
                            if (!state) {
                                keys.forceActiveFocus()
                                return
                            }
                            // Não rouba o foco de um campo que o estado já focou.
                            let focused = keys.Window.activeFocusItem
                            while (focused && focused !== state)
                                focused = focused.parent
                            if (!focused)
                                state.forceActiveFocus()
                        })
                    }
                }

                Item {
                    id: pill

                    readonly property bool asDot: win.phase === 0 && win.dotVisible

                    anchors.horizontalCenter: parent.horizontalCenter
                    // Largura do corpo + as duas curvas côncavas do topo.
                    width: (win.phase === 2 ? win.targetWidth : asDot ? 28 : 40) + 2 * win.flare
                    height: win.phase === 2 ? win.targetHeight : asDot ? 6 : 12
                    // Colado na borda de cima; em repouso fica escondido acima dela.
                    y: win.phase > 0 || asDot ? 0 : -14
                    opacity: win.phase > 0 || asDot ? 1 : 0
                    clip: true

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
                        color: pill.asDot ? indicatorSource.dotColor : island.bg

                        Behavior on color {
                            ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                        }
                    }

                    // ---- Hover: o que está acontecendo | relógio | o que dá para fazer ----
                    Item {
                        id: hoverContent

                        // Cada lado tem a largura do próprio conteúdo: sem espaço vazio.
                        readonly property real gap: 18
                        readonly property bool shown: win.mode === "hover" && win.contentOn

                        anchors.centerIn: parent
                        implicitWidth: leftGroup.implicitWidth + clockBox.implicitWidth + rightGroup.implicitWidth + 2 * gap
                        implicitHeight: 46
                        width: implicitWidth
                        height: implicitHeight
                        opacity: shown ? 1 : 0
                        scale: shown ? 1 : 0.97
                        visible: opacity > 0
                        enabled: shown

                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(hoverContent.shown ? 180 : 120); easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: Commons.Style.duration(hoverContent.shown ? 180 : 120); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                        }

                        Row {
                            id: leftGroup
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Row {
                                id: workspaceRow
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                leftPadding: 4

                                Repeater {
                                    model: Hyprland.workspaces.values.filter(ws => ws.id > 0
                                        && (!ws.monitor || String(ws.monitor.name) === win.screenName))

                                    Item {
                                        id: wsDot
                                        required property var modelData
                                        readonly property bool current: modelData.active

                                        anchors.verticalCenter: parent.verticalCenter
                                        width: current ? 18 : 8
                                        height: 14

                                        Behavior on width {
                                            NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                                        }

                                        ContinuousRect {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width
                                            height: 8
                                            radius: height / 2
                                            color: wsDot.current ? island.accent
                                                : Qt.rgba(island.fg.r, island.fg.g, island.fg.b, wsHover.hovered ? 0.6 : 0.35)
                                        }

                                        HoverHandler {
                                            id: wsHover
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        TapHandler {
                                            onTapped: wsDot.modelData.activate()
                                        }
                                    }
                                }
                            }

                            Indicators {
                                anchors.verticalCenter: parent.verticalCenter
                                source: indicatorSource
                                shell: island.shell
                                fg: island.fg
                                accent: island.accent
                                danger: island.danger
                                onNavigate: target => island.show(target, win.screenName)
                            }
                        }

                        // Relógio no centro: tocar abre o calendário.
                        Item {
                            id: clockBox
                            x: leftGroup.implicitWidth + hoverContent.gap
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: Math.max(timeText.implicitWidth, dateText.implicitWidth) + 16
                            implicitHeight: 40
                            width: implicitWidth
                            height: implicitHeight

                            Accessible.role: Accessible.Button
                            Accessible.name: strings.t("island.calendar")

                            ContinuousRect {
                                anchors.fill: parent
                                radius: 14
                                color: Qt.rgba(island.fg.r, island.fg.g, island.fg.b, 0.10)
                                opacity: clockHover.hovered ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: -1

                                Text {
                                    id: timeText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.locale(Commons.I18n.formatLocale).toString(clock.date, "HH:mm")
                                    color: island.fg
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    textFormat: Text.PlainText
                                }

                                Text {
                                    id: dateText
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.locale(Commons.I18n.formatLocale).toString(clock.date, "ddd, d MMM")
                                    color: Commons.Color.muted
                                    font.pixelSize: 11
                                    textFormat: Text.PlainText
                                }
                            }

                            HoverHandler {
                                id: clockHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: island.show("calendar", win.screenName)
                            }
                        }

                        Row {
                            id: rightGroup
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Repeater {
                                model: [
                                    { icon: "\uDB80\uDC3B", target: "launcher", key: "island.apps" },     // nf-md-apps (U+F003B)
                                    { icon: "\uF1DE", target: "control", key: "island.control" },         // nf-fa-sliders (U+F1DE)
                                    { icon: "\uDB80\uDD00", target: "capture", key: "island.capture" },   // nf-md-camera (U+F0100)
                                    { icon: "\uF1FC", target: "style", key: "island.style" },             // nf-fa-paint_brush (U+F1FC)
                                    { icon: "\uF0AD", target: "tools", key: "island.tools" },             // nf-fa-wrench (U+F0AD)
                                    { icon: "\uF011", target: "power", key: "island.power" }              // nf-fa-power_off (U+F011)
                                ]

                                IconButton {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: modelData.icon
                                    label: strings.t(modelData.key)
                                    fg: island.fg
                                    accent: island.accent
                                    onTapped: island.show(modelData.target, win.screenName)
                                }
                            }
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
                }
            }
        }
    }

    // Um estado carregado de arquivo. Se o arquivo faltar ou quebrar, só
    // aquele estado some; a barra continua de pé.
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

        anchors.centerIn: parent
        implicitWidth: loader.item ? loader.item.implicitWidth : 0
        implicitHeight: loader.item ? loader.item.implicitHeight : 0
        width: implicitWidth
        height: implicitHeight
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.97
        visible: opacity > 0
        enabled: shown

        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(slot.shown ? 180 : 120); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(slot.shown ? 180 : 120); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
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
            if (slot.name === "osd")
                bindIfPresent(target, "payload", () => slot.hostIsland.osdPayload)
            if (target.closeRequested)
                target.closeRequested.connect(() => {
                    if (slot.name === "osd")
                        slot.hostIsland.closeOsd()
                    else if (slot.hostIsland.view === slot.name)
                        slot.hostIsland.close()
                })
            if (target.navigate)
                target.navigate.connect(dest => {
                    if (!slot.hostIsland.show(String(dest), slot.hostWindow.screenName))
                        slot.hostIsland.close()
                })
        }
    }
}
