import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons as Commons
import "TileArm.js" as TileArm

// Ilha: plugin de barra (kind "bar") que substitui a barra do Omarchy por uma
// pílula só, solta do topo, que muda de forma.
//
// Em repouso é uma cápsula com a hora, a alguns pixels da borda. Com algo
// ligado, uma marca fica ao lado da hora: o ícone do aviso mais importante
// (gravando, lembrete, atualização, Não perturbe, luz noturna, manter
// acordado), o tempo da gravação em segundos e, com música, as três
// barrinhas. Tocar na marca, ainda no repouso, abre o painel dono; tocar
// no resto da cápsula abre o Tempo.
//
// Nível 1: uma faixa invisível de 3 px nos 600 px do centro da borda de
// cima, o vão de 12 px ou a própria cápsula abrem a linha de estado:
// workspaces, hora e no máximo dois avisos, sem vão. Nível 2: só com o
// ponteiro em cima da própria pílula, parado (900 ms sem andar mais de
// 3 px, medidos na cena: a pílula cresce do centro). A faixa e o vão nunca
// abrem o nível 2. O Estilo pode desligar o nível 2 (prefs.level2Dwell).
//
// Seletor: toque longo ou clique direito na cápsula (ou na linha) mostra os
// seis destinos por um instante e some. Um painel abre sozinho no lugar da
// pílula. Na primeira linha da sessão, uma dica curta lembra os dígitos.
//
// Aviso ao vivo (prefs.livePeek): um indicador que liga vira uma frase
// curta na pílula ("Gravando 0:42", "Lembrete em 15 min") que cresce e
// volta; uma notificação urgente vira uma linha no formato do NoticeView.
// Tocar abre o painel dono ou a notificação. Desligado, é a linha de
// estado por 2,6 s, como antes.
//
// Hover: a pílula mede essa linha. Painel: a largura do próprio painel + 2 × 14.
// O OSD tem a sua. O sino, quando clicado, mostra a notificação mais
// recente na pílula, numa linha. Coluna = estado ativo (+ PanelFooter só no
// modo teclado). Clicar na hora ou num indicador abre um painel e liga o
// "modo menu": repousar 150 ms noutro ícone troca de painel, descer o
// ponteiro cancela, clicar no ícone ativo volta à faixa e sair com o
// ponteiro não fecha.
//
// Roda: só troca de painel com um painel já aberto, na borda de cima dele
// (panelWheelZone). Na linha e no repouso a roda não faz nada.
//
// Monitores: uma janela por tela, sempre com ExclusionMode.Ignore e a
// máscara. Com prefs.focusedOnly, só a tela focada desenha a cápsula (e a
// que estiver mostrando painel, OSD, notificação, aviso ou seletor).
//
// Teclado (spec §4): o estado trata a tecla primeiro (handleKey); depois vêm
// 0–6 / Alt+0–6 (categorias), Ctrl+Tab / Ctrl+Shift+Tab e a cadeia do Esc
// (handleEscape do estado → fechar). keyboardMode liga ao abrir por IPC ou
// atalho e na primeira tecla; mover o ponteiro mais de 8 px desliga.
//
// Música: o painel "media" (MediaPanel) lê o player da mesma fonte dos
// indicadores (serviço omarchy.media do shell, senão MPRIS direto). Só entra
// na roda e no Ctrl+Tab quando há uma faixa; por IPC abre sempre.
//
// RTL (ar, fa, he, ur): a superfície espelha tudo (LayoutMirroring herdado).
// O que é x calculado aqui troca de lado à mão: a marca do repouso (markRow)
// fica à esquerda do relógio em LTR e à direita em RTL, com a própria
// ordem invertida (layoutDirection), e o relógio cede metade da largura
// dela para o lado oposto. O relógio, o tempo da gravação e o progresso da
// música ficam da esquerda para a direita.
//
// Contrato com o host (shell.qml do Omarchy): as propriedades injetadas,
// o estado publicado (barHidden, barSize, screenBarSizes, fontFamily,
// position, barSizeFor), os atalhos de painel (summonBarWidget e afins) e os
// alvos de IPC que a barra padrão registrava.
Item {
    id: island

    // ---- Injetado pelo host (só é preenchido se estiver declarado) ----
    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var barWidgetRegistry: null
    property var pluginRegistry: null
    property var barConfig: null

    // ---- Estado publicado para o host e para as notificações ----
    property bool barHidden: false
    // Altura de repouso informada: a faixa de ativação e a folga da pílula.
    // Precisa ser maior que zero, senão as notificações usam o tamanho padrão.
    // Em repouso a ilha fica sempre visível: uma cápsula só com o relógio,
    // solta da borda (floatGap). barSize chega até a base dessa cápsula.
    // 12 / 38 / 108: perto do vídeo (~14 / 40 / 110) sem crescer muito a
    // área reservada no topo (barSize 50).
    readonly property int floatGap: 12
    readonly property int restHeight: 38
    readonly property int restWidth: 108
    readonly property int barSize: floatGap + restHeight
    readonly property var screenBarSizes: {
        const sizes = ({})
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            sizes[screens[i].name] = island.barHidden ? 0 : island.barSize
        return sizes
    }
    // A fonte escolhida no Estilo pinta na hora. Vazio segue o alias do sistema.
    property string face: ""
    readonly property string fontFamily: face !== "" ? face : Commons.Style.fontFamily
    readonly property string position: "top"
    // Sobe quando o layout do workspace muda (Super + L ou o clique na marca).
    property int spaceModeTick: 0

    function barSizeFor(screenName) {
        const size = screenBarSizes[String(screenName || "")]
        return size !== undefined ? size : (barHidden ? 0 : barSize)
    }

    // ---- Cores do tema (o host repassa as mesmas aos estados) ----
    // A paleta de base, não a superfície da barra. As duas coincidem, mas a
    // superfície só é regravada quando o plano de fundo revela. A paleta
    // entra no instante em que o tema é escolhido.
    readonly property color fg: Commons.Color.foreground
    readonly property color bg: Commons.Color.background
    readonly property color accent: Commons.Color.accent
    readonly property color danger: Commons.Color.urgent

    // Cantos e vidro, os mesmos modos do Estilo. O clique pinta na hora;
    // o arquivo do toggle confirma, inclusive quando a troca vem de fora.
    property bool cornerSharp: false
    property bool cornerRounded: false
    property bool glassOpaque: false
    property bool glassGlassy: true
    readonly property string cornerMode: cornerSharp ? "sharp" : cornerRounded ? "rounded" : "theme"
    readonly property string glassMode: glassOpaque ? "opaque" : glassGlassy ? "glassy" : "transparent"

    // Superfície da ilha: o fundo do tema levado quase ao preto (tema escuro)
    // ou, num tema claro, um degrau na direção de fg (o texto fg continua
    // legível). No vídeo a ilha é preta chapada por cima de tudo; com o fundo
    // do tema puro ela teria a mesma cor do terminal e perderia a borda.
    readonly property real bgLum: 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
    readonly property bool lightTheme: bgLum > 0.5
    readonly property color surface: lightTheme
        ? Qt.rgba(bg.r + (fg.r - bg.r) * 0.06, bg.g + (fg.g - bg.g) * 0.06, bg.b + (fg.b - bg.b) * 0.06, 1)
        : Qt.rgba(bg.r * 0.28, bg.g * 0.28, bg.b * 0.28, 1)      // Tokyo Night -> #07080b
    // Opaco fecha. Vidro deixa passar só um fio do blur; transparente abre um
    // pouco mais e ainda fica bem acima do ignore_alpha 0.3, senão o blur abre
    // um buraco. O painel é um tico mais fechado, para o texto ficar legível.
    // Sem aro em opaco e vidro num tema escuro, como no vídeo; o transparente
    // e os temas claros guardam um fio de 1 px para a borda não sumir. Sem sombra.
    readonly property bool glassTransparent: !glassOpaque && !glassGlassy
    readonly property real alphaRest: glassOpaque ? 1 : glassGlassy ? 0.94 : 0.84
    readonly property real alphaBody: glassOpaque ? 1 : glassGlassy ? 0.92 : 0.82
    readonly property color fillRest: Qt.rgba(surface.r, surface.g, surface.b, alphaRest)
    readonly property color fillBody: Qt.rgba(surface.r, surface.g, surface.b, alphaBody)
    readonly property bool needsRim: glassTransparent || lightTheme
    readonly property int rimWidth: needsRim ? 1 : 0
    readonly property color rimRest: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    // Aro do painel aberto (quando há aro): um degrau acima do repouso.
    readonly property color rimBody: Qt.rgba(fg.r, fg.g, fg.b, 0.10)

    // Repouso e hover: sempre uma cápsula de verdade (altura / 2), menos no
    // Reto. Painel: cartão de 32 no Arredondado e num tema sem
    // arredondamento; num tema arredondado, o dobro do raio das janelas,
    // entre 16 e 32. Reto: quina viva.
    function shellRadius(h, panel) {
        if (cornerSharp)
            return 0
        if (!panel)
            return h / 2
        if (cornerRounded || Commons.Style.cornerRadius <= 0)
            return Math.min(h / 2, 32)
        return Math.min(h / 2, Math.max(16, Math.min(32, Commons.Style.cornerRadius * 2)))
    }

    function showCorners(mode) {
        cornerSharp = mode === "sharp"
        cornerRounded = mode === "rounded"
    }
    function showGlass(mode) {
        glassOpaque = mode === "opaque"
        glassGlassy = mode === "glassy"
    }
    function showFace(name) {
        face = String(name || "")
    }

    // Tema escolhido na ilha e ainda não gravado em theme.name. Enquanto
    // estiver à frente, uma gravação do tema anterior não pinta por cima.
    property string aheadSlug: ""
    property int previewToken: 0
    property int appliedToken: 0
    readonly property string home: Quickshell.env("HOME")
    readonly property string themesRoot: {
        const fromHost = island.omarchyPath
        const fromEnv = Quickshell.env("OMARCHY_PATH")
        const base = (fromHost && String(fromHost).length > 0) ? String(fromHost)
            : (fromEnv && String(fromEnv).length > 0) ? String(fromEnv)
            : "/usr/share/omarchy"
        return base + "/themes"
    }

    function slugify(name) {
        return String(name || "").toLowerCase().replace(/ /g, "-").replace(/[^a-z0-9._-]/g, "")
    }

    // Lê o colors.toml do tema (o do usuário, senão o do sistema) e aplica
    // só a paleta. O `omarchy theme set` segue no menu e cuida do resto.
    function previewTheme(name) {
        const slug = slugify(name)
        if (slug === "")
            return
        aheadSlug = slug
        previewToken += 1
        previewRead.token = previewToken
        previewRead.slug = slug
        previewRead.userFirst = true
        previewRead.command = ["cat", home + "/.config/omarchy/themes/" + slug + "/colors.toml"]
        previewRead.running = true
    }

    function settleTheme() {
        aheadSlug = ""
    }

    function noteSystemTheme(raw) {
        const slug = String(raw || "").trim()
        if (!themeNameFile.ready) {
            themeNameFile.ready = true
            return
        }
        if (aheadSlug !== "" && slug !== aheadSlug)
            return
        aheadSlug = ""
        if (slug === "")
            return
        appliedToken += 1
        const file = home + "/.local/state/omarchy/current/theme/colors.toml"
        appliedRead.token = appliedToken
        appliedRead.command = ["cat", file]
        appliedRead.running = true
    }

    // Prévia: pasta do usuário primeiro. O estoque cobre o que não foi
    // sobreposto. Um clique mais novo invalida a leitura anterior.
    Process {
        id: previewRead
        property int token: 0
        property string slug: ""
        property bool userFirst: true
        stdout: StdioCollector {
            id: previewOut
            waitForEnd: true
            onStreamFinished: {
                if (previewRead.token !== island.previewToken)
                    return
                const raw = String(previewOut.text || "")
                if (raw.indexOf("=") < 0) {
                    if (!previewRead.userFirst)
                        return
                    previewRead.userFirst = false
                    Qt.callLater(() => {
                        if (previewRead.token !== island.previewToken)
                            return
                        previewRead.command = ["cat", island.themesRoot + "/" + previewRead.slug + "/colors.toml"]
                        previewRead.running = true
                    })
                    return
                }
                Commons.Color.loadColors(raw)
            }
        }
    }

    Process {
        id: appliedRead
        property int token: 0
        stdout: StdioCollector {
            id: appliedOut
            waitForEnd: true
            onStreamFinished: {
                if (appliedRead.token !== island.appliedToken)
                    return
                const raw = String(appliedOut.text || "")
                if (raw.indexOf("=") >= 0)
                    Commons.Color.loadColors(raw)
            }
        }
    }

    FileView {
        id: themeNameFile
        property bool ready: false
        path: island.home + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: island.noteSystemTheme(text())
    }

    // Os toggles são pequenos. A leitura inicial bloqueia para a primeira
    // pintura já sair no modo certo.
    FileView {
        path: island.home + "/.local/state/omarchy/toggles/hypr/corners-sharp.lua"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: island.cornerSharp = true
        onLoadFailed: island.cornerSharp = false
    }
    FileView {
        path: island.home + "/.local/state/omarchy/toggles/hypr/corners-rounded.lua"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: island.cornerRounded = true
        onLoadFailed: island.cornerRounded = false
    }
    FileView {
        path: island.home + "/.local/state/omarchy/toggles/hypr/window-opaque.lua"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: island.glassOpaque = true
        onLoadFailed: island.glassOpaque = false
    }
    FileView {
        path: island.home + "/.local/state/omarchy/toggles/hypr/window-glassy.lua"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: island.glassGlassy = true
        onLoadFailed: island.glassGlassy = false
    }

    // Para testes fora do shell: onde fica a flag bar-off e se checa
    // atualizações (faz git fetch).
    property string hiddenFlagPath: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/bar-off"
    property bool checkUpdates: true

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    // Outro nome para repassar: dentro de Strip { strings: … } o nome
    // "strings" seria a própria propriedade da faixa.
    readonly property var translations: strings

    // Medidas da grade, repassadas aos estados (StateSlot.wire).
    property Metrics metrics: Metrics {
        corners: island.cornerMode
        glass: island.glassMode
    }

    // Os três interruptores do Estilo (bar.ilha no shell.json, gravados pela
    // API do host). Lidos ao vivo de barConfig; sem host, ficam na memória.
    property Prefs prefs: Prefs {
        shell: island.shell
        barConfig: island.barConfig
    }

    // ---- Teclado ----
    // Modo teclado: anel de foco, letras cheias e dígitos na faixa.
    property bool keyboardMode: false
    // Alt segurado mostra os dígitos da faixa.
    property bool altHeld: false
    // Último painel aberto (Super+Z → "toggle last").
    property string lastView: "control"
    // Tecla pendente de "run <estado> <tecla>": { view, event }.
    property var pendingRun: null

    // A notch "respira" (1.0 → 1.015 → 1.0) quando um indicador liga ou chega um OSD.
    signal breathe()

    // ---- Estados ----
    // Painel aberto: "" ou um destes.
    property string view: ""
    readonly property var views: ["launcher", "control", "capture", "style", "tools", "calendar", "power", "plugins", "media"]
    // Ordem da faixa: 0 = Tempo, 1–6 = Apps … Energia. Plugins e Música vêm
    // depois, só na roda (Música só com faixa).
    readonly property var categoryOrder: ["calendar", "launcher", "control", "capture", "style", "tools", "power", "plugins", "media"]
    readonly property bool rtl: Commons.I18n.rightToLeft
    // Monitor que mostra painéis, OSD e eventos (só um por vez).
    property string panelScreen: ""

    property var osdPayload: ({})
    property bool osdShown: false
    readonly property bool eventShown: eventTimer.running

    // Seletor: os seis destinos na linha, por um instante (toque longo ou
    // clique direito na cápsula). Some sozinho (pickerClose, por janela).
    property bool pickerShown: false
    // Dica da primeira linha da sessão ("0 tempo · 1 apps · roda troca").
    property bool lineHintSeen: false

    // Aviso ao vivo: uma frase curta no formato do NoticeView. Só aparece
    // enquanto o indicador seguir ligado (a notificação vale pelo tempo).
    property string peekKey: ""
    property var peekRow: null
    // Ponteiro parado no aviso (holdPeek): a contagem pausa, para o toque
    // cair nele e não na linha. Saiu, sobra uma cauda curta (peekTail).
    property bool peekHovered: false
    property bool peekTail: false
    readonly property bool peekShown: peekKey !== "" && (peekTimer.running || peekHovered)
        && (peekKey === "notifications" || indicatorSource.isOn(peekKey))
    // O texto da gravação anda sozinho: peekText lê recordingClock.
    readonly property var peekPayload: {
        const key = island.peekKey
        if (key === "")
            return ({})
        if (key === "notifications") {
            const row = island.peekRow || ({})
            const app = String(row.app || "")
            return ({ key: key, app: app, summary: String(row.summary || app), urgent: true })
        }
        return ({
            key: key,
            icon: indicatorSource.iconOf(key),
            tone: indicatorSource.toneOf(key),
            app: "",
            summary: indicatorSource.peekText(key),
            urgent: false
        })
    }

    // Atalhos de painel do Omarchy (Super+Ctrl+…) que a ilha atende.
    readonly property var widgetViews: ({
        "omarchy.audio": "control",
        "omarchy.bluetooth": "control",
        "omarchy.network": "control",
        "omarchy.clock": "calendar",
        "omarchy.power": "power",
        "omarchy.media": "media"
    })

    function focusedScreenName() {
        if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.name)
            return String(Hyprland.focusedMonitor.name)
        const screens = Quickshell.screens
        return screens.length > 0 ? String(screens[0].name) : ""
    }

    // "last" vira o último painel aberto.
    function resolveView(target) {
        const t = String(target || "")
        return t === "last" ? lastView : t
    }

    // Abre um estado num monitor (o focado, se não for dito).
    function show(target, screenName) {
        target = resolveView(target)
        if (views.indexOf(target) < 0)
            return false
        closePicker()
        endPeek()
        panelScreen = screenName && screenName !== "" ? screenName : focusedScreenName()
        view = target
        return true
    }

    // Alterna: abrir o que já está aberto fecha.
    function toggle(target, screenName) {
        target = resolveView(target)
        if (views.indexOf(target) < 0)
            return false
        if (view === target) {
            close()
            return true
        }
        return show(target, screenName)
    }

    function close() {
        view = ""
        closePicker()
    }

    // ---- Seletor ----
    // Só sem painel aberto: com painel, a borda de cima e os dígitos já trocam.
    function openPicker(screenName) {
        if (view !== "")
            return
        endPeek()
        panelScreen = screenName && String(screenName) !== "" ? String(screenName) : focusedScreenName()
        pickerShown = true
    }

    function closePicker() {
        pickerShown = false
    }

    // Clique direito: o mesmo monitor fecha; outro monitor leva o seletor.
    function togglePicker(screenName) {
        const s = screenName && String(screenName) !== "" ? String(screenName) : focusedScreenName()
        if (pickerShown && panelScreen === s)
            closePicker()
        else
            openPicker(s)
    }

    // ---- Aviso ao vivo ----
    // Sem painel, segue o monitor focado; não arranca o seletor nem a
    // notificação fixa do monitor onde estão. Com painel aberto, o indicador
    // não arma aviso: o painel já mostra o estado, e o aviso apareceria
    // depois de fechar repetindo o que a pessoa acabou de fazer.
    function showPeek(key, row) {
        if (barHidden)
            return
        key = String(key || "")
        if (view !== "" && key !== "notifications")
            return
        if (view === "" && !pickerShown && !noticeShown)
            panelScreen = focusedScreenName()
        peekKey = key
        peekRow = row || null
        peekTail = false
        peekClear.stop()
        peekTimer.restart()
    }

    // A chave fica até o fade de saída terminar (peekClear), para o texto
    // não sumir antes da pílula voltar.
    function endPeek() {
        peekHovered = false
        peekTimer.stop()
        if (peekKey !== "")
            peekClear.restart()
    }

    // Ponteiro chegou no aviso (peekHold da janela): pausa. Saiu: volta a
    // contar só a cauda. A cauda liga antes de soltar a pausa, para o aviso
    // não piscar fora no meio.
    function holdPeek(on) {
        if (on === peekHovered)
            return
        if (on) {
            peekHovered = true
            peekTimer.stop()
            return
        }
        if (peekKey !== "") {
            peekTail = true
            peekTimer.restart()
        }
        peekHovered = false
    }

    // Toque no aviso: a notificação abre fixa na pílula (como no sino); um
    // indicador abre o painel dono.
    function tapPeek(screenName) {
        const key = peekKey
        const row = peekRow
        const s = screenName && String(screenName) !== "" ? String(screenName) : focusedScreenName()
        endPeek()
        if (key === "notifications") {
            panelScreen = s
            presentNotice(row)
            return
        }
        const owner = indicatorSource.ownerOf(key)
        keyboardMode = false
        show(owner, s)
    }

    onViewChanged: {
        if (view !== "")
            lastView = view
        else
            altHeld = false
        // Nenhum confirm fica armado ao trocar de painel.
        TileArm.disarmAll()
    }

    // Clique na faixa: abre; clicar no ativo volta à faixa sozinha.
    function categoryClick(target, screenName) {
        keyboardMode = false
        if (view === target && panelScreen === screenName) {
            close()
            return
        }
        show(target, screenName)
    }

    // Dígito ou Alt+dígito: abre; o dígito do painel aberto volta à faixa
    // (que fica um instante, como num evento).
    function categoryKey(target) {
        if (view === target) {
            close()
            revealEvent()
            return
        }
        show(target, panelScreen)
    }

    // Ctrl+Tab (+1) / Ctrl+Shift+Tab (-1), na ordem da faixa, com volta.
    // A roda manda o monitor dela; o teclado continua no painel que está aberto.
    function cycle(step, screenName) {
        const n = categoryOrder.length
        const at = categoryOrder.indexOf(view)
        const from = at < 0 ? categoryOrder.indexOf(lastView) : at
        const screen = screenName !== undefined && String(screenName) !== "" ? String(screenName) : panelScreen
        // Música sem faixa fica fora da volta.
        let next = from
        for (let tries = 0; tries < n; tries++) {
            next = ((next + step) % n + n) % n
            if (categoryOrder[next] !== "media" || indicatorSource.hasMedia)
                break
        }
        show(categoryOrder[next], screen)
    }

    // "Q", "shift+Q", "⇧Q", "enter", "pgdn"… → evento sintético para handleKey.
    function parseKey(name) {
        let raw = String(name || "").trim()
        let mods = 0
        const parts = raw.split("+")
        if (parts.length > 1 && parts[parts.length - 1] !== "") {
            raw = parts.pop()
            for (const m of parts) {
                const lower = m.toLowerCase()
                if (lower === "shift") mods |= Qt.ShiftModifier
                else if (lower === "ctrl" || lower === "control") mods |= Qt.ControlModifier
                else if (lower === "alt") mods |= Qt.AltModifier
                else return null
            }
        }
        if (raw.indexOf("⇧") === 0) {
            mods |= Qt.ShiftModifier
            raw = raw.slice(1)
        }
        const named = {
            "enter": Qt.Key_Return, "return": Qt.Key_Return, "space": Qt.Key_Space,
            "esc": Qt.Key_Escape, "escape": Qt.Key_Escape, "tab": Qt.Key_Tab,
            "up": Qt.Key_Up, "down": Qt.Key_Down, "left": Qt.Key_Left, "right": Qt.Key_Right,
            "pgup": Qt.Key_PageUp, "pageup": Qt.Key_PageUp, "pgdn": Qt.Key_PageDown,
            "pagedown": Qt.Key_PageDown, "home": Qt.Key_Home, "end": Qt.Key_End
        }
        let key = named[raw.toLowerCase()]
        let text = raw === "space" ? " " : ""
        if (key === undefined) {
            if (raw.length !== 1)
                return null
            const code = raw.toUpperCase().charCodeAt(0)
            // Qt.Key_A…Z, 0…9, "-", "=", "[", "]" têm o código ASCII da tecla.
            if (code < 0x20 || code > 0x7e)
                return null
            key = code
            text = (mods & Qt.ShiftModifier) ? raw.toUpperCase() : raw.toLowerCase()
        }
        return { key: key, modifiers: mods, text: text, isAutoRepeat: false, accepted: false, synthetic: true }
    }

    // run <estado> <tecla>: abre no modo teclado e manda a tecla quando o
    // estado estiver na tela.
    function runKey(target, keyName) {
        target = resolveView(target)
        if (views.indexOf(target) < 0)
            return "unknown"
        const event = parseKey(keyName)
        if (!event)
            return "invalid-key"
        keyboardMode = true
        if (view !== target)
            show(target, "")
        pendingRun = { view: target, event: event, at: Date.now() }
        return "ok"
    }

    function showOsd(payloadJson) {
        let payload
        try {
            payload = JSON.parse(String(payloadJson || "{}"))
        } catch (e) {
            return false
        }
        if (!payload || typeof payload !== "object" || Array.isArray(payload))
            return false
        if (view === "")
            panelScreen = focusedScreenName()
        osdPayload = payload
        osdShown = true
        island.breathe()
        const parsed = parseInt(payload.duration !== undefined && String(payload.duration) !== "" ? payload.duration : "1200", 10)
        const duration = isNaN(parsed) ? 1200 : Math.max(0, parsed)
        if (duration > 0) {
            osdTimer.interval = duration
            osdTimer.restart()
        } else {
            osdTimer.stop()
        }
        return true
    }

    function closeOsd() {
        osdTimer.stop()
        osdShown = false
    }

    // Notificação compacta na própria pílula. Só abre no clique do sino.
    // O volume (OSD) continua na frente.
    property var noticePayload: ({})
    property bool noticeShown: false

    function presentNotice(row) {
        if (!row || typeof row !== "object")
            return
        const app = String(row.app || "").slice(0, 48)
        const summary = String(row.summary || "").slice(0, 140)
        if (summary === "" && app === "")
            return
        noticePayload = {
            key: String(row.key || "").slice(0, 80),
            app: app,
            summary: summary !== "" ? summary : app,
            urgent: row.urgent === true || Number(row.urgency) === 2
        }
        if (view !== "")
            close()
        endPeek()
        noticeShown = true
        breathe()
    }

    function toggleNotice(screenName) {
        if (noticeShown) {
            closeNotice()
            return
        }
        const row = indicatorSource.currentNotice
        if (!row)
            return
        panelScreen = screenName && String(screenName) !== "" ? String(screenName) : focusedScreenName()
        presentNotice(row)
    }

    function closeNotice() {
        noticeShown = false
    }

    // Revela a pílula sozinha por um instante (indicador novo, por exemplo).
    function revealEvent() {
        if (view === "")
            panelScreen = focusedScreenName()
        eventTimer.restart()
    }

    // ---- Contrato de painéis do host ----
    function summonBarWidget(pluginId) {
        const target = widgetViews[String(pluginId || "")]
        if (!target) {
            console.log("ilha: no pill state for " + pluginId)
            return false
        }
        keyboardMode = true
        return show(target, focusedScreenName())
    }

    function hideBarWidget(pluginId) {
        const target = widgetViews[String(pluginId || "")]
        if (!target)
            return false
        if (view === target)
            close()
        return true
    }

    function isBarWidgetOpen(pluginId) {
        const target = widgetViews[String(pluginId || "")]
        return !!target && view === target
    }

    // Super+Ctrl+1..9: a N-ésima entrada de cada seção, contando de 1.
    function panelWidgetIdAt(section, index) {
        const sections = {
            "center": ["omarchy.clock"],
            "right": ["omarchy.audio", "omarchy.network", "omarchy.power"]
        }
        const list = sections[String(section || "")] || []
        const item = list[Math.round(Number(index)) - 1]
        return item ? item : ""
    }

    // A ilha não tem fundo transparente/vidro para alternar.
    function cycleBackground() {
        console.log("ilha: cycleBackground is not supported")
    }

    function debugBarGeometry() {
        return JSON.stringify({
            id: "esegnorelli.ilha",
            barHidden: barHidden,
            barSize: barSize,
            screenBarSizes: screenBarSizes,
            view: view,
            lastView: lastView,
            keyboardMode: keyboardMode,
            panelScreen: panelScreen,
            osd: osdShown,
            notice: noticeShown,
            picker: pickerShown,
            peek: peekShown ? peekKey : ""
        })
    }

    Component.onCompleted: panelScreen = focusedScreenName()

    Timer {
        id: osdTimer
        interval: 1200
        onTriggered: island.osdShown = false
    }

    Timer {
        id: eventTimer
        interval: 2600
    }

    // A notificação fica um pouco mais: tem texto de fora para ler. Depois
    // do ponteiro passar por cima, só a cauda de 1 s.
    Timer {
        id: peekTimer
        interval: island.peekTail ? 1000 : island.peekKey === "notifications" ? 4000 : 2600
        onTriggered: if (!island.peekHovered) peekClear.restart()
    }

    // Depois do fade de saída, esquece a chave: o texto da gravação não
    // fica andando escondido.
    Timer {
        id: peekClear
        interval: 400
        onTriggered: {
            if (peekTimer.running || island.peekHovered)
                return
            island.peekKey = ""
            island.peekRow = null
        }
    }

    // ---- Indicadores: uma fonte só, espelhada em cada monitor ----
    // (repassada por este nome: em Strip { indicatorSource: … } o nome
    // "indicatorSource" seria a propriedade da própria faixa)
    readonly property var sharedIndicators: indicatorSource
    Indicators {
        id: indicatorSource
        visible: false
        shell: island.shell
        fg: island.fg
        accent: island.accent
        danger: island.danger
        muted: Commons.Color.muted
        checkUpdates: island.checkUpdates
        // Indicador novo: a frase curta (aviso ao vivo) ou, com ele
        // desligado, a linha de estado por um instante. Notificação comum só
        // respira; a urgente chega por urgentArrived.
        onBecameActive: what => {
            if (what !== "notifications") {
                if (island.prefs.livePeek)
                    island.showPeek(what, null)
                else
                    island.revealEvent()
            }
            island.breathe()
        }
        onUrgentArrived: row => {
            if (!island.prefs.livePeek)
                return
            island.showPeek("notifications", row)
            island.breathe()
        }
        onCurrentNoticeChanged: {
            if (indicatorSource.currentNotice)
                return
            if (island.noticeShown)
                island.closeNotice()
            if (island.peekKey === "notifications")
                island.endPeek()
        }
        onNoticeRequested: island.toggleNotice("")
    }

    // ---- Barra escondida (omarchy toggle bar): flag bar-off ----
    Process {
        id: hiddenProbe
        running: true
        command: ["sh", "-c", "if [ -f \"$1\" ]; then echo yes; else echo no; fi", "sh", island.hiddenFlagPath]
        stdout: SplitParser {
            onRead: line => island.barHidden = String(line).trim() === "yes"
        }
    }

    // A FileView não vigia arquivo que ainda não existe; vigia a pasta.
    FileView {
        path: island.hiddenFlagPath.replace(/\/[^\/]*$/, "")
        watchChanges: true
        printErrors: false
        onFileChanged: hiddenProbe.running = true
    }

    // ---- IPC: os alvos que a barra padrão registrava ----
    Commons.ShellIpc {
        target: "omarchy.bar"

        function syncHidden(): void {
            hiddenProbe.running = true
        }
    }

    Commons.ShellIpc {
        target: "omarchy.indicators"

        function refresh(): void {
            indicatorSource.refresh()
        }
    }

    Commons.ShellIpc {
        target: "omarchy.system-update"

        function refresh(): void {
            indicatorSource.refreshUpdates()
        }

        function clear(): void {
            indicatorSource.clearUpdates()
        }
    }

    Commons.ShellIpc {
        target: "omarchy.workspaces"

        function refresh(): void {
            Hyprland.refreshWorkspaces()
            island.spaceModeTick++
        }
    }

    Commons.ShellIpc {
        target: "omarchy.clock"

        function refresh(): void {
            clock.enabled = false
            clock.enabled = true
        }

        function open(): void { island.keyboardMode = true; island.show("calendar", "") }
        function close(): void { if (island.view === "calendar") island.close() }
        function show(): void { island.keyboardMode = true; island.show("calendar", "") }
        function hide(): void { if (island.view === "calendar") island.close() }
        function toggle(): void { island.keyboardMode = true; island.toggle("calendar", "") }
    }

    // Alvo próprio: omarchy-shell ilha open <estado|last> | toggle <estado|last>
    // | run <estado> <tecla> | close | osd <json> | state
    Commons.ShellIpc {
        target: "ilha"

        // Como antes: abrir o que já está aberto fecha.
        function open(target: string): string {
            island.keyboardMode = true
            return island.toggle(String(target), "") ? "ok" : "unknown"
        }

        function toggle(target: string): string {
            island.keyboardMode = true
            return island.toggle(String(target), "") ? "ok" : "unknown"
        }

        // Abre o painel no modo teclado e manda a tecla: ilha run capture Q
        function run(target: string, key: string): string {
            return island.runKey(String(target), String(key))
        }

        function close(): string {
            island.close()
            return "ok"
        }

        function osd(payloadJson: string): string {
            return island.showOsd(payloadJson) ? "ok" : "invalid"
        }

        function closeOsd(): string {
            island.closeOsd()
            return "ok"
        }

        function state(): string {
            return JSON.stringify({ view: island.view, lastView: island.lastView, keyboard: island.keyboardMode, osd: island.osdShown, hidden: island.barHidden, screen: island.panelScreen })
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }


    // ---- Uma janela por monitor ----
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            readonly property string screenName: String(modelData.name)
            readonly property bool isTarget: island.panelScreen === screenName
            readonly property Metrics metrics: island.metrics

            anchors.top: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "omarchy-bar"
            // OnDemand: com Exclusive o compositor derruba o HyprlandFocusGrab.
            WlrLayershell.keyboardFocus: win.isTarget && island.view !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            surfaceFormat.opaque: false

            // Largura da tela: o Estilo estica os carrosséis de ponta a ponta.
            // A máscara limita o mouse ao que está visível.
            implicitWidth: modelData.width
            implicitHeight: Math.min(modelData.height, 820)

            // ---- O que esta janela mostra ----
            // Só no monitor focado (Estilo): as outras telas não desenham a
            // cápsula, a não ser a que estiver mostrando algo agora.
            readonly property bool isFocusedScreen: !!Hyprland.focusedMonitor
                && String(Hyprland.focusedMonitor.name) === screenName
            readonly property bool drawsPill: !island.prefs.focusedOnly || isFocusedScreen
                || (isTarget && (island.view !== "" || island.osdShown || island.noticeShown
                    || island.peekShown || island.pickerShown || island.eventShown))
            readonly property bool hoverAllowed: !island.barHidden && drawsPill
            readonly property bool hovered: hoverAllowed && (surfaceHover.hovered || closeDelay.running)

            // Ponteiro na marca do repouso: a linha não abre, para o toque
            // cair na marca (abre o painel dono). Sai da marca, a linha abre.
            property bool markLatch: false
            readonly property bool markHold: markLatch && !stripLatched
            // A marca só segura enquanto está de fato na tela e tocável. Sumiu
            // (linha, painel, aviso), a trava cai na hora: um HoverHandler
            // escondido pode não avisar a saída e a linha ficaria presa.
            readonly property bool markLive: markVisible && !stripOn && restClock.visible
            onMarkLiveChanged: if (!markLive) markLatch = false
            // Um aviso que entrou com o ponteiro fora segura a pílula quando o
            // ponteiro chega, para o toque cair nele. Ponteiro já em cima: a
            // linha continua na frente.
            property bool peekLatch: false
            readonly property bool peekHold: peekLatch && isTarget && island.peekShown
            // Com o ponteiro em cima do aviso a contagem pausa (holdPeek):
            // sem isso o aviso acabava sob o ponteiro e a linha tomava o lugar.
            readonly property bool peekPointed: peekHold && surfaceHover.hovered
            onPeekPointedChanged: island.holdPeek(peekPointed)
            Component.onDestruction: if (peekPointed) island.holdPeek(false)

            // Com painel aberto (modo menu) o ponteiro sair não fecha: o modo
            // segue a view; só o modo hover depende do ponteiro.
            readonly property string mode: isTarget && island.view !== "" ? island.view
                : isTarget && island.osdShown ? "osd"
                : isTarget && island.noticeShown ? "notice"
                : isTarget && island.pickerShown ? "picker"
                : hovered && !markHold && !peekHold ? "hover"
                : isTarget && island.peekShown ? "peek"
                : isTarget && island.eventShown ? "hover"
                : "rest"
            readonly property bool revealed: mode !== "rest"
            // Marca do repouso: os estados ligados e a música (notificação fica no sino).
            readonly property bool markVisible: hoverAllowed && indicatorSource.restMark
            // Partes da marca. Condições explícitas: o "visible" lido de um item
            // é o efetivo e cai junto com o relógio do repouso escondido.
            readonly property bool markIconOn: indicatorSource.restKey !== ""
            readonly property bool recTimeOn: indicatorSource.restKey === "recording" && indicatorSource.recordingClock !== ""
            readonly property bool markBarsOn: indicatorSource.restBars
            // Com o tempo da gravação, a marca se afasta um pouco mais do relógio.
            readonly property int markGap: recTimeOn ? 8 : 6
            // A pílula em repouso cresce o tamanho da marca, para o par
            // marca + relógio continuar no centro.
            readonly property real restPillWidth: island.restWidth + (markVisible ? markRow.width + markGap : 0)

            // Hover nível 2: 900 ms com o ponteiro parado em cima da própria
            // pílula (a faixa de 3 px e o vão só abrem o nível 1). Andar mais
            // de 3 px recomeça a conta. Saiu do hover, volta ao nível 1.
            property bool expanded: false
            property point dwellAnchor: Qt.point(-1, -1)
            Timer {
                id: level2Timer
                interval: 900
                running: island.prefs.level2Dwell && win.mode === "hover" && win.stripOn
                    && pillHover.hovered && !win.expanded
                onTriggered: win.expanded = true
            }

            // Seletor: some sozinho. Depois que o ponteiro passou nele, sair
            // fecha rápido; sem ponteiro (toque), fica um pouco mais.
            property bool pickerTouched: false
            readonly property bool pickerHovered: mode === "picker" && hovered
            onPickerHoveredChanged: if (pickerHovered) pickerTouched = true
            Timer {
                id: pickerClose
                interval: win.pickerTouched ? 700 : 2600
                running: win.mode === "picker" && !win.hovered
                onTriggered: island.closePicker()
            }

            // Dica da primeira linha: uma vez por sessão, quando o ponteiro
            // abre a linha (não um evento).
            readonly property bool hintArm: stripOn && mode === "hover" && surfaceHover.hovered && !island.lineHintSeen
            onHintArmChanged: {
                if (!hintArm)
                    return
                island.lineHintSeen = true
                hintTimer.restart()
            }
            Timer {
                id: hintTimer
                interval: 3000
            }
            readonly property bool hintOn: hintTimer.running && stripOn && mode === "hover"

            // Dica da marca: o nome curto do aviso, com o ponteiro parado nela.
            property bool markTipReady: false
            onMarkHoldChanged: if (!markHold) markTipReady = false
            Timer {
                interval: win.metrics.msTooltip
                running: win.markHold && win.markTipText !== "" && !win.markTipReady
                onTriggered: win.markTipReady = true
            }
            readonly property string markTipText: {
                switch (indicatorSource.restKey) {
                case "recording": return strings.t("indicators.face.recording", "Recording")
                case "reminders": return strings.t("indicators.face.reminders", "Reminder")
                case "updates": return strings.t("indicators.face.updates", "Update")
                case "dnd": return strings.t("indicators.face.dnd", "Quiet")
                case "nightlight": return strings.t("indicators.face.nightlight", "Night")
                case "stayAwake": return strings.t("indicators.face.stayAwake", "Awake")
                default: return ""
                }
            }
            readonly property bool markTipOn: markHold && markTipReady && markTipText !== ""

            // Toque no repouso: nas barrinhas abre a Mídia, na marca o painel
            // dono, no resto da cápsula o Tempo. Coordenadas da pílula; a
            // marca ganha 4 px de folga e a altura toda.
            function restTarget(px) {
                if (markVisible) {
                    const m = markRow.mapToItem(pill, 0, 0)
                    if (px >= m.x - 4 && px <= m.x + markRow.width + 4) {
                        if (markBarsOn) {
                            if (!markIconOn)
                                return "media"
                            // As barras ficam do lado do relógio: à direita da
                            // marca em LTR, à esquerda em RTL.
                            const b = markBars.mapToItem(pill, 0, 0)
                            const split = island.rtl ? b.x + markBars.width + markRow.spacing / 2
                                : b.x - markRow.spacing / 2
                            if (island.rtl ? px <= split : px >= split)
                                return "media"
                        }
                        const owner = indicatorSource.restOwnerView
                        return owner !== "" ? owner : "calendar"
                    }
                }
                return "calendar"
            }

            // Estado (painel ou OSD) na tela; nulo em hover e repouso.
            readonly property Item modeItem: {
                switch (mode) {
                case "launcher": return launcherSlot
                case "control": return controlSlot
                case "capture": return captureSlot
                case "style": return styleSlot
                case "tools": return toolsSlot
                case "plugins": return pluginsSlot
                case "calendar": return calendarSlot
                case "power": return powerSlot
                case "media": return mediaSlot
                case "osd": return osdSlot
                case "notice": return noticeSlot
                case "peek": return peekSlot
                default: return null
                }
            }
            readonly property bool faceMode: mode === "osd" || mode === "notice" || mode === "peek"
            readonly property bool isPanel: island.views.indexOf(mode) >= 0
            // A linha só existe no hover e no seletor. O painel é o cartão
            // inteiro, sem linha em cima; a roda na borda de cima
            // (panelWheelZone) ainda anda os painéis sem passar por cima das
            // listas de dentro.
            readonly property bool lineMode: mode === "hover" || mode === "picker"
            readonly property bool hasStrip: lineMode
            readonly property int contentTop: metrics.pad
            readonly property real targetWidth: mode === "rest" ? 12
                : faceMode ? (modeItem ? modeItem.implicitWidth + 32 : 12)
                : lineMode ? Math.max(64, strip.implicitWidth)
                : modeItem && modeItem.implicitWidth > 0 ? modeItem.implicitWidth + 2 * metrics.pad
                : metrics.width
            // Rodapé só no modo teclado (painel aberto ou guiado pelo teclado) e
            // só se o estado publicar algo. No ponteiro o painel fecha com o
            // mesmo respiro de cima, como no vídeo.
            readonly property bool footerOn: isPanel && island.keyboardMode && footerSlot !== null
                && (footerSlot.footerHints !== "" || footerSlot.footerStatus !== "")
            // Hover: a cápsula do elemento da vez. Painel: o cartão, sem a faixa.
            readonly property real targetHeight: mode === "rest" ? 12
                : faceMode ? (modeItem ? modeItem.implicitHeight + 16 : 12)
                : lineMode ? strip.implicitHeight
                : Math.min(contentTop + (modeItem ? modeItem.implicitHeight : 0) + (footerOn ? metrics.gap + metrics.footer + metrics.padBottom : metrics.pad), win.height - 16)

            // ---- Coreografia ----
            // 0: repouso (sumida ou bolinha); 1: bolinha de 12 px no lugar;
            // 2: esticada no estado atual.
            property int phase: 0
            property bool contentLatched: false
            property string pendingStep: ""
            readonly property bool animate: Commons.Style.duration(1) > 0
            readonly property bool shrinking: phase < 2 || !revealed
            readonly property bool contentOn: phase === 2 && revealed && contentLatched
            // A faixa aparece quando a pílula já chegou perto do tamanho do hover.
            // A altura do hover é a da linha (46, ou 64 no nível 2).
            // Depois de entrar, a linha fica: o nível 2 cresce a pílula de novo
            // e a linha faz a própria troca, sem o relógio do repouso voltar.
            readonly property bool stripReady: phase === 2 && revealed && hasStrip
                && pill.width >= targetWidth * 0.8 && pill.height >= targetHeight * 0.8
            property bool stripLatched: false
            onStripReadyChanged: if (stripReady) stripLatched = true
            readonly property bool stripOn: phase === 2 && revealed && hasStrip && (stripReady || stripLatched)

            function checkLatch() {
                if (phase === 2 && revealed && pill.width >= targetWidth * 0.8 && pill.height >= targetHeight * 0.8)
                    contentLatched = true
            }

            function step(name, ms) {
                pendingStep = name
                stepTimer.interval = Commons.Style.duration(ms)
                stepTimer.restart()
            }

            // A cápsula do relógio se estica direto até o estado. Adiado: o
            // ponteiro que entra direto na marca liga e desliga o hover no
            // mesmo evento, e a pílula não chega a se mexer.
            function growNow() {
                if (!revealed)
                    return
                phase = 2
                Qt.callLater(checkLatch)
            }

            onRevealedChanged: {
                stepTimer.stop()
                if (revealed) {
                    Qt.callLater(growNow)
                } else {
                    // Conteúdo some primeiro, depois encolhe de volta ao relógio.
                    contentLatched = false
                    stripLatched = false
                    if (phase === 2)
                        step("shrink", 120)
                    else
                        step("rise", 0)
                }
            }

            onModeChanged: {
                // Entre o hover e o seletor a linha fica (só troca o conteúdo);
                // o nível 2 não sobrevive ao seletor.
                if (mode !== "hover")
                    expanded = false
                if (!lineMode)
                    stripLatched = false
                if (mode !== "picker")
                    pickerTouched = false
                contentLatched = false
                Qt.callLater(checkLatch)
            }
            onTargetWidthChanged: Qt.callLater(checkLatch)
            onTargetHeightChanged: Qt.callLater(checkLatch)

            // O rodapé mostra o estado que está de fato na tela (não troca de
            // texto antes do conteúdo novo entrar).
            property Item footerSlot: null
            onContentOnChanged: {
                if (!contentOn)
                    return
                if (isPanel)
                    footerSlot = modeItem
                // Depois que o slot reavaliar "enabled" (senão o tile Q ainda
                // não aceita foco).
                Qt.callLater(focusState)
            }

            Timer {
                id: stepTimer
                onTriggered: {
                    const name = win.pendingStep
                    win.pendingStep = ""
                    if (name === "expand") {
                        win.phase = 2
                        Qt.callLater(win.checkLatch)
                    } else if (name === "shrink") {
                        win.phase = 0
                    } else if (name === "rise") {
                        win.phase = 0
                    }
                }
            }

            // Folga antes de esconder, para o mouse poder voltar.
            Timer {
                id: closeDelay
                interval: 300
            }

            // ---- Respiro: 1.0 → 1.015 → 1.0 em ~260 ms, sempre desacelerando ----
            property real breath: 1

            SequentialAnimation {
                id: breathAnim
                NumberAnimation {
                    target: win; property: "breath"; to: win.metrics.breathScale
                    duration: Commons.Style.duration(Math.round(win.metrics.msBreath * 0.4))
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: win; property: "breath"; to: 1
                    duration: Commons.Style.duration(Math.round(win.metrics.msBreath * 0.6))
                    easing.type: Easing.OutCubic
                }
            }

            Connections {
                target: island
                function onBreathe() {
                    if (win.animate && (win.revealed || win.markVisible))
                        breathAnim.restart()
                }
                // O aviso que começa com o ponteiro fora desta tela segura a
                // pílula quando ele chegar (peekHold).
                function onPeekShownChanged() {
                    win.peekLatch = island.peekShown && !surfaceHover.hovered
                }
                // Modo teclado novo: a próxima posição do ponteiro vira a âncora.
                function onKeyboardModeChanged() { win.kbAnchored = false }
            }

            // ---- Teclado ----
            property point kbAnchor: Qt.point(0, 0)
            property bool kbAnchored: false

            function currentState() {
                return isPanel && modeItem && modeItem.item ? modeItem.item : null
            }

            // Ao entrar um painel: foco no item Q (focusFirst) ou no estado.
            // O lançador foca o próprio campo; um campo já focado não é roubado.
            function focusState() {
                if (!isTarget || !isPanel || mode === "launcher")
                    return
                const state = currentState()
                if (!state) {
                    keys.forceActiveFocus()
                    return
                }
                let focused = keys.Window.activeFocusItem
                while (focused && focused !== state)
                    focused = focused.parent
                if (focused)
                    return
                state.forceActiveFocus()
                if (typeof state.focusFirst === "function")
                    state.focusFirst()
            }

            // Tecla vinda da superfície (ou sintetizada por "run").
            function dispatchKey(event) {
                const k = event.key
                if (k === Qt.Key_Alt || k === Qt.Key_AltGr) {
                    island.altHeld = true
                    return false
                }
                if (k === Qt.Key_Shift || k === Qt.Key_Control || k === Qt.Key_Meta
                        || k === Qt.Key_Super_L || k === Qt.Key_Super_R)
                    return false
                island.keyboardMode = true
                const state = currentState()
                if (state && typeof state.handleKey === "function" && state.handleKey(event))
                    return true
                return globalKey(event)
            }

            function globalKey(event) {
                const k = event.key
                const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)
                if (k >= Qt.Key_0 && k <= Qt.Key_6 && (mods === 0 || mods === Qt.AltModifier)) {
                    if (!event.isAutoRepeat)
                        island.categoryKey(island.categoryOrder[k - Qt.Key_0])
                    return true
                }
                if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && (mods & Qt.ControlModifier)) {
                    island.cycle(k === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1)
                    return true
                }
                if (k === Qt.Key_Escape) {
                    // Cadeia: desarmar → limpar a busca (o estado decide) → fechar.
                    const state = currentState()
                    if (state && typeof state.handleEscape === "function" && state.handleEscape())
                        return true
                    island.close()
                    return true
                }
                return false
            }

            // "run <estado> <tecla>": espera o estado entrar e manda a tecla.
            function tryRun() {
                const p = island.pendingRun
                if (!p)
                    return
                if (Date.now() - p.at > 3000) {
                    island.pendingRun = null
                    return
                }
                const slot = win.modeItem
                if (win.mode !== p.view || !slot || !slot.item || !slot.shown)
                    return
                island.pendingRun = null
                win.focusState()
                win.dispatchKey(p.event)
            }

            Timer {
                interval: 40
                repeat: true
                running: win.isTarget && island.pendingRun !== null
                onTriggered: win.tryRun()
            }

            // ---- Entrada: faixa de ativação + a pílula ----
            // A faixa de 3 px (e o vão de 12 px até a cápsula) só abrem o
            // nível 1. O nível 2 espera o ponteiro parado na própria pílula.
            readonly property int stripWidth: 600
            readonly property int stripHeight: 3
            // A área de entrada segue o tamanho final do estado, não a pílula
            // animada: trocar a máscara a cada quadro faz o compositor mandar
            // saída/entrada do ponteiro e o hover piscar. A altura inclui o
            // vão até a borda, senão o ponteiro cai no wallpaper no meio do caminho.
            // No hover a máscara fica na largura do maior elemento, senão a
            // pílula encolhe e o ponteiro cai no wallpaper no meio da troca.
            readonly property int inputWidth: revealed
                ? Math.ceil(lineMode ? Math.max(targetWidth, strip.hoverSpan) : targetWidth)
                : hoverAllowed ? Math.ceil(restPillWidth) : 0
            readonly property int inputHeight: revealed ? Math.ceil(island.floatGap + targetHeight) : hoverAllowed ? island.floatGap + island.restHeight : 0

            mask: Region {
                Region {
                    x: Math.round((win.width - win.stripWidth) / 2)
                    y: 0
                    width: win.hoverAllowed ? win.stripWidth : 0
                    height: win.hoverAllowed ? win.stripHeight : 0
                }
                Region {
                    x: Math.floor((win.width - win.inputWidth) / 2)
                    y: 0
                    width: win.inputWidth
                    height: win.inputHeight
                }
            }

            // Clicar fora fecha o painel.
            HyprlandFocusGrab {
                windows: [win]
                active: win.isTarget && island.view !== ""
                onCleared: island.close()
            }

            Item {
                id: surface
                anchors.fill: parent
                // RTL: a ilha inteira espelha (âncoras, Row, alinhamento do texto).
                // Os x calculados não espelham; cada um decide o lado (ver o
                // ponto do repouso e o OsdView), e o que deve ficar LTR desliga
                // o espelho no próprio item.
                LayoutMirroring.enabled: island.rtl
                LayoutMirroring.childrenInherit: true

                HoverHandler {
                    id: surfaceHover
                    // Sair pela marca (markHold) não liga a folga: a linha não
                    // pisca no caminho de volta ao repouso.
                    onHoveredChanged: if (!hovered && !win.markHold) closeDelay.restart()
                    // Mover o ponteiro mais de 8 px sai do modo teclado.
                    onPointChanged: {
                        if (!island.keyboardMode || !win.isTarget || !hovered)
                            return
                        const p = point.position
                        if (!win.kbAnchored) {
                            win.kbAnchor = Qt.point(p.x, p.y)
                            win.kbAnchored = true
                            return
                        }
                        if (Math.hypot(p.x - win.kbAnchor.x, p.y - win.kbAnchor.y) > win.metrics.pointerModeThreshold)
                            island.keyboardMode = false
                    }
                }

                // Tratador central: fica na superfície, ancestral de todos os
                // estados, então recebe toda tecla que o item focado não aceitou.
                Keys.onPressed: event => {
                    if (win.dispatchKey(event))
                        event.accepted = true
                }
                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr)
                        island.altHeld = false
                }

                // Alt+0…6 e Ctrl+Tab valem até dentro do campo do lançador
                // (onde os dígitos digitam): atalhos passam antes do foco.
                Shortcut { sequence: "Alt+0"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(0) }
                Shortcut { sequence: "Alt+1"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(1) }
                Shortcut { sequence: "Alt+2"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(2) }
                Shortcut { sequence: "Alt+3"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(3) }
                Shortcut { sequence: "Alt+4"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(4) }
                Shortcut { sequence: "Alt+5"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(5) }
                Shortcut { sequence: "Alt+6"; enabled: win.isTarget && island.view !== ""; onActivated: win.shortcutCategory(6) }
                Shortcut {
                    sequence: "Ctrl+Tab"
                    enabled: win.isTarget && island.view !== ""
                    onActivated: { island.keyboardMode = true; island.cycle(1) }
                }
                Shortcut {
                    sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]
                    enabled: win.isTarget && island.view !== ""
                    onActivated: { island.keyboardMode = true; island.cycle(-1) }
                }

                // Foco de reserva quando o estado não tem item carregado.
                Item {
                    id: keys
                    focus: true
                }

                Item {
                    id: pill

                    // Em repouso: cápsula só com o relógio (e a marquinha).
                    readonly property bool atRest: win.phase !== 2
                    readonly property bool asDot: false

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: win.phase === 2 ? win.targetWidth : win.restPillWidth
                    height: win.phase === 2 ? win.targetHeight : island.restHeight
                    // Solta da borda. O vão entra na máscara para o hover não piscar.
                    y: island.floatGap
                    opacity: win.hoverAllowed ? 1 : 0
                    clip: true
                    // Respiro preso à borda de cima: o centro (e o relógio) não sai do lugar.
                    transformOrigin: Item.Top
                    scale: win.breath

                    onWidthChanged: win.checkLatch()
                    onHeightChanged: win.checkLatch()

                    // Nível 2: o ponteiro parado em cima da pílula. A posição
                    // é a da cena: a pílula cresce do centro e a posição local
                    // andaria com um ponteiro parado.
                    HoverHandler {
                        id: pillHover
                        onHoveredChanged: win.dwellAnchor = Qt.point(-1, -1)
                        onPointChanged: {
                            if (!hovered)
                                return
                            const p = point.scenePosition
                            const a = win.dwellAnchor
                            if (a.x >= 0 && Math.hypot(p.x - a.x, p.y - a.y) <= 3)
                                return
                            win.dwellAnchor = Qt.point(p.x, p.y)
                            if (level2Timer.running)
                                level2Timer.restart()
                        }
                    }

                    // Morph: 200 ms crescendo, 160 ms encolhendo, sempre desacelerando.
                    Behavior on width {
                        enabled: win.animate
                        NumberAnimation {
                            duration: Commons.Style.duration(win.shrinking ? 160 : 200)
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Commons.Style.easeOut
                        }
                    }

                    Behavior on height {
                        enabled: win.animate
                        NumberAnimation {
                            duration: Commons.Style.duration(win.shrinking ? 160 : 200)
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Commons.Style.easeOut
                        }
                    }

                    Behavior on y {
                        NumberAnimation {
                            duration: Commons.Style.duration(win.phase === 0 ? 100 : 140)
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Commons.Style.duration(win.phase === 0 ? 100 : 140)
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Cápsula enquanto é baixa; cartão de canto contínuo quando abre um painel.
                    // Superfície quase preta por cima do blur; aro só no transparente e no tema claro.
                    ContinuousRect {
                        anchors.fill: parent
                        radius: island.shellRadius(height, win.isPanel)
                        color: win.isPanel ? island.fillBody : island.fillRest
                        borderWidth: win.isPanel ? (island.needsRim ? 1 : 0) : island.rimWidth
                        borderColor: win.isPanel ? island.rimBody : island.rimRest

                        Behavior on radius {
                            NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                        }
                        Behavior on borderColor {
                            ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                        }
                    }

                    // ---- Repouso: relógio compacto + marca do indicador ----
                    // Fica no centro da pílula (também na vertical) e só some
                    // quando o relógio da linha já entrou no mesmo lugar: a
                    // pílula nunca fica vazia no meio do morph.
                    Item {
                        id: restClock
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.round((parent.height - height) / 2)
                        width: parent.width
                        height: island.restHeight
                        opacity: (!win.revealed && pill.atRest) || (win.lineMode && !win.stripOn) ? 1 : 0
                        visible: opacity > 0
                        // Posições calculadas à mão (o lado da marca segue island.rtl):
                        // o espelho automático fica desligado para não virar duas vezes.
                        LayoutMirroring.enabled: false
                        LayoutMirroring.childrenInherit: true
                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(pill.atRest ? 160 : 120); easing.type: Easing.OutCubic }
                        }

                        Text {
                            id: restClockText
                            anchors.centerIn: parent
                            // Com a marca, o par marca + relógio é que fica centrado:
                            // o relógio cede metade da marca (e do vão) para o outro
                            // lado. Em RTL a marca vai para a direita e o relógio cede
                            // para a esquerda.
                            anchors.horizontalCenterOffset: win.markVisible && !win.revealed
                                ? (island.rtl ? -1 : 1) * (markRow.width + win.markGap) / 2 : 0
                            text: Qt.locale(Commons.I18n.formatLocale).toString(clock.date, "HH:mm")
                            Accessible.role: Accessible.Button
                            Accessible.name: strings.t("island.time", "Time")
                            textFormat: Text.PlainText
                            font.family: island.fontFamily
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            font.features: ({ "tnum": 1 })
                            color: island.fg

                            Behavior on anchors.horizontalCenterOffset {
                                NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                            }
                        }

                        // Marca do repouso: o ícone do aviso mais importante na cor
                        // dele, o tempo da gravação (segundos, só gravando) e, com
                        // música tocando, as três barrinhas ao lado.
                        // x calculado: do lado de fora do relógio, à esquerda (à
                        // direita em RTL). Em RTL a ordem também vira, e as barras
                        // continuam encostadas no relógio.
                        Row {
                            id: markRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            layoutDirection: island.rtl ? Qt.RightToLeft : Qt.LeftToRight
                            x: island.rtl ? restClockText.x + restClockText.width + win.markGap
                                : restClockText.x - win.markGap - width
                            opacity: win.markVisible ? 1 : 0
                            Accessible.role: Accessible.Button
                            Accessible.name: win.markTipText !== "" ? win.markTipText : indicatorSource.mediaTitle
                            Behavior on opacity {
                                NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                            }

                            Icon {
                                id: markIcon
                                anchors.verticalCenter: parent.verticalCenter
                                visible: win.markIconOn
                                width: 16
                                height: 16
                                name: indicatorSource.restIcon
                                size: 14
                                filled: true
                                color: indicatorSource.restTone
                            }

                            Text {
                                id: recTime
                                anchors.verticalCenter: parent.verticalCenter
                                visible: win.recTimeOn
                                text: indicatorSource.recordingClock
                                textFormat: Text.PlainText
                                // Dígitos ASCII, sempre da esquerda para a direita.
                                LayoutMirroring.enabled: false
                                horizontalAlignment: Text.AlignLeft
                                font.family: island.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                                color: island.danger
                            }

                            Row {
                                id: markBars
                                anchors.verticalCenter: parent.verticalCenter
                                visible: win.markBarsOn
                                height: 10
                                spacing: 1
                                LayoutMirroring.enabled: false

                                Repeater {
                                    model: [6, 10, 7]

                                    Rectangle {
                                        required property int modelData
                                        anchors.bottom: parent.bottom
                                        width: 2
                                        height: modelData
                                        radius: 1
                                        color: island.accent
                                    }
                                }
                            }
                        }

                        // Alvo da marca, ainda no repouso: 4 px de folga e a altura
                        // toda da cápsula. Com o ponteiro aqui a linha não abre
                        // (markHold) e o toque da pílula (restPress) abre o dono.
                        Item {
                            id: markHit
                            x: markRow.x - 4
                            y: 0
                            width: markRow.width + 8
                            height: parent.height
                            enabled: win.markLive

                            HoverHandler {
                                id: markHover
                                enabled: markHit.enabled
                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: {
                                    if (hovered) {
                                        if (win.markLive)
                                            win.markLatch = true
                                        return
                                    }
                                    // Depois do evento: a superfície decide a folga
                                    // (closeDelay) ainda com a marca segurando.
                                    Qt.callLater(() => {
                                        if (!markHover.hovered)
                                            win.markLatch = false
                                    })
                                }
                            }
                        }
                    }

                    // ---- Faixa: workspaces · hora · até dois avisos ----
                    Strip {
                        id: strip

                        // Preso ao centro da pílula (e a pílula ao centro da tela): o
                        // relógio fica no centro exato enquanto a largura e a altura
                        // animam, no mesmo ponto do relógio do repouso.
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        // O nível 2 só no hover e só com o interruptor do Estilo.
                        expanded: win.expanded && win.mode === "hover" && island.prefs.level2Dwell
                        // Seletor: a fileira dos seis destinos no lugar da linha.
                        picker: win.mode === "picker"
                        screenName: win.screenName
                        spaceModeTick: island.spaceModeTick
                        activeView: win.isTarget ? island.view : ""
                        menuMode: win.isTarget && island.view !== ""
                        keyboardMode: win.isTarget && island.view !== "" && island.keyboardMode
                        altHeld: win.isTarget && island.altHeld
                        indicatorSource: island.sharedIndicators
                        shell: island.shell
                        strings: island.translations
                        now: clock.date
                        fg: island.fg
                        bg: island.bg
                        accent: island.accent
                        danger: island.danger
                        fontFamily: island.fontFamily
                        metrics: win.metrics

                        opacity: win.stripOn ? 1 : 0
                        scale: win.stripOn ? 1 : 0.97
                        visible: opacity > 0
                        enabled: win.stripOn

                        // Entra em 160 ms enquanto o relógio do repouso sai em 120:
                        // os dois relógios se cruzam no mesmo ponto.
                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(win.stripOn ? win.metrics.msFadeIn : win.metrics.msFadeOut); easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: Commons.Style.duration(win.stripOn ? win.metrics.msFadeIn : win.metrics.msFadeOut); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                        }

                        onCategoryClicked: target => island.categoryClick(target, win.screenName)
                        onCategoryDwelled: target => {
                            if (win.isTarget && island.view !== "")
                                island.show(target, win.screenName)
                        }
                        onWorkspaceClicked: island.close()
                        onIndicatorNavigate: target => {
                            island.keyboardMode = false
                            island.show(target, win.screenName)
                        }
                        onNoticeRequested: island.toggleNotice(win.screenName)
                        onMediaRequested: {
                            island.keyboardMode = false
                            island.show("media", win.screenName)
                        }
                        // Só com um painel aberto (a borda de cima dele chama
                        // wheelPanels). Sem painel, a roda não abre nada.
                        onPanelWheel: step => {
                            if (island.view !== "")
                                island.cycle(step, win.screenName)
                        }
                    }

                    // ---- Estados (painéis e OSD) ----
                    StateSlot { id: launcherSlot; hostWindow: win; hostIsland: island; name: "launcher"; source: "Launcher.qml" }
                    StateSlot { id: controlSlot; hostWindow: win; hostIsland: island; name: "control"; source: "ControlPanel.qml" }
                    StateSlot { id: captureSlot; hostWindow: win; hostIsland: island; name: "capture"; source: "CaptureMenu.qml" }
                    StateSlot { id: styleSlot; hostWindow: win; hostIsland: island; name: "style"; source: "StyleMenu.qml" }
                    StateSlot { id: toolsSlot; hostWindow: win; hostIsland: island; name: "tools"; source: "ToolsMenu.qml" }
                    StateSlot { id: pluginsSlot; hostWindow: win; hostIsland: island; name: "plugins"; source: "PluginsMenu.qml" }
                    StateSlot { id: calendarSlot; hostWindow: win; hostIsland: island; name: "calendar"; source: "CalendarView.qml" }
                    StateSlot { id: powerSlot; hostWindow: win; hostIsland: island; name: "power"; source: "PowerMenu.qml" }
                    StateSlot { id: mediaSlot; hostWindow: win; hostIsland: island; name: "media"; source: "MediaPanel.qml" }
                    StateSlot { id: osdSlot; hostWindow: win; hostIsland: island; name: "osd"; source: "OsdView.qml" }
                    StateSlot { id: noticeSlot; hostWindow: win; hostIsland: island; name: "notice"; source: "NoticeView.qml" }
                    // Aviso ao vivo: a mesma linha da notificação, com o ícone e
                    // o tom do indicador.
                    StateSlot { id: peekSlot; hostWindow: win; hostIsland: island; name: "peek"; source: "NoticeView.qml" }

                    TapHandler {
                        enabled: win.mode === "notice"
                        onTapped: island.closeNotice()
                    }

                    // Toque no aviso: a notificação fixa, ou o painel dono.
                    TapHandler {
                        enabled: win.mode === "peek"
                        onTapped: island.tapPeek(win.screenName)
                    }
                    HoverHandler {
                        enabled: win.mode === "peek"
                        cursorShape: Qt.PointingHandCursor
                    }

                    // Toque na cápsula de repouso (a linha cuida dos próprios
                    // toques): marca → painel dono, barrinhas → Mídia, resto →
                    // Tempo. Toque longo abre o seletor.
                    // O limite padrão (DragThreshold) pega o toque junto com os
                    // filhos e dispara depois deles, mesmo desligado no meio:
                    // quando chega aqui o toque da linha já trocou o modo. Por
                    // isso o dono do toque se decide no aperto (restGesture), e
                    // na soltura um estado novo nesta janela também cancela.
                    TapHandler {
                        id: restPress
                        property bool restGesture: false
                        acceptedButtons: Qt.LeftButton
                        enabled: !win.isPanel && !win.faceMode
                        onPressedChanged: {
                            if (pressed)
                                restGesture = !win.isPanel && !win.faceMode && !(win.revealed && win.stripOn)
                        }
                        onTapped: eventPoint => {
                            const own = restGesture
                            restGesture = false
                            if (!own || win.isPanel || win.faceMode || win.mode === "picker")
                                return
                            const target = win.restTarget(eventPoint.position.x)
                            island.keyboardMode = false
                            island.categoryClick(target, win.screenName)
                        }
                        onLongPressed: island.openPicker(win.screenName)
                    }

                    // Clique direito na cápsula ou na linha: mostra ou esconde o seletor.
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        enabled: !win.isPanel && !win.faceMode
                        onTapped: island.togglePicker(win.screenName)
                    }

                    // Borda de cima do painel (o pad de 14 px, largura toda): a
                    // roda anda os painéis, como fazia a linha. As listas de
                    // dentro ficam abaixo e guardam a própria roda.
                    Item {
                        id: panelWheelZone
                        x: 0
                        y: 0
                        width: parent.width
                        height: win.metrics.pad
                        visible: win.isPanel
                        enabled: win.isPanel

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => strip.wheelPanels(event.angleDelta.y)
                        }
                    }

                    // ---- Rodapé: estado à esquerda, dicas à direita ----
                    PanelFooter {
                        id: footer
                        readonly property bool shown: win.footerOn && win.contentOn

                        anchors.horizontalCenter: parent.horizontalCenter
                        // Acompanha a largura do próprio painel (e a métrica dele, se tiver).
                        width: win.footerSlot && win.footerSlot.implicitWidth > 0 ? win.footerSlot.implicitWidth : win.metrics.content
                        y: win.contentTop
                            + (win.footerSlot ? win.footerSlot.implicitHeight : 0) + win.metrics.gap
                        status: win.footerSlot ? win.footerSlot.footerStatus : ""
                        hints: win.footerSlot ? win.footerSlot.footerHints : ""
                        alert: win.footerSlot ? win.footerSlot.footerAlert : false
                        fg: island.fg
                        danger: island.danger
                        metrics: win.footerSlot ? win.footerSlot.panelMetrics : win.metrics
                        opacity: shown ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(footer.shown ? win.metrics.msFadeIn : win.metrics.msFadeOut); easing.type: Easing.OutCubic }
                        }
                    }
                }

                // ---- Dica por baixo da pílula ----
                // A da linha (layout do workspace, nome · dígito no seletor), a
                // de primeira vez da linha e o nome curto da marca do repouso.
                Item {
                    id: tip
                    readonly property bool lineTip: strip.tooltipShown && win.stripOn && strip.tooltipX >= 0
                    readonly property bool shown: lineTip || win.hintOn || win.markTipOn
                    readonly property string liveText: win.hintOn
                        ? strings.t("island.lineHint", "0 time · 1 apps · scroll switches")
                        : win.markTipOn ? win.markTipText : strip.tooltipText
                    // Centro x em coordenadas da pílula.
                    readonly property real liveX: win.hintOn ? strip.x + strip.width / 2
                        : win.markTipOn ? restClock.x + markRow.x + markRow.width / 2
                        : strip.x + strip.tooltipX
                    property string text: ""
                    property real centerX: 0

                    // Guarda o último texto para o fade de saída não piscar vazio.
                    onShownChanged: if (shown) { text = liveText; centerX = liveX }
                    onLiveTextChanged: if (shown) text = liveText
                    onLiveXChanged: if (shown) centerX = liveX

                    width: tipText.implicitWidth + 20
                    height: 26
                    x: Math.max(4, Math.min(surface.width - width - 4, pill.x + centerX - width / 2))
                    y: pill.y + pill.height + 6
                    opacity: shown ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: Commons.Style.duration(tip.shown ? 160 : 120); easing.type: Easing.OutCubic }
                    }

                    ContinuousRect {
                        anchors.fill: parent
                        radius: island.shellRadius(height, false)
                        color: island.fillBody
                        borderWidth: 0
                    }

                    Text {
                        id: tipText
                        anchors.centerIn: parent
                        text: tip.text
                        color: island.fg
                        font.family: island.fontFamily
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                }
            }

            function shortcutCategory(digit) {
                island.keyboardMode = true
                island.categoryKey(island.categoryOrder[digit])
            }
        }
    }

    // Um estado carregado de arquivo. Se o arquivo faltar ou quebrar, só
    // aquele estado some; a barra continua de pé.
    //
    // Contrato (tudo opcional além de active/closeRequested/navigate):
    //   entra:  active, fg, bg, accent, danger, shell, metrics, keyboardMode,
//           checkUpdates, media (a fonte de música, Indicators)
    //           (payload no OSD)
    //   lido:   panelContent (int constante, sem depender de metrics) = largura útil;
    //           o slot monta o metrics do estado com esse content (padrão 536)
    //   sai:    closeRequested(), navigate(target) = trocar de categoria,
    //           footerStatus, footerHints, footerAlert (lidos pelo rodapé),
    //           handleKey(event) → bool, handleEscape() → bool, focusFirst()
    component StateSlot: Item {
        id: slot

        // A janela e a ilha donas (componentes inline não enxergam ids de fora).
        required property var hostWindow
        required property var hostIsland

        property string name: ""
        property string source: ""
        // Só carrega depois que win e island chegaram.
        property bool ready: false
        Component.onCompleted: ready = true
        readonly property Item item: loader.item
        readonly property bool current: slot.hostWindow.mode === name
        readonly property bool shown: current && slot.hostWindow.contentOn

        // Rodapé do painel (vazio se o estado não publicar).
        readonly property string footerStatus: item && item.footerStatus !== undefined ? String(item.footerStatus) : ""
        readonly property string footerHints: item && item.footerHints !== undefined ? String(item.footerHints) : ""
        readonly property bool footerAlert: !!(item && item.footerAlert)
        // Largura útil declarada pelo painel (constante panelContent), senão a grade de 536.
        readonly property int contentWidth: loader.item && loader.item.panelContent > 0 ? loader.item.panelContent : 536
        // Métrica própria do estado: a da ilha com content = largura do painel,
        // para grade, linhas e rodapé seguirem um painel mais estreito.
        Metrics {
            id: slotMetrics
            corners: slot.hostIsland.cornerMode
            glass: slot.hostIsland.glassMode
            content: slot.contentWidth
        }
        readonly property Metrics panelMetrics: slotMetrics

        anchors.horizontalCenter: parent.horizontalCenter
        // O painel é o cartão inteiro. O OSD, a notificação e o aviso ficam
        // centrados na pílula.
        y: name === "osd" || name === "notice" || name === "peek" ? Math.round((parent.height - height) / 2)
            : slot.hostWindow.contentTop
        implicitWidth: loader.item ? loader.item.implicitWidth : 0
        implicitHeight: loader.item ? loader.item.implicitHeight : 0
        width: implicitWidth
        height: implicitHeight
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.97
        // Visível já ao entrar (o fade ainda em 0): focusFirst só acha itens visíveis.
        visible: shown || opacity > 0
        enabled: shown

        // Troca de painel: 120 ms saindo, 160 ms entrando.
        Behavior on opacity {
            NumberAnimation { duration: Commons.Style.duration(slot.shown ? slot.hostIsland.metrics.msFadeIn : slot.hostIsland.metrics.msFadeOut); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(slot.shown ? slot.hostIsland.metrics.msFadeIn : slot.hostIsland.metrics.msFadeOut); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }

        Loader {
            id: loader
            anchors.centerIn: parent
            // Só o monitor que mostra painéis mantém os estados.
            active: slot.ready && slot.hostWindow.isTarget && slot.source !== ""
            source: active ? Qt.resolvedUrl(slot.source) : ""
            onLoaded: slot.wire(item)
            onStatusChanged: if (status === Loader.Error) console.warn("ilha: state " + slot.source + " failed to load")
        }

        function bindIfPresent(target, prop, getter) {
            if (prop in target)
                target[prop] = Qt.binding(getter)
        }

        function wire(target) {
            if (!target)
                return
            bindIfPresent(target, "active", () => slot.current)
            // Versão antiga do lançador usa "open" em vez de "active".
            if ("open" in target && typeof target.open !== "function")
                target.open = Qt.binding(() => slot.current)
            bindIfPresent(target, "fg", () => slot.hostIsland.fg)
            bindIfPresent(target, "bg", () => slot.hostIsland.bg)
            bindIfPresent(target, "surface", () => slot.hostIsland.surface)
            bindIfPresent(target, "accent", () => slot.hostIsland.accent)
            bindIfPresent(target, "danger", () => slot.hostIsland.danger)
            if (target.themePreview)
                target.themePreview.connect(name => slot.hostIsland.previewTheme(name))
            if (target.themeSettled)
                target.themeSettled.connect(() => slot.hostIsland.settleTheme())
            if (target.lookCorners)
                target.lookCorners.connect(mode => slot.hostIsland.showCorners(mode))
            if (target.lookGlass)
                target.lookGlass.connect(mode => slot.hostIsland.showGlass(mode))
            if (target.lookFont)
                target.lookFont.connect(name => slot.hostIsland.showFace(name))
            bindIfPresent(target, "shell", () => slot.hostIsland.shell)
            bindIfPresent(target, "metrics", () => slotMetrics)
            bindIfPresent(target, "keyboardMode", () => slot.hostIsland.keyboardMode)
            // Testes fora do shell desligam a checagem de atualizações (git fetch).
            bindIfPresent(target, "checkUpdates", () => slot.hostIsland.checkUpdates)
            bindIfPresent(target, "fontFamily", () => slot.hostIsland.fontFamily)
            bindIfPresent(target, "screenSpan", () => slot.hostWindow.screen.width)
            // A fonte de música é a mesma dos indicadores (uma só para os monitores).
            bindIfPresent(target, "media", () => slot.hostIsland.sharedIndicators)
            // Os interruptores do Estilo (Prefs).
            bindIfPresent(target, "prefs", () => slot.hostIsland.prefs)
            if (slot.name === "osd")
                bindIfPresent(target, "payload", () => slot.hostIsland.osdPayload)
            if (slot.name === "notice")
                bindIfPresent(target, "payload", () => slot.hostIsland.noticePayload)
            if (slot.name === "peek")
                bindIfPresent(target, "payload", () => slot.hostIsland.peekPayload)
            if (target.closeRequested)
                target.closeRequested.connect(() => {
                    if (slot.name === "osd")
                        slot.hostIsland.closeOsd()
                    else if (slot.name === "notice")
                        slot.hostIsland.closeNotice()
                    else if (slot.name === "peek")
                        slot.hostIsland.endPeek()
                    else if (slot.hostIsland.view === slot.name)
                        slot.hostIsland.close()
                })
            // navigate(target) = trocar de categoria (como clicar na faixa).
            if (target.navigate)
                target.navigate.connect(dest => {
                    if (!slot.hostIsland.show(String(dest), slot.hostWindow.screenName))
                        slot.hostIsland.close()
                })
        }
    }
}
