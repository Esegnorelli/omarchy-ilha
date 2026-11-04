pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Música dentro da Central de controle: o cartão "tocando agora" (486 x 64,
// raio 21, fill card), entre a Tela e as Notificações.
//
// - Capa 44 (raio 12) a 10 da borda, a nota musical sem capa.
// - Título 14 / 600 e artista 12 inkMuted; sem player, "Nada tocando".
// - Anterior, tocar/pausar (círculo accent 34) e próxima, à direita.
// - Toque na capa ou no texto abre a tela de Mídia (fila, posição, aleatório).
// - focusedPart ("open" | "prev" | "play" | "next") desenha o anel do teclado.
Item {
    id: root

    property Theme theme: null
    property var strings: null
    property var media: null
    property string focusedPart: ""

    HoverHandler { id: cardHover }
    readonly property bool pointed: cardHover.hovered || prevBtn.hovered || nextBtn.hovered
    signal openRequested()

    readonly property bool has: !!root.media && root.media.hasTrack
    readonly property alias prevButton: prevBtn
    readonly property alias playButton: playBtn
    readonly property alias nextButton: nextBtn
    readonly property alias openArea: openZone

    width: 486
    height: 64

    function t(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    Rectangle {
        anchors.fill: parent
        radius: 21
        antialiasing: true
        color: root.theme ? root.theme.card : "#111"
    }

    // ---- Capa ----
    Item {
        id: art
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        height: 44

        Rectangle {
            id: artMask
            anchors.fill: parent
            radius: 12
            antialiasing: true
            visible: false
            layer.enabled: true
            layer.smooth: true
        }
        Rectangle {
            anchors.fill: parent
            radius: 12
            antialiasing: true
            color: root.theme ? root.theme.raised : "#222"
        }
        Icon {
            anchors.centerIn: parent
            name: "music_note"
            size: 20
            color: root.theme ? root.theme.inkFaint : "gray"
            opacity: cover.status === Image.Ready ? 0 : 1
        }
        Image {
            id: cover
            anchors.fill: parent
            source: root.has ? root.media.artUrl : ""
            sourceSize.width: 88
            sourceSize.height: 88
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.theme ? root.theme.dur(120) : 0 }
            }
            layer.enabled: status === Image.Ready
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: artMask
            }
        }
    }

    // ---- Texto ----
    Column {
        x: art.x + art.width + 12
        width: transport.x - x - 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        IlhaText {
            width: parent.width
            theme: root.theme
            size: 14
            weight: 600
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignLeft
            color: root.theme ? (root.has ? root.theme.ink : root.theme.inkMuted) : "white"
            text: root.has ? root.media.title : root.t("media.nothingPlaying")
        }
        IlhaText {
            width: parent.width
            visible: text !== ""
            theme: root.theme
            size: 12
            weight: 400
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignLeft
            color: root.theme ? root.theme.inkMuted : "gray"
            text: root.has ? (root.media.artist || root.media.playerName || "") : ""
        }
    }

    // Capa e texto: abrem a Mídia.
    MouseArea {
        id: openZone
        x: 0
        width: transport.x
        height: parent.height
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested()

        FocusRing {
            theme: root.theme
            itemRadius: 21
            shown: root.focusedPart === "open"
        }
    }

    // ---- Transporte ----
    Row {
        id: transport
        x: parent.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        CircleButton {
            id: prevBtn
            theme: root.theme
            size: 32
            glyphSize: 18
            icon: "skip_previous"
            enabled: root.has && root.media.canPrevious
            focused: root.focusedPart === "prev"
            veil: (root.pointed || root.focusedPart === "prev") ? 1 : 0
            accessibleName: root.t("media.previous")
            onClicked: root.media.previous()
        }
        Item {
            id: playBtn
            width: 34
            height: 34
            readonly property bool focusedNow: root.focusedPart === "play"
            Accessible.role: Accessible.Button
            Accessible.name: root.has && root.media.playing ? root.t("media.pause") : root.t("media.play")
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: root.theme ? root.theme.accent : "white"
                opacity: root.has && root.media.canPlayPause ? (playArea.pressed ? 0.8 : 1) : 0.35
            }
            Icon {
                anchors.centerIn: parent
                name: root.has && root.media.playing ? "pause" : "play_arrow"
                size: 20
                filled: true
                color: root.theme ? root.theme.onAccent : "black"
            }
            MouseArea {
                id: playArea
                anchors.fill: parent
                enabled: root.has && root.media.canPlayPause
                cursorShape: Qt.PointingHandCursor
                onClicked: root.media.playPause()
            }
            FocusRing {
                theme: root.theme
                itemRadius: 17
                shown: playBtn.focusedNow
            }
        }
        CircleButton {
            id: nextBtn
            theme: root.theme
            size: 32
            glyphSize: 18
            icon: "skip_next"
            enabled: root.has && root.media.canNext
            focused: root.focusedPart === "next"
            veil: (root.pointed || root.focusedPart === "next") ? 1 : 0
            accessibleName: root.t("media.next")
            onClicked: root.media.next()
        }
    }
}
