import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import "AppSearch.js" as AppSearch

// Aplicativos do lançador (dono: Agent F). Porte do AppLibrary do Omarchy
// (shell/services/AppLibrary.qml, MIT): um plugin de barra não recebe
// shell.appLibrary (o host só injeta isso em plugins "menu"), então a Ilha
// refaz aqui, com o mesmo comportamento:
//
// - Entradas: DesktopEntries.applications, sem NoDisplay, sem as ids de
//   $OMARCHY_PATH/default/omarchy/launcher.hides e sem as que o
//   shell/services/hidden-entries.sh do Omarchy esconde (Hidden, NoDisplay,
//   OnlyShowIn / NotShowIn para esta sessão).
// - Ordem e busca: AppSearch.js (cópia do Omarchy). Consulta vazia = A–Z sem
//   distinção de maiúsculas; com texto, pela pontuação difusa.
// - Ícone: o índice de ícones de apps/dispositivos (a mesma varredura do
//   Omarchy, para ícones instalados depois do processo começar e para não
//   cair num ícone de ação com o mesmo nome), depois o tema, depois
//   application-x-executable.
// - Abrir: entrada de terminal vai pelo omarchy-launch-tui; o resto por
//   `uwsm-app -- gtk-launch <id>.desktop` (fica fora do wayland-wm@.service e
//   aceita ids com espaço). Sem janela nova em 2 s, o OSD fixo do host diz
//   "Abrindo…" até a janela aparecer (ou 15 s) — só quando `strings` tem as
//   chaves launcher.launching / launcher.launchingApp (pedido ao lead).
//
// API (FINAL):
//   in       omarchyPath, strings (opcional)
//   estado   entries: as entradas visíveis, A–Z
//   results(query) -> [{id, name, desc, iconName}]   (iconName: ícone do app,
//            não é Material Symbol; desc: GenericName, senão Comment)
//   launch(id, name) -> bool                          (true se mandou abrir)
//   iconSource(iconName) -> url                       (para o Image da linha)
//   refresh()                                         (a tela chama ao abrir)
//
// Varreduras (nada de sondagem): a de ocultos roda na partida e quando a
// lista de apps muda; a de ícones roda uma vez pouco depois da partida,
// quando a lista muda (agrupada em 750 ms) e ao abrir o lançador se a última
// tiver mais de 5 min. Ambas em shell sem login (o perfil do usuário pode
// tocar em ~/.local/share e disparar a próxima varredura, como o Omarchy avisa).
//
// ILHA_DEV=1 (harness): launch() só registra no log, não abre nada.
QtObject {
    id: root

    // ---- Entradas ----
    property string omarchyPath: ""
    // Catálogo da Ilha (island.strings), só para o texto do OSD de abertura.
    property var strings: null

    // ---- Estado ----
    // Visíveis, A–Z (sem distinção de maiúsculas).
    property var entries: root.results("")

    readonly property string basePath: root.omarchyPath !== "" ? root.omarchyPath : String(Quickshell.env("OMARCHY_PATH") || "")
    readonly property bool dev: Quickshell.env("ILHA_DEV") === "1"

    // id -> true
    property var configuredHidden: ({})
    property var desktopHidden: ({})
    // nome do ícone -> caminho no disco (apps/ e devices/ dos temas, pixmaps).
    property var iconIndex: ({})

    readonly property string fallbackUrl: Quickshell.iconPath("application-x-executable", true)

    // ---- Busca ----

    function isHidden(entry) {
        const id = String((entry && entry.id) || "");
        return root.configuredHidden[id] === true || root.desktopHidden[id] === true;
    }

    // GenericName, a menos que repita o nome; senão Comment.
    function descFor(entry) {
        const name = AppSearch.entryName(entry).toLowerCase();
        const generic = String((entry && entry.genericName) || "").trim();
        if (generic !== "" && generic.toLowerCase() !== name)
            return generic;
        return String((entry && entry.comment) || "").trim();
    }

    function results(query) {
        // Lidos aqui para a ligação de quem chama depender deles mesmo com a lista vazia.
        const hiddenA = root.configuredHidden;
        const hiddenB = root.desktopHidden;
        const values = DesktopEntries.applications.values || [];
        const rows = AppSearch.sortedEntries(values, String(query || ""), entry => {
            const id = String((entry && entry.id) || "");
            return hiddenA[id] === true || hiddenB[id] === true;
        });
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const e = rows[i].entry;
            out.push({
                id: String(e.id || ""),
                name: AppSearch.entryName(e),
                desc: root.descFor(e),
                iconName: String(e.icon || "")
            });
        }
        return out;
    }

    // URL do ícone de um app (mesma ordem do AppLibrary.iconSource).
    function iconSource(name) {
        const v = String(name || "");
        const index = root.iconIndex;
        if (v.length === 0)
            return root.fallbackUrl;
        if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0)
            return v;
        if (v.charAt(0) === "/")
            return Commons.Util.fileUrl(v);
        const found = index[v];
        if (found)
            return Commons.Util.fileUrl(found);
        const themed = Quickshell.iconPath(v, true);
        if (themed.length > 0)
            return themed;
        return root.fallbackUrl;
    }

    // A tela chama ao abrir: ícones instalados depois da última varredura aparecem.
    function refresh() {
        if (Date.now() - priv.iconsAt > root.iconStaleMs)
            root.scanIcons();
    }

    // ---- Abrir ----

    // O comando de uma entrada de terminal, sem os códigos de campo (%f, %U…);
    // vazio para quem não roda no terminal.
    function terminalCommand(entry) {
        if (!entry || !entry.runInTerminal)
            return [];
        return (entry.command || []).filter(word => !/^%[a-zA-Z]$/.test(String(word)));
    }

    function launch(id, name) {
        const desktopId = String(id || "");
        if (desktopId === "")
            return false;
        const entry = DesktopEntries.byId(desktopId);
        if (!entry)
            return false;
        const label = String(name || entry.name || "");
        const command = root.terminalCommand(entry);
        if (root.dev) {
            console.log("ilha(dev): abriria " + desktopId + (command.length > 0 ? " (terminal: " + command.join(" ") + ")" : ""));
            return true;
        }
        root.beginFeedback(label);
        const U = Commons.Util;
        if (command.length > 0) {
            // O lançador de TUI do Omarchy dá à janela o nome do comando (org.omarchy.nvim).
            U.execDetached("omarchy-launch-tui " + command.map(word => U.shellQuote(word)).join(" "));
        } else {
            // O sufixo .desktop fica: ids como org.telegram.desktop precisam dele.
            U.execDetached("uwsm-app -- gtk-launch " + U.shellQuote(desktopId + ".desktop"));
        }
        return true;
    }

    // ---- Retorno de abertura (o OSD fixo do host, como no AppLibrary) ----

    readonly property int feedbackDelayMs: 2000
    readonly property int feedbackTimeoutMs: 15000

    function toplevelCount() {
        try {
            return ToplevelManager.toplevels.values.length;
        } catch (e) {
            return 0;
        }
    }

    function feedbackMessage(name) {
        const s = root.strings;
        if (!s || typeof s.t !== "function")
            return "";
        if (name !== "") {
            const withName = String(s.t("launcher.launching", ""));
            if (withName.indexOf("%1") !== -1)
                return withName.arg(name);
        }
        return String(s.t("launcher.launchingApp", ""));
    }

    function beginFeedback(name) {
        priv.serial++;
        priv.toplevels = root.toplevelCount();
        priv.active = ToplevelManager.activeToplevel;
        priv.message = root.feedbackMessage(name);
        if (priv.message === "")
            return;
        delayTimer.restart();
        timeoutTimer.restart();
    }

    function closeFeedback(serial) {
        if (serial !== priv.serial)
            return;
        delayTimer.stop();
        timeoutTimer.stop();
        if (priv.osdOpen) {
            Quickshell.execDetached(["omarchy-shell", "osd", "close"]);
            priv.osdOpen = false;
        }
    }

    function maybeFinishFeedback() {
        if (!delayTimer.running && !timeoutTimer.running && !priv.osdOpen)
            return;
        if (root.toplevelCount() <= priv.toplevels && ToplevelManager.activeToplevel === priv.active)
            return;
        root.closeFeedback(priv.serial);
    }

    property Timer feedbackDelay: Timer {
        id: delayTimer
        interval: root.feedbackDelayMs
        onTriggered: {
            if (root.toplevelCount() > priv.toplevels || ToplevelManager.activeToplevel !== priv.active)
                return;
            priv.osdOpen = true;
            // Ícone do foguete (Nerd Font), o mesmo do AppLibrary; duração 0 = fixo no host.
            Quickshell.execDetached(["omarchy-shell", "osd", "show", JSON.stringify({ icon: "󱓞", message: priv.message, duration: 0 })]);
        }
    }

    property Timer feedbackTimeout: Timer {
        id: timeoutTimer
        interval: root.feedbackTimeoutMs
        onTriggered: root.closeFeedback(priv.serial)
    }

    property Connections toplevelsWatch: Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            root.maybeFinishFeedback();
        }
    }

    property Connections activeWatch: Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            root.maybeFinishFeedback();
        }
    }

    // ---- Ocultos ----

    function normalizeId(id) {
        let v = String(id || "").trim();
        if (v.slice(-8) === ".desktop")
            v = v.slice(0, -8);
        return v;
    }

    function idSet(rawText) {
        const next = ({});
        const lines = String(rawText || "").split(/\n/);
        for (let i = 0; i < lines.length; i++) {
            const id = root.normalizeId(lines[i]);
            if (id.length > 0)
                next[id] = true;
        }
        return next;
    }

    function scanHidden() {
        if (root.basePath === "")
            return;
        if (hiddenProc.running) {
            priv.hiddenAgain = true;
            return;
        }
        hiddenProc.running = true;
    }

    readonly property string desktopNames: [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(v => String(v || "").length > 0).join(":")

    // `bash <script>`: sem login, como o Omarchy exige.
    property Process hiddenScan: Process {
        id: hiddenProc
        command: ["bash", root.basePath + "/shell/services/hidden-entries.sh", root.desktopNames]
        stdout: StdioCollector {
            id: hiddenOut
            onStreamFinished: root.desktopHidden = root.idSet(hiddenOut.text)
        }
        onExited: {
            if (priv.hiddenAgain) {
                priv.hiddenAgain = false;
                Qt.callLater(root.scanHidden);
            }
        }
    }

    property FileView hidesFile: FileView {
        id: hides
        path: root.basePath !== "" ? root.basePath + "/default/omarchy/launcher.hides" : ""
        watchChanges: true
        printErrors: false
        onLoaded: root.configuredHidden = root.idSet(hides.text())
        onFileChanged: hides.reload()
        onLoadFailed: root.configuredHidden = ({})
    }

    // ---- Índice de ícones (porte de AppLibrary.iconIndexScanCommand) ----

    readonly property int iconStaleMs: 5 * 60 * 1000

    function iconScanCommand() {
        // Ícones de apps/dispositivos nos diretórios XDG e em /usr/share/pixmaps,
        // SVG antes de PNG (o primeiro achado de cada nome fica).
        return [
            'dirs="$HOME/.icons $HOME/.local/share/icons";',
            'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
            '{',
            '  for base in $dirs; do',
            '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
            '  done;',
            '  find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) 2>/dev/null;',
            '} | awk \'/\\.svg$/ { print; next } { png[++n] = $0 } END { for (i = 1; i <= n; i++) print png[i] }\''
        ].join(" ");
    }

    function indexLine(path) {
        const value = String(path || "").trim();
        if (value.length === 0)
            return;
        const slash = value.lastIndexOf("/");
        const file = slash >= 0 ? value.slice(slash + 1) : value;
        const dot = file.lastIndexOf(".");
        const name = dot > 0 ? file.slice(0, dot) : file;
        if (name.length > 0 && priv.pendingIcons[name] === undefined)
            priv.pendingIcons[name] = value;
    }

    function scanIcons() {
        if (!iconProc.running)
            iconProc.running = true;
    }

    property Process iconScan: Process {
        id: iconProc
        command: ["bash", "-c", root.iconScanCommand()]
        stdout: SplitParser {
            onRead: line => root.indexLine(line)
        }
        onStarted: priv.pendingIcons = ({})
        onExited: {
            // Trocar o objeto reavalia cada iconSource(): ícones novos aparecem sem refazer a lista.
            root.iconIndex = priv.pendingIcons;
            priv.pendingIcons = ({});
            priv.iconsAt = Date.now();
        }
    }

    // Uma instalação toca em muitas entradas: uma varredura só.
    property Timer iconDebounce: Timer {
        id: debounceTimer
        interval: 750
        onTriggered: root.scanIcons()
    }

    // A primeira varredura de ícones espera a partida do shell assentar.
    property Timer iconStartup: Timer {
        interval: 4000
        running: true
        onTriggered: root.scanIcons()
    }

    property Connections appsWatch: Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root.scanHidden();
            debounceTimer.restart();
        }
    }

    onBasePathChanged: root.scanHidden()
    Component.onCompleted: root.scanHidden()

    property QtObject internals: QtObject {
        id: priv
        property bool hiddenAgain: false
        property var pendingIcons: ({})
        property real iconsAt: 0
        property int serial: 0
        property int toplevels: 0
        property var active: null
        property string message: ""
        property bool osdOpen: false
    }
}
