import QtQuick
import Quickshell
import qs.Commons as Commons

// Lançador de aplicativos: campo de busca e até 7 resultados. A altura
// acompanha o número de resultados.
Item {
  id: root

  // Cores do tema (o host passa as mesmas).
  property color fg: Commons.Color.bar.text
  property color bg: Commons.Color.bar.background
  property color accent: Commons.Color.accent
  property color danger: Commons.Color.urgent

  // `open` (semântica antiga) e `active` (contrato de estado) fazem o mesmo:
  // enquanto um deles for verdadeiro o lançador está visível e com foco.
  property bool open: false
  property bool active: false
  readonly property bool shown: open || active

  // Fachada do host; não é usada aqui, mas aceita para seguir o contrato.
  property var shell: null

  signal closeRequested()
  signal navigate(string target)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property int maxRows: 7
  readonly property int rowHeight: 44
  readonly property int rowGap: 2
  readonly property int searchHeight: 46
  readonly property int spacing: 12
  readonly property string iconFont: "JetBrainsMono Nerd Font"

  readonly property color surface: Qt.rgba(fg.r, fg.g, fg.b, 0.08)
  readonly property color hoverTint: Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.5)

  property string query: ""
  property int selectedIndex: 0

  // Apps visíveis (sem noDisplay), útil para o host e para testes.
  readonly property int appCount: allApps.length

  readonly property var allApps: {
    var values = DesktopEntries.applications.values || []
    var out = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (e && !e.noDisplay && e.name) out.push(e)
    }
    return out
  }

  readonly property var results: {
    var q = root.query.trim().toLowerCase()
    var apps = root.allApps
    var scored = []
    for (var i = 0; i < apps.length; i++) {
      var e = apps[i]
      var name = String(e.name || "").toLowerCase()
      var score = -1
      if (q.length === 0) {
        score = 0
      } else if (name.indexOf(q) === 0) {
        score = 3
      } else if (name.indexOf(q) >= 0) {
        score = 2
      } else if (String(e.genericName || "").toLowerCase().indexOf(q) >= 0) {
        score = 1
      } else {
        var kws = e.keywords || []
        for (var k = 0; k < kws.length; k++) {
          if (String(kws[k]).toLowerCase().indexOf(q) >= 0) { score = 1; break }
        }
      }
      if (score >= 0) scored.push({ entry: e, score: score, name: name })
    }
    scored.sort(function(a, b) {
      if (a.score !== b.score) return b.score - a.score
      return a.name.localeCompare(b.name)
    })
    var out = []
    for (var j = 0; j < scored.length && j < root.maxRows; j++) out.push(scored[j].entry)
    return out
  }

  onResultsChanged: {
    if (selectedIndex >= results.length) selectedIndex = Math.max(0, results.length - 1)
  }

  function reset() {
    input.text = ""
    root.query = ""
    root.selectedIndex = 0
    input.forceActiveFocus()
  }

  onShownChanged: if (shown) reset()
  Component.onCompleted: if (shown) input.forceActiveFocus()

  function launch(index) {
    var e = results[index]
    if (!e) return
    root.closeRequested()
    e.execute()
  }

  implicitWidth: 420
  // Cresce com os resultados; sem nenhum, reserva uma linha para o aviso.
  readonly property int rowCount: Math.max(1, results.length)
  implicitHeight: searchHeight + spacing + rowCount * rowHeight + (rowCount - 1) * rowGap

  // ---------- Campo de busca ----------
  ContinuousRect {
    id: searchBox
    x: 0
    y: 0
    width: root.implicitWidth
    height: root.searchHeight
    radius: height / 2
    color: root.surface
    borderWidth: 1
    borderColor: input.activeFocus
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55)
      : "transparent"
    Behavior on borderColor {
      ColorAnimation { duration: Commons.Style.duration(200); easing.type: Easing.OutCubic }
    }

    Text {
      id: searchIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: "\uF002" // nf-fa-search
      font.family: root.iconFont
      font.pixelSize: 15
      color: root.accent
    }

    TextInput {
      id: input
      anchors.left: searchIcon.right
      anchors.leftMargin: 12
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      color: root.fg
      selectionColor: root.accent
      selectedTextColor: root.bg
      font.pixelSize: 15
      clip: true
      onTextChanged: {
        root.query = text
        root.selectedIndex = 0
      }

      Keys.onUpPressed: event => {
        if (root.results.length > 0)
          root.selectedIndex = (root.selectedIndex - 1 + root.results.length) % root.results.length
        event.accepted = true
      }
      Keys.onDownPressed: event => {
        if (root.results.length > 0)
          root.selectedIndex = (root.selectedIndex + 1) % root.results.length
        event.accepted = true
      }
      Keys.onTabPressed: event => {
        if (root.results.length > 0)
          root.selectedIndex = (root.selectedIndex + 1) % root.results.length
        event.accepted = true
      }
      Keys.onBacktabPressed: event => {
        if (root.results.length > 0)
          root.selectedIndex = (root.selectedIndex - 1 + root.results.length) % root.results.length
        event.accepted = true
      }
      Keys.onReturnPressed: event => { root.launch(root.selectedIndex); event.accepted = true }
      Keys.onEnterPressed: event => { root.launch(root.selectedIndex); event.accepted = true }
      Keys.onEscapePressed: event => { root.closeRequested(); event.accepted = true }

      Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        text: strings.t("launcher.placeholder")
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
        font.pixelSize: 15
        elide: Text.ElideRight
        visible: input.text.length === 0
      }
    }
  }

  // ---------- Resultados ----------
  Column {
    id: list
    x: 0
    y: root.searchHeight + root.spacing
    width: root.implicitWidth
    spacing: root.rowGap

    Repeater {
      model: root.results

      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property bool selected: index === root.selectedIndex

        width: list.width
        height: root.rowHeight

        ContinuousRect {
          anchors.fill: parent
          radius: 14
          color: row.selected
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            : (hover.hovered ? root.hoverTint : "transparent")
          Behavior on color {
            ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
          }
        }

        // O hover só destaca; não move a seleção. As linhas são recriadas a
        // cada tecla, e um cursor parado roubaria a seleção (Enter abriria o
        // app errado).
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.launch(row.index) }

        Item {
          id: iconBox
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 26
          height: 26

          readonly property string src: {
            var v = String(row.modelData.icon || "")
            if (v.length === 0) return ""
            if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
            if (v.charAt(0) === "/") return "file://" + v
            return Quickshell.iconPath(v, true)
          }

          Image {
            id: img
            anchors.fill: parent
            source: iconBox.src
            sourceSize.width: 52
            sourceSize.height: 52
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            visible: status === Image.Ready
          }
          Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: "\uF2D0" // nf-fa-window_maximize (ícone reserva de app)
            font.family: root.iconFont
            font.pixelSize: 16
            color: row.selected ? root.accent : root.fg
          }
        }

        Text {
          id: nameText
          anchors.left: iconBox.right
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, row.width - 64)
          textFormat: Text.PlainText
          text: String(row.modelData.name || "")
          color: row.selected ? root.accent : root.fg
          Behavior on color {
            ColorAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
          }
          font.pixelSize: 14
          font.weight: row.selected ? Font.DemiBold : Font.Normal
          elide: Text.ElideRight
        }

        Text {
          anchors.left: nameText.right
          anchors.leftMargin: 10
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String(row.modelData.genericName || "")
          color: root.dim
          font.pixelSize: 13
          elide: Text.ElideRight
        }
      }
    }
  }

  Text {
    visible: root.results.length === 0
    x: 0
    y: list.y
    width: root.implicitWidth
    height: root.rowHeight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: strings.t("launcher.empty")
    color: root.dim
    font.pixelSize: 14
  }
}
