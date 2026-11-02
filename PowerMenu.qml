import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Energia (spec §3.4): sempre 3 + 3, na grade de 3 colunas iguais.
//   Q Bloquear · W Suspender · E Hibernar       (ações seguras)
//   A Sair     · S Reiniciar · D Desligar        (confirm: dois toques)
// Suspender e hibernar ficam esmaecidos no lugar quando o sistema não deixa
// (com o motivo na sublinha); a grade nunca muda de forma.
// Cada ação é um botão quadrado arredondado (ícone + nome), 88 de altura.
//
// Contrato com o host: active, fg/bg/accent/danger, metrics, keyboardMode,
// closeRequested(), navigate(target), footerStatus, footerHints, footerAlert,
// handleKey(event) → bool, handleEscape() → bool, focusFirst().
Item {
    id: root

    // Cores do tema (o host passa os mesmos tokens).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted

    // O host liga enquanto este estado está visível.
    property bool active: false
    property bool keyboardMode: false
    property Metrics metrics: Metrics {}
    // Texto secundário (sublinhas, legendas): o token compartilhado do
    // Metrics, um passo mais claro que o muted; sem ele, o muted do tema.
    readonly property var _tokens: metrics
    readonly property color textSecondary: _tokens && _tokens.textSecondary !== undefined
                                           ? _tokens.textSecondary : muted

    signal closeRequested()
    signal navigate(string target)

    implicitWidth: metrics.content
    implicitHeight: grid.implicitHeight

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    function fmt(template, args) {
        return String(template).replace(/%(\d+)/g, (m, n) => {
            const i = parseInt(n) - 1;
            return i >= 0 && i < args.length ? String(args[i]) : m;
        });
    }

    // ---------- Rodapé ----------
    readonly property bool anyArmed: logoutTile.armed || rebootTile.armed || shutdownTile.armed
    readonly property string footerStatus: anyArmed ? strings.t("power.confirmHint")
                                         : uptimeText !== "" ? fmt(strings.t("power.uptime"), [uptimeText])
                                         : ""
    readonly property bool footerAlert: anyArmed
    readonly property string footerHints: strings.t("hint.confirmTwice")

    // ---------- Teclado (o host chama) ----------
    function handleKey(event) { return grid.handleKey(event); }
    function handleEscape() { return grid.handleEscape(); }
    function focusFirst() { return grid.focusFirst(); }

    // ---------- Disponibilidade de suspender/hibernar ----------
    // Mesma regra do menu do sistema: suspender sai quando o atalho
    // "suspend-off" está ligado ou quando o sono está desativado na máquina;
    // hibernar exige swap suficiente e o hook de retomada configurado.
    property bool suspendAvailable: true
    property bool hibernateAvailable: false

    Process {
        id: availProc
        command: ["sh", "-c",
            "if omarchy-sleep-disabled; then echo '0 0'; exit 0; fi; "
            + "s=1; omarchy-toggle-enabled suspend-off && s=0; "
            + "h=0; omarchy-hibernation-available && h=1; "
            + "echo \"$s $h\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length === 2) {
                    root.suspendAvailable = parts[0] === "1";
                    root.hibernateAvailable = parts[1] === "1";
                }
            }
        }
    }

    // ---------- Tempo ligado (rodapé em repouso) ----------
    property string uptimeText: ""

    function formatUptime(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        const n = v => Commons.I18n.formatNumber(v);
        if (d > 0) return n(d) + " d " + n(h) + " h";
        if (h > 0) return n(h) + " h " + n(m) + " min";
        return n(m) + " min";
    }

    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(String(text).trim().split(/\s+/)[0]);
                root.uptimeText = isNaN(v) ? "" : root.formatUptime(v);
            }
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: if (!uptimeProc.running) uptimeProc.running = true
    }

    function refresh() {
        if (!availProc.running) availProc.running = true;
        if (!uptimeProc.running) uptimeProc.running = true;
    }

    onActiveChanged: {
        if (active) refresh();
        else disarm();
    }
    Component.onCompleted: if (active) refresh()

    function disarm() {
        logoutTile.disarm();
        rebootTile.disarm();
        shutdownTile.disarm();
    }

    // Fecha a ilha e só depois executa, para a ação não aparecer por trás dela.
    function runClosed(cmd) {
        root.disarm();
        root.closeRequested();
        // Espera fixa: é o tempo de a janela sumir, não uma animação.
        const wait = (root.metrics.msCloseFirst / 1000).toFixed(2);
        Quickshell.execDetached(["sh", "-c", "sleep \"$0\"; exec \"$@\"", wait].concat(cmd));
    }

    // ---------- Grade ----------
    PanelGrid {
        id: grid
        width: root.metrics.content
        metrics: root.metrics
        strings: strings
        keyboardMode: root.keyboardMode
        fg: root.fg
        bg: root.bg
        accent: root.accent
        danger: root.danger
        muted: root.textSecondary

        // Linha Q W E: preserva a sessão.
        GridRow {
            columns: 3
            tileHeight: 88
            Tile {
                iconFace: true
                faceIconSize: 28
                cornerRadius: root.metrics.cardRadius
                icon: "lock"
                label: strings.t("power.lock")
                closesIsland: true
                onActivated: root.runClosed(["omarchy", "system", "lock"])
            }
            Tile {
                iconFace: true
                faceIconSize: 28
                cornerRadius: root.metrics.cardRadius
                icon: "bedtime"
                label: strings.t("power.suspend")
                available: root.suspendAvailable
                unavailableText: strings.t("power.suspendOff")
                closesIsland: true
                onActivated: root.runClosed(["systemctl", "suspend"])
            }
            Tile {
                iconFace: true
                faceIconSize: 28
                cornerRadius: root.metrics.cardRadius
                icon: "ac_unit"
                label: strings.t("power.hibernate")
                available: root.hibernateAvailable
                unavailableText: strings.t("power.hibernateOff")
                closesIsland: true
                onActivated: root.runClosed(["systemctl", "hibernate"])
            }
        }

        // Linha A S D: encerra a sessão, pede dois toques.
        GridRow {
            columns: 3
            tileHeight: 88
            Tile {
                id: logoutTile
                iconFace: true
                faceIconSize: 28
                cornerRadius: root.metrics.cardRadius
                icon: "logout"
                label: strings.t("power.logout")
                kind: "confirm"
                closesIsland: true
                onActivated: root.runClosed(["omarchy", "system", "logout"])
            }
            Tile {
                id: rebootTile
                iconFace: true
                faceIconSize: 28
                cornerRadius: root.metrics.cardRadius
                icon: "restart_alt"
                label: strings.t("power.reboot")
                kind: "confirm"
                closesIsland: true
                onActivated: root.runClosed(["omarchy", "system", "reboot"])
            }
            Tile {
                id: shutdownTile
                iconFace: true
                faceIconSize: 28
                cornerRadius: root.metrics.cardRadius
                icon: "power_settings_new"
                label: strings.t("power.shutdown")
                kind: "confirm"
                closesIsland: true
                onActivated: root.runClosed(["omarchy", "system", "shutdown"])
            }
        }
    }
}
