import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.Commons as Commons

// Faixa fixa do topo da ilha (spec §3.3): aparece no modo hover e em cima de
// todo painel, sempre no mesmo lugar. Três zonas de largura fixa:
//
//   zoneL 216  workspaces →  nome do app focado  ← indicadores (+N)
//   zoneC 104  relógio, no centro exato da tela (tocar = Tempo)
//   zoneR 216  6 vagas de 36: Apps, Controle, Captura, Estilo, Ferramentas, Energia
//
// O nome do app ocupa o espaço que sobra entre workspaces e indicadores, para
// a faixa nunca ter campo vazio sem mexer nos ícones.
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
    property Metrics metrics: Metrics {}

    signal categoryClicked(string target)
    signal categoryDwelled(string target)
    signal workspaceClicked()
    signal indicatorNavigate(string target)

    implicitWidth: metrics.content
    implicitHeight: metrics.strip
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
    readonly property real tooltipX: volumeShown ? centerOf("control") : centerOf(hoverTarget)
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
                    width: current ? 18 : 8
                    height: 22

                    Accessible.role: Accessible.Button
                    Accessible.name: String(modelData.name)

                    Behavior on width {
                        NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                    }

                    ContinuousRect {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 8
                        radius: height / 2
                        color: wsDot.current ? strip.accent
                            : Qt.rgba(strip.fg.r, strip.fg.g, strip.fg.b, wsHover.hovered ? 0.6 : 0.35)

                        Behavior on color {
                            ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
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
            color: strip.muted
            font.pixelSize: 12
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
        readonly property bool active: strip.activeView === "calendar"
        x: strip.metrics.zoneL + (strip.metrics.zoneC - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: strip.metrics.zoneC - 8
        height: 38

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
            spacing: -1

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.locale(Commons.I18n.formatLocale).toString(strip.now, "HH:mm")
                color: clockBox.active ? strip.accent : strip.fg
                font.pixelSize: 15
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
                font.pixelSize: 11
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
                    iconSize: 20
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
        opacity: strip.activeCenter >= 0 ? 1 : 0

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
