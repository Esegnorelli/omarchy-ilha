import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Captura (spec §3.4, painel 3): três linhas de ícones, com legenda.
//   PRINT     Q Região · W Tela inteira · E Janela · R Rolagem
//   GRAVAÇÃO  A Gravar região · S Gravar tela · D Som do sistema · F Mic na gravação
//             (gravando: A+S viram "Parar gravação 00:42" em danger, c1–c2; D/F indisponíveis)
//   EXTRAIR   Z Texto (OCR) · X QR code · C Conta-gotas
// ⇧Q = A e ⇧W = S. Tudo que gera pixels fecha a ilha antes (350 ms).
//
// Contrato de estado: active, closeRequested(), navigate(target), fg/bg/accent/danger,
// metrics, keyboardMode, footerStatus, footerHints, footerAlert,
// handleKey(event) → bool, handleEscape() → bool, focusFirst().
Item {
    id: root

    // Cores do tema (o host passa os mesmos tokens).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent

    // O host liga enquanto este estado está visível.
    property bool active: false
    property Metrics metrics: Metrics {}
    property bool keyboardMode: false

    signal closeRequested()
    signal navigate(string target)

    implicitWidth: metrics.content
    implicitHeight: grid.implicitHeight

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // ---------- Estado da gravação ----------
    property bool recording: false
    property bool statusKnown: false
    // Início da gravação (segundos epoch); 0 = desconhecido.
    property real recStart: 0
    property real nowSec: Date.now() / 1000

    // Opções de áudio somadas ao comando de gravar.
    property bool withDesktopAudio: false
    property bool withMicrophone: false

    // Mesmo arquivo de pid que o comando de gravação grava ao começar: a data
    // dele é o início da gravação.
    readonly property string recPidFile: (Quickshell.env("XDG_RUNTIME_DIR")
                                          || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy"))
                                         + "/omarchy-screenrecord-pid"

    // Código de saída 0 = há uma gravação em andamento.
    Process {
        id: statusProc
        command: ["omarchy", "capture", "screenrecording", "--status"]
        onExited: (exitCode, exitStatus) => {
            const was = root.recording;
            root.recording = exitCode === 0;
            root.statusKnown = true;
            if (root.recording && (!was || root.recStart === 0)) startProc.running = true;
            if (!root.recording) root.recStart = 0;
        }
    }
    Process {
        id: startProc
        command: ["stat", "-c", "%Y", root.recPidFile]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = parseInt(text.trim());
                root.recStart = isFinite(t) && t > 0 ? t : Date.now() / 1000;
            }
        }
        onExited: (exitCode, exitStatus) => { if (exitCode !== 0 && root.recStart === 0) root.recStart = Date.now() / 1000; }
    }

    function refresh() {
        if (!statusProc.running) statusProc.running = true;
    }

    // Relê o estado de vez em quando com o painel aberto (a gravação pode
    // terminar pelo indicador ou por outro atalho).
    Timer {
        interval: 2000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.recording
        triggeredOnStart: true
        onTriggered: root.nowSec = Date.now() / 1000
    }

    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()

    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    readonly property string elapsedText: {
        if (!recording || recStart <= 0) return "";
        const s = Math.max(0, Math.floor(nowSec - recStart));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        return h > 0 ? h + ":" + pad2(m) + ":" + pad2(sec) : pad2(m) + ":" + pad2(sec);
    }

    // ---------- Execução ----------
    // Fecha a ilha e roda o comando depois que ela sumiu da tela.
    function runAfterClose(cmd) {
        root.closeRequested();
        const wait = (root.metrics.msCloseFirst / 1000).toFixed(2);
        Quickshell.execDetached(["sh", "-c", "sleep \"$0\"; exec \"$@\"", wait].concat(cmd));
    }

    function screenshot(mode) {
        runAfterClose(["omarchy", "capture", "screenshot", mode]);
    }

    function startRecording(fullscreen) {
        const cmd = ["omarchy", "capture", "screenrecording"];
        if (fullscreen) cmd.push("--fullscreen");
        if (root.withDesktopAudio) cmd.push("--with-desktop-audio");
        if (root.withMicrophone) cmd.push("--with-microphone-audio");
        runAfterClose(cmd);
    }

    function stopRecording() {
        root.recording = false;
        root.recStart = 0;
        runAfterClose(["omarchy", "capture", "screenrecording", "--stop-recording"]);
    }

    // ---------- Rodapé ----------
    readonly property string footerStatus: recording ? strings.t("capture.footerRecording") : strings.t("capture.ready")
    readonly property bool footerAlert: recording
    readonly property string footerHints: recording ? strings.t("hint.captureRecording") : strings.t("hint.capture")

    // ---------- Teclado ----------
    function handleKey(event) {
        // ⇧Q / ⇧W = A / S (gravar sob o print equivalente, ou parar).
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier);
        if (mods === Qt.ShiftModifier && (event.key === Qt.Key_Q || event.key === Qt.Key_W)) {
            const it = grid.itemAtKey(1, event.key === Qt.Key_Q ? 0 : 1);
            if (!it) return false;
            if (event.isAutoRepeat) return true;
            if (it.activeFocusOnTab) it.forceActiveFocus(Qt.ShortcutFocusReason);
            it.activate();
            return true;
        }
        return grid.handleKey(event);
    }
    function handleEscape() { return grid.handleEscape(); }
    function focusFirst() { return grid.focusFirst(); }

    // ---------- Layout ----------
    PanelGrid {
        id: grid
        metrics: root.metrics
        strings: strings
        keyboardMode: root.keyboardMode
        fg: root.fg
        bg: root.bg
        accent: root.accent
        danger: root.danger

        GridRow {
            caption: strings.t("capture.section.print")
            Tile {
                iconFace: true
                icon: "screenshot_region"
                label: strings.t("capture.region")
                closesIsland: true
                onActivated: root.screenshot("region")
            }
            Tile {
                iconFace: true
                icon: "desktop_windows"
                label: strings.t("capture.fullscreen")
                closesIsland: true
                onActivated: root.screenshot("fullscreen")
            }
            Tile {
                iconFace: true
                icon: "select_window"
                label: strings.t("capture.window")
                closesIsland: true
                onActivated: root.screenshot("windows")
            }
            Tile {
                iconFace: true
                icon: "swipe_vertical"
                label: strings.t("capture.scroll")
                closesIsland: true
                onActivated: root.screenshot("scroll")
            }
        }

        GridRow {
            caption: strings.t("capture.section.rec")
            captionStatus: root.recording
                           ? (root.elapsedText !== "" ? strings.t("capture.recordingWithTime").arg(root.elapsedText)
                                                      : strings.t("capture.recordingNow"))
                           : ""
            captionStatusAlert: root.recording

            // Gravando: um bloco só em c1–c2 (responde a A, S, ⇧Q e ⇧W).
            Tile {
                visible: root.recording
                iconFace: true
                span: 2
                icon: "stop_circle"
                label: root.elapsedText !== "" ? strings.t("capture.stopWithTime").arg(root.elapsedText)
                                               : strings.t("capture.stop")
                sublabel: strings.t("capture.stopHint")
                on: true
                tone: "danger"
                closesIsland: true
                onActivated: root.stopRecording()
            }
            Tile {
                visible: !root.recording
                iconFace: true
                icon: "videocam"
                label: strings.t("capture.recordRegion")
                closesIsland: true
                onActivated: root.startRecording(false)
            }
            Tile {
                visible: !root.recording
                iconFace: true
                icon: "screen_record"
                label: strings.t("capture.recordScreen")
                closesIsland: true
                onActivated: root.startRecording(true)
            }
            Tile {
                iconFace: true
                kind: "toggle"
                icon: root.withDesktopAudio ? "volume_up" : "volume_off"
                label: strings.t("capture.desktopAudioRec")
                sublabel: root.withDesktopAudio ? strings.t("control.on") : strings.t("control.off")
                on: root.withDesktopAudio
                available: !root.recording
                unavailableText: strings.t("capture.beforeRecording")
                onActivated: root.withDesktopAudio = !root.withDesktopAudio
            }
            Tile {
                iconFace: true
                kind: "toggle"
                icon: root.withMicrophone ? "mic" : "mic_off"
                label: strings.t("capture.micRec")
                sublabel: root.withMicrophone ? strings.t("control.on") : strings.t("control.off")
                on: root.withMicrophone
                available: !root.recording
                unavailableText: strings.t("capture.beforeRecording")
                onActivated: root.withMicrophone = !root.withMicrophone
            }
        }

        GridRow {
            caption: strings.t("capture.section.extract")
            Tile {
                iconFace: true
                icon: "text_fields"
                label: strings.t("capture.ocr")
                closesIsland: true
                onActivated: root.runAfterClose(["omarchy", "capture", "text"])
            }
            Tile {
                iconFace: true
                icon: "qr_code_scanner"
                label: strings.t("capture.qr")
                closesIsland: true
                onActivated: root.runAfterClose(["omarchy", "capture", "qr"])
            }
            Tile {
                iconFace: true
                icon: "colorize"
                label: strings.t("capture.picker")
                closesIsland: true
                onActivated: root.runAfterClose(["hyprpicker", "-a"])
            }
        }
    }
}
