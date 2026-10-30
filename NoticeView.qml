import QtQuick
import qs.Commons as Commons

// Notificação como estado compacto da pílula: ícone, aplicativo e resumo
// numa linha. O texto chega de fora e fica em PlainText.
Item {
    id: root

    property color fg: Commons.Color.foreground
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property string fontFamily: Commons.Style.fontFamily
    property var payload: ({})

    signal closeRequested()

    readonly property string app: String(payload && payload.app ? payload.app : "").slice(0, 48)
    readonly property string summary: String(payload && payload.summary ? payload.summary : "").slice(0, 140)
    readonly property bool urgent: !!(payload && (payload.urgent === true || Number(payload.urgency) === 2))
    readonly property bool showApp: app !== "" && app !== summary

    readonly property int iconBox: 22
    readonly property int gap: 8
    // A medida vem do TextMetrics. Ligar a largura do Text no próprio
    // implicitWidth, com elide, encolhe o texto até sobrar só a reticência.
    readonly property int appBox: showApp ? Math.min(140, Math.ceil(appMetrics.advanceWidth) + 2) : 0
    readonly property int summaryBox: Math.min(360, Math.max(24, Math.ceil(summaryMetrics.advanceWidth) + 4))

    implicitWidth: iconBox + gap + (showApp ? appBox + gap : 0) + summaryBox
    implicitHeight: 36

    TextMetrics {
        id: appMetrics
        font.family: root.fontFamily
        font.pixelSize: 13
        font.weight: Font.Medium
        text: root.app
    }

    TextMetrics {
        id: summaryMetrics
        font.family: root.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
        text: root.summary
    }

    Accessible.role: Accessible.Button
    Accessible.name: (showApp ? app + " " : "") + summary

    Row {
        anchors.centerIn: parent
        spacing: root.gap

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconBox
            height: root.iconBox
            name: root.urgent ? "priority_high" : "notifications"
            size: 18
            filled: true
            color: root.urgent ? root.danger : root.accent

            Behavior on color {
                ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
            }
        }

        Text {
            id: appText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showApp
            width: root.appBox
            elide: Text.ElideRight
            text: root.app
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.62)
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            textFormat: Text.PlainText
        }

        Text {
            id: summaryText
            anchors.verticalCenter: parent.verticalCenter
            width: root.summaryBox
            elide: Text.ElideRight
            text: root.summary
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }
    }
}
