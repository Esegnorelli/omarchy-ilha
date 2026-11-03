import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Estilo (spec §3.4): como o sistema parece, em três páginas enxutas com a
// mesma largura (só a altura muda). Abas no cabeçalho; Tab / ⇧Tab trocam.
//
//   TEMA            carrossel de amostras: o fundo do tema, a paleta e o nome
//                   nas cores dele. ←→ escolhem, ↵ aplica. O ponto de destaque
//                   marca o tema em uso. / abre a busca. R ou o botão de grade
//                   abre Todos os temas (grade de 4 colunas, ←→ ±1, ↑↓ ±4).
//   FUNDO           carrossel do tema no centro. A escolhida fica inteira e
//                   contornada; as vizinhas encolhem. Rodapé: arquivo e 1/13.
//                   ←→ escolhem, ↵ e o clique na escolhida aplicam.
//                   Q Próximo fundo · W Escolher fundo… · E Cores do fundo
//   JANELAS E FONTE Cantos (W E R) · Transparência (S D F) · Fonte ‹ chips › ([ ])
//                   Ilha (Z X C): nível 2 ao parar o ponteiro · pílula só no
//                   monitor focado · aviso ao vivo. Gravadas em bar.ilha do
//                   shell.json pelo Prefs (o Island liga `prefs` pelo StateSlot).
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
    // Texto de segundo plano (rótulos laterais, contagens, legendas): o muted
    // um degrau acima, pelo token do Metrics. Com o par fg/muted daqui, para
    // acompanhar a prévia do tema; sem o token, fica o muted.
    readonly property color textSecondary: {
        const m = root.metrics;
        if (m && typeof m.secondaryOf === "function")
            return m.secondaryOf(root.fg, root.muted);
        const v = m ? m["textSecondary"] : undefined;
        if (v !== undefined && v !== null && v !== "")
            return v;
        return root.muted;
    }

    // O host liga enquanto este estado está visível; as leituras são refeitas ao ligar.
    property bool active: false
    property var shell: null
    property Metrics metrics: Metrics {}
    property bool keyboardMode: false
    // Preferências da ilha (Prefs.qml). O Island liga pelo StateSlot; sem ele,
    // as três chaves da página Janelas ficam indisponíveis.
    property var prefs: null

    readonly property bool rtl: Commons.I18n.rightToLeft

    signal closeRequested()
    signal navigate(string target)
    // A ilha pinta a paleta na hora. O comando do sistema vem depois.
    signal themePreview(string name)
    signal themeSettled()
    signal lookCorners(string mode)
    signal lookGlass(string mode)
    signal lookFont(string name)

    // Largura fixa nas três páginas (ilha de 564): trocar de aba só mexe na altura.
    readonly property int panelContent: 536
    implicitWidth: panelContent
    implicitHeight: grid.implicitHeight

    // Página à vista: "theme" | "background" | "windows".
    property string page: "theme"
    readonly property var pages: ["theme", "background", "windows"]

    // Troca de página: as buscas e a grade de Todos os temas não atravessam
    // abas (nada fica filtrando escondido). O foco vai para o primeiro item.
    function setPage(next, reason) {
        if (root.pages.indexOf(next) < 0) return;
        if (next !== root.page) {
            root.themeQuery = "";
            root.themeTyping = false;
            root.wallQuery = "";
            root.wallTyping = false;
            if (next !== "theme") root.allThemesOpen = false;
            root.page = next;
        }
        root.focusPage(reason === undefined ? Qt.TabFocusReason : reason);
    }
    function stepPage(d) {
        const i = root.pages.indexOf(root.page);
        const n = root.pages.length;
        root.setPage(root.pages[(i + d + n) % n], Qt.TabFocusReason);
    }
    function focusPage(reason) {
        const r = reason === undefined ? Qt.TabFocusReason : reason;
        if (root.page === "background") {
            wallStrip.forceActiveFocus(r);
            return true;
        }
        if (root.page === "windows") {
            const it = cornersRow.focusItems()[0];
            if (it) it.forceActiveFocus(r);
            return !!it;
        }
        themeStrip.forceActiveFocus(r);
        return true;
    }
    // Fonte do Estilo (o host liga a mesma da ilha).
    property string fontFamily: Commons.Style.fontFamily

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // ---------- Contrato ----------
    // Rodapé só no modo teclado: com o ponteiro, as abas já dizem tudo.
    readonly property string footerStatus: !root.keyboardMode ? ""
                                         : [root.currentTheme, root.background].filter(s => s !== "").join(" · ")
    readonly property string footerHints: !root.keyboardMode ? ""
                                        : root.allThemesOpen ? strings.t("hint.styleAllThemes", strings.t("hint.styleAll"))
                                        : strings.t("hint.stylePages", strings.t("hint.style"))

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        // Tab / ⇧Tab trocam de página (Ctrl+Tab segue com a ilha: troca de painel).
        if (!mods && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)) {
            grid.navigated = true;
            if (!event.isAutoRepeat)
                root.stepPage(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
            return true;
        }
        // R na página Tema, sem busca: abre ou fecha Todos os temas.
        if (!mods && event.key === Qt.Key_R && root.page === "theme"
                && root.themeQuery === "" && !root.themeTyping
                && !(event.modifiers & Qt.ShiftModifier)) {
            if (!event.isAutoRepeat) {
                grid.navigated = true;
                root.allThemesOpen = !root.allThemesOpen;
                themeStrip.forceActiveFocus(Qt.ShortcutFocusReason);
            }
            return true;
        }
        if (!mods && (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight)) {
            // [ ] só escolhem a fonte e levam o foco até ela; Enter aplica.
            // Fora da página Janelas, o primeiro toque só leva até ela.
            if (root.page !== "windows") {
                if (!event.isAutoRepeat) {
                    grid.navigated = true;
                    root.setPage("windows", Qt.ShortcutFocusReason);
                    const box = fontRow.focusItems()[0];
                    if (box) box.forceActiveFocus(Qt.ShortcutFocusReason);
                }
                return true;
            }
            if (!event.isAutoRepeat) {
                grid.navigated = true;
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
    // Com a faixa focada, o que se digita filtra. Com a busca vazia, as
    // letras dos atalhos (Q W E R, A S D F, Z X C V) e os dígitos continuam
    // sendo atalhos; / arma a busca e aí tudo vira texto. Esc ou apagar a
    // busca inteira desarma.
    function typeTheme(event) {
        if (root.page !== "theme" || !themeStrip.activeFocus) return false;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods || event.isAutoRepeat) return false;
        if (event.key === Qt.Key_Backspace) {
            if (root.themeQuery.length === 0) {
                if (!root.themeTyping) return false;
                root.themeTyping = false;
                return true;
            }
            root.themeQuery = root.themeQuery.slice(0, -1);
            return true;
        }
        const text = event.text || "";
        if (text.length !== 1 || /[\u0000-\u001f]/.test(text)) return false;
        if (text === "/" && !root.themeTyping) {
            root.themeTyping = true;
            return true;
        }
        const idle = root.themeQuery.length === 0 && !root.themeTyping;
        if (idle && grid._letters[event.key] !== undefined) return false;
        if (idle && /[0-9]/.test(text)) return false;
        if (root.themeQuery.length >= 32) return true;
        root.themeQuery += text;
        return true;
    }
    function typeWall(event) {
        if (root.page !== "background" || !wallStrip.activeFocus) return false;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods || event.isAutoRepeat) return false;
        if (event.key === Qt.Key_Backspace) {
            if (root.wallQuery.length === 0) {
                if (!root.wallTyping) return false;
                root.wallTyping = false;
                return true;
            }
            root.wallQuery = root.wallQuery.slice(0, -1);
            return true;
        }
        const text = event.text || "";
        if (text.length !== 1 || /[\u0000-\u001f]/.test(text)) return false;
        if (text === "/" && !root.wallTyping) {
            root.wallTyping = true;
            return true;
        }
        const idle = root.wallQuery.length === 0 && !root.wallTyping;
        if (idle && grid._letters[event.key] !== undefined) return false;
        if (idle && /[0-9]/.test(text)) return false;
        if (root.wallQuery.length >= 32) return true;
        root.wallQuery += text;
        return true;
    }
    // Esc: busca → Todos os temas → volta à página Tema → o que a grade tiver armado.
    function handleEscape() {
        if (wallQuery !== "" || wallTyping) {
            wallQuery = ""
            wallTyping = false
            return true
        }
        if (themeQuery !== "" || themeTyping) {
            themeQuery = ""
            themeTyping = false
            return true
        }
        if (allThemesOpen) {
            allThemesOpen = false
            return true
        }
        if (page !== "theme") {
            grid.disarmAll()
            setPage("theme", Qt.ShortcutFocusReason)
            return true
        }
        return grid.handleEscape()
    }
    function focusFirst() { return root.focusPage(Qt.TabFocusReason); }

    // Cartão do meio em cada carrossel. galleryUserMoved evita puxar o tema
    // de volta para o atual enquanto a pessoa ainda está folheando.
    property int galleryCursor: -1
    // Texto da busca de temas. Vazio mostra a lista inteira.
    property string themeQuery: ""
    // Busca da faixa de fundos, pelo nome do arquivo.
    property string wallQuery: ""
    // / armou a busca: as letras dos atalhos viram texto até Esc ou a busca esvaziar.
    property bool themeTyping: false
    property bool wallTyping: false
    onWallQueryChanged: Qt.callLater(() => {
        if (root.wallQuery === "") root.wallTyping = false;
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
        if (root.themeQuery === "") root.themeTyping = false;
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
    property var themes: []          // [{ name, preview, colors, bg, fg }]
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

    // Todos os temas (só na página Tema): a faixa vira uma grade de 4 colunas,
    // até 3 linhas à vista. Os fundos seguem o tema do cursor. Esc volta à faixa.
    property bool allThemesOpen: false

    onActiveChanged: {
        if (!active) {
            pendingFont = ""
            allThemesOpen = false
            themeQuery = ""
            wallQuery = ""
            themeTyping = false
            wallTyping = false
        }
        if (active) {
            root.page = "theme";
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
            // A paleta, o fundo e o texto do tema saem numa linha; "-" marca o que falta.
            "dots=''; tbg=''; tfg=''; if [ -n \"$toml\" ]; then pal=$(awk '" +
            "{ n=split($0, a, \"=\"); if (n < 2) next; key=a[1]; val=a[2]; gsub(/[ \\t\"]/, \"\", key); gsub(/[ \\t\"]/, \"\", val); if (val ~ /^#[0-9A-Fa-f]{6}$/) c[key]=val } " +
            "END { n=split(\"red orange yellow green cyan blue magenta accent\", keys, \" \"); out=\"\"; for (i=1; i<=n; i++) if ((keys[i] in c) && !seen[c[keys[i]]]++) out=out (out==\"\" ? \"\" : \",\") c[keys[i]]; " +
            "print (out==\"\" ? \"-\" : out), ((\"background\" in c) ? c[\"background\"] : \"-\"), ((\"foreground\" in c) ? c[\"foreground\"] : \"-\") }' " +
            "\"$toml\"); set -- $pal; dots=$1; tbg=$2; tfg=$3; fi; " +
            "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$n\" \"$p\" \"$dots\" \"$tbg\" \"$tfg\"; done"]
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
                    // Fundo e texto do tema pintam a amostra; sem eles, a prévia entra.
                    const hex = v => /^#[0-9A-Fa-f]{6}$/.test(String(v || "")) ? String(v) : "";
                    out.push({
                        name: parts[0],
                        preview: parts.length > 1 ? parts[1] : "",
                        colors: colors,
                        bg: hex(parts[3]),
                        fg: hex(parts[4])
                    });
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
    // Aba do cabeçalho: 13 px, a ativa em DemiBold fg; as outras em Medium secundário.
    component PageTab: Text {
        id: tab
        property string pageName: ""
        readonly property bool current: root.page === tab.pageName
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: 13
        font.weight: tab.current ? Font.DemiBold : Font.Medium
        color: tab.current ? root.fg : root.textSecondary
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
        Accessible.role: Accessible.PageTab
        Accessible.name: tab.text
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.setPage(tab.pageName, Qt.MouseFocusReason) }
    }

    // Máscara das bordas das faixas: opaca no meio e some em `edge` px nos
    // dois lados. Com o MultiEffect (limiar 0.5, espalhamento 1) o degradê vira
    // uma rampa suave; o cartão que sai pela borda esmaece em vez de ser cortado.
    component EdgeMask: Rectangle {
        id: edgeMask
        property real edge: 56
        readonly property real stop: Math.min(0.5, edge / Math.max(1, width))
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0) }
            GradientStop { position: edgeMask.stop; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 1) }
            GradientStop { position: 1 - edgeMask.stop; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 1) }
            GradientStop { position: 1; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0) }
        }
    }

    // Amostra de um tema: o fundo do tema, a paleta em pontos e o nome na cor
    // do texto dele. Sem cores no tema, a imagem de prévia entra no lugar.
    // O contorno marca o cursor (destaque só com a faixa focada) e o ponto
    // de 6 px marca o tema em uso.
    component ThemeCard: Item {
        id: tc
        property var entry: null
        property bool selected: false
        property bool applied: false
        property bool focused: false
        signal tapped()

        // Mesmo raio de Metrics.cardRadius (fit(20)).
        readonly property real radius: root.metrics.fit(20)
        readonly property bool swatch: !!(tc.entry && tc.entry.bg)
        readonly property bool fallback: !tc.swatch && !!(tc.entry && tc.entry.preview)

        // Base. O fio de 1 px só existe para uma amostra igual ao painel não sumir.
        ContinuousRect {
            anchors.fill: parent
            radius: tc.radius
            color: tc.swatch ? tc.entry.bg : root.metrics.plate(root.bg, 0.9)
            borderWidth: 1
            borderColor: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
        }

        // Prévia, só quando o tema não traz cores.
        Item {
            id: shotSource
            anchors.fill: parent
            visible: false
            layer.enabled: tc.fallback && shot.status === Image.Ready
            Image {
                id: shot
                anchors.fill: parent
                source: tc.fallback ? root.fileUrl(tc.entry.preview) : ""
                sourceSize.width: 260
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 28
                color: root.metrics.plate(root.bg, 0.72)
            }
        }
        ContinuousRect {
            id: shotMask
            anchors.fill: parent
            radius: tc.radius
            visible: false
            layer.enabled: tc.fallback
            color: root.fg
        }
        MultiEffect {
            anchors.fill: parent
            visible: tc.fallback && shot.status === Image.Ready
            source: shotSource
            maskEnabled: true
            maskSource: shotMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Row {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -8
            spacing: 5
            Repeater {
                model: tc.entry && tc.entry.colors ? tc.entry.colors : []
                Rectangle {
                    required property string modelData
                    width: 10
                    height: 10
                    radius: 5
                    color: modelData
                }
            }
        }
        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            horizontalAlignment: Text.AlignHCenter
            text: tc.entry ? String(tc.entry.name || "") : ""
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            color: tc.swatch && tc.entry.fg ? tc.entry.fg : root.fg
        }

        // Tema em uso.
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            width: 6
            height: 6
            radius: 3
            color: root.accent
            opacity: tc.applied ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
        }

        // Cursor.
        ContinuousRect {
            anchors.fill: parent
            radius: tc.radius
            color: "transparent"
            borderWidth: 2
            borderColor: tc.focused ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.35)
            opacity: tc.selected ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tc.tapped() }
    }

    // Fundos do tema no centro. A escolhida fica inteira e contornada; as
    // vizinhas encolhem e esmaecem. O nome do arquivo vai no rodapé.
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

        // 160 × 90 no centro: menor que o seletor do sistema, sem cabeçalho
        // próprio (as abas do Estilo fazem esse papel).
        readonly property int thumbW: 160
        readonly property int thumbH: 90
        readonly property int gap: 12
        readonly property int footerH: 16
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
        readonly property var focusEntry: picker.listed.length > 0 && picker.focusPos < picker.listed.length
                                          ? picker.listed[picker.focusPos].entry : null
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
        implicitHeight: row.height + 6 + footerH
        width: implicitWidth
        height: implicitHeight
        activeFocusOnTab: true
        Accessible.role: Accessible.List
        Accessible.name: strings.t("style.section.background")

        Item {
            id: row
            width: parent.width
            // Folga de 4 px em cima e embaixo para o contorno da escolhida.
            height: picker.thumbH + 8
            clip: true

            readonly property real centerX: width / 2

            // Escala por distância do centro, e o deslocamento que mantém o
            // mesmo vão visível entre miniaturas de tamanhos diferentes: os
            // vizinhos ficam simétricos em volta da escolhida.
            function scaleAt(a) { return a === 0 ? 1 : a === 1 ? 0.82 : 0.68; }
            function offsetFor(d) {
                const a = Math.abs(d);
                let off = 0;
                for (let k = 1; k <= a; k++)
                    off += picker.thumbW * (row.scaleAt(k - 1) + row.scaleAt(k)) / 2 + picker.gap;
                return d < 0 ? -off : off;
            }

            // As bordas esmaecem em vez de cortar a miniatura que sai da faixa.
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: rowMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

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
                    x: row.centerX + row.offsetFor(distance) * (root.rtl ? -1 : 1) - width / 2
                    y: (row.height - height) / 2
                    z: 100 - absDistance
                    scale: row.scaleAt(absDistance)
                    transformOrigin: Item.Center
                    opacity: {
                        if (isActive || absDistance === 0) return 1;
                        if (absDistance === 1) return 0.75;
                        if (absDistance === 2) return 0.4;
                        return 0;
                    }
                    visible: opacity > 0.01
                    Behavior on x { enabled: picker.settle; NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }
                    Behavior on scale { enabled: picker.settle; NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }
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
                            sourceSize.width: 256
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: shot.status !== Image.Ready
                            name: thumb.entry && thumb.entry.video ? "movie" : "image"
                            size: 18
                            color: root.textSecondary
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
                    // Fundo em uso.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 6
                        height: 6
                        radius: 3
                        color: root.accent
                        visible: thumb.isActive
                    }
                    // Escolhida: contorno de destaque, apagado sem foco.
                    ContinuousRect {
                        anchors.fill: parent
                        anchors.margins: -2
                        radius: root.metrics.corners === "sharp" ? 0 : picker.thumbRadius + 2
                        color: "transparent"
                        borderWidth: 2
                        borderColor: root.accent
                        opacity: thumb.isSelected ? (picker.activeFocus ? 1 : 0.4) : 0
                        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
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
                font.family: root.fontFamily
                font.pixelSize: 13
                color: root.textSecondary
            }
        }
        EdgeMask {
            id: rowMask
            x: row.x
            y: row.y
            width: row.width
            height: row.height
            edge: 56
        }

        // Rodapé: o arquivo da escolhida e a contagem.
        Item {
            y: row.y + row.height + 6
            width: parent.width
            height: picker.footerH

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - countText.implicitWidth - 16
                text: picker.focusEntry ? String(picker.focusEntry.path || "").split("/").pop() : ""
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideMiddle
                color: root.textSecondary
            }
            Text {
                id: countText
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                text: !picker.loaded || picker.listed.length === 0 ? ""
                      : ((picker.listedPos < 0 ? 1 : picker.listedPos + 1) + "/" + picker.listed.length
                         + " · " + strings.t("style.wallApply"))
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
                color: root.textSecondary
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

    // Faixa de temas: linha de busca e o carrossel de amostras. Em Todos os
    // temas vira uma grade de 4 colunas. Enter aplica.
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

        readonly property int cardW: 140
        readonly property int cardH: 80
        readonly property int gap: 10
        // Folga de 4 px em cima e embaixo para o contorno de 2 px do cursor.
        readonly property int stripH: cardH + 8
        // Linha de 16 px sob a faixa: o tema em uso e a contagem.
        readonly property int lineH: 16
        // Grade de Todos os temas: 4 colunas, no máximo 3 linhas à vista.
        readonly property bool gridMode: root.allThemesOpen
        readonly property int columns: 4
        readonly property int cellH: 64
        readonly property real cellW: (width - (columns - 1) * gap) / columns
        readonly property int rowCount: Math.ceil(themes.listed.length / columns)
        readonly property int rowsShown: Math.max(1, Math.min(3, rowCount))
        readonly property real gridH: rowsShown * cellH + (rowsShown - 1) * gap
        readonly property real bodyH: gridMode ? gridH : stripH + 6 + lineH
        // Contagem "n/N" (ou "Aplicando…"), lida também pelo cabeçalho do Estilo.
        readonly property string countText: !themes.loaded ? ""
                                            : root.pendingTheme !== "" ? strings.t("style.applying")
                                            : themes.listed.length === 0 ? "0/0"
                                            : ((themes.listedPos < 0 ? 1 : themes.listedPos + 1) + "/" + themes.listed.length)

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
        readonly property int focusPos: themes.listedPos < 0 ? 0 : themes.listedPos
        property bool settle: false

        function moveTo(to) {
            if (to < 0 || to >= themes.listed.length) return false;
            themes.cursorMoved(themes.listed[to].index);
            return true;
        }
        function move(d) {
            if (themes.listed.length === 0) return false;
            return themes.moveTo(themes.focusPos + d);
        }
        function handleArrow(key) {
            if (key === Qt.Key_Left) return themes.move(root.rtl ? 1 : -1);
            if (key === Qt.Key_Right) return themes.move(root.rtl ? -1 : 1);
            if (!themes.gridMode || themes.listed.length === 0) return false;
            const pos = themes.focusPos;
            const n = themes.listed.length;
            const c = themes.columns;
            if (key === Qt.Key_Up) return themes.moveTo(pos - c);
            if (key === Qt.Key_Down) {
                // Última linha incompleta: desce para o último tema.
                if (pos + c < n) return themes.moveTo(pos + c);
                if (Math.floor(pos / c) < Math.floor((n - 1) / c)) return themes.moveTo(n - 1);
                return false;
            }
            return false;
        }
        function activate() {
            const pos = themes.listedPos;
            if (pos < 0) return false;
            themes.chosen(themes.listed[pos].index);
            return true;
        }
        // Mantém a linha do cursor à vista na grade.
        function revealCursor() {
            if (!themes.gridMode) return;
            const top = Math.floor(themes.focusPos / themes.columns) * (themes.cellH + themes.gap);
            const bottom = top + themes.cellH;
            const maxY = Math.max(0, gridView.contentHeight - gridView.height);
            let y = gridView.contentY;
            if (top < y) y = top;
            else if (bottom > y + gridView.height) y = bottom - gridView.height;
            const to = Math.max(0, Math.min(maxY, y));
            if (Math.abs(to - gridView.contentY) < 0.5) return;
            // Só a rolagem pelo teclado anima; arrastar a grade segue o dedo.
            if (!themes.settle) {
                gridView.contentY = to;
                return;
            }
            gridScroll.stop();
            gridScroll.from = gridView.contentY;
            gridScroll.to = to;
            gridScroll.start();
        }
        NumberAnimation {
            id: gridScroll
            target: gridView
            property: "contentY"
            duration: Commons.Style.duration(200)
            easing.type: Easing.OutCubic
        }
        onFocusPosChanged: Qt.callLater(themes.revealCursor)
        onGridModeChanged: Qt.callLater(themes.revealCursor)

        Component.onCompleted: Qt.callLater(() => { themes.settle = true; })

        implicitWidth: root.metrics.content
        implicitHeight: bodyH
        width: implicitWidth
        height: implicitHeight
        activeFocusOnTab: true
        Accessible.role: Accessible.List
        Accessible.name: strings.t("style.gallery")

        // Carrossel: o cartão do cursor no centro, os vizinhos deslizam.
        Item {
            id: carousel
            width: parent.width
            height: themes.stripH
            visible: !themes.gridMode
            clip: true
            // As amostras que saem pela borda esmaecem em vez de serem cortadas.
            layer.enabled: visible
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: carouselMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            Repeater {
                model: themes.gridMode ? [] : themes.listed
                ThemeCard {
                    id: card
                    required property int index
                    required property var modelData
                    readonly property int dist: Math.abs(index - themes.focusPos)

                    entry: modelData.entry
                    selected: dist === 0
                    applied: !!(entry && entry.name === themes.marked)
                    focused: themes.activeFocus
                    width: themes.cardW
                    height: themes.cardH
                    y: (carousel.height - height) / 2
                    x: carousel.width / 2 + (index - themes.focusPos) * (themes.cardW + themes.gap) * (root.rtl ? -1 : 1) - themes.cardW / 2
                    z: 100 - dist
                    visible: dist <= 3
                    opacity: [1, 0.8, 0.45][Math.min(dist, 2)]
                    scale: dist === 0 ? 1 : 0.94
                    transformOrigin: Item.Center
                    Behavior on x { enabled: themes.settle; NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }
                    Behavior on scale { enabled: themes.settle; NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }
                    Behavior on opacity { enabled: themes.settle; NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }

                    onTapped: {
                        themes.forceActiveFocus(Qt.MouseFocusReason);
                        if (card.selected) themes.chosen(card.modelData.index);
                        else themes.cursorMoved(card.modelData.index);
                    }
                }
            }
        }
        EdgeMask {
            id: carouselMask
            x: carousel.x
            y: carousel.y
            width: carousel.width
            height: carousel.height
            edge: 64
        }

        // Sob a faixa: o tema em uso à esquerda, a contagem e o ↵ à direita.
        Item {
            y: carousel.height + 6
            width: parent.width
            height: themes.lineH
            visible: !themes.gridMode

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - lineCount.implicitWidth - 16)
                text: root.currentTheme
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                color: root.textSecondary
            }
            Text {
                id: lineCount
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                text: themes.countText === "" || root.pendingTheme !== "" ? themes.countText
                      : themes.countText + " · " + strings.t("style.wallApply")
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
                color: root.textSecondary
            }
        }

        // Todos os temas: grade de 4 colunas que rola até o cursor.
        Flickable {
            id: gridView
            width: parent.width
            height: themes.gridH
            visible: themes.gridMode
            clip: true
            contentWidth: width
            contentHeight: themeGrid.height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id: themeGrid
                width: parent.width
                columns: themes.columns
                spacing: themes.gap
                // RTL: o espelho herdado da ilha já inverte a grade; virar aqui
                // de novo a deixaria LTR.
                layoutDirection: Qt.LeftToRight

                Repeater {
                    model: themes.gridMode ? themes.listed : []
                    ThemeCard {
                        id: cell
                        required property int index
                        required property var modelData

                        entry: modelData.entry
                        selected: index === themes.focusPos
                        applied: !!(entry && entry.name === themes.marked)
                        focused: themes.activeFocus
                        width: themes.cellW
                        height: themes.cellH

                        onTapped: {
                            themes.forceActiveFocus(Qt.MouseFocusReason);
                            if (cell.selected) themes.chosen(cell.modelData.index);
                            else themes.cursorMoved(cell.modelData.index);
                        }
                    }
                }
            }
        }

        Text {
            x: 0
            width: parent.width
            height: themes.gridMode ? themes.bodyH : themes.stripH
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            visible: !themes.loaded || themes.listed.length === 0
            text: !themes.loaded ? themes.loadingText : themes.emptyText
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: 13
            elide: Text.ElideRight
            color: root.textSecondary
        }

        WheelHandler {
            enabled: !themes.gridMode
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

        // ----- Cabeçalho (28 px): abas à esquerda, contexto da página à direita -----
        Item {
            id: pageHeader
            width: root.metrics.content
            height: 28

            // A busca armada ou digitada na página toma o lugar das abas.
            readonly property bool searching: root.page === "theme" ? (root.themeQuery !== "" || root.themeTyping)
                                            : root.page === "background" ? (root.wallQuery !== "" || root.wallTyping)
                                            : false
            readonly property Item activeTab: root.page === "background" ? tabBackground
                                            : root.page === "windows" ? tabWindows : tabTheme

            // Uma Row: espelha sozinha em RTL (e o x das abas já vem espelhado).
            Row {
                id: tabs
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -1
                spacing: 16
                visible: !pageHeader.searching

                PageTab { id: tabTheme; pageName: "theme"; text: strings.t("style.section.theme") }
                PageTab { id: tabBackground; pageName: "background"; text: strings.t("style.section.background") }
                PageTab { id: tabWindows; pageName: "windows"; text: strings.t("style.section.windows") }
            }
            // Sublinhado de 2 px sob a aba ativa.
            Rectangle {
                visible: !pageHeader.searching
                y: 26
                height: 2
                radius: 1
                x: tabs.x + pageHeader.activeTab.x
                width: pageHeader.activeTab.width
                color: root.accent
                Behavior on x { NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic } }
            }

            // Busca: "⌕ texto" ou o convite quando só armada.
            Text {
                id: searchText
                readonly property string query: root.page === "theme" ? root.themeQuery : root.wallQuery
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - rightSide.width - 16)
                visible: pageHeader.searching
                text: searchText.query !== "" ? "⌕ " + searchText.query
                      : "⌕ " + strings.t(root.page === "theme" ? "style.themeSearch" : "style.wallSearch")
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: searchText.query !== "" ? root.fg : root.textSecondary
            }

            // Direita: Tema → n/N e a grade; Fundo → o tema dos fundos; Janelas → nada.
            Row {
                id: rightSide
                anchors.right: parent.right
                anchors.rightMargin: root.page === "theme" ? 0 : 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.page === "theme"
                    text: themeStrip.countText
                    textFormat: Text.PlainText
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.features: ({ "tnum": 1 })
                    color: root.textSecondary
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.page === "theme"
                    size: 24
                    iconSize: 16
                    icon: "grid_view"
                    label: strings.t("style.allThemes")
                    highlighted: root.allThemesOpen
                    fg: root.fg
                    accent: root.accent
                    muted: root.muted
                    fontFamily: root.fontFamily
                    metrics: root.metrics
                    onTapped: {
                        root.allThemesOpen = !root.allThemesOpen;
                        themeStrip.forceActiveFocus(Qt.MouseFocusReason);
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.page === "background"
                    width: Math.min(implicitWidth, pageHeader.width * 0.4)
                    text: root.wallTheme + (root.pendingWallpaper !== "" ? " · " + strings.t("style.applying") : "")
                    textFormat: Text.PlainText
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    color: root.textSecondary
                }
            }
        }

        // ----- Tema: carrossel de paletas (ou a grade de Todos os temas) -----
        Item {
            id: themeBlock
            visible: root.page === "theme"
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
                // Saiu da faixa sem digitar nada: a busca desarma.
                onActiveFocusChanged: if (!activeFocus && root.themeQuery === "") root.themeTyping = false
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

        // ----- Fundo: os fundos do tema em vista, a escolhida no centro -----
        Item {
            id: wallBlock
            visible: root.page === "background"
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
                onActiveFocusChanged: if (!activeFocus && root.wallQuery === "") root.wallTyping = false
                onCursorMoved: index => {
                    root.wallUserMoved = true;
                    root.wallCursor = index;
                }
                onChosen: index => root.setWallpaper(index)
            }
        }

        // ----- Fundo: Q W E, botões compactos de 32 px em 3 colunas -----
        GridRow {
            visible: root.page === "background"
            columns: 3
            tileHeight: root.metrics.compact
            Tile {
                compact: true
                icon: "skip_next"
                label: strings.t("style.backgroundNext")
                onActivated: root.run(["omarchy", "theme", "bg", "next"])
            }
            Tile {
                compact: true
                icon: "wallpaper"
                label: strings.t("style.backgroundPick")
                closesIsland: true
                onActivated: root.runAfterClose(["omarchy", "theme", "bg-switcher"])
            }
            Tile {
                compact: true
                icon: "auto_awesome"
                label: strings.t("style.wallpaperColorsShort")
                busy: root.paletteBusy
                available: !root.wallpaperIsVideo
                unavailableText: strings.t("style.wallpaperVideoShort")
                onActivated: root.generateFromWallpaper()
            }
        }

        // ----- Janelas e fonte: Cantos (W E R) -----
        // Sem legenda: a aba já diz "Janelas e fonte".
        LabeledRow {
            id: cornersRow
            visible: root.page === "windows"
            variant: "segmented"
            label: strings.t("style.corners")
            // O segmento ligado já diz o modo: sem repetir à direita.
            value: ""
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
            muted: root.textSecondary
            onPicked: value => root.setCorners(value)
        }

        // ----- Transparência: S D F -----
        LabeledRow {
            visible: root.page === "windows"
            variant: "segmented"
            label: strings.t("style.transparency")
            value: ""
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
            muted: root.textSecondary
            onPicked: value => root.setTransparency(value)
        }

        // ----- Fonte: ‹ chips › ([ ]) -----
        LabeledRow {
            id: fontRow
            visible: root.page === "windows"
            variant: "chips"
            label: strings.t("style.font")
            // Só avisa que falta o ↵ enquanto a fonte marcada não foi aplicada.
            value: root.pendingFont !== "" && root.pendingFont !== root.currentFont ? strings.t("style.wallApply") : ""
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
            muted: root.textSecondary
            onPreviewed: value => root.pendingFont = value
            onPicked: value => {
                root.pendingFont = "";
                root.setFont(value);
            }
        }

        // ----- Ilha: Z X C, chaves compactas de 32 px em 3 colunas -----
        // A fonte (chips) não tem tecla: esta é a 3ª linha com tecla do PanelGrid.
        GridRow {
            visible: root.page === "windows"
            columns: 3
            tileHeight: root.metrics.compact
            caption: strings.t("style.island", "Island")
            Tile {
                compact: true
                kind: "toggle"
                icon: "touch_app"
                label: strings.t("style.level2Dwell", "Level 2 on rest")
                on: !!root.prefs && root.prefs.level2Dwell
                available: !!root.prefs
                onActivated: if (root.prefs) root.prefs.toggle("level2Dwell")
            }
            Tile {
                compact: true
                kind: "toggle"
                icon: "desktop_windows"
                label: strings.t("style.focusedOnly", "Focused monitor only")
                on: !!root.prefs && root.prefs.focusedOnly
                available: !!root.prefs
                onActivated: if (root.prefs) root.prefs.toggle("focusedOnly")
            }
            Tile {
                compact: true
                kind: "toggle"
                icon: "notifications"
                label: strings.t("style.livePeek", "Live notice")
                on: !!root.prefs && root.prefs.livePeek
                available: !!root.prefs
                onActivated: if (root.prefs) root.prefs.toggle("livePeek")
            }
        }
    }
}
