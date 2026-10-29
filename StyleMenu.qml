import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Estilo (spec §3.4): como o sistema parece.
//
//   TEMA            legenda com o tema atual; galeria 4 × 2 visível (188 px),
//                   rola e abre no tema atual; setas + ↵ dentro dela
//   FUNDO           Q Próximo fundo · W Escolher fundo… · E Cores do fundo · R Todos os temas…
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

    implicitWidth: metrics.content
    implicitHeight: grid.implicitHeight

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // ---------- Contrato ----------
    readonly property string footerStatus: [root.currentTheme, root.background].filter(s => s !== "").join(" · ")
    readonly property string footerHints: strings.t("hint.style")

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (!mods && (event.key === Qt.Key_BracketLeft || event.key === Qt.Key_BracketRight)) {
            // Cada passo aplica a fonte: segurar a tecla não dispara uma rajada.
            if (!event.isAutoRepeat) {
                if (event.key === Qt.Key_BracketLeft) fontRow.prev();
                else fontRow.next();
            }
            return true;
        }
        return grid.handleKey(event);
    }
    function handleEscape() { return grid.handleEscape(); }
    function focusFirst() { gallery.forceActiveFocus(Qt.TabFocusReason); return true; }

    // Cursor de teclado na galeria (índice do tema).
    property int galleryCursor: -1

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

    onActiveChanged: {
        if (active) {
            refresh();
            root.galleryCursor = root.currentThemeIndex;
            Qt.callLater(gallery.revealCurrent);
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

    function setTheme(name) {
        if (name === root.currentTheme) return;
        root.currentTheme = name;
        root.pendingTheme = name;
        root.pendingChecks = 0;
        root.run(["omarchy", "theme", "set", name]);
    }
    function setFont(name) {
        if (name === root.currentFont) return;
        root.currentFont = name;
        root.run(["omarchy", "font", "set", name]);
    }
    function setCorners(mode) {
        if (mode === root.corners) return;
        root.corners = mode;
        root.run(["omarchy", "hyprland", "corners", mode]);
    }
    function setTransparency(mode) {
        if (mode === root.transparency) return;
        root.transparency = mode;
        root.run(["omarchy", "hyprland", "window", "transparency", mode]);
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
            "s=$(printf '%s' \"$n\" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'); p=''; " +
            "for d in \"$HOME/.config/omarchy/themes/$s\" \"$OMARCHY_PATH/themes/$s\"; do " +
            "for f in preview.png preview.jpg; do [ -z \"$p\" ] && [ -f \"$d/$f\" ] && p=\"$d/$f\"; done; done; " +
            "printf '%s\\t%s\\n' \"$n\" \"$p\"; done"]
        stdout: StdioCollector {
            id: themeListOut
            onStreamFinished: {
                const out = [];
                for (const l of root.lines(themeListOut.text)) {
                    const parts = l.split("\t");
                    out.push({ name: parts[0], preview: parts.length > 1 ? parts[1] : "" });
                }
                root.themes = out;
                root.themesLoaded = true;
                Qt.callLater(gallery.revealCurrent);
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
                if (root.pendingTheme !== "" && t !== root.pendingTheme && root.pendingChecks < 6) {
                    root.pendingChecks++;
                    if (root.active) recheck.restart();
                    return;
                }
                root.pendingTheme = "";
                if (t !== "" && t !== "Unknown") root.currentTheme = t;
                Qt.callLater(gallery.revealCurrent);
            }
        }
    }
    Process {
        id: fontListProc
        command: ["omarchy", "font", "list"]
        stdout: StdioCollector {
            id: fontListOut
            onStreamFinished: {
                root.fonts = root.lines(fontListOut.text);
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
            onStreamFinished: root.corners = cornersOut.text.trim()
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
        muted: root.muted

        // ----- Tema: legenda + galeria (20 + 188) -----
        Item {
            id: themeBlock
            width: root.metrics.content
            height: root.metrics.caption + root.metrics.captionGap + 188

            function focusItems() { return [gallery]; }

            Caption {
                text: strings.t("style.section.theme")
                status: root.pendingTheme !== "" ? strings.t("style.applying") : root.currentTheme
                statusStrong: root.pendingTheme === "" && root.currentTheme !== ""
            }

            // Item focável da galeria: setas movem o cursor, ↵ aplica.
            Item {
                id: gallery
                y: root.metrics.caption + root.metrics.captionGap
                width: root.metrics.content
                height: 188
                activeFocusOnTab: true
                Accessible.role: Accessible.List
                Accessible.name: strings.t("style.gallery")

                readonly property int columns: 4
                readonly property int thumbH: 72
                readonly property int cellH: thumbH + 18          // prévia + nome
                readonly property int pitchY: cellH + root.metrics.gap
                property bool userMoved: false

                // Galeria aberta no tema atual, sem animação.
                function revealCurrent() {
                    if (!gallery.userMoved || root.galleryCursor < 0)
                        root.galleryCursor = root.currentThemeIndex;
                    gallery.ensureVisible(root.currentThemeIndex >= 0 ? root.currentThemeIndex : 0, false);
                }
                function ensureVisible(i, animate) {
                    if (i < 0 || themeView.count === 0) return;
                    const top = Math.floor(i / gallery.columns) * gallery.pitchY;
                    const maxY = Math.max(0, themeView.contentHeight - themeView.height);
                    let y = themeView.contentY;
                    if (top < y) y = top;
                    else if (top + gallery.cellH > y + themeView.height) y = top + gallery.cellH - themeView.height;
                    y = Math.max(0, Math.min(maxY, y));
                    scrollAnim.stop();
                    if (animate && Commons.Style.duration(200) > 0) {
                        scrollAnim.to = y;
                        scrollAnim.start();
                    } else {
                        themeView.contentY = y;
                    }
                }
                // ←→ andam de um em um (passando de linha); ↑↓ de uma linha.
                function moveCursor(d) {
                    const n = root.themes.length;
                    if (n === 0) return false;
                    const from = root.galleryCursor < 0 ? Math.max(0, root.currentThemeIndex) : root.galleryCursor;
                    const to = from + d;
                    if (to < 0 || to >= n) return false;
                    root.galleryCursor = to;
                    gallery.userMoved = true;
                    gallery.ensureVisible(to, true);
                    return true;
                }
                function handleArrow(key) {
                    if (key === Qt.Key_Left) return gallery.moveCursor(root.rtl ? 1 : -1) || true;
                    if (key === Qt.Key_Right) return gallery.moveCursor(root.rtl ? -1 : 1) || true;
                    if (key === Qt.Key_Up) return gallery.moveCursor(-gallery.columns);
                    if (key === Qt.Key_Down) {
                        const n = root.themes.length;
                        const cur = root.galleryCursor < 0 ? 0 : root.galleryCursor;
                        const lastRow = Math.floor((n - 1) / gallery.columns);
                        if (Math.floor(cur / gallery.columns) >= lastRow) return false;
                        // Linha de baixo incompleta: vai para o último tema.
                        root.galleryCursor = Math.min(n - 1, cur + gallery.columns);
                        gallery.userMoved = true;
                        gallery.ensureVisible(root.galleryCursor, true);
                        return true;
                    }
                    return false;
                }
                function activate() {
                    const t = root.themes[root.galleryCursor];
                    if (!t) return false;
                    const cell = themeView.itemAtIndex(root.galleryCursor);
                    if (cell) cell.pulse();
                    root.setTheme(t.name);
                    return true;
                }

                onActiveFocusChanged: if (activeFocus && root.galleryCursor < 0) root.galleryCursor = Math.max(0, root.currentThemeIndex)

                GridView {
                    id: themeView
                    // A última coluna leva um vão de 8 px para fora (dentro do pad).
                    width: root.metrics.content + root.metrics.gap
                    height: parent.height
                    cellWidth: root.metrics.col + root.metrics.gap
                    cellHeight: gallery.pitchY
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Sem o vão depois da última linha.
                    bottomMargin: -root.metrics.gap
                    model: root.themes
                    reuseItems: true

                    NumberAnimation {
                        id: scrollAnim
                        target: themeView
                        property: "contentY"
                        duration: Commons.Style.duration(200)
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Commons.Style.easeOut
                    }

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: modelData.name === root.currentTheme
                        readonly property bool isCursor: index === root.galleryCursor && gallery.activeFocus && root.keyboardMode
                        width: root.metrics.col
                        height: gallery.cellH

                        property bool _pulsing: false
                        function pulse() { cell._pulsing = true; cellPulse.restart(); }
                        Timer { id: cellPulse; interval: Math.max(1, Commons.Style.duration(root.metrics.msPress)); onTriggered: cell._pulsing = false }

                        Item {
                            id: body
                            anchors.fill: parent
                            scale: cellTap.pressed || cell._pulsing ? root.metrics.pressScale : 1
                            Behavior on scale { NumberAnimation { duration: Commons.Style.duration(root.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut } }

                            // Prévia recortada nos cantos contínuos: imagem e máscara
                            // viram texturas e o MultiEffect recorta.
                            Item {
                                id: thumb
                                width: parent.width
                                height: gallery.thumbH

                                ContinuousRect {
                                    anchors.fill: parent
                                    radius: root.metrics.rowRadius
                                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: preview.status !== Image.Ready
                                    name: "palette"
                                    size: 20
                                    color: root.muted
                                }
                                Item {
                                    id: thumbSource
                                    anchors.fill: parent
                                    visible: false
                                    layer.enabled: preview.status === Image.Ready
                                    Image {
                                        id: preview
                                        anchors.fill: parent
                                        source: cell.modelData.preview !== "" ? "file://" + cell.modelData.preview.split("/").map(encodeURIComponent).join("/") : ""
                                        sourceSize.width: 256
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                    }
                                }
                                ContinuousRect {
                                    id: thumbMask
                                    anchors.fill: parent
                                    radius: root.metrics.rowRadius
                                    visible: false
                                    // Sempre ligada: um Shape numa camada ligada depois não repinta.
                                    layer.enabled: true
                                    color: root.fg
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    visible: preview.status === Image.Ready
                                    source: thumbSource
                                    maskEnabled: true
                                    maskSource: thumbMask
                                    maskThresholdMin: 0.5
                                    maskSpreadAtMin: 1.0
                                    opacity: preview.status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msFadeIn); easing.type: Easing.OutCubic } }
                                }
                                // Véu de hover.
                                ContinuousRect {
                                    anchors.fill: parent
                                    radius: root.metrics.rowRadius
                                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)
                                    opacity: cellHover.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                                }
                                // Tema atual: contorno em accent por dentro.
                                ContinuousRect {
                                    anchors.fill: parent
                                    radius: root.metrics.rowRadius
                                    color: "transparent"
                                    borderWidth: 2
                                    borderColor: root.accent
                                    opacity: cell.isCurrent ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                                }
                                // Selo do tema atual.
                                ContinuousRect {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    width: 18
                                    height: 18
                                    radius: height / 2
                                    color: root.accent
                                    opacity: cell.isCurrent ? 1 : 0
                                    scale: cell.isCurrent ? 1 : root.metrics.pressScale
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
                                // Cursor do teclado: anel de 2 px por fora, raio + 2.
                                ContinuousRect {
                                    anchors.fill: parent
                                    anchors.margins: -(root.metrics.ring + 1)
                                    radius: root.metrics.rowRadius + root.metrics.ring + 1
                                    color: "transparent"
                                    borderWidth: root.metrics.ring
                                    borderColor: root.accent
                                    opacity: cell.isCursor ? 1 : 0
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
                                text: cell.modelData.name
                                textFormat: Text.PlainText
                                font.pixelSize: root.metrics.tileSublabel
                                font.weight: cell.isCurrent ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                color: cell.isCurrent ? root.accent : (cell.isCursor || cellHover.hovered ? root.fg : root.muted)
                                Behavior on color { ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                            }
                        }

                        HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: cellTap
                            onTapped: {
                                root.galleryCursor = cell.index;
                                root.setTheme(cell.modelData.name);
                            }
                        }
                    }
                }

                // Indicador de rolagem, no vão à direita (dentro do pad).
                ContinuousRect {
                    visible: themeView.contentHeight > themeView.height + 1
                    x: parent.width + 6
                    y: themeView.visibleArea.yPosition * themeView.height
                    width: 3
                    height: Math.max(20, themeView.visibleArea.heightRatio * themeView.height)
                    radius: width / 2
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaPill)
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.themes.length === 0
                    text: root.themesLoaded ? strings.t("style.themesEmpty") : strings.t("style.themesLoading")
                    textFormat: Text.PlainText
                    font.pixelSize: 13
                    color: root.muted
                }
            }
        }

        // ----- Fundo: Q W E R -----
        GridRow {
            caption: strings.t("style.section.background")
            captionStatus: root.backgroundStatus
            captionStatusAlert: root.paletteFailed && !root.paletteBusy

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
                closesIsland: true
                onActivated: root.runAfterClose(["omarchy", "theme", "switcher"])
            }
        }

        // ----- Janelas e fonte: Cantos (S D F) com a legenda -----
        Item {
            id: cornersBlock
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
            variant: "segmented"
            label: strings.t("style.transparency")
            value: currentIndex >= 0 ? options[currentIndex].label : ""
            current: root.transparency
            options: [
                { value: "opaque", label: strings.t("style.transparency.opaque") },
                { value: "transparent", label: strings.t("style.transparency.transparent") },
                { value: "glassy", label: strings.t("style.transparency.glassy") }
            ]
            onPicked: value => root.setTransparency(value)
        }

        // ----- Fonte: ‹ chips › ([ ]) -----
        LabeledRow {
            id: fontRow
            variant: "chips"
            label: strings.t("style.font")
            value: root.currentFont
            current: root.currentFont
            options: root.fonts.map(f => ({ value: f, label: f, font: f }))
            onPicked: value => root.setFont(value)
        }
    }
}
