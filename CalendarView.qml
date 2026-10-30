import QtQuick
import Quickshell
import qs.Commons as Commons

// Tempo (spec §3.4, view id "calendar"): só o mês, na largura da grade.
//
//   bloco 242   ‹ Mês de ano ›  (32) · iniciais (18) · 6 × 32 linhas de 7 × 76
//
// Contrato de estado: active, shell, fg/bg/accent/danger, metrics,
// keyboardMode, footerStatus, footerHints, handleKey(event) → bool,
// handleEscape() → bool, focusFirst(), closeRequested(), navigate(target).
// Teclas próprias: PgUp/PgDn trocam o mês, Home volta para hoje.
Item {
    id: root

    // Cores do tema (o host passa as mesmas).
    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted

    property bool active: false
    property var shell: null
    property Metrics metrics: Metrics {}
    property bool keyboardMode: false

    signal closeRequested()
    signal navigate(string target)

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    implicitWidth: metrics.content
    implicitHeight: grid.implicitHeight

    readonly property var loc: Qt.locale(Commons.I18n.formatLocale)
    readonly property bool rtl: Commons.I18n.rightToLeft
    // Primeiro dia da semana do idioma, em 0 = domingo (Qt usa 7 para domingo).
    readonly property int weekStart: ((loc.firstDayOfWeek % 7) + 7) % 7

    // ---------- Contrato ----------
    readonly property string footerStatus: root.todayText
    readonly property string footerHints: strings.t("hint.time")

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier);
        if (!mods) {
            if (event.key === Qt.Key_PageUp) { root.shiftMonth(-1); return true; }
            if (event.key === Qt.Key_PageDown) { root.shiftMonth(1); return true; }
            if (event.key === Qt.Key_Home) { root.goToday(); return true; }
        }
        return grid.handleKey(event);
    }
    function handleEscape() { return grid.handleEscape(); }
    function focusFirst() { prevButton.forceActiveFocus(Qt.TabFocusReason); return true; }

    // ---------- Data de hoje (só atualiza enquanto visível) ----------
    SystemClock {
        id: clock
        enabled: root.active
        precision: SystemClock.Minutes
    }
    readonly property int todayYear: clock.date.getFullYear()
    readonly property int todayMonth: clock.date.getMonth()
    readonly property int todayDay: clock.date.getDate()

    // ---------- Mês exibido ----------
    property int viewYear: todayYear
    property int viewMonth: todayMonth
    readonly property bool showingToday: viewYear === todayYear && viewMonth === todayMonth
    // Enquanto o usuário não navegar, a vista acompanha a virada do mês.
    property bool followToday: true

    function goToday() {
        const dir = (todayYear * 12 + todayMonth) - (viewYear * 12 + viewMonth);
        followToday = true;
        viewYear = todayYear;
        viewMonth = todayMonth;
        if (dir !== 0) monthSwap.play(dir > 0 ? 1 : -1);
    }
    function showMonth(year, month) {
        const dir = (year * 12 + month) - (viewYear * 12 + viewMonth);
        followToday = false;
        viewYear = year;
        viewMonth = month;
        if (dir !== 0) monthSwap.play(dir > 0 ? 1 : -1);
    }
    function shiftMonth(delta) {
        const d = new Date(viewYear, viewMonth + delta, 1);
        showMonth(d.getFullYear(), d.getMonth());
    }
    onTodayMonthChanged: if (followToday) goToday()
    onTodayYearChanged: if (followToday) goToday()

    function capitalize(s) {
        return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s;
    }

    readonly property string monthTitle: capitalize(
        new Date(viewYear, viewMonth, 1).toLocaleDateString(loc, strings.t("calendar.monthFormat")))

    readonly property string todayText: {
        // "quinta-feira" fica "quinta", mais curto no rodapé.
        const s = clock.date.toLocaleDateString(loc, strings.t("calendar.todayFormat")).replace("-feira", "");
        return strings.t("calendar.today").arg(s);
    }

    // Iniciais dos dias, na ordem do idioma; sábado e domingo ficam apagados.
    readonly property var weekdays: {
        const out = [];
        for (let i = 0; i < 7; i++) {
            const jsDay = (weekStart + i) % 7;
            out.push({ label: loc.dayName(jsDay, Locale.NarrowFormat), weekend: jsDay === 0 || jsDay === 6 });
        }
        return out;
    }

    // 42 células (6 semanas), cada uma com dia, mês e ano.
    readonly property var cells: {
        const first = new Date(viewYear, viewMonth, 1);
        const offset = (first.getDay() - weekStart + 7) % 7;
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(viewYear, viewMonth, 1 - offset + i);
            out.push({
                day: d.getDate(),
                month: d.getMonth(),
                year: d.getFullYear(),
                inMonth: d.getMonth() === viewMonth,
                weekend: d.getDay() === 0 || d.getDay() === 6
            });
        }
        return out;
    }

    onActiveChanged: {
        if (active) {
            goToday();
            Qt.callLater(root.focusFirst);
        }
    }
    Component.onCompleted: {
        goToday();
        if (active)
            Qt.callLater(root.focusFirst);
    }

    // ---------- Componentes internos ----------
    // Botão ‹ › do cabeçalho: pílula de 32 px, focável, com anel no modo teclado.
    component NavButton: Item {
        id: nav
        property string icon: ""
        signal clicked()

        width: 44
        height: 32
        activeFocusOnTab: true
        Accessible.role: Accessible.Button

        function activate() { nav.pulse(); nav.clicked(); return true; }
        property bool _pulsing: false
        function pulse() { nav._pulsing = true; navPulse.restart(); }
        Timer { id: navPulse; interval: Math.max(1, Commons.Style.duration(root.metrics.msPress)); onTriggered: nav._pulsing = false }

        Item {
            anchors.fill: parent
            scale: navTap.pressed || nav._pulsing ? root.metrics.pressScale : 1
            Behavior on scale { NumberAnimation { duration: Commons.Style.duration(root.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut } }

            ContinuousRect {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, navHover.hovered ? root.metrics.alphaHover : root.metrics.alphaIdle)
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
            }
            Icon {
                anchors.centerIn: parent
                name: nav.icon
                size: 20
                color: navHover.hovered || (nav.activeFocus && root.keyboardMode) ? root.accent : root.fg
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
            }
        }
        ContinuousRect {
            anchors.fill: parent
            anchors.margins: -root.metrics.ring
            radius: height / 2
            color: "transparent"
            borderWidth: root.metrics.ring
            borderColor: root.accent
            opacity: nav.activeFocus && root.keyboardMode ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msPress); easing.type: Easing.OutCubic } }
        }
        HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: navTap; onTapped: nav.activate() }
    }

    // ---------- Layout ----------
    PanelGrid {
        id: grid
        metrics: root.metrics
        strings: strings
        keyboardMode: root.keyboardMode
        fg: root.fg
        bg: root.bg
        accent: root.accent
        danger: root.danger
        muted: root.muted

        // ----- Bloco do calendário: 32 + 18 + 6 × 32 = 242 -----
        Item {
            id: calendar
            width: root.metrics.content
            height: 242

            // Itens focáveis do bloco (setas do PanelGrid passam por eles).
            function focusItems() { return [prevButton, nextButton]; }

            readonly property real cellWidth: 76
            readonly property real gridX: (width - 7 * cellWidth) / 2

            // Cabeçalho: ‹  Mês de ano  ›
            Item {
                id: header
                width: parent.width
                height: 32

                NavButton {
                    id: prevButton
                    x: calendar.gridX
                    icon: root.rtl ? "chevron_right" : "chevron_left"
                    Accessible.name: strings.t("calendar.previousMonth")
                    onClicked: root.shiftMonth(-1)
                }
                NavButton {
                    id: nextButton
                    x: parent.width - calendar.gridX - width
                    icon: root.rtl ? "chevron_left" : "chevron_right"
                    Accessible.name: strings.t("calendar.nextMonth")
                    onClicked: root.shiftMonth(1)
                }

                // Título: tocar volta para hoje quando outro mês está à mostra.
                Item {
                    id: title
                    anchors.centerIn: parent
                    width: titleRow.implicitWidth + 28
                    height: 32

                    ContinuousRect {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaIdle)
                        opacity: titleHover.hovered && !root.showingToday ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                    }
                    Row {
                        id: titleRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.monthTitle
                            textFormat: Text.PlainText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: root.fg
                        }
                        // Ponto: há um "voltar para hoje" disponível.
                        ContinuousRect {
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.showingToday ? 0 : 6
                            height: 6
                            radius: 3
                            color: root.accent
                            opacity: root.showingToday ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                        }
                    }
                    HoverHandler {
                        id: titleHover
                        cursorShape: root.showingToday ? Qt.ArrowCursor : Qt.PointingHandCursor
                    }
                    TapHandler { onTapped: root.goToday() }
                }
            }

            // Iniciais dos dias da semana (18 px)
            Row {
                x: calendar.gridX
                y: 32
                Repeater {
                    model: root.weekdays
                    Text {
                        required property var modelData
                        width: calendar.cellWidth
                        height: 18
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.label
                        textFormat: Text.PlainText
                        font.pixelSize: root.metrics.captionText
                        font.weight: Font.DemiBold
                        color: root.muted
                        opacity: modelData.weekend ? 0.6 : 1
                    }
                }
            }

            // Grade de 6 semanas (6 × 32). Ao trocar de mês, desliza de leve
            // no sentido da troca e reaparece (sem quique).
            Item {
                id: days
                x: calendar.gridX
                y: 50
                width: 7 * calendar.cellWidth
                height: 192
                clip: true

                Grid {
                    id: dayGrid
                    columns: 7
                    property real shift: 0
                    x: shift
                    Repeater {
                        model: root.cells
                        Item {
                            id: cell
                            required property var modelData
                            readonly property bool isToday: modelData.day === root.todayDay
                                                            && modelData.month === root.todayMonth
                                                            && modelData.year === root.todayYear
                            width: calendar.cellWidth
                            height: 32

                            ContinuousRect {
                                anchors.centerIn: parent
                                width: 48
                                height: 28
                                radius: height / 2
                                color: cell.isToday ? root.metrics.plate(root.accent)
                                     : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, root.metrics.alphaHover)
                                opacity: cell.isToday ? 1 : (cellHover.hovered ? 1 : 0)
                                Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(root.metrics.msState); easing.type: Easing.OutCubic } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: Commons.I18n.formatNumber(cell.modelData.day)
                                textFormat: Text.PlainText
                                font.pixelSize: 13
                                font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                                color: {
                                    if (cell.isToday)
                                        return root.metrics.glass === "opaque" ? root.bg : root.fg
                                    if (!cell.modelData.inMonth || cell.modelData.weekend)
                                        return root.muted
                                    return root.fg
                                }
                                opacity: cell.isToday || cell.modelData.inMonth ? 1 : 0.5
                            }

                            HoverHandler {
                                id: cellHover
                                cursorShape: cell.modelData.inMonth ? Qt.ArrowCursor : Qt.PointingHandCursor
                            }
                            // Tocar num dia de outro mês leva até aquele mês.
                            TapHandler {
                                onTapped: if (!cell.modelData.inMonth)
                                    root.showMonth(cell.modelData.year, cell.modelData.month)
                            }
                        }
                    }
                }

                ParallelAnimation {
                    id: monthSwap
                    property int dir: 1
                    function play(d) {
                        monthSwap.stop();
                        monthSwap.dir = d;
                        if (Commons.Style.duration(200) <= 0) return;
                        monthSwap.start();
                    }
                    NumberAnimation {
                        target: dayGrid
                        property: "shift"
                        from: 14 * monthSwap.dir
                        to: 0
                        duration: Commons.Style.duration(220)
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Commons.Style.easeOut
                    }
                    NumberAnimation {
                        target: dayGrid
                        property: "opacity"
                        from: 0.25
                        to: 1
                        duration: Commons.Style.duration(root.metrics.msFadeIn)
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
