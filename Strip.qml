import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.Commons as Commons

// Faixa do topo da ilha. No hover (o caminho vivo) é uma linha só, sem vão:
// pontos dos workspaces à esquerda, a hora no centro exato, rede, bateria e
// no máximo dois avisos à direita. O workspace ativo é uma pílula alongada
// no destaque; o nome do layout sai na dica e no nome acessível.
//
// Nível 2 (expanded, depois de ~1 s de hover): cápsula larga de três
// colunas. Esquerda: app focado sobre os pontos. Centro: hora grande e data.
// Direita: estado das notificações sobre rede e bateria.
//
// As três zonas de largura fixa só existem no caminho de menus, que está
// fechado. Elas não desenham os seis destinos juntos.
//
// API pública:
//   screenName: string        monitor desta faixa (workspaces e app focado)
//   activeView: string        painel aberto ("" = nenhum): pílula + cursor (caret)
//   menuMode: bool            painel aberto: repousar 150 ms num ícone troca de painel
//   keyboardMode, altHeld     mostram os dígitos (0–6) dos ícones
//   expanded: bool            hover nível 2 (640 × 80, três colunas)
//   readonly centerClock      o relógio central do nível 1 (o Island alinha o do repouso)
//   indicatorSource           a instância de Indicators que lê o sistema
//   strings                   Commons.Translations da ilha
//   now: date                 hora do relógio
//   fg, bg, accent, danger, muted, metrics
//   readonly tooltipShown, tooltipText, tooltipX   dica para o host desenhar
//       (a faixa fica dentro do notch recortado; a dica sai por baixo dele)
// Sinais:
//   categoryClicked(target)   clique num ícone ou no relógio
//   categoryDwelled(target)   repouso de 150 ms noutro ícone (só em menuMode)
//   workspaceClicked()        trocou de workspace (o host fecha)
//   indicatorNavigate(target) indicador ou "+N" pediu um painel
//   noticeRequested()         toque no sino / no estado das notificações
//   panelWheel(step)          roda: +1 próximo painel, -1 o anterior
Item {
    id: strip

    property string screenName: ""
    property string activeView: ""
    property bool menuMode: false
    property bool keyboardMode: false
    property bool altHeld: false
    property var indicatorSource: null
    property var shell: null
    property var strings: null
    property var now: new Date()
    property bool expanded: false

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property string fontFamily: Commons.Style.fontFamily
    property Metrics metrics: Metrics {}

    signal categoryClicked(string target)
    signal categoryDwelled(string target)
    signal workspaceClicked()
    signal indicatorNavigate(string target)
    signal noticeRequested()
    // Roda na linha: +1 próximo painel, -1 o anterior.
    signal panelWheel(int step)

    // A faixa de hover não é um menu. Os seis destinos não aparecem nela.
    readonly property bool menus: false

    // Nível 1: o relógio no centro exato e os dois grupos a 14 px dele; a
    // largura cobre o lado maior dos dois, mais 18 px de folga de cada lado.
    // Nível 2: 640 × 80.
    implicitWidth: menus ? metrics.content
        : expanded ? 640
        : Math.ceil(stateClock.implicitWidth + 2 * (Math.max(leftGroup.implicitWidth, rightGroup.implicitWidth) + 14) + 36)
    implicitHeight: menus ? metrics.strip : expanded ? 80 : 46
    // A máscara de hover usa a largura final, para a pílula encolher sem o
    // ponteiro cair no papel de parede.
    readonly property real hoverSpan: implicitWidth
    readonly property Item centerClock: stateClock
    width: implicitWidth
    height: implicitHeight

    function tr(key) { return strip.strings ? strip.strings.t(key) : key }
    // tr + arg, sem avisos enquanto o catálogo ainda não carregou.
    function fmt(key, a, b) {
        let text = tr(key)
        if (text.indexOf("%1") < 0)
            return b === undefined ? String(a) : String(a) + " · " + String(b)
        text = text.arg(a)
        return b === undefined || text.indexOf("%2") < 0 ? text : text.arg(b)
    }

    // ---- Categorias (ordem de hoje; dígito = posição) ----
    readonly property var categories: [
        { icon: "apps", target: "launcher", key: "island.apps", digit: "1" },
        { icon: "tune", target: "control", key: "island.control", digit: "2" },
        { icon: "photo_camera", target: "capture", key: "island.capture", digit: "3" },
        { icon: "palette", target: "style", key: "island.style", digit: "4" },
        { icon: "build", target: "tools", key: "island.tools", digit: "5" },
        { icon: "power_settings_new", target: "power", key: "island.power", digit: "6" }
    ]
    readonly property real zoneRX: metrics.zoneL + metrics.zoneC
    readonly property bool showDigits: keyboardMode || altHeld

    function indexOf(target) {
        for (let i = 0; i < categories.length; i++)
            if (categories[i].target === target)
                return i
        return -1
    }

    // Centro x (coordenadas da faixa) de um alvo; -1 se não for da faixa.
    function centerOf(target) {
        if (target === "calendar")
            return metrics.zoneL + metrics.zoneC / 2
        const i = indexOf(target)
        return i < 0 ? -1 : zoneRX + i * metrics.iconSlot + metrics.iconSlot / 2
    }

    // Alvo sob um ponto da faixa ("" fora do relógio e dos ícones).
    function targetAt(x, y) {
        if (!menus)
            return ""
        if (x >= metrics.zoneL && x < zoneRX)
            return "calendar"
        if (x >= zoneRX && x < zoneRX + metrics.zoneR) {
            const i = Math.floor((x - zoneRX) / metrics.iconSlot)
            return i >= 0 && i < categories.length ? categories[i].target : ""
        }
        return ""
    }

    function nameOf(target) {
        if (target === "calendar")
            return tr("island.time")
        const i = indexOf(target)
        return i < 0 ? "" : tr(categories[i].key)
    }

    function digitOf(target) {
        if (target === "calendar")
            return "0"
        const i = indexOf(target)
        return i < 0 ? "" : categories[i].digit
    }

    // Uma volta da roda troca um painel. O resto do gesto fica para a próxima.
    property real panelWheelAccum: 0

    function wheelPanels(delta) {
        panelWheelAccum += delta
        if (panelWheelAccum >= 120) {
            panelWheelAccum = 0
            panelWheel(-1)
        } else if (panelWheelAccum <= -120) {
            panelWheelAccum = 0
            panelWheel(1)
        }
    }

    // ---- Dicas ("Nome · dígito") ----
    property string hoverTarget: ""
    property bool tipReady: false

    // Intervalos de comportamento, não de animação: ficam fixos mesmo com as
    // animações desligadas (com 0 ms o repouso trocaria de painel ao passar).
    Timer {
        id: tipTimer
        interval: strip.metrics.msTooltip
        onTriggered: strip.tipReady = true
    }

    // Na linha de hover a única dica é o layout do workspace ativo
    // (hoverTarget "layout"), posta pela pílula do workspace.
    property real layoutTipX: -1

    function layoutTip(item, on) {
        if (menus)
            return
        if (on) {
            const p = item.mapToItem(strip, item.width / 2, 0)
            layoutTipX = p.x
            hoverTarget = "layout"
            tipReady = false
            tipTimer.restart()
        } else if (hoverTarget === "layout") {
            tipTimer.stop()
            tipReady = false
            hoverTarget = ""
        }
    }

    readonly property bool tooltipShown: tipReady && hoverTarget !== "" && !menuMode && tooltipText !== ""
    readonly property real tooltipX: hoverTarget === "layout" ? layoutTipX
        : !menus ? width / 2 : centerOf(hoverTarget)
    readonly property string tooltipText: {
        if (hoverTarget === "")
            return ""
        if (hoverTarget === "layout")
            return layoutName(spaceMode)
        return fmt("strip.tooltip", nameOf(hoverTarget), digitOf(hoverTarget))
    }

    // ---- Repouso (dwell): só em menuMode; descer o ponteiro cancela ----
    property string dwellTarget: ""
    property real lastY: -1
    // O repouso só vale depois de o ponteiro se mexer de verdade: um cursor
    // parado sobre a faixa (o painel abriu por tecla ou IPC embaixo dele)
    // não troca de painel sozinho.
    property real anchorX: -1
    property real anchorY: -1
    property bool pointerMoved: false

    Timer {
        id: dwellTimer
        interval: strip.metrics.msDwell
        onTriggered: {
            if (strip.menuMode && strip.dwellTarget !== "" && strip.dwellTarget !== strip.activeView)
                strip.categoryDwelled(strip.dwellTarget)
        }
    }

    HoverHandler {
        id: stripHover
        onHoveredChanged: {
            if (!hovered) {
                dwellTimer.stop()
                tipTimer.stop()
                strip.tipReady = false
                strip.hoverTarget = ""
                strip.dwellTarget = ""
                strip.lastY = -1
                strip.anchorX = -1
                strip.pointerMoved = false
            }
        }
        onPointChanged: {
            if (!hovered)
                return
            const p = point.position
            const t = strip.targetAt(p.x, p.y)
            if (strip.menus && t !== strip.hoverTarget) {
                strip.hoverTarget = t
                strip.tipReady = false
                if (t !== "")
                    tipTimer.restart()
                else
                    tipTimer.stop()
            }
            if (strip.anchorX < 0) {
                strip.anchorX = p.x
                strip.anchorY = p.y
            } else if (!strip.pointerMoved
                       && Math.abs(p.x - strip.anchorX) + Math.abs(p.y - strip.anchorY) > 3) {
                strip.pointerMoved = true
            }
            const down = strip.lastY >= 0 && p.y > strip.lastY + 0.5
            strip.lastY = p.y
            if (!strip.pointerMoved) {
                strip.dwellTarget = t
                dwellTimer.stop()
                return
            }
            if (t !== strip.dwellTarget) {
                strip.dwellTarget = t
                if (strip.menuMode && t !== "" && t !== strip.activeView && !down)
                    dwellTimer.restart()
                else
                    dwellTimer.stop()
            } else if (down) {
                // A caminho do painel: não troca.
                dwellTimer.stop()
            } else if (strip.menuMode && t !== "" && t !== strip.activeView && !dwellTimer.running) {
                dwellTimer.restart()
            }
        }
    }

    onMenuModeChanged: if (!menuMode) dwellTimer.stop()
    onActiveViewChanged: {
        dwellTimer.stop()
        // Painel trocado por tecla/IPC: exige movimento novo antes do repouso.
        if (keyboardMode) {
            anchorX = -1
            pointerMoved = false
        }
    }

    // ================= zoneL =================
    Item {
        id: zoneL
        visible: strip.menus
        enabled: strip.menus
        x: 0
        width: strip.metrics.zoneL
        height: parent.height
        clip: true

        Row {
            id: workspaceRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            leftPadding: 4

            Repeater {
                model: Hyprland.workspaces.values.filter(ws => ws.id > 0
                    && (!ws.monitor || String(ws.monitor.name) === strip.screenName))

                Item {
                    id: wsDot
                    required property var modelData
                    readonly property bool current: modelData.active

                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 22

                    Accessible.role: Accessible.Button
                    Accessible.name: String(modelData.name)

                    // Ponto, nunca uma pílula larga: um workspace só não pode
                    // parecer um interruptor ao lado do nome do app.
                    Rectangle {
                        anchors.centerIn: parent
                        width: wsDot.current ? 7 : 5
                        height: width
                        radius: width / 2
                        color: wsDot.current ? strip.accent
                            : Qt.rgba(strip.fg.r, strip.fg.g, strip.fg.b, wsHover.hovered ? 0.55 : 0.28)

                        Behavior on color {
                            ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                        }
                        Behavior on width {
                            NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                        }
                    }

                    HoverHandler {
                        id: wsHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            wsDot.modelData.activate()
                            strip.workspaceClicked()
                        }
                    }
                }
            }
        }

        // Indicadores colados no relógio, em vagas de 24 px.
        Indicators {
            id: indicators
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            source: strip.indicatorSource
            shell: strip.shell
            fg: strip.fg
            accent: strip.accent
            danger: strip.danger
            muted: strip.muted
            slot: 24
            capacity: Math.max(0, Math.floor((strip.metrics.zoneL - workspaceRow.width - 8) / slot))
            onNavigate: target => strip.indicatorNavigate(target)
        }

        // App focado: preenche o vão entre workspaces e indicadores.
        Text {
            id: appName
            readonly property real startX: workspaceRow.width + 10
            readonly property real endX: indicators.visible ? indicators.x - 6 : zoneL.width - 6
            x: startX
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, endX - startX)
            visible: width >= 24 && text !== ""
            text: strip.appLabel
            color: strip.fg
            opacity: 0.88
            font.pixelSize: 13
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
        }
    }

    // ---- Nome do app focado neste monitor ----
    readonly property var monitorObj: {
        const list = Hyprland.monitors.values
        for (let i = 0; i < list.length; i++)
            if (String(list[i].name) === strip.screenName)
                return list[i]
        return null
    }
    readonly property var focusedToplevel: {
        const t = Hyprland.activeToplevel
        if (t && t.monitor && String(t.monitor.name) === strip.screenName)
            return t
        const ws = monitorObj ? monitorObj.activeWorkspace : null
        const list = ws && ws.toplevels ? ws.toplevels.values : []
        return list.length > 0 ? list[0] : null
    }

    function prettyApp(t) {
        if (!t)
            return ""
        const title = String(t.title || "").trim()
        const cls = t.wayland && t.wayland.appId ? String(t.wayland.appId)
            : (t.lastIpcObject && t.lastIpcObject["class"] ? String(t.lastIpcObject["class"]) : "")
        // Web apps do navegador têm classe gerada ("chrome-site__-Default"): o título diz mais.
        if (cls === "" || /^(chrome|chromium|brave|msedge|vivaldi)-/.test(cls))
            return title
        const name = cls.split(".").pop().replace(/[-_]+/g, " ").trim()
        if (name === "")
            return title
        return name.charAt(0).toUpperCase() + name.slice(1)
    }

    readonly property string appLabel: {
        const name = prettyApp(focusedToplevel)
        if (name !== "")
            return name
        return tr("strip.desktop")
    }

    // Classe do app focado, para achar o ícone no .desktop.
    readonly property string appClass: {
        const t = focusedToplevel
        if (!t)
            return ""
        return t.wayland && t.wayland.appId ? String(t.wayland.appId)
            : (t.lastIpcObject && t.lastIpcObject["class"] ? String(t.lastIpcObject["class"]) : "")
    }
    readonly property string appIcon: {
        if (appClass === "")
            return ""
        const entry = DesktopEntries.heuristicLookup(appClass)
        const name = entry && entry.icon ? String(entry.icon) : ""
        return name !== "" ? Quickshell.iconPath(name, true) : ""
    }

    // ---- Rede (Quickshell.Networking, o mesmo critério do Controle) ----
    readonly property var netDevices: Networking.devices ? Networking.devices.values : []
    function findDevice(type) {
        const devices = strip.netDevices || []
        let fallback = null
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i]
            if (!d || d.type !== type)
                continue
            if (d.connected)
                return d
            if (!fallback)
                fallback = d
        }
        return fallback
    }
    function connectedNetwork(device) {
        if (!device || !device.networks)
            return null
        const list = device.networks.values || []
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].connected)
                return list[i]
        return null
    }
    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wifiNetwork: connectedNetwork(wifiDevice)
    readonly property string netKind: {
        if (wiredDevice && wiredDevice.connected) return "ethernet"
        if (wifiNetwork || (wifiDevice && wifiDevice.connected)) return "wifi"
        return "disconnected"
    }
    // Barras acesas (0–4). Sinal desconhecido com Wi-Fi conectado: cheio.
    readonly property int netBars: {
        if (netKind !== "wifi")
            return 0
        const strength = wifiNetwork && wifiNetwork.signalStrength > 0 ? wifiNetwork.signalStrength : 0
        return strength > 0 ? Math.max(1, Math.min(4, Math.ceil(strength * 4))) : 4
    }

    // ---- Bateria (UPower) ----
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(battery && battery.isLaptopBattery)
    readonly property real batteryLevel: hasBattery ? Math.max(0, Math.min(1, battery.percentage)) : 0
    readonly property bool charging: hasBattery && (battery.state === UPowerDeviceState.Charging
        || battery.state === UPowerDeviceState.FullyCharged
        || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool batteryLow: hasBattery && batteryLevel < 0.15 && !charging

    readonly property int notificationCount: indicatorSource ? indicatorSource.notificationCount : 0
    readonly property bool dndOn: !!(indicatorSource && indicatorSource.dnd)
    readonly property string noticeText: {
        if (notificationCount > 0) {
            const form = strip.strings ? strip.strings.tn("strip.notifications", notificationCount) : "%1"
            return form.indexOf("%1") >= 0 ? form.arg(Commons.I18n.formatNumber(notificationCount)) : form
        }
        return tr("strip.caughtUp")
    }

    // ================= zoneC: relógio =================
    Item {
        id: clockBox
        visible: strip.menus
        enabled: strip.menus
        readonly property bool active: strip.activeView === "calendar"
        x: strip.metrics.zoneL + (strip.metrics.zoneC - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: strip.metrics.zoneC - 8
        height: 42

        Accessible.role: Accessible.Button
        Accessible.name: strip.tr("island.time")

        ContinuousRect {
            anchors.fill: parent
            radius: height / 2
            color: clockBox.active ? Qt.rgba(strip.accent.r, strip.accent.g, strip.accent.b, strip.metrics.alphaPill)
                                   : Qt.rgba(strip.fg.r, strip.fg.g, strip.fg.b, strip.metrics.alphaHover)
            opacity: clockBox.active || clockHover.hovered ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale(Commons.I18n.formatLocale).toString(strip.now, "HH:mm")
                color: clockBox.active ? strip.accent : strip.fg
                font.pixelSize: 18
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
                textFormat: Text.PlainText

                Behavior on color {
                    ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale(Commons.I18n.formatLocale).toString(strip.now, "ddd, d MMM")
                color: strip.muted
                font.pixelSize: 10
                font.letterSpacing: 0.2
                textFormat: Text.PlainText
            }
        }

        scale: clockTap.pressed ? 0.97 : 1
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(120); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }

        KeyBadge {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: 2
            letter: "0"
            keyboardMode: true
            strong: clockBox.active
            fg: strip.fg
            bg: strip.bg
            accent: strip.accent
            muted: strip.muted
            metrics: strip.metrics
            opacity: strip.showDigits ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
            }
        }

        HoverHandler {
            id: clockHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: clockTap
            onTapped: strip.categoryClicked("calendar")
        }
    }

    // ================= zoneR: 6 vagas fixas =================
    Row {
        id: zoneR
        visible: strip.menus
        enabled: strip.menus
        x: strip.zoneRX
        width: strip.metrics.zoneR
        height: parent.height

        Repeater {
            model: strip.categories

            Item {
                id: slotItem
                required property var modelData
                required property int index
                readonly property bool active: strip.activeView === modelData.target

                width: strip.metrics.iconSlot
                height: parent.height

                IconButton {
                    anchors.centerIn: parent
                    size: strip.metrics.iconSlot
                    iconSize: 18
                    icon: slotItem.modelData.icon
                    label: strip.nameOf(slotItem.modelData.target)
                    highlighted: slotItem.active
                    caption: strip.showDigits ? slotItem.modelData.digit : ""
                    muted: strip.muted
                    fg: strip.fg
                    accent: strip.accent
                    onTapped: strip.categoryClicked(slotItem.modelData.target)
                }

            }
        }
    }

    // Bloco de workspaces deste monitor (1–10, 11–20, …), o mesmo arquivo
    // que a barra do Omarchy lê.
    property var workspaceBlocks: ({})

    function readBlocks(text) {
        const next = {}
        const lines = String(text || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const fields = lines[i].split("\t")
            if (fields.length >= 2 && fields[1] !== "")
                next[fields[1]] = parseInt(fields[0], 10)
        }
        workspaceBlocks = next
    }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: strip.readBlocks(text())
        onLoadFailed: strip.readBlocks("")
    }

    readonly property int workspaceBlock: {
        const known = workspaceBlocks[screenName]
        if (known !== undefined && !isNaN(known))
            return known
        const mon = monitorObj
        const active = mon && mon.activeWorkspace ? mon.activeWorkspace.id : 1
        return active > 0 ? Math.floor((active - 1) / 10) : 0
    }

    // Os cinco primeiros do monitor, e mais um se já existir além deles.
    readonly property int spaceCount: {
        const base = workspaceBlock * 10
        let n = 5
        const src = Hyprland.workspaces.values
        for (let i = 0; i < src.length; i++) {
            const id = src[i].id
            if (id <= base || id > base + 10)
                continue
            if (src[i].monitor && String(src[i].monitor.name) !== screenName)
                continue
            n = Math.max(n, id - base)
        }
        return n
    }

    function workspaceById(id) {
        const src = Hyprland.workspaces.values
        for (let i = 0; i < src.length; i++)
            if (src[i].id === id)
                return src[i]
        return null
    }

    function focusSpace(id) {
        const slot = (id - 1) % 10 + 1
        const name = String(screenName || "").replace(/["\\]/g, "")
        Quickshell.execDetached(["hyprctl", "dispatch",
            "o.workspaces.focus(" + slot + ", \"" + name + "\")"])
        workspaceClicked()
    }

    // Layout do workspace ativo: dwindle (mosaico), scrolling (rolagem)
    // ou floating. O clique no número ativo percorre os três, como Super + L.
    property string spaceMode: ""
    property int spaceModeTick: 0
    property var modeCache: ({})
    property int modeWs: -1
    property int modeGen: 0
    property int modeProcGen: 0
    property bool modeStale: false
    property bool modeKnown: false

    function layoutName(mode) {
        if (mode === "scrolling") return tr("island.layout.scrolling")
        if (mode === "floating") return tr("island.layout.floating")
        if (mode === "dwindle") return tr("island.layout.dwindle")
        return ""
    }
    function showSpaceMode() {
        const mon = monitorObj
        const id = mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1
        if (id < 1) return
        const cached = modeCache[String(id)]
        if (cached) {
            spaceMode = cached
            modeKnown = true
            return
        }
        readSpaceMode()
    }
    function refreshSpaceModes() {
        modeGen++
        modeCache = ({})
        readSpaceMode()
    }
    function readSpaceMode() {
        if (modeProc.running) {
            modeStale = true
            return
        }
        const mon = monitorObj
        const id = mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1
        if (id < 1) return
        modeWs = id
        modeProcGen = modeGen
        modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
        modeProc.running = true
    }
    function rememberMode(id, mode) {
        const next = Object.assign({}, modeCache)
        next[String(id)] = mode
        modeCache = next
        const mon = monitorObj
        const active = mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1
        if (active === id) {
            spaceMode = mode
            modeKnown = true
        }
    }
    function cycleSpace() {
        const mon = monitorObj
        const name = String(screenName || "").replace(/["\\]/g, "")
        modeGen++
        if (modeKnown) {
            const order = ["dwindle", "scrolling", "floating"]
            const at = order.indexOf(spaceMode)
            const next = order[(at < 0 ? 0 : at + 1) % order.length]
            const id = mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1
            if (id > 0) rememberMode(id, next)
            else spaceMode = next
        }
        if (mon && !mon.focused && name !== "") {
            Quickshell.execDetached(["sh", "-c",
                "hyprctl dispatch 'hl.dsp.focus({ monitor = \"" + name + "\" })' >/dev/null && exec omarchy-hyprland-workspace-layout-toggle"])
        } else {
            Quickshell.execDetached(["omarchy-hyprland-workspace-layout-toggle"])
        }
    }

    onSpaceModeTickChanged: if (spaceModeTick > 0) refreshSpaceModes()
    onMonitorObjChanged: showSpaceMode()

    Connections {
        target: strip.monitorObj
        ignoreUnknownSignals: true
        function onActiveWorkspaceChanged() { strip.showSpaceMode() }
    }

    Process {
        id: modeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const mode = text.trim()
                if (strip.modeProcGen !== strip.modeGen) return
                if (mode !== "dwindle" && mode !== "scrolling" && mode !== "floating") return
                strip.rememberMode(strip.modeWs, mode)
            }
        }
        onExited: {
            if (!strip.modeStale) return
            strip.modeStale = false
            Qt.callLater(strip.readSpaceMode)
        }
    }
    readonly property var statusMarks: {
        const src = indicatorSource
        const list = src && src.items ? src.items : []
        const out = []
        const n = Math.min(2, list.length)
        for (let i = 0; i < n; i++)
            out.push(list[i])
        return out
    }

    function activateMark(key) {
        if (!indicatorSource)
            return
        if (key === "notifications") {
            noticeRequested()
            return
        }
        if (key === "reminders" || key === "updates")
            indicatorNavigate(indicatorSource.ownerOf(key))
        else
            indicatorSource.activate(key)
    }

    // ================= Hover nível 1 =================
    // O relógio no centro exato; os grupos se penduram nele a 14 px.
    Item {
        id: stateRow
        visible: !strip.menus && opacity > 0
        enabled: !strip.menus && !strip.expanded
        anchors.fill: parent
        opacity: strip.expanded ? 0 : 1

        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(strip.expanded ? strip.metrics.msFadeOut : strip.metrics.msFadeIn); easing.type: Easing.OutCubic }
        }

        Text {
            id: stateClock
            anchors.centerIn: parent
            text: Qt.locale(Commons.I18n.formatLocale).toString(strip.now, "HH:mm")
            textFormat: Text.PlainText
            color: strip.fg
            font.family: strip.fontFamily
            font.pixelSize: 16
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })

            Accessible.role: Accessible.Button
            Accessible.name: strip.tr("island.time")

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: strip.categoryClicked("calendar") }
        }

        Row {
            id: leftGroup
            anchors.right: stateClock.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter

            SpaceDots { host: strip }
        }

        Row {
            id: rightGroup
            anchors.left: stateClock.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            NetGlyph { anchors.verticalCenter: parent.verticalCenter; host: strip }
            BatteryGlyph { anchors.verticalCenter: parent.verticalCenter; host: strip }

            StatusMarks { anchors.verticalCenter: parent.verticalCenter; host: strip }
        }
    }

    // ================= Hover nível 2 =================
    // Três colunas ancoradas (folga 22, linhas a 6 px), em fade cruzado com
    // a linha de cima enquanto a pílula cresce.
    Item {
        id: wideRow
        visible: !strip.menus && opacity > 0
        enabled: !strip.menus && strip.expanded
        anchors.fill: parent
        opacity: strip.expanded ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(strip.expanded ? strip.metrics.msFadeIn : strip.metrics.msFadeOut); easing.type: Easing.OutCubic }
        }

        // Esquerda: app focado sobre os pontos dos workspaces.
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Row {
                spacing: 8

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16

                    Image {
                        id: appImage
                        anchors.fill: parent
                        source: strip.appIcon
                        sourceSize.width: 32
                        sourceSize.height: 32
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: source !== "" && status === Image.Ready
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !appImage.visible
                        name: "apps"
                        size: 15
                        color: strip.muted
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 180)
                    text: strip.appLabel
                    color: strip.fg
                    font.family: strip.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                }
            }

            SpaceDots { host: strip }
        }

        // Centro: hora grande e a data, mais apagada, na mesma linha de base.
        Row {
            anchors.centerIn: parent
            spacing: 10

            Text {
                id: wideClock
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.locale(Commons.I18n.formatLocale).toString(strip.now, "HH:mm")
                textFormat: Text.PlainText
                color: strip.fg
                font.family: strip.fontFamily
                font.pixelSize: 26
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })

                Accessible.role: Accessible.Button
                Accessible.name: strip.tr("island.time")

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: strip.categoryClicked("calendar") }
            }

            Text {
                anchors.baseline: wideClock.baseline
                text: Qt.locale(Commons.I18n.formatLocale).toString(strip.now, "ddd, d MMM")
                textFormat: Text.PlainText
                color: Qt.rgba(strip.fg.r, strip.fg.g, strip.fg.b, 0.6)
                font.family: strip.fontFamily
                font.pixelSize: 13
            }
        }

        // Direita: notificações sobre rede e bateria.
        Column {
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Row {
                id: noticeLine
                anchors.right: parent.right
                spacing: 6

                Accessible.role: Accessible.Button
                Accessible.name: strip.noticeText

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: strip.noticeText
                    color: Qt.rgba(strip.fg.r, strip.fg.g, strip.fg.b, 0.85)
                    font.family: strip.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    font.features: ({ "tnum": 1 })
                    textFormat: Text.PlainText
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: strip.notificationCount === 0 && strip.dndOn ? "notifications_off" : "notifications"
                    size: 15
                    filled: strip.notificationCount > 0
                    color: Qt.rgba(strip.fg.r, strip.fg.g, strip.fg.b, 0.85)
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: strip.noticeRequested() }
            }

            Row {
                anchors.right: parent.right
                spacing: 8

                NetGlyph { anchors.verticalCenter: parent.verticalCenter; host: strip }
                BatteryGlyph { anchors.verticalCenter: parent.verticalCenter; host: strip }
                // As mesmas marcas do nível 1: o toque para desligar não some
                // quando a pílula cresce.
                StatusMarks { anchors.verticalCenter: parent.verticalCenter; host: strip }
            }
        }
    }

    // ---- Peças da linha (componentes: os dois níveis usam as mesmas) ----
    // Componentes inline não enxergam os ids de fora: tudo passa por host.

    // Marcas de estado vivas (gravando, não perturbe, acordado…): tocar
    // desliga ou abre o dono. Até duas, nos dois níveis de hover.
    component StatusMarks: Row {
        id: marks
        property var host: null
        visible: host && host.statusMarks.length > 0
        spacing: 8

        Repeater {
            model: marks.host ? marks.host.statusMarks : []

            Item {
                id: markSlot
                required property var modelData
                readonly property string markKey: modelData.key

                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16

                Accessible.role: Accessible.Button
                Accessible.name: marks.host.tr("indicators.face." + markKey)

                Icon {
                    anchors.centerIn: parent
                    name: markSlot.modelData.icon
                    size: 15
                    filled: true
                    color: markSlot.modelData.tint
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: marks.host.activateMark(markSlot.markKey) }
            }
        }
    }

    // Pontos dos workspaces: o ativo é uma pílula alongada no destaque;
    // ocupado é ponto claro, vazio é ponto quieto. Tocar troca; tocar no
    // ativo percorre os layouts (o nome sai na dica).
    component SpaceDots: Row {
        id: dots
        property var host: null
        spacing: 4

        Repeater {
            model: dots.host ? dots.host.spaceCount : 0

            Item {
                id: wsDot
                required property int index
                readonly property var host: dots.host
                readonly property int wsId: host.workspaceBlock * 10 + index + 1
                readonly property int slot: (wsId - 1) % 10 + 1
                readonly property var ws: host.workspaceById(wsId)
                readonly property bool current: {
                    const mon = host.monitorObj
                    return !!(mon && mon.activeWorkspace && mon.activeWorkspace.id === wsId)
                }
                readonly property bool occupied: !!(ws && ws.toplevels && ws.toplevels.values.length > 0)

                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 22

                Accessible.role: Accessible.Button
                Accessible.name: current && host.layoutName(host.spaceMode) !== ""
                    ? String(slot) + ", " + host.layoutName(host.spaceMode)
                    : String(slot)

                Rectangle {
                    anchors.centerIn: parent
                    width: wsDot.current ? 8 : 6
                    height: wsDot.current ? 18 : 10
                    radius: width / 2
                    color: wsDot.current ? wsDot.host.accent
                        : Qt.rgba(wsDot.host.fg.r, wsDot.host.fg.g, wsDot.host.fg.b, wsDot.occupied ? 0.55 : 0.22)

                    Behavior on width {
                        NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                    }
                    Behavior on height {
                        NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                    }
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: wsDot.host.layoutTip(wsDot, hovered && wsDot.current)
                }

                TapHandler {
                    onTapped: {
                        if (wsDot.current) wsDot.host.cycleSpace()
                        else wsDot.host.focusSpace(wsDot.wsId)
                    }
                }
            }
        }
    }

    // Rede: quatro barras (acesas em fg, apagadas em fg 0.25); cabo vira o
    // ícone "lan"; sem rede, as quatro apagadas.
    component NetGlyph: Item {
        id: net
        property var host: null
        readonly property bool wired: !!host && host.netKind === "ethernet"

        width: wired ? 15 : bars.width
        height: 15

        Accessible.role: Accessible.StaticText
        Accessible.name: net.host ? net.host.netKind : ""

        Icon {
            anchors.centerIn: parent
            visible: net.wired
            name: "lan"
            size: 15
            color: net.host ? net.host.fg : "transparent"
        }

        Row {
            id: bars
            visible: !net.wired
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            spacing: 2

            Repeater {
                model: 4

                Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width: 3
                    height: 4 + index * 3
                    radius: net.host ? net.host.metrics.fit(1.5) : 1.5
                    color: !net.host ? "transparent"
                        : index < net.host.netBars ? net.host.fg
                        : Qt.rgba(net.host.fg.r, net.host.fg.g, net.host.fg.b, 0.25)

                    Behavior on color {
                        ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    // Bateria: contorno de 22 × 11, preenchimento sólido no destaque
    // (urgente abaixo de 15% sem carregar) e o pino de 2 × 5.
    component BatteryGlyph: Item {
        id: batt
        property var host: null

        visible: !!host && host.hasBattery
        width: 25
        height: 11

        Accessible.role: Accessible.StaticText
        Accessible.name: batt.host && batt.host.hasBattery
            ? Commons.I18n.formatNumber(Math.round(batt.host.batteryLevel * 100)) + "%" : ""

        ContinuousRect {
            id: battShell
            x: 0
            width: 22
            height: 11
            radius: batt.host ? batt.host.metrics.fit(3.5) : 3.5
            color: "transparent"
            borderWidth: 1
            borderColor: batt.host ? Qt.rgba(batt.host.fg.r, batt.host.fg.g, batt.host.fg.b, 0.35) : "transparent"
        }

        ContinuousRect {
            x: 2
            anchors.verticalCenter: battShell.verticalCenter
            width: batt.host ? Math.max(0, (battShell.width - 4) * batt.host.batteryLevel) : 0
            height: battShell.height - 4
            radius: batt.host ? batt.host.metrics.fit(2) : 2
            visible: width > 0.5
            color: !batt.host ? "transparent" : batt.host.batteryLow ? batt.host.danger : batt.host.accent

            Behavior on width {
                NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            x: 23
            anchors.verticalCenter: battShell.verticalCenter
            width: 2
            height: 5
            radius: batt.host ? batt.host.metrics.fit(1) : 1
            color: batt.host ? Qt.rgba(batt.host.fg.r, batt.host.fg.g, batt.host.fg.b, 0.35) : "transparent"
        }
    }

    // Roda na linha troca o painel. As listas de dentro ficam de fora daqui.
    WheelHandler {
        enabled: !strip.menus
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => strip.wheelPanels(event.angleDelta.y)
    }

    // ================= Cursor do painel ativo =================
    readonly property real activeCenter: centerOf(activeView)
    property real caretX: -1
    property bool caretGlide: false

    function placeCaret() {
        const c = activeCenter
        if (c < 0) {
            caretGlide = false
            return
        }
        // Só desliza de um ícone para outro; ao aparecer, nasce no lugar.
        caretGlide = caret.opacity > 0.5 && caretX >= 0
        caretX = c
    }
    onActiveCenterChanged: placeCaret()
    Component.onCompleted: {
        showSpaceMode()
        placeCaret()
    }

    ContinuousRect {
        id: caret
        width: strip.metrics.caretWidth
        height: strip.metrics.caretHeight
        radius: height / 2
        y: strip.height - height
        x: strip.caretX - width / 2
        color: strip.accent
        opacity: strip.menus && strip.activeCenter >= 0 ? 1 : 0

        Behavior on x {
            enabled: strip.caretGlide && Commons.Style.duration(1) > 0
            // A mesma mola da ilha ao crescer (medida: chega sem passar do alvo).
            SpringAnimation { spring: 6; damping: 0.5; epsilon: 0.25 }
        }
        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
        }
    }
}
