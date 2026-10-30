import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons as Commons

// Faixa do topo da ilha. No hover (o caminho vivo) é uma linha só, sem vão:
// workspaces à esquerda, a hora no meio, no máximo dois avisos à direita.
// O workspace ativo é uma cápsula na cor do tema; os outros são pontos.
//
// As três zonas de largura fixa só existem no caminho de menus, que está
// fechado. Elas não desenham os seis destinos juntos.
//
// API pública:
//   screenName: string        monitor desta faixa (workspaces e app focado)
//   activeView: string        painel aberto ("" = nenhum): pílula + cursor (caret)
//   menuMode: bool            painel aberto: repousar 150 ms num ícone troca de painel
//   keyboardMode, altHeld     mostram os dígitos (0–6) dos ícones
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
    // Roda na linha: +1 próximo painel, -1 o anterior.
    signal panelWheel(int step)

    // A faixa de hover não é um menu. Os seis destinos não aparecem nela.
    readonly property bool menus: false

    implicitWidth: menus ? metrics.content : Math.ceil(stateRow.implicitWidth + 28)
    implicitHeight: menus ? metrics.strip : 34
    // A máscara de hover usa a largura final, para a pílula encolher sem o
    // ponteiro cair no papel de parede.
    readonly property real hoverSpan: implicitWidth
    // No painel a linha ocupa a faixa de cima inteira, para a roda pegar
    // mesmo com o ponteiro um pouco ao lado do relógio.
    width: activeView !== "" ? parent.width : implicitWidth
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

    // ---- Áudio (roda sobre o Controle = volume ±5%) ----
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: strip.sink ? [strip.sink] : [] }
    readonly property bool sinkReady: sink !== null && sink.audio !== null
    property real wheelAccum: 0

    function wheelVolume(delta) {
        if (!sinkReady)
            return
        wheelAccum += delta
        const steps = wheelAccum > 0 ? Math.floor(wheelAccum / 120) : Math.ceil(wheelAccum / 120)
        if (steps === 0)
            return
        wheelAccum -= steps * 120
        const next = Math.max(0, Math.min(1, Math.round((sink.audio.volume + steps * 0.05) * 100) / 100))
        sink.audio.volume = next
        volumeFlash.restart()
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

    Timer {
        id: volumeFlash
        interval: 1200
    }

    readonly property bool volumeShown: volumeFlash.running && sinkReady
    readonly property bool tooltipShown: volumeShown || (tipReady && hoverTarget !== "" && !menuMode)
    readonly property real tooltipX: !menus ? width / 2
        : volumeShown ? centerOf("control") : centerOf(hoverTarget)
    readonly property string tooltipText: {
        if (volumeShown) {
            const pct = Math.round(sink.audio.volume * 100)
            return fmt(sink.audio.muted ? "strip.volumeMuted" : "strip.volume", Commons.I18n.formatNumber(pct))
        }
        if (hoverTarget === "")
            return ""
        return fmt(hoverTarget === "control" ? "strip.tooltipVolume" : "strip.tooltip",
            nameOf(hoverTarget), digitOf(hoverTarget))
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
            if (t !== strip.hoverTarget) {
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
        const ws = monitorObj ? monitorObj.activeWorkspace : null
        return ws ? fmt("strip.desktop", String(ws.name)) : ""
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

                // Rolar sobre o Controle ajusta o volume.
                WheelHandler {
                    enabled: slotItem.modelData.target === "control"
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => strip.wheelVolume(event.angleDelta.y)
                }
            }
        }
    }

    // Hover: a linha do vídeo de outubro. Uma pílula, três grupos colados.
    // O ativo cresce numa cápsula com halo; ocupado é ponto claro; vazio é
    // ponto quieto. A hora abre o Tempo. No máximo dois avisos, só o ícone.
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
        if (key === "reminders" || key === "updates" || key === "notifications")
            indicatorNavigate(indicatorSource.ownerOf(key))
        else
            indicatorSource.activate(key)
    }

    Row {
        id: stateRow
        visible: !strip.menus
        anchors.centerIn: parent
        spacing: 12

        Row {
            id: spaceRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Repeater {
                model: strip.spaceCount

                Item {
                    id: wsDot
                    required property int index
                    readonly property int wsId: strip.workspaceBlock * 10 + index + 1
                    readonly property int slot: (wsId - 1) % 10 + 1
                    readonly property var ws: strip.workspaceById(wsId)
                    readonly property bool current: {
                        const mon = strip.monitorObj
                        return mon && mon.activeWorkspace && mon.activeWorkspace.id === wsId
                    }
                    readonly property bool occupied: ws && ws.toplevels
                        && ws.toplevels.values.length > 0

                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 22

                    Accessible.role: Accessible.Button
                    Accessible.name: String(slot)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 16
                        height: 18
                        radius: 8
                        color: strip.accent
                        opacity: wsDot.current ? 0.28 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(wsDot.slot)
                        textFormat: Text.PlainText
                        font.family: strip.fontFamily
                        font.pixelSize: 13
                        font.weight: wsDot.current ? Font.DemiBold : Font.Medium
                        font.features: ({ "tnum": 1 })
                        color: wsDot.current ? strip.accent
                            : Qt.rgba(strip.fg.r, strip.fg.g, strip.fg.b, wsDot.occupied ? 0.9 : 0.38)

                        Behavior on color {
                            ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                        }
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                    TapHandler {
                        onTapped: strip.focusSpace(wsDot.wsId)
                    }
                }
            }
        }

        Text {
            id: stateClock
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.locale(Commons.I18n.formatLocale).toString(strip.now, "HH:mm")
            textFormat: Text.PlainText
            color: strip.fg
            font.family: strip.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })

            Accessible.role: Accessible.Button
            Accessible.name: strip.tr("island.time")

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: strip.categoryClicked("calendar") }
        }

        // Aparência: sempre aqui. A cor é a do tema; o toque abre o Estilo.
        Item {
            id: lookSlot
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18

            Accessible.role: Accessible.Button
            Accessible.name: strip.tr("island.style")

            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: 9
                color: strip.accent
                opacity: strip.activeView === "style" ? 0.28 : 0

                Behavior on opacity {
                    NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                }
            }

            Icon {
                anchors.centerIn: parent
                name: "palette"
                size: 15
                filled: strip.activeView === "style"
                color: strip.accent
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: strip.categoryClicked("style") }
        }

        Row {
            id: statusRow
            visible: strip.statusMarks.length > 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: strip.statusMarks

                Item {
                    id: markSlot
                    required property var modelData
                    readonly property string markKey: modelData.key

                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16

                    Accessible.role: Accessible.Button
                    Accessible.name: strip.tr("indicators.face." + markKey)

                    Icon {
                        anchors.centerIn: parent
                        name: markSlot.modelData.icon
                        size: 15
                        filled: true
                        color: markSlot.modelData.tint
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: strip.activateMark(markSlot.markKey) }
                }
            }
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
    Component.onCompleted: placeCaret()

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
