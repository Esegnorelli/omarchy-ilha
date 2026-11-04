pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Motion.js" as Motion

// Aviso ao vivo (peek): quando um indicador liga (gravação, lembrete perto,
// atualização, Não perturbe, luz noturna, manter acordado) ou chega uma
// notificação URGENTE, a pílula vira uma frase curta por um instante e volta
// (amendments §9, §14.2). Dono: Agent I. Este objeto guarda o estado e as
// regras; quem desenha é o PeekFace, dentro do recorte da IslandWindow
// (face "peek", logo abaixo de "screen" e "osd").
//
// raise(key, row, force = false) -> "shown" | "queued" | "off" | "busy" | "quiet" | "unknown"
//   chave desconhecida                              -> "unknown"
//   !prefs.livePeek || barra escondida              -> "off" (force não passa por cima)
//   Não perturbe ligado e chave fora de {dnd, recording, urgent}, sem force -> "quiet"
//   tela aberta ou seletor aberto                   -> "busy" (nunca briga com tela nem foco)
//   tela cheia no monitor focado                    -> "busy"
//   já mostrando: prioridade >= a atual -> troca no lugar e reinicia o tempo -> "shown"
//                 senão fica na vaga (a de maior prioridade)                 -> "queued"
//   monitor focado em repouso                       -> mostra                -> "shown"
//   senão (seletor, L2, OSD na frente)                   -> vaga                  -> "queued"
//
// Vaga (uma só): a de maior prioridade fica; empate, a mais nova. Sai quando
// o monitor focado volta ao repouso ou quando o aviso atual termina. Cai
// depois de PEEK_PENDING_TTL (5 s) ou se a chave desligou (menos urgente e
// force). Abrir tela, seletor ou L2 (end()) esvazia a vaga.
//
// Na tela: PEEK_MS 2,6 s (urgente PEEK_URGENT_MS 4 s). hold(true) pausa
// (ponteiro na zona; a face continua "peek", nunca vira seletor); hold(false)
// recomeça com a cauda PEEK_TAIL_MS (1 s). Termina quando: o tempo acaba; a
// chave desliga (menos urgente e force); abre tela ou seletor; um OSD aparece
// no mesmo monitor (o OSD ganha); livePeek desliga ou a barra some; o
// monitor sai; dismiss() (botão direito). O aviso nunca pega o teclado.
//
// tap() abre o dono (§9.5) e termina sem esperar o fade:
//   recording / reminder / update -> L2 fixado na linha dessa chave (M)
//   dnd / nightlight              -> Central
//   stayAwake                     -> Central/Tela, cartão Manter acordado
//   urgent                        -> Central, cartão de notificações piscando a linha
QtObject {
    id: root

    // ---- Entradas (o Ilha.qml liga) ----
    property var island: null
    property var status: null
    property var prefs: null

    readonly property var priority: ({ urgent: 7, recording: 6, reminder: 5, update: 4, dnd: 3, nightlight: 2, stayAwake: 1 })
    // Chaves que passam pelo Não perturbe (decisão F).
    readonly property var dndAllowed: ["dnd", "recording", "urgent"]

    // ---- Estado ----
    readonly property bool showing: root.st.key !== ""
    readonly property string key: root.st.key
    // status.peekFor(key, row), reavaliado (a gravação anda de segundo em segundo).
    // Lê o par {key, row} de uma vez só (snap): uma troca nunca mistura a
    // chave nova com a linha antiga.
    readonly property var payload: !root.st.snap || !root.status ? null : root.status.peekFor(root.st.snap.key, root.st.snap.row)
    readonly property string output: root.st.output
    readonly property bool held: root.st.held
    // {key, row, force, at} | null
    readonly property var pending: root.st.pending

    // ---- API ----

    function raise(key, row, force) {
        const k = String(key || "");
        const forced = force === true;
        if (!Object.prototype.hasOwnProperty.call(root.priority, k))
            return "unknown";
        const why = root.gate(k, forced);
        if (why !== "")
            return why;
        const isl = root.island;
        const out = isl.focusedOutput();
        const r = row && typeof row === "object" ? row : null;

        if (root.showing) {
            if (root.priority[k] >= root.priority[root.st.key]) {
                root.place(k, r, forced, out);
                return "shown";
            }
            root.queue(k, r, forced);
            return "queued";
        }
        const face = isl.faceOf(out);
        if (face === "rest") {
            root.place(k, r, forced, out);
            return "shown";
        }
        root.queue(k, r, forced);
        return "queued";
    }

    // Ponteiro entrou (true) / saiu (false) da zona do aviso.
    function hold(on) {
        if (!root.showing)
            return;
        const want = !!on;
        if (want === root.st.held)
            return;
        root.st.held = want;
        if (want) {
            root.showTimer.stop();
        } else {
            root.showTimer.interval = Motion.TIMING.PEEK_TAIL_MS;
            root.showTimer.restart();
        }
    }

    // Toque: abre o dono e termina na hora (a face nova cobre o fade).
    function tap() {
        if (!root.showing || !root.island)
            return;
        const k = root.st.key;
        const out = root.st.output;
        const row = root.st.row || ({});
        const isl = root.island;
        root.end();
        switch (k) {
        case "recording":
        case "reminder":
        case "update":
            isl.setExpanded(out, true, k);
            break;
        case "dnd":
        case "nightlight":
            isl.open("control", out);
            break;
        case "stayAwake":
            isl.open("control", out, { sub: "display", focus: "stayAwake" });
            break;
        case "urgent":
            isl.open("control", out, { focus: "notifications", key: String(row.key || ""), app: String(row.app || ""), summary: String(row.summary || "") });
            break;
        }
    }

    // Botão direito: este some; o que estava na vaga ainda pode vir.
    function dismiss() {
        if (!root.showing)
            return;
        root.finish(true);
    }

    // Fim imediato (tela, seletor, L2, toque). A vaga também sai.
    function end() {
        root.st.pending = null;
        root.pendingTimer.stop();
        root.clear();
    }

    // ---- Interno ----

    // "" = pode mostrar agora; senão o motivo ("off" | "quiet" | "busy").
    function gate(k, forced) {
        const isl = root.island;
        if (!isl || !root.prefs || !root.prefs.livePeek || isl.barHidden)
            return "off";
        if (!forced && root.status && root.status.dnd && root.dndAllowed.indexOf(k) === -1)
            return "quiet";
        if (isl.screen !== "" || isl.pickerOutput !== "")
            return "busy";
        const out = isl.focusedOutput();
        if (out === "" || isl.fullscreenOn(out))
            return "busy";
        // Chave que já desligou não aparece (o force do IPC passa).
        if (!forced && !root.alive(k))
            return "quiet";
        return "";
    }

    // O aviso atual acabou: a vaga (se ainda valer) entra no lugar dele, como
    // uma troca (PEEK_SWAP), sem a forma voltar ao repouso no meio.
    function takePending() {
        const p = root.st.pending;
        if (!p)
            return false;
        root.st.pending = null;
        root.pendingTimer.stop();
        if (Date.now() - p.at > Motion.TIMING.PEEK_PENDING_TTL || root.gate(p.key, p.force) !== "")
            return false;
        root.place(p.key, p.row, p.force, root.island.focusedOutput());
        return true;
    }

    // Ainda vale? (urgente e force não dependem de indicador).
    function alive(k) {
        if (k === "urgent")
            return true;
        return !!root.status && root.status.isOn(k);
    }

    function place(k, row, forced, out) {
        // As ligações de fim (keyAlive, osdOnTop) esperam a troca inteira.
        root.st.placing = true;
        root.st.row = row;
        root.st.force = forced;
        root.st.output = out;
        root.st.shownAt = Date.now();
        root.st.key = k;
        root.st.snap = { key: k, row: row };
        root.st.placing = false;
        // Troca com o ponteiro dentro: o tempo continua pausado.
        if (root.st.held) {
            root.showTimer.stop();
        } else {
            root.showTimer.interval = k === "urgent" ? Motion.TIMING.PEEK_URGENT_MS : Motion.TIMING.PEEK_MS;
            root.showTimer.restart();
        }
    }

    function queue(k, row, forced) {
        const p = root.st.pending;
        if (p && Date.now() - p.at <= Motion.TIMING.PEEK_PENDING_TTL && root.priority[p.key] > root.priority[k])
            return;
        root.st.pending = { key: k, row: row, force: forced, at: Date.now() };
        root.pendingTimer.restart();
    }

    function clear() {
        root.showTimer.stop();
        root.st.snap = null;
        root.st.key = "";
        root.st.row = null;
        root.st.force = false;
        root.st.held = false;
    }

    // Termina o atual. Com flushAfter, a vaga entra no lugar (troca) ou,
    // se não puder agora, espera o repouso.
    function finish(flushAfter) {
        if (flushAfter && root.showing && root.takePending())
            return;
        root.clear();
        if (flushAfter)
            Qt.callLater(root.flush);
    }

    // A vaga entra se o monitor focado estiver em repouso; senão espera.
    function flush() {
        const p = root.st.pending;
        if (!p || root.showing || !root.island)
            return;
        if (Date.now() - p.at > Motion.TIMING.PEEK_PENDING_TTL || (!p.force && !root.alive(p.key))) {
            root.st.pending = null;
            root.pendingTimer.stop();
            return;
        }
        if (root.island.faceOf(root.island.focusedOutput()) !== "rest")
            return;
        root.st.pending = null;
        root.pendingTimer.stop();
        root.raise(p.key, p.row, p.force);
    }

    function outputAlive(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (String(screens[i].name) === String(name))
                return true;
        }
        return false;
    }

    // Regras de fim (§9.3). Cada uma é uma ligação; a mudança encerra.
    // (As reações vão no fim do evento: mexer no estado dentro do próprio
    // aviso de mudança reavaliaria a ligação no meio — laço.)
    readonly property bool keyAlive: root.st.placing || root.st.key === "" || root.st.force || root.alive(root.st.key)
    onKeyAliveChanged: if (!root.keyAlive) Qt.callLater(root.recheck)

    readonly property bool blocked: !!root.island && (root.island.screen !== "" || root.island.pickerOutput !== "")
    onBlockedChanged: if (root.blocked) root.end()

    readonly property bool switchedOff: !!root.island && (!root.prefs || !root.prefs.livePeek || root.island.barHidden)
    onSwitchedOffChanged: if (root.switchedOff) root.end()

    readonly property bool osdOnTop: !root.st.placing && !!root.island && !!root.island.osd && root.island.osd.showing && root.island.osd.output === root.st.output
    onOsdOnTopChanged: if (root.osdOnTop) Qt.callLater(root.recheck)

    function recheck() {
        if (!root.showing)
            return;
        if (root.osdOnTop)
            root.finish(false);
        else if (!root.keyAlive)
            root.finish(true);
    }

    // ---- Estado interno ----
    component PeekState: QtObject {
        property string key: ""
        property var row: null
        property bool force: false
        property string output: ""
        property bool held: false
        property real shownAt: 0
        property var pending: null
        property bool placing: false
        property var snap: null
    }

    property PeekState st: PeekState {}

    property Timer showTimer: Timer {
        onTriggered: {
            if (!root.st.held)
                root.finish(true);
        }
    }

    // A vaga cai sozinha depois do TTL (o estado de depuração não fica velho).
    property Timer pendingTimer: Timer {
        interval: Motion.TIMING.PEEK_PENDING_TTL + 50
        onTriggered: root.st.pending = null
    }

    // O monitor focado voltou ao repouso: a vaga entra.
    property Connections facesWatch: Connections {
        target: root.island
        ignoreUnknownSignals: true
        function onFacesChanged() {
            if (root.st.pending && !root.showing)
                Qt.callLater(root.flush);
        }
    }

    // O monitor do aviso saiu.
    property Connections screensWatch: Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.showing && !root.outputAlive(root.st.output))
                root.end();
        }
    }
}
