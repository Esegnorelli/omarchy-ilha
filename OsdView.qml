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

    function glyphFor(name, pct) {
        switch (name) {
        case "volume-muted": case "volume-mute": case "muted": case "mute":
            return "\uDB81\uDD81"      // nf-md-volume_off (U+F0581)
        case "volume-low":
            return "\uDB81\uDD7F"      // nf-md-volume_low (U+F057F)
        case "volume-medium":
            return "\uDB81\uDD80"      // nf-md-volume_medium (U+F0580)
        case "volume-high": case "volume":
            return "\uDB81\uDD7E"      // nf-md-volume_high (U+F057E)
        case "microphone-muted": case "microphone-off": case "mic-muted": case "mic-off":
            return "\uDB80\uDF6D"      // nf-md-microphone_off (U+F036D)
        case "microphone": case "mic":
            return "\uDB80\uDF6C"      // nf-md-microphone (U+F036C)
        case "keyboard":
            return "\uDB80\uDF0C"      // nf-md-keyboard (U+F030C)
        case "brightness": case "display":
            return "\uDB80\uDF79"      // nf-md-monitor (U+F0379)
        case "touchpad":
            return "\uDB81\uDFF8"      // nf-md-laptop (U+F07F8)
        case "touch": case "touchscreen":
            return "\uDB81\uDF41"      // nf-md-gesture_tap (U+F0741)
        case "reboot": case "restart":
            return "\uDB81\uDF09"      // nf-md-restart (U+F0709)
        case "shutdown": case "power": case "poweroff":
            return "\uDB81\uDC25"      // nf-md-power (U+F0425)
        case "logout": case "sign-out": case "leave":
            return "\uDB80\uDF43"      // nf-md-logout (U+F0343)
        case "media": case "player": case "media-source": case "player-source":
            return "\uDB81\uDF5A"      // nf-md-music (U+F075A)
        case "media-play": case "player-play":
            return "\uDB81\uDC0A"      // nf-md-play (U+F040A)
        case "media-pause": case "player-pause":
            return "\uDB80\uDFE4"      // nf-md-pause (U+F03E4)
        case "media-next": case "player-next":
            return "\uDB81\uDCAD"      // nf-md-skip_next (U+F04AD)
        case "media-previous": case "player-previous":
            return "\uDB81\uDCAE"      // nf-md-skip_previous (U+F04AE)
        }
        // Um glifo literal curto passa como está (o OSD original aceita).
        if (name.length > 0 && name.length <= 2)
            return String(payload.icon)
        if (pct < 0)
            return ""
        if (pct === 0)
            return "\uDB81\uDD81"      // nf-md-volume_off (U+F0581)
        if (pct <= 33)
            return "\uDB81\uDD7F"      // nf-md-volume_low (U+F057F)
        if (pct <= 66)
            return "\uDB81\uDD80"      // nf-md-volume_medium (U+F0580)
        return "\uDB81\uDD7E"          // nf-md-volume_high (U+F057E)
    }

    readonly property string glyph: glyphFor(iconKey, percent)

    implicitWidth: hasProgress ? 300
        : Math.min(420, Math.max(160, messageText.implicitWidth + (glyph !== "" ? 34 : 0) + 8))
    implicitHeight: 36

    Row {
        anchors.centerIn: parent
        spacing: 12

        Text {
            id: iconText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.glyph !== ""
            width: 22
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph
            color: root.isMuted ? Commons.Color.muted : root.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
            textFormat: Text.PlainText

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
