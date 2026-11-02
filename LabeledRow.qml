import QtQuick
import qs.Commons as Commons

// Linha fina de 44 px (spec §3.2): rótulo e valor em c1, controle em c2–c4.
// A variante "bar" é um cartão de 80 px: título e valor no alto e uma barra
// grossa de 32 px embaixo, com o ícone dentro do preenchimento (o Volume).
//
// API pública:
//   variant: "segmented" | "slider" | "chips" | "bar"
//   icon, label: string      rótulo em c1 (11 DemiBold muted) com ícone opcional;
//                            no bar o rótulo é o título (12 DemiBold fg) e o ícone vai na barra
//   value: string            valor atual abaixo do rótulo (12 DemiBold fg); no bar, 11 muted à direita
//   options: [{ value, label, icon?, font? }]   segmentos (até 3, um por coluna) ou chips
//   current: string          valor escolhido (segmented/chips)
//   sliderValue: real 0–1, step: real (0.05), dimmed: bool (valor e trilho apagados, ex. mudo)
//   stepBase: real           de onde ± step parte (padrão sliderValue); o passo não passa de
//                            max(1, stepBase), assim um volume acima de 100% não cai sozinho
//   hasMore: bool            bar: botão › no canto (moreTapped); Enter na barra faz o mesmo
//   keyRow: int              -2 automático (só segmented tem tecla), -1, 0/1/2
//   keyboardMode, focusVisible, strings, fg, bg, accent, danger, muted, metrics, fontFamily
// Sinais:
//   picked(string value)     segmento ou chip escolhido
//   moved(real value)        slider/barra arrastado/tocado/setas/roda
//   labelTapped()            toque no rótulo, ou no ícone da barra (por exemplo mudo no volume)
//   moreTapped()             bar com hasMore: o botão › ou Enter
// Funções:
//   next() / prev()          chips: escolhe o vizinho; slider/bar: ± step; segmented: vizinho
//   focusItems() → [Item]    segmentos, ou o slider/barra/chips (sem letra; setas ←→ mudam o valor)
// A roda acumula angleDelta e anda um passo a cada 120 (touchpad não dispara rajadas).
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
    property real stepBase: sliderValue
    property bool hasMore: false
    property bool dimmed: false
    property int keyRow: -2

    property bool keyboardMode: false
    property bool focusVisible: false
    property var strings: null
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property string fontFamily: Commons.Style.fontFamily
    property Metrics metrics: Metrics {}

    property int autoKeyRow: -1
    readonly property int resolvedKeyRow: keyRow >= -1 ? keyRow : autoKeyRow
    readonly property bool keyable: variant === "segmented"

    signal picked(string value)
    // Chips com stepPreview: setas e [ ] só marcam a opção (previewed);
    // Enter ou o clique aplicam (picked).
    property bool stepPreview: false
    signal previewed(string value)
    signal moved(real value)
    signal labelTapped()
    signal moreTapped()

    implicitWidth: metrics.content
    implicitHeight: variant === "bar" ? 80 : metrics.slim
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
        if (lrow.variant === "slider" || lrow.variant === "bar") {
            const cap = Math.max(1, lrow.stepBase);
            lrow.moved(Math.max(0, Math.min(cap, Math.round((lrow.stepBase + d * lrow.step) * 100) / 100)));
            return;
        }
        if (lrow.options.length === 0) return;
        const i = lrow.currentIndex < 0 ? (d > 0 ? 0 : lrow.options.length - 1)
                                        : Math.max(0, Math.min(lrow.options.length - 1, lrow.currentIndex + d));
        if (i === lrow.currentIndex) return;
        if (lrow.stepPreview && lrow.variant === "chips") lrow.previewed(lrow.options[i].value);
        else lrow.picked(lrow.options[i].value);
    }

    function focusItems() {
        if (lrow.variant === "slider") return [sliderBox];
        if (lrow.variant === "bar") return [barBox];
        if (lrow.variant === "chips") return [chipsBox];
        const out = [];
        for (let i = 0; i < segRepeater.count; i++) {
            const it = segRepeater.itemAt(i);
            if (it && it.visible) out.push(it);
        }
        return out;
    }

    // Roda: um passo a cada 120 de angleDelta; trocar de sentido zera a soma.
    property real _wheelAcc: 0
    function _wheel(event) {
        const dy = event.angleDelta.y;
        if (dy === 0) return;
        if (lrow._wheelAcc !== 0 && (dy > 0) !== (lrow._wheelAcc > 0)) lrow._wheelAcc = 0;
        lrow._wheelAcc += dy;
        while (Math.abs(lrow._wheelAcc) >= 120) {
            const dir = lrow._wheelAcc > 0 ? 1 : -1;
            lrow._wheelAcc -= dir * 120;
            lrow._step(dir);
        }
    }

    // Anel de foco do teclado: 1 px accent a 55%, só depois de navegar.
    component FocusRing: ContinuousRect {
        property bool shown: false
        color: "transparent"
        borderWidth: 1
        borderColor: Qt.rgba(lrow.accent.r, lrow.accent.g, lrow.accent.b, 0.55)
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msPress); easing.type: Easing.OutCubic } }
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
            radius: lrow.metrics.fit(height / 2)
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
        visible: lrow.variant !== "bar"
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
                    font.family: lrow.fontFamily
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
                    font.family: lrow.fontFamily
                    font.pixelSize: lrow.metrics.tileLabel
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: lrow.dimmed ? lrow.muted : lrow.fg
                }
            }
        }
        HoverHandler { id: labelHover; enabled: lrow.icon !== "" && labelArea.visible; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: lrow.icon !== "" && labelArea.visible; onTapped: lrow.labelTapped() }
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
            focusVisible: lrow.focusVisible
            fontFamily: lrow.fontFamily
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
            radius: lrow.metrics.fit(3)
            color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, lrow.metrics.alphaHover)

            ContinuousRect {
                width: Math.max(height, knob.x + knob.width / 2)
                height: parent.height
                radius: lrow.metrics.fit(3)
                color: lrow.dimmed ? lrow.muted : lrow.accent
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
            }
            ContinuousRect {
                id: knob
                width: 16
                height: 16
                radius: lrow.metrics.fit(8)
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

        FocusRing {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            radius: lrow.metrics.rowRadius
            shown: sliderBox.activeFocus && lrow.focusVisible
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
            onWheel: event => lrow._wheel(event)
        }
    }

    // ---------- Barra (variant "bar"): cartão de 80 px ----------
    Item {
        id: barBox
        visible: lrow.variant === "bar"
        anchors.fill: parent
        activeFocusOnTab: visible
        Accessible.role: Accessible.Slider
        Accessible.name: lrow.label

        readonly property real fraction: Math.max(0, Math.min(1, lrow.sliderValue))

        // Enter na barra abre o "mais" (subpágina), quando houver.
        function activate() {
            if (!lrow.hasMore) return false;
            lrow.moreTapped();
            return true;
        }
        function handleArrow(key) {
            if (key === Qt.Key_Left) { lrow.prev(); return true; }
            if (key === Qt.Key_Right) { lrow.next(); return true; }
            return false;
        }
        function setFromX(px) {
            lrow.moved(Math.max(0, Math.min(1, px / Math.max(1, bar.width))));
        }

        ContinuousRect {
            anchors.fill: parent
            radius: lrow.metrics.cardRadius
            color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, lrow.metrics.alphaIdle)
        }

        // Cabeçalho: título à esquerda, valor e › à direita.
        Text {
            id: barTitle
            x: 14
            y: 12
            width: Math.min(implicitWidth, barValue.x - x - 8)
            text: lrow.label
            textFormat: Text.PlainText
            font.family: lrow.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            color: lrow.fg
        }
        Text {
            id: barValue
            anchors.right: moreButton.visible ? moreButton.left : parent.right
            anchors.rightMargin: moreButton.visible ? 8 : 14
            anchors.verticalCenter: barTitle.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: lrow.value
            textFormat: Text.PlainText
            font.family: lrow.fontFamily
            font.pixelSize: 11
            font.features: ({ "tnum": 1 })
            color: lrow.muted
        }
        IconButton {
            id: moreButton
            visible: lrow.hasMore
            solid: true
            size: 26
            iconSize: 16
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: barTitle.verticalCenter
            icon: "chevron_right"
            fg: lrow.fg
            accent: lrow.accent
            muted: lrow.muted
            label: lrow.label
            onTapped: lrow.moreTapped()
        }

        // Barra grossa: trilho neutro, preenchimento accent sólido com o ícone.
        ContinuousRect {
            id: bar
            x: 10
            y: 38
            width: parent.width - 20
            height: 32
            radius: lrow.metrics.fit(16)
            color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, barHover.hovered || barDrag.active ? 0.12 : 0.08)
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }

            ContinuousRect {
                id: barFill
                height: parent.height
                width: Math.max(height, barBox.fraction * bar.width)
                radius: lrow.metrics.fit(16)
                color: lrow.dimmed ? lrow.muted : lrow.accent
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
                Behavior on width {
                    enabled: !barDrag.active
                    NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                }
            }
            Icon {
                id: barIcon
                visible: lrow.icon !== ""
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                name: lrow.icon
                size: 18
                filled: true
                color: lrow.dimmed ? lrow.fg : lrow.bg
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
            }

            HoverHandler { id: barHover; cursorShape: Qt.PointingHandCursor }
            // Um toque só: no ícone (os primeiros 38 px) é o rótulo (mudo);
            // no resto, posiciona a barra.
            TapHandler {
                onTapped: eventPoint => {
                    const px = eventPoint.position.x;
                    if (barIcon.visible && px < barIcon.x + barIcon.width + 10) lrow.labelTapped();
                    else barBox.setFromX(px);
                }
            }
            DragHandler {
                id: barDrag
                target: null
                yAxis.enabled: false
                onCentroidChanged: if (active) barBox.setFromX(centroid.position.x)
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => lrow._wheel(event)
            }
        }

        FocusRing {
            anchors.fill: parent
            radius: lrow.metrics.cardRadius
            shown: barBox.activeFocus && lrow.focusVisible
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

        function activate() {
            if (!lrow.stepPreview || lrow.currentIndex < 0) return false;
            lrow.picked(lrow.options[lrow.currentIndex].value);
            return true;
        }
        // Segurar a seta não dispara uma rajada.
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
            // A opção escolhida desliza para o meio; as vizinhas somem
            // suavemente nas bordas (chipFade) em vez de cortar seco.
            function recenter(animated) {
                const it = itemAtIndex(currentIndex);
                if (!it || width <= 0) return;
                const max = Math.max(0, contentWidth - width);
                const to = Math.max(0, Math.min(max, it.x + it.width / 2 - width / 2)) + originX;
                if (animated && Commons.Style.duration(1) > 0) {
                    centerAnim.to = to;
                    centerAnim.restart();
                } else {
                    contentX = to;
                }
            }
            onCurrentIndexChanged: Qt.callLater(recenter, true)
            onWidthChanged: Qt.callLater(recenter, false)
            onCountChanged: Qt.callLater(recenter, false)
            Component.onCompleted: Qt.callLater(recenter, false)
            NumberAnimation on contentX {
                id: centerAnim
                running: false
                duration: Commons.Style.duration(220)
                easing.type: Easing.OutCubic
            }
            highlightMoveDuration: Commons.Style.duration(220)
            highlightResizeDuration: Commons.Style.duration(220)
            // Seleção é um preenchimento neutro mais claro, não accent.
            highlight: ContinuousRect {
                radius: lrow.metrics.fit(height / 2)
                color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, lrow.metrics.alphaPressed)
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
                    radius: lrow.metrics.fit(height / 2)
                    color: Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, chipHover.hovered ? lrow.metrics.alphaHover : lrow.metrics.alphaIdle)
                    opacity: chip.selected ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
                }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData.label || ""
                    textFormat: Text.PlainText
                    font.family: chip.modelData.font ? chip.modelData.font : lrow.fontFamily
                    font.pixelSize: lrow.metrics.tileLabel
                    font.weight: chip.selected ? Font.DemiBold : Font.Normal
                    color: chip.selected ? lrow.fg : Qt.rgba(lrow.fg.r, lrow.fg.g, lrow.fg.b, 0.78)
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(lrow.metrics.msState); easing.type: Easing.OutCubic } }
                }
                scale: chipTap.pressed ? lrow.metrics.pressScale : 1
                Behavior on scale { NumberAnimation { duration: Commons.Style.duration(lrow.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut } }
                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: chipTap; onTapped: lrow.picked(chip.modelData.value) }
            }
        }

        // Esmaecimento nas bordas: degradê da cor do fundo por cima dos chips.
        Item {
            id: chipFade
            anchors.fill: chipList
            readonly property real edge: 22
            Rectangle {
                width: chipFade.edge
                height: parent.height
                visible: chipList.contentX - chipList.originX > 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: lrow.metrics.plate(lrow.bg) }
                    GradientStop { position: 1; color: Qt.rgba(lrow.bg.r, lrow.bg.g, lrow.bg.b, 0) }
                }
            }
            Rectangle {
                x: parent.width - width
                width: chipFade.edge
                height: parent.height
                visible: chipList.contentX - chipList.originX < chipList.contentWidth - chipList.width - 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(lrow.bg.r, lrow.bg.g, lrow.bg.b, 0) }
                    GradientStop { position: 1; color: lrow.metrics.plate(lrow.bg) }
                }
            }
        }

        FocusRing {
            anchors.fill: parent
            anchors.topMargin: 4
            anchors.bottomMargin: 4
            radius: lrow.metrics.rowRadius
            shown: chipsBox.activeFocus && lrow.focusVisible
        }
    }
}
