import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Aparência: tema, plano de fundo, fonte monoespaçada e estilo das janelas.
Item {
    id: root

    // Cores do tema (o host passa as mesmas).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color dim: Commons.Color.muted

    // O host liga enquanto este estado está visível; as leituras são refeitas ao ligar.
    property bool active: false

    signal closeRequested()
    signal navigate(string target)

    implicitWidth: 420
    implicitHeight: content.implicitHeight

    readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.07)
    readonly property color surfaceStrong: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
    readonly property color hoverTint: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    // ---------- Estado lido do sistema ----------
    property var themes: []          // [{ name, preview }]
    property string currentTheme: ""
    property var fonts: []
    property string currentFont: ""
    property string corners: ""      // theme | sharp | rounded
    property string transparency: "" // opaque | transparent | glassy
    property string background: ""
    property bool themesLoaded: false

    // Tema escolhido aqui que ainda não foi gravado pelo sistema.
    property string pendingTheme: ""
    property int pendingChecks: 0

    readonly property int currentThemeIndex: {
        for (let i = 0; i < themes.length; i++)
            if (themes[i].name === currentTheme) return i;
        return -1;
    }

    onActiveChanged: {
        if (active) refresh();
        else recheck.stop();
    }
    Component.onCompleted: if (active) refresh()

    function refresh() {
        root.pendingTheme = "";
        themeListProc.running = true;
        fontListProc.running = true;
        refreshStatus();
    }

    function refreshStatus() {
        themeCurrentProc.running = true;
        fontCurrentProc.running = true;
        cornersProc.running = true;
        transparencyProc.running = true;
        backgroundProc.running = true;
    }

    // Confere o estado real pouco depois de uma ação.
    Timer {
        id: recheck
        interval: 1500
        onTriggered: if (root.active) root.refreshStatus()
    }

    function run(cmd) {
        Quickshell.execDetached(cmd);
        recheck.restart();
    }

    // Para ações que abrem outra interface: recolhe a ilha antes de executar.
    function runAfterClose(cmd) {
        root.closeRequested();
        Quickshell.execDetached(["sh", "-c", "sleep 0.35; exec \"$@\"", "sh"].concat(cmd));
    }

    function setTheme(name) {
        if (name === root.currentTheme) return;
        root.currentTheme = name;
        root.pendingTheme = name;
        root.pendingChecks = 0;
        root.run(["omarchy", "theme", "set", name]);
    }
    function setFont(name) {
        if (name === root.currentFont) return;
        root.currentFont = name;
        Qt.callLater(fontStrip.revealCurrent);
        root.run(["omarchy", "font", "set", name]);
    }
    function setCorners(mode) {
        if (mode === root.corners) return;
        root.corners = mode;
        root.run(["omarchy", "hyprland", "corners", mode]);
    }
    function setTransparency(mode) {
        if (mode === root.transparency) return;
        root.transparency = mode;
        root.run(["omarchy", "hyprland", "window", "transparency", mode]);
    }

    function lines(text) {
        return String(text).split("\n").map(l => l.trim()).filter(l => l.length > 0);
    }

    // ---------- Leituras ----------
    // Lista de temas com a imagem de prévia de cada um (pasta do usuário primeiro).
    // Os nomes chegam pelo `read` do próprio script; nada daqui é interpolado nele.
    Process {
        id: themeListProc
        command: ["sh", "-c",
            "[ -n \"$OMARCHY_PATH\" ] || for d in \"$HOME/.local/share/omarchy\" /usr/share/omarchy; do " +
            "[ -d \"$d/themes\" ] && export OMARCHY_PATH=\"$d\" && break; done; " +
            "omarchy theme list | while IFS= read -r n; do " +
            "s=$(printf '%s' \"$n\" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'); p=''; " +
            "for d in \"$HOME/.config/omarchy/themes/$s\" \"$OMARCHY_PATH/themes/$s\"; do " +
            "for f in preview.png preview.jpg; do [ -z \"$p\" ] && [ -f \"$d/$f\" ] && p=\"$d/$f\"; done; done; " +
            "printf '%s\\t%s\\n' \"$n\" \"$p\"; done"]
        stdout: StdioCollector {
            id: themeListOut
            onStreamFinished: {
                const out = [];
                for (const l of root.lines(themeListOut.text)) {
                    const parts = l.split("\t");
                    out.push({ name: parts[0], preview: parts.length > 1 ? parts[1] : "" });
                }
                root.themes = out;
                root.themesLoaded = true;
                Qt.callLater(grid.revealCurrent);
            }
        }
    }
    Process {
        id: themeCurrentProc
        command: ["omarchy", "theme", "current"]
        stdout: StdioCollector {
            id: themeCurrentOut
            onStreamFinished: {
                const t = themeCurrentOut.text.trim();
                // Aplicar um tema leva alguns segundos: enquanto o sistema ainda
                // mostra o anterior, mantém a escolha e confere de novo.
                if (root.pendingTheme !== "" && t !== root.pendingTheme && root.pendingChecks < 6) {
                    root.pendingChecks++;
                    if (root.active) recheck.restart();
                    return;
                }
                root.pendingTheme = "";
                if (t !== "" && t !== "Unknown") root.currentTheme = t;
                Qt.callLater(grid.revealCurrent);
            }
        }
    }
    Process {
        id: fontListProc
        command: ["omarchy", "font", "list"]
        stdout: StdioCollector {
            id: fontListOut
            onStreamFinished: {
                root.fonts = root.lines(fontListOut.text);
                Qt.callLater(fontStrip.revealCurrent);
            }
        }
    }
    Process {
        id: fontCurrentProc
        command: ["omarchy", "font", "current"]
        stdout: StdioCollector {
            id: fontCurrentOut
            onStreamFinished: {
                root.currentFont = fontCurrentOut.text.trim();
                Qt.callLater(fontStrip.revealCurrent);
            }
        }
    }
    Process {
        id: cornersProc
        command: ["omarchy", "hyprland", "corners"]
        stdout: StdioCollector {
            id: cornersOut
            onStreamFinished: root.corners = cornersOut.text.trim()
        }
    }
    Process {
        id: transparencyProc
        command: ["omarchy", "hyprland", "window", "transparency"]
        stdout: StdioCollector {
            id: transparencyOut
            onStreamFinished: root.transparency = transparencyOut.text.trim()
        }
    }
    Process {
        id: backgroundProc
        command: ["omarchy", "theme", "bg", "current"]
        stdout: StdioCollector {
            id: backgroundOut
            onStreamFinished: root.background = backgroundOut.text.trim()
        }
    }

    // ---------- Componentes internos ----------
    // Chip em cápsula: selecionado fica na cor de destaque.
    component Chip: Item {
        id: chip
        property string icon: ""
        property string label: ""
        property string labelFont: ""
        property bool selected: false
        signal clicked()

        implicitWidth: chipRow.implicitWidth + 28
        implicitHeight: 32

        property color ink: selected ? root.bg : root.fg
        Behavior on ink { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }

        scale: chipTap.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: Commons.Style.duration(120); easing.type: Easing.OutCubic } }

        ContinuousRect {
            anchors.fill: parent
            radius: height / 2
            color: chip.selected ? root.accent : root.surface
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
        }
        ContinuousRect {
            anchors.fill: parent
            radius: height / 2
            color: root.hoverTint
            opacity: chipHover.hovered && !chip.selected ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(150); easing.type: Easing.OutCubic } }
        }
        Row {
            id: chipRow
            anchors.centerIn: parent
            width: Math.min(implicitWidth, chip.width - 16)
            spacing: 7
            Text {
                visible: chip.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                font.family: root.iconFont
                font.pixelSize: 13
                color: chip.ink
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, chip.width - 16 - (chip.icon !== "" ? 20 : 0))
                text: chip.label
                textFormat: Text.PlainText
                font.family: chip.labelFont !== "" ? chip.labelFont : Qt.application.font.family
                font.pixelSize: 13
                font.weight: chip.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                color: chip.ink
            }
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: chipTap; onTapped: chip.clicked() }
    }

    component SectionTitle: Text {
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: root.fg
    }

    // Valor atual à direita de um título (nome de tema, fonte, arquivo).
    component SectionValue: Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        font.pixelSize: 12
        elide: Text.ElideRight
        color: root.dim
    }

    // Cartão de seção: superfície sutil com cantos contínuos.
    component Card: Item {
        id: card
        default property alias body: cardBody.data
        Layout.fillWidth: true
        implicitHeight: cardBody.implicitHeight + 28
        ContinuousRect {
            anchors.fill: parent
            radius: 18
            color: root.surface
        }
        ColumnLayout {
            id: cardBody
            x: 14
            y: 14
            width: card.width - 28
            spacing: 10
        }
    }

    // Controle segmentado: a pílula de destaque desliza até a opção atual.
    component Segmented: Item {
        id: seg
        property var options: []   // [{ value, label }]
        property string current: ""
        signal picked(string value)

        Layout.fillWidth: true
        implicitHeight: 34

        readonly property int currentIndex: {
            for (let i = 0; i < options.length; i++)
                if (options[i].value === current) return i;
            return -1;
        }
        readonly property real segWidth: options.length > 0 ? (width - 6) / options.length : 0
        // Só anima depois do primeiro valor lido, para não deslizar ao abrir.
        property bool settled: false
        onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(() => seg.settled = true)

        ContinuousRect {
            anchors.fill: parent
            radius: height / 2
            color: root.surface
        }
        ContinuousRect {
            x: 3 + Math.max(0, seg.currentIndex) * seg.segWidth
            y: 3
            width: seg.segWidth
            height: seg.height - 6
            radius: height / 2
            color: root.accent
            opacity: seg.currentIndex >= 0 ? 1 : 0
            Behavior on x {
                enabled: seg.settled
                NumberAnimation { duration: Commons.Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
            }
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic } }
        }
        Row {
            x: 3
            y: 3
            Repeater {
                model: seg.options
                delegate: Item {
                    id: segItem
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === seg.currentIndex
                    width: seg.segWidth
                    height: seg.height - 6

                    ContinuousRect {
                        anchors.fill: parent
                        radius: height / 2
                        color: root.hoverTint
                        opacity: segHover.hovered && !segItem.selected ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(150); easing.type: Easing.OutCubic } }
                    }
                    Text {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 12)
                        horizontalAlignment: Text.AlignHCenter
                        text: segItem.modelData.label
                        font.pixelSize: 12
                        font.weight: segItem.selected ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        color: segItem.selected ? root.bg : root.fg
                        Behavior on color { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                    }
                    HoverHandler { id: segHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: seg.picked(segItem.modelData.value) }
                }
            }
        }
    }

    // Rótulo com ícone acima de um controle segmentado.
    component OptionLabel: Row {
        id: optLabel
        property string icon: ""
        property string label: ""
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: optLabel.icon
            font.family: root.iconFont
            font.pixelSize: 13
            color: root.dim
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: optLabel.label
            font.pixelSize: 13
            color: root.fg
        }
    }

    // ---------- Layout ----------
    ColumnLayout {
        id: content
        width: root.implicitWidth
        spacing: 12

        // Cabeçalho
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Chip {
                icon: "\uF053" // nf-fa-chevron_left
                label: strings.t("style.back")
                onClicked: root.navigate("control")
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "\uF1FC" // nf-fa-paint_brush
                font.family: root.iconFont
                font.pixelSize: 15
                color: root.accent
            }
            Text {
                Layout.rightMargin: 4
                text: strings.t("style.title")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: root.fg
            }
        }

        // ---------- Temas ----------
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 12
            SectionTitle { text: strings.t("style.theme") }
            SectionValue {
                text: root.pendingTheme !== "" ? strings.t("style.applying") : root.currentTheme
                color: root.pendingTheme !== "" ? root.dim : root.accent
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: grid.height

            GridView {
                id: grid
                width: parent.width
                height: root.themes.length === 0 ? 48
                        : Math.min(cellHeight * 2 + 28, Math.ceil(root.themes.length / 3) * cellHeight)
                cellWidth: Math.floor(width / 3)
                cellHeight: 112
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.themes

                // Rola até o tema atual sem animação ao abrir.
                function revealCurrent() {
                    if (root.currentThemeIndex >= 0 && count > root.currentThemeIndex)
                        positionViewAtIndex(root.currentThemeIndex, GridView.Contain);
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool isCurrent: modelData.name === root.currentTheme
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Item {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 4
                        scale: cellTap.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: Commons.Style.duration(120); easing.type: Easing.OutCubic } }

                        ContinuousRect {
                            anchors.fill: parent
                            radius: 14
                            color: cell.isCurrent ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : root.surface
                            borderWidth: 1.5
                            borderColor: cell.isCurrent ? root.accent : "transparent"
                            Behavior on color { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                            Behavior on borderColor { ColorAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                        }
                        ContinuousRect {
                            anchors.fill: parent
                            radius: 14
                            color: root.hoverTint
                            opacity: cellHover.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(150); easing.type: Easing.OutCubic } }
                        }

                        // Prévia recortada nos mesmos cantos contínuos do cartão:
                        // a imagem e a máscara viram texturas e o MultiEffect recorta.
                        Item {
                            id: thumb
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 6
                            height: 66

                            ContinuousRect {
                                anchors.fill: parent
                                radius: 10
                                color: root.surfaceStrong
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: preview.status !== Image.Ready
                                text: "\uF1FC" // nf-fa-paint_brush
                                font.family: root.iconFont
                                font.pixelSize: 16
                                color: root.dim
                            }

                            Item {
                                id: thumbSource
                                anchors.fill: parent
                                visible: false
                                layer.enabled: preview.status === Image.Ready
                                Image {
                                    id: preview
                                    anchors.fill: parent
                                    source: cell.modelData.preview !== "" ? "file://" + cell.modelData.preview.split("/").map(encodeURIComponent).join("/") : ""
                                    sourceSize.width: 256
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }
                            }
                            ContinuousRect {
                                id: thumbMask
                                anchors.fill: parent
                                radius: 10
                                visible: false
                                // Sempre ligada: um Shape numa camada ligada depois não repinta.
                                layer.enabled: true
                                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 1)
                            }
                            MultiEffect {
                                anchors.fill: parent
                                visible: preview.status === Image.Ready
                                source: thumbSource
                                maskEnabled: true
                                maskSource: thumbMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                                opacity: preview.status === Image.Ready ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic } }
                            }

                            // Selo do tema atual
                            ContinuousRect {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 5
                                width: 18
                                height: 18
                                radius: height / 2
                                color: root.accent
                                opacity: cell.isCurrent ? 1 : 0
                                scale: cell.isCurrent ? 1 : 0.97
                                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\uF00C" // nf-fa-check
                                    font.family: root.iconFont
                                    font.pixelSize: 10
                                    color: root.bg
                                }
                            }
                        }

                        Text {
                            anchors.top: thumb.bottom
                            anchors.topMargin: 7
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.name
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            font.weight: cell.isCurrent ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            color: cell.isCurrent ? root.accent : root.fg
                        }
                    }

                    HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: cellTap; onTapped: root.setTheme(cell.modelData.name) }
                }
            }

            // Indicador de rolagem
            ContinuousRect {
                visible: grid.contentHeight > grid.height + 1
                anchors.right: parent.right
                anchors.rightMargin: -7
                y: grid.visibleArea.yPosition * grid.height
                width: 3
                height: Math.max(20, grid.visibleArea.heightRatio * grid.height)
                radius: width / 2
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)
            }

            Text {
                anchors.centerIn: parent
                visible: root.themes.length === 0
                text: root.themesLoaded ? strings.t("style.themesEmpty") : strings.t("style.themesLoading")
                font.pixelSize: 13
                color: root.dim
            }
        }

        // ---------- Plano de fundo ----------
        Card {
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                SectionTitle { text: strings.t("style.background") }
                SectionValue { text: root.background }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Chip {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: "\uF04E" // nf-fa-forward
                    label: strings.t("style.backgroundNext")
                    onClicked: root.run(["omarchy", "theme", "bg", "next"])
                }
                Chip {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: "\uF03E" // nf-fa-image
                    label: strings.t("style.backgroundPick")
                    onClicked: root.runAfterClose(["omarchy", "theme", "bg-switcher"])
                }
                Chip {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    icon: "\uF009" // nf-fa-th_large
                    label: strings.t("style.themeSwitcher")
                    onClicked: root.runAfterClose(["omarchy", "theme", "switcher"])
                }
            }
        }

        // ---------- Fonte ----------
        Card {
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                SectionTitle { text: strings.t("style.font") }
                SectionValue { text: root.currentFont; color: root.accent }
            }
            Flickable {
                id: fontStrip
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                contentWidth: fontRow.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                // Traz a fonte atual para a área visível.
                function revealCurrent() {
                    const i = root.fonts.indexOf(root.currentFont);
                    const item = i >= 0 ? fontRepeater.itemAt(i) : null;
                    if (!item) return;
                    const maxX = Math.max(0, contentWidth - width);
                    if (item.x < contentX) contentX = item.x;
                    else if (item.x + item.width > contentX + width)
                        contentX = Math.min(maxX, item.x + item.width - width);
                }

                Row {
                    id: fontRow
                    spacing: 6
                    onPositioningComplete: fontStrip.revealCurrent()
                    Repeater {
                        id: fontRepeater
                        model: root.fonts
                        delegate: Chip {
                            required property string modelData
                            icon: "\uF031" // nf-fa-font
                            label: modelData
                            labelFont: modelData
                            selected: modelData === root.currentFont
                            onClicked: root.setFont(modelData)
                        }
                    }
                }

                // Roda do mouse rola a faixa na horizontal.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        const maxX = Math.max(0, fontStrip.contentWidth - fontStrip.width);
                        fontStrip.contentX = Math.max(0, Math.min(maxX, fontStrip.contentX - delta / 2));
                    }
                }
            }
        }

        // ---------- Janelas ----------
        Card {
            SectionTitle { text: strings.t("style.windows") }
            OptionLabel {
                Layout.topMargin: 2
                icon: "\uF096" // nf-fa-square_o
                label: strings.t("style.corners")
            }
            Segmented {
                current: root.corners
                options: [
                    { value: "theme", label: strings.t("style.corners.theme") },
                    { value: "sharp", label: strings.t("style.corners.sharp") },
                    { value: "rounded", label: strings.t("style.corners.rounded") }
                ]
                onPicked: (value) => root.setCorners(value)
            }
            OptionLabel {
                Layout.topMargin: 4
                icon: "\uF043" // nf-fa-tint
                label: strings.t("style.transparency")
            }
            Segmented {
                current: root.transparency
                options: [
                    { value: "opaque", label: strings.t("style.transparency.opaque") },
                    { value: "transparent", label: strings.t("style.transparency.transparent") },
                    { value: "glassy", label: strings.t("style.transparency.glassy") }
                ]
                onPicked: (value) => root.setTransparency(value)
            }
        }
    }
}
