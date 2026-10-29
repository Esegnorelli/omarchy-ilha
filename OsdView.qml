import QtQuick
import qs.Commons as Commons

// OSD como estado compacto da pílula. Desenha o mesmo payload do OSD do
// Omarchy: {icon, message, value, progressText, max, duration}. Uma mensagem
// esconde a barra de progresso, como no original.
Item {
    id: root

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent

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

    implicitWidth: hasProgress ? 300
        : Math.min(420, Math.max(160, messageText.implicitWidth + (glyph !== "" ? 34 : 0) + 8))
    implicitHeight: 36

    Row {
        anchors.centerIn: parent
        spacing: 12

        Icon {
            id: iconText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph !== ""
            width: 24
            name: root.glyph
            size: 22
            filled: !root.isMuted
            color: root.isMuted ? Commons.Color.muted : root.fg

            Behavior on color {
                ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic }
            }
        }

        // Com progresso: trilho e valor.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasProgress
            width: 196
            height: 8

            ContinuousRect {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
            }

            ContinuousRect {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: Math.max(height, parent.width * root.value / root.maxValue)
                visible: root.value > 0
                radius: height / 2
                color: root.isMuted ? Commons.Color.muted : root.accent

                Behavior on width {
                    NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasProgress
            width: 46
            horizontalAlignment: Text.AlignRight
            text: root.valueText
            color: root.fg
            font.pixelSize: 14
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }

        // Sem progresso: a mensagem.
        Text {
            id: messageText
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.hasProgress
            width: Math.min(implicitWidth, 420 - (root.glyph !== "" ? 34 : 0) - 8)
            elide: Text.ElideRight
            text: root.rawMessage
            color: root.fg
            font.pixelSize: 14
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }
    }
}
