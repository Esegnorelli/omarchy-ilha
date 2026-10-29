import QtQuick
import qs.Commons as Commons

// Linha de Tiles da grade (spec §3.2 TileRow). Os filhos (Tile) são postos
// lado a lado pelo span na grade 128 + 8 (ou 3 colunas iguais, Energia).
// O último filho visível com stretch: true estica até a última coluna.
//
// API pública:
//   keyRow: int              -2 = automático (o PanelGrid conta as linhas com tecla), -1 = sem tecla, 0/1/2 = fixo
//   columns: 4 | 3
//   caption: string          legenda opcional de 16 px acima (11 DemiBold muted, caixa alta)
//   captionStatus: string    estado ao vivo à direita da legenda
//   captionStatusAlert: bool estado em danger (por exemplo "● Gravando 00:42")
//   keyboardMode, strings, fg, bg, accent, danger, muted, metrics   repassados aos Tiles
//   readonly resolvedKeyRow  linha de tecla efetiva
//   autoKeyRow               escrito pelo PanelGrid
// Funções:
//   focusItems() → [Item]    tiles visíveis (para teclas e setas)
//   relayout()
Item {
    id: row

    property int keyRow: -2
    property int columns: 4
    property string caption: ""
    property string captionStatus: ""
    property bool captionStatusAlert: false

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
    readonly property bool keyable: true

    default property alias tiles: holder.data

    readonly property bool hasCaption: caption !== "" || captionStatus !== ""
    readonly property int captionSpace: hasCaption ? metrics.caption + metrics.captionGap : 0

    implicitWidth: metrics.content
    implicitHeight: captionSpace + metrics.tile
    width: implicitWidth

    function focusItems() {
        const out = [];
        for (let i = 0; i < holder.children.length; i++) {
            const c = holder.children[i];
            if (c.visible && ("span" in c) && typeof c.activate === "function") out.push(c);
        }
        return out;
    }

    property var _wired: []
    function relayout() { Qt.callLater(row.layout); }

    function _wire(c) {
        if (row._wired.indexOf(c) >= 0) return;
        row._wired.push(c);
        c.visibleChanged.connect(row.relayout);
        if (c.spanChanged) c.spanChanged.connect(row.relayout);
        if (c.stretchChanged) c.stretchChanged.connect(row.relayout);
        const pass = ["fg", "bg", "accent", "danger", "muted", "metrics", "keyboardMode", "strings"];
        for (const p of pass)
            if (p in c) c[p] = Qt.binding(() => row[p]);
    }

    function layout() {
        const n = row.columns === 3 ? 3 : 4;
        const kids = [];
        for (let i = 0; i < holder.children.length; i++) {
            const c = holder.children[i];
            if (!("span" in c)) continue;   // Repeater e afins
            row._wire(c);
            if (c.visible) kids.push(c);
        }
        const spans = kids.map(c => Math.max(1, Math.min(n, c.span || 1)));
        let used = spans.reduce((a, b) => a + b, 0);
        if (used < n) {
            for (let i = kids.length - 1; i >= 0; i--) {
                if (kids[i].stretch) { spans[i] += n - used; used = n; break; }
            }
        }
        let c0 = 0;
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i];
            const s = Math.min(spans[i], Math.max(1, n - c0));
            k.x = row.metrics.colX(c0, n);
            k.y = 0;
            k.width = row.metrics.spanWidth(s, n);
            k.height = row.metrics.tile;
            if ("keyCol" in k) k.keyCol = c0 < n ? c0 : -1;
            if ("keySpan" in k) k.keySpan = s;
            if ("keyRow" in k) k.keyRow = row.resolvedKeyRow;
            c0 += s;
        }
    }

    onResolvedKeyRowChanged: relayout()
    onColumnsChanged: relayout()
    Component.onCompleted: layout()

    // ---------- Legenda ----------
    Item {
        visible: row.hasCaption
        width: parent.width
        height: row.metrics.caption

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width / 2)
            text: row.caption
            textFormat: Text.PlainText
            font.pixelSize: row.metrics.captionText
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            elide: Text.ElideRight
            color: row.muted
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            ContinuousRect {
                visible: row.captionStatusAlert && row.captionStatus !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: row.danger
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, row.width / 2)
                text: row.captionStatus
                textFormat: Text.PlainText
                font.pixelSize: row.metrics.captionText
                font.weight: row.captionStatusAlert ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                color: row.captionStatusAlert ? row.danger : row.muted
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(row.metrics.msState); easing.type: Easing.OutCubic } }
            }
        }
    }

    Item {
        id: holder
        y: row.captionSpace
        width: parent.width
        height: row.metrics.tile
        onChildrenChanged: row.relayout()
    }
}
