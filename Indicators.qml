import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Fileira de indicadores da ilha. Só aparece o que está ligado, e tocar
// resolve: para a gravação, tira o Não perturbe, abre Ferramentas…
//
// Fontes (ver o plano):
// - Não perturbe, luz noturna, manter acordado: proxies do shell
//   (shell.firstPartyServiceFor). Sem shell (fora do Omarchy, no teste),
//   lê os comandos de status somente leitura.
// - Gravando: omarchy-capture-screenrecording --status (0 = gravando).
// - Lembretes: omarchy-reminder show --json.
// - Atualizações: omarchy-update-available (0 = há atualização).
// - Notificações na tela: ~/.local/state/omarchy/notifications/live.json.
Item {
    id: root

    property var shell: null
    property color fg: Commons.Color.bar.text
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    // Verificar atualizações (faz git fetch no checkout de desenvolvimento).
    property bool checkUpdates: true
    // Outra instância que já lê o sistema. Com ela, esta só desenha a
    // fileira (uma por monitor) e não roda nenhum processo.
    property var source: null
    readonly property bool reads: source === null

    // Um indicador passou de desligado para ligado depois da primeira
    // leitura: "recording", "dnd", "nightlight", "stayAwake", "reminders",
    // "updates" ou "notifications".
    signal becameActive(string what)
    signal navigate(string target)

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    readonly property string home: Quickshell.env("HOME")
    readonly property string notificationsDir: home + "/.local/state/omarchy/notifications"

    // Proxies do shell. Cada um pode ser nulo.
    function serviceFor(id) {
        if (!root.shell || typeof root.shell.firstPartyServiceFor !== "function")
            return null
        try {
            return root.shell.firstPartyServiceFor(id) || null
        } catch (e) {
            return null
        }
    }
    readonly property var notificationService: serviceFor("omarchy.notifications")
    readonly property var idleService: serviceFor("omarchy.idle")
    readonly property var nightlightService: serviceFor("omarchy.nightlight")

    // Leituras de reserva quando não há proxy.
    property bool fallbackDnd: false
    property bool fallbackStayAwake: false
    property bool fallbackNightlight: false

    readonly property bool ownDnd: notificationService ? notificationService.doNotDisturb : fallbackDnd
    readonly property bool ownStayAwake: idleService ? idleService.stayAwake : fallbackStayAwake
    readonly property bool ownNightlight: nightlightService ? nightlightService.enabled : fallbackNightlight

    property bool ownRecording: false
    property int ownReminderCount: 0
    property bool ownUpdateAvailable: false
    property int ownNotificationCount: 0
    property string ownNotificationApp: ""

    // O que vale: o da fonte, se houver, ou o lido aqui.
    readonly property bool dnd: source ? source.dnd : ownDnd
    readonly property bool stayAwake: source ? source.stayAwake : ownStayAwake
    readonly property bool nightlight: source ? source.nightlight : ownNightlight
    readonly property bool recording: source ? source.recording : ownRecording
    readonly property int reminderCount: source ? source.reminderCount : ownReminderCount
    readonly property bool updateAvailable: source ? source.updateAvailable : ownUpdateAvailable
    readonly property int notificationCount: source ? source.notificationCount : ownNotificationCount
    readonly property string notificationApp: source ? source.notificationApp : ownNotificationApp

    readonly property bool anyActive: recording || dnd || nightlight || stayAwake
        || reminderCount > 0 || updateAvailable || notificationCount > 0
    readonly property color dotColor: recording ? danger : accent

    // Não avisa durante as primeiras leituras (estado que já estava ligado
    // ao carregar). Depois disso, qualquer passagem de desligado para
    // ligado avisa, inclusive a primeira mudança de uma fonte que começou
    // desligada (gravação, por exemplo, não muda ao ler "false").
    property var seen: ({})
    property bool settled: false

    Timer {
        interval: 4000
        running: root.reads && !root.settled
        onTriggered: root.settled = true
    }

    function track(what, value) {
        if (!reads)
            return
        const was = !!seen[what]
        const next = Object.assign({}, seen)
        next[what] = !!value
        seen = next
        if (settled && !was && value)
            root.becameActive(what)
    }

    onDndChanged: track("dnd", dnd)
    onStayAwakeChanged: track("stayAwake", stayAwake)
    onNightlightChanged: track("nightlight", nightlight)
    onRecordingChanged: track("recording", recording)
    onReminderCountChanged: track("reminders", reminderCount > 0)
    onUpdateAvailableChanged: track("updates", updateAvailable)
    onNotificationCountChanged: track("notifications", notificationCount > 0)

    // Chamado pelo host em "omarchy.indicators refresh".
    function refresh() {
        if (!reads) {
            source.refresh()
            return
        }
        if (!recordingProc.running)
            recordingProc.running = true
        if (!reminderProc.running)
            reminderProc.running = true
        liveFile.reload()
        if (!notificationService && !dndProc.running)
            dndProc.running = true
        if (!idleService && !idleProc.running)
            idleProc.running = true
        if (!nightlightService && !nightlightProc.running)
            nightlightProc.running = true
        // A checagem de atualização faz rede; no máximo a cada 10 minutos.
        if (Date.now() - lastUpdateCheck > 600000)
            refreshUpdates()
    }

    property real lastUpdateCheck: 0

    function refreshUpdates() {
        if (!reads) {
            source.refreshUpdates()
            return
        }
        if (!checkUpdates || updateProc.running)
            return
        lastUpdateCheck = Date.now()
        updateProc.running = true
    }

    // "omarchy.system-update clear": a atualização acabou de rodar.
    function clearUpdates() {
        if (!reads) {
            source.clearUpdates()
            return
        }
        ownUpdateAvailable = false
    }

    function parseJson(raw) {
        const text = String(raw || "")
        const start = text.indexOf("{")
        const end = text.lastIndexOf("}")
        if (start < 0 || end < start)
            return null
        try {
            return JSON.parse(text.slice(start, end + 1))
        } catch (e) {
            return null
        }
    }

    function readLive(raw) {
        let list = []
        try {
            const parsed = JSON.parse(String(raw || "[]"))
            if (Array.isArray(parsed))
                list = parsed
        } catch (e) {
            list = []
        }
        ownNotificationCount = list.length
        const last = list.length > 0 ? list[list.length - 1] : null
        ownNotificationApp = last && last.app ? String(last.app).slice(0, 60) : ""
    }

    // Ações ao tocar.
    function stopRecording() {
        Quickshell.execDetached(["omarchy-capture-screenrecording", "--stop-recording"])
    }

    function allowNotifications() {
        if (!reads) {
            source.allowNotifications()
            return
        }
        if (notificationService) {
            notificationService.setDoNotDisturb(false)
            return
        }
        const result = Commons.IpcRegistry.call("notifications", "setDnd", ["off"])
        if (!result.ran)
            Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "setDnd", "off"])
        fallbackDnd = false
    }

    function nightlightOff() {
        if (nightlightService)
            nightlightService.setNightlight(false)
        else
            Quickshell.execDetached(["omarchy-shell", "-q", "nightlight", "disable"])
    }

    function allowIdle() {
        if (idleService)
            idleService.setIdleEnabled(true)
        else
            Quickshell.execDetached(["omarchy-shell", "-q", "idle", "enable"])
    }

    function showReminders() {
        Quickshell.execDetached(["omarchy-reminder", "show"])
    }

    function showNotificationHistory() {
        const result = Commons.IpcRegistry.call("notifications", "showHistory", [])
        if (!result.ran)
            Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "showHistory"])
    }

    Component.onCompleted: {
        if (!reads)
            return
        refresh()
        refreshUpdates()
    }

    // As atualizações também são checadas a cada 6 horas, como na barra padrão.
    Timer {
        interval: 21600000
        running: root.checkUpdates && root.reads
        repeat: true
        onTriggered: root.refreshUpdates()
    }

    Process {
        id: recordingProc
        command: ["omarchy-capture-screenrecording", "--status"]
        onExited: function(exitCode) { root.ownRecording = exitCode === 0 }
    }

    Process {
        id: reminderProc
        command: ["omarchy-reminder", "show", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const data = root.parseJson(text)
                root.ownReminderCount = data ? Math.max(0, Number(data.count || 0)) : 0
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.ownReminderCount = 0
        }
    }

    Process {
        id: updateProc
        command: ["omarchy-update-available"]
        onExited: function(exitCode) { root.ownUpdateAvailable = exitCode === 0 }
    }

    Process {
        id: dndProc
        command: ["omarchy-shell", "notifications", "isDnd"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.fallbackDnd = String(text).trim() === "on"
        }
    }

    Process {
        id: idleProc
        command: ["omarchy-shell", "idle", "status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const data = root.parseJson(text)
                root.fallbackStayAwake = !!(data && data.stayAwake)
            }
        }
    }

    Process {
        id: nightlightProc
        command: ["omarchy-shell", "nightlight", "status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const data = root.parseJson(text)
                root.fallbackNightlight = !!(data && data.enabled)
            }
        }
    }

    // O arquivo é regravado inteiro a cada mudança; vigiar a pasta também
    // pega a troca por renomeação.
    FileView {
        id: liveFile
        path: root.reads ? root.notificationsDir + "/live.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readLive(text())
        onLoadFailed: root.readLive("[]")
    }

    FileView {
        path: root.reads ? root.notificationsDir : ""
        watchChanges: true
        printErrors: false
        onFileChanged: liveFile.reload()
    }

    // Só o que está ligado aparece.
    readonly property var items: {
        const list = []
        if (recording)
            list.push({ key: "recording", icon: "\uDB83\uDEC2", tint: danger, count: 0 })       // nf-md-record_circle (U+F0EC2)
        if (dnd)
            list.push({ key: "dnd", icon: "\uDB80\uDC9B", tint: fg, count: 0 })                 // nf-md-bell_off (U+F009B)
        if (nightlight)
            list.push({ key: "nightlight", icon: "\uDB81\uDD0E", tint: fg, count: 0 })          // nf-md-weather_night (U+F050E)
        if (stayAwake)
            list.push({ key: "stayAwake", icon: "\uEF59", tint: fg, count: 0 })                 // nf-cod-coffee (U+EF59)
        if (reminderCount > 0)
            list.push({ key: "reminders", icon: "\uDB82\uDC8C", tint: fg, count: reminderCount })   // nf-md-alarm (U+F088C)
        if (updateAvailable)
            list.push({ key: "updates", icon: "\uF021", tint: accent, count: 0 })               // nf-fa-refresh (U+F021)
        if (notificationCount > 0)
            list.push({ key: "notifications", icon: "\uDB80\uDC9A", tint: fg, count: notificationCount })  // nf-md-bell (U+F009A)
        return list
    }

    function labelFor(key, count) {
        switch (key) {
        case "recording": return strings.t("indicators.recording")
        case "dnd": return strings.t("indicators.dnd")
        case "nightlight": return strings.t("indicators.nightlight")
        case "stayAwake": return strings.t("indicators.stayAwake")
        case "reminders": return strings.tn("indicators.reminders", count).arg(Commons.I18n.formatNumber(count))
        case "updates": return strings.t("indicators.updates")
        case "notifications": return strings.tn("indicators.notifications", count).arg(Commons.I18n.formatNumber(count))
        default: return ""
        }
    }

    function activate(key) {
        switch (key) {
        case "recording": stopRecording(); break
        case "dnd": allowNotifications(); break
        case "nightlight": nightlightOff(); break
        case "stayAwake": allowIdle(); break
        case "reminders": showReminders(); break
        case "updates": root.navigate("tools"); break
        case "notifications": showNotificationHistory(); break
        }
    }

    implicitWidth: row.implicitWidth
    implicitHeight: 30
    visible: items.length > 0

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: root.items

            Item {
                id: chip
                required property var modelData

                width: chipRow.implicitWidth + 14
                height: 30

                Accessible.role: Accessible.Button
                Accessible.name: root.labelFor(modelData.key, modelData.count)

                ContinuousRect {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
                    opacity: chipHover.hovered ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                    }
                }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: chip.modelData.icon
                        color: chip.modelData.tint
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        textFormat: Text.PlainText
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: chip.modelData.count > 0
                        text: Commons.I18n.formatNumber(chip.modelData.count)
                        color: root.fg
                        opacity: 0.85
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        textFormat: Text.PlainText
                    }
                }

                HoverHandler {
                    id: chipHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.activate(chip.modelData.key)
                }
            }
        }
    }
}
