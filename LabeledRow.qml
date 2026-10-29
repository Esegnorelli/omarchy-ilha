import QtQuick
import qs.Commons as Commons

// Linha fina de 44 px (spec §3.2): rótulo e valor em c1, controle em c2–c4.
//
// API pública:
//   variant: "segmented" | "slider" | "chips"
//   icon, label: string      rótulo em c1 (11 DemiBold muted) com ícone opcional
//   value: string            valor atual abaixo do rótulo (12 DemiBold fg)
//   options: [{ value, label, icon?, font? }]   segmentos (até 3, um por coluna) ou chips
//   current: string          valor escolhido (segmented/chips)
//   sliderValue: real 0–1, step: real (0.05), dimmed: bool (valor e trilho apagados, ex. mudo)
//   keyRow: int              -2 automático (só segmented tem tecla), -1, 0/1/2
//   keyboardMode, strings, fg, bg, accent, danger, muted, metrics
// Sinais:
//   picked(string value)     segmento ou chip escolhido
//   moved(real value)        slider arrastado/tocado/setas/roda
//   labelTapped()            toque no rótulo (por exemplo mudo no volume)
// Funções:
//   next() / prev()          chips: escolhe o vizinho; slider: ± step; segmented: vizinho
//   focusItems() → [Item]    segmentos, ou o slider/chips (sem letra; setas ←→ mudam o valor)
Item {
    id: lrow

    property string variant: "segmented"
    property string icon: ""
    property string label: ""
    property string value: ""
    property var options: []
    property string current: ""
    property real sliderValue: 0
    property real step: 0.05
    property bool dimmed: false
    property int keyRow: -2

    property bool keyboardMode: false
    property var strings: null
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property Metrics metrics: Metrics {}

    property int autoKeyRow: -1
    readonly property int resolvedKeyRow: keyRow >= -1 ? keyRow : autoKeyRow
    readonly property bool keyable: variant === "segmented"

    signal picked(string value)
    signal moved(real value)
    signal labelTapped()

    implicitWidth: metrics.content
    implicitHeight: metrics.slim
    width: implicitWidth

    readonly property int currentIndex: {
        for (let i = 0; i < options.length; i++)
            if (options[i].value === current) return i;
        return -1;
    }
    readonly property real controlX: metrics.colX(1, 4)
    readonly property real controlWidth: metrics.spanWidth(3, 4)

    function next() { lrow._step(1); }
    function prev() { lrow._step(-1); }
    function _step(d) {
        if (lrow.variant === "slider") {
            lrow.moved(Math.max(0, Math.min(1, Math.round((lrow.sliderValue + d * lrow.step) * 100) / 100)));
            return;
        }
        if (lrow.options.length === 0) return;
        const i = lrow.currentIndex < 0 ? (d > 0 ? 0 : lrow.options.length - 1)
                                        : Math.max(0, Math.min(lrow.options.length - 1, lrow.currentIndex + d));
        if (i !== lrow.currentIndex) lrow.picked(lrow.options[i].value);
    }

    function focusItems() {
        if (lrow.variant === "slider") return [sliderBox];
        if (lrow.variant === "chips") return [chipsBox];
        const out = [];
        for (let i = 0; i < segRepeater.count; i++) {
            const it = segRepeater.itemAt(i);
            if (it && it.visible) out.push(it);
        }
        return out;
    }

    // Seta ‹ › do rolador de chips.
    component Arrow: Item {
        id: arrow
        property string icon: ""
        property bool enabledArrow: true
        signal tapped()
        width: 28
        height: 32
        anchors.verticalCenter: parent.verticalCenter
        opacity: enabledArrow ? 1 : 0.35
        Accessible.role: Accessible.Button
        ContinuousRect {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, lrow.metrics.alphaHover)
            opacity: arrowHover.hovered && arrow.enabledArrow ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
        }
        Icon {
            anchors.centerIn: parent
            name: arrow.icon
            size: 18
            color: arrowHover.hovered && arrow.enabledArrow ? lrow.accent : lrow.fg
        }
        scale: arrowTap.pressed ? lrow.metrics.pressScale : 1
        Behavior on scale { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut } }
        HoverHandler { id: arrowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: arrowTap; onTapped: if (arrow.enabledArrow) arrow.tapped() }
    }

    // ---------- c1: rótulo e valor ----------
    Item {
        id: labelArea
        width: lrow.metrics.col
        height: parent.height

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Icon {
                id: labelIcon
                visible: lrow.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: lrow.icon
                size: 18
                filled: labelHover.hovered
                color: labelHover.hovered ? lrow.accent : lrow.fg
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: labelArea.width - 4 - (labelIcon.visible ? labelIcon.width + 8 : 0) - 4
                spacing: 0
                Text {
                    width: parent.width
                    text: lrow.label
                    textFormat: Text.PlainText
                    font.pixelSize: lrow.metrics.captionText
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: lrow.muted
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: lrow.value
                    textFormat: Text.PlainText
                    font.pixelSize: lrow.metrics.tileLabel
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: lrow.dimmed ? lrow.muted : lrow.fg
                }
            }
        }
        HoverHandler { id: labelHover; enabled: lrow.icon !== ""; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: lrow.icon !== ""; onTapped: lrow.labelTapped() }
    }

    // ---------- Segmentos: um por coluna (c2, c3, c4) ----------
    Repeater {
        id: segRepeater
        model: lrow.variant === "segmented" ? lrow.options.slice(0, 3) : []
        delegate: Tile {
            required property var modelData
            required property int index
            x: lrow.metrics.colX(1 + index, 4)
            y: (lrow.height - height) / 2
            width: lrow.metrics.col
            height: lrow.metrics.segment
            compact: true
            icon: modelData.icon || ""
            label: modelData.label || ""
            on: index === lrow.currentIndex
            available: modelData.available !== false
            keyRow: lrow.resolvedKeyRow
            keyCol: 1 + index
            keyboardMode: lrow.keyboardMode
            strings: lrow.strings
            fg: lrow.fg
            bg: lrow.bg
            accent: lrow.accent
            danger: lrow.danger
            muted: lrow.muted
            metrics: lrow.metrics
            onActivated: lrow.picked(modelData.value)
        }
    }

    // ---------- Slider (c2–c4) ----------
    Item {
        id: sliderBox
        visible: lrow.variant === "slider"
        x: lrow.controlX
        width: lrow.controlWidth
        height: parent.height
        activeFocusOnTab: visible
        Accessible.role: Accessible.Slider
        Accessible.name: lrow.label

        function activate() { return false; }
        function handleArrow(key) {
            if (key === Qt.Key_Left) { lrow.prev(); return true; }
            if (key === Qt.Key_Right) { lrow.next(); return true; }
            return false;
        }
        function setFromX(px) {
            lrow.moved(Math.max(0, Math.min(1, (px - knob.width / 2) / (track.width - knob.width))));
        }

        ContinuousRect {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            radius: 3
            color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, lrow.metrics.alphaHover)

            ContinuousRect {
                width: Math.max(height, knob.x + knob.width / 2)
                height: parent.height
                radius: 3
                color: lrow.dimmed ? lrow.muted : lrow.accent
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
            }
            ContinuousRect {
                id: knob
                width: 16
                height: 16
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(1, lrow.sliderValue)) * (track.width - width)
                color: lrow.fg
                scale: sliderHover.hovered || sliderDrag.active ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
                Behavior on x {
                    enabled: !sliderDrag.active
                    NumberAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic }
                }
            }
        }

        ContinuousRect {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            anchors.leftMargin: -lrow.metrics.ring
            anchors.rightMargin: -lrow.metrics.ring
            radius: lrow.metrics.rowRadius
            color: "transparent"
            borderWidth: lrow.metrics.ring
            borderColor: lrow.accent
            opacity: sliderBox.activeFocus && lrow.keyboardMode ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msPress); easing.type: Easing.OutCubic } }
        }

        HoverHandler { id: sliderHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: eventPoint => sliderBox.setFromX(eventPoint.position.x - track.x) }
        DragHandler {
            id: sliderDrag
            target: null
            yAxis.enabled: false
            onCentroidChanged: if (active) sliderBox.setFromX(centroid.position.x - track.x)
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => { if (event.angleDelta.y > 0) lrow.next(); else if (event.angleDelta.y < 0) lrow.prev(); }
        }
    }

    // ---------- Chips com ‹ › (c2–c4) ----------
    Item {
        id: chipsBox
        visible: lrow.variant === "chips"
        x: lrow.controlX
        width: lrow.controlWidth
        height: parent.height
        activeFocusOnTab: visible
        Accessible.role: Accessible.List
        Accessible.name: lrow.label

        function activate() { return false; }
        // Cada passo aplica a opção (ex.: font set): segurar a seta não
        // dispara uma rajada.
        function handleArrow(key, event) {
            if (key !== Qt.Key_Left && key !== Qt.Key_Right) return false;
            if (event && event.isAutoRepeat) return true;
            if (key === Qt.Key_Left) lrow.prev();
            else lrow.next();
            return true;
        }

        Arrow {
            id: prevArrow
            x: 0
            icon: "chevron_left"
            enabledArrow: lrow.currentIndex > 0
            Accessible.name: lrow.strings ? lrow.strings.t("grid.previous") : ""
            onTapped: lrow.prev()
        }
        Arrow {
            id: nextArrow
            x: parent.width - width
            icon: "chevron_right"
            enabledArrow: lrow.currentIndex < lrow.options.length - 1
            Accessible.name: lrow.strings ? lrow.strings.t("grid.next") : ""
            onTapped: lrow.next()
        }

        ListView {
            id: chipList
            anchors.left: prevArrow.right
            anchors.right: nextArrow.left
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            clip: true
            orientation: ListView.Horizontal
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            model: lrow.variant === "chips" ? lrow.options : []
            currentIndex: lrow.currentIndex
            highlightFollowsCurrentItem: true
            highlightRangeMode: ListView.ApplyRange
            preferredHighlightBegin: 32
            preferredHighlightEnd: width - 32
            highlightMoveDuration: Commons.Style.duration(220)
            highlightResizeDuration: Commons.Style.duration(220)
            highlight: ContinuousRect {
                radius: height / 2
                color: lrow.accent
            }

            delegate: Item {
                id: chip
                required property var modelData
                required property int index
                readonly property bool selected: index === lrow.currentIndex
                width: chipText.implicitWidth + 28
                height: 32

                ContinuousRect {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, chipHover.hovered ? lrow.metrics.alphaHover : lrow.metrics.alphaIdle)
                    opacity: chip.selected ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
                }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData.label || ""
                    textFormat: Text.PlainText
                    font.family: chip.modelData.font ? chip.modelData.font : Qt.application.font.family
                    font.pixelSize: lrow.metrics.tileLabel
                    font.weight: chip.selected ? Font.DemiBold : Font.Normal
                    color: chip.selected ? lrow.bg : lrow.fg
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
                }
                scale: chipTap.pressed ? lrow.metrics.pressScale : 1
                Behavior on scale { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut } }
                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: chipTap; onTapped: lrow.picked(chip.modelData.value) }
            }
        }

        ContinuousRect {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            anchors.leftMargin: -lrow.metrics.ring
            anchors.rightMargin: -lrow.metrics.ring
            radius: lrow.metrics.rowRadius
            color: "transparent"
            borderWidth: lrow.metrics.ring
            borderColor: lrow.accent
            opacity: chipsBox.activeFocus && lrow.keyboardMode ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msPress); easing.type: Easing.OutCubic } }
        }
    }
}
