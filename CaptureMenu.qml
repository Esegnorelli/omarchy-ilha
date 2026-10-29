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
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: btn.icon
                    size: 22
                    filled: btnHover.hovered
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
        property string iconOff: ""
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
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: !chip.on && chip.iconOff !== "" ? chip.iconOff : chip.icon
                    size: 18
                    filled: chip.on
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
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron_left"
                        size: 18
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
                icon: "screenshot_region"
                label: strings.t("capture.region")
                onClicked: root.screenshot("region")
            }
            CaptureButton {
                icon: "select_window"
                label: strings.t("capture.window")
                onClicked: root.screenshot("windows")
            }
            CaptureButton {
                icon: "desktop_windows"
                label: strings.t("capture.fullscreen")
                onClicked: root.screenshot("fullscreen")
            }
            CaptureButton {
                icon: "swipe_vertical"
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
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "stop_circle"
                        size: 20
                        filled: true
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
                icon: "videocam"
                label: strings.t("capture.recordRegion")
                onClicked: root.startRecording(false)
            }
            CaptureButton {
                icon: "screen_record"
                label: strings.t("capture.recordScreen")
                onClicked: root.startRecording(true)
            }
        }

        RowLayout {
            visible: !root.recording
            Layout.fillWidth: true
            spacing: 10
            ToggleChip {
                icon: "volume_up"
                iconOff: "volume_off"
                label: strings.t("capture.desktopAudio")
                on: root.withDesktopAudio
                onToggled: root.withDesktopAudio = !root.withDesktopAudio
            }
            ToggleChip {
                icon: "mic"
                iconOff: "mic_off"
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
                icon: "text_fields"
                label: strings.t("capture.ocr")
                onClicked: root.runAfterClose(["omarchy", "capture", "text"])
            }
            CaptureButton {
                icon: "qr_code_scanner"
                label: strings.t("capture.qr")
                onClicked: root.runAfterClose(["omarchy", "capture", "qr"])
            }
            CaptureButton {
                icon: "colorize"
                label: strings.t("capture.picker")
                onClicked: root.runAfterClose(["hyprpicker", "-a"])
            }
        }
    }
}
