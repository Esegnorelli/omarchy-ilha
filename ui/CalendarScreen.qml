pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
import "Motion.js" as Motion

// Calendário (screens: "calendar"): o mês, a barra do ano e a da vida, os
// relógios de outros fusos e os lembretes. 514 x 420 (theme.screenSize),
// cap 30, um fade só (como a Central e a Mídia). Dono: agente do Calendário.
// A lógica vem do painel de relógio do Omarchy (plugins/panels/clock:
// Panel.qml e Model.js) e do calendário da 1.x; o visual é o da 2.x.
//
//   cabeçalho  y 10..44   Mês de ano (17/600)          [hoje] [‹] [›]  (30)
//   barras     y 50..66   2026 ━━━━━━━━ 84 %    VIDA ━━━━━━━━ 53 %
//   dias       y 74..88   S | DOM. SEG. TER. …  (10.5/600, a semana do idioma)
//   grade      y 90..270  6 x 30; semana ISO (26) | fio | 7 colunas de 64
//   fusos      y 278..306 até 4 cidades do elsewhen (some sem cidades)
//   lembretes  y 314..404 cartão (raio 20, card): título, [Definir lembrete],
//                         2 linhas de 22 (3 sem a faixa de fusos, y 280)
//
// - Grade: sempre 6 semanas (Model.monthGrid, andando em UTC); cada linha
//   leva a semana ISO da quinta-feira. Hoje: círculo accent (28) com o número
//   onAccent; o dia escolhido: um anel que desliza de dia a dia (salta ao
//   trocar de mês); outros meses: inkFaint a 50 %; fim de semana: inkMuted.
//   Um ponto embaixo marca o dia com lembrete.
// - O dia escolhido está sempre no mês à mostra: trocar de mês leva o dia
//   junto (o mesmo número, limitado ao fim do mês); clicar num dia de outro
//   mês vai até lá. A troca de mês desliza 14 px no sentido dela e volta a
//   aparecer (220 ms, como a 1.x).
// - Começo da semana, barra do ano e barra da vida: as contas do Model.js,
//   com a configuração da entrada omarchy.clock do barConfig (weekStartDay,
//   birthYear, lifeExpectancy); sem birthYear a barra da vida some e a do
//   ano ocupa a linha toda.
// - Lembretes (CalendarSvc: omarchy-reminder show --json): os do dia
//   escolhido, com a data no título; sem nenhum nesse dia, os próximos
//   ("Próximos lembretes"); sem nenhum, "Nenhum lembrete pendente".
//   "Definir lembrete" fecha a ilha e roda o fluxo do Omarchy (o comando do
//   menu, omarchy-reminder -i, que faz shell summon omarchy.reminders) 180 ms
//   depois. ILHA_DEV=1: só registra no log.
// - Teclas: setas movem o dia (Esquerda/Direita pela tela; no RTL a Direita
//   volta um dia), PgUp/PgDn trocam o mês (com Shift, o ano), Home volta para
//   hoje, End vai ao último dia do mês, Tab / Shift+Tab passam pela grade,
//   hoje, ‹, › e Definir lembrete; Enter / Espaço ativam o botão focado; Esc
//   fecha (a janela cuida dele). Anéis de foco só no modo teclado.
// - Mouse: clique escolhe o dia; a roda sobre a grade troca o mês.
// - RTL: a IslandWindow espelha as âncoras; a grade, a coluna das semanas e
//   os fusos usam x espelhado à mão; as setas viram (flip).
// - Nada roda antes de opened() nem depois de closed() (o serviço só lê com
//   a tela aberta; a hora vem do island.now, alinhado ao minuto).
Item {
    id: root

    // ---- Contrato de tela ----
    property var island: null
    property Theme theme: null
    property var strings: null
    property var morph: null
    property bool current: false
    property bool keyboardMode: false
    property var payload: null
    property real edgeLeft: 0
    property real edgeRight: root.implicitWidth
    property var heightMotion: "panel"
    property bool snapping: false
    property list<Item> headerItems
    property list<Item> bodyItems
    signal navigate(string id, var payload)
    signal closeRequested()

    function opened(payload) {
        root.snapping = true;
        priv.ringSnap = true;
        priv.openedAt = Date.now();
        priv.live = true;
        svc.live = true;
        svc.refresh();
        priv.focus = "grid";
        priv.hover = -1;
        priv.wheelAcc = 0;
        slide.stop();
        days.shift = 0;
        days.opacity = 1;
        // payload.date ("yyyy-MM-dd") abre num dia; sem ele, hoje.
        const m = payload && typeof payload.date === "string" ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(payload.date) : null;
        if (m)
            root.select(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), false);
        else
            root.goToday(false);
        Qt.callLater(() => {
            root.snapping = false;
            priv.ringSnap = false;
        });
    }

    function closed() {
        priv.live = false;
        svc.live = false;
        priv.hover = -1;
        slide.stop();
    }

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods !== 0)
            return false;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        // Esquerda/Direita andam pela tela: no RTL a Direita volta um dia.
        const ahead = root.rtl ? -1 : 1;
        switch (event.key) {
        case Qt.Key_Left:
            priv.focus = "grid";
            root.moveDays(-ahead);
            return true;
        case Qt.Key_Right:
            priv.focus = "grid";
            root.moveDays(ahead);
            return true;
        case Qt.Key_Up:
            priv.focus = "grid";
            root.moveDays(-7);
            return true;
        case Qt.Key_Down:
            priv.focus = "grid";
            root.moveDays(7);
            return true;
        case Qt.Key_PageUp:
            root.moveMonths(shift ? -12 : -1);
            return true;
        case Qt.Key_PageDown:
            root.moveMonths(shift ? 12 : 1);
            return true;
        case Qt.Key_Home:
            priv.focus = "grid";
            root.goToday(true);
            return true;
        case Qt.Key_End:
            priv.focus = "grid";
            root.select(priv.selY, priv.selM, svc.daysInMonth(priv.selY, priv.selM), true);
            return true;
        case Qt.Key_Tab:
            root.cycleFocus(shift ? -1 : 1);
            return true;
        case Qt.Key_Backtab:
            root.cycleFocus(-1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (priv.focus === "grid")
                return false;
            if (!event.isAutoRepeat)
                root.activate(priv.focus);
            return true;
        }
        return false;
    }

    // Nada para desfazer aqui: o Esc fecha a ilha (pela janela).
    function handleEscape() {
        return false;
    }

    readonly property var dims: root.theme && root.island ? root.theme.screenSize("calendar", root.island.screenGeometry(root.island.screenOutput)) : ({ w: 514, h: 420, k: 0 })
    implicitWidth: root.dims.w
    implicitHeight: root.dims.h

    Accessible.role: Accessible.Grouping
    Accessible.name: root.tr("picker.calendar")

    // ---- Medidas ----
    readonly property real pad: 16
    readonly property real contentW: root.implicitWidth - 2 * root.pad
    readonly property real headerY: 10
    readonly property real headerH: 34
    readonly property real btn: 30
    readonly property real railY: 50
    readonly property real railH: 16
    readonly property real railGap: 20
    readonly property real weekdayY: 74
    readonly property real weekdayH: 14
    readonly property real gridY: 90
    readonly property real rowH: 30
    readonly property real dayD: 28
    // Coluna das semanas ISO e o vão (com o fio no meio) antes dos dias.
    readonly property real weekColW: 26
    readonly property real gutter: 8
    readonly property real daysX: root.weekColW + root.gutter
    readonly property real cellW: (root.contentW - root.daysX) / 7
    readonly property real gridH: 6 * root.rowH
    readonly property real worldY: root.gridY + root.gridH + 8
    readonly property real worldH: 28
    readonly property real cardY: root.hasWorld ? root.worldY + root.worldH + 8 : root.gridY + root.gridH + 10
    readonly property real cardH: Math.max(0, root.implicitHeight - root.pad - root.cardY)
    readonly property real cardRadius: 20
    readonly property real cardTop: 40
    readonly property real remRowH: 22
    readonly property int maxRows: Math.max(1, Math.floor((root.cardH - root.cardTop - 4) / root.remRowH))

    readonly property bool rtl: !!root.theme && root.theme.rtl

    // ---- Serviço próprio ----
    CalendarSvc {
        id: svc
        island: root.island
    }

    // ---- Estado ----
    QtObject {
        id: priv
        property bool live: false
        // O dia escolhido (mês de 0 a 11); o mês à mostra é sempre o dele.
        property int selY: 2026
        property int selM: 0
        property int selD: 1
        // Segue hoje na virada do dia enquanto o escolhido for hoje.
        property bool followToday: true
        // grid | today | prev | next | remind
        property string focus: "grid"
        property int hover: -1
        property real wheelAcc: 0
        property real wheelAt: 0
        // O anel salta (sem deslizar) na troca de mês e na abertura.
        property bool ringSnap: true
        property real openedAt: 0
    }

    readonly property var loc: Qt.locale(Commons.I18n.formatLocale)
    readonly property var nowDate: root.island && root.island.now ? root.island.now : new Date()
    // O instante de agora para "faltam" e os fusos: o de opened() e, depois,
    // o de cada minuto do island.now (que vem alinhado ao minuto).
    readonly property real nowMs: Math.max(priv.openedAt, root.nowDate.getTime())
    readonly property int todayY: root.nowDate.getFullYear()
    readonly property int todayM: root.nowDate.getMonth()
    readonly property int todayD: root.nowDate.getDate()
    readonly property string todayKey: svc.dateKey(root.todayY, root.todayM, root.todayD)
    readonly property string selKey: svc.dateKey(priv.selY, priv.selM, priv.selD)
    readonly property bool onToday: root.selKey === root.todayKey

    onTodayKeyChanged: {
        if (priv.live && priv.followToday)
            root.goToday(false);
    }

    readonly property int weekStart: svc.weekStart(root.loc.firstDayOfWeek)
    readonly property var weeks: svc.monthGrid(priv.selY, priv.selM, root.weekStart, root.todayKey)
    readonly property var cells: {
        const out = [];
        for (let w = 0; w < root.weeks.length; w++) {
            for (let d = 0; d < 7; d++)
                out.push(root.weeks[w].days[d]);
        }
        return out;
    }
    // Índice do dia escolhido na grade (está sempre no mês à mostra).
    readonly property int selIndex: ((new Date(Date.UTC(priv.selY, priv.selM, 1)).getUTCDay() - root.weekStart + 7) % 7) + priv.selD - 1

    // Cabeçalho dos dias: o nome curto do idioma, em maiúsculas (como o relógio do Omarchy).
    readonly property var weekdays: {
        const out = [];
        for (let i = 0; i < 7; i++) {
            const wd = (root.weekStart + i) % 7;
            out.push({ label: String(root.loc.dayName(wd, Locale.ShortFormat)).toUpperCase(), weekend: wd === 0 || wd === 6 });
        }
        return out;
    }

    readonly property string title: {
        const month = String(root.loc.standaloneMonthName(priv.selM, Locale.LongFormat));
        const name = month.length > 0 ? month.charAt(0).toUpperCase() + month.slice(1) : month;
        return root.fill(Commons.I18n.t("clock.monthYear"), name, Commons.I18n.formatNumber(priv.selY));
    }

    // ---- Barras do ano e da vida (presas a hoje, não ao mês à mostra) ----
    readonly property int yearPercent: Math.round(svc.yearProgress(root.todayY, root.todayM, root.todayD) * 100)
    readonly property int birthYear: svc.birthYear(root.todayY)
    readonly property real lifeDone: svc.lifeProgress(root.birthYear, root.todayY, svc.lifeExpectancy())
    readonly property int lifePercent: Math.round(root.lifeDone * 100)
    readonly property bool hasLife: root.birthYear > 0

    // ---- Lembretes ----
    readonly property var activeReminders: svc.reminders.filter(r => r.at * 1000 > root.nowMs)
    readonly property var reminderDays: {
        const map = {};
        for (const r of root.activeReminders)
            map[svc.keyForDate(new Date(r.at * 1000))] = true;
        return map;
    }
    readonly property var dayReminders: root.activeReminders.filter(r => svc.keyForDate(new Date(r.at * 1000)) === root.selKey)
    readonly property bool dayMode: root.dayReminders.length > 0
    readonly property var listed: root.dayMode ? root.dayReminders : root.activeReminders
    readonly property var shownReminders: root.listed.slice(0, root.maxRows)
    readonly property string cardTitle: root.dayMode
        ? new Date(priv.selY, priv.selM, priv.selD, 12).toLocaleDateString(root.loc, Commons.I18n.t("clock.dayMonthFormat"))
        : svc.tc("reminder.upcoming", "Upcoming reminders")
    readonly property string setLabel: {
        const k = svc.tk("Set reminder");
        return k !== "" ? k : svc.tc("reminder.setTooltip", "Set reminder");
    }

    // ---- Outros fusos (até 4) ----
    readonly property var world: svc.cities.filter(c => c.offset !== null).slice(0, 4)
    readonly property bool hasWorld: root.world.length > 0

    // ---- Funções ----

    function tr(key) {
        return root.strings ? root.strings.t(key) : "";
    }
    // %1 e %2 trocados sem String.arg (que avisa quando falta o marcador).
    function fill(text, a, b) {
        let s = String(text || "").replace("%1", a);
        if (b !== undefined)
            s = s.replace("%2", b);
        return s;
    }
    function fade(ms) {
        return root.snapping || !root.theme ? 0 : root.theme.dur(ms);
    }
    // x de uma caixa de grade, espelhado à mão no RTL (x explícito não espelha).
    function mx(x, w) {
        return root.rtl ? root.contentW - x - w : x;
    }
    function cellX(col) {
        return root.mx(root.daysX + col * root.cellW, root.cellW);
    }

    // "09:05" ou "9:05 PM" (island.clock12), com os algarismos do idioma.
    function clockText(h, m) {
        const f = Commons.I18n.formatNumber;
        const pad2 = n => n < 10 ? f(0) + f(n) : f(n);
        if (root.island && root.island.clock12) {
            const ap = h < 12 ? root.loc.amText : root.loc.pmText;
            return f(h % 12 === 0 ? 12 : h % 12) + ":" + pad2(m) + " " + ap;
        }
        return pad2(h) + ":" + pad2(m);
    }
    function localClock(ms) {
        const d = new Date(ms);
        return root.clockText(d.getHours(), d.getMinutes());
    }
    // A hora de um fuso: o instante deslocado, lido em UTC (Model.zoneParts do elsewhen).
    function zoneParts(offset) {
        const d = new Date(root.nowMs + offset * 60000);
        return { y: d.getUTCFullYear(), m: d.getUTCMonth(), d: d.getUTCDate(), h: d.getUTCHours(), min: d.getUTCMinutes() };
    }
    // "+1 dia" / "-1 dia" quando o fuso já está noutro dia (elsewhen.daysAhead / daysBehind).
    function dayHint(p) {
        const diff = Math.round((Date.UTC(p.y, p.m, p.d) - Date.UTC(root.todayY, root.todayM, root.todayD)) / svc.msPerDay);
        if (diff === 0)
            return "";
        const n = Math.abs(diff);
        return root.fill(Commons.I18n.tn(diff > 0 ? "elsewhen.daysAhead" : "elsewhen.daysBehind", n), Commons.I18n.formatNumber(n));
    }
    function remainingText(at) {
        const s = at - root.nowMs / 1000;
        return root.island && root.island.status ? root.island.status.durationText(s) : "";
    }

    // Escolhe um dia (normalizado em UTC); outro mês desliza a grade.
    function select(y, m, d, animate) {
        const t = new Date(Date.UTC(y, m, d));
        const ny = t.getUTCFullYear(), nm = t.getUTCMonth(), nd = t.getUTCDate();
        const delta = (ny * 12 + nm) - (priv.selY * 12 + priv.selM);
        if (delta !== 0) {
            priv.ringSnap = true;
            priv.hover = -1;
            if (animate)
                slide.play(delta > 0 ? 1 : -1);
            Qt.callLater(() => priv.ringSnap = root.snapping);
        }
        priv.selY = ny;
        priv.selM = nm;
        priv.selD = nd;
        priv.followToday = svc.dateKey(ny, nm, nd) === root.todayKey;
    }
    function moveDays(delta) {
        root.select(priv.selY, priv.selM, priv.selD + delta, true);
    }
    function moveMonths(delta) {
        const t = svc.stepMonth(priv.selY, priv.selM, delta);
        root.select(t.year, t.month, Math.min(priv.selD, svc.daysInMonth(t.year, t.month)), true);
    }
    function goToday(animate) {
        root.select(root.todayY, root.todayM, root.todayD, animate);
    }

    // Roda: um passo a cada 120 (o touchpad soma os pedacinhos); para baixo = próximo mês.
    function wheel(dy) {
        if (dy === 0)
            return;
        const now = Date.now();
        if (now - priv.wheelAt > Motion.TIMING.WHEEL_DECAY_MS || (priv.wheelAcc !== 0 && Math.sign(priv.wheelAcc) !== Math.sign(dy)))
            priv.wheelAcc = 0;
        priv.wheelAt = now;
        priv.wheelAcc += dy;
        if (priv.wheelAcc <= -Motion.TIMING.WHEEL_STEP) {
            priv.wheelAcc = 0;
            root.moveMonths(1);
        } else if (priv.wheelAcc >= Motion.TIMING.WHEEL_STEP) {
            priv.wheelAcc = 0;
            root.moveMonths(-1);
        }
    }

    function focusOrder() {
        return root.onToday ? ["grid", "prev", "next", "remind"] : ["grid", "today", "prev", "next", "remind"];
    }
    function cycleFocus(step) {
        const order = root.focusOrder();
        const at = Math.max(0, order.indexOf(priv.focus));
        priv.focus = order[((at + step) % order.length + order.length) % order.length];
    }
    function focused(id) {
        return root.keyboardMode && priv.focus === id;
    }
    function activate(id) {
        switch (id) {
        case "today":
            root.goToday(true);
            priv.focus = "grid";
            break;
        case "prev":
            root.moveMonths(-1);
            break;
        case "next":
            root.moveMonths(1);
            break;
        case "remind":
            root.setReminder();
            break;
        }
    }
    // Sem o "hoje" (o escolhido voltou a ser hoje), o foco volta para a grade.
    onOnTodayChanged: if (root.onToday && priv.focus === "today") priv.focus = "grid"

    // Fecha a ilha e abre o fluxo de lembrete do Omarchy (o comando do menu),
    // num processo à parte que espera a ilha sair.
    function setReminder() {
        root.closeRequested();
        const bin = svc.omarchyPath !== "" ? svc.omarchyPath + "/bin/omarchy-reminder" : "omarchy-reminder";
        if (Quickshell.env("ILHA_DEV") === "1") {
            console.log("ilha(dev): calendário -> " + bin + " -i (não executado)");
            return;
        }
        const wait = (Motion.TIMING.CLOSE_THEN_RUN_MS / 1000).toFixed(2);
        Quickshell.execDetached(["sh", "-c", "sleep \"$0\"; exec \"$@\"", wait, bin, "-i"]);
    }

    // ---- Cabeçalho ----
    Item {
        id: header
        x: root.pad
        y: root.headerY
        width: root.contentW
        height: root.headerH

        IlhaText {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: buttons.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            size: 17
            weight: 600
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignLeft
            text: root.title
        }

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            CircleButton {
                id: todayBtn
                theme: root.theme
                icon: "today"
                size: root.btn
                glyphSize: 17
                fill: root.theme ? root.theme.card : "transparent"
                glyphColor: root.theme ? root.theme.accentInk : "white"
                focused: root.focused("today")
                accessibleName: Commons.I18n.t("clock.backToToday")
                opacity: root.onToday ? 0 : 1
                visible: todayBtn.opacity > 0.01
                enabled: !root.onToday
                onClicked: root.goToday(true)
                Behavior on opacity {
                    NumberAnimation { duration: root.fade(Motion.FADE.HOVER); easing.type: Easing.OutCubic }
                }
            }
            CircleButton {
                theme: root.theme
                icon: "chevron_left"
                flip: root.rtl
                size: root.btn
                glyphSize: 18
                fill: root.theme ? root.theme.card : "transparent"
                glyphColor: root.theme ? root.theme.ink : "white"
                focused: root.focused("prev")
                accessibleName: Commons.I18n.t("clock.previousMonth")
                onClicked: root.moveMonths(-1)
            }
            CircleButton {
                theme: root.theme
                icon: "chevron_right"
                flip: root.rtl
                size: root.btn
                glyphSize: 18
                fill: root.theme ? root.theme.card : "transparent"
                glyphColor: root.theme ? root.theme.ink : "white"
                focused: root.focused("next")
                accessibleName: Commons.I18n.t("clock.nextMonth")
                onClicked: root.moveMonths(1)
            }
        }
    }

    // ---- Barras do ano e da vida ----
    Item {
        x: root.pad
        y: root.railY
        width: root.contentW
        height: root.railH

        Rail {
            anchors.left: parent.left
            width: root.hasLife ? (parent.width - root.railGap) / 2 : parent.width
            label: Commons.I18n.formatNumber(root.todayY)
            percent: root.yearPercent
        }
        Rail {
            anchors.right: parent.right
            width: (parent.width - root.railGap) / 2
            visible: root.hasLife
            label: Commons.I18n.t("clock.life")
            percent: root.lifePercent
        }
    }

    // ---- Cabeçalho dos dias (com o "S" da coluna das semanas) ----
    Item {
        x: root.pad
        y: root.weekdayY
        width: root.contentW
        height: root.weekdayH

        IlhaText {
            x: root.mx(0, root.weekColW)
            width: root.weekColW
            height: parent.height
            theme: root.theme
            size: 10.5
            weight: 600
            color: root.theme ? root.theme.inkFaint : "gray"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: Commons.I18n.t("clock.weekShort")
        }
        Repeater {
            model: root.weekdays

            IlhaText {
                required property var modelData
                required property int index
                x: root.cellX(index)
                width: root.cellW
                height: parent.height
                theme: root.theme
                size: 10.5
                weight: 600
                font.letterSpacing: 0.5
                color: root.theme ? (modelData.weekend ? root.theme.inkFaint : root.theme.inkMuted) : "gray"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: modelData.label
            }
        }
    }

    // ---- Grade ----
    Item {
        id: gridBox
        x: root.pad
        y: root.gridY
        width: root.contentW
        height: root.gridH

        // Fio entre as semanas e os dias.
        Rectangle {
            x: root.mx(root.weekColW + root.gutter / 2, 1)
            y: 4
            width: 1
            height: parent.height - 8
            color: root.theme ? root.theme.rim : "transparent"
        }

        Item {
            id: days
            property real shift: 0
            x: days.shift
            width: parent.width
            height: parent.height

            // Semanas ISO.
            Repeater {
                model: root.weeks

                IlhaText {
                    required property var modelData
                    required property int index
                    x: root.mx(0, root.weekColW)
                    y: index * root.rowH
                    width: root.weekColW
                    height: root.rowH
                    theme: root.theme
                    size: 10.5
                    weight: 500
                    tnum: true
                    color: root.theme ? root.theme.inkFaint : "gray"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Commons.I18n.formatNumber(modelData.week)
                }
            }

            // Hover (atrás do número).
            Rectangle {
                readonly property var hovered: priv.hover >= 0 && priv.hover < root.cells.length ? root.cells[priv.hover] : null
                x: root.cellX(priv.hover % 7) + (root.cellW - root.dayD) / 2
                y: Math.floor(priv.hover / 7) * root.rowH + (root.rowH - root.dayD) / 2
                width: root.dayD
                height: root.dayD
                radius: width / 2
                color: root.theme ? root.theme.hoverOverlay : "transparent"
                visible: !!hovered && !hovered.today
            }

            Repeater {
                model: root.cells

                Item {
                    id: cell
                    required property var modelData
                    required property int index

                    readonly property bool marked: !!root.reminderDays[cell.modelData.key]

                    x: root.cellX(cell.index % 7)
                    y: Math.floor(cell.index / 7) * root.rowH
                    width: root.cellW
                    height: root.rowH

                    Accessible.role: Accessible.Button
                    Accessible.name: new Date(cell.modelData.year, cell.modelData.month, cell.modelData.day, 12).toLocaleDateString(root.loc, Locale.LongFormat)
                    Accessible.focusable: true
                    Accessible.focused: cell.index === root.selIndex
                    Accessible.onPressAction: root.select(cell.modelData.year, cell.modelData.month, cell.modelData.day, true)

                    Rectangle {
                        anchors.centerIn: parent
                        width: root.dayD
                        height: root.dayD
                        radius: width / 2
                        color: root.theme ? root.theme.accent : "white"
                        visible: cell.modelData.today
                    }
                    IlhaText {
                        anchors.centerIn: parent
                        theme: root.theme
                        size: 13
                        weight: cell.modelData.today ? 600 : 500
                        tnum: true
                        opacity: cell.modelData.inMonth || cell.modelData.today ? 1 : 0.5
                        color: !root.theme ? "white"
                            : cell.modelData.today ? root.theme.onAccent
                            : !cell.modelData.inMonth ? root.theme.inkFaint
                            : cell.modelData.weekend ? root.theme.inkMuted
                            : root.theme.ink
                        text: Commons.I18n.formatNumber(cell.modelData.day)
                    }
                    // Dia com lembrete.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.rowH / 2 + 8.5
                        width: 4
                        height: 4
                        radius: 2
                        visible: cell.marked
                        color: root.theme ? (cell.modelData.today ? root.theme.onAccent : root.theme.accentInk) : "white"
                        opacity: cell.modelData.inMonth || cell.modelData.today ? 1 : 0.5
                    }
                }
            }

            // O anel do dia escolhido: desliza de dia a dia. Em volta de hoje
            // (o círculo accent) fica por fora, a 1,5 px, como um anel de foco
            // (por dentro brigaria com o ponto do lembrete). No modo teclado,
            // com a grade focada, é o anel de foco: accent, 2 px.
            Rectangle {
                id: ring
                readonly property bool onFill: root.onToday
                readonly property bool keyed: root.focused("grid")
                readonly property real inset: ring.onFill ? -(1.5 + ring.border.width) : 0
                x: root.cellX(root.selIndex % 7) + (root.cellW - root.dayD) / 2 + ring.inset
                y: Math.floor(root.selIndex / 7) * root.rowH + (root.rowH - root.dayD) / 2 + ring.inset
                width: root.dayD - 2 * ring.inset
                height: width
                radius: width / 2
                color: "transparent"
                border.width: ring.keyed ? 2 : 1.5
                border.color: !root.theme ? "white"
                    : ring.keyed ? root.theme.focusRing
                    : root.theme.alpha(root.theme.ink, 0.75)
                Behavior on x {
                    enabled: !priv.ringSnap && !root.snapping
                    NumberAnimation { duration: root.fade(Motion.FADE.SWITCH); easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: !priv.ringSnap && !root.snapping
                    NumberAnimation { duration: root.fade(Motion.FADE.SWITCH); easing.type: Easing.OutCubic }
                }
            }

            // Troca de mês: desliza 14 px no sentido da troca (espelhado no RTL) e reaparece.
            ParallelAnimation {
                id: slide
                property int dir: 1
                function play(d) {
                    slide.stop();
                    days.shift = 0;
                    days.opacity = 1;
                    if (!root.theme || root.theme.dur(220) <= 0)
                        return;
                    slide.dir = d * (root.rtl ? -1 : 1);
                    slide.start();
                }
                NumberAnimation {
                    target: days
                    property: "shift"
                    from: 14 * slide.dir
                    to: 0
                    duration: 220
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: days
                    property: "opacity"
                    from: 0.25
                    to: 1
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Clique, hover e roda: uma área só sobre os dias.
        MouseArea {
            id: gridArea
            x: root.mx(root.daysX, root.contentW - root.daysX)
            width: root.contentW - root.daysX
            height: parent.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            function indexAt(px, py) {
                if (px < 0 || py < 0 || px >= gridArea.width || py >= gridArea.height)
                    return -1;
                let col = Math.floor(px / root.cellW);
                if (root.rtl)
                    col = 6 - col;
                const row = Math.floor(py / root.rowH);
                return Math.max(0, Math.min(6, col)) + 7 * Math.max(0, Math.min(5, row));
            }
            onPositionChanged: mouse => priv.hover = gridArea.indexAt(mouse.x, mouse.y)
            onExited: priv.hover = -1
            onClicked: mouse => {
                const i = gridArea.indexAt(mouse.x, mouse.y);
                const c = i >= 0 ? root.cells[i] : null;
                if (!c)
                    return;
                priv.focus = "grid";
                root.select(c.year, c.month, c.day, true);
            }
            onWheel: ev => {
                root.wheel(ev.angleDelta.y);
                ev.accepted = true;
            }
        }
    }

    // ---- Outros fusos ----
    Row {
        x: root.pad
        y: root.worldY
        width: root.contentW
        height: root.worldH
        visible: root.hasWorld

        Repeater {
            model: root.world

            Item {
                id: city
                required property var modelData
                required property int index
                readonly property var parts: root.zoneParts(city.modelData.offset)
                readonly property string hint: root.dayHint(city.parts)

                width: root.contentW / Math.max(1, root.world.length)
                height: root.worldH

                Accessible.role: Accessible.StaticText
                Accessible.name: city.modelData.label + " " + timeText.text + (city.hint !== "" ? " " + city.hint : "")

                // Fio entre as cidades.
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 18
                    color: root.theme ? root.theme.rim : "transparent"
                    visible: city.index > 0
                }
                IlhaText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    width: parent.width - 12
                    theme: root.theme
                    size: 10.5
                    weight: 600
                    color: root.theme ? root.theme.inkFaint : "gray"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: city.modelData.label
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 13
                    spacing: 4

                    IlhaText {
                        id: timeText
                        theme: root.theme
                        size: 13
                        weight: 600
                        tnum: true
                        text: root.clockText(city.parts.h, city.parts.min)
                    }
                    IlhaText {
                        anchors.baseline: timeText.baseline
                        theme: root.theme
                        size: 10.5
                        weight: 500
                        color: root.theme ? root.theme.inkFaint : "gray"
                        visible: city.hint !== ""
                        text: city.hint
                    }
                }
            }
        }
    }

    // ---- Lembretes ----
    Rectangle {
        id: card
        x: root.pad
        y: root.cardY
        width: root.contentW
        height: root.cardH
        radius: root.cardRadius
        color: root.theme ? root.theme.card : "transparent"

        Icon {
            id: cardIcon
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: setBtn.verticalCenter
            name: "alarm"
            size: 16
            color: root.theme ? root.theme.accentInk : "white"
        }
        IlhaText {
            anchors.left: cardIcon.right
            anchors.leftMargin: 8
            anchors.right: setBtn.left
            anchors.rightMargin: 10
            anchors.verticalCenter: setBtn.verticalCenter
            theme: root.theme
            size: 13.5
            weight: 600
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignLeft
            text: root.listed.length > root.shownReminders.length && root.strings
                ? root.cardTitle + " · " + root.fill(root.strings.tn("bar.reminders", root.listed.length), Commons.I18n.formatNumber(root.listed.length))
                : root.cardTitle
        }

        PillButton {
            id: setBtn
            anchors.right: parent.right
            anchors.rightMargin: 8
            y: 8
            icon: "add_alarm"
            text: root.setLabel
            focused: root.focused("remind")
            onClicked: root.setReminder()
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: root.cardTop

            Repeater {
                model: root.shownReminders

                Item {
                    id: rem
                    required property var modelData
                    readonly property string label: rem.modelData.label !== "" ? rem.modelData.label : root.fill(svc.tc("reminder.minuteLabel", "%1-min reminder"), Commons.I18n.formatNumber(rem.modelData.minutes))

                    width: parent.width
                    height: root.remRowH

                    Accessible.role: Accessible.StaticText
                    Accessible.name: root.fill(svc.tc("reminder.inRemaining", "%1 in %2 (%3)"), rem.label, remainText.text).replace("%3", atText.text)

                    IlhaText {
                        id: atText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.island && root.island.clock12 ? 62 : 44
                        theme: root.theme
                        size: 12.5
                        weight: 600
                        tnum: true
                        color: root.theme ? root.theme.accentInk : "white"
                        horizontalAlignment: Text.AlignLeft
                        text: root.localClock(rem.modelData.at * 1000)
                    }
                    IlhaText {
                        anchors.left: atText.right
                        anchors.leftMargin: 6
                        anchors.right: remainText.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        theme: root.theme
                        size: 13
                        weight: 500
                        color: root.theme ? root.theme.alpha(root.theme.ink, 0.92) : "white"
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        horizontalAlignment: Text.AlignLeft
                        text: rem.label
                    }
                    IlhaText {
                        id: remainText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        theme: root.theme
                        size: 12
                        weight: 500
                        tnum: true
                        color: root.theme ? root.theme.inkFaint : "gray"
                        text: root.remainingText(rem.modelData.at)
                    }
                }
            }
        }

        IlhaText {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.rightMargin: 14
            y: root.cardTop + (root.remRowH - height) / 2
            visible: svc.remindersLoaded && root.listed.length === 0
            theme: root.theme
            size: 12.5
            weight: 500
            color: root.theme ? root.theme.inkFaint : "gray"
            horizontalAlignment: Text.AlignLeft
            elide: Text.ElideRight
            text: svc.tc("reminder.none", "No outstanding reminders")
        }
    }

    // Barra fina com rótulo e porcentagem (ano e vida, como no relógio do Omarchy).
    component Rail: Item {
        id: rail
        property string label: ""
        property int percent: 0

        height: root.railH

        Accessible.role: Accessible.ProgressBar
        Accessible.name: rail.label + " " + railPct.text

        IlhaText {
            id: railLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            size: 10.5
            weight: 600
            tnum: true
            font.letterSpacing: 0.5
            color: root.theme ? root.theme.inkFaint : "gray"
            text: rail.label
        }
        IlhaText {
            id: railPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            size: 11
            weight: 600
            tnum: true
            color: root.theme ? root.theme.inkMuted : "gray"
            text: root.strings ? root.fill(root.strings.t("common.percent"), Commons.I18n.formatNumber(rail.percent)) : ""
        }
        Rectangle {
            anchors.left: railLabel.right
            anchors.leftMargin: 10
            anchors.right: railPct.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 4
            radius: 2
            color: root.theme ? root.theme.raised : "transparent"

            Rectangle {
                anchors.left: parent.left
                width: Math.round(parent.width * Math.max(0, Math.min(100, rail.percent)) / 100)
                height: parent.height
                radius: parent.radius
                color: root.theme ? root.theme.accent : "white"
            }
        }
    }

    // Botão de pílula do cartão (accentSoft + accentInk, como a pílula da ListRow).
    component PillButton: Item {
        id: pill
        property string icon: ""
        property string text: ""
        property bool focused: false
        signal clicked()

        readonly property bool hovered: pillArea.containsMouse

        width: Math.ceil(pillMetrics.advanceWidth) + 15 + 6 + 24
        height: 28

        Accessible.role: Accessible.Button
        Accessible.name: pill.text
        Accessible.onPressAction: pill.clicked()

        IlhaMetrics {
            id: pillMetrics
            theme: root.theme
            size: 12.5
            weight: 600
            text: pill.text
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: !root.theme ? "transparent"
                : pillArea.pressed ? root.theme.mix(root.theme.accentSoft, root.theme.accent, 0.22)
                : pill.hovered ? root.theme.mix(root.theme.accentSoft, root.theme.accent, 0.12)
                : root.theme.accentSoft
            Behavior on color {
                ColorAnimation { duration: root.fade(Motion.FADE.HOVER) }
            }
        }
        Row {
            anchors.centerIn: parent
            spacing: 6

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: pill.icon
                size: 15
                color: root.theme ? root.theme.accentInk : "white"
            }
            IlhaText {
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                size: 12.5
                weight: 600
                color: root.theme ? root.theme.accentInk : "white"
                text: pill.text
            }
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
        FocusRing {
            theme: root.theme
            shown: pill.focused
            itemRadius: pill.height / 2
        }
    }
}
