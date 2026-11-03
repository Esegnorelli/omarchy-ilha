pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
import "Motion.js" as Motion

// OSD na pílula (screens §4, host_contract "OSD TAKEOVER", amendments §14.4).
// Dono: Agent I. Só decide e guarda o estado; quem desenha é o OsdFace,
// dentro do recorte da IslandWindow (face "osd").
//
// De onde vem um OSD:
// 1. Do OSD do host (takeover). O item do plugin omarchy.osd é keepLoaded e
//    expõe opened, iconKey, message, value, maxValue, hasProgress e
//    duration. Os OSDs de script (omarchy-osd -> IPC osd show) e os de dentro
//    do processo (teclas de volume e brilho, troca de faixa) terminam todos
//    nele, então um vigia só cobre tudo. Na subida de opened (e a cada
//    value / iconKey / message com ele aberto), num Qt.callLater: tira uma
//    foto do estado, decide e SÓ ENTÃO esconde o do host. O host aparece
//    sempre que a Ilha não desenha: nunca fica sem retorno.
//    - duration 0 (fixo, ex.: o aviso de abrir app): fica no host.
//    - Barra escondida, tela cheia no monitor focado, ou uma tela que não
//      seja a Central aberta: fica no host.
//    - Central aberta: volume com sub "" / sound, ou brilho com sub "" /
//      display -> esconde o do host e não mostra nada (o slider anda).
//      Outro tipo com a Central aberta: fica no host.
//    - Senão: desenha na pílula do monitor focado e esconde o do host.
//    O item do host só é alcançável quando `shell` é o shell completo
//    (shell.panelLoaders). Para plugin de terceiros o host injeta o
//    PluginShellApi, que não tem panelLoaders: hostOsd fica nulo, o vigia
//    não liga e o OSD do Omarchy segue como sempre. `takeover` é a chave de
//    emergência do Phase 2 (o Ilha.qml liga).
// 2. Da própria Ilha e do IPC `ilha osd <json>` (show): a mesma decisão. Sem
//    poder desenhar (barra escondida, tela cheia, outra tela aberta), o
//    pedido vai para o OSD do host (shell.summon), que é quem sempre aparece.
// 3. Os dois OSDs fixos internos (os únicos fixos da pílula):
//    - Resolução: enquanto monitors.pendingResolution existir e a subpágina
//      Tela da Central não estiver à vista, "Manter esta resolução?
//      Revertendo em 7 s". Clique = manter. O MonitorSvc reverte sozinho.
//    - Reinício: manifest.version diferente de codeVersion, uma vez por
//      sessão, 8 s, "Reinicie o shell…". Clique roda omarchy-restart-shell
//      (nunca no harness). Com a barra escondida vai para o OSD do host.
//    Um OSD passageiro (volume, brilho…) passa na frente de um fixo; quando
//    ele some, o fixo volta (se ainda valer).
//
// payload (normalize): {kind, iconKey, glyph, rawGlyph, value, max, percent,
//   muted, text, title, artist, art, sticky, duration, internal, seq}
//   kind: "progress" | "message" | "media"
//   glyph: literal de dev/icons.txt (iconFor, o porte do OsdModel.iconFor);
//   rawGlyph: chave não-ASCII (glifo Nerd Font) desenhada como está na fonte
//   do sistema (Commons.Style.fontFamily).
//   seq: sobe a cada OSD novo; dentro do mesmo, a barra anima 120 ms.
//
// Clique (activate, chamado pela IslandWindow no toque da face "osd"):
// volume -> Central/Som; brilho -> Central/Tela; mídia -> Mídia; resolução
// -> manter; reinício -> reinicia o shell; outro -> dispensa.
QtObject {
    id: root

    // ---- Entradas (o Ilha.qml liga) ----
    property var island: null
    property var shell: null

    // ---- Estado ----
    property bool enabled: true
    // Chave de emergência do takeover do OSD do host (Phase 2).
    property bool takeover: false
    readonly property bool showing: root.st.showing
    // O payload atual. Os fixos e a mídia são vivos (contagem, idioma, capa).
    // Continua com o último depois de hide(): o fade de saída mostra o que
    // estava na tela.
    readonly property var payload: {
        const p = root.st.payload;
        if (!p)
            return null;
        const tick = root.st.tick;
        if (p.internal === "restart")
            return Object.assign({}, p, { text: root.t("bar.restartNotice") });
        if (p.internal === "resolution") {
            const r = root.pendingResolution();
            const s = r ? Math.max(0, Math.round(Number(r.secondsLeft) || 0)) : root.st.lastSeconds;
            return Object.assign({}, p, { text: root.t("display.keepPrompt").arg(Commons.I18n.formatNumber(s)), tick: tick });
        }
        if (p.kind === "media" && p.art === "") {
            const m = root.island ? root.island.media : null;
            if (m && m.artUrl && m.title && (p.title === m.title || p.title === "" || String(p.text).indexOf(m.title) === 0))
                return Object.assign({}, p, { art: String(m.artUrl) });
        }
        return p;
    }
    // Monitor onde o OSD aparece (o focado no momento do show).
    readonly property string output: root.st.output
    // Date.now() do último show (diagnóstico, amendments §14.4).
    readonly property real lastShownAt: root.st.lastShownAt
    // Qual fixo interno está na tela: "" | "resolution" | "restart". A dica da
    // linha não aparece com o aviso de reinício na tela.
    readonly property string internal: root.st.showing ? root.st.internal : ""
    // O item do OSD do host, quando alcançável (só com o shell completo).
    readonly property var hostOsd: {
        const s = root.shell;
        if (!s)
            return null;
        const loaders = s.panelLoaders;
        if (!loaders || typeof loaders !== "object")
            return null;
        const l = loaders["omarchy.osd"];
        return l && l.item ? l.item : null;
    }
    readonly property bool hostReachable: root.hostOsd !== null

    // Glifos aceitos em payload.glyph (IPC / chamadas internas). Fora disso
    // vale o mapa do iconFor pela chave.
    readonly property var payloadGlyphs: ({
        "volume_up": "volume_up", "volume_down": "volume_down", "volume_mute": "volume_mute", "volume_off": "volume_off",
        "mic": "mic", "mic_off": "mic_off", "keyboard": "keyboard", "light_mode": "light_mode", "dark_mode": "dark_mode",
        "touchpad_mouse": "touchpad_mouse", "touch_app": "touch_app", "restart_alt": "restart_alt",
        "power_settings_new": "power_settings_new", "logout": "logout", "lock": "lock", "bedtime": "bedtime",
        "music_note": "music_note", "play_arrow": "play_arrow", "pause": "pause", "skip_next": "skip_next",
        "skip_previous": "skip_previous", "shuffle": "shuffle", "repeat": "repeat", "repeat_one": "repeat_one",
        "info": "info", "notifications": "notifications", "notifications_active": "notifications_active",
        "do_not_disturb_on": "do_not_disturb_on", "wifi": "wifi", "wifi_off": "wifi_off", "lan": "lan",
        "bluetooth": "bluetooth", "bluetooth_disabled": "bluetooth_disabled", "headphones": "headphones",
        "speaker": "speaker", "desktop_windows": "desktop_windows", "bolt": "bolt", "coffee": "coffee",
        "alarm": "alarm", "check": "check", "close": "close", "palette": "palette", "wallpaper": "wallpaper",
        "screen_share": "screen_share", "fiber_manual_record": "fiber_manual_record",
        "system_update_alt": "system_update_alt", "mouse": "mouse", "mobile": "mobile", "movie": "movie"
    })

    // Chaves do host que são volume (o "mudo" pinta a barra de inkFaint).
    readonly property var volumeKeys: ["volume-muted", "volume-mute", "muted", "mute", "volume-low", "volume-medium", "volume-high", "volume"]
    readonly property var mutedKeys: ["volume-muted", "volume-mute", "muted", "mute", "microphone-muted", "microphone-off", "mic-muted", "mic-off"]

    // ---- API ----

    // JSON do IPC (ou objeto da própria Ilha) -> "ok" | "invalid" | "off".
    function show(payloadJson) {
        let p;
        try {
            p = typeof payloadJson === "string" ? JSON.parse(payloadJson || "{}") : payloadJson;
        } catch (e) {
            return "invalid";
        }
        if (!p || typeof p !== "object" || Array.isArray(p))
            return "invalid";
        if (!root.enabled)
            return "off";
        const n = root.normalize(p);
        if (n.text === "" && n.kind !== "progress" && n.rawGlyph === "" && n.glyph === "info")
            return "invalid";
        root.noteLevel(n);
        switch (root.route(n, false)) {
        case "none":
            return "ok";
        case "host":
            if (root.toHost(n))
                return "ok";
            break;
        }
        root.stOpen(n, root.focused(), "");
        return "ok";
    }

    // Um OSD de brilho com nível (teclas de brilho via `ilha osd`, ou o host
    // quando alcançável) leva o slider da Central e da Tela junto, sem gravar.
    function noteLevel(n) {
        const mons = root.island ? root.island.monitors : null;
        if (!mons || typeof mons.noteBrightness !== "function" || n.kind !== "progress" || root.classOf(n) !== "brightness")
            return;
        if (!isFinite(n.percent))
            return;
        const f = mons.focused;
        mons.noteBrightness(f ? f.name : "", Math.round(n.percent));
    }

    // OSD fixo (sem tempo): só some com hide() ou com o clique.
    function showSticky(p) {
        if (!root.enabled)
            return;
        const n = root.normalize(p || ({}));
        n.sticky = true;
        n.duration = 0;
        root.stOpen(n, root.focused(), n.internal);
    }

    // Esconde o que está na tela. Um fixo dispensado não volta; um fixo que
    // estava por baixo de um passageiro volta.
    function hide() {
        if (!root.st.showing)
            return;
        if (root.st.internal === "resolution")
            root.st.resDismissed = root.resIdentity(root.pendingResolution());
        else if (root.st.internal === "restart")
            root.st.restartUntil = 0;
        root.stClose();
        Qt.callLater(root.syncInternal);
    }

    // Toque na face "osd" (a IslandWindow chama). true = tratou.
    function activate(output) {
        if (!root.st.showing || !root.island)
            return false;
        const n = root.st.payload;
        const out = root.st.output !== "" ? root.st.output : String(output || "");
        if (root.st.internal === "resolution") {
            const r = root.pendingResolution();
            root.st.resDismissed = root.resIdentity(r);
            root.stClose();
            if (r && root.island.monitors && typeof root.island.monitors.keepResolution === "function")
                root.island.monitors.keepResolution();
            Qt.callLater(root.syncInternal);
            return true;
        }
        if (root.st.internal === "restart") {
            root.st.restartUntil = 0;
            root.stClose();
            root.restartShell();
            return true;
        }
        const cls = root.classOf(n);
        root.hide();
        if (cls === "volume")
            return root.island.open("control", out, { sub: "sound" });
        if (cls === "brightness")
            return root.island.open("control", out, { sub: "display" });
        if (cls === "media")
            return root.island.open("media", out);
        return true;
    }

    // Qualquer payload (o do host: {icon, message, value, progressText, max,
    // duration}; o da Ilha: {kind, glyph, value, text, …}) -> o payload da
    // pílula. Mesma semântica do OsdModel.stateForShow do host.
    function normalize(p) {
        const src = p && typeof p === "object" ? p : ({});
        const rawKey = String(src.iconKey !== undefined && src.iconKey !== null ? src.iconKey : (src.icon !== undefined && src.icon !== null ? src.icon : ""));
        const key = rawKey.toLowerCase();
        const nonAscii = /[^\x00-\x7f]/.test(rawKey);
        const kindIn = String(src.kind || "");
        const message = root.oneLine(src.text !== undefined && src.text !== null ? src.text : (src.message !== undefined && src.message !== null ? src.message : ""));
        const maxRaw = src.max !== undefined && src.max !== null && src.max !== "" ? src.max : src.maxValue;
        const max = Math.max(1, Math.round(Number(maxRaw !== undefined && maxRaw !== null && maxRaw !== "" ? maxRaw : 100)) || 100);
        const rawValue = src.value;
        const parsed = rawValue === undefined || rawValue === null || String(rawValue).trim() === "" ? NaN : Math.round(Number(rawValue));
        const valueOk = !isNaN(parsed) && isFinite(parsed);
        let progress;
        if (src.hasProgress !== undefined)
            progress = !!src.hasProgress && valueOk;
        else if (kindIn === "progress")
            progress = valueOk;
        else if (kindIn === "message" || kindIn === "media")
            progress = false;
        else
            progress = valueOk && message === "";
        const media = !progress && (kindIn === "media" || key.indexOf("media") === 0 || key.indexOf("player") === 0);
        const kind = progress ? "progress" : (media ? "media" : "message");
        const value = progress ? Math.max(0, Math.min(max, parsed)) : 0;
        const percent = progress ? Math.round(value * 100 / max) : -1;

        let text = message;
        if (progress) {
            const given = root.oneLine(src.progressText || (kindIn === "progress" || src.hasProgress !== undefined ? message : ""));
            text = given !== "" ? given : root.percentText(percent);
        }
        text = text.slice(0, 200);

        let title = root.oneLine(src.title || "");
        let artist = root.oneLine(src.artist || "");
        if (media && title === "" && message !== "") {
            // O host escreve "Título - Artista" (MediaModel.osdMessage).
            const cut = message.lastIndexOf(" - ");
            title = cut > 0 ? message.slice(0, cut) : message;
            artist = artist !== "" ? artist : (cut > 0 ? message.slice(cut + 3) : "");
        }

        const rawGlyph = String(src.rawGlyph || (nonAscii ? rawKey : "")).slice(0, 8);
        const wanted = String(src.glyph || "");
        const lead = rawGlyph !== "" ? "" : (root.payloadGlyphs[wanted] !== undefined ? root.payloadGlyphs[wanted] : root.iconFor(key, percent));
        const muted = src.muted !== undefined ? !!src.muted : root.mutedKeys.indexOf(key) !== -1;
        const parsedDuration = src.duration === undefined || src.duration === null || String(src.duration).trim() === "" ? NaN : parseInt(src.duration, 10);
        const duration = isNaN(parsedDuration) ? Motion.TIMING.OSD_DEFAULT_MS : Math.max(0, parsedDuration);

        return {
            kind: kind,
            iconKey: nonAscii ? "" : key,
            glyph: lead,
            rawGlyph: rawGlyph,
            value: value,
            max: max,
            percent: percent,
            muted: muted,
            text: text,
            title: title.slice(0, 160),
            artist: artist.slice(0, 120),
            art: String(src.art || ""),
            sticky: !!src.sticky || duration === 0,
            duration: duration,
            internal: String(src.internal || ""),
            seq: 0
        };
    }

    // Porte do OsdModel.iconFor (shell/plugins/osd/OsdModel.js, MIT) para
    // Material Symbols. Chave vazia: volume pelo valor (mensagem sem chave
    // ganha "info"). Chave ASCII desconhecida: "info".
    function iconFor(key, percent) {
        switch (String(key || "").toLowerCase()) {
        case "volume-muted":
        case "volume-mute":
        case "muted":
        case "mute":
            return "volume_off";
        case "volume-low":
            return "volume_mute";
        case "volume-medium":
            return "volume_down";
        case "volume-high":
        case "volume":
            return "volume_up";
        case "microphone-muted":
        case "microphone-off":
        case "mic-muted":
        case "mic-off":
            return "mic_off";
        case "microphone":
        case "mic":
            return "mic";
        case "keyboard":
            return "keyboard";
        case "brightness":
        case "display":
            return "light_mode";
        case "touchpad":
            return "touchpad_mouse";
        case "touch":
        case "touchscreen":
            return "touch_app";
        case "reboot":
        case "restart":
            return "restart_alt";
        case "shutdown":
        case "power":
        case "poweroff":
            return "power_settings_new";
        case "logout":
        case "sign-out":
        case "leave":
            return "logout";
        case "media":
        case "player":
        case "media-source":
        case "player-source":
            return "music_note";
        case "media-play":
        case "player-play":
            return "play_arrow";
        case "media-pause":
        case "player-pause":
            return "pause";
        case "media-next":
        case "player-next":
            return "skip_next";
        case "media-previous":
        case "player-previous":
            return "skip_previous";
        case "":
            if (percent < 0)
                return "info";
            if (percent <= 0)
                return "volume_off";
            if (percent <= 33)
                return "volume_mute";
            if (percent <= 66)
                return "volume_down";
            return "volume_up";
        default:
            return "info";
        }
    }

    // ---- Decisão ----

    // "volume" | "brightness" | "media" | "other" (Central aberta e clique).
    function classOf(n) {
        if (!n)
            return "other";
        const k = String(n.iconKey || "");
        if (root.volumeKeys.indexOf(k) !== -1)
            return "volume";
        if (k === "brightness" || k === "display")
            return "brightness";
        if (n.kind === "media")
            return "media";
        if (k === "" && n.rawGlyph === "") {
            const g = String(n.glyph || "");
            if (g.indexOf("volume_") === 0)
                return "volume";
            if (g === "light_mode")
                return "brightness";
        }
        return "other";
    }

    // Onde um OSD aparece: "pill" | "host" | "none" (Central aberta: o slider basta).
    function route(n, fromHost) {
        const isl = root.island;
        if (!isl)
            return "pill";
        // Fixo de fora (host ou `ilha osd` com duration 0/sticky) vai para o
        // host: os únicos fixos da pílula são os internos (resolução, reinício).
        if ((n.duration === 0 || n.sticky) && n.internal === "")
            return "host";
        if (isl.screen !== "") {
            if (isl.screen === "control") {
                const cls = root.classOf(n);
                const sub = String(isl.screenSub || "");
                if ((cls === "volume" && (sub === "" || sub === "sound")) || (cls === "brightness" && (sub === "" || sub === "display")))
                    return "none";
            }
            return "host";
        }
        if (isl.barHidden)
            return "host";
        if (isl.fullscreenOn(isl.focusedOutput()))
            return "host";
        return "pill";
    }

    // Vigia do host: decide no fim do evento, com o estado já completo.
    function hostChanged() {
        const h = root.hostOsd;
        if (h && h.opened)
            Qt.callLater(root.decide);
    }

    function decide() {
        const h = root.hostOsd;
        if (!h || !h.opened || !root.takeover || !root.enabled || !root.island)
            return;
        const progress = !!h.hasProgress;
        const n = root.normalize({
            iconKey: String(h.iconKey || ""),
            message: progress ? "" : String(h.message || ""),
            value: progress ? h.value : undefined,
            progressText: progress ? String(h.message || "") : "",
            max: h.maxValue,
            hasProgress: progress,
            duration: h.duration
        });
        const r = root.route(n, true);
        if (r === "host")
            return;
        if (r === "pill")
            root.stOpen(n, root.focused(), "");
        root.hideHost();
    }

    function hideHost() {
        const s = root.shell;
        if (s && typeof s.hide === "function")
            s.hide("omarchy.osd");
    }

    // Manda um payload para o OSD do host (quem sempre aparece). false sem host.
    function toHost(n) {
        const s = root.shell;
        if (!s || typeof s.summon !== "function")
            return false;
        const key = n.rawGlyph !== "" ? n.rawGlyph : root.hostKeyFor(n);
        const progress = n.kind === "progress";
        return s.summon("omarchy.osd", JSON.stringify({
            icon: key,
            message: progress ? "" : (n.kind === "media" && n.title !== "" ? (n.artist !== "" ? n.title + " - " + n.artist : n.title) : n.text),
            value: progress ? String(n.value) : "",
            progressText: progress ? n.text : "",
            max: String(n.max),
            duration: String(n.duration)
        })) !== false;
    }

    // Chave do host para um payload da Ilha (a própria iconKey, ou a do glifo).
    function hostKeyFor(n) {
        if (n.iconKey !== "")
            return n.iconKey;
        const byLead = {
            "volume_off": "volume-muted", "volume_mute": "volume-low", "volume_down": "volume-medium", "volume_up": "volume-high",
            "mic_off": "microphone-muted", "mic": "microphone", "keyboard": "keyboard", "light_mode": "brightness",
            "touchpad_mouse": "touchpad", "touch_app": "touchscreen", "restart_alt": "restart",
            "power_settings_new": "power", "logout": "logout", "music_note": "media", "play_arrow": "media-play",
            "pause": "media-pause", "skip_next": "media-next", "skip_previous": "media-previous"
        };
        const k = byLead[String(n.glyph || "")];
        return k !== undefined ? k : "";
    }

    // ---- Fixos internos ----

    function pendingResolution() {
        const m = root.island ? root.island.monitors : null;
        const r = m ? m.pendingResolution : null;
        return r && typeof r === "object" ? r : null;
    }

    function resIdentity(r) {
        if (!r)
            return "";
        let mode = "";
        try {
            mode = JSON.stringify(r.mode);
        } catch (e) {
            mode = String(r.mode);
        }
        return String(r.name || "") + "|" + mode;
    }

    // O fixo que deveria estar na tela agora ("" = nenhum).
    function wantedInternal() {
        const isl = root.island;
        if (!isl || !root.enabled)
            return "";
        const r = root.pendingResolution();
        const id = root.resIdentity(r);
        if (id === "")
            root.st.resDismissed = "";
        const ccDisplay = isl.screen === "control" && isl.screenSub === "display";
        if (id !== "" && id !== root.st.resDismissed && !ccDisplay && !isl.barHidden)
            return "resolution";
        if (root.st.restartUntil > Date.now() + 500 && !isl.barHidden)
            return "restart";
        return "";
    }

    // Põe na tela (ou tira) o fixo que vale agora. Um passageiro na frente
    // espera: este volta a rodar quando ele some.
    function syncInternal() {
        if (root.st.showing && root.st.internal === "")
            return;
        const want = root.wantedInternal();
        if (want === "") {
            if (root.st.showing)
                root.stClose();
            return;
        }
        if (want === "resolution") {
            const r = root.pendingResolution();
            root.st.lastSeconds = r ? Math.max(0, Math.round(Number(r.secondsLeft) || 0)) : 0;
        }
        if (root.st.showing && root.st.internal === want && root.outputAlive(root.st.output))
            return;
        const isl = root.island;
        const out = want === "resolution" && isl.screenOutput !== "" && root.outputAlive(isl.screenOutput) ? isl.screenOutput : root.focused();
        const lead = want === "resolution" ? "desktop_windows" : "restart_alt";
        const n = root.normalize({ kind: "message", glyph: lead, text: "", duration: 0, internal: want });
        n.sticky = true;
        root.stOpen(n, out, want);
    }

    // Aviso de reinício: uma vez por sessão, quando o manifest injetado não
    // bate com o código carregado (o host não limpa o cache de QML).
    readonly property bool needsRestart: !!root.island && root.island.manifestVersion !== "" && root.island.manifestVersion !== root.island.codeVersion
    onNeedsRestartChanged: root.checkVersion()

    function checkVersion() {
        if (root.st.restartDone || !root.needsRestart)
            return;
        root.st.restartDone = true;
        root.st.restartTries = 0;
        root.restartDelay.restart();
    }

    function tryRestartNotice() {
        const isl = root.island;
        if (!isl)
            return;
        if (isl.barHidden) {
            // Sem pílula à vista: o OSD do host avisa (só leitura, 8 s).
            const restartKey = "restart";
            const s = root.shell;
            if (s && typeof s.summon === "function")
                s.summon("omarchy.osd", JSON.stringify({ icon: restartKey, message: root.t("bar.restartNotice"), duration: String(Motion.TIMING.RESTART_NOTICE_MS) }));
            return;
        }
        const out = root.focused();
        const face = isl.faceOf(out);
        // Não corta tela, hover nem outro OSD: tenta de novo (até ~1 min).
        if ((isl.screen !== "" || (face !== "rest" && face !== "peek") || root.st.showing) && root.st.restartTries < 30) {
            root.st.restartTries++;
            root.restartDelay.restart();
            return;
        }
        root.st.restartUntil = Date.now() + Motion.TIMING.RESTART_NOTICE_MS;
        root.restartLife.interval = Motion.TIMING.RESTART_NOTICE_MS;
        root.restartLife.restart();
        root.syncInternal();
    }

    function restartShell() {
        if (root.island && root.island.dev) {
            console.log("ilha: harness, não reinicio o shell (omarchy-restart-shell)");
            return;
        }
        Quickshell.execDetached(["omarchy-restart-shell"]);
    }

    // ---- Ajudantes ----

    function focused() {
        return root.island ? root.island.focusedOutput() : "";
    }

    function outputAlive(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (String(screens[i].name) === String(name))
                return true;
        }
        return false;
    }

    function t(key) {
        const s = root.island ? root.island.strings : null;
        return s ? s.t(key) : key;
    }

    function percentText(percent) {
        return root.t("common.percent").arg(Commons.I18n.formatNumber(Math.max(0, percent)));
    }

    function oneLine(s) {
        return String(s === undefined || s === null ? "" : s).replace(/[\r\n\t]+/g, " ").replace(/\s{2,}/g, " ").trim();
    }

    // ---- Estado interno ----
    component OsdState: QtObject {
        property bool showing: false
        property var payload: null
        property string output: ""
        property real lastShownAt: 0
        property string internal: ""
        property int seq: 0
        property int tick: 0
        property int lastSeconds: 0
        // Fixos internos
        property string resDismissed: ""
        property real restartUntil: 0
        property bool restartDone: false
        property int restartTries: 0
    }

    property OsdState st: OsdState {}

    // Abre ou atualiza. Um OSD do mesmo tipo já na tela só troca o conteúdo
    // (a barra anima); o resto conta como novo (seq sobe).
    function stOpen(n, out, internalKind) {
        const fresh = !root.st.showing || root.st.output !== out || !root.st.payload
            || root.st.payload.kind !== n.kind || root.st.internal !== internalKind;
        if (fresh)
            root.st.seq++;
        n.seq = root.st.seq;
        n.internal = internalKind;
        root.st.payload = n;
        root.st.internal = internalKind;
        root.st.output = out;
        root.st.lastShownAt = Date.now();
        root.st.showing = true;
        if (!n.sticky && n.duration > 0) {
            root.hideTimer.interval = n.duration;
            root.hideTimer.restart();
        } else {
            root.hideTimer.stop();
        }
    }

    function stClose() {
        root.hideTimer.stop();
        root.st.showing = false;
    }


    // Tempo do passageiro: some `duration` ms depois da última atualização.
    property Timer hideTimer: Timer {
        onTriggered: {
            root.stClose();
            root.syncInternal();
        }
    }

    // Contagem da resolução: relê a cada segundo enquanto ela está na tela
    // (vale mesmo se o MonitorSvc mudar secondsLeft sem reatribuir o objeto).
    property Timer resolutionTick: Timer {
        interval: 1000
        repeat: true
        running: root.st.showing && root.st.internal === "resolution"
        onTriggered: root.st.tick++
    }

    property Timer restartDelay: Timer {
        interval: 2000
        onTriggered: root.tryRestartNotice()
    }

    property Timer restartLife: Timer {
        onTriggered: root.syncInternal()
    }

    // ---- Vigias ----
    property Connections hostWatch: Connections {
        target: root.takeover && root.enabled ? root.hostOsd : null
        ignoreUnknownSignals: true
        function onOpenedChanged() {
            root.hostChanged();
        }
        function onValueChanged() {
            root.hostChanged();
        }
        function onIconKeyChanged() {
            root.hostChanged();
        }
        function onMessageChanged() {
            root.hostChanged();
        }
    }

    property Connections monitorsWatch: Connections {
        target: root.island ? root.island.monitors : null
        ignoreUnknownSignals: true
        function onPendingResolutionChanged() {
            root.syncInternal();
        }
    }

    property Connections islandWatch: Connections {
        target: root.island
        ignoreUnknownSignals: true
        function onScreenChanged() {
            root.syncInternal();
        }
        function onScreenSubChanged() {
            root.syncInternal();
        }
        function onBarHiddenChanged() {
            if (root.island.barHidden && root.st.showing && root.st.internal === "") {
                // Sem pílula à vista: o passageiro some (o próximo vai ao host).
                root.stClose();
            }
            root.syncInternal();
        }
    }

    property Connections screensWatch: Connections {
        target: Quickshell
        function onScreensChanged() {
            // O monitor do OSD saiu: o passageiro some; o fixo muda de monitor.
            if (root.st.showing && !root.outputAlive(root.st.output)) {
                if (root.st.internal === "")
                    root.stClose();
                else
                    root.st.output = root.focused();
            }
        }
    }

    Component.onCompleted: root.checkVersion()
}
