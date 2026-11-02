import QtQuick
import qs.Commons as Commons

// OSD como estado compacto da pílula. Desenha o mesmo payload do OSD do
// Omarchy: {icon, message, value, progressText, max, duration}. Uma mensagem
// esconde a barra de progresso, como no original.
// RTL: tudo é âncora ou Row, então o espelho do Island vira a barra (enche
// da direita) e põe o valor do outro lado.
Item {
    id: root

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property string fontFamily: Commons.Style.fontFamily
    property Metrics metrics: Metrics {}

    property bool active: false
    signal closeRequested()
    signal navigate(string target)

    // O payload já decodificado (objeto) ou vazio.
    property var payload: ({})

    readonly property string iconKey: String(payload && payload.icon ? payload.icon : "").toLowerCase()
    readonly property string rawMessage: String(payload && payload.message ? payload.message : "").slice(0, 200)
    readonly property int maxValue: Math.max(1, parseInt(payload && payload.max !== undefined ? payload.max : "100", 10) || 100)
    readonly property int parsedValue: parseInt(payload && payload.value !== undefined ? payload.value : "", 10)
    readonly property bool hasProgress: payload && payload.value !== undefined && String(payload.value) !== ""
        && !isNaN(parsedValue) && rawMessage === ""
    readonly property int value: hasProgress ? Math.max(0, Math.min(maxValue, parsedValue)) : 0
    readonly property int percent: hasProgress ? Math.round(value * 100 / maxValue) : -1
    readonly property string valueText: {
        if (!hasProgress)
            return ""
        const given = String(payload && payload.progressText ? payload.progressText : "").slice(0, 16)
        return given !== "" ? given : Commons.I18n.formatNumber(percent) + "%"
    }
    readonly property bool isMuted: iconKey === "volume-muted" || iconKey === "volume-mute"
        || iconKey === "muted" || iconKey === "mute" || iconKey.indexOf("microphone-muted") === 0
        || iconKey === "microphone-off" || iconKey === "mic-muted" || iconKey === "mic-off"

    // Duração em ms (0 = fica até fechar). Padrão 1200, como o OSD original.
    function durationOf(p) {
        const parsed = parseInt(p && p.duration !== undefined && String(p.duration) !== "" ? p.duration : "1200", 10)
        return isNaN(parsed) ? 1200 : Math.max(0, parsed)
    }

    // Nome Material Symbols para cada chave de ícone do OSD do Omarchy.
    function volumeFor(pct) {
        if (pct === 0)
            return "volume_off"
        if (pct <= 33)
            return "volume_mute"
        if (pct <= 66)
            return "volume_down"
        return "volume_up"
    }

    function brightnessFor(pct) {
        if (pct < 0)
            return "brightness_medium"
        if (pct <= 33)
            return "brightness_low"
        if (pct <= 66)
            return "brightness_medium"
        return "brightness_high"
    }

    function glyphFor(name, pct) {
        switch (name) {
        case "volume-muted": case "volume-mute": case "muted": case "mute":
            return "volume_off"
        case "volume-low":
            return "volume_mute"
        case "volume-medium":
            return "volume_down"
        case "volume-high": case "volume":
            return "volume_up"
        case "microphone-muted": case "microphone-off": case "mic-muted": case "mic-off":
            return "mic_off"
        case "microphone": case "mic":
            return "mic"
        case "keyboard":
            return "keyboard"
        case "brightness": case "display":
            return brightnessFor(pct)
        case "touchpad":
            return "touchpad_mouse"
        case "touch": case "touchscreen":
            return "touch_app"
        case "reboot": case "restart":
            return "restart_alt"
        case "shutdown": case "power": case "poweroff":
            return "power_settings_new"
        case "logout": case "sign-out": case "leave":
            return "logout"
        case "media": case "player": case "media-source": case "player-source":
            return "music_note"
        case "media-play": case "player-play":
            return "play_arrow"
        case "media-pause": case "player-pause":
            return "pause"
        case "media-next": case "player-next":
            return "skip_next"
        case "media-previous": case "player-previous":
            return "skip_previous"
        }
        // Chave desconhecida: com progresso vira volume pelo valor; só
        // mensagem ganha um "info".
        if (pct >= 0)
            return volumeFor(pct)
        return name.length > 0 ? "info" : ""
    }

    readonly property string glyph: glyphFor(iconKey, percent)

    // A mensagem é medida pelo TextMetrics (como no NoticeView): ligar a
    // largura do Text no próprio implicitWidth, com elide, encolhe o texto.
    readonly property int glyphBox: glyph !== "" ? 34 : 0
    readonly property int messageBox: Math.min(420 - glyphBox - 8, Math.ceil(messageMetrics.advanceWidth) + 2)
    // Progresso: cápsula de 220 × 28 com o ícone dentro, valor à direita.
    readonly property int barWidth: 220
    readonly property int barHeight: 28
    readonly property int valueBox: 46

    implicitWidth: hasProgress ? barWidth + 12 + valueBox
        : Math.min(420, Math.max(160, messageBox + glyphBox + 8))
    implicitHeight: 36

    TextMetrics {
        id: messageMetrics
        font.family: root.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
        text: root.rawMessage
    }

    // Com progresso: trilho em cápsula, preenchimento sólido no destaque e o
    // ícone dentro dele, na tinta do fundo.
    Row {
        anchors.centerIn: parent
        visible: root.hasProgress
        spacing: 12

        Item {
            id: bar
            anchors.verticalCenter: parent.verticalCenter
            width: root.barWidth
            height: root.barHeight

            ContinuousRect {
                anchors.fill: parent
                radius: root.metrics.fit(height / 2)
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
            }

            ContinuousRect {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                // Nunca menor que a altura: o ícone sempre tem onde ficar.
                width: Math.max(height, parent.width * root.value / root.maxValue)
                radius: root.metrics.fit(14)
                color: root.isMuted ? root.muted : root.accent

                Behavior on width {
                    NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                }
                Behavior on color {
                    ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
                }
            }

            // Âncora, não x fixo: em RTL o preenchimento cresce da direita e o
            // ícone vai junto (o Island espelha a ilha inteira).
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                visible: root.glyph !== ""
                name: root.glyph
                size: 16
                filled: !root.isMuted
                color: root.bg
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.valueBox
            horizontalAlignment: Text.AlignRight
            text: root.valueText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            textFormat: Text.PlainText
        }
    }

    // Sem progresso: ícone e mensagem.
    Row {
        anchors.centerIn: parent
        visible: !root.hasProgress
        spacing: 10

        Icon {
            id: iconText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph !== ""
            width: 24
            name: root.glyph
            size: 22
            filled: !root.isMuted
            color: root.isMuted ? root.muted : root.fg

            Behavior on color {
                ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: messageText
            anchors.verticalCenter: parent.verticalCenter
            width: root.messageBox
            elide: Text.ElideRight
            text: root.rawMessage
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }
    }
}
