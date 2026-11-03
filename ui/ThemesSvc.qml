import QtQuick
import Quickshell
import Quickshell.Io
import "Motion.js" as Motion

// Temas e papéis de parede (dono: Agent G). Um objeto só, island.themes.
//
// Temas
// - Lista: as pastas de ~/.config/omarchy/themes e $OMARCHY_PATH/themes
//   (a mesma união do `omarchy theme list`), com o colors.toml de cada uma
//   lido por awk: vermelho, verde, amarelo, azul, magenta, ciano, fundo,
//   texto e accent. O do usuário vence, como no `omarchy theme set` (que
//   copia o tema do sistema e põe o do usuário por cima).
// - Atual: ~/.local/state/omarchy/current/theme.name (um FileView que vigia
//   o arquivo), com a guarda de escrita velha da 1.x: enquanto pendingCurrent
//   espera, uma gravação do tema anterior não pinta por cima.
// - Aplicar: `omarchy-theme-set <slug>`, solto do shell (execDetached), para
//   um recarregamento da barra no meio nunca deixar um tema pela metade. A
//   confirmação é o theme.name mudar para o pedido (sinal applied()).
//
// Papéis de parede
// - Lista: `omarchy-menu-images --print-rows` com as mesmas pastas do
//   omarchy-theme-bg-switcher (current/theme/backgrounds e
//   ~/.config/omarchy/backgrounds/<tema>). O Omarchy aquece essas miniaturas
//   depois de cada `theme set` (omarchy-theme-bg-cache), então a leitura é
//   rápida. Guardada por tema: abrir de novo mostra a lista na hora e a
//   releitura só troca o que mudou.
// - Atual: readlink -f de current/background. O link costuma apontar para a
//   cópia do tema no sistema (outro inode), então a comparação cai para o
//   nome do arquivo quando o caminho não bate.
// - Aplicar: `omarchy-theme-bg-set <caminho>` (curto: entrega ao shell e
//   sai); wallpaperBusy acompanha o processo.
//
// Atividade: nada roda antes do primeiro reload() / reloadWallpapers()
// (chamados pelas telas em opened()); só então o FileView do theme.name liga.
QtObject {
    id: root

    // ---- Entradas ----
    property string omarchyPath: ""

    // ---- Estado (API congelada) ----
    // [{slug, name, bg, fg, accent, dots: [red, green, yellow, blue, magenta, cyan], preview}]
    property var themes: []
    property string current: ""
    // Slug pedido agora: a marca do atual pula no quadro do Enter.
    property string pendingCurrent: ""
    // Um `theme set` foi pedido e ainda não confirmou.
    property bool applying: false
    readonly property string currentName: root.nameFor(root.current)
    // [{path, thumb, name, video, real}] do tema atual.
    property var wallpapers: []
    property string currentWallpaper: ""
    property string pendingWallpaper: ""

    // ---- Estado extra ----
    // A lista de temas chegou pelo menos uma vez.
    property bool themesReady: false
    // A lista de papéis do tema atual chegou (vazia = o tema não tem papéis).
    property bool wallpapersReady: false
    // Tema a que `wallpapers` pertence.
    property string wallpapersTheme: ""
    // `omarchy-theme-bg-set` rodando (a tela fecha quando ele sai).
    property bool wallpaperBusy: false

    // Um tema confirmou (theme.name mudou para o pedido).
    signal applied()

    // Harness (ILHA_DEV=1): aplicar só finge (registra no log e simula a
    // confirmação), para um Enter num teste nunca trocar o tema nem o papel
    // de parede de verdade do usuário. As leituras são as reais.
    readonly property bool dryRun: Quickshell.env("ILHA_DEV") === "1"

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: root.home + "/.local/state/omarchy/current"
    readonly property string omarchyDir: {
        if (root.omarchyPath !== "")
            return root.omarchyPath;
        const env = Quickshell.env("OMARCHY_PATH");
        return env && String(env) !== "" ? String(env) : root.home + "/.local/share/omarchy";
    }

    // ---- Ajudantes ----

    // "Tokyo Night" ou "tokyo-night" -> "tokyo-night" (o mesmo do omarchy-theme-set).
    function slugFor(name) {
        return String(name || "").replace(/<[^>]+>/g, "").trim().toLowerCase().replace(/ /g, "-");
    }

    // "tokyo-night" -> "Tokyo Night" (o mesmo sed do omarchy-theme-list).
    function nameFor(slug) {
        return String(slug || "").replace(/(^|-)([a-z])/g, (m, a, b) => a + b.toUpperCase()).replace(/-/g, " ");
    }

    function fileUrl(path) {
        if (!path)
            return "";
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }

    function isVideo(path) {
        return /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(String(path || ""));
    }

    function baseName(path) {
        const s = String(path || "");
        return s.substring(s.lastIndexOf("/") + 1);
    }

    function themeIndex(list, slug) {
        const s = String(slug || "");
        for (let i = 0; i < list.length; i++) {
            if (list[i].slug === s)
                return i;
        }
        return -1;
    }

    // Uma linha de papel é este caminho? Caminho igual, o real igual, ou o
    // mesmo nome de arquivo (o link do Omarchy aponta para a cópia do tema).
    function sameWallpaper(row, path) {
        const p = String(path || "");
        if (!row || p === "")
            return false;
        if (row.path === p || (row.real && row.real === p))
            return true;
        return root.baseName(row.path) === root.baseName(p);
    }

    // Índice do papel `path` (ou do atual) numa lista; -1 sem nenhum.
    function wallpaperIndex(list, path) {
        const want = String(path || "") !== "" ? String(path) : (root.pendingWallpaper || root.currentWallpaper);
        if (!list || want === "")
            return -1;
        // Primeiro o caminho exato; só depois o nome do arquivo.
        for (let i = 0; i < list.length; i++) {
            if (list[i].path === want || (list[i].real && list[i].real === want))
                return i;
        }
        for (let j = 0; j < list.length; j++) {
            if (root.sameWallpaper(list[j], want))
                return j;
        }
        return -1;
    }

    // ---- Comandos ----

    // Relê a lista de temas (e liga a leitura do tema atual).
    function reload() {
        priv.armed = true;
        if (themeProc.running) {
            priv.themesQueued = true;
            return;
        }
        themeProc.running = true;
    }

    // Relê os papéis do tema atual. A lista guardada do tema entra na hora.
    function reloadWallpapers() {
        priv.armed = true;
        const cached = priv.wallCache[root.current];
        if (root.current !== "" && cached && root.wallpapersTheme !== root.current) {
            root.wallpapers = cached;
            root.wallpapersTheme = root.current;
            root.wallpapersReady = true;
        }
        if (wallProc.running) {
            priv.wallsQueued = true;
            return;
        }
        wallProc.running = true;
    }

    // Aplica um tema (slug ou nome). false quando não há o que fazer (vazio ou
    // já é o atual sem nada pendente).
    function apply(name) {
        const slug = root.slugFor(name);
        if (slug === "" || slug.indexOf("/") !== -1 || slug.charAt(0) === ".")
            return false;
        if (slug === root.current && root.pendingCurrent === "")
            return false;
        root.pendingCurrent = slug;
        root.applying = true;
        applyGuard.restart();
        if (root.dryRun) {
            console.log("ilha (dev): omarchy-theme-set " + slug + " (simulado)");
            priv.dryTheme = slug;
            dryThemeTimer.restart();
            return true;
        }
        Quickshell.execDetached(["bash", "-c", "PATH=\"$1/bin:$PATH\"; exec omarchy-theme-set \"$2\"", "ilha", root.omarchyDir, slug]);
        return true;
    }

    // Aplica um papel de parede pelo caminho. Vários seguidos: vale o último.
    function applyWallpaper(path) {
        const p = String(path || "");
        if (p === "")
            return false;
        root.noteWallpaper(p);
        if (bgProc.running) {
            priv.queuedWallpaper = p;
            return true;
        }
        root.startBgSet(p);
        return true;
    }

    // Um papel escolhido por outro caminho (takeover: o script do Omarchy
    // aplica). Marca o pendente e acompanha o link por pouco tempo.
    function noteWallpaper(path) {
        const p = String(path || "");
        if (p === "")
            return;
        root.pendingWallpaper = p;
        priv.pendingWallAt = Date.now();
        priv.watchUntil = Date.now() + Motion.TIMING.WALLPAPER_CLOSE_MS + 400;
        if (!root.dryRun)
            linkWatch.restart();
    }

    function startBgSet(path) {
        if (root.dryRun) {
            console.log("ilha (dev): omarchy-theme-bg-set " + path + " (simulado)");
            priv.dryWallpaper = path;
            root.wallpaperBusy = true;
            dryWallTimer.restart();
            return;
        }
        bgProc.command = ["bash", "-c", "PATH=\"$1/bin:$PATH\"; exec omarchy-theme-bg-set \"$2\"", "ilha", root.omarchyDir, path];
        root.wallpaperBusy = true;
        bgProc.running = true;
    }

    function readCurrentWallpaper() {
        if (!linkProc.running)
            linkProc.running = true;
    }

    // ---- Leituras ----

    function noteThemeName(raw) {
        const slug = String(raw || "").trim();
        if (slug === "")
            return;
        if (root.pendingCurrent !== "" && slug !== root.pendingCurrent) {
            // Escrita velha (o tema anterior) chegando depois do Enter: não
            // pinta por cima. Na primeira leitura não há o que guardar.
            if (root.current === "")
                root.current = slug;
            return;
        }
        const wanted = root.pendingCurrent;
        root.current = slug;
        if (wanted !== "" && slug === wanted) {
            root.pendingCurrent = "";
            root.applying = false;
            applyGuard.stop();
            root.applied();
        }
    }

    function parseThemes(text) {
        const hex = v => /^#[0-9A-Fa-f]{6}$/.test(String(v || "")) ? String(v).toLowerCase() : "";
        const out = [];
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const parts = lines[i].split("\t");
            const slug = String(parts[0] || "").trim();
            if (slug === "" || slug.charAt(0) === "." || slug.indexOf("/") !== -1)
                continue;
            out.push({
                slug: slug,
                name: root.nameFor(slug),
                dots: [hex(parts[1]), hex(parts[2]), hex(parts[3]), hex(parts[4]), hex(parts[5]), hex(parts[6])],
                bg: hex(parts[7]),
                fg: hex(parts[8]),
                accent: hex(parts[9]),
                // Caminho da imagem de prévia do tema ("" = sem prévia).
                preview: parts[10] && parts[10] !== "-" && String(parts[10]).charAt(0) === "/" ? String(parts[10]) : ""
            });
        }
        if (JSON.stringify(out) !== JSON.stringify(root.themes))
            root.themes = out;
        root.themesReady = true;
    }

    function parseWallpapers(text) {
        const lines = String(text || "").split("\n");
        let slug = root.current;
        let bg = "";
        const out = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line === "")
                continue;
            const parts = line.split("\t");
            if (parts[0] === "#") {
                slug = String(parts[1] || "").trim();
                bg = String(parts[2] || "").trim();
                continue;
            }
            const path = parts[0];
            const video = root.isVideo(path);
            let thumb = String(parts[1] || "");
            // Sem miniatura: a imagem serve; um vídeo fica com o glifo.
            if (thumb === "" || thumb === path)
                thumb = video ? "" : path;
            out.push({
                path: path,
                thumb: thumb,
                name: root.baseName(path),
                video: video,
                real: String(parts[2] || "")
            });
        }
        if (bg !== "")
            root.setCurrentWallpaper(bg);
        if (slug !== "") {
            const next = Object.assign({}, priv.wallCache);
            next[slug] = out;
            priv.wallCache = next;
        }
        if (root.current === "" && slug !== "")
            root.current = slug;
        // O script lê o theme.name na hora: a lista dele é a do tema em disco.
        if (JSON.stringify(out) !== JSON.stringify(root.wallpapers))
            root.wallpapers = out;
        root.wallpapersTheme = slug;
        root.wallpapersReady = true;
    }

    function setCurrentWallpaper(path) {
        const p = String(path || "").trim();
        if (p !== "")
            root.currentWallpaper = p;
        if (root.pendingWallpaper === "")
            return;
        const same = root.baseName(root.pendingWallpaper) === root.baseName(root.currentWallpaper)
            || root.pendingWallpaper === root.currentWallpaper;
        // O link já aponta para o pedido, ou o pedido ficou velho (falhou).
        if (same || Date.now() - priv.pendingWallAt > 8000) {
            root.pendingWallpaper = "";
            linkWatch.stop();
        }
    }

    property QtObject internals: QtObject {
        id: priv
        property bool armed: false
        property bool themesQueued: false
        property bool wallsQueued: false
        property var wallCache: ({})
        property string queuedWallpaper: ""
        property real pendingWallAt: 0
        property real watchUntil: 0
        property string dryTheme: ""
        property string dryWallpaper: ""
    }

    // ---- Processos ----

    // Uma linha por tema: slug e as nove cores ("-" falta).
    readonly property string themeScript: [
        "op=\"$1\"",
        "[ -d \"$op/themes\" ] || op=\"${OMARCHY_PATH:-$HOME/.local/share/omarchy}\"",
        "user=\"$HOME/.config/omarchy/themes\"",
        "{",
        "  [ -d \"$user\" ] && find -L \"$user\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null",
        "  [ -d \"$op/themes\" ] && find -L \"$op/themes\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null",
        "} | LC_ALL=C sort -u | while IFS= read -r s; do",
        "  case \"$s\" in ''|.*) continue ;; esac",
        "  toml=''",
        "  for d in \"$user/$s\" \"$op/themes/$s\"; do",
        "    if [ -f \"$d/colors.toml\" ]; then toml=\"$d/colors.toml\"; break; fi",
        "  done",
        // A prévia, na ordem do omarchy-theme-switcher (só imagens paradas).
        "  pv=''",
        "  for d in \"$user/$s\" \"$op/themes/$s\"; do",
        "    [ -d \"$d\" ] || continue",
        "    for n in preview.png preview.jpg preview.jpeg preview.webp; do",
        "      pv=$(find -L \"$d\" -maxdepth 1 -type f -iname \"$n\" -print -quit 2>/dev/null)",
        "      [ -n \"$pv\" ] && break 2",
        "    done",
        "  done",
        "  if [ -n \"$toml\" ]; then",
        "    awk -v s=\"$s\" -v pv=\"${pv:--}\" 'BEGIN { n = split(\"red green yellow blue magenta cyan background foreground accent\", k, \" \") }",
        "      { i = index($0, \"=\"); if (i == 0) next; key = substr($0, 1, i - 1); val = substr($0, i + 1);",
        "        gsub(/[ \\t\"]/, \"\", key); gsub(/[ \\t\"]/, \"\", val);",
        "        if (!(key in c) && val ~ /^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/) c[key] = substr(val, 1, 7) }",
        "      END { line = s; for (j = 1; j <= n; j++) line = line \"\\t\" ((k[j] in c) ? c[k[j]] : \"-\"); print line \"\\t\" pv }' \"$toml\"",
        "  else",
        "    printf '%s\\t-\\t-\\t-\\t-\\t-\\t-\\t-\\t-\\t-\\t%s\\n' \"$s\" \"${pv:--}\"",
        "  fi",
        "done"
    ].join("\n")

    // Primeira linha "#<TAB>slug<TAB>papel atual"; depois imagem, miniatura e caminho real.
    readonly property string wallScript: [
        "op=\"$1\"",
        "[ -d \"$op/bin\" ] || op=\"${OMARCHY_PATH:-$HOME/.local/share/omarchy}\"",
        "PATH=\"$op/bin:$PATH\"",
        "st=\"$HOME/.local/state/omarchy/current\"",
        "slug=$(cat \"$st/theme.name\" 2>/dev/null)",
        "bg=$(readlink -f \"$st/background\" 2>/dev/null)",
        "printf '#\\t%s\\t%s\\n' \"$slug\" \"$bg\"",
        "dirs=(\"$st/theme/backgrounds\")",
        "[ -n \"$slug\" ] && dirs+=(\"$HOME/.config/omarchy/backgrounds/$slug\")",
        "omarchy-menu-images --print-rows \"${dirs[@]}\" 2>/dev/null | while IFS=$'\\t' read -r img th; do",
        "  [ -n \"$img\" ] || continue",
        "  printf '%s\\t%s\\t%s\\n' \"$img\" \"$th\" \"$(readlink -f \"$img\" 2>/dev/null)\"",
        "done"
    ].join("\n")

    property Process themeRunner: Process {
        id: themeProc
        command: ["bash", "-c", root.themeScript, "ilha", root.omarchyDir]
        stdout: StdioCollector {
            id: themeOut
            onStreamFinished: root.parseThemes(themeOut.text)
        }
        onExited: {
            if (priv.themesQueued) {
                priv.themesQueued = false;
                Qt.callLater(() => themeProc.running = true);
            }
        }
    }

    property Process wallRunner: Process {
        id: wallProc
        command: ["bash", "-c", root.wallScript, "ilha", root.omarchyDir]
        stdout: StdioCollector {
            id: wallOut
            onStreamFinished: root.parseWallpapers(wallOut.text)
        }
        onExited: {
            if (priv.wallsQueued) {
                priv.wallsQueued = false;
                Qt.callLater(() => wallProc.running = true);
            }
        }
    }

    property Process bgRunner: Process {
        id: bgProc
        onExited: {
            root.wallpaperBusy = false;
            root.readCurrentWallpaper();
            const next = priv.queuedWallpaper;
            priv.queuedWallpaper = "";
            if (next !== "")
                Qt.callLater(() => root.startBgSet(next));
        }
    }

    property Process linkRunner: Process {
        id: linkProc
        command: ["readlink", "-f", root.stateDir + "/background"]
        stdout: StdioCollector {
            id: linkOut
            onStreamFinished: root.setCurrentWallpaper(linkOut.text)
        }
    }

    // Depois de um pedido, relê o link algumas vezes até ele apontar para o
    // escolhido (no máximo WALLPAPER_CLOSE_MS + 400 ms). Não é uma sondagem
    // contínua: só roda logo depois de um Enter.
    property Timer linkTimer: Timer {
        id: linkWatch
        interval: 150
        repeat: true
        onTriggered: {
            if (root.pendingWallpaper === "" || Date.now() > priv.watchUntil) {
                linkWatch.stop();
                return;
            }
            root.readCurrentWallpaper();
        }
    }

    // Um `theme set` que nunca confirmou (falhou, tema sumiu): solta a marca.
    property Timer applyTimer: Timer {
        id: applyGuard
        interval: 20000
        onTriggered: {
            root.pendingCurrent = "";
            root.applying = false;
        }
    }

    // Só no harness: as confirmações simuladas.
    property Timer dryThemeRunner: Timer {
        id: dryThemeTimer
        interval: 500
        onTriggered: root.noteThemeName(priv.dryTheme)
    }
    property Timer dryWallRunner: Timer {
        id: dryWallTimer
        interval: 250
        onTriggered: {
            root.wallpaperBusy = false;
            root.setCurrentWallpaper(priv.dryWallpaper);
        }
    }

    property FileView nameWatch: FileView {
        id: nameFile
        path: priv.armed ? root.stateDir + "/theme.name" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: nameFile.reload()
        onLoaded: root.noteThemeName(nameFile.text())
    }
}
