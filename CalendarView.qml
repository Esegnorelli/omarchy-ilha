import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons as Commons

// Calendário do mês: cabeçalho com mês e ano, setas entre meses e grade de
// 6 semanas a partir do primeiro dia da semana do idioma. Abre pelo relógio;
// Esc fecha, setas trocam o mês e Home volta para hoje.
Item {
  id: root

  // Cores do tema (o host passa as mesmas).
  property color fg: Commons.Color.bar.text
  property color bg: Commons.Color.bar.background
  property color accent: Commons.Color.accent
  property color danger: Commons.Color.urgent

  // O host liga enquanto este estado está visível.
  property bool active: false
  property var shell: null

  signal closeRequested()
  signal navigate(string target)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitWidth: 380
  implicitHeight: content.implicitHeight

  focus: true

  readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
  readonly property color hoverTint: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.28)
  readonly property var loc: Qt.locale(Commons.I18n.formatLocale)
  readonly property bool rtl: Commons.I18n.rightToLeft

  // Primeiro dia da semana do idioma, em 0 = domingo (Qt usa 7 para domingo).
  readonly property int weekStart: ((loc.firstDayOfWeek % 7) + 7) % 7

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
    followToday = true
    viewYear = todayYear
    viewMonth = todayMonth
  }
  function showMonth(year, month) {
    followToday = false
    viewYear = year
    viewMonth = month
  }
  function shiftMonth(delta) {
    const d = new Date(viewYear, viewMonth + delta, 1)
    showMonth(d.getFullYear(), d.getMonth())
  }
  onTodayMonthChanged: if (followToday) goToday()
  onTodayYearChanged: if (followToday) goToday()

  onActiveChanged: if (active) { goToday(); root.forceActiveFocus() }
  Component.onCompleted: { goToday(); if (active) root.forceActiveFocus() }

  Keys.onPressed: event => {
    const key = Commons.Util.readingKey(event, false)
    if (key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true }
    else if (key === Qt.Key_Left || key === Qt.Key_PageUp) { root.shiftMonth(-1); event.accepted = true }
    else if (key === Qt.Key_Right || key === Qt.Key_PageDown) { root.shiftMonth(1); event.accepted = true }
    else if (key === Qt.Key_Home) { root.goToday(); event.accepted = true }
  }

  function capitalize(s) {
    return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : s
  }

  readonly property string monthTitle: capitalize(
    new Date(viewYear, viewMonth, 1).toLocaleDateString(loc, strings.t("calendar.monthFormat")))

  readonly property string todayText: {
    // "quinta-feira" fica "quinta", mais curto no rodapé.
    const s = clock.date.toLocaleDateString(loc, strings.t("calendar.todayFormat")).replace("-feira", "")
    return strings.t("calendar.today").arg(s)
  }

  // Iniciais dos dias, na ordem do idioma; sábado e domingo ficam mais apagados.
  readonly property var weekdays: {
    const out = []
    for (let i = 0; i < 7; i++) {
      const jsDay = (weekStart + i) % 7
      // dayName aceita 0..6 com 0 = domingo, igual ao Date.getDay().
      out.push({ label: loc.dayName(jsDay, Locale.NarrowFormat), weekend: jsDay === 0 || jsDay === 6 })
    }
    return out
  }

  // 42 células (6 semanas), cada uma com dia, mês e ano.
  readonly property var cells: {
    const first = new Date(viewYear, viewMonth, 1)
    const offset = (first.getDay() - weekStart + 7) % 7
    const out = []
    for (let i = 0; i < 42; i++) {
      const d = new Date(viewYear, viewMonth, 1 - offset + i)
      out.push({
        day: d.getDate(),
        month: d.getMonth(),
        year: d.getFullYear(),
        inMonth: d.getMonth() === viewMonth,
        weekend: d.getDay() === 0 || d.getDay() === 6
      })
    }
    return out
  }

  // ---------- Componentes internos ----------
  component ArrowChip: Item {
    id: arrow
    property string icon: ""
    signal clicked()

    implicitWidth: 34
    implicitHeight: 34

    ContinuousRect {
      anchors.fill: parent
      radius: height / 2
      color: arrowHover.hovered ? root.hoverTint : root.surface
      Behavior on color {
        ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
      }
    }
    Icon {
      anchors.centerIn: parent
      name: arrow.icon
      size: 20
      color: arrowHover.hovered ? root.accent : root.fg
      Behavior on color {
        ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
      }
    }
    HoverHandler { id: arrowHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: arrow.clicked() }
  }

  // ---------- Layout ----------
  ColumnLayout {
    id: content
    width: root.implicitWidth
    spacing: 12

    // Cabeçalho: ‹  Mês de ano  ›
    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      ArrowChip {
        // Setas trocam de lado em idiomas RTL.
        icon: root.rtl ? "chevron_right" : "chevron_left"
        onClicked: root.shiftMonth(-1)
      }

      Item {
        id: title
        Layout.fillWidth: true
        Layout.preferredHeight: 34

        ContinuousRect {
          anchors.fill: parent
          radius: height / 2
          color: titleHover.hovered && !root.showingToday ? root.hoverTint : "transparent"
          Behavior on color {
            ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
          }
        }
        Row {
          anchors.centerIn: parent
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.monthTitle
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: root.fg
          }
          // Ponto que avisa que há um "voltar para hoje" disponível.
          ContinuousRect {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: root.accent
            opacity: root.showingToday ? 0 : 1
            Behavior on opacity {
              NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
            }
          }
        }
        HoverHandler {
          id: titleHover
          cursorShape: root.showingToday ? Qt.ArrowCursor : Qt.PointingHandCursor
        }
        TapHandler { onTapped: root.goToday() }
      }

      ArrowChip {
        icon: root.rtl ? "chevron_left" : "chevron_right"
        onClicked: root.shiftMonth(1)
      }
    }

    // Cartão com a grade do mês.
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: gridColumn.implicitHeight + 24

      ContinuousRect {
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
      }

      Column {
        id: gridColumn
        x: 12
        y: 12
        width: parent.width - 24
        spacing: 4

        // Iniciais dos dias da semana
        Row {
          width: parent.width
          Repeater {
            model: root.weekdays
            Text {
              required property var modelData
              width: gridColumn.width / 7
              height: 22
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: modelData.label
              font.pixelSize: 12
              font.weight: Font.DemiBold
              color: modelData.weekend ? root.faint : root.dim
            }
          }
        }

        // Grade de 6 semanas
        Grid {
          id: grid
          width: parent.width
          columns: 7

          Repeater {
            model: root.cells
            Item {
              id: cell
              required property var modelData
              readonly property bool isToday: modelData.day === root.todayDay
                                              && modelData.month === root.todayMonth
                                              && modelData.year === root.todayYear
              width: grid.width / 7
              height: 38

              ContinuousRect {
                anchors.centerIn: parent
                width: 34
                height: 32
                radius: 12
                color: cell.isToday ? root.accent : root.hoverTint
                opacity: cell.isToday ? 1 : (cellHover.hovered ? 1 : 0)
                Behavior on opacity {
                  NumberAnimation { duration: Commons.Style.duration(140); easing.type: Easing.OutCubic }
                }
              }
              Text {
                anchors.centerIn: parent
                text: cell.modelData.day
                font.pixelSize: 13
                font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                color: cell.isToday ? root.bg
                     : !cell.modelData.inMonth ? root.faint
                     : cell.modelData.weekend ? root.dim
                     : root.fg
              }

              HoverHandler { id: cellHover }
              // Tocar num dia de outro mês leva até aquele mês.
              TapHandler {
                onTapped: if (!cell.modelData.inMonth)
                  root.showMonth(cell.modelData.year, cell.modelData.month)
              }
            }
          }
        }
      }
    }

    // Rodapé com a data de hoje por extenso
    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: root.todayText
      font.pixelSize: 13
      elide: Text.ElideRight
      color: root.dim
    }
  }
}
