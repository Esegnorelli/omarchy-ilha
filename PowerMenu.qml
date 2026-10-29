import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Menu de energia: bloquear, suspender, hibernar, sair, reiniciar e desligar.
// Suspender e hibernar só aparecem quando o sistema permite. Sair, reiniciar
// e desligar pedem um segundo toque em até 3 s.
Item {
    id: root

    // Cores do tema (o host passa os mesmos tokens).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    // Cor de alerta para botões armados.
    property color danger: Commons.Color.urgent

    // O host liga enquanto este estado está visível.
    property bool active: false

    signal closeRequested()
    signal navigate(string target)

    implicitWidth: 400
    implicitHeight: content.implicitHeight

    readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.07)
    readonly property color surfaceHover: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    readonly property color dim: Commons.Color.muted
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    // Lado dos quadrados e espaço entre eles: três por linha.
    readonly property int tileSpacing: 14
    readonly property int tileSize: Math.floor((implicitWidth - 2 * tileSpacing) / 3)

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // ---------- Disponibilidade de suspender/hibernar ----------
    // Mesma regra do menu do sistema: suspender some quando o atalho
    // "suspend-off" está ligado ou quando o sono está desativado na máquina;
    // hibernar exige swap suficiente e o hook de retomada configurado.
    property bool suspendAvailable: true
    property bool hibernateAvailable: false

    Process {
        id: availProc
        command: ["sh", "-c",
            "if omarchy-sleep-disabled; then echo '0 0'; exit 0; fi; "
            + "s=1; omarchy-toggle-enabled suspend-off && s=0; "
            + "h=0; omarchy-hibernation-available && h=1; "
            + "echo \"$s $h\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length === 2) {
                    root.suspendAvailable = parts[0] === "1";
                    root.hibernateAvailable = parts[1] === "1";
                }
            }
        }
    }

    // ---------- Confirmação (sair, reiniciar, desligar) ----------
    property string armed: ""
    Timer {
        id: armTimer
        interval: 3000
        onTriggered: root.armed = ""
    }

    function disarm() {
        armTimer.stop();
        root.armed = "";
    }

    function refresh() {
        if (!availProc.running) availProc.running = true;
    }

    onActiveChanged: {
        if (active) refresh();
        else disarm();
    }
    Component.onCompleted: if (active) refresh()

    // Fecha a ilha e só depois executa, para a ação não aparecer por trás dela.
    function runClosed(cmd) {
        root.disarm();
        root.closeRequested();
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$@\"", "sh"].concat(cmd));
    }

    function confirmOrRun(key, cmd) {
        if (root.armed === key) {
            root.runClosed(cmd);
        } else {
            root.armed = key;
            armTimer.restart();
        }
    }

    // ---------- Componentes internos ----------
    // Quadrado grande de cantos contínuos com ícone e rótulo.
    component PowerButton: Item {
        id: pb
        property string key: ""
        property string icon: ""
        property string label: ""
        readonly property bool isArmed: root.armed !== "" && root.armed === key
        signal clicked()

        width: root.tileSize
        height: root.tileSize

        // Tinta do conteúdo: fundo do tema sobre o vermelho quando armado.
        property color ink: isArmed ? root.bg : (pbHover.hovered ? root.accent : root.fg)
        Behavior on ink { ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }

        ContinuousRect {
            id: tile
            anchors.fill: parent
            radius: 18
            color: pb.isArmed ? root.danger : root.surface
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }
            scale: pbTap.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: Commons.Style.duration(140); easing.type: Easing.OutCubic } }

            // Destaque de hover
            ContinuousRect {
                anchors.fill: parent
                radius: 18
                color: root.surfaceHover
                opacity: pbHover.hovered && !pb.isArmed ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 16
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pb.icon
                    font.family: root.iconFont
                    font.pixelSize: 28
                    color: pb.ink
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: pb.isArmed ? strings.t("power.confirm") : pb.label
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: pb.ink
                }
            }
        }

        HoverHandler { id: pbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: pbTap; onTapped: pb.clicked() }
    }

    // ---------- Layout ----------
    ColumnLayout {
        id: content
        width: root.implicitWidth
        spacing: root.tileSpacing

        // Cabeçalho: voltar ao painel de controle + título
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                id: back
                Layout.preferredWidth: backRow.implicitWidth + 26
                Layout.preferredHeight: 32

                ContinuousRect {
                    anchors.fill: parent
                    radius: height / 2
                    color: backHover.hovered ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14) : root.surface
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                }
                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uF053" // nf-fa-chevron_left
                        font.family: root.iconFont
                        font.pixelSize: 11
                        color: backHover.hovered ? root.accent : root.fg
                        Behavior on color { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: strings.t("power.back")
                        font.pixelSize: 13
                        color: root.fg
                    }
                }
                HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.navigate("control") }
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.rightMargin: 4
                text: strings.t("power.title")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: root.fg
            }
        }

        // Linha 1: ações que preservam a sessão
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: root.tileSpacing

            PowerButton {
                key: "lock"
                icon: "\uF023" // nf-fa-lock
                label: strings.t("power.lock")
                onClicked: root.runClosed(["omarchy", "system", "lock"])
            }
            PowerButton {
                key: "suspend"
                visible: root.suspendAvailable
                icon: "\uDB81\uDCB2" // nf-md-sleep (U+F04B2)
                label: strings.t("power.suspend")
                onClicked: root.runClosed(["systemctl", "suspend"])
            }
            PowerButton {
                key: "hibernate"
                visible: root.hibernateAvailable
                icon: "\uDB82\uDD01" // nf-md-power_sleep (U+F0901)
                label: strings.t("power.hibernate")
                onClicked: root.runClosed(["systemctl", "hibernate"])
            }
        }

        // Linha 2: ações que encerram a sessão (pedem confirmação)
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: root.tileSpacing

            PowerButton {
                key: "logout"
                icon: "\uDB80\uDF43" // nf-md-logout (U+F0343)
                label: strings.t("power.logout")
                onClicked: root.confirmOrRun("logout", ["omarchy", "system", "logout"])
            }
            PowerButton {
                key: "reboot"
                icon: "\uDB81\uDF09" // nf-md-restart (U+F0709)
                label: strings.t("power.reboot")
                onClicked: root.confirmOrRun("reboot", ["omarchy", "system", "reboot"])
            }
            PowerButton {
                key: "shutdown"
                icon: "\uDB81\uDC25" // nf-md-power (U+F0425)
                label: strings.t("power.shutdown")
                onClicked: root.confirmOrRun("shutdown", ["omarchy", "system", "shutdown"])
            }
        }

        // Dica que aparece enquanto um botão está armado.
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: strings.t("power.confirmHint")
            font.pixelSize: 12
            color: root.danger
            opacity: root.armed !== "" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
        }
    }
}
