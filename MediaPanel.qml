import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.Commons as Commons

// Música (view id "media"): o player MPRIS ativo dentro da pílula.
//
//   capa 64 · 12 · título / artista · álbum / [players] · 12 · ◀ ▶‖ ▶   (64)
//   10 · [aleatório] tempo · progresso · duração [repetir]            (24)
//
// Mini-player na densidade do vídeo: conteúdo 440 × 98 (ilha 468 × 126,
// 14 de margem). Nada maior do que o necessário.
//
// A fonte é a mesma dos indicadores (Island liga "media" na instância
// compartilhada): o serviço omarchy.media do shell, senão o MPRIS direto.
// Aleatório e repetir só aparecem quando o player suporta. O seletor de
// players só aparece com mais de um. Sem player, o painel mostra o vazio
// na mesma altura, para a pílula não pular.
//
// Teclado: Espaço/K tocar ou pausar, ←/J anterior, →/L próxima, ,/. voltar
// ou avançar 10 s, S aleatório, R repetir, P próximo player. Esc fecha.
// RTL: o Island espelha a ilha; os botões de transporte e o progresso ficam
// da esquerda para a direita de propósito (o tempo anda para a direita, e
// anterior/próxima seguem os próprios ícones), como no Omarchy.
//
// Contrato com o host: active, fg/bg/accent/danger/muted, fontFamily, metrics,
// keyboardMode, media, closeRequested(), navigate(target), footerStatus,
// footerHints, handleKey(event) → bool, handleEscape() → bool, focusFirst().
Item {
    id: root

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property string fontFamily: Commons.Style.fontFamily

    property bool active: false
    property bool keyboardMode: false
    property Metrics metrics: Metrics {}
    // Indicators compartilhado (mediaPlayer, mediaPlayers, mediaAction…).
    property var media: null

    signal closeRequested()
    signal navigate(string target)

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    function tr(key) { return strings.t(key) }

    // Tons do texto: primário em fg; secundário no token compartilhado
    // (Metrics.secondaryOf: muted um degrau na direção de fg). O ícone do
    // vazio e da capa reserva fica em fg com alfa.
    readonly property color secondary: metrics.secondaryOf(fg, muted)
    readonly property real tertiaryAlpha: 0.52

    // ---------- Player ----------
    readonly property var player: media ? media.mediaPlayer : null
    readonly property var players: media && media.mediaPlayers ? media.mediaPlayers : []
    // Exige o player: na troca (um player some ou chega) hasMedia pode valer
    // um instante antes de mediaPlayer existir.
    readonly property bool hasTrack: !!(media && media.hasMedia && player)
    readonly property bool playing: !!(player && player.isPlaying)
    readonly property string title: hasTrack ? String(player.trackTitle || player.trackArtist || "") : ""
    readonly property string artist: hasTrack && player.trackTitle ? String(player.trackArtist || "") : ""
    readonly property string album: hasTrack ? String(player.trackAlbum || "") : ""
    readonly property string artUrl: hasTrack && player.trackArtUrl ? String(player.trackArtUrl) : ""
    readonly property string playerName: media && player ? media.mediaLabel(player) : ""

    readonly property bool canPrev: !!(player && player.canGoPrevious)
    readonly property bool canNext: !!(player && player.canGoNext)
    readonly property bool canToggle: !!(player && (player.canTogglePlaying || player.canPlay || player.canPause))
    readonly property bool hasShuffle: !!(player && player.shuffleSupported && player.canControl)
    readonly property bool hasLoop: !!(player && player.loopSupported && player.canControl)
    readonly property bool shuffleOn: hasShuffle && !!player.shuffle
    readonly property int loopMode: hasLoop ? player.loopState : MprisLoopState.None

    // ---------- Tempo ----------
    readonly property real length: player && player.lengthSupported && player.length > 0 ? player.length : 0
    readonly property real position: player && player.positionSupported ? Math.max(0, player.position) : 0
    readonly property bool canSeek: !!(player && player.canSeek && player.positionSupported) && length > 0
    // Arrastando: o trilho mostra o ponto do dedo, não o do player.
    property bool scrubbing: false
    property real scrubFrac: 0
    readonly property real shownPosition: scrubbing ? scrubFrac * length : Math.min(position, length > 0 ? length : position)
    readonly property real progress: length > 0 ? Math.max(0, Math.min(1, shownPosition / length)) : 0

    // O MPRIS não avisa o avanço da posição: pedimos a leitura a cada segundo,
    // só com o painel aberto e tocando.
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.playing && root.player !== null
        onTriggered: if (root.player) root.player.positionChanged()
    }
    onActiveChanged: if (active && player) player.positionChanged()
    onPlayerChanged: scrubbing = false

    function pad2(n) {
        return n < 10 ? Commons.I18n.formatNumber(0) + Commons.I18n.formatNumber(n) : Commons.I18n.formatNumber(n)
    }
    // 3:07 ou 1:02:45, com os dígitos do idioma.
    function clockText(seconds) {
        const s = Math.max(0, Math.floor(Number(seconds) || 0))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const r = s % 60
        if (h > 0)
            return Commons.I18n.formatNumber(h) + ":" + pad2(m) + ":" + pad2(r)
        return Commons.I18n.formatNumber(m) + ":" + pad2(r)
    }

    // ---------- Ações ----------
    function act(action) {
        if (!media || !player)
            return false
        return media.mediaAction(action, media.mediaKey(player))
    }
    function seekTo(seconds) {
        if (!canSeek)
            return false
        player.position = Math.max(0, Math.min(length - 0.5, seconds))
        player.positionChanged()
        return true
    }
    function seekBy(delta) {
        return seekTo(position + delta)
    }
    function toggleShuffle() {
        if (!hasShuffle)
            return false
        player.shuffle = !player.shuffle
        return true
    }
    // Desligado → lista → faixa → desligado.
    function cycleLoop() {
        if (!hasLoop)
            return false
        const now = player.loopState
        player.loopState = now === MprisLoopState.None ? MprisLoopState.Playlist
            : now === MprisLoopState.Playlist ? MprisLoopState.Track
            : MprisLoopState.None
        return true
    }
    function nextPlayer() {
        if (!media || players.length < 2)
            return false
        const key = media.mediaKey(player)
        let at = 0
        for (let i = 0; i < players.length; i++)
            if (media.mediaKey(players[i]) === key)
                at = i
        media.selectMedia(media.mediaKey(players[(at + 1) % players.length]))
        return true
    }

    // ---------- Rodapé ----------
    // Só no modo teclado: com o mouse o mini-player fica sem rodapé.
    readonly property string footerStatus: !hasTrack || !keyboardMode ? ""
        : playerName !== "" ? playerName + " · " + tr(playing ? "media.playing" : "media.paused")
        : tr(playing ? "media.playing" : "media.paused")
    readonly property string footerHints: hasTrack && keyboardMode ? tr("hint.media") : ""
    readonly property bool footerAlert: false

    // ---------- Teclado (o host chama) ----------
    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
        if (mods)
            return false
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_K:
            if (!event.isAutoRepeat)
                act("playPause")
            return true
        case Qt.Key_Left:
        case Qt.Key_J:
            if (!event.isAutoRepeat)
                act("previous")
            return true
        case Qt.Key_Right:
        case Qt.Key_L:
            if (!event.isAutoRepeat)
                act("next")
            return true
        case Qt.Key_Comma:
            seekBy(-10)
            return true
        case Qt.Key_Period:
            seekBy(10)
            return true
        case Qt.Key_S:
            if (!event.isAutoRepeat)
                toggleShuffle()
            return true
        case Qt.Key_R:
            if (!event.isAutoRepeat)
                cycleLoop()
            return true
        case Qt.Key_P:
            if (!event.isAutoRepeat)
                nextPlayer()
            return true
        }
        return false
    }
    function handleEscape() {
        if (scrubbing) {
            scrubbing = false
            return true
        }
        return false
    }
    function focusFirst() {
        root.forceActiveFocus()
        return true
    }

    // Largura do conteúdo (ilha = 440 + 2 × 14 = 468) e altura das duas
    // linhas: capa 64 + 10 + progresso 24 = 98 (ilha 126).
    readonly property int panelContent: 440
    implicitWidth: panelContent
    implicitHeight: 98

    // ================= Vazio =================
    Row {
        anchors.centerIn: parent
        visible: !root.hasTrack
        spacing: 12

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48

            ContinuousRect {
                anchors.fill: parent
                radius: root.metrics.fit(14)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
            }
            Icon {
                anchors.centerIn: parent
                name: "music_off"
                size: 24
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.tertiaryAlpha)
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: root.tr("media.nothingPlaying")
                textFormat: Text.PlainText
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignLeft
            }
            Text {
                text: root.tr("media.nothingPlayingHint")
                textFormat: Text.PlainText
                color: root.secondary
                font.family: root.fontFamily
                font.pixelSize: 12
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    // ================= Tocando =================
    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.hasTrack
        spacing: 10

        // ---- Linha 1: capa · textos · transporte ----
        Item {
            width: parent.width
            height: 64

            Item {
                id: artBox
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                height: 64

                ContinuousRect {
                    anchors.fill: parent
                    radius: root.metrics.fit(14)
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
                    visible: !art.ready
                }
                Icon {
                    anchors.centerIn: parent
                    visible: !art.ready
                    name: "music_note"
                    size: 28
                    filled: true
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.tertiaryAlpha)
                }

                Image {
                    id: artImage
                    anchors.fill: parent
                    visible: false
                    source: root.artUrl
                    sourceSize.width: 128
                    sourceSize.height: 128
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    cache: true
                }
                ContinuousRect {
                    id: artMask
                    anchors.fill: parent
                    radius: root.metrics.fit(14)
                    color: root.fg
                    visible: false
                    layer.enabled: art.ready
                }
                MultiEffect {
                    id: art
                    readonly property bool ready: root.artUrl !== "" && artImage.status === Image.Ready
                    anchors.fill: parent
                    visible: ready
                    source: artImage
                    maskEnabled: true
                    maskSource: artMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
            }

            Column {
                id: info
                anchors.left: artBox.right
                anchors.leftMargin: 12
                anchors.right: transportBox.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    width: parent.width
                    text: root.title
                    textFormat: Text.PlainText
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    // Explícito para o espelho do RTL alinhar à direita.
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                // Artista e álbum numa linha só.
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.artist !== "" && root.album !== "" ? root.artist + " · " + root.album
                        : root.artist !== "" ? root.artist : root.album
                    textFormat: Text.PlainText
                    color: root.secondary
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                // Seletor de players: fichas com o nome, só com mais de um.
                Item {
                    width: parent.width
                    height: 18
                    visible: root.players.length > 1

                    Row {
                        id: chips
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 4
                        clip: true

                        Repeater {
                            model: root.players.length > 1 ? root.players : []

                            Item {
                                id: chip
                                required property var modelData
                                readonly property string key: root.media ? root.media.mediaKey(modelData) : ""
                                readonly property bool selected: !!root.media && key === root.media.mediaKey(root.player)

                                width: Math.min(96, chipText.implicitWidth + (chipDot.visible ? 24 : 16))
                                height: 18

                                Accessible.role: Accessible.Button
                                Accessible.name: chipText.text

                                ContinuousRect {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
                                        chip.selected ? root.metrics.alphaPressed
                                        : chipHover.hovered ? root.metrics.alphaHover : root.metrics.alphaIdle)
                                    Behavior on color {
                                        ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic }
                                    }
                                }

                                // Ponto no destaque: este player está tocando.
                                Rectangle {
                                    id: chipDot
                                    anchors.left: parent.left
                                    anchors.leftMargin: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!chip.modelData.isPlaying
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: root.accent
                                }

                                Text {
                                    id: chipText
                                    anchors.left: chipDot.visible ? chipDot.right : parent.left
                                    anchors.leftMargin: chipDot.visible ? 4 : 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.media ? root.media.mediaLabel(chip.modelData) : ""
                                    textFormat: Text.PlainText
                                    color: chip.selected ? root.fg : root.secondary
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    font.weight: chip.selected ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: if (root.media) root.media.selectMedia(chip.key)
                                }
                            }
                        }
                    }
                }
            }

            // Transporte: a caixa segue o espelho da ilha (vai para a esquerda
            // no RTL); a fileira dentro fica LTR, como os ícones.
            Item {
                id: transportBox
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: transport.width
                height: transport.height

                Row {
                    id: transport
                    LayoutMirroring.enabled: false
                    LayoutMirroring.childrenInherit: true
                    spacing: 4

                    RoundButton {
                        anchors.verticalCenter: parent.verticalCenter
                        diameter: 32
                        iconName: "skip_previous"
                        iconSize: 18
                        available: root.canPrev
                        label: root.tr("media.previous")
                        onTapped: root.act("previous")
                    }
                    RoundButton {
                        anchors.verticalCenter: parent.verticalCenter
                        diameter: 40
                        iconName: root.playing ? "pause" : "play_arrow"
                        iconSize: 22
                        primary: true
                        available: root.canToggle
                        label: root.tr(root.playing ? "media.pause" : "media.play")
                        onTapped: root.act("playPause")
                    }
                    RoundButton {
                        anchors.verticalCenter: parent.verticalCenter
                        diameter: 32
                        iconName: "skip_next"
                        iconSize: 18
                        available: root.canNext
                        label: root.tr("media.next")
                        onTapped: root.act("next")
                    }
                }
            }
        }

        // ---- Linha 2: [aleatório] tempo · trilho · duração [repetir] ----
        // Sempre LTR: o tempo anda para a direita.
        Row {
            id: progressRow
            width: parent.width
            height: 24
            spacing: 8
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            readonly property bool hot: seekHover.hovered || root.scrubbing
            // O trilho fica com o que sobra da fileira.
            readonly property real trackWidth: Math.max(0, width
                - (shuffleBtn.visible ? shuffleBtn.width + spacing : 0)
                - elapsedText.width - spacing
                - spacing - totalText.width
                - (repeatBtn.visible ? spacing + repeatBtn.width : 0))

            RoundButton {
                id: shuffleBtn
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasShuffle
                diameter: visible ? 24 : 0
                iconName: "shuffle"
                iconSize: 16
                on: root.shuffleOn
                label: root.tr("media.shuffle")
                onTapped: root.toggleShuffle()
            }

            Text {
                id: elapsedText
                anchors.verticalCenter: parent.verticalCenter
                // Largura da duração: o tempo não empurra o trilho ao virar 10:00.
                width: Math.max(implicitWidth, totalText.implicitWidth)
                horizontalAlignment: Text.AlignRight
                text: root.length > 0 || root.position > 0 ? root.clockText(root.shownPosition) : ""
                textFormat: Text.PlainText
                color: root.secondary
                font.family: root.fontFamily
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }

            Item {
                id: trackBox
                anchors.verticalCenter: parent.verticalCenter
                width: progressRow.trackWidth
                height: 18

                ContinuousRect {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    x: 0
                    width: parent.width
                    height: 4
                    radius: root.metrics.fit(2)
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)

                    ContinuousRect {
                        x: 0
                        width: Math.max(height, track.width * root.progress)
                        height: parent.height
                        radius: root.metrics.fit(2)
                        color: root.accent
                        visible: root.length > 0
                    }

                    // Botão do trilho: só no hover ou arrastando.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: track.width * root.progress - width / 2
                        width: 10
                        height: 10
                        radius: root.metrics.fit(5)
                        color: root.fg
                        visible: root.canSeek
                        opacity: progressRow.hot ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic }
                        }
                    }
                }

                // Clique ou arraste no trilho (faixa de 18 px em volta dele).
                MouseArea {
                    id: seekArea
                    anchors.fill: parent
                    enabled: root.canSeek
                    cursorShape: root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                    preventStealing: true

                    function fracAt(px) {
                        return Math.max(0, Math.min(1, px / Math.max(1, width)))
                    }
                    onPressed: mouse => {
                        root.scrubFrac = fracAt(mouse.x)
                        root.scrubbing = true
                    }
                    onPositionChanged: mouse => {
                        if (root.scrubbing)
                            root.scrubFrac = fracAt(mouse.x)
                    }
                    onReleased: {
                        if (!root.scrubbing)
                            return
                        root.scrubbing = false
                        root.seekTo(root.scrubFrac * root.length)
                    }
                    onCanceled: root.scrubbing = false
                }
                HoverHandler { id: seekHover; enabled: root.canSeek }
            }

            Text {
                id: totalText
                anchors.verticalCenter: parent.verticalCenter
                text: root.length > 0 ? root.clockText(root.length) : ""
                textFormat: Text.PlainText
                color: root.secondary
                font.family: root.fontFamily
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }

            RoundButton {
                id: repeatBtn
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasLoop
                diameter: visible ? 24 : 0
                iconName: root.loopMode === MprisLoopState.Track ? "repeat_one" : "repeat"
                iconSize: 16
                on: root.loopMode !== MprisLoopState.None
                label: root.tr("media.repeat")
                onTapped: root.cycleLoop()
            }
        }
    }

    // Botão redondo do transporte. "primary" é o play/pausa: círculo cheio no
    // destaque com o ícone na cor do fundo. "on" (aleatório, repetir ligados):
    // ícone no destaque sobre um fundo do destaque bem leve.
    component RoundButton: Item {
        id: btn
        property int diameter: 48
        property string iconName: ""
        property int iconSize: 24
        property bool primary: false
        property bool on: false
        property bool available: true
        property string label: ""
        signal tapped()

        width: diameter
        height: diameter
        opacity: available ? 1 : root.metrics.opacityUnavailable

        Accessible.role: Accessible.Button
        Accessible.name: btn.label

        ContinuousRect {
            anchors.fill: parent
            radius: root.metrics.fit(height / 2)
            color: btn.primary ? root.accent
                : btn.on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.metrics.alphaPill)
                : Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
                    btnTap.pressed ? root.metrics.alphaPressed
                    : btnHover.hovered ? root.metrics.alphaHover : root.metrics.alphaIdle)
            Behavior on color {
                ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic }
            }
        }
        // Hover no play/pausa: um véu de fg por cima do destaque.
        ContinuousRect {
            anchors.fill: parent
            radius: root.metrics.fit(height / 2)
            visible: btn.primary
            color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, btnTap.pressed ? 0.16 : btnHover.hovered ? 0.08 : 0)
        }

        Icon {
            anchors.centerIn: parent
            name: btn.iconName
            size: btn.iconSize
            filled: true
            color: btn.primary ? root.bg : btn.on ? root.accent : root.fg
            Behavior on color {
                ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic }
            }
        }

        scale: btnTap.pressed && btn.available ? root.metrics.pressScale : 1
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(root.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }

        HoverHandler {
            id: btnHover
            enabled: btn.available
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: btnTap
            enabled: btn.available
            onTapped: btn.tapped()
        }
    }
}
