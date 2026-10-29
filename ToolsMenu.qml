import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Ferramentas (spec §3.4): abre uma ferramenta do Omarchy.
//   Q Área de transferência · W Emojis · E Atalhos · R Menu do Omarchy
//   A Notificações (histórico) · S Sobre · D Atualizações (largo, c3–c4)
// O tile de atualizações sempre existe: "Verificando…", "Sistema em dia" ou
// "N pendentes", e tocar roda a atualização (fecha a ilha antes).
// Rede foi para o Controle; lembretes e fuso horário, para o Tempo.
//
// Contrato com o host: active, fg/bg/accent/danger, shell, metrics,
// keyboardMode, closeRequested(), navigate(target), footerStatus,
// footerHints, handleKey(event) → bool, handleEscape() → bool, focusFirst().
Item {
    id: root

    // Cores do tema (o host passa os mesmos tokens).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent

    // O host liga enquanto este estado está visível.
    property bool active: false
    property bool keyboardMode: false
    property Metrics metrics: Metrics {}

    // Fachada PluginShellApi do host. Não é usada aqui hoje, mas o host a
    // passa a todos os estados; pode ser null.
    property var shell: null

    // Verificar atualizações ao abrir (faz git fetch no checkout de
    // desenvolvimento). O teste desliga.
    property bool checkUpdates: true

    // Pede ao host para recolher a ilha.
    signal closeRequested()
    // Pede ao host para trocar de estado ("control", "launcher", ...).
    signal navigate(string target)

    implicitWidth: metrics.content
    implicitHeight: grid.implicitHeight

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // Troca %1, %2... numa passada só, para que um valor que contenha "%2"
    // não seja substituído de novo.
    function fmt(template, args) {
        return String(template).replace(/%(\d+)/g, (m, n) => {
            const i = parseInt(n) - 1;
            return i >= 0 && i < args.length ? String(args[i]) : m;
        });
    }

    // ---------- Rodapé ----------
    readonly property string footerStatus: updatesChecking ? strings.t("tools.updates.checking")
                                         : hasUpdates ? fmt(strings.tn("tools.footer.updates", updateLines.length),
                                                            [Commons.I18n.formatNumber(updateLines.length)])
                                         : updatesExit >= 0 ? strings.t("tools.updates.upToDate")
                                         : ""
    readonly property string footerHints: strings.t("hint.open")

    // ---------- Teclado (o host chama) ----------
    function handleKey(event) { return grid.handleKey(event); }
    function handleEscape() { return grid.handleEscape(); }
    function focusFirst() { return grid.focusFirst(); }

    // ---------- Execução ----------
    // Fecha a ilha e roda o comando um pouco depois, para que a janela
    // aberta (menu, terminal, seletor) não apareça por baixo da ilha.
    // Espera fixa: é o tempo de a janela sumir, não uma animação.
    readonly property string closeWait: (metrics.msCloseFirst / 1000).toFixed(2)

    function launch(cmd) {
        root.closeRequested();
        Quickshell.execDetached(["sh", "-c", "sleep \"$0\"; exec \"$@\"", root.closeWait].concat(cmd));
    }

    // ---------- Notificações ----------
    // Mesmo caminho do indicador (Indicators.qml showNotificationHistory):
    // IPC do shell em processo, com o comando como reserva. Fecha antes.
    function showNotificationHistory() {
        root.closeRequested();
        historyDelay.restart();
    }

    Timer {
        id: historyDelay
        interval: root.metrics.msCloseFirst
        onTriggered: {
            const result = Commons.IpcRegistry.call("notifications", "showHistory", []);
            if (!result || !result.ran)
                Quickshell.execDetached(["omarchy-shell", "-q", "notifications", "showHistory"]);
        }
    }

    // Quantas estão na tela agora: o mesmo arquivo que o indicador lê.
    readonly property string notificationsDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
    property int notificationCount: 0

    function readLive(raw) {
        let n = 0;
        try {
            const parsed = JSON.parse(String(raw || "[]"));
            if (Array.isArray(parsed)) n = parsed.length;
        } catch (e) {
            n = 0;
        }
        root.notificationCount = n;
    }

    FileView {
        id: liveFile
        path: root.notificationsDir + "/live.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readLive(text())
        onLoadFailed: root.readLive("[]")
    }

    // O arquivo é regravado inteiro; vigiar a pasta pega a troca por renomeação.
    FileView {
        path: root.notificationsDir
        watchChanges: true
        printErrors: false
        onFileChanged: liveFile.reload()
    }

    // ---------- Atualizações ----------
    property bool updatesChecking: false
    property int updatesExit: -1
    property string updatesText: ""
    readonly property var updateLines: updatesText.split("\n").map(l => l.trim()).filter(l => l.length > 0)
    readonly property bool hasUpdates: !updatesChecking && updatesExit === 0 && updateLines.length > 0

    // Deixa as linhas da verificação mais legíveis (e curtas: cabem na
    // 3ª linha do tile largo).
    function describeUpdate(line) {
        let m = line.match(/^omarchy-dev-checkout\s+(\d+)\s+new\s+commits?\s+on\s+(\S+)/);
        if (m) {
            const n = parseInt(m[1]);
            const commits = fmt(strings.tn("tools.updates.commits", n), [Commons.I18n.formatNumber(n)]);
            return fmt(strings.t("tools.updates.checkoutShort"), [commits, m[2]]);
        }
        m = line.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/);
        if (m) return m[1] + "  " + m[2] + " → " + m[3];
        return line;
    }

    Process {
        id: updatesProc
        command: ["omarchy", "update", "available"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.updatesText = text
        }
        onExited: (exitCode, exitStatus) => {
            root.updatesExit = exitCode;
            root.updatesChecking = false;
        }
    }

    function refreshUpdates() {
        if (!root.checkUpdates || updatesProc.running) return;
        root.updatesChecking = true;
        updatesProc.running = true;
    }

    onActiveChanged: if (active) refreshUpdates()
    Component.onCompleted: if (active) refreshUpdates()

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

        // Linha Q W E R: menus e seletores do Omarchy.
        GridRow {
            Tile {
                icon: "content_paste"
                label: strings.t("tools.clipboard")
                closesIsland: true
                onActivated: root.launch(["omarchy", "menu", "clipboard"])
            }
            Tile {
                icon: "mood"
                label: strings.t("tools.emoji")
                closesIsland: true
                onActivated: root.launch(["omarchy", "menu", "emoji"])
            }
            Tile {
                icon: "keyboard"
                label: strings.t("tools.keybindings")
                closesIsland: true
                onActivated: root.launch(["omarchy", "menu", "keybindings"])
            }
            Tile {
                icon: "menu"
                label: strings.t("tools.omarchyMenu")
                closesIsland: true
                // "summon" sempre abre o menu principal (rota raiz), sem alternar.
                onActivated: root.launch(["omarchy", "menu", "summon"])
            }
        }

        // Linha A S D: histórico, sobre e atualizações (D ocupa c3–c4).
        GridRow {
            Tile {
                icon: "notifications"
                label: strings.t("tools.notifications")
                sublabel: root.notificationCount > 0
                          ? root.fmt(strings.tn("tools.notifications.onScreen", root.notificationCount),
                                     [Commons.I18n.formatNumber(root.notificationCount)])
                          : strings.t("tools.notifications.history")
                closesIsland: true
                onActivated: root.showNotificationHistory()
            }
            Tile {
                icon: "info"
                label: strings.t("tools.about")
                closesIsland: true
                onActivated: root.launch(["omarchy", "launch", "about"])
            }
            Tile {
                span: 2
                icon: root.hasUpdates ? "system_update" : root.updatesChecking ? "sync" : "check_circle"
                label: strings.t("tools.updates.title")
                on: root.hasUpdates
                sublabel: root.updatesChecking ? strings.t("tools.updates.checkingShort")
                          : root.hasUpdates ? root.fmt(strings.tn("tools.updates.pendingAction", root.updateLines.length),
                                                       [Commons.I18n.formatNumber(root.updateLines.length)])
                          : strings.t("tools.updates.upToDate")
                // Sempre há uma 3ª linha, para o tile manter o mesmo layout
                // em todos os estados.
                detail: root.hasUpdates ? root.describeUpdate(root.updateLines[0])
                        : strings.t("tools.updates.runHint")
                closesIsland: true
                // Mesmo caminho que o próprio Omarchy usa para atualizar.
                onActivated: root.launch(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"])
            }
        }
    }
}
