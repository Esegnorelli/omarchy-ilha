import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Motion.js" as Motion

// Monitores: brilho, escala e resolução de cada tela, com a contagem de
// "manter / reverter" da resolução vivendo aqui (screens §9). Dono: Agent E.
//
// Fontes (Omarchy, MIT): omarchy-monitor-state (linhas: brilho do focado,
// interno, externo, …, foco, escala, JSON dos monitores), o painel de
// monitores (shell/plugins/panels/monitor/Panel.qml e Model.js): o leitor do
// estado, a fila de comandos, o debounce do brilho e as regras de escala e
// de resolução (availableScales, matchingScaleIndex, resolutionOptions,
// refreshOptions).
//
// - displays: [{name, focused, width, height, refresh, scale, brightness,
//   hasBrightness, modes: [{width, height, refresh}], modeIndex,
//   scales: ["1", "1.25", …], scaleIndex}]. brightness em 0..100; refresh é a
//   taxa exata que o modo anuncia (o texto arredonda). focused segue o
//   monitor focado do Hyprland ao vivo.
// - Brilho: setBrightness mostra na hora e grava 180 ms depois do último
//   movimento (omarchy-brightness-display --no-osd --monitor N P%), uma
//   gravação por vez, só a última de cada monitor. Não relê depois de gravar:
//   o valor local manda (a releitura logo após corre com o driver e volta 0).
// - polling (gravável): a Central liga enquanto está aberta; lê na hora e a
//   cada 5 s. A sondagem pausa com gravação na fila ou rodando e por 2 s
//   depois; a leitura de um monitor com gravação pendente é ignorada.
// - Escala e resolução: um comando por vez, na ordem pedida; a tela mostra o
//   valor novo na hora e relê quando a fila esvazia.
// - pendingResolution: {name, mode, previous, secondsLeft} | null. O Timer de
//   10 s vive aqui e reverte sozinho, feche a Central ou não.
//
// No harness (ILHA_DEV=1) as escritas ficam só na memória: nada muda no
// sistema do usuário. A leitura é a real.
QtObject {
    id: root

    // ---- Entradas ----
    property var shell: null

    // ---- Estado ----
    readonly property var displays: {
        const fn = priv.focusName;
        const lv = priv.levels;
        return priv.base.map(d => Object.assign({}, d, {
            focused: fn !== "" ? d.name === fn : d.stateFocused,
            brightness: Object.prototype.hasOwnProperty.call(lv, d.name) ? lv[d.name] : d.brightness
        }));
    }
    readonly property var focused: {
        for (let i = 0; i < root.displays.length; i++) {
            if (root.displays[i].focused)
                return root.displays[i];
        }
        return root.displays.length > 0 ? root.displays[0] : null;
    }
    // Já houve uma leitura (antes dela displays é vazio).
    readonly property bool ready: priv.loaded
    property bool polling: false
    readonly property bool pendingWrite: debounce.running || brightProc.running || Object.keys(priv.queue).length > 0
    readonly property var pendingResolution: priv.pendingRes

    // ---- Comandos ----
    function refresh() {
        if (stateProc.running) {
            priv.reread = true;
            return;
        }
        priv.readStartedAt = Date.now();
        stateProc.running = true;
    }

    function setBrightness(name, pct) {
        const n = String(name || "");
        if (n === "" || !root.find(n))
            return;
        const p = root.clampBrightness(pct);
        const lv = Object.assign({}, priv.levels);
        lv[n] = p;
        priv.levels = lv;
        const want = Object.assign({}, priv.wanted);
        want[n] = p;
        priv.wanted = want;
        debounce.restart();
    }

    // Nível que mudou fora da Ilha (teclas de brilho: o OsdBridge repassa o
    // valor do OSD do host). Só mostra; não grava. Uma gravação local
    // pendente do mesmo monitor manda.
    function noteBrightness(name, pct) {
        const d = name ? root.find(name) : root.focused;
        const n = Number(pct);
        if (!d || !isFinite(n))
            return;
        if (Object.prototype.hasOwnProperty.call(priv.wanted, d.name) || Object.prototype.hasOwnProperty.call(priv.queue, d.name) || priv.writing === d.name)
            return;
        const lv = Object.assign({}, priv.levels);
        delete lv[d.name];
        priv.levels = lv;
        priv.patch(d.name, { brightness: Math.max(0, Math.min(100, Math.round(n))), hasBrightness: true });
    }

    function setScale(name, s) {
        const d = root.find(name);
        if (!d)
            return;
        const value = root.normalizeScale(s);
        if (value === "")
            return;
        // Mostra na hora a escala que o Hyprland vai aceitar (passos de 1/120).
        const clean = Number(root.cleanScale(value, d.width, d.height)) || Number(value);
        priv.patch(d.name, { scale: clean, scaleIndex: root.matchingScaleIndex(d.scales, clean, d.width, d.height) });
        root.runAction(["omarchy-hyprland-monitor-scaling", "--monitor", d.name, value]);
    }

    // mode: {width, height, refresh} ou "LxA@taxa".
    function setResolution(name, mode) {
        const d = root.find(name);
        const m = root.parseMode(mode);
        if (!d || !m)
            return;
        if (m.width === d.width && m.height === d.height && Math.abs(m.refresh - d.refresh) < 0.5)
            return;
        let previous = { width: d.width, height: d.height, refresh: d.refresh };
        const p = priv.pendingRes;
        if (p && p.name === d.name)
            previous = p.previous;
        else if (p)
            root.keepResolution();
        root.applyMode(d.name, m);
        priv.pendingRes = { name: d.name, mode: m, previous: previous, secondsLeft: Motion.TIMING.RESOLUTION_REVERT_S };
        countdown.restart();
    }

    function keepResolution() {
        countdown.stop();
        priv.pendingRes = null;
    }

    function revertResolution() {
        const p = priv.pendingRes;
        countdown.stop();
        priv.pendingRes = null;
        if (p && p.previous)
            root.applyMode(p.name, p.previous);
    }

    // ---- Interno ----
    readonly property bool dry: Quickshell.env("ILHA_DEV") === "1"
    // Escalas oferecidas (as do vídeo); availableScales tira as que dariam a
    // mesma escala efetiva no modo atual.
    readonly property var scalePresets: ["1", "1.25", "1.5", "1.75", "2"]

    function find(name) {
        const n = String(name || "");
        for (let i = 0; i < priv.base.length; i++) {
            if (priv.base[i].name === n)
                return priv.base[i];
        }
        return null;
    }

    function parseMode(mode) {
        if (mode && typeof mode === "object") {
            const w = Number(mode.width), h = Number(mode.height), r = Number(mode.refresh);
            return w > 0 && h > 0 && r > 0 ? { width: w, height: h, refresh: r } : null;
        }
        const m = /^(\d+)x(\d+)@([0-9.]+)/.exec(String(mode || ""));
        return m ? { width: Number(m[1]), height: Number(m[2]), refresh: Number(m[3]) } : null;
    }

    function applyMode(name, m) {
        const d = root.find(name);
        if (!d)
            return;
        const list = d.modes;
        let idx = -1;
        for (let i = 0; i < list.length; i++) {
            if (list[i].width === m.width && list[i].height === m.height && Math.abs(list[i].refresh - m.refresh) < 0.5)
                idx = i;
        }
        priv.patch(name, { width: m.width, height: m.height, refresh: m.refresh, modeIndex: idx });
        root.runAction(["omarchy-hyprland-monitor-resolution", "--monitor", name,
            m.width + "x" + m.height + "@" + Number(m.refresh).toFixed(2)]);
    }

    // Um comando de monitor por vez; relê quando a fila esvazia.
    function runAction(command) {
        if (root.dry)
            return;
        priv.actions = priv.actions.concat([command]);
        root.runNextAction();
    }

    function runNextAction() {
        if (actionProc.running)
            return;
        if (priv.actions.length === 0) {
            root.refresh();
            return;
        }
        actionProc.command = priv.actions[0];
        priv.actions = priv.actions.slice(1);
        actionProc.running = true;
    }

    function runWrite() {
        if (brightProc.running)
            return;
        const names = Object.keys(priv.queue);
        if (names.length === 0)
            return;
        const n = names[0];
        const p = priv.queue[n];
        const q = Object.assign({}, priv.queue);
        delete q[n];
        priv.queue = q;
        priv.writing = n;
        brightProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", n, p + "%"];
        brightProc.running = true;
    }

    // ---- Regras do Model.js do monitor do Omarchy (MIT) ----
    function clampBrightness(value) {
        const n = Number(value);
        if (!isFinite(n))
            return 1;
        return Math.max(1, Math.min(100, Math.round(n)));
    }

    function normalizeScale(scale) {
        const n = parseFloat(String(scale === undefined || scale === null ? "" : scale));
        if (!isFinite(n) || n <= 0)
            return "";
        return String(Math.round(n * 100) / 100);
    }

    function gcd(a, b) {
        while (b) {
            const r = a % b;
            a = b;
            b = r;
        }
        return a;
    }

    // O Hyprland só aceita escalas que dividem o modo em pixels lógicos
    // inteiros (passos de 1/120): arredonda para cima até a próxima limpa.
    function cleanScale(scale, width, height) {
        const req = Number(scale), w = Number(width), h = Number(height);
        if (!isFinite(req) || !isFinite(w) || !isFinite(h) || req <= 0 || w <= 0 || h <= 0)
            return "";
        const divisor = root.gcd(Math.round(w * 120), Math.round(h * 120));
        let units = Math.round(req * 120);
        if (units > divisor)
            units = divisor;
        while (divisor % units !== 0)
            units++;
        return root.normalizeScale(units / 120);
    }

    function matchingScaleIndex(scales, current, width, height) {
        const cur = Number(current);
        if (!scales || !isFinite(cur))
            return -1;
        const want = root.normalizeScale(cur);
        let best = -1, bestDistance = Infinity;
        for (let i = 0; i < scales.length; i++) {
            if (root.cleanScale(scales[i], width, height) !== want)
                continue;
            const distance = Math.abs(Number(scales[i]) - cur);
            if (distance < bestDistance) {
                best = i;
                bestDistance = distance;
            }
        }
        return best;
    }

    function availableScales(scales, width, height) {
        if (Number(width) <= 0 || Number(height) <= 0)
            return scales.slice();
        const byEffective = {};
        for (let i = 0; i < scales.length; i++) {
            const requested = Number(scales[i]);
            const effective = Number(root.cleanScale(requested, width, height));
            if (!isFinite(requested) || !isFinite(effective))
                continue;
            const key = root.normalizeScale(effective);
            const existing = byEffective[key];
            if (!existing || Math.abs(requested - effective) < existing.distance)
                byEffective[key] = { value: String(scales[i]), index: i, distance: Math.abs(requested - effective) };
        }
        return Object.keys(byEffective).map(k => byEffective[k]).sort((a, b) => a.index - b.index).map(c => c.value);
    }

    // As fichas: as escalas oferecidas e, se a atual não estiver entre elas
    // (1.6 do Omarchy, 3…), a atual no lugar da vizinha mais próxima. No
    // máximo 5; a escala de verdade sempre aparece marcada.
    function scaleChips(scale, width, height) {
        const list = root.availableScales(root.scalePresets, width, height);
        if (root.matchingScaleIndex(list, scale, width, height) >= 0 || !(Number(scale) > 0))
            return list.slice(0, 5);
        const cur = root.normalizeScale(scale);
        if (list.length >= 5) {
            let near = 0;
            for (let i = 1; i < list.length; i++) {
                if (Math.abs(Number(list[i]) - Number(cur)) < Math.abs(Number(list[near]) - Number(cur)))
                    near = i;
            }
            list.splice(near, 1);
        }
        list.push(cur);
        list.sort((a, b) => Number(a) - Number(b));
        return list.slice(0, 5);
    }

    // Modos para a lista inline (no máximo 6, maior primeiro): as resoluções
    // de resolutionOptions (a nativa e as menores com o mesmo formato, até
    // 1080p) na taxa mais rápida de cada uma; na resolução atual, cada taxa
    // inteira de refreshOptions (só quando alguma passa de 60 Hz). O modo
    // atual sempre aparece.
    function modesFor(available, width, height, refresh) {
        const all = [];
        const sizes = {};
        for (let i = 0; i < (available || []).length; i++) {
            const m = /^(\d+)x(\d+)@([0-9.]+)/.exec(String(available[i]));
            if (!m)
                continue;
            const w = Number(m[1]), h = Number(m[2]), r = parseFloat(m[3]);
            if (!(w > 0 && h > 0 && r > 0))
                continue;
            all.push({ width: w, height: h, refresh: r });
            sizes[w + "x" + h] = { w: w, h: h };
        }
        const cur = { width: Number(width), height: Number(height), refresh: Number(refresh) };
        const keys = Object.keys(sizes).map(k => sizes[k]).sort((a, b) => b.w * b.h - a.w * a.h || b.w - a.w);
        if (keys.length === 0)
            return cur.width > 0 ? [cur] : [];
        const native = keys[0];
        const aspect = native.w / native.h;
        let options = keys.filter(s => s.h >= 1080 && Math.abs(s.w / s.h - aspect) < 0.01).slice(0, 5);
        if (sizes[cur.width + "x" + cur.height] && !options.some(s => s.w === cur.width && s.h === cur.height))
            options.push(sizes[cur.width + "x" + cur.height]);
        if (options.length === 0)
            options = [native];
        options.sort((a, b) => b.w * b.h - a.w * a.h || b.w - a.w);

        const fastest = (w, h) => {
            let best = null;
            for (let i = 0; i < all.length; i++) {
                if (all[i].width === w && all[i].height === h && (!best || all[i].refresh > best.refresh))
                    best = all[i];
            }
            return best;
        };
        // Taxas da resolução atual: uma por taxa inteira (59,94 e 60 são a
        // mesma escolha), de 60 Hz para cima, só se alguma passar de 60.
        const rates = {};
        for (let i = 0; i < all.length; i++) {
            const m = all[i];
            if (m.width !== cur.width || m.height !== cur.height || m.refresh < 59.5)
                continue;
            const whole = Math.round(m.refresh);
            if (!rates[whole] || m.refresh > rates[whole].refresh)
                rates[whole] = m;
        }
        const wholes = Object.keys(rates).map(Number).sort((a, b) => b - a);
        const multi = wholes.length >= 2 && wholes[0] > 60;

        const out = [];
        for (let i = 0; i < options.length; i++) {
            const s = options[i];
            if (s.w === cur.width && s.h === cur.height && multi) {
                for (let j = 0; j < wholes.length; j++)
                    out.push(rates[wholes[j]]);
            } else {
                const f = fastest(s.w, s.h);
                if (f)
                    out.push(f);
            }
        }
        if (!out.some(m => m.width === cur.width && m.height === cur.height && Math.abs(m.refresh - cur.refresh) < 0.5) && cur.width > 0)
            out.push(cur);
        out.sort((a, b) => b.width * b.height - a.width * a.height || b.width - a.width || b.refresh - a.refresh);
        // Até 6: se passar, tira de baixo sem tirar o atual.
        while (out.length > 6) {
            let drop = out.length - 1;
            if (out[drop].width === cur.width && out[drop].height === cur.height && Math.abs(out[drop].refresh - cur.refresh) < 0.5)
                drop--;
            out.splice(drop, 1);
        }
        return out.map(m => ({ width: m.width, height: m.height, refresh: m.refresh }));
    }

    function modeIndexFor(modes, width, height, refresh) {
        for (let i = 0; i < modes.length; i++) {
            if (modes[i].width === width && modes[i].height === height && Math.abs(modes[i].refresh - refresh) < 0.5)
                return i;
        }
        return -1;
    }

    function parseState(raw) {
        const lines = String(raw || "").split("\n");
        let list = [];
        try {
            list = JSON.parse(String(lines[7] || "[]").trim() || "[]");
        } catch (e) {
            list = [];
        }
        if (!Array.isArray(list))
            return;
        // Monitores com gravação de brilho pendente (ou recém gravada, antes
        // de uma leitura que começou depois da pausa) ficam com o valor local.
        const lv = Object.assign({}, priv.levels);
        const rows = [];
        for (let i = 0; i < list.length; i++) {
            const d = list[i];
            if (!d || !d.name || !d.enabled || !(Number(d.width) > 0))
                continue;
            const name = String(d.name);
            const w = Number(d.width), h = Number(d.height), r = Number(d.refreshRate) || 0;
            const scale = Number(root.normalizeScale(d.scale)) || 1;
            const scales = root.scaleChips(scale, w, h);
            const modes = root.modesFor(d.availableModes, w, h, r);
            const has = typeof d.brightness === "number";
            const busy = Object.prototype.hasOwnProperty.call(priv.wanted, name) || Object.prototype.hasOwnProperty.call(priv.queue, name)
                || priv.writing === name || priv.readStartedAt < (priv.wroteAt[name] || 0) + Motion.TIMING.MONITOR_PAUSE_MS;
            if (Object.prototype.hasOwnProperty.call(lv, name) && !busy && !root.dry)
                delete lv[name];
            rows.push({
                name: name,
                stateFocused: !!d.focused,
                width: w,
                height: h,
                refresh: r,
                scale: scale,
                brightness: has ? Math.max(0, Math.min(100, Math.round(d.brightness))) : 0,
                hasBrightness: has,
                modes: modes,
                modeIndex: root.modeIndexFor(modes, w, h, r),
                scales: scales,
                scaleIndex: root.matchingScaleIndex(scales, scale, w, h)
            });
        }
        // Monitor que saiu leva o valor local junto.
        for (const k in lv) {
            if (!rows.some(x => x.name === k))
                delete lv[k];
        }
        priv.levels = lv;
        // No harness a escala/resolução escolhidas ficam por cima da leitura.
        priv.base = root.dry && priv.loaded ? rows.map(x => {
            const old = root.find(x.name);
            return old ? Object.assign({}, x, { width: old.width, height: old.height, refresh: old.refresh, scale: old.scale,
                modeIndex: old.modeIndex, scaleIndex: old.scaleIndex }) : x;
        }) : rows;
        priv.loaded = true;
        const p = priv.pendingRes;
        if (p && !rows.some(x => x.name === p.name))
            root.keepResolution();
    }

    property QtObject _priv: QtObject {
        id: priv
        property var base: []
        property bool loaded: false
        // Nível mostrado na hora (antes e logo depois da gravação).
        property var levels: ({})
        // Pedidos no debounce, fila de gravação (último por monitor) e quem grava.
        property var wanted: ({})
        property var queue: ({})
        property string writing: ""
        // Quando a última gravação de cada monitor terminou (ms).
        property var wroteAt: ({})
        property real readStartedAt: 0
        property bool reread: false
        property var actions: []
        property var pendingRes: null
        readonly property string focusName: Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""

        function patch(name, fields) {
            priv.base = priv.base.map(d => d.name === name ? Object.assign({}, d, fields) : d);
        }
    }

    // Brilho: grava 180 ms depois do último movimento.
    property Timer _debounce: Timer {
        id: debounce
        interval: Motion.TIMING.BRIGHTNESS_COMMIT_MS
        onTriggered: {
            const q = Object.assign({}, priv.queue, priv.wanted);
            priv.wanted = ({});
            if (root.dry)
                return;
            priv.queue = q;
            root.runWrite();
        }
    }

    property Process _brightProc: Process {
        id: brightProc
        stdout: StdioCollector {
            waitForEnd: true
        }
        onRunningChanged: {
            if (running)
                return;
            const w = Object.assign({}, priv.wroteAt);
            w[priv.writing] = Date.now();
            priv.wroteAt = w;
            priv.writing = "";
            pause.restart();
            Qt.callLater(root.runWrite);
        }
    }

    // A sondagem fica parada 2 s depois da última gravação.
    property Timer _pause: Timer {
        id: pause
        interval: Motion.TIMING.MONITOR_PAUSE_MS
    }

    property Timer _poll: Timer {
        id: poll
        interval: Motion.TIMING.MONITOR_POLL_MS
        running: root.polling
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.pendingWrite || pause.running)
                return;
            root.refresh();
        }
    }

    property Process _stateProc: Process {
        id: stateProc
        command: ["omarchy-monitor-state"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseState(text)
        }
        onRunningChanged: {
            if (running || !priv.reread)
                return;
            priv.reread = false;
            Qt.callLater(root.refresh);
        }
    }

    property Process _actionProc: Process {
        id: actionProc
        stdout: StdioCollector {
            waitForEnd: true
        }
        onRunningChanged: {
            if (!running)
                Qt.callLater(root.runNextAction);
        }
    }

    // Contagem do "manter esta resolução?": reverte sozinho no zero.
    property Timer _countdown: Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            const p = priv.pendingRes;
            if (!p) {
                countdown.stop();
                return;
            }
            const s = p.secondsLeft - 1;
            if (s <= 0)
                root.revertResolution();
            else
                priv.pendingRes = Object.assign({}, p, { secondsLeft: s });
        }
    }

    // Monitor ligado, desligado ou config recarregada: relê (agrupado).
    property Timer _hotplug: Timer {
        id: hotplug
        interval: 600
        onTriggered: root.refresh()
    }
    property Connections _hyprEvents: Connections {
        id: hyprEvents
        target: Hyprland
        function onRawEvent(event) {
            const n = event ? String(event.name || "") : "";
            if (n === "monitoradded" || n === "monitoraddedv2" || n === "monitorremoved" || n === "monitorremovedv2" || n === "configreloaded")
                hotplug.restart();
        }
    }

    // Uma leitura logo depois do início, para a Central abrir com o brilho certo.
    property Timer _warm: Timer {
        id: warm
        interval: Motion.TIMING.WARM_START_MS
        running: true
        onTriggered: root.refresh()
    }
}
