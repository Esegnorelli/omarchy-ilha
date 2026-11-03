pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons as Commons
import "Motion.js" as Motion

// Tela de música (screens §14): 514 x 218, cap 30, um fade só (como a
// Central e a Energia). Dono: Agent H.
//
//   capa 120 (16, 16) | título 17/600 (152, 20)
//                     | artista 13.5/500 (152, 46)
//                     | [ícone] player (152, 70)   botão com mais de um
//                     | ━━━━━━━●─────── barra (152..498, y 104), sempre LTR
//                     | 1:23                 −2:10 (y 116)
//        aleatório · anterior · tocar/pausar · próxima · repetir (y 152..202)
//
// - Tudo em posição final fixa; nada depende do tamanho vivo da forma.
// - RTL: a capa vai para a direita e a coluna de texto para a esquerda
//   (theme.mirrorX). A barra, os tempos e o transporte ficam LTR de
//   propósito (o tempo anda para a direita; anterior/próxima seguem os
//   próprios ícones), como no Omarchy.
// - Capa nova: troca cruzada de 200 ms quando a imagem nova fica pronta.
//   Sem capa: cartão com a nota musical.
// - Sem player (ou sem faixa): "Nada tocando" e a dica, no mesmo tamanho;
//   barra vazia e transporte apagado.
// - Teclas: Espaço / Enter tocar ou pausar; ← / → voltar ou avançar 5 s;
//   Shift+← / Shift+→ anterior / próxima; S aleatório; R repetir; P próximo
//   player; Esc solta um arraste (depois fecha, pela pilha).
// - Nada roda antes de opened(): a posição só é lida com a tela aberta
//   (media.positionPolling, ligado no Ilha.qml enquanto a Mídia está aberta em
//   algum monitor) e a capa nova só carrega aberta.
Item {
    id: root

    // ---- Contrato de tela ----
    property var island: null
    property Theme theme: null
    property var strings: null
    property var morph: null
    property bool current: false
    property bool keyboardMode: false
    property var payload: null
    property real edgeLeft: 0
    property real edgeRight: root.implicitWidth
    property var heightMotion: "panel"
    property bool snapping: false
    property list<Item> headerItems
    property list<Item> bodyItems
    signal navigate(string id, var payload)
    signal closeRequested()

    function opened(payload) {
        root.snapping = true;
        root.live = true;
        root.scrubbing = false;
        root.loadArt();
        Qt.callLater(() => root.snapping = false);
    }
    function closed() {
        root.live = false;
        root.scrubbing = false;
    }

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods)
            return false;
        const m = root.media;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!event.isAutoRepeat && m)
                m.playPause();
            return true;
        case Qt.Key_Left:
        case Qt.Key_Right: {
            const forward = event.key === Qt.Key_Right;
            if (shift) {
                if (!event.isAutoRepeat && m) {
                    if (forward)
                        m.next();
                    else
                        m.previous();
                }
            } else if (m && m.canSeek) {
                m.seek(m.position + (forward ? 5 : -5));
            }
            return true;
        }
        case Qt.Key_S:
            if (!event.isAutoRepeat && m)
                m.setShuffle(!m.shuffle);
            return true;
        case Qt.Key_R:
            if (!event.isAutoRepeat && m)
                m.cycleLoop();
            return true;
        case Qt.Key_P:
            if (!event.isAutoRepeat && m)
                m.selectNext();
            return true;
        }
        return false;
    }
    function handleEscape() {
        if (root.scrubbing) {
            root.scrubbing = false;
            return true;
        }
        return false;
    }

    implicitWidth: 514
    implicitHeight: 218

    // ---- Estado ----
    readonly property var media: root.island ? root.island.media : null
    readonly property var status: root.island ? root.island.status : null
    readonly property bool has: !!root.media && root.media.hasTrack
    readonly property bool rtl: !!root.theme && root.theme.rtl
    // Entre opened() e closed().
    property bool live: false

    // Arraste na barra: o trilho mostra o ponto do ponteiro, não o do player.
    property bool scrubbing: false
    property real scrubFrac: 0
    readonly property real length: root.has ? root.media.length : 0
    readonly property real shownPosition: root.scrubbing ? root.scrubFrac * root.length : (root.has ? Math.min(root.media.position, root.length > 0 ? root.length : root.media.position) : 0)
    readonly property real progress: root.length > 0 ? Math.max(0, Math.min(1, root.shownPosition / root.length)) : 0
    onHasChanged: if (!root.has) root.scrubbing = false
    readonly property bool loopOne: !!root.media && root.media.loopState === "track"

    function tr(key) {
        return root.strings ? root.strings.t(key) : "";
    }
    // x de uma caixa no layout LTR, espelhada no RTL.
    function mx(x, w) {
        return root.rtl && root.theme ? root.theme.mirrorX(x, w, root.implicitWidth / 2) : x;
    }
    function clock(sec) {
        return root.status ? root.status.clockText(Math.max(0, Math.floor(sec))) : "";
    }
    function fade(ms) {
        return root.snapping || !root.theme ? 0 : root.theme.dur(ms);
    }

    // ---- Capa com troca cruzada ----
    readonly property string artWanted: root.has ? root.media.artUrl : ""
    onArtWantedChanged: if (root.live) root.loadArt()
    property int artFront: 0

    function loadArt() {
        const url = root.artWanted;
        const front = root.artFront === 0 ? artA : artB;
        const back = root.artFront === 0 ? artB : artA;
        if (url === "") {
            artA.pending = false;
            artB.pending = false;
            artA.shown = false;
            artB.shown = false;
            return;
        }
        if (front.shown && String(front.source) === url) {
            back.pending = false;
            return;
        }
        back.pending = true;
        if (String(back.source) === url)
            root.flipArt(back);
        else
            back.source = url;
    }
    function flipArt(img) {
        if (!img.pending || img.status !== Image.Ready)
            return;
        img.pending = false;
        const other = img === artA ? artB : artA;
        img.shown = true;
        other.shown = false;
        root.artFront = img === artA ? 0 : 1;
    }

    Item {
        id: artBox
        x: root.mx(16, 120)
        y: 16
        width: 120
        height: 120

        ClippingRectangle {
            anchors.fill: parent
            radius: 16
            color: root.theme ? root.theme.card : "transparent"

            Icon {
                anchors.centerIn: parent
                name: "music_note"
                size: 40
                color: root.theme ? root.theme.inkFaint : "gray"
                opacity: (artA.shown && artA.status === Image.Ready) || (artB.shown && artB.status === Image.Ready) ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: root.fade(Motion.FADE.ART_CROSSFADE); easing.type: Easing.OutCubic }
                }
            }

            ArtImage { id: artA }
            ArtImage { id: artB }
        }
    }

    // ---- Coluna de texto ----
    IlhaText {
        x: root.mx(152, 346)
        y: 20
        width: 346
        theme: root.theme
        size: root.has ? 17 : 15
        weight: 600
        elide: Text.ElideRight
        maximumLineCount: 1
        horizontalAlignment: Text.AlignLeft
        text: root.has ? root.media.title : root.tr("media.nothingPlaying")
    }
    IlhaText {
        x: root.mx(152, 346)
        y: 46
        width: 346
        theme: root.theme
        size: root.has ? 13.5 : 12.5
        weight: root.has ? 500 : 400
        color: root.theme ? root.theme.inkMuted : "gray"
        elide: Text.ElideRight
        maximumLineCount: 1
        horizontalAlignment: Text.AlignLeft
        text: !root.has ? root.tr("media.nothingHint")
            : root.media.artist !== "" ? root.media.artist
            : root.media.album !== "" ? root.media.album
            : root.tr("media.unknownArtist")
    }

    // Ficha do player: ícone 14 + nome 11.5. Com mais de um player é um
    // botão (próximo player) e mostra "1/2".
    Item {
        id: chip
        readonly property bool multi: !!root.media && root.media.players.length > 1
        readonly property int index: {
            if (!chip.multi)
                return 0;
            const list = root.media.players;
            const key = root.media.keyOf(root.media.player);
            for (let i = 0; i < list.length; i++) {
                if (root.media.keyOf(list[i]) === key)
                    return i;
            }
            return 0;
        }
        readonly property string counter: chip.multi && root.strings ? root.strings.t("common.counter").arg(Commons.I18n.formatNumber(chip.index + 1)).arg(Commons.I18n.formatNumber(root.media.players.length)) : ""
        readonly property real nameW: Math.min(200, Math.ceil(nameMetrics.advanceWidth))
        readonly property real counterW: chip.counter !== "" ? Math.ceil(counterMetrics.advanceWidth) : 0
        readonly property real contentW: 14 + 6 + chip.nameW + (chip.counterW > 0 ? 6 + chip.counterW : 0)
        readonly property bool hovered: chipArea.containsMouse

        x: root.mx(152 - 6, chip.contentW + 12)
        y: 68
        width: chip.contentW + 12
        height: 22
        opacity: root.has && root.media.playerName !== "" ? 1 : 0
        enabled: chip.opacity > 0.5 && chip.multi
        Behavior on opacity {
            NumberAnimation { duration: root.fade(Motion.FADE.HOVER); easing.type: Easing.OutCubic }
        }

        Accessible.role: chip.multi ? Accessible.Button : Accessible.StaticText
        Accessible.name: chip.multi ? root.tr("media.switchPlayer") + ": " + (root.media ? root.media.playerName : "") : (root.media ? root.media.playerName : "")

        IlhaMetrics {
            id: nameMetrics
            theme: root.theme
            size: 11.5
            weight: 500
            text: root.media ? root.media.playerName : ""
        }
        IlhaMetrics {
            id: counterMetrics
            theme: root.theme
            size: 11.5
            weight: 500
            tnum: true
            text: chip.counter
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.theme ? (chipArea.pressed ? root.theme.rowHover : root.theme.raised) : "transparent"
            opacity: chip.multi && (chip.hovered || chipArea.pressed) ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.fade(Motion.FADE.HOVER); easing.type: Easing.OutCubic }
            }
        }

        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: chip.contentW
            spacing: 6

            Item {
                width: 14
                height: 14
                anchors.verticalCenter: parent.verticalCenter

                IconImage {
                    id: appIcon
                    anchors.fill: parent
                    source: root.media && root.media.playerIconName !== "" ? Quickshell.iconPath(root.media.playerIconName, true) : ""
                    asynchronous: true
                    opacity: appIcon.status === Image.Ready ? 1 : 0
                }
                Icon {
                    anchors.centerIn: parent
                    name: "music_note"
                    size: 14
                    filled: true
                    color: root.theme ? root.theme.inkFaint : "gray"
                    opacity: appIcon.status === Image.Ready ? 0 : 1
                }
            }
            IlhaText {
                width: chip.nameW
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                size: 11.5
                weight: 500
                color: root.theme ? (chip.hovered ? root.theme.inkMuted : root.theme.inkFaint) : "gray"
                elide: Text.ElideRight
                maximumLineCount: 1
                text: root.media ? root.media.playerName : ""
            }
            IlhaText {
                width: chip.counterW
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                size: 11.5
                weight: 500
                tnum: true
                color: root.theme ? root.theme.inkFaint : "gray"
                opacity: chip.counterW > 0 ? 0.8 : 0
                text: chip.counter
            }
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.media) root.media.selectNext()
        }
    }

    // ---- Barra de progresso (sempre LTR por dentro) ----
    Item {
        id: seek
        x: root.mx(152, 346)
        y: 96
        width: 346
        height: 40
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        readonly property bool hot: seekArea.containsMouse || root.scrubbing
        readonly property bool canSeek: root.has && root.media.canSeek

        Accessible.role: Accessible.Slider
        Accessible.name: root.clock(root.shownPosition) + (root.length > 0 ? " / " + root.clock(root.length) : "")

        // Trilho: y 104..110 na tela.
        Rectangle {
            id: track
            x: 0
            y: 8
            width: seek.width
            height: 6
            radius: 3
            color: root.theme ? root.theme.raised : "transparent"

            Rectangle {
                x: 0
                width: Math.max(0, track.width * root.progress)
                height: track.height
                radius: 3
                color: root.theme ? root.theme.accent : "white"
                opacity: root.length > 0 && width >= 1 ? 1 : 0
            }
        }

        // Botão: só no hover ou arrastando.
        Rectangle {
            x: track.width * root.progress - width / 2
            y: track.y + track.height / 2 - height / 2
            width: 12
            height: 12
            radius: 6
            color: root.theme ? root.theme.ink : "white"
            opacity: seek.canSeek && seek.hot ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.fade(Motion.FADE.HOVER); easing.type: Easing.OutCubic }
            }
        }

        // Tempos: y 116 na tela.
        IlhaText {
            x: 0
            y: 20
            theme: root.theme
            size: 11.5
            weight: 500
            tnum: true
            color: root.theme ? root.theme.inkFaint : "gray"
            horizontalAlignment: Text.AlignLeft
            opacity: root.has && (root.length > 0 || root.shownPosition > 0) ? 1 : 0
            text: root.clock(root.shownPosition)
        }
        IlhaText {
            x: seek.width - width
            y: 20
            theme: root.theme
            size: 11.5
            weight: 500
            tnum: true
            color: root.theme ? root.theme.inkFaint : "gray"
            horizontalAlignment: Text.AlignRight
            opacity: root.has && root.length > 0 ? 1 : 0
            text: "−" + root.clock(Math.max(0, root.length - root.shownPosition))
        }

        // Faixa de toque em volta do trilho (o trilho tem 6 px).
        MouseArea {
            id: seekArea
            x: 0
            y: 0
            width: seek.width
            height: 22
            enabled: seek.canSeek
            hoverEnabled: true
            preventStealing: true
            cursorShape: seek.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

            function fracAt(px) {
                return Math.max(0, Math.min(1, px / Math.max(1, width)));
            }
            onPressed: mouse => {
                root.scrubFrac = seekArea.fracAt(mouse.x);
                root.scrubbing = true;
            }
            onPositionChanged: mouse => {
                if (root.scrubbing)
                    root.scrubFrac = seekArea.fracAt(mouse.x);
            }
            onReleased: {
                if (!root.scrubbing)
                    return;
                root.scrubbing = false;
                if (root.media)
                    root.media.seek(root.scrubFrac * root.length);
            }
            onCanceled: root.scrubbing = false
        }
    }

    // ---- Transporte (y 152..202, centrado em 257, sempre LTR) ----
    // aleatório 36 | 18 | anterior 44 | 18 | tocar 50 | 18 | próxima 44 | 18 | repetir 36
    Item {
        id: transport
        x: (root.implicitWidth - 282) / 2
        y: 152
        width: 282
        height: 50
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true
        opacity: root.has ? 1 : 0.35
        Behavior on opacity {
            NumberAnimation { duration: root.fade(Motion.FADE.HOVER); easing.type: Easing.OutCubic }
        }

        TransportButton {
            x: 0
            diameter: 36
            glyph: "shuffle"
            glyphSize: 18
            toggle: true
            on: !!root.media && root.media.shuffle
            available: root.has && root.media.shuffleSupported
            label: root.tr("media.shuffle")
            onTapped: root.media.setShuffle(!root.media.shuffle)
        }
        TransportButton {
            x: 36 + 18
            diameter: 44
            glyph: "skip_previous"
            glyphSize: 24
            available: root.has && root.media.canPrevious
            label: root.tr("media.previous")
            onTapped: root.media.previous()
        }
        TransportButton {
            x: 36 + 18 + 44 + 18
            diameter: 50
            glyph: root.media && root.media.playing ? "pause" : "play_arrow"
            glyphSize: 26
            primary: true
            available: root.has && root.media.canPlayPause
            label: root.tr(root.media && root.media.playing ? "media.pause" : "media.play")
            onTapped: root.media.playPause()
        }
        TransportButton {
            x: 36 + 18 + 44 + 18 + 50 + 18
            diameter: 44
            glyph: "skip_next"
            glyphSize: 24
            available: root.has && root.media.canNext
            label: root.tr("media.next")
            onTapped: root.media.next()
        }
        TransportButton {
            x: 282 - 36
            diameter: 36
            glyph: root.loopOne ? "repeat_one" : "repeat"
            glyphSize: 18
            toggle: true
            on: !!root.media && root.media.loopState !== "none"
            available: root.has && root.media.loopSupported
            label: root.tr("media.repeat")
            onTapped: root.media.cycleLoop()
        }
    }

    // Uma camada da capa (duas, para a troca cruzada).
    component ArtImage: Image {
        id: img
        property bool shown: false
        property bool pending: false

        anchors.fill: parent
        sourceSize.width: 240
        sourceSize.height: 240
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        opacity: img.shown && img.status === Image.Ready ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.fade(Motion.FADE.ART_CROSSFADE); easing.type: Easing.OutCubic }
        }
        onStatusChanged: {
            if (img.status === Image.Ready)
                root.flipArt(img);
            else if (img.status === Image.Error) {
                // A capa nova falhou: some a velha também, a nota musical aparece.
                if (img.pending && String(img.source) === root.artWanted) {
                    artA.shown = false;
                    artB.shown = false;
                }
                img.pending = false;
            }
        }
    }

    // Botão redondo do transporte. primary: círculo accent com o glifo
    // onAccent. toggle: aleatório / repetir (accentInk quando ligado).
    component TransportButton: Item {
        id: btn
        property real diameter: 44
        property string glyph: ""
        property real glyphSize: 24
        property bool primary: false
        property bool toggle: false
        property bool on: false
        property bool available: true
        property string label: ""
        signal tapped()

        readonly property bool hovered: btnArea.containsMouse && btn.available
        readonly property bool down: btnArea.pressed && btn.available

        y: (transport.height - btn.diameter) / 2
        width: btn.diameter
        height: btn.diameter
        opacity: btn.available ? 1 : 0.4

        Accessible.role: Accessible.Button
        Accessible.name: btn.label
        Accessible.checkable: btn.toggle
        Accessible.checked: btn.on

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: !root.theme ? "transparent"
                : btn.primary ? (btn.hovered ? root.theme.mix(root.theme.accent, root.theme.ink, 0.08) : root.theme.accent)
                : btn.hovered || btn.down ? root.theme.raised
                : root.theme.alpha(root.theme.raised, 0)
            Behavior on color {
                ColorAnimation { duration: root.fade(Motion.FADE.HOVER) }
            }
        }
        // Toque: um véu de tinta por cima (também no accent).
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.theme ? root.theme.pressOverlay : "transparent"
            opacity: btn.down ? 1 : 0
        }

        Icon {
            anchors.centerIn: parent
            name: btn.glyph
            size: btn.glyphSize
            filled: true
            color: !root.theme ? "white"
                : btn.primary ? root.theme.onAccent
                : btn.toggle ? (btn.on ? root.theme.accentInk : root.theme.inkMuted)
                : root.theme.ink
            Behavior on color {
                ColorAnimation { duration: root.fade(Motion.FADE.HOVER) }
            }
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.available
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.tapped()
        }
    }
}
