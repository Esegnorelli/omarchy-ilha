import QtQuick
import qs.Commons as Commons

// Linha de Tiles da grade (spec §3.2 TileRow). Os filhos (Tile) são postos
// lado a lado pelo span na grade 128 + 8 (ou 3 colunas iguais, Energia).
// O último filho visível com stretch: true estica até a última coluna.
// Se algum filho tem shape "round", a linha vira cápsulas + círculos: cada
// round tem tileHeight de largura e as cápsulas dividem o resto; as letras
// seguem a ordem dos filhos (Q W E R).
// RTL: o x é explícito (não espelha sozinho), então layout() espelha a
// posição; a ordem e as letras seguem a leitura (Q é o primeiro à direita).
// As setas do PanelGrid andam pela posição na tela e viram junto.
//
// API pública:
//   keyRow: int              -2 = automático (o PanelGrid conta as linhas com tecla), -1 = sem tecla, 0/1/2 = fixo
//   columns: 4 | 3
//   tileHeight: int          altura dos tiles (metrics.tile; o Controle usa metrics.capsuleTile)
//   caption: string          legenda opcional de 16 px acima (12 Medium, fg a 60%, como frase)
//   captionStatus: string    estado ao vivo à direita da legenda
//   captionStatusAlert: bool estado em danger (por exemplo "● Gravando 00:42")
//   keyboardMode, focusVisible, strings, fg, bg, accent, danger, muted, metrics, fontFamily
//                            repassados aos Tiles (focusVisible vem do PanelGrid)
//   readonly resolvedKeyRow  linha de tecla efetiva
//   autoKeyRow               escrito pelo PanelGrid
// Funções:
//   focusItems() → [Item]    tiles visíveis (para teclas e setas)
//   relayout()
Item {
    id: row

    property int keyRow: -2
    property int columns: 4
    property int tileHeight: metrics.tile
    property string caption: ""
    property string captionStatus: ""
    property bool captionStatusAlert: false

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
    readonly property bool keyable: true
    // Espelhamento efetivo (herdado do Island em RTL).
    readonly property bool rtl: LayoutMirroring.enabled

    default property alias tiles: holder.data

    readonly property bool hasCaption: caption !== "" || captionStatus !== ""
    readonly property int captionSpace: hasCaption ? metrics.caption + metrics.captionGap : 0

    implicitWidth: metrics.content
    implicitHeight: captionSpace + tileHeight
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
        if (c.shapeChanged) c.shapeChanged.connect(row.relayout);
        const pass = ["fg", "bg", "accent", "danger", "muted", "metrics", "keyboardMode", "focusVisible", "strings", "fontFamily"];
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
        const h = row.tileHeight;
        // x lógico (da borda inicial) para x na tela.
        const place = (lx, w) => row.rtl ? row.width - lx - w : lx;
        // Cápsulas e círculos: round = h de largura, as cápsulas dividem o resto.
        if (kids.some(c => c.shape === "round")) {
            const rounds = kids.filter(c => c.shape === "round").length;
            const caps = kids.length - rounds;
            const free = row.width - rounds * h - Math.max(0, kids.length - 1) * row.metrics.gap;
            const capW = caps > 0 ? Math.max(h, free / caps) : 0;
            let x = 0;
            for (let i = 0; i < kids.length; i++) {
                const k = kids[i];
                const w = k.shape === "round" ? h : capW;
                k.x = place(x, w);
                k.y = 0;
                k.width = w;
                k.height = h;
                if ("keyCol" in k) k.keyCol = i < 4 ? i : -1;
                if ("keySpan" in k) k.keySpan = 1;
                if ("keyRow" in k) k.keyRow = row.resolvedKeyRow;
                x += w + row.metrics.gap;
            }
            return;
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
            const w = row.metrics.spanWidth(s, n);
            k.x = place(row.metrics.colX(c0, n), w);
            k.y = 0;
            k.width = w;
            k.height = h;
            if ("keyCol" in k) k.keyCol = c0 < n ? c0 : -1;
            if ("keySpan" in k) k.keySpan = s;
            if ("keyRow" in k) k.keyRow = row.resolvedKeyRow;
            c0 += s;
        }
    }

    onResolvedKeyRowChanged: relayout()
    onColumnsChanged: relayout()
    onTileHeightChanged: relayout()
    onWidthChanged: relayout()
    onRtlChanged: relayout()
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
            font.family: row.fontFamily
            font.pixelSize: 12
            font.weight: Font.Medium
            font.capitalization: Font.MixedCase
            font.letterSpacing: 0
            elide: Text.ElideRight
            color: Qt.rgba(row.fg.r, row.fg.g, row.fg.b, 0.6)
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
                font.family: row.fontFamily
                font.pixelSize: row.metrics.captionText
                font.weight: row.captionStatusAlert ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                color: row.captionStatusAlert ? row.danger : row.metrics.textSecondary
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(row.metrics.msState); easing.type: Easing.OutCubic } }
            }
        }
    }

    Item {
        id: holder
        y: row.captionSpace
        width: parent.width
        height: row.tileHeight
        onChildrenChanged: row.relayout()
    }
}
