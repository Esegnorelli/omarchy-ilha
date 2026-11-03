import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Motion.js" as Motion

// Estados do sistema para a linha do L2, a marca do repouso, o aviso ao vivo
// e a Central: Não perturbe, luz noturna, modo jogo, gravação, sessão remota,
// sudo sem senha, manter acordado, lembretes, atualização e notificações.
// Um só por ilha (island.status). Dono: Agent H (design + amendments §4.1,
// §9.1, §14.1).
//
// DE ONDE VEM CADA COISA
// - Não perturbe, luz noturna, manter acordado, sessão remota: os proxies
//   estreitos do host (shell.firstPartyServiceFor: omarchy.notifications,
//   omarchy.nightlight, omarchy.idle, omarchy.remote-session). Sem proxy
//   (harness, host antigo) lê os arquivos de estado do próprio Omarchy:
//   notifications/quiet.json, indicators/stay-awake e `hyprctl hyprsunset
//   temperature`. Nunca pergunta nada ao shell por IPC só para ler.
// - Gravação: omarchy-capture-screenrecording --status (0 = gravando); o
//   início é a data do arquivo de pid do gravador.
// - Sudo sem senha: omarchy-sudo-passwordless --active. Sem sondagem
//   periódica (o script chama omarchy.indicators refresh ao ligar, desligar e
//   expirar).
// - Lembretes: omarchy-reminder show --json. Sem sondagem: o Omarchy chama
//   omarchy.indicators refresh quando um lembrete é criado e quando dispara.
// - Atualização: omarchy-update-available (0 = há), na partida, a cada 6 h e
//   em omarchy.system-update refresh.
// - Notificações: ~/.local/state/omarchy/notifications/live.json (na tela) e
//   history.json (fechadas), os arquivos do serviço do Omarchy (formato em
//   plugins/notifications/Store.js). Só lidos; as ações passam pelo IPC
//   "notifications" do próprio processo (Commons.IpcRegistry).
// - Modo jogo: o game-mode.json da 1.x (StateStore.legacyGameMode). Ligar
//   salva animações, espaçamento e transparência e desliga o que estiver
//   ligado; desligar devolve só o que foi mudado e apaga o arquivo.
//
// ESCRITA OTIMISTA: um setter mostra o valor novo na hora ("held") e o solta
// quando a leitura de verdade concorda (ou depois de 4 s).
//
// HARNESS (ILHA_DEV=1): lê o sistema (arquivos e sondagens só de leitura),
// mas nenhum setter ou ação roda comando: tudo fica na memória. Sudo e
// atualização nem são sondados (o sudo registra no diário; a checagem faz
// git fetch).
//
// Tons (statusLine.tone, markTone, peekFor().tone): theme.toneColor(tone).
// Ações (statusLine.action): "" (sem clique) | "stop-recording" | "disable-sudo"
//   | "open-reminders" | "run-update" | "allow-idle" | "dnd-off"
//   | "open:control" | "open:media". runAction(a) executa as de serviço e
//   devolve false para "open:*" (quem chama abre a tela).
QtObject {
    id: root

    // ---- Entradas (o Ilha.qml liga) ----
    property var shell: null
    property var strings: null
    property var media: null       // MediaSvc (faixa na linha do L2)
    property var store: null       // StateStore (clearedAt, nightK, game-mode.json)

    readonly property bool dev: Quickshell.env("ILHA_DEV") === "1"
    readonly property string home: Quickshell.env("HOME")
    readonly property string notificationsDir: root.home + "/.local/state/omarchy/notifications"
    readonly property string indicatorsDir: root.home + "/.local/state/omarchy/indicators"
    // O mesmo arquivo de pid que o script de gravação usa.
    readonly property string recPidFile: (Quickshell.env("XDG_RUNTIME_DIR") || ((Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state")) + "/omarchy")) + "/omarchy-screenrecord-pid"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (root.home + "/.local/state")) + "/esegnorelli.ilha"

    // ---- Proxies do host (cada um pode ser nulo) ----
    function serviceFor(id) {
        if (!root.shell || typeof root.shell.firstPartyServiceFor !== "function")
            return null;
        try {
            return root.shell.firstPartyServiceFor(id) || null;
        } catch (e) {
            return null;
        }
    }
    readonly property var notificationService: root.serviceFor("omarchy.notifications")
    readonly property var idleService: root.serviceFor("omarchy.idle")
    readonly property var nightlightService: root.serviceFor("omarchy.nightlight")
    readonly property var remoteService: root.serviceFor("omarchy.remote-session")

    // ---- Não perturbe, luz noturna, modo jogo ----
    readonly property bool dnd: root.heldOr("dnd", priv.realDnd)
    function setDnd(on) {
        const want = !!on;
        root.holdValue("dnd", want);
        if (root.dev)
            return;
        if (root.notificationService) {
            root.notificationService.setDoNotDisturb(want);
            return;
        }
        root.ipcOrShell("notifications", "setDnd", [want ? "on" : "off"]);
    }

    readonly property bool nightlight: root.heldOr("nightlight", priv.realNight)
    // A temperatura mostrada: a escolhida agora (arrastando), a lida do
    // hyprsunset com a luz ligada, ou a preferida (store.nightK).
    readonly property int nightTemperature: {
        if (priv.shownK > 0)
            return priv.shownK;
        if (root.nightlight && priv.probedTemp >= 1000 && priv.probedTemp < 6000)
            return root.clampK(priv.probedTemp);
        return root.store ? root.clampK(root.store.nightK) : 4000;
    }
    function setNightlight(on) {
        const want = !!on;
        root.holdValue("nightlight", want);
        if (root.dev) {
            if (want)
                priv.probedTemp = root.preferredK();
            return;
        }
        if (want) {
            // Liga já na temperatura preferida (o serviço do host liga sempre
            // em 4000 K); depois o serviço relê o estado.
            root.applyNight(root.preferredK());
            return;
        }
        nightDebounce.stop();
        priv.queuedK = 0;
        if (root.nightlightService) {
            root.nightlightService.setNightlight(false);
            return;
        }
        const r = Commons.IpcRegistry.call("nightlight", "disable", []);
        if (!r.ran)
            root.applyNight(0);
    }
    // 2500..5800 K. Mostra na hora; aplica 120 ms depois do último movimento
    // (só com a luz ligada); guarda como preferida.
    function setTemperature(k) {
        const v = root.clampK(k);
        priv.shownK = v;
        if (root.store)
            root.store.nightK = v;
        if (root.dev) {
            priv.probedTemp = v;
            priv.shownK = 0;
            return;
        }
        if (root.nightlight)
            nightDebounce.restart();
        else
            priv.shownK = 0;
    }

    readonly property bool gameMode: priv.gameWant >= 0 ? priv.gameWant === 1 : (!!root.store && root.store.legacyGameMode !== null)
    function setGameMode(on) {
        const want = !!on;
        if (priv.gameBusy || want === root.gameMode)
            return;
        priv.gameWant = want ? 1 : 0;
        if (root.dev)
            return;
        priv.gameBusy = true;
        gameWatchdog.restart();
        if (want) {
            gmAnimProc.running = true;
        } else {
            const saved = root.store ? root.store.legacyGameMode : null;
            root.runGameSteps(root.gameModeOffSteps(saved));
        }
    }

    // ---- Gravação ----
    readonly property bool recording: root.heldOr("recording", priv.recActive)
    // Segundos desde o início; -1 = desconhecido (ou sem gravação).
    readonly property int recordingSeconds: root.recording && priv.recStart > 0 ? Math.max(0, Math.floor(priv.nowSec - priv.recStart)) : -1
    // "0:42", "12:05", "1:02:03" com os algarismos do idioma; "" sem tempo.
    readonly property string recordingClock: root.clockText(root.recordingSeconds)
    function stopRecording() {
        root.holdValue("recording", false);
        if (root.dev)
            return;
        root.run(["omarchy-capture-screenrecording", "--stop-recording"]);
        recheckTimer.restart();
    }

    // ---- Sessão remota, sudo sem senha, manter acordado ----
    readonly property bool remoteActive: !!root.remoteService && root.remoteService.active === true
    readonly property var remotePeers: root.remoteService && Array.isArray(root.remoteService.peers) ? root.remoteService.peers.map(p => root.oneLine(p, 48)).filter(p => p !== "") : []

    readonly property bool sudoPasswordless: root.heldOr("sudo", priv.sudoOn)
    function disableSudo() {
        root.holdValue("sudo", false);
        if (root.dev || sudoDisableProc.running)
            return;
        sudoDisableProc.running = true;
    }

    readonly property bool stayAwake: root.heldOr("stayAwake", priv.realStay)
    function allowIdle() {
        root.setStayAwake(false);
    }
    // Proxy do idle (setIdleEnabled(!on)); sem ele, o IPC "idle" do próprio
    // processo; sem esse, omarchy-shell -q idle.
    function setStayAwake(on) {
        const want = !!on;
        root.holdValue("stayAwake", want);
        if (root.dev)
            return;
        if (root.idleService) {
            root.idleService.setIdleEnabled(!want);
            return;
        }
        root.ipcOrShell("idle", want ? "disable" : "enable", []);
    }

    // ---- Lembretes ----
    readonly property int reminderCount: priv.remCount
    // Época em segundos do lembrete mais próximo (0 = nenhum).
    readonly property real nextReminderAt: priv.remNextAt
    // `message` do lembrete com o menor `at` ("" sem mensagem própria).
    readonly property string nextReminderMessage: priv.remNextMsg
    function openReminders() {
        if (!root.dev)
            root.run(["omarchy-reminder", "show"]);
    }

    // ---- Atualização ----
    readonly property bool updateAvailable: priv.updateOn
    function runUpdate() {
        if (!root.dev)
            root.run(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]);
    }

    // ---- Notificações ----
    // Linha: {key, app, summary, body, urgency, icon, rawGlyph, ts, live}
    //   ts em ms (como Date.now()); icon = appIcon do Omarchy (nome de ícone
    //   do sistema ou caminho, nunca Material Symbol); rawGlyph = o glifo
    //   Nerd Font que o Omarchy guardou ("" quando não há).
    // live: as da tela, a mais nova primeiro (live[0]).
    readonly property var live: priv.liveRows
    // history: fechadas depois de max(clearedAt, agora − 24 h), a mais nova primeiro.
    readonly property var history: {
        const cleared = root.store ? Number(root.store.clearedAt) || 0 : 0;
        const cutoff = Math.max(cleared, priv.histNow - 24 * 3600 * 1000);
        const onScreen = {};
        for (let i = 0; i < priv.liveRows.length; i++)
            onScreen[priv.liveRows[i].key] = true;
        return priv.historyRows.filter(r => r.closedAt > cutoff && !onScreen[r.key]);
    }
    // live primeiro, depois history; no máximo 30.
    readonly property var visibleRows: root.live.concat(root.history).slice(0, 30)
    readonly property int liveCount: root.live.length
    function clearAll() {
        if (root.dev) {
            priv.liveRows = [];
            if (root.store)
                root.store.clearedAt = Date.now();
            return;
        }
        const ran = root.ipcOrShell("notifications", "dismissAll", []);
        // As que acabaram de fechar entram no histórico com closed_ts de agora:
        // a margem as deixa do lado de "limpas" (o caminho por processo demora mais).
        if (root.store)
            root.store.clearedAt = Date.now() + (ran ? 1000 : 3000);
    }
    // Tira da tela as notificações com este resumo (IPC notifications dismiss).
    function dismiss(summary) {
        const s = String(summary || "");
        if (s === "")
            return;
        if (root.dev) {
            priv.liveRows = priv.liveRows.filter(r => r.summary.indexOf(s) === -1);
            return;
        }
        root.ipcOrShell("notifications", "dismiss", [s]);
    }
    // Clica na mais nova da tela, como o ponteiro faria.
    function invokeLast() {
        if (!root.dev)
            root.ipcOrShell("notifications", "invokeLast", []);
    }

    // ---- Derivados ----
    readonly property bool privacy: root.recording || root.remoteActive || root.sudoPasswordless

    // Linha de estado do L2 (prioridade do design, primeiro que casar).
    readonly property var statusLine: root.lineFor("")

    // omarchy.indicators refresh (e a partida): relê tudo o que não se vigia sozinho.
    function refresh() {
        root.kick(recordingProc);
        root.kick(reminderProc);
        if (!root.dev)
            root.kick(sudoProbe);
        if (root.remoteService && typeof root.remoteService.refresh === "function")
            root.remoteService.refresh();
        liveFile.reload();
        historyFile.reload();
        if (!root.notificationService)
            quietFile.reload();
        if (!root.idleService)
            stayFile.reload();
        root.kick(tempProbe);
        // A checagem de atualização usa a rede: no máximo a cada 10 minutos.
        if (Date.now() - priv.lastUpdateCheck > 600000)
            root.refreshUpdates();
    }
    // omarchy.system-update refresh.
    function refreshUpdates() {
        if (root.dev)
            return;
        priv.lastUpdateCheck = Date.now();
        root.kick(updateProc);
    }
    // omarchy.system-update clear: a atualização acabou de rodar.
    function clearUpdates() {
        priv.updateOn = false;
        root.track("update", false);
    }

    // ---- Marca do repouso (amendments §4.1) ----
    readonly property var markOrder: ["remote", "sudo", "recording", "reminder", "update", "dnd", "nightlight", "stayAwake"]
    readonly property string markKey: {
        for (let i = 0; i < root.markOrder.length; i++) {
            if (root.isOn(root.markOrder[i]))
                return root.markOrder[i];
        }
        return "";
    }
    readonly property string markIcon: root.iconFor(root.markKey)
    readonly property bool markFilled: root.filledFor(root.markKey)
    readonly property string markTone: root.toneFor(root.markKey)
    readonly property string markOwner: root.ownerFor(root.markKey)

    // Sobe na borda de subida de um indicador, depois do assentamento
    // (SETTLE_MS); a primeira leitura nunca dispara. reminder também sobe
    // quando a contagem aumenta e uma vez por `at` a 300 s do horário.
    signal activated(string key)
    // A linha mais nova de live.json com urgency 2 e uma key nova: {key, app, summary, body}.
    signal urgentArrived(var row)

    function isOn(key) {
        switch (String(key || "")) {
        case "remote": return root.remoteActive;
        case "sudo": return root.sudoPasswordless;
        case "recording": return root.recording;
        case "reminder": return root.reminderCount > 0;
        case "update": return root.updateAvailable;
        case "dnd": return root.dnd;
        case "nightlight": return root.nightlight;
        case "stayAwake": return root.stayAwake;
        case "notifications": return root.liveCount > 0;
        default: return false;
        }
    }

    function iconFor(key) {
        switch (String(key || "")) {
        case "remote": return "screen_share";
        case "sudo": return "admin_panel_settings";
        case "recording": return "fiber_manual_record";
        case "reminder": return "alarm";
        case "update": return "system_update_alt";
        case "dnd": return "do_not_disturb_on";
        case "nightlight": return "dark_mode";
        case "stayAwake": return "coffee";
        case "urgent": return "notifications_active";
        case "notifications": return "notifications_active";
        default: return "";
        }
    }

    function filledFor(key) {
        return ["remote", "sudo", "recording", "dnd", "nightlight", "stayAwake", "urgent", "notifications"].indexOf(String(key || "")) !== -1;
    }

    // "danger" | "accentInk" | "ink" (a marca e o aviso; a linha do L2 tem os próprios tons).
    function toneFor(key) {
        switch (String(key || "")) {
        case "remote":
        case "sudo":
        case "recording":
        case "urgent":
            return "danger";
        case "dnd":
            return "ink";
        case "":
            return "";
        default:
            return "accentInk";
        }
    }

    // Dono de cada chave: "l2" (L2 fixado na linha) | "control" | "control:display".
    function ownerFor(key) {
        switch (String(key || "")) {
        case "dnd":
        case "nightlight":
            return "control";
        case "stayAwake":
            return "control:display";
        case "":
            return "";
        default:
            return "l2";
        }
    }

    // A entrada da linha de estado para uma chave ativa ({key, text, icon, filled, tone, action});
    // statusLine quando a chave é "" ou está desligada.
    function statusFor(key) {
        if (String(key || "") === "" || !root.isOn(key))
            return root.statusLine;
        return root.lineFor(key);
    }

    function t(k) {
        return root.strings ? root.strings.t(k) : k;
    }

    // Prioridade da linha do L2 (design screens §3). `only` pede uma chave só
    // (statusFor); "nightlight" só existe por esse caminho (a linha nunca a mostra).
    function lineFor(only) {
        const want = String(only || "");
        const order = ["remote", "recording", "sudo", "notifications", "reminder", "update", "stayAwake", "track", "dnd"];
        if (want === "nightlight" && root.nightlight)
            return root.entryFor("nightlight");
        for (let i = 0; i < order.length; i++) {
            const k = order[i];
            if (want !== "" && want !== k)
                continue;
            const on = k === "track" ? !!(root.media && root.media.hasTrack) : root.isOn(k);
            if (on)
                return root.entryFor(k);
        }
        return { key: "", text: root.t("bar.allCaughtUp"), icon: "notifications", filled: false, tone: "calm", action: "open:control" };
    }

    function entryFor(k) {
        switch (k) {
        case "remote":
            return { key: k, text: root.remotePeers.length > 0 ? root.t("bar.remoteSessionFrom").arg(root.remotePeers.join(", ")) : root.t("bar.remoteSession"), icon: "screen_share", filled: true, tone: "danger", action: "" };
        case "recording":
            return { key: k, text: root.recordingSeconds >= 0 ? root.t("bar.recording").arg(root.recordingClock) : root.t("bar.recordingNow"), icon: "fiber_manual_record", filled: true, tone: "danger", action: "stop-recording" };
        case "sudo":
            return { key: k, text: root.t("bar.sudoPasswordless"), icon: "admin_panel_settings", filled: true, tone: "danger", action: "disable-sudo" };
        case "notifications":
            return { key: k, text: (root.strings ? root.strings.tn("bar.notifications", root.liveCount) : "%1").arg(Commons.I18n.formatNumber(root.liveCount)), icon: "notifications_active", filled: true, tone: "accentInk", action: "open:control" };
        case "reminder":
            return { key: k, text: root.t("bar.reminderIn").arg(root.durationText(root.nextReminderAt - priv.remNow)), icon: "alarm", filled: false, tone: "accentInkSoft", action: "open-reminders" };
        case "update":
            return { key: k, text: root.t("bar.update"), icon: "system_update_alt", filled: false, tone: "accentInkSoft", action: "run-update" };
        case "stayAwake":
            return { key: k, text: root.t("bar.stayAwake"), icon: "coffee", filled: false, tone: "accentInkSoft", action: "allow-idle" };
        case "track": {
            const m = root.media;
            const title = m ? String(m.title || "") : "";
            const artist = m ? String(m.artist || "") : "";
            return { key: k, text: artist !== "" ? root.t("bar.trackArtist").arg(title).arg(artist) : title, icon: m && m.playing ? "music_note" : "pause", filled: false, tone: "accentInk", action: "open:media" };
        }
        case "dnd":
            return { key: k, text: root.t("bar.dnd"), icon: "do_not_disturb_on", filled: true, tone: "inkSoft", action: "dnd-off" };
        case "nightlight":
            return { key: k, text: root.t("peek.nightLightOn"), icon: "dark_mode", filled: true, tone: "accentInk", action: "open:control" };
        default:
            return null;
        }
    }

    // Executa a ação de uma linha. false = "open:*" (quem chama abre a tela) ou desconhecida.
    function runAction(action) {
        switch (String(action || "")) {
        case "stop-recording": root.stopRecording(); return true;
        case "disable-sudo": root.disableSudo(); return true;
        case "open-reminders": root.openReminders(); return true;
        case "run-update": root.runUpdate(); return true;
        case "allow-idle": root.allowIdle(); return true;
        case "dnd-off": root.setDnd(false); return true;
        default: return false;
        }
    }

    // Payload do aviso ao vivo (amendments §9.2): {key, icon, filled, tone, text, app, summary, urgent}
    // (+ rowKey no urgente). Reavaliado ao vivo: a gravação anda de segundo
    // em segundo e o lembrete de minuto em minuto. null para chave desconhecida.
    function peekFor(key, row) {
        const k = String(key || "");
        const r = row || ({});
        switch (k) {
        case "recording":
            return { key: k, icon: "fiber_manual_record", filled: true, tone: "danger", text: root.recordingSeconds >= 0 ? root.t("bar.recording").arg(root.recordingClock) : root.t("bar.recordingNow"), app: "", summary: "", urgent: false };
        case "reminder": {
            const d = root.durationText(root.nextReminderAt - priv.remNow);
            const msg = root.oneLine(root.nextReminderMessage, 80);
            const text = msg !== "" ? root.t("peek.reminderInWith").arg(d).arg(msg) : root.t("bar.reminderIn").arg(d);
            return { key: k, icon: "alarm", filled: false, tone: "accentInk", text: text, app: "", summary: "", urgent: false };
        }
        case "update":
            return { key: k, icon: "system_update_alt", filled: false, tone: "accentInk", text: root.t("bar.update"), app: "", summary: "", urgent: false };
        case "dnd":
            return { key: k, icon: "do_not_disturb_on", filled: true, tone: "ink", text: root.t("peek.dndOn"), app: "", summary: "", urgent: false };
        case "nightlight":
            return { key: k, icon: "dark_mode", filled: true, tone: "accentInk", text: root.t("peek.nightLightOn"), app: "", summary: "", urgent: false };
        case "stayAwake":
            return { key: k, icon: "coffee", filled: true, tone: "accentInk", text: root.t("peek.stayAwakeOn"), app: "", summary: "", urgent: false };
        case "urgent": {
            const summary = root.oneLine(r.summary || r.body || "", 140);
            return { key: k, icon: "notifications_active", filled: true, tone: "danger", text: summary, app: root.oneLine(r.app || "", 48), summary: summary, urgent: true, rowKey: String(r.key || "") };
        }
        default:
            return null;
        }
    }

    // Uma linha só: sem marcação, sem controles, sem quebras, entidades comuns
    // decodificadas; corta em maxLen (padrão 200).
    function oneLine(s, maxLen) {
        let text = String(s === null || s === undefined ? "" : s);
        text = text.replace(/<[^>]{0,200}>/g, " ");
        text = text.replace(/&(amp|lt|gt|quot|apos|#39|nbsp);/g, (m, e) => ({ amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", "#39": "'", nbsp: " " })[e]);
        text = text.replace(/[\u0000-\u001f\u007f\u2028\u2029]+/g, " ");
        text = text.replace(/\s+/g, " ").trim();
        const max = maxLen > 0 ? maxLen : 200;
        return text.length > max ? text.slice(0, max) : text;
    }

    // "m:ss" ou "h:mm:ss" com os algarismos do idioma; "" para tempo negativo.
    function clockText(sec) {
        const v = Math.floor(Number(sec));
        if (!(v >= 0))
            return "";
        const f = Commons.I18n.formatNumber;
        const pad2 = n => n < 10 ? f(0) + f(n) : f(n);
        const h = Math.floor(v / 3600), m = Math.floor((v % 3600) / 60), s = v % 60;
        return h > 0 ? f(h) + ":" + pad2(m) + ":" + pad2(s) : f(m) + ":" + pad2(s);
    }

    // "15 min", "2 h", "1 h 5 min" (bar.minutes / bar.hours / bar.hoursMinutes),
    // arredondando para cima o minuto que falta.
    function durationText(seconds) {
        const f = Commons.I18n.formatNumber;
        const mins = Math.max(1, Math.ceil((Number(seconds) || 0) / 60));
        if (mins < 60)
            return root.t("bar.minutes").arg(f(mins));
        const h = Math.floor(mins / 60), m = mins % 60;
        return m === 0 ? root.t("bar.hours").arg(f(h)) : root.t("bar.hoursMinutes").arg(f(h)).arg(f(m));
    }

    // ---- Bordas de subida (amendments §14.1) ----
    // key -> último valor (bool ou contagem). A primeira leitura só guarda.
    property var known: ({})
    // SETTLE_MS (4000) depois da partida: o que muda antes disso (proxies e
    // arquivos chegando) também só é guardado.
    property bool settled: false
    function track(key, value) {
        const had = Object.prototype.hasOwnProperty.call(root.known, key);
        const was = root.known[key];
        if (had && was === value)
            return;
        const next = Object.assign({}, root.known);
        next[key] = value;
        root.known = next;
        if (!had || !root.settled)
            return;
        if (key === "reminder" ? value > was : (!was && value))
            root.activated(key);
    }

    // Os indicadores que vêm de proxies ou arquivos passam aqui a cada mudança;
    // os de processo, a cada leitura (recordingProc, reminderProc, updateProc).
    onDndChanged: root.track("dnd", root.dnd)
    onNightlightChanged: root.track("nightlight", root.nightlight)
    onStayAwakeChanged: root.track("stayAwake", root.stayAwake)

    // ---- Ajudantes ----
    function clampK(k) {
        const v = Math.round(Number(k));
        return isFinite(v) ? Math.max(2500, Math.min(5800, v)) : 4000;
    }
    function preferredK() {
        return root.store ? root.clampK(root.store.nightK) : 4000;
    }

    // Comando de ação (nunca no harness). bash -lc 'exec "$@"': os argumentos
    // nunca são reinterpretados por um shell (Commons.Util.execArgv).
    function run(argv) {
        if (root.dev)
            return;
        Commons.Util.execArgv(argv);
    }

    // IPC do próprio processo; se o alvo não existe, omarchy-shell -q. true = rodou aqui.
    function ipcOrShell(target, method, args) {
        if (root.dev)
            return false;
        const r = Commons.IpcRegistry.call(target, method, args);
        if (r.ran)
            return true;
        root.run(["omarchy-shell", "-q", target, method].concat(args));
        return false;
    }

    // Roda uma sondagem; se já está rodando, roda de novo quando acabar.
    function kick(proc) {
        if (proc.running)
            proc.again = true;
        else
            proc.running = true;
    }

    // Valor otimista de um setter até a leitura concordar.
    property var held: ({})
    function holdValue(key, value) {
        const next = Object.assign({}, root.held);
        next[key] = value;
        root.held = next;
        if (!root.dev)
            heldTimer.restart();
    }
    function heldOr(key, real) {
        return Object.prototype.hasOwnProperty.call(root.held, key) ? root.held[key] : real;
    }
    function release(key, real) {
        if (!Object.prototype.hasOwnProperty.call(root.held, key) || root.held[key] !== real)
            return;
        const next = Object.assign({}, root.held);
        delete next[key];
        root.held = next;
    }

    // Luz noturna: k > 0 liga em k (sobe o hyprsunset se preciso); 0 volta ao
    // dia e à identidade. Uma por vez; a última pedida vale.
    function applyNight(k) {
        if (root.dev)
            return;
        if (nightApply.running) {
            priv.queuedK = k > 0 ? k : -1;
            return;
        }
        priv.applyingK = k;
        nightApply.command = k > 0
            ? ["bash", "-c", "pgrep -x hyprsunset >/dev/null || { setsid uwsm-app -- hyprsunset >/dev/null 2>&1 & sleep 1; }; hyprctl hyprsunset temperature \"$1\"", "_", String(k)]
            : ["bash", "-c", "pgrep -x hyprsunset >/dev/null || exit 0; hyprctl hyprsunset temperature 6500 && hyprctl hyprsunset identity"];
        nightApply.running = true;
    }

    // ---- Modo jogo (port do 1.x ControlPanel) ----
    function isTransparency(m) {
        return m === "opaque" || m === "transparent" || m === "glassy";
    }
    // Passos para ligar, a partir do estado lido (anim/gaps: true = ligado agora).
    function gameModeOnSteps(anim, gaps, mode) {
        if (!root.isTransparency(mode))
            return [];
        // JSON montado só com booleanos e um valor conhecido.
        const json = JSON.stringify({ animations: anim === true, gaps: gaps === true, transparency: mode });
        const steps = [["sh", "-c", "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/game-mode.json\"", "sh", root.stateDir, json]];
        if (anim)
            steps.push(["omarchy-hyprland-toggle", "no-animations", "on"]);
        if (gaps)
            steps.push(["omarchy-hyprland-toggle", "window-no-gaps", "on"]);
        if (mode !== "opaque")
            steps.push(["omarchy-hyprland-window-transparency", "opaque"]);
        return steps;
    }
    // Passos para desligar, a partir do game-mode.json salvo.
    function gameModeOffSteps(saved) {
        const steps = [];
        if (saved && typeof saved === "object") {
            if (saved.animations === true)
                steps.push(["omarchy-hyprland-toggle", "no-animations", "off"]);
            if (saved.gaps === true)
                steps.push(["omarchy-hyprland-toggle", "window-no-gaps", "off"]);
            if (root.isTransparency(saved.transparency) && saved.transparency !== "opaque")
                steps.push(["omarchy-hyprland-window-transparency", saved.transparency]);
        }
        steps.push(["rm", "-f", root.stateDir + "/game-mode.json"]);
        return steps;
    }
    function runGameSteps(steps) {
        if (steps.length === 0) {
            root.finishGame();
            return;
        }
        priv.gameQueue = steps;
        gameWatchdog.restart();
        root.nextGameStep();
    }
    function nextGameStep() {
        if (priv.gameQueue.length === 0) {
            root.finishGame();
            return;
        }
        const q = priv.gameQueue.slice();
        const cmd = q.shift();
        priv.gameQueue = q;
        // Único passo por sh: gravar o arquivo (sem ele não há como desfazer).
        priv.gameStepIsSave = cmd[0] === "sh";
        gameStep.command = cmd;
        gameStep.running = true;
    }
    function finishGame() {
        gameWatchdog.stop();
        priv.gameBusy = false;
        if (root.store)
            root.store.reloadGameMode();
        // A leitura do arquivo decide daqui a pouco.
        gameRelease.restart();
    }

    // ---- Leitura das notificações ----
    function parseList(text) {
        try {
            const v = JSON.parse(String(text || ""));
            return Array.isArray(v) ? v : null;
        } catch (e) {
            return null;
        }
    }
    // O valor se for texto; "" para o resto.
    function textOf(v) {
        return typeof v === typeof "" ? v : "";
    }
    function rowFrom(e, isLive) {
        const s = root.oneLine(e.summary, 140);
        const b = root.oneLine(e.body, 140);
        const ts = Number(e.ts);
        const closed = Number(e.closed_ts);
        const u = Number(e.urgency);
        return {
            key: String(e.key),
            app: root.oneLine(e.app, 48),
            summary: s !== "" ? s : b,
            body: s !== "" ? b : "",
            urgency: isFinite(u) ? u : 1,
            icon: root.textOf(e.appIcon),
            rawGlyph: root.textOf(e.glyph),
            ts: isFinite(ts) && ts > 0 ? ts * 1000 : (isFinite(closed) ? closed * 1000 : 0),
            closedAt: isFinite(closed) ? closed * 1000 : 0,
            live: isLive
        };
    }
    function readLive(text) {
        const list = root.parseList(text);
        // A gravação atômica tira o arquivo por um instante: isso não é uma lista vazia.
        if (list === null)
            return;
        const rows = [];
        for (let i = list.length - 1; i >= 0; i--) {
            const e = list[i];
            if (e && typeof e === "object" && typeof e.key === "string" && e.key !== "")
                rows.push(root.rowFrom(e, true));
        }
        priv.liveRows = rows;
        // Urgente nova: a mais recente com urgency 2 que ainda não estava na
        // lista. Lembra todas as chaves vistas, então dispensar uma notificação
        // nunca reanuncia outra que já estava lá; a primeira leitura só semeia.
        const seen = priv.seenKeys;
        const now = ({});
        let fresh = null;
        for (let i = 0; i < rows.length; i++) {
            now[rows[i].key] = true;
            if (!fresh && rows[i].urgency === 2 && !seen[rows[i].key])
                fresh = rows[i];
        }
        priv.seenKeys = now;
        if (fresh && root.settled && priv.liveRead)
            root.urgentArrived({ key: fresh.key, app: fresh.app, summary: fresh.summary, body: fresh.body });
        priv.liveRead = true;
    }
    function readHistory(text) {
        const list = root.parseList(text);
        if (list === null)
            return;
        const rows = [];
        for (let i = 0; i < list.length && rows.length < 100; i++) {
            const e = list[i];
            if (e && typeof e === "object" && typeof e.key === "string" && e.key !== "" && isFinite(Number(e.closed_ts)))
                rows.push(root.rowFrom(e, false));
        }
        rows.sort((a, b) => b.closedAt - a.closedAt);
        priv.historyRows = rows;
        priv.histNow = Date.now();
    }

    // ---- Lembrete: o "faltam N min" anda no minuto certo ----
    function armReminderTick() {
        const rem = root.nextReminderAt - Date.now() / 1000;
        if (root.reminderCount <= 0 || !(rem > 0)) {
            reminderTick.stop();
            return;
        }
        const frac = rem % 60;
        reminderTick.interval = Math.max(250, Math.round((frac > 0.05 ? frac : 60) * 1000) + 40);
        reminderTick.restart();
    }
    // "Em breve": um disparo REMINDER_SOON_S antes do lembrete mais próximo.
    function armReminderSoon() {
        soonTimer.stop();
        const at = root.nextReminderAt;
        const left = at - Date.now() / 1000;
        if (!(at > 0) || left <= Motion.TIMING.REMINDER_SOON_S + 5)
            return;
        priv.soonArmedAt = at;
        soonTimer.interval = Math.min(2147483647, Math.round((left - Motion.TIMING.REMINDER_SOON_S) * 1000));
        soonTimer.start();
    }

    onNextReminderAtChanged: {
        priv.remNow = Date.now() / 1000;
        root.armReminderSoon();
        root.armReminderTick();
    }
    onReminderCountChanged: root.armReminderTick()

    Component.onCompleted: {
        // Os de proxy / arquivo começam conhecidos; os de processo, na primeira leitura.
        root.track("dnd", root.dnd);
        root.track("nightlight", root.nightlight);
        root.track("stayAwake", root.stayAwake);
        Qt.callLater(root.refresh);
    }

    // ---- Estado interno ----
    readonly property QtObject _priv: QtObject {
        id: priv

        // Leituras sem proxy.
        property bool fileDnd: false
        property bool fileStay: false
        property int probedTemp: 0
        readonly property bool realDnd: root.notificationService ? root.notificationService.doNotDisturb === true : priv.fileDnd
        readonly property bool realNight: root.nightlightService ? root.nightlightService.enabled === true : (priv.probedTemp >= 1000 && priv.probedTemp < 6000)
        readonly property bool realStay: root.idleService ? root.idleService.stayAwake === true : priv.fileStay

        onRealDndChanged: root.release("dnd", priv.realDnd)
        onRealNightChanged: {
            root.release("nightlight", priv.realNight);
            root.kick(tempProbe);
        }
        onRealStayChanged: root.release("stayAwake", priv.realStay)
        onRecActiveChanged: root.release("recording", priv.recActive)
        onSudoOnChanged: root.release("sudo", priv.sudoOn)

        // Luz noturna.
        property int shownK: 0
        property int applyingK: 0
        property int queuedK: 0

        // Modo jogo: -1 = segue o arquivo; 0 / 1 = pedido em andamento.
        property int gameWant: -1
        property bool gameBusy: false
        property var gameQueue: []
        property bool gameStepIsSave: false
        property bool gmAnim: true
        property bool gmGaps: true

        // Gravação.
        property bool recActive: false
        property real recStart: 0
        property real nowSec: Date.now() / 1000

        // Sudo, lembretes, atualização.
        property bool sudoOn: false
        property int remCount: 0
        property real remNextAt: 0
        property string remNextMsg: ""
        property real remNow: Date.now() / 1000
        property real soonArmedAt: 0
        property real lastSoonAt: 0
        property bool updateOn: false
        // A primeira checagem é a do _updateFirst (5 s depois da partida).
        property real lastUpdateCheck: Date.now()

        // Notificações.
        property var liveRows: []
        property var historyRows: []
        property real histNow: Date.now()
        property bool liveRead: false
        property var seenKeys: ({})
    }

    // ---- Temporizadores ----
    readonly property Timer _settleTimer: Timer {
        interval: Motion.TIMING.SETTLE_MS
        running: true
        onTriggered: root.settled = true
    }

    // Solta todos os valores otimistas que a leitura não confirmou.
    readonly property Timer _heldTimer: Timer {
        id: heldTimer
        interval: 4000
        onTriggered: root.held = ({})
    }

    readonly property Timer _nightDebounce: Timer {
        id: nightDebounce
        interval: Motion.TIMING.NIGHT_DEBOUNCE_MS
        onTriggered: {
            if (priv.shownK > 0 && root.nightlight)
                root.applyNight(priv.shownK);
            else
                priv.shownK = 0;
        }
    }

    // Relógio de segundos só enquanto grava (o relógio da ilha fica em minutos).
    readonly property Timer _recTick: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.recording && priv.recStart > 0
        onTriggered: priv.nowSec = Date.now() / 1000
    }

    // Depois de pedir para parar a gravação: confere (o script também avisa).
    readonly property Timer _recheckTimer: Timer {
        id: recheckTimer
        interval: 1500
        onTriggered: root.kick(recordingProc)
    }

    readonly property Timer _reminderTick: Timer {
        id: reminderTick
        onTriggered: {
            priv.remNow = Date.now() / 1000;
            root.armReminderTick();
        }
    }

    readonly property Timer _soonTimer: Timer {
        id: soonTimer
        onTriggered: {
            const at = priv.soonArmedAt;
            if (root.reminderCount > 0 && root.nextReminderAt === at && priv.lastSoonAt !== at) {
                priv.lastSoonAt = at;
                priv.remNow = Date.now() / 1000;
                root.activated("reminder");
            }
        }
    }

    // Atualizações: a primeira 5 s depois da partida (não briga com o login), depois a cada 6 h.
    readonly property Timer _updateFirst: Timer {
        interval: 5000
        running: !root.dev
        onTriggered: root.refreshUpdates()
    }
    readonly property Timer _updatePoll: Timer {
        interval: Motion.TIMING.UPDATES_POLL_MS
        repeat: true
        running: !root.dev
        onTriggered: root.refreshUpdates()
    }

    // O corte de 24 h do histórico anda mesmo sem o arquivo mudar.
    readonly property Timer _historyAge: Timer {
        interval: 600000
        repeat: true
        running: priv.historyRows.length > 0
        onTriggered: priv.histNow = Date.now()
    }

    readonly property Timer _gameWatchdog: Timer {
        id: gameWatchdog
        // Um passo que não termina não deixa a alternância presa.
        interval: 30000
        onTriggered: {
            priv.gameQueue = [];
            root.finishGame();
        }
    }
    readonly property Timer _gameRelease: Timer {
        id: gameRelease
        interval: 600
        onTriggered: if (!priv.gameBusy) priv.gameWant = -1
    }

    // ---- Sondagens ----
    readonly property Process _recordingProc: Process {
        id: recordingProc
        property bool again: false
        command: ["omarchy-capture-screenrecording", "--status"]
        onExited: (code, status) => {
            const on = code === 0;
            priv.recActive = on;
            if (on) {
                if (priv.recStart <= 0)
                    root.kick(recStartProc);
            } else {
                priv.recStart = 0;
            }
            root.track("recording", on);
            if (recordingProc.again) {
                recordingProc.again = false;
                recordingProc.running = true;
            }
        }
    }

    // Início da gravação: a data do arquivo de pid. Sem ele, agora.
    readonly property Process _recStartProc: Process {
        id: recStartProc
        property bool again: false
        command: ["stat", "-c", "%Y", root.recPidFile]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!priv.recActive)
                    return;
                const t = parseInt(String(text).trim());
                priv.nowSec = Date.now() / 1000;
                priv.recStart = isFinite(t) && t > 0 && t <= priv.nowSec + 5 ? Math.min(t, priv.nowSec) : priv.nowSec;
            }
        }
        onExited: (code, status) => {
            if (code !== 0 && priv.recActive && priv.recStart <= 0) {
                priv.nowSec = Date.now() / 1000;
                priv.recStart = priv.nowSec;
            }
        }
    }

    readonly property Process _reminderProc: Process {
        id: reminderProc
        property bool again: false
        command: ["omarchy-reminder", "show", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const raw = String(text || "");
                const a = raw.indexOf("{"), b = raw.lastIndexOf("}");
                let data = null;
                if (a >= 0 && b > a) {
                    try {
                        data = JSON.parse(raw.slice(a, b + 1));
                    } catch (e) {
                        data = null;
                    }
                }
                const list = data && Array.isArray(data.reminders) ? data.reminders : [];
                let next = 0, msg = "";
                for (let i = 0; i < list.length; i++) {
                    const at = Number(list[i] && list[i].at);
                    if (isFinite(at) && at > 0 && (next === 0 || at < next)) {
                        next = at;
                        msg = String(list[i].message || "");
                    }
                }
                // O próximo antes da contagem: quem ouve a contagem já acha a hora certa.
                priv.remNextMsg = msg;
                priv.remNextAt = next;
                const count = data ? Math.max(0, Math.floor(Number(data.count) || 0)) : 0;
                priv.remCount = count;
                root.track("reminder", count);
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                priv.remNextMsg = "";
                priv.remNextAt = 0;
                priv.remCount = 0;
                root.track("reminder", 0);
            }
            if (reminderProc.again) {
                reminderProc.again = false;
                reminderProc.running = true;
            }
        }
    }

    readonly property Process _sudoProbe: Process {
        id: sudoProbe
        property bool again: false
        command: ["omarchy-sudo-passwordless", "--active"]
        onExited: (code, status) => {
            priv.sudoOn = code === 0 && status === 0;
            if (sudoProbe.again) {
                sudoProbe.again = false;
                sudoProbe.running = true;
            }
        }
    }

    readonly property Process _sudoDisableProc: Process {
        id: sudoDisableProc
        command: ["omarchy-sudo-passwordless", "--disable"]
        onExited: (code, status) => root.kick(sudoProbe)
    }

    readonly property Process _updateProc: Process {
        id: updateProc
        property bool again: false
        command: ["omarchy-update-available"]
        onExited: (code, status) => {
            priv.updateOn = code === 0;
            root.track("update", priv.updateOn);
            if (updateProc.again) {
                updateProc.again = false;
                updateProc.running = true;
            }
        }
    }

    // Temperatura atual do hyprsunset (só leitura).
    readonly property Process _tempProbe: Process {
        id: tempProbe
        property bool again: false
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // Só um número puro: a mensagem de erro sem o hyprsunset também tem algarismos.
                const m = String(text || "").match(/^\s*([0-9]{3,5})(\s*K)?\s*$/i);
                priv.probedTemp = m ? Number(m[1]) : 0;
            }
        }
        onExited: (code, status) => {
            if (code !== 0)
                priv.probedTemp = 0;
            if (tempProbe.again) {
                tempProbe.again = false;
                tempProbe.running = true;
            }
        }
    }

    readonly property Process _nightApply: Process {
        id: nightApply
        onExited: (code, status) => {
            const applied = priv.applyingK;
            if (priv.queuedK !== 0) {
                const k = priv.queuedK;
                priv.queuedK = 0;
                root.applyNight(k > 0 ? k : 0);
                return;
            }
            // O valor aplicado já vale como lido (a sondagem confirma em seguida),
            // para o controle não voltar um quadro ao valor antigo.
            if (applied > 0 && code === 0)
                priv.probedTemp = applied;
            if (applied > 0 && priv.shownK === applied)
                priv.shownK = 0;
            // O serviço do host relê o hyprsunset (fica com o mesmo estado que nós).
            Commons.IpcRegistry.call("nightlight", "refresh", []);
            root.kick(tempProbe);
        }
    }

    // Modo jogo: leitura antes de ligar, depois os passos um a um.
    readonly property Process _gmAnimProc: Process {
        id: gmAnimProc
        // 0 = animações desligadas.
        command: ["omarchy-hyprland-toggle-enabled", "no-animations"]
        onExited: (code, status) => {
            priv.gmAnim = code !== 0;
            gmGapsProc.running = true;
        }
    }
    readonly property Process _gmGapsProc: Process {
        id: gmGapsProc
        // 0 = espaçamento desligado.
        command: ["omarchy-hyprland-toggle-enabled", "window-no-gaps"]
        onExited: (code, status) => {
            priv.gmGaps = code !== 0;
            gmTransProc.running = true;
        }
    }
    readonly property Process _gmTransProc: Process {
        id: gmTransProc
        command: ["omarchy-hyprland-window-transparency"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.runGameSteps(root.gameModeOnSteps(priv.gmAnim, priv.gmGaps, String(text || "").trim()))
        }
    }
    readonly property Process _gameStep: Process {
        id: gameStep
        onExited: (code, status) => {
            // Sem o arquivo salvo não há como desfazer: não muda mais nada.
            if (code !== 0 && priv.gameStepIsSave) {
                priv.gameQueue = [];
                priv.gameWant = 0;
            }
            Qt.callLater(root.nextGameStep);
        }
    }

    // ---- Arquivos ----
    readonly property FileView _liveFile: FileView {
        id: liveFile
        path: root.notificationsDir + "/live.json"
        printErrors: false
        watchChanges: true
        onFileChanged: liveFile.reload()
        onLoaded: root.readLive(liveFile.text())
    }
    readonly property FileView _historyFile: FileView {
        id: historyFile
        path: root.notificationsDir + "/history.json"
        printErrors: false
        watchChanges: true
        onFileChanged: historyFile.reload()
        onLoaded: root.readHistory(historyFile.text())
    }
    // quiet.json: só sem o proxy das notificações.
    readonly property FileView _quietFile: FileView {
        id: quietFile
        path: root.notificationService ? "" : root.notificationsDir + "/quiet.json"
        printErrors: false
        watchChanges: true
        onFileChanged: quietFile.reload()
        onLoaded: {
            let v = null;
            try {
                v = JSON.parse(quietFile.text());
            } catch (e) {
                v = null;
            }
            priv.fileDnd = !!v && v.dnd === true;
        }
    }
    // A gravação atômica troca o arquivo por renomeação: vigiar a pasta pega isso.
    readonly property FileView _notificationsDirWatch: FileView {
        path: root.notificationsDir
        printErrors: false
        watchChanges: true
        onFileChanged: {
            liveFile.reload();
            historyFile.reload();
            if (!root.notificationService)
                quietFile.reload();
        }
    }
    // indicators/stay-awake: só sem o proxy do idle. Existe = manter acordado.
    readonly property FileView _stayFile: FileView {
        id: stayFile
        path: root.idleService ? "" : root.indicatorsDir + "/stay-awake"
        printErrors: false
        watchChanges: true
        onFileChanged: stayFile.reload()
        onLoaded: priv.fileStay = true
        onLoadFailed: error => priv.fileStay = false
    }
    readonly property FileView _indicatorsDirWatch: FileView {
        path: root.idleService ? "" : root.indicatorsDir
        printErrors: false
        watchChanges: true
        onFileChanged: stayFile.reload()
    }
}
