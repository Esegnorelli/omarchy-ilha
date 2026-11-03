import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons as Commons
import "Motion.js" as Motion

// Som: saída e entrada padrão, volumes, mudo e as listas de aparelhos da
// subpágina Som (screens §8). Dono: Agent E.
//
// Regras do painel de áudio do Omarchy (shell/plugins/panels/audio/Panel.qml
// e Model.js, MIT), portadas aqui:
// - Saídas: nós isSink que não são stream nem escondidos pela plataforma
//   (Commons.AudioNodes.platformHides), filtrados pela disponibilidade
//   (omarchy-audio-sink-availability). A saída padrão sempre aparece.
// - Entradas: fontes tipadas e as virtuais sem PwNode.audio (que o Pulse lista);
//   o volume e o mudo dessas vão pelo wpctl (Commons.UntypedInput).
// - O volume mora no "sink de volume": uma saída DSP (afinação, EasyEffects)
//   resolve para a física com omarchy-audio-output-sink, como as teclas.
// - Trocar o padrão: Pipewire.preferredDefault… e o script set-default.
// - As listas são linhas primitivas {node, name, label, glyph, selected}: uma
//   linha que guardasse o PwNode derrubaria o shell quando o PipeWire apaga o
//   nó durante a montagem do delegado. As linhas saem de um retrato tirado
//   75 ms depois da última mudança do grafo.
// - A sondagem de disponibilidade (5 s) só roda com a subpágina aberta
//   (detailOpen).
//
// glyph é um literal de dev/icons.txt: "desktop_windows" (HDMI/DisplayPort),
// "headphones", "bluetooth", "speaker" ou "mic". volume / micVolume em 0..1.
//
// No harness (ILHA_DEV=1) as escritas ficam só na memória: nada muda no
// sistema do usuário. A leitura é a real.
QtObject {
    id: root

    // ---- Entradas ----
    property var shell: null

    // ---- Estado ----
    readonly property var sinks: priv.sinkRows
    readonly property var sources: priv.sourceRows
    readonly property var sink: root.pick(priv.sinkRows)
    readonly property var source: root.pick(priv.sourceRows)

    readonly property bool hasOutput: !!(root.volumeSink && root.volumeSink.audio)
    readonly property bool hasInput: !!(root.pwSource && root.pwSource.audio) || (root.inputViaWpctl && Commons.UntypedInput.known)

    readonly property real volume: priv.has("volume") ? priv.shadow.volume
        : (root.volumeSink && root.volumeSink.audio ? Math.max(0, Math.min(1, root.volumeSink.audio.volume)) : 0)
    readonly property bool muted: priv.has("muted") ? priv.shadow.muted
        : (root.volumeSink && root.volumeSink.audio ? root.volumeSink.audio.muted : false)
    readonly property real micVolume: priv.has("micVolume") ? priv.shadow.micVolume
        : root.inputViaWpctl ? Math.max(0, Math.min(1, Commons.UntypedInput.volume))
        : (root.pwSource && root.pwSource.audio ? Math.max(0, Math.min(1, root.pwSource.audio.volume)) : 0)
    readonly property bool micMuted: priv.has("micMuted") ? priv.shadow.micMuted
        : root.inputViaWpctl ? Commons.UntypedInput.muted
        : (root.pwSource && root.pwSource.audio ? root.pwSource.audio.muted : false)

    // A subpágina Som liga enquanto está aberta (sondagem de disponibilidade).
    property bool detailOpen: false

    // ---- Comandos ----
    function setVolume(v) {
        const x = Math.max(0, Math.min(1, Number(v) || 0));
        if (root.dry) {
            priv.put("volume", x);
            return;
        }
        if (root.volumeSink && root.volumeSink.audio)
            root.volumeSink.audio.volume = x;
    }

    function setMuted(on) {
        if (root.dry) {
            priv.put("muted", !!on);
            return;
        }
        if (root.volumeSink && root.volumeSink.audio)
            root.volumeSink.audio.muted = !!on;
    }

    function toggleMute() {
        root.setMuted(!root.muted);
    }

    function setMicVolume(v) {
        const x = Math.max(0, Math.min(1, Number(v) || 0));
        if (root.dry) {
            priv.put("micVolume", x);
            return;
        }
        if (root.inputViaWpctl)
            Commons.UntypedInput.setVolume(x);
        else if (root.pwSource && root.pwSource.audio)
            root.pwSource.audio.volume = x;
    }

    function setMicMuted(on) {
        if (root.dry) {
            priv.put("micMuted", !!on);
            return;
        }
        if (root.inputViaWpctl) {
            if (Commons.UntypedInput.known)
                Commons.UntypedInput.setMuted(!!on);
        } else if (root.pwSource && root.pwSource.audio) {
            root.pwSource.audio.muted = !!on;
        }
    }

    // node: o id (number) de uma linha de sinks, ou a própria linha.
    function selectSink(node) {
        const row = root.rowFor(priv.sinkRows, node);
        if (!row || row.selected)
            return;
        if (root.dry) {
            priv.put("sinkId", row.node);
            priv.snapshot();
            return;
        }
        const n = root.nodeFor(row);
        if (!n)
            return;
        Pipewire.preferredDefaultAudioSink = n;
        Quickshell.execDetached(["omarchy-audio-output-set-default", String(n.id), String(n.name)]);
    }

    function selectSource(node) {
        const row = root.rowFor(priv.sourceRows, node);
        if (!row || row.selected)
            return;
        if (root.dry) {
            priv.put("sourceId", row.node);
            priv.snapshot();
            return;
        }
        const n = root.nodeFor(row);
        if (!n)
            return;
        // O Quickshell recusa um nó sem tipo; o script escolhe assim mesmo.
        if (n.audio)
            Pipewire.preferredDefaultAudioSource = n;
        Quickshell.execDetached(["omarchy-audio-input-set-default", String(n.id), String(n.name)]);
    }

    // ---- Interno: PipeWire ----
    readonly property bool dry: Quickshell.env("ILHA_DEV") === "1"

    readonly property var pwSink: Pipewire.defaultAudioSink
    readonly property var pwSource: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

    readonly property var nodeNames: {
        const names = [];
        for (let i = 0; i < root.nodes.length; i++) {
            if (root.nodes[i] && root.nodes[i].name)
                names.push(String(root.nodes[i].name));
        }
        return names;
    }

    readonly property var candidateSinks: {
        const list = [];
        for (let i = 0; i < root.nodes.length; i++) {
            const n = root.nodes[i];
            if (!n || !n.isSink || n.isStream || root.platformHides(n))
                continue;
            list.push(n);
        }
        return list;
    }

    readonly property var candidateSources: {
        const list = [];
        for (let i = 0; i < root.nodes.length; i++) {
            const n = root.nodes[i];
            if (!n || n.isSink || n.isStream)
                continue;
            if (!root.isAudioSource(n) && !root.isUntypedSource(n))
                continue;
            const name = String(n.name || "");
            if (Commons.AudioNodes.isShellLevelMeter(name) || root.platformHides(n))
                continue;
            list.push(n);
        }
        return list;
    }

    readonly property var rawSinks: {
        const list = [];
        for (let i = 0; i < root.candidateSinks.length; i++) {
            if (root.sinkAvailable(root.candidateSinks[i]))
                list.push(root.candidateSinks[i]);
        }
        if (root.pwSink && list.indexOf(root.pwSink) < 0)
            list.unshift(root.pwSink);
        return list;
    }

    readonly property var rawSources: {
        const list = root.candidateSources.slice();
        if (root.pwSource && list.indexOf(root.pwSource) < 0)
            list.unshift(root.pwSource);
        return list;
    }

    // Linhas ao vivo (primitivas). O retrato em priv sai 75 ms depois.
    readonly property var liveSinkRows: {
        const sel = priv.has("sinkId") ? priv.shadow.sinkId : (root.pwSink ? root.pwSink.id : -1);
        return root.rawSinks.map(n => ({
            node: n.id, name: String(n.name || ""), label: root.nodeLabel(n),
            glyph: root.sinkGlyph(n), selected: n.id === sel
        }));
    }
    readonly property var liveSourceRows: {
        const sel = priv.has("sourceId") ? priv.shadow.sourceId : (root.pwSource ? root.pwSource.id : -1);
        return root.rawSources.map(n => ({
            node: n.id, name: String(n.name || ""), label: root.nodeLabel(n),
            glyph: root.sourceGlyph(n), selected: n.id === sel
        }));
    }
    onLiveSinkRowsChanged: rowsTimer.restart()
    onLiveSourceRowsChanged: rowsTimer.restart()

    // Entrada virtual (sem PwNode.audio): volume e mudo pelo wpctl.
    readonly property bool inputViaWpctl: Commons.UntypedInput.active

    // Sink de volume (DSP -> física), resolvido pelo script do Omarchy.
    property string volumeSinkName: ""
    // Atribuído (não binding): ler os nós do Pipewire no meio da avaliação
    // faz eles emitirem mudança na mesma passada, e o binding entrava em loop
    // no shell real. pickVolumeSink() roda um ciclo depois de cada mudança.
    property var volumeSink: null
    function pickVolumeSink() {
        let found = root.pwSink;
        if (root.volumeSinkName !== "" && root.pwSink && root.volumeSinkName !== String(root.pwSink.name)) {
            for (let i = 0; i < root.nodes.length; i++) {
                const n = root.nodes[i];
                if (n && n.isSink && !n.isStream && String(n.name) === root.volumeSinkName) {
                    found = n;
                    break;
                }
            }
        }
        if (root.volumeSink !== found)
            root.volumeSink = found;
    }
    onVolumeSinkNameChanged: Qt.callLater(root.pickVolumeSink)
    onPwSinkChanged: {
        root.resolveVolumeSink();
        Qt.callLater(root.pickVolumeSink);
        Qt.callLater(root.syncTrackedDefaults);
    }
    onNodesChanged: {
        resolveTimer.restart();
        Qt.callLater(root.pickVolumeSink);
    }

    property var sinkAvailability: ({})
    property bool sinkAvailabilityLoaded: false
    property var sourceAvailability: ({})

    function pick(rows) {
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].selected)
                return rows[i];
        }
        return rows.length > 0 ? rows[0] : null;
    }

    function rowFor(rows, node) {
        const id = node !== null && typeof node === "object" ? node.node : Number(node);
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].node === id)
                return rows[i];
        }
        return null;
    }

    // O nó vivo de uma linha (id + nome: o PipeWire reaproveita ids).
    function nodeFor(row) {
        if (!row)
            return null;
        for (let i = 0; i < root.nodes.length; i++) {
            const n = root.nodes[i];
            if (n && n.id === row.node && String(n.name || "") === row.name)
                return n;
        }
        return null;
    }

    function platformHides(node) {
        return !!node && Commons.AudioNodes.platformHides(node.name, root.nodeNames);
    }

    // Model.js do Omarchy (MIT): isAudioSource, isUntypedSource, nodeLabel,
    // friendlyDeviceLabel, isHeadphones e os glifos de aparelho.
    function isAudioSource(node) {
        if (!node)
            return false;
        if (node.audio)
            return true;
        const mediaClass = String(node.type || "");
        return mediaClass.indexOf("Audio/Source") !== -1 || mediaClass.indexOf("AudioSource") !== -1 || mediaClass.indexOf("Source") !== -1;
    }

    function isUntypedSource(node) {
        if (!node || node.audio || node.isStream || node.isSink)
            return false;
        const name = String(node.name || "");
        return name !== "" && Object.prototype.hasOwnProperty.call(root.sourceAvailability, name);
    }

    function nodeProps(node) {
        return node && node.ready && node.properties ? node.properties : ({});
    }

    function friendlyDeviceLabel(text) {
        let label = String(text || "").trim();
        label = label.replace(/^sof-soundwire\s+/i, "");
        label = label.replace(/^built-?in audio\s+/i, "");
        label = label.replace(/\s+Output$/i, "");
        label = label.replace(/\s+Input$/i, "");
        label = label.replace(/\bMicrophones\b/g, "Microphone");
        return label;
    }

    function nodeLabel(node) {
        if (!node)
            return "";
        const p = root.nodeProps(node);
        const nick = root.friendlyDeviceLabel(node.nickname || p["node.nick"] || p["device.profile.description"] || "");
        if (nick)
            return nick;
        return root.friendlyDeviceLabel(node.description || p["node.description"] || node.name || "");
    }

    function deviceBlob(node, extra) {
        const p = root.nodeProps(node);
        const parts = [node.name, node.description, node.nickname, p["device.icon-name"] || ""];
        if (extra)
            parts.push(p["device.product.name"] || "", p["node.description"] || "", p["node.nick"] || "");
        return String(parts.join(" ")).toLowerCase();
    }

    function isHeadphones(node) {
        if (!node)
            return false;
        const b = root.deviceBlob(node, true);
        return b.indexOf("headphone") !== -1 || b.indexOf("headset") !== -1 || b.indexOf("earbud") !== -1
            || b.indexOf("earphone") !== -1 || b.indexOf("airpod") !== -1;
    }

    function sinkGlyph(node) {
        if (!node)
            return "speaker";
        if (root.isHeadphones(node))
            return "headphones";
        const b = root.deviceBlob(node, true);
        if (b.indexOf("bluetooth") !== -1)
            return "bluetooth";
        if (b.indexOf("hdmi") !== -1 || b.indexOf("display") !== -1)
            return "desktop_windows";
        return "speaker";
    }

    function sourceGlyph(node) {
        if (!node)
            return "mic";
        const b = root.deviceBlob(node, false);
        if (b.indexOf("headset") !== -1)
            return "headphones";
        if (b.indexOf("bluetooth") !== -1)
            return "bluetooth";
        return "mic";
    }

    function sinkAvailable(node) {
        if (!node || !node.name || !root.sinkAvailabilityLoaded)
            return true;
        return root.sinkAvailability[String(node.name)] !== false;
    }

    function parseAvailability(raw) {
        const next = {};
        const lines = String(raw || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line)
                continue;
            const parts = line.split("\t");
            if (parts.length >= 2)
                next[parts[0]] = parts[1] !== "0";
        }
        return next;
    }

    // Uma saída de hardware é o próprio sink de volume; só uma DSP precisa
    // do script (que segue a cadeia até a física).
    function resolveVolumeSink() {
        priv.generation++;
        if (root.pwSink && String(root.pwSink.name).indexOf("alsa_output.") === 0) {
            root.volumeSinkName = String(root.pwSink.name);
            return;
        }
        if (volumeSinkProc.running) {
            priv.volumeSinkStale = true;
            return;
        }
        priv.request = priv.generation;
        volumeSinkProc.running = true;
    }

    // ---- Interno: objetos ----
    property QtObject _priv: QtObject {
        id: priv
        property var sinkRows: []
        property var sourceRows: []
        // Só no harness: as escritas ficam aqui por cima da leitura real.
        property var shadow: ({})
        property int generation: 0
        property int request: -1
        property bool volumeSinkStale: false

        function has(key) {
            return Object.prototype.hasOwnProperty.call(priv.shadow, key);
        }

        function put(key, value) {
            const next = Object.assign({}, priv.shadow);
            next[key] = value;
            priv.shadow = next;
        }

        function snapshot() {
            priv.sinkRows = root.liveSinkRows;
            priv.sourceRows = root.liveSourceRows;
        }
    }

    // Os nós listados (e os padrões) precisam estar ligados para ter .audio.
    property PwObjectTracker _tracker: PwObjectTracker {
        id: tracker
        objects: root.candidateSinks.concat(root.candidateSources)
    }
    // Um ciclo depois: ligar o nó muda propriedades que o volumeSink lê, e
    // ligar na mesma passada da avaliação dava binding loop.
    property var trackedDefaults: []
    function syncTrackedDefaults() {
        root.trackedDefaults = [root.pwSink, root.pwSource, root.volumeSink].filter(n => !!n);
    }
    onVolumeSinkChanged: Qt.callLater(root.syncTrackedDefaults)
    onPwSourceChanged: Qt.callLater(root.syncTrackedDefaults)
    property PwObjectTracker _defaultsTracker: PwObjectTracker {
        id: defaultsTracker
        objects: root.trackedDefaults
    }

    // Retrato das linhas: 75 ms depois da última mudança do grafo.
    property Timer _rowsTimer: Timer {
        id: rowsTimer
        interval: 75
        onTriggered: priv.snapshot()
    }

    property Timer _resolveTimer: Timer {
        id: resolveTimer
        interval: 500
        onTriggered: root.resolveVolumeSink()
    }

    property Connections _links: Connections {
        id: links
        target: Pipewire.linkGroups
        function onValuesChanged() {
            resolveTimer.restart();
        }
    }

    // EasyEffects ocioso resolve pelo aparelho configurado, que muda sem
    // mexer no grafo.
    property FileView _easyEffects: FileView {
        id: easyEffects
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/easyeffects/db/easyeffectsrc"
        watchChanges: true
        printErrors: false
        onFileChanged: resolveTimer.restart()
    }

    property Process _volumeSinkProc: Process {
        id: volumeSinkProc
        command: ["omarchy-audio-output-sink"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (priv.request === priv.generation)
                    root.volumeSinkName = String(text).trim();
            }
        }
        onExited: {
            if (!priv.volumeSinkStale)
                return;
            priv.volumeSinkStale = false;
            Qt.callLater(root.resolveVolumeSink);
        }
    }

    property Process _sinkAvailabilityProc: Process {
        id: sinkAvailabilityProc
        command: ["omarchy-audio-sink-availability"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.sinkAvailability = root.parseAvailability(text);
                root.sinkAvailabilityLoaded = true;
            }
        }
    }

    property Process _sourceAvailabilityProc: Process {
        id: sourceAvailabilityProc
        command: ["omarchy-audio-sink-availability", "sources"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.sourceAvailability = root.parseAvailability(text)
        }
    }

    // Disponibilidade: a cada 5 s, só com a subpágina aberta.
    property Timer _availabilityPoll: Timer {
        id: availabilityPoll
        interval: Motion.TIMING.AUDIO_POLL_MS
        running: root.detailOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!sinkAvailabilityProc.running)
                sinkAvailabilityProc.running = true;
            if (!sourceAvailabilityProc.running)
                sourceAvailabilityProc.running = true;
        }
    }

    Component.onCompleted: {
        root.pickVolumeSink();
        root.syncTrackedDefaults();
        root.resolveVolumeSink();
        priv.snapshot();
    }
}
