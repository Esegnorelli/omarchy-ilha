import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Estado de captura: capturas de tela, gravação de tela e ferramentas
// de leitura da tela (OCR, QR code e conta-gotas).
Item {
    id: root

    // Cores do tema (o host passa os mesmos tokens).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    // Cor de destaque para "Parar gravação".
    property color danger: Commons.Color.urgent

    // O host liga enquanto este estado está visível.
    property bool active: false

    signal closeRequested()
    signal navigate(string target)

    // Estado da gravação, lido ao ativar.
    property bool recording: false
    property bool statusKnown: false

    // Opções de áudio somadas ao comando de gravar.
    property bool withDesktopAudio: false
    property bool withMicrophone: false

    implicitWidth: 400
    implicitHeight: content.implicitHeight

    readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.07)
    readonly property color surfaceHover: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    readonly property color dim: Commons.Color.muted
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // ---------- Leitura do estado da gravação ----------
    // Código de saída 0 = há uma gravação em andamento.
    Process {
        id: statusProc
        command: ["omarchy", "capture", "screenrecording", "--status"]
        onExited: (exitCode, exitStatus) => {
            root.recording = exitCode === 0;
            root.statusKnown = true;
        }
    }

    function refresh() {
        if (!statusProc.running) statusProc.running = true;
    }

    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()

    // ---------- Execução ----------
    // Fecha a ilha e roda o comando depois que ela sumiu da tela.
    function runAfterClose(cmd) {
        root.closeRequested();
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$@\"", "sh"].concat(cmd));
    }

    function screenshot(mode) {
        runAfterClose(["omarchy", "capture", "screenshot", mode]);
    }

    function startRecording(fullscreen) {
        const cmd = ["omarchy", "capture", "screenrecording"];
        if (fullscreen) cmd.push("--fullscreen");
        if (root.withDesktopAudio) cmd.push("--with-desktop-audio");
        if (root.withMicrophone) cmd.push("--with-microphone-audio");
        runAfterClose(cmd);
    }

    function stopRecording() {
        root.recording = false;
        runAfterClose(["omarchy", "capture", "screenrecording", "--stop-recording"]);
    }

    // ---------- Componentes internos ----------
    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: 6
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.dim
    }

    // Bloco com ícone e rótulo, cantos contínuos.
    component CaptureButton: Item {
        id: btn
        property string icon: ""
        property string label: ""
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: 72

        ContinuousRect {
            anchors.fill: parent
            radius: 14
            color: root.surface
            scale: btnTap.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: Commons.Style.duration(140); easing.type: Easing.OutCubic } }

            ContinuousRect {
                anchors.fill: parent
                radius: 14
                color: root.surfaceHover
                opacity: btnHover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 12
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: btn.icon
                    font.family: root.iconFont
                    font.pixelSize: 18
                    color: btnHover.hovered ? root.accent : root.fg
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: btn.label
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    color: root.fg
                }
            }
        }

        HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: btnTap; onTapped: btn.clicked() }
    }

    // Chip liga/desliga para as opções de áudio.
    component ToggleChip: Item {
        id: chip
        property string icon: ""
        property string label: ""
        property bool on: false
        signal toggled()

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.preferredHeight: 36

        property color ink: on ? root.bg : root.fg
        Behavior on ink { ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }

        ContinuousRect {
            anchors.fill: parent
            radius: height / 2
            color: chip.on ? root.accent : root.surface
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }
            scale: chipTap.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: Commons.Style.duration(140); easing.type: Easing.OutCubic } }

            ContinuousRect {
                anchors.fill: parent
                radius: height / 2
                color: root.surfaceHover
                opacity: chipHover.hovered && !chip.on ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
            }

            Row {
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.icon
                    font.family: root.iconFont
                    font.pixelSize: 14
                    color: chip.ink
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.label
                    font.pixelSize: 12
                    font.weight: chip.on ? Font.DemiBold : Font.Normal
                    color: chip.ink
                }
            }
        }

        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: chipTap; onTapped: chip.toggled() }
    }

    // ---------- Layout ----------
    ColumnLayout {
        id: content
        width: root.implicitWidth
        spacing: 10

        // Cabeçalho: voltar + título
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2
            spacing: 12

            Item {
                id: backChip
                Layout.preferredHeight: 32
                Layout.preferredWidth: backRow.implicitWidth + 26

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
                        text: strings.t("capture.back")
                        font.pixelSize: 13
                        color: root.fg
                    }
                }

                HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.navigate("control") }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                rightPadding: 4
                text: strings.t("capture.title")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: root.fg
            }
        }

        // ---------- Captura de tela ----------
        SectionLabel { text: strings.t("capture.section.screenshot") }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            CaptureButton {
                icon: "\uF125" // nf-fa-crop
                label: strings.t("capture.region")
                onClicked: root.screenshot("region")
            }
            CaptureButton {
                icon: "\uF2D0" // nf-fa-window_maximize
                label: strings.t("capture.window")
                onClicked: root.screenshot("windows")
            }
            CaptureButton {
                icon: "\uF108" // nf-fa-desktop
                label: strings.t("capture.fullscreen")
                onClicked: root.screenshot("fullscreen")
            }
            CaptureButton {
                icon: "\uF07D" // nf-fa-arrows_v
                label: strings.t("capture.scroll")
                onClicked: root.screenshot("scroll")
            }
        }

        // ---------- Gravação ----------
        SectionLabel { text: strings.t("capture.section.recording") }

        // Gravação em andamento: botão de parar em destaque.
        Item {
            id: stopButton
            visible: root.recording
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            ContinuousRect {
                anchors.fill: parent
                radius: 16
                color: root.danger
                scale: stopTap.pressed ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: Commons.Style.duration(140); easing.type: Easing.OutCubic } }

                ContinuousRect {
                    anchors.fill: parent
                    radius: 16
                    color: root.bg
                    opacity: stopHover.hovered ? 0.15 : 0
                    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\uF04D" // nf-fa-stop
                        font.family: root.iconFont
                        font.pixelSize: 15
                        color: root.bg
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: strings.t("capture.stop")
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: root.bg
                    }
                }
            }

            HoverHandler { id: stopHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { id: stopTap; onTapped: root.stopRecording() }
        }

        // Sem gravação: iniciar + opções de áudio.
        RowLayout {
            visible: !root.recording
            Layout.fillWidth: true
            spacing: 10
            CaptureButton {
                icon: "\uF03D" // nf-fa-video_camera
                label: strings.t("capture.recordRegion")
                onClicked: root.startRecording(false)
            }
            CaptureButton {
                icon: "\uF108" // nf-fa-desktop
                label: strings.t("capture.recordScreen")
                onClicked: root.startRecording(true)
            }
        }

        RowLayout {
            visible: !root.recording
            Layout.fillWidth: true
            spacing: 10
            ToggleChip {
                icon: "\uF028" // nf-fa-volume_up
                label: strings.t("capture.desktopAudio")
                on: root.withDesktopAudio
                onToggled: root.withDesktopAudio = !root.withDesktopAudio
            }
            ToggleChip {
                icon: "\uF130" // nf-fa-microphone
                label: strings.t("capture.microphone")
                on: root.withMicrophone
                onToggled: root.withMicrophone = !root.withMicrophone
            }
        }

        // ---------- Ferramentas ----------
        SectionLabel { text: strings.t("capture.section.tools") }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            CaptureButton {
                icon: "\uF031" // nf-fa-font
                label: strings.t("capture.ocr")
                onClicked: root.runAfterClose(["omarchy", "capture", "text"])
            }
            CaptureButton {
                icon: "\uF029" // nf-fa-qrcode
                label: strings.t("capture.qr")
                onClicked: root.runAfterClose(["omarchy", "capture", "qr"])
            }
            CaptureButton {
                icon: "\uF1FB" // nf-fa-eyedropper
                label: strings.t("capture.picker")
                onClicked: root.runAfterClose(["hyprpicker", "-a"])
            }
        }
    }
}
