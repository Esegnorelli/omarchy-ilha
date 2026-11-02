import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.Commons as Commons

// Música (view id "media"): o player MPRIS ativo dentro da pílula.
//
//   capa 132 · 16 · título / artista / álbum / seletor de players   (132)
//   14 · progresso (trilho 6 + tempos 11 px)                         (30)
//   14 · [aleatório] anterior · play/pausa · próxima [repetir]      (60)
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
    readonly property string footerStatus: !hasTrack ? ""
        : playerName !== "" ? playerName + " · " + tr(playing ? "media.playing" : "media.paused")
        : tr(playing ? "media.playing" : "media.paused")
    readonly property string footerHints: hasTrack ? tr("hint.media") : ""
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

    implicitWidth: metrics.content
    implicitHeight: 250

    // ================= Vazio =================
    Column {
        anchors.centerIn: parent
        visible: !root.hasTrack
        spacing: 10

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72
            height: 72

            ContinuousRect {
                anchors.fill: parent
                radius: root.metrics.cardRadius
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
            }
            Icon {
                anchors.centerIn: parent
                name: "music_off"
                size: 32
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.tertiaryAlpha)
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.tr("media.nothingPlaying")
            textFormat: Text.PlainText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.tr("media.nothingPlayingHint")
            textFormat: Text.PlainText
            color: root.secondary
            font.family: root.fontFamily
            font.pixelSize: 12
        }
    }

    // ================= Tocando =================
    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.hasTrack
        spacing: 14

        // ---- Capa e textos ----
        Item {
            width: parent.width
            height: 132

            Item {
                id: artBox
                anchors.left: parent.left
                anchors.top: parent.top
                width: 132
                height: 132

                ContinuousRect {
                    anchors.fill: parent
                    radius: root.metrics.cardRadius
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
                    visible: !art.ready
                }
                Icon {
                    anchors.centerIn: parent
                    visible: !art.ready
                    name: "music_note"
                    size: 44
                    filled: true
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.tertiaryAlpha)
                }

                Image {
                    id: artImage
                    anchors.fill: parent
                    visible: false
                    source: root.artUrl
                    sourceSize.width: 264
                    sourceSize.height: 264
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    cache: true
                }
                ContinuousRect {
                    id: artMask
                    anchors.fill: parent
                    radius: root.metrics.cardRadius
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
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 6
                spacing: 4

                Text {
                    width: parent.width
                    text: root.title
                    textFormat: Text.PlainText
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    // Explícito para o espelho do RTL alinhar à direita.
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.artist
                    textFormat: Text.PlainText
                    color: root.secondary
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.album
                    textFormat: Text.PlainText
                    color: root.secondary
                    opacity: 0.85
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            // Seletor de players: fichas com o nome, só com mais de um.
            Row {
                id: chips
                anchors.left: info.left
                anchors.right: info.right
                anchors.bottom: parent.bottom
                spacing: 6
                clip: true
                visible: root.players.length > 1

                Repeater {
                    model: root.players.length > 1 ? root.players : []

                    Item {
                        id: chip
                        required property var modelData
                        readonly property string key: root.media ? root.media.mediaKey(modelData) : ""
                        readonly property bool selected: !!root.media && key === root.media.mediaKey(root.player)

                        width: Math.min(120, chipText.implicitWidth + (chipDot.visible ? 30 : 22))
                        height: 26

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
                            anchors.leftMargin: 10
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
                            anchors.leftMargin: chipDot.visible ? 5 : 11
                            anchors.right: parent.right
                            anchors.rightMargin: 11
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

        // ---- Progresso (sempre LTR: o tempo anda para a direita) ----
        Item {
            id: progressBox
            width: parent.width
            height: 30
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            readonly property bool hot: seekHover.hovered || root.scrubbing

            ContinuousRect {
                id: track
                x: 0
                y: 4
                width: parent.width
                height: 6
                radius: root.metrics.fit(3)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)

                ContinuousRect {
                    x: 0
                    width: Math.max(height, track.width * root.progress)
                    height: parent.height
                    radius: root.metrics.fit(3)
                    color: root.accent
                    visible: root.length > 0
                }

                // Botão do trilho: só no hover ou arrastando.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: track.width * root.progress - width / 2
                    width: 12
                    height: 12
                    radius: root.metrics.fit(6)
                    color: root.fg
                    visible: root.canSeek
                    opacity: progressBox.hot ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic }
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: root.length > 0 || root.position > 0 ? root.clockText(root.shownPosition) : ""
                textFormat: Text.PlainText
                color: root.secondary
                font.family: root.fontFamily
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }
            Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                text: root.length > 0 ? root.clockText(root.length) : ""
                textFormat: Text.PlainText
                color: root.secondary
                font.family: root.fontFamily
                font.pixelSize: 11
                font.features: ({ "tnum": 1 })
            }

            // Clique ou arraste no trilho (faixa de 18 px em volta dele).
            MouseArea {
                id: seekArea
                x: 0
                y: -2
                width: parent.width
                height: 18
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

        // ---- Transporte (sempre LTR, como os ícones) ----
        Item {
            width: parent.width
            height: 60
            LayoutMirroring.enabled: false
            LayoutMirroring.childrenInherit: true

            Row {
                anchors.centerIn: parent
                spacing: 14

                RoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasShuffle
                    diameter: 40
                    iconName: "shuffle"
                    iconSize: 18
                    on: root.shuffleOn
                    label: root.tr("media.shuffle")
                    onTapped: root.toggleShuffle()
                }
                RoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 48
                    iconName: "skip_previous"
                    iconSize: 24
                    available: root.canPrev
                    label: root.tr("media.previous")
                    onTapped: root.act("previous")
                }
                RoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 60
                    iconName: root.playing ? "pause" : "play_arrow"
                    iconSize: 30
                    primary: true
                    available: root.canToggle
                    label: root.tr(root.playing ? "media.pause" : "media.play")
                    onTapped: root.act("playPause")
                }
                RoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 48
                    iconName: "skip_next"
                    iconSize: 24
                    available: root.canNext
                    label: root.tr("media.next")
                    onTapped: root.act("next")
                }
                RoundButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.hasLoop
                    diameter: 40
                    iconName: root.loopMode === MprisLoopState.Track ? "repeat_one" : "repeat"
                    iconSize: 18
                    on: root.loopMode !== MprisLoopState.None
                    label: root.tr("media.repeat")
                    onTapped: root.cycleLoop()
                }
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
