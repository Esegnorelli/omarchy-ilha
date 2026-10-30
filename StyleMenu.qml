import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Estilo (spec §3.4): como o sistema parece.
//
//   TEMA            faixa: busca, imagem do tema, paleta, nome. ←→ escolhem, ↵ aplica
//   FUNDO           busca e carrossel do tema no centro. A escolhida sobe; as
//                   vizinhas ficam mais baixas e mais quietas. O nome fica na
//                   miniatura. O fundo em uso não escurece. ←→ escolhem, ↵ e o
//                   clique na levantada aplicam. O clique na vizinha só escolhe.
//                   Q Próximo fundo · W Escolher fundo… · E Cores do fundo · R Todos os temas…
//   TODOS OS TEMAS  a mesma faixa de temas, sem os outros controles.
//                   O fundo continua o carrossel do tema no centro. Esc volta.
//   JANELAS E FONTE Cantos (S D F) · Transparência (X C V) · Fonte ‹ chips › ([ ])
//
// Contrato de estado: active, fg/bg/accent/danger, metrics, keyboardMode,
// footerStatus, footerHints, handleKey(event) → bool, handleEscape() → bool,
// focusFirst(), closeRequested(), navigate(target).
Item {
    id: root

    // Cores do tema (o host passa as mesmas).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted

    // O host liga enquanto este estado está visível; as leituras são refeitas ao ligar.
    property bool active: false
    property var shell: null
    property Metrics metrics: Metrics {}
    property bool keyboardMode: false

    readonly property bool rtl: Commons.I18n.rightToLeft

    signal closeRequested()
    signal navigate(string target)
    // A ilha pinta a paleta na hora. O comando do sistema vem depois.
    signal themePreview(string name)
    signal themeSettled()
    signal lookCorners(string mode)
    signal lookGlass(string mode)
    signal lookFont(string name)

    implicitWidth: metrics.content
    implicitHeight: grid.implicitHeight
    // Largura da tela, para os carrosséis irem de ponta a ponta. O host liga.
    property real screenSpan: metrics.content

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // ---------- Contrato ----------
    readonly property string footerStatus: [root.currentTheme, root.background].filter(s => s !== "").join(" · ")
    readonly property string footerHints: allThemesOpen ? strings.t("hint.styleAll") : strings.t("hint.style")

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (!mods && (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight)) {
            // [ ] só escolhem a fonte e levam o foco até ela; Enter aplica.
            if (!event.isAutoRepeat) {
                const box = fontRow.focusItems()[0];
                if (box) box.forceActiveFocus(Qt.TabFocusReason);
                if (event.key === Qt.Key_BracketLeft) fontRow.prev();
                else fontRow.next();
            }
            return true;
        }
        if (root.typeTheme(event)) return true;
        if (root.typeWall(event)) return true;
        return grid.handleKey(event);
    }
    // Com a faixa de temas focada, o que se digita filtra. Dígito com a
    // busca vazia continua trocando de painel.
    function typeTheme(event) {
        if (!themeStrip.activeFocus) return false;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods || event.isAutoRepeat) return false;
        if (event.key === Qt.Key_Backspace) {
            if (root.themeQuery.length === 0) return false;
            root.themeQuery = root.themeQuery.slice(0, -1);
            return true;
        }
        const text = event.text || "";
        if (text.length !== 1 || /[\u0000-\u001f]/.test(text)) return false;
        if (/[0-9]/.test(text) && root.themeQuery.length === 0) return false;
        if (root.themeQuery.length >= 32) return true;
        root.themeQuery += text;
        return true;
    }
    function typeWall(event) {
        if (!wallStrip.activeFocus) return false;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods || event.isAutoRepeat) return false;
        if (event.key === Qt.Key_Backspace) {
            if (root.wallQuery.length === 0) return false;
            root.wallQuery = root.wallQuery.slice(0, -1);
            return true;
        }
        const text = event.text || "";
        if (text.length !== 1 || /[\u0000-\u001f]/.test(text)) return false;
        if (/[0-9]/.test(text) && root.wallQuery.length === 0) return false;
        if (root.wallQuery.length >= 32) return true;
        root.wallQuery += text;
        return true;
    }
    function handleEscape() {
        if (wallStrip.activeFocus && wallQuery !== "") {
            wallQuery = ""
            return true
        }
        if (themeQuery !== "") {
            themeQuery = ""
            return true
        }
        if (allThemesOpen) {
            allThemesOpen = false
            return true
        }
        return grid.handleEscape()
    }
    function focusFirst() { themeStrip.forceActiveFocus(Qt.TabFocusReason); return true; }

    // Cartão do meio em cada carrossel. galleryUserMoved evita puxar o tema
    // de volta para o atual enquanto a pessoa ainda está folheando.
    property int galleryCursor: -1
    // Texto da busca de temas. Vazio mostra a lista inteira.
    property string themeQuery: ""
    // Busca da faixa de fundos, pelo nome do arquivo.
    property string wallQuery: ""
    onWallQueryChanged: Qt.callLater(() => {
        const listed = wallStrip.listed;
        if (!listed) return;
        if (root.wallQuery.trim() === "") {
            root.wallUserMoved = false;
            root.syncWallCursor();
            return;
        }
        if (listed.length === 0) return;
        for (let i = 0; i < listed.length; i++)
            if (listed[i].index === root.wallCursor) return;
        root.wallUserMoved = true;
        root.wallCursor = listed[0].index;
    })
    onThemeQueryChanged: Qt.callLater(() => {
        const listed = themeStrip.listed;
        if (!listed || listed.length === 0) return;
        for (let i = 0; i < listed.length; i++)
            if (listed[i].index === root.galleryCursor) return;
        root.galleryUserMoved = true;
        root.galleryCursor = listed[0].index;
    })
    property bool galleryUserMoved: false
    property int wallCursor: -1
    // Folhear os fundos não puxa o cartão de volta para o atual.
    property bool wallUserMoved: false

    // Estado da linha Fundo: nome do arquivo e, se houver, o andamento das cores.
    readonly property string paletteStatus: root.wallpaperIsVideo ? strings.t("style.wallpaperColorsVideo")
                                          : root.paletteBusy ? strings.t("style.wallpaperColorsBusy")
                                          : root.paletteFailed ? strings.t("style.wallpaperColorsFailed")
                                          : ""
    readonly property string backgroundStatus: root.paletteFailed && !root.paletteBusy ? root.paletteStatus
                                             : [root.background, root.paletteStatus].filter(s => s !== "").join(" · ")

    // ---------- Estado lido do sistema ----------
    property var themes: []          // [{ name, preview }]
    property string currentTheme: ""
    property var fonts: []
    property string currentFont: ""
    // Fonte marcada nos chips e ainda não aplicada.
    property string pendingFont: ""
    property string corners: ""      // theme | sharp | rounded
    property string transparency: "" // opaque | transparent | glassy
    property string background: ""
    property bool themesLoaded: false
    // Arquivo real do plano de fundo atual (o link de estado resolvido).
    property string wallpaperPath: ""
    readonly property bool wallpaperIsVideo: /\.(mp4|webm|mkv|mov|avi)$/i.test(wallpaperPath)

    // Tema escolhido aqui que ainda não foi gravado pelo sistema.
    property string pendingTheme: ""
    property int pendingChecks: 0

    readonly property int currentThemeIndex: {
        for (let i = 0; i < themes.length; i++)
            if (themes[i].name === currentTheme) return i;
        return -1;
    }

    // Todos os temas: os dois carrosséis ocupam a tela. O de baixo segue o tema do centro. Esc volta ao Estilo.
    property bool allThemesOpen: false

    onActiveChanged: {
        if (!active) {
            pendingFont = ""
            allThemesOpen = false
            themeQuery = ""
            wallQuery = ""
        }
        if (active) {
            refresh();
            root.galleryUserMoved = false;
            root.galleryCursor = root.currentThemeIndex;
            Qt.callLater(root.focusFirst);
        } else {
            recheck.stop();
        }
    }
    Component.onCompleted: if (active) { refresh(); Qt.callLater(root.focusFirst); }

    function refresh() {
        root.pendingTheme = "";
        themeListProc.running = true;
        fontListProc.running = true;
        refreshStatus();
    }

    function refreshStatus() {
        themeCurrentProc.running = true;
        fontCurrentProc.running = true;
        cornersProc.running = true;
        transparencyProc.running = true;
        backgroundProc.running = true;
        wallpaperProc.running = true;
    }

    // Confere o estado real pouco depois de uma ação.
    Timer {
        id: recheck
        interval: 1500
        onTriggered: if (root.active) root.refreshStatus()
    }

    function run(cmd) {
        Quickshell.execDetached(cmd);
        recheck.restart();
    }

    // Para ações que abrem outra interface: recolhe a ilha antes de executar.
    function runAfterClose(cmd) {
        root.closeRequested();
        const wait = (root.metrics.msCloseFirst / 1000).toFixed(2);
        Quickshell.execDetached(["sh", "-c", "sleep \"$0\"; exec \"$@\"", wait].concat(cmd));
    }

    // Vários toques seguidos viram um tema só no sistema. A pílula não espera.
    Timer {
        id: themeApply
        interval: 280
        onTriggered: {
            if (root.pendingTheme === "")
                return
            root.run(["omarchy", "theme", "set", root.pendingTheme])
        }
    }

    function setTheme(name) {
        if (name === root.currentTheme) return;
        root.currentTheme = name;
        root.pendingTheme = name;
        root.pendingChecks = 0;
        root.themePreview(name);
        themeApply.restart();
    }
    function setFont(name) {
        if (name === root.currentFont) return;
        root.currentFont = name;
        root.lookFont(name);
        root.run(["omarchy", "font", "set", name]);
    }
    // Evita que uma leitura antiga, ainda no ar, devolva o botão para o
    // modo anterior logo depois do clique.
    property real cornersChosenAt: 0
    function setCorners(mode) {
        if (mode === root.corners) return;
        root.corners = mode;
        root.lookCorners(mode);
        cornersChosenAt = Date.now();
        root.run(["omarchy", "hyprland", "corners", mode]);
    }
    function setTransparency(mode) {
        if (mode === root.transparency) return;
        root.transparency = mode;
        root.lookGlass(mode);
        root.run(["omarchy", "hyprland", "window", "transparency", mode]);
    }

    // Fundo escolhido num tema que ainda está sendo aplicado. Entra quando
    // o sistema confirma o tema, para o `theme set` não trocar o arquivo depois.
    property string pendingWallpaper: ""
    property var wallpapers: []
    property bool wallsLoaded: false
    property string wallTheme: ""
    property string wallQueued: ""
    property string wallPending: ""
    property string wallRunningName: ""

    function fileUrl(path) {
        if (!path) return "";
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }
    function prettyName(base) {
        const bare = String(base).replace(/\.[^.]+$/, "").replace(/^\d+-/, "").replace(/[-_]+/g, " ");
        return bare.replace(/\b\w/g, c => c.toUpperCase());
    }
    function themeAtCursor() {
        const i = root.galleryCursor >= 0 ? root.galleryCursor : root.currentThemeIndex;
        return i >= 0 && i < root.themes.length ? root.themes[i] : null;
    }
    function queueWalls() {
        // A fileira de baixo é sempre a do tema no centro, também em Todos os temas.
        const next = root.themeAtCursor() ? root.themeAtCursor().name : "";
        if (next !== root.wallQueued)
            root.wallUserMoved = false;
        root.wallQueued = next;
        wallDebounce.restart();
    }
    function startWalls() {
        if (wallListProc.running) {
            root.wallPending = root.wallQueued;
            return;
        }
        if (root.wallQueued === "") {
            root.wallpapers = [];
            root.wallsLoaded = true;
            root.wallTheme = "";
            root.wallCursor = -1;
            return;
        }
        root.wallRunningName = root.wallQueued;
        wallListProc.command = ["sh", "-c", root.wallScript, "sh", root.wallQueued];
        wallListProc.running = true;
    }
    function syncWallCursor() {
        if (root.wallpapers.length === 0) {
            root.wallCursor = -1;
            return;
        }
        if (root.wallUserMoved && root.wallCursor >= 0 && root.wallCursor < root.wallpapers.length)
            return;
        const showingCurrent = root.themeAtCursor() && root.themeAtCursor().name === root.currentTheme;
        let i = 0;
        if (showingCurrent && root.wallpaperPath !== "") {
            const at = root.wallpapers.findIndex(w => w.path === root.wallpaperPath);
            if (at >= 0) i = at;
        }
        root.wallCursor = i;
    }
    function setWallpaper(index) {
        const wall = root.wallpapers[index];
        if (!wall) return;
        root.wallCursor = index;
        const themeName = wall.theme || "";
        if (wall.path === root.wallpaperPath && (themeName === "" || themeName === root.currentTheme))
            return;
        if (themeName !== "" && themeName !== root.currentTheme) {
            root.pendingWallpaper = wall.path;
            root.setTheme(themeName);
            return;
        }
        root.pendingWallpaper = "";
        root.run(["omarchy", "theme", "bg", "set", wall.path]);
    }
    function applyPendingWallpaper() {
        const path = root.pendingWallpaper;
        root.pendingWallpaper = "";
        if (path !== "")
            root.run(["omarchy", "theme", "bg", "set", path]);
    }

    readonly property string wallScript:
        "[ -n \"$OMARCHY_PATH\" ] || for d in \"$HOME/.local/share/omarchy\" /usr/share/omarchy \"$HOME/omarchy\"; do " +
        "[ -d \"$d/themes\" ] && export OMARCHY_PATH=\"$d\" && break; done; " +
        "name=\"$1\"; [ -n \"$name\" ] || exit 0; " +
        "s=$(printf '%s' \"$name\" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'); " +
        "cur=$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null || true); " +
        "bg=$(readlink -f \"$HOME/.local/state/omarchy/current/background\" 2>/dev/null || true); " +
        "{ printf '%s\\n' \"$HOME/.config/omarchy/backgrounds/$s\"; " +
        "printf '%s\\n' \"$HOME/.config/omarchy/themes/$s/backgrounds\"; " +
        "[ \"$s\" = \"$cur\" ] && printf '%s\\n' \"$HOME/.local/state/omarchy/current/theme/backgrounds\"; " +
        "printf '%s\\n' \"$OMARCHY_PATH/themes/$s/backgrounds\"; } | " +
        "while IFS= read -r dir; do [ -d \"$dir\" ] || continue; " +
        "find -L \"$dir\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.avi' \\) -print; " +
        "done | while IFS= read -r f; do printf '%s\\t%s\\n' \"$(basename \"$f\")\" \"$(readlink -f \"$f\")\"; done | " +
        "awk -F '\\t' -v bg=\"$bg\" '{ if (!($1 in path) || (bg != \"\" && $2 == bg)) { if (!($1 in path)) seq[++n] = $1; path[$1] = $2 } } END { for (i = 1; i <= n; i++) print path[seq[i]] }'"

    Timer {
        id: wallDebounce
        interval: 80
        onTriggered: root.startWalls()
    }

    onGalleryCursorChanged: root.queueWalls()
    onAllThemesOpenChanged: root.queueWalls()
    onWallpaperPathChanged: {
        if (root.themeAtCursor() && root.themeAtCursor().name === root.currentTheme)
            root.syncWallCursor();
    }

    // ---------- Tema a partir do plano de fundo ----------
    // Relê o arquivo do plano de fundo na hora do toque e, se for imagem,
    // gera e aplica um tema com as cores dele. A ilha fica aberta: o shell
    // se recolore sozinho quando o tema novo entra.
    property bool paletteQueued: false
    property bool paletteFailed: false
    readonly property bool paletteBusy: paletteQueued || paletteProc.running

    function generateFromWallpaper() {
        if (root.paletteBusy || root.wallpaperIsVideo) return;
        root.paletteFailed = false;
        root.paletteQueued = true;
        wallpaperProc.running = true;
    }

    Timer {
        id: paletteFailTimer
        interval: 4000
        onTriggered: root.paletteFailed = false
    }

    function lines(text) {
        return String(text).split("\n").map(l => l.trim()).filter(l => l.length > 0);
    }

    // ---------- Leituras ----------
    // Lista de temas com a imagem de prévia de cada um (pasta do usuário primeiro).
    // Os nomes chegam pelo `read` do próprio script; nada daqui é interpolado nele.
    Process {
        id: themeListProc
        command: ["sh", "-c",
            "[ -n \"$OMARCHY_PATH\" ] || for d in \"$HOME/.local/share/omarchy\" /usr/share/omarchy; do " +
            "[ -d \"$d/themes\" ] && export OMARCHY_PATH=\"$d\" && break; done; " +
            "omarchy theme list | while IFS= read -r n; do " +
            "s=$(printf '%s' \"$n\" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'); p=''; toml=''; " +
            "for d in \"$HOME/.config/omarchy/themes/$s\" \"$OMARCHY_PATH/themes/$s\"; do " +
            "for f in preview.png preview.jpg; do [ -z \"$p\" ] && [ -f \"$d/$f\" ] && p=\"$d/$f\"; done; " +
            "[ -z \"$toml\" ] && [ -f \"$d/colors.toml\" ] && toml=\"$d/colors.toml\"; done; " +
            "if [ -z \"$p\" ]; then for d in \"$HOME/.config/omarchy/themes/$s\" \"$OMARCHY_PATH/themes/$s\"; do " +
            "[ -d \"$d/backgrounds\" ] || continue; " +
            "p=$(find -L \"$d/backgrounds\" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) -printf '%p\\n' 2>/dev/null | sort | head -n 1); " +
            "[ -n \"$p\" ] && break; done; fi; " +
            "dots=''; if [ -n \"$toml\" ]; then dots=$(awk '" +
            "{ n=split($0, a, \"=\"); if (n < 2) next; key=a[1]; val=a[2]; gsub(/[ \\t\"]/, \"\", key); gsub(/[ \\t\"]/, \"\", val); if (val ~ /^#[0-9A-Fa-f]{6}$/) c[key]=val } " +
            "END { n=split(\"red orange yellow green cyan blue magenta accent\", keys, \" \"); out=\"\"; for (i=1; i<=n; i++) if ((keys[i] in c) && !seen[c[keys[i]]]++) out=out (out==\"\" ? \"\" : \",\") c[keys[i]]; print out }' " +
            "\"$toml\"); fi; " +
            "printf '%s\\t%s\\t%s\\n' \"$n\" \"$p\" \"$dots\"; done"]
        stdout: StdioCollector {
            id: themeListOut
            onStreamFinished: {
                const out = [];
                for (const l of root.lines(themeListOut.text)) {
                    const parts = l.split("\t");
                    const colors = [];
                    for (const c of String(parts[2] || "").split(","))
                        if (/^#[0-9A-Fa-f]{6}$/.test(c) && colors.indexOf(c) < 0 && colors.length < 8)
                            colors.push(c);
                    out.push({ name: parts[0], preview: parts.length > 1 ? parts[1] : "", colors: colors });
                }
                root.themes = out;
                root.themesLoaded = true;
                if (!root.galleryUserMoved || root.galleryCursor < 0)
                    root.galleryCursor = root.currentThemeIndex;
                root.queueWalls();
            }
        }
    }
    Process {
        id: themeCurrentProc
        command: ["omarchy", "theme", "current"]
        stdout: StdioCollector {
            id: themeCurrentOut
            onStreamFinished: {
                const t = themeCurrentOut.text.trim();
                // Aplicar um tema leva alguns segundos: enquanto o sistema ainda
                // mostra o anterior, mantém a escolha e confere de novo.
                if (root.pendingTheme !== "" && t !== root.pendingTheme && root.pendingChecks < 10) {
                    root.pendingChecks++;
                    if (root.active) recheck.restart();
                    return;
                }
                const wanted = root.pendingTheme;
                root.pendingTheme = "";
                if (t !== "" && t !== "Unknown") root.currentTheme = t;
                if (wanted !== "") {
                    // O sistema ficou no tema anterior: devolve a paleta junto.
                    if (t !== wanted && t !== "" && t !== "Unknown") {
                        root.pendingWallpaper = "";
                        root.themePreview(t);
                    } else {
                        root.applyPendingWallpaper();
                    }
                    root.themeSettled();
                }
                if (!root.galleryUserMoved || root.galleryCursor < 0)
                    root.galleryCursor = root.currentThemeIndex;
            }
        }
    }
    Process {
        id: fontListProc
        command: ["omarchy", "font", "list"]
        stdout: StdioCollector {
            id: fontListOut
            onStreamFinished: {
                // Fontes de ícones (Material Symbols, emoji…) não servem de
                // fonte do sistema: deixariam o terminal ilegível.
                root.fonts = root.lines(fontListOut.text)
                    .filter(f => !/symbols|icons?\b|emoji|awesome|codicon/i.test(f));
            }
        }
    }
    Process {
        id: fontCurrentProc
        command: ["omarchy", "font", "current"]
        stdout: StdioCollector {
            id: fontCurrentOut
            onStreamFinished: {
                root.currentFont = fontCurrentOut.text.trim();
            }
        }
    }
    Process {
        id: cornersProc
        command: ["omarchy", "hyprland", "corners"]
        stdout: StdioCollector {
            id: cornersOut
            onStreamFinished: {
                const got = cornersOut.text.trim()
                if (got === "")
                    return
                if (root.cornersChosenAt > 0 && Date.now() - root.cornersChosenAt < 4000 && got !== root.corners)
                    return
                root.corners = got
            }
        }
    }
    Process {
        id: transparencyProc
        command: ["omarchy", "hyprland", "window", "transparency"]
        stdout: StdioCollector {
            id: transparencyOut
            onStreamFinished: root.transparency = transparencyOut.text.trim()
        }
    }
    Process {
        id: backgroundProc
        command: ["omarchy", "theme", "bg", "current"]
        stdout: StdioCollector {
            id: backgroundOut
            onStreamFinished: root.background = backgroundOut.text.trim()
        }
    }

    Process {
        id: wallpaperProc
        command: ["sh", "-c", "readlink -f \"$HOME/.local/state/omarchy/current/background\""]
        stdout: StdioCollector {
            id: wallpaperOut
            onStreamFinished: {
                root.wallpaperPath = wallpaperOut.text.trim();
                if (!root.paletteQueued) return;
                if (root.wallpaperPath === "" || root.wallpaperIsVideo) {
                    root.paletteQueued = false;
                    return;
                }
                paletteProc.command = ["aether", "--generate", root.wallpaperPath];
                paletteProc.running = true;
                root.paletteQueued = false;
            }
        }
    }
    Process {
        id: wallListProc
        stdout: StdioCollector {
            id: wallListOut
            onStreamFinished: {
                const name = root.wallRunningName;
                if (root.wallPending !== "" && root.wallPending !== name) {
                    const next = root.wallPending;
                    root.wallPending = "";
                    root.wallQueued = next;
                    root.startWalls();
                    return;
                }
                root.wallPending = "";
                const video = /\.(mp4|m4v|mov|webm|mkv|avi)$/i;
                const out = [];
                for (const line of root.lines(wallListOut.text)) {
                    if (!line) continue;
                    const base = line.split("/").pop();
                    out.push({
                        name: root.prettyName(base),
                        path: line,
                        preview: video.test(base) ? "" : line,
                        video: video.test(base),
                        theme: name
                    });
                }
                root.wallpapers = out;
                root.wallsLoaded = true;
                root.wallTheme = name;
                root.syncWallCursor();
            }
        }
    }
    Process {
        id: paletteProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.paletteFailed = true;
                paletteFailTimer.restart();
            }
            // O tema novo entra na lista e vira o atual.
            root.refresh();
            recheck.restart();
        }
    }

    // ---------- Componentes internos ----------
    // Legenda de 16 px (mesmo desenho da legenda do GridRow).
    component Caption: Item {
        id: cap
        property string text: ""
        property string status: ""
        property bool statusStrong: false
        width: root.metrics.content
        height: root.metrics.caption

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width / 2)
            text: cap.text
            textFormat: Text.PlainText
            font.pixelSize: root.metrics.captionText
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            elide: Text.ElideRight
            color: root.muted
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width / 2)
            horizontalAlignment: Text.AlignRight
            text: cap.status
            textFormat: Text.PlainText
            font.pixelSize: root.metrics.captionText
            font.weight: cap.statusStrong ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            color: cap.statusStrong ? root.accent : root.muted
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
        }
    }

    // Carrossel horizontal. O cartão do meio fica no centro; os vizinhos
    // aparecem nas laterais, menores. ←→ e a roda andam. O clique e o ↵ aplicam.
    component Filmstrip: Item {
        id: film

        property var entries: []
        property int cursor: -1
        property string marked: ""
        property bool loaded: false
        property string emptyText: ""
        property string loadingText: ""
        signal cursorMoved(int index)
        signal chosen(int index)

        readonly property int cardW: 260
        readonly property int cardH: 118
        readonly property int thumbH: 96
        readonly property int pitch: cardW + 12
        readonly property real inset: Math.max(0, (width - cardW) / 2)
        property real span: root.allThemesOpen ? root.screenSpan : root.metrics.content

        implicitWidth: span
        implicitHeight: cardH
        width: implicitWidth
        height: implicitHeight
        onWidthChanged: if (_ready) Qt.callLater(() => sync(false))
        activeFocusOnTab: true
        Accessible.role: Accessible.List

        function move(d) {
            const n = film.entries.length;
            if (n === 0) return false;
            const from = film.cursor < 0 ? 0 : film.cursor;
            const to = from + d;
            if (to < 0 || to >= n) return false;
            film.cursorMoved(to);
            return true;
        }
        function handleArrow(key) {
            if (key === Qt.Key_Left) {
                film.move(root.rtl ? 1 : -1);
                return true;
            }
            if (key === Qt.Key_Right) {
                film.move(root.rtl ? -1 : 1);
                return true;
            }
            return false;
        }
        function activate() {
            if (film.cursor < 0 || film.cursor >= film.entries.length) return false;
            film.chosen(film.cursor);
            return true;
        }
        function sync(animate) {
            if (view.count === 0 || film.cursor < 0) return;
            const i = Math.min(film.cursor, view.count - 1);
            // O respiro das pontas deixa o primeiro e o último cartão
            // chegarem no meio da tela.
            if (view.headerItem)
                view.headerItem.width = film.inset;
            if (view.footerItem)
                view.footerItem.width = film.inset;
            view.highlightMoveDuration = animate ? Commons.Style.duration(220) : 0;
            view.currentIndex = i;
            Qt.callLater(() => {
                if (view.count === 0) return;
                if (view.headerItem)
                    view.headerItem.width = film.inset;
                if (view.footerItem)
                    view.footerItem.width = film.inset;
                view.positionViewAtIndex(Math.min(i, view.count - 1), ListView.Center);
            });
        }

        property bool _ready: false
        onCursorChanged: film.sync(film._ready)
        onEntriesChanged: {
            film._ready = false;
            Qt.callLater(() => {
                film.sync(false);
                film._ready = true;
            });
        }

        ListView {
            id: view
            anchors.fill: parent
            orientation: ListView.Horizontal
            layoutDirection: root.rtl ? Qt.RightToLeft : Qt.LeftToRight
            spacing: 12
            clip: true
            model: film.entries
            reuseItems: true
            cacheBuffer: Math.max(1200, film.span)
            boundsBehavior: Flickable.StopAtBounds
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: film.inset
            preferredHighlightEnd: film.inset + film.cardW
            highlightMoveDuration: Commons.Style.duration(220)
            keyNavigationEnabled: false
            header: Item { width: film.inset; height: 1 }
            footer: Item { width: film.inset; height: 1 }

            property bool userDrag: false
            onDragStarted: view.userDrag = true
            onFlickStarted: view.userDrag = true
            onMovementEnded: {
                if (!view.userDrag) return;
                view.userDrag = false;
                if (view.currentIndex >= 0 && view.currentIndex !== film.cursor)
                    film.cursorMoved(view.currentIndex);
            }

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                width: film.cardW
                height: film.cardH
                readonly property bool centered: index === film.cursor
                readonly property bool marked: modelData.path
                    ? modelData.path === film.marked
                    : modelData.name === film.marked
                readonly property bool keyboard: centered && film.activeFocus && root.keyboardMode

                scale: centered ? 1 : 0.96
                opacity: centered ? 1 : 0.62
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }

                Item {
                    id: thumb
                    width: parent.width
                    height: film.thumbH

                    ContinuousRect {
                        anchors.fill: parent
                        radius: root.metrics.rowRadius
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: shot.status !== Image.Ready
                        name: card.modelData.video ? "movie" : "image"
                        size: 22
                        color: root.muted
                    }
                    Item {
                        id: shotSource
                        anchors.fill: parent
                        visible: false
                        layer.enabled: shot.status === Image.Ready
                        Image {
                            id: shot
                            anchors.fill: parent
                            source: card.modelData.preview ? root.fileUrl(card.modelData.preview) : ""
                            sourceSize.width: 520
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                    }
                    ContinuousRect {
                        id: shotMask
                        anchors.fill: parent
                        radius: root.metrics.rowRadius
                        visible: false
                        layer.enabled: true
                        color: root.fg
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: shot.status === Image.Ready
                        source: shotSource
                        maskEnabled: true
                        maskSource: shotMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                        opacity: shot.status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msFadeIn); easing.type: Easing.OutCubic } }
                    }
                    ContinuousRect {
                        anchors.fill: parent
                        radius: root.metrics.rowRadius
                        color: "transparent"
                        borderWidth: 2
                        borderColor: root.accent
                        opacity: card.centered || card.marked ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                    }
                    ContinuousRect {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 18
                        height: 18
                        radius: root.metrics.fit(height / 2)
                        color: root.accent
                        opacity: card.marked ? 1 : 0
                        scale: card.marked ? 1 : root.metrics.pressScale
                        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                        Icon {
                            anchors.centerIn: parent
                            name: "check"
                            size: 14
                            weight: 600
                            color: root.bg
                        }
                    }
                    ContinuousRect {
                        anchors.fill: parent
                        anchors.margins: -(root.metrics.ring + 1)
                        radius: root.metrics.corners === "sharp" ? 0 : root.metrics.rowRadius + root.metrics.ring + 1
                        color: "transparent"
                        borderWidth: root.metrics.ring
                        borderColor: root.accent
                        opacity: card.keyboard ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msPress); easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    anchors.top: thumb.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 18
                    verticalAlignment: Text.AlignBottom
                    horizontalAlignment: Text.AlignHCenter
                    text: card.modelData.name
                    textFormat: Text.PlainText
                    font.pixelSize: root.metrics.tileSublabel
                    font.weight: card.marked ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    color: card.marked || card.centered ? root.accent : root.muted
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        film.cursorMoved(card.index);
                        film.chosen(card.index);
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: film.entries.length === 0
            text: film.loaded ? film.emptyText : film.loadingText
            textFormat: Text.PlainText
            font.pixelSize: 13
            color: root.muted
        }

        Repeater {
            model: [
                { dir: -1, icon: root.rtl ? "chevron_right" : "chevron_left", side: "left" },
                { dir: 1, icon: root.rtl ? "chevron_left" : "chevron_right", side: "right" }
            ]
            Item {
                required property var modelData
                width: 28
                height: 28
                y: (parent.height - height) / 2 - 9
                x: modelData.side === "left" ? 12 : parent.width - width - 12
                opacity: (filmHover.hovered || film.activeFocus) && film.entries.length > 1 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic } }
                ContinuousRect {
                    anchors.fill: parent
                    radius: root.metrics.fit(height / 2)
                    color: root.metrics.plate(root.bg, 0.78)
                }
                Icon {
                    anchors.centerIn: parent
                    name: modelData.icon
                    size: 18
                    color: root.fg
                }
                TapHandler { onTapped: film.move(modelData.dir) }
            }
        }

        HoverHandler { id: filmHover }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const dy = event.angleDelta.y + event.angleDelta.x;
                if (dy === 0) return;
                film.move(dy > 0 ? -1 : 1);
            }
        }
    }

    // Fundos do tema no centro. A miniatura escolhida sobe; as vizinhas
    // descem e esmaecem. O nome fica na foto. Sem aro. A pílula não estica.
    component WallPicker: Item {
        id: picker

        property var entries: []
        property int cursor: -1
        property string marked: ""
        property bool loaded: false
        property string emptyText: ""
        property string loadingText: ""
        signal cursorMoved(int index)
        signal chosen(int index)

        readonly property int thumbW: 100
        readonly property int thumbH: 56
        readonly property int gap: 8
        readonly property int lift: 10
        readonly property int thumbRadius: root.metrics.fit(10)
        readonly property var listed: {
            const q = root.wallQuery.trim().toLowerCase();
            const src = picker.entries || [];
            const out = [];
            for (let i = 0; i < src.length; i++) {
                const path = String(src[i] && src[i].path || "");
                const base = path.split("/").pop().toLowerCase();
                const pretty = String(src[i] && src[i].name || "").toLowerCase();
                if (q === "" || base.indexOf(q) >= 0 || pretty.indexOf(q) >= 0)
                    out.push({ index: i, entry: src[i] });
            }
            return out;
        }
        readonly property int listedPos: {
            for (let i = 0; i < picker.listed.length; i++)
                if (picker.listed[i].index === picker.cursor) return i;
            return -1;
        }
        readonly property int focusPos: picker.listedPos < 0 ? 0 : picker.listedPos
        property bool settle: false

        function move(d) {
            if (picker.listed.length === 0) return false;
            const pos = picker.listedPos < 0 ? 0 : picker.listedPos;
            const to = pos + d;
            if (to < 0 || to >= picker.listed.length) return false;
            picker.cursorMoved(picker.listed[to].index);
            return true;
        }
        function handleArrow(key) {
            if (key === Qt.Key_Left) return picker.move(root.rtl ? 1 : -1);
            if (key === Qt.Key_Right) return picker.move(root.rtl ? -1 : 1);
            return false;
        }
        function activate() {
            const pos = picker.listedPos;
            if (pos < 0) return false;
            picker.chosen(picker.listed[pos].index);
            return true;
        }

        Component.onCompleted: Qt.callLater(() => { picker.settle = true; })

        implicitWidth: root.metrics.content
        implicitHeight: 32 + 8 + 1 + 8 + thumbH + lift + 8
        width: implicitWidth
        height: implicitHeight
        activeFocusOnTab: true
        Accessible.role: Accessible.List
        Accessible.name: strings.t("style.section.background")

        ContinuousRect {
            id: searchBox
            y: 0
            width: parent.width - 72
            height: 32
            radius: root.metrics.fit(height / 2)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                name: "search"
                size: 16
                color: root.muted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 32
                width: parent.width - 40
                text: root.wallQuery !== "" ? root.wallQuery : strings.t("style.wallSearch")
                textFormat: Text.PlainText
                font.pixelSize: root.metrics.captionText
                elide: Text.ElideRight
                color: root.wallQuery !== "" ? root.fg : root.muted
            }
            TapHandler { onTapped: picker.forceActiveFocus(Qt.MouseFocusReason) }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: searchBox.verticalCenter
            text: !picker.loaded ? ""
                  : root.pendingWallpaper !== "" ? strings.t("style.applying")
                  : picker.listed.length === 0 ? "0/0"
                  : ((picker.listedPos < 0 ? 1 : picker.listedPos + 1) + "/" + picker.listed.length)
            textFormat: Text.PlainText
            font.pixelSize: root.metrics.captionText
            color: root.muted
        }
        Rectangle {
            y: searchBox.height + 8
            width: parent.width
            height: 1
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)
        }

        Item {
            id: row
            y: 32 + 8 + 1 + 8
            width: parent.width
            height: picker.thumbH + picker.lift
            clip: true

            readonly property real centerX: width / 2
            readonly property real step: picker.thumbW + picker.gap

            Repeater {
                model: picker.listed
                Item {
                    id: thumb
                    required property int index
                    required property var modelData
                    readonly property int entryIndex: modelData.index
                    readonly property var entry: modelData.entry
                    readonly property int distance: index - picker.focusPos
                    readonly property int absDistance: Math.abs(distance)
                    readonly property bool isSelected: distance === 0
                    readonly property bool isActive: picker.marked !== "" && thumb.entry && thumb.entry.path === picker.marked
                    readonly property bool near: thumb.absDistance <= 2 || thumb.isActive

                    width: picker.thumbW
                    height: picker.thumbH
                    x: row.centerX + distance * row.step * (root.rtl ? -1 : 1) - width / 2
                    y: isSelected ? 0 : picker.lift
                    z: 100 - absDistance
                    opacity: {
                        if (isActive || absDistance === 0) return 1;
                        if (absDistance === 1) return 0.75;
                        if (absDistance === 2) return 0.4;
                        return 0;
                    }
                    visible: opacity > 0.01
                    Behavior on x { enabled: picker.settle; NumberAnimation { duration: Commons.Style.duration(260); easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: picker.settle; NumberAnimation { duration: Commons.Style.duration(260); easing.type: Easing.OutCubic } }
                    Behavior on opacity { enabled: picker.settle; NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }

                    Item {
                        id: face
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)
                        }
                        Image {
                            id: shot
                            anchors.fill: parent
                            source: thumb.near && thumb.entry && thumb.entry.preview ? root.fileUrl(thumb.entry.preview) : ""
                            sourceSize.width: 200
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                        Icon {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -8
                            visible: shot.status !== Image.Ready
                            name: thumb.entry && thumb.entry.video ? "movie" : "image"
                            size: 18
                            color: root.muted
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 28
                            visible: !thumb.isActive
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, thumb.isSelected ? 0.72 : 0.55) }
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            anchors.bottomMargin: 4
                            text: thumb.entry ? String(thumb.entry.name || "") : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: "white"
                            style: thumb.isActive ? Text.Outline : Text.Normal
                            styleColor: Qt.rgba(0, 0, 0, 0.55)
                            font.pixelSize: thumb.isSelected ? 12 : 11
                            font.weight: thumb.isSelected ? Font.DemiBold : Font.Medium
                        }
                    }
                    ContinuousRect {
                        id: faceMask
                        anchors.fill: parent
                        radius: picker.thumbRadius
                        visible: false
                        layer.enabled: true
                        color: root.fg
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: face
                        maskEnabled: true
                        maskSource: faceMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            picker.forceActiveFocus(Qt.MouseFocusReason);
                            if (thumb.isSelected) picker.chosen(thumb.entryIndex);
                            else picker.cursorMoved(thumb.entryIndex);
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: picker.listed.length === 0
                text: picker.loaded ? picker.emptyText : picker.loadingText
                textFormat: Text.PlainText
                font.pixelSize: root.metrics.captionText
                color: root.muted
            }
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const dy = event.angleDelta.y + event.angleDelta.x;
                if (dy === 0) return;
                picker.move(dy > 0 ? -1 : 1);
            }
        }
    }

    // Faixa de temas: busca, a imagem do tema, a paleta e o nome. Enter aplica.
    component ThemePicker: Item {
        id: themes

        property var entries: []
        property int cursor: -1
        property string marked: ""
        property bool loaded: false
        property string emptyText: ""
        property string loadingText: ""
        signal cursorMoved(int index)
        signal chosen(int index)

        readonly property int cardW: 100
        readonly property int cardH: 72
        readonly property int gap: 8
        readonly property int slots: 5
        readonly property int cardRadius: root.metrics.fit(10)
        readonly property var listed: {
            const q = root.themeQuery.trim().toLowerCase();
            const src = themes.entries || [];
            const out = [];
            for (let i = 0; i < src.length; i++) {
                const name = String(src[i] && src[i].name || "");
                if (q === "" || name.toLowerCase().indexOf(q) >= 0)
                    out.push({ index: i, entry: src[i] });
            }
            return out;
        }
        readonly property int listedPos: {
            for (let i = 0; i < themes.listed.length; i++)
                if (themes.listed[i].index === themes.cursor) return i;
            return -1;
        }

        function slotItem(slot) {
            const pos = themes.listedPos < 0 ? 0 : themes.listedPos;
            const i = pos - 2 + slot;
            if (i < 0 || i >= themes.listed.length) return null;
            return themes.listed[i];
        }
        function move(d) {
            if (themes.listed.length === 0) return false;
            const pos = themes.listedPos < 0 ? 0 : themes.listedPos;
            const to = pos + d;
            if (to < 0 || to >= themes.listed.length) return false;
            themes.cursorMoved(themes.listed[to].index);
            return true;
        }
        function handleArrow(key) {
            if (key === Qt.Key_Left) return themes.move(root.rtl ? 1 : -1);
            if (key === Qt.Key_Right) return themes.move(root.rtl ? -1 : 1);
            return false;
        }
        function activate() {
            const pos = themes.listedPos;
            if (pos < 0) return false;
            themes.chosen(themes.listed[pos].index);
            return true;
        }

        implicitWidth: root.metrics.content
        implicitHeight: 32 + 8 + cardH + 8 + 16
        width: implicitWidth
        height: implicitHeight
        activeFocusOnTab: true
        Accessible.role: Accessible.List
        Accessible.name: strings.t("style.gallery")

        ContinuousRect {
            id: searchBox
            y: 0
            width: 220
            height: 32
            radius: root.metrics.fit(height / 2)
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                name: "search"
                size: 16
                color: root.muted
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 32
                width: parent.width - 40
                text: root.themeQuery !== "" ? root.themeQuery : strings.t("style.themeSearch")
                textFormat: Text.PlainText
                font.pixelSize: root.metrics.captionText
                elide: Text.ElideRight
                color: root.themeQuery !== "" ? root.fg : root.muted
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: searchBox.verticalCenter
            text: !themes.loaded ? ""
                  : root.pendingTheme !== "" ? strings.t("style.applying")
                  : themes.listed.length === 0 ? "0/0"
                  : ((themes.listedPos < 0 ? 1 : themes.listedPos + 1) + "/" + themes.listed.length)
            textFormat: Text.PlainText
            font.pixelSize: root.metrics.captionText
            color: root.muted
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 32 + 8
            spacing: themes.gap
            Repeater {
                model: themes.slots
                Item {
                    id: slot
                    required property int index
                    readonly property var item: themes.slotItem(index)
                    readonly property bool center: index === 2 && slot.item !== null
                    width: themes.cardW
                    height: themes.cardH
                    opacity: slot.item === null ? 0 : 1

                    ContinuousRect {
                        anchors.fill: parent
                        radius: themes.cardRadius
                        color: root.metrics.plate(root.bg, 0.82)
                        borderWidth: slot.center ? 2 : 1
                        borderColor: slot.center ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)
                    }
                    Item {
                        id: shotSource
                        anchors.fill: parent
                        visible: false
                        layer.enabled: slot.item !== null && shot.status === Image.Ready
                        Image {
                            id: shot
                            anchors.fill: parent
                            source: slot.item && slot.item.entry.preview ? root.fileUrl(slot.item.entry.preview) : ""
                            sourceSize.width: 220
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 36
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.72) }
                            }
                        }
                    }
                    ContinuousRect {
                        id: shotMask
                        anchors.fill: parent
                        radius: themes.cardRadius
                        visible: false
                        layer.enabled: true
                        color: root.fg
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: slot.item !== null && shot.status === Image.Ready
                        source: shotSource
                        maskEnabled: true
                        maskSource: shotMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 22
                        spacing: 3
                        Repeater {
                            model: slot.item && slot.item.entry.colors ? slot.item.entry.colors : []
                            Rectangle {
                                required property string modelData
                                width: 8
                                height: 8
                                radius: 4
                                color: modelData
                            }
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        text: slot.item ? String(slot.item.entry.name || "") : ""
                        textFormat: Text.PlainText
                        font.pixelSize: root.metrics.captionText
                        elide: Text.ElideRight
                        color: shot.status === Image.Ready ? "white" : (slot.center ? root.fg : root.muted)
                    }
                    TapHandler {
                        enabled: slot.item !== null
                        onTapped: {
                            if (slot.center) themes.chosen(slot.item.index);
                            else themes.cursorMoved(slot.item.index);
                        }
                    }
                }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.bottom: parent.bottom
            width: parent.width * 0.6
            text: !themes.loaded ? themes.loadingText
                  : themes.listed.length === 0 ? themes.emptyText : ""
            textFormat: Text.PlainText
            font.pixelSize: root.metrics.captionText
            elide: Text.ElideRight
            color: root.muted
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.bottom: parent.bottom
            text: themes.listedPos < 0 ? "" : strings.t("style.wallApply")
            textFormat: Text.PlainText
            font.pixelSize: root.metrics.captionText
            color: root.muted
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const dy = event.angleDelta.y + event.angleDelta.x;
                if (dy === 0) return;
                themes.move(dy > 0 ? -1 : 1);
            }
        }
    }

    // ---------- Layout ----------
    PanelGrid {
        id: grid
        metrics: root.metrics
        strings: strings
        keyboardMode: root.keyboardMode
        fg: root.fg
        // ----- Tema: busca e paletas -----
        Item {
            id: themeBlock
            width: root.metrics.content
            height: themeStrip.implicitHeight

            function focusItems() { return [themeStrip]; }

            ThemePicker {
                id: themeStrip
                anchors.horizontalCenter: parent.horizontalCenter
                entries: root.themes
                cursor: root.galleryCursor
                marked: root.currentTheme
                loaded: root.themesLoaded
                emptyText: strings.t("style.themesEmpty")
                loadingText: strings.t("style.themesLoading")
                onCursorMoved: index => {
                    root.galleryUserMoved = true;
                    root.galleryCursor = index;
                }
                onChosen: index => {
                    const theme = root.themes[index];
                    if (theme) root.setTheme(theme.name);
                }
            }
        }

        // ----- Fundos do tema em vista: a escolhida sobe, largura da pílula -----
        Item {
            id: wallBlock
            width: root.metrics.content
            height: wallStrip.implicitHeight

            function focusItems() { return [wallStrip]; }

            WallPicker {
                id: wallStrip
                anchors.horizontalCenter: parent.horizontalCenter
                entries: root.wallpapers
                cursor: root.wallCursor
                marked: root.wallpaperPath
                loaded: root.wallsLoaded
                emptyText: strings.t("style.backgroundsEmpty")
                loadingText: root.pendingWallpaper !== "" ? strings.t("style.applying") : strings.t("style.backgroundsLoading")
                onCursorMoved: index => {
                    root.wallUserMoved = true;
                    root.wallCursor = index;
                }
                onChosen: index => root.setWallpaper(index)
            }
        }

        // ----- Fundo: Q W E R -----
        GridRow {
            visible: !root.allThemesOpen
            Tile {
                icon: "skip_next"
                label: strings.t("style.backgroundNext")
                onActivated: root.run(["omarchy", "theme", "bg", "next"])
            }
            Tile {
                icon: "wallpaper"
                label: strings.t("style.backgroundPick")
                closesIsland: true
                onActivated: root.runAfterClose(["omarchy", "theme", "bg-switcher"])
            }
            Tile {
                icon: "auto_awesome"
                label: strings.t("style.wallpaperColorsShort")
                busy: root.paletteBusy
                available: !root.wallpaperIsVideo
                unavailableText: strings.t("style.wallpaperVideoShort")
                onActivated: root.generateFromWallpaper()
            }
            Tile {
                icon: "grid_view"
                label: strings.t("style.allThemes")
                onActivated: {
                    root.allThemesOpen = true
                    themeStrip.forceActiveFocus(Qt.TabFocusReason)
                }
            }
        }

        // ----- Janelas e fonte: Cantos (S D F) com a legenda -----
        Item {
            id: cornersBlock
            visible: !root.allThemesOpen
            width: root.metrics.content
            height: root.metrics.caption + root.metrics.captionGap + root.metrics.slim

            // O PanelGrid numera esta linha como se fosse a própria LabeledRow.
            property int autoKeyRow: -1
            readonly property bool keyable: true
            function focusItems() { return cornersRow.focusItems(); }

            Caption { text: strings.t("style.section.windows") }

            LabeledRow {
                id: cornersRow
                y: root.metrics.caption + root.metrics.captionGap
                variant: "segmented"
                keyRow: cornersBlock.autoKeyRow
                label: strings.t("style.corners")
                value: currentIndex >= 0 ? options[currentIndex].label : ""
                current: root.corners
                options: [
                    { value: "theme", label: strings.t("style.corners.theme") },
                    { value: "sharp", label: strings.t("style.corners.sharp") },
                    { value: "rounded", label: strings.t("style.corners.rounded") }
                ]
                metrics: root.metrics
                strings: strings
                keyboardMode: root.keyboardMode
                fg: root.fg
                bg: root.bg
                accent: root.accent
                danger: root.danger
                muted: root.muted
                onPicked: value => root.setCorners(value)
            }
        }

        // ----- Transparência: X C V -----
        LabeledRow {
            visible: !root.allThemesOpen
            variant: "segmented"
            label: strings.t("style.transparency")
            value: currentIndex >= 0 ? options[currentIndex].label : ""
            current: root.transparency
            options: [
                { value: "opaque", label: strings.t("style.transparency.opaque") },
                { value: "transparent", label: strings.t("style.transparency.transparent") },
                { value: "glassy", label: strings.t("style.transparency.glassy") }
            ]
            metrics: root.metrics
            strings: strings
            keyboardMode: root.keyboardMode
            fg: root.fg
            bg: root.bg
            accent: root.accent
            danger: root.danger
            muted: root.muted
            onPicked: value => root.setTransparency(value)
        }

        // ----- Fonte: ‹ chips › ([ ]) -----
        LabeledRow {
            id: fontRow
            visible: !root.allThemesOpen
            variant: "chips"
            label: strings.t("style.font")
            value: root.currentFont
            current: root.pendingFont !== "" ? root.pendingFont : root.currentFont
            stepPreview: true
            options: root.fonts.map(f => ({ value: f, label: f, font: f }))
            metrics: root.metrics
            strings: strings
            keyboardMode: root.keyboardMode
            fg: root.fg
            bg: root.bg
            accent: root.accent
            danger: root.danger
            muted: root.muted
            onPreviewed: value => root.pendingFont = value
            onPicked: value => {
                root.pendingFont = "";
                root.setFont(value);
            }
        }
    }
}
