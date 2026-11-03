import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons

// Fileira de indicadores da ilha. Só aparece o que está ligado, e tocar
// resolve: para a gravação, tira o Não perturbe, abre Ferramentas…
//
// Na faixa (Strip) cada indicador ocupa uma vaga fixa de 24 px ("slot") e a
// fileira tem "capacity" vagas. Se não couber, a última vaga vira "+N", que
// abre o painel dono do primeiro indicador escondido (ownerOf).
//
// Fontes (ver o plano):
// - Não perturbe, luz noturna, manter acordado: proxies do shell
//   (shell.firstPartyServiceFor). Sem shell (fora do Omarchy, no teste),
//   lê os comandos de status somente leitura.
// - Gravando: omarchy-capture-screenrecording --status (0 = gravando). O
//   início vem da data do arquivo de pid (o mesmo do CaptureMenu).
// - Lembretes: omarchy-reminder show --json (a contagem e o próximo "at").
// - Atualizações: omarchy-update-available (0 = há atualização).
// - Notificações na tela: ~/.local/state/omarchy/notifications/live.json.
// - Música: o serviço omarchy.media do shell (o mesmo player ativo da barra
//   padrão). Sem shell, lê o MPRIS direto, com a mesma escolha simples:
//   o preferido, senão o que toca, senão o primeiro com faixa.
Item {
    id: root

    property var shell: null
    property color fg: Commons.Color.bar.text
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property string fontFamily: Commons.Style.fontFamily
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
    // Chegou uma notificação urgente nova (a mais recente da lista):
    // { key, app, summary, urgent: true }. Só a instância que lê emite,
    // e só depois das primeiras leituras.
    signal urgentArrived(var row)

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
    // A notificação mais recente, para o clique no sino. Chegar uma nova
    // não abre a pílula sozinha.
    property var currentNotice: null
    signal noticeRequested()

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

    // ---- Tempo da gravação ----
    // Mesmo arquivo de pid que o CaptureMenu lê: a data dele é o início.
    readonly property string recPidFile: (Quickshell.env("XDG_RUNTIME_DIR")
                                          || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy"))
                                         + "/omarchy-screenrecord-pid"
    // Início em segundos epoch; 0 = desconhecido.
    property real ownRecStart: 0
    property real nowSec: Date.now() / 1000
    readonly property int ownRecordingSeconds: ownRecording && ownRecStart > 0
        ? Math.max(0, Math.floor(nowSec - ownRecStart)) : -1
    // -1 quando não grava ou o início ainda não chegou.
    readonly property int recordingSeconds: source ? source.recordingSeconds : ownRecordingSeconds
    // "0:42", "12:05", "1:02:03", sempre em dígitos ASCII; "" sem tempo.
    readonly property string recordingClock: source ? source.recordingClock : clockOf(ownRecordingSeconds)

    function pad2(n) { return (n < 10 ? "0" : "") + n }
    function clockOf(seconds) {
        if (!(seconds >= 0))
            return ""
        const h = Math.floor(seconds / 3600)
        const m = Math.floor((seconds % 3600) / 60)
        const s = seconds % 60
        return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : m + ":" + pad2(s)
    }

    onOwnRecordingChanged: {
        if (!reads)
            return
        if (ownRecording) {
            if (!recStartProc.running)
                recStartProc.running = true
        } else {
            ownRecStart = 0
        }
    }

    // Relógio de segundos só enquanto grava. O relógio geral da pílula
    // continua em minutos.
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.reads && root.ownRecording
        onTriggered: root.nowSec = Date.now() / 1000
    }

    // ---- Próximo lembrete ----
    // Menor "at" (segundos epoch) de omarchy-reminder show --json; 0 = nenhum.
    property real ownNextReminderAt: 0
    readonly property real nextReminderAt: source ? source.nextReminderAt : ownNextReminderAt

    // ---- Música (MPRIS) ----
    // O serviço do shell decide o player ativo; esta instância só repassa.
    // Uma instância espelho (source) lê tudo da fonte.
    readonly property var mediaService: serviceFor("omarchy.media")
    // Reserva sem shell: os players do MPRIS com algum metadado.
    property string ownMediaKey: ""
    readonly property var ownMediaPlayers: {
        const list = Mpris.players ? Mpris.players.values : []
        const out = []
        for (let i = 0; i < list.length; i++) {
            const p = list[i]
            if (p && (p.trackTitle || p.trackArtist || p.identity))
                out.push(p)
        }
        out.sort((a, b) => (!!a.isPlaying === !!b.isPlaying) ? 0 : (a.isPlaying ? -1 : 1))
        return out
    }
    readonly property var ownMediaPlayer: {
        const list = ownMediaPlayers
        if (list.length === 0)
            return null
        for (let i = 0; i < list.length; i++)
            if (ownMediaKey !== "" && mediaKey(list[i]) === ownMediaKey)
                return list[i]
        for (let j = 0; j < list.length; j++)
            if (list[j].isPlaying)
                return list[j]
        for (let k = 0; k < list.length; k++)
            if (list[k].trackTitle)
                return list[k]
        return list[0]
    }

    readonly property var mediaPlayers: source ? source.mediaPlayers
        : mediaService ? (mediaService.sourcePlayers || []) : ownMediaPlayers
    readonly property var mediaPlayer: source ? source.mediaPlayer
        : mediaService ? mediaService.activePlayer : ownMediaPlayer
    // Há faixa: título ou artista. Sem isso nada de música aparece na pílula.
    readonly property bool hasMedia: !!(mediaPlayer && (mediaPlayer.trackTitle || mediaPlayer.trackArtist))
    readonly property bool mediaPlaying: hasMedia && !!mediaPlayer.isPlaying
    readonly property string mediaTitle: hasMedia ? oneLine(mediaPlayer.trackTitle || mediaPlayer.trackArtist, 160) : ""
    readonly property string mediaArtist: hasMedia && mediaPlayer.trackTitle ? oneLine(mediaPlayer.trackArtist, 120) : ""
    readonly property string mediaArtUrl: hasMedia && mediaPlayer.trackArtUrl ? String(mediaPlayer.trackArtUrl) : ""

    function mediaKey(player) {
        if (!player)
            return ""
        if (mediaService && typeof mediaService.playerKey === "function")
            return String(mediaService.playerKey(player) || "")
        return String(player.dbusName || player.desktopEntry || player.identity || "")
    }

    // Nome curto do player para o seletor (Spotify, Firefox…).
    function mediaLabel(player) {
        if (!player)
            return ""
        const name = String(player.identity || player.desktopEntry || "").trim()
        return oneLine(name !== "" ? name : player.dbusName, 32)
    }

    function selectMedia(key) {
        if (source) {
            source.selectMedia(key)
            return
        }
        if (mediaService && typeof mediaService.selectPlayer === "function") {
            mediaService.selectPlayer(String(key))
            return
        }
        ownMediaKey = String(key || "")
    }

    // "playPause", "play", "pause", "next", "previous". Sem OSD: o
    // controle já está na tela.
    function mediaAction(action, key) {
        if (source)
            return source.mediaAction(action, key)
        if (mediaService && typeof mediaService.runAction === "function")
            return !!mediaService.runAction(action, false, key !== undefined ? String(key) : mediaKey(mediaPlayer))
        const p = mediaPlayer
        if (!p)
            return false
        if (action === "next" && p.canGoNext) { p.next(); return true }
        if (action === "previous" && p.canGoPrevious) { p.previous(); return true }
        if (action === "playPause" || action === "play" || action === "pause") {
            const wantPlay = action === "play" || (action === "playPause" && !p.isPlaying)
            if (wantPlay && p.canPlay) { p.play(); return true }
            if (!wantPlay && p.canPause) { p.pause(); return true }
            if (p.canTogglePlaying) { p.togglePlaying(); return true }
        }
        return false
    }

    // ---- Marca da pílula em repouso ----
    // Um ícone só: o primeiro estado ligado nesta ordem. Só entra o que o
    // usuário ligou (ou que pede ação); notificação na tela não conta, ela
    // vive no sino. Tocar na marca abre o painel dono (restOwnerView).
    readonly property var restOrder: ["recording", "reminders", "updates", "dnd", "nightlight", "stayAwake"]
    readonly property string ownRestKey: {
        for (let i = 0; i < restOrder.length; i++)
            if (isOn(restOrder[i]))
                return restOrder[i]
        return ""
    }
    readonly property string restKey: source ? source.restKey : ownRestKey
    readonly property string restIcon: source ? source.restIcon : (restKey !== "" ? iconOf(restKey) : "")
    readonly property color restTone: source ? source.restTone : colorOf(restKey)
    readonly property string restOwnerView: source ? source.restOwnerView : (restKey !== "" ? ownerOf(restKey) : "")
    // Música tocando: as três barrinhas ficam ao lado do ícone (ou sozinhas,
    // sem ícone). Pausada, não.
    readonly property bool restBars: source ? source.restBars : mediaPlaying
    readonly property bool restMark: source ? source.restMark : (restKey !== "" || mediaPlaying)
    // Compatibilidade: o ponto antigo. A ilha não usa mais.
    readonly property bool restDot: restKey !== ""
    readonly property color dotColor: restTone

    // ---- Ícone, tom e estado de cada chave ----
    function iconOf(key) {
        switch (key) {
        case "recording": return "radio_button_checked"
        case "reminders": return "alarm"
        case "updates": return "update"
        case "dnd": return "notifications_off"
        case "nightlight": return "nightlight"
        case "stayAwake": return "coffee"
        case "notifications": return "notifications"
        default: return ""
        }
    }

    // "danger", "accent" ou "fg" (o mesmo nome que o NoticeView aceita).
    function toneOf(key) {
        if (key === "recording")
            return "danger"
        if (key === "updates")
            return "accent"
        return "fg"
    }

    function colorOf(key) {
        const tone = toneOf(key)
        return tone === "danger" ? danger : tone === "accent" ? accent : fg
    }

    function isOn(key) {
        switch (key) {
        case "recording": return recording
        case "reminders": return reminderCount > 0
        case "updates": return updateAvailable
        case "dnd": return dnd
        case "nightlight": return nightlight
        case "stayAwake": return stayAwake
        case "notifications": return notificationCount > 0
        default: return false
        }
    }

    function countOf(key) {
        if (key === "reminders")
            return reminderCount
        if (key === "notifications")
            return notificationCount
        return 0
    }

    // Frase curta do aviso ao vivo: "Gravando 0:42", "Lembrete em 15 min".
    function peekText(key) {
        if (source)
            return source.peekText(key)
        switch (key) {
        case "recording":
            return recordingClock !== ""
                ? strings.t("capture.recordingWithTime", "Recording %1").arg(recordingClock)
                : strings.t("capture.recordingNow", "Recording")
        case "reminders": {
            if (!(nextReminderAt > 0))
                return labelFor("reminders", reminderCount)
            const m = Math.max(1, Math.ceil((nextReminderAt - Date.now() / 1000) / 60))
            const h = Math.floor(m / 60)
            const mm = m % 60
            const dur = m < 60
                ? strings.tn("peek.minutes", m, "%1 min").arg(Commons.I18n.formatNumber(m))
                : mm === 0
                    ? strings.t("peek.hours", "%1 h").arg(Commons.I18n.formatNumber(h))
                    : strings.t("peek.hoursMinutes", "%1 h %2 min").arg(Commons.I18n.formatNumber(h)).arg(Commons.I18n.formatNumber(mm))
            return strings.t("peek.reminderIn", "Reminder in %1").arg(dur)
        }
        case "updates": return strings.t("peek.updates", "Update available")
        case "dnd": return strings.t("peek.dnd", "Do not disturb on")
        case "nightlight": return strings.t("peek.nightlight", "Night light on")
        case "stayAwake": return strings.t("peek.stayAwake", "Stay awake on")
        case "notifications": return currentNotice ? String(currentNotice.summary || "") : ""
        default: return ""
        }
    }

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

    // Uma linha só, sem markup. O Text que desenha isto é PlainText.
    function oneLine(value, maxLen) {
        let text = String(value == null ? "" : value)
        text = text.replace(/[\u0000-\u001f\u007f]+/g, " ")
        text = text.replace(/<[^>]{0,200}>/g, " ")
        text = text.replace(/\s+/g, " ").trim()
        if (text.length > maxLen)
            text = text.slice(0, maxLen)
        return text
    }

    function readLive(raw) {
        let list = []
        let parsedOk = false
        try {
            const parsed = JSON.parse(String(raw || "[]"))
            if (Array.isArray(parsed)) {
                list = parsed
                parsedOk = true
            }
        } catch (e) {
            parsedOk = false
        }
        if (!parsedOk)
            return
        const last = list.length > 0 ? list[list.length - 1] : null
        let row = null
        if (last && typeof last === "object") {
            const app = oneLine(last.app, 48)
            const summary = oneLine(last.summary, 140)
            const detail = oneLine(last.body, 140)
            const headline = summary !== "" ? summary : detail
            let key = oneLine(last.key || last.originalId || "", 80)
            if (key === "")
                key = app + "\n" + headline + "\n" + String(list.length)
            if (headline !== "" || app !== "") {
                row = {
                    key: key,
                    app: app,
                    summary: headline !== "" ? headline : app,
                    urgent: Number(last.urgency) === 2
                }
            }
        }
        ownNotificationCount = list.length
        ownNotificationApp = row && row.app ? row.app : ""
        currentNotice = row

        // Urgente nova no topo da lista: avisa uma vez por chave. Nas
        // primeiras leituras só guarda a chave (já estava na tela).
        if (reads && row && row.urgent && row.key !== lastUrgentKey) {
            lastUrgentKey = row.key
            if (settled)
                root.urgentArrived({ key: row.key, app: row.app, summary: row.summary, urgent: true })
        }
    }

    property string lastUrgentKey: ""

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
                // O próximo antes da contagem: quem ouve a contagem mudar já
                // acha a hora certa para o aviso.
                const list = data && Array.isArray(data.reminders) ? data.reminders : []
                let next = 0
                for (let i = 0; i < list.length; i++) {
                    const at = Number(list[i] && list[i].at)
                    if (isFinite(at) && at > 0 && (next === 0 || at < next))
                        next = at
                }
                root.ownNextReminderAt = next
                root.ownReminderCount = data ? Math.max(0, Number(data.count || 0)) : 0
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.ownNextReminderAt = 0
                root.ownReminderCount = 0
            }
        }
    }

    // Início da gravação: a data do arquivo de pid. Sem ele, agora.
    Process {
        id: recStartProc
        command: ["stat", "-c", "%Y", root.recPidFile]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!root.ownRecording)
                    return
                const t = parseInt(String(text).trim())
                root.nowSec = Date.now() / 1000
                root.ownRecStart = isFinite(t) && t > 0 ? t : Date.now() / 1000
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 && root.ownRecording && root.ownRecStart === 0)
                root.ownRecStart = Date.now() / 1000
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
        // A gravação atômica some com o arquivo por um instante. Isso não é
        // uma lista vazia; a próxima leitura boa traz o conteúdo.
    }

    FileView {
        path: root.reads ? root.notificationsDir : ""
        watchChanges: true
        printErrors: false
        onFileChanged: liveFile.reload()
    }

    // Só o que está ligado aparece, na mesma ordem da marca de repouso e
    // com as notificações por último.
    readonly property var itemOrder: restOrder.concat(["notifications"])
    readonly property var items: {
        const list = []
        for (let i = 0; i < itemOrder.length; i++) {
            const key = itemOrder[i]
            if (isOn(key))
                list.push({ key: key, icon: iconOf(key), tint: colorOf(key), count: countOf(key) })
        }
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
        if (!reads && source) {
            source.activate(key)
            return
        }
        switch (key) {
        case "recording": stopRecording(); break
        case "dnd": allowNotifications(); break
        case "nightlight": nightlightOff(); break
        case "stayAwake": allowIdle(); break
        case "reminders": root.navigate("calendar"); break
        case "updates": root.navigate("tools"); break
        case "notifications": noticeRequested(); break
        }
    }

    // Painel que cuida de cada indicador (usado pelo "+N").
    function ownerOf(key) {
        switch (key) {
        case "recording": return "capture"
        case "reminders": return "calendar"
        case "updates":
        case "notifications": return "tools"
        default: return "control"
        }
    }

    // ---- Vagas ----
    // Largura fixa de cada vaga e quantas cabem (-1 = sem limite).
    property int slot: 24
    property int capacity: -1
    readonly property bool overflowing: capacity >= 0 && items.length > capacity
    readonly property var shownItems: overflowing ? items.slice(0, Math.max(0, capacity - 1)) : items
    readonly property int hiddenCount: items.length - shownItems.length
    readonly property bool showMore: overflowing && capacity >= 1

    implicitWidth: (shownItems.length + (showMore ? 1 : 0)) * slot
    implicitHeight: 30
    width: implicitWidth
    visible: implicitWidth > 0

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: root.shownItems

            Item {
                id: chip
                required property var modelData

                width: root.slot
                height: 30

                Accessible.role: Accessible.Button
                Accessible.name: root.labelFor(modelData.key, modelData.count)

                ContinuousRect {
                    anchors.centerIn: parent
                    width: root.slot
                    height: root.slot
                    radius: height / 2
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
                    opacity: chipHover.hovered ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                    }
                }

                Icon {
                    anchors.centerIn: parent
                    name: chip.modelData.icon
                    color: chip.modelData.tint
                    size: 17
                    filled: true
                }

                // Contagem: número pequeno no canto, sem alargar a vaga.
                Text {
                    visible: chip.modelData.count > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    text: chip.modelData.count > 9 ? "9+" : Commons.I18n.formatNumber(chip.modelData.count)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.features: ({ "tnum": 1 })
                    font.weight: Font.Bold
                    textFormat: Text.PlainText
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

        // "+N": abre o painel do primeiro indicador que não coube.
        Item {
            id: more
            visible: root.showMore
            width: root.slot
            height: 30

            Accessible.role: Accessible.Button
            Accessible.name: strings.tn("indicators.more", root.hiddenCount).arg(Commons.I18n.formatNumber(root.hiddenCount))

            ContinuousRect {
                anchors.centerIn: parent
                width: root.slot
                height: 18
                radius: height / 2
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, moreHover.hovered ? 0.18 : 0.10)

                Behavior on color {
                    ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                }
            }

            Text {
                anchors.centerIn: parent
                text: "+" + Commons.I18n.formatNumber(root.hiddenCount)
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
            }

            HoverHandler {
                id: moreHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: {
                    const first = root.items[root.shownItems.length]
                    if (first)
                        root.navigate(root.ownerOf(first.key))
                }
            }
        }
    }
}
