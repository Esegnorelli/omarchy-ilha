import QtQuick
import qs.Commons as Commons

// Linha de informação de 56 px (spec §3.2): ícone num círculo de 36 px, título
// e detalhe em c1–c2; até 2 botões compactos em cápsula (Tile { compact: true },
// 32 px) em c3–c4, um por
// coluna. Com um só botão visível e stretch: true ele ocupa c3–c4; sem stretch
// fica em c4. A letra de cada botão é a da coluna onde começa.
// RTL: o x dos botões é explícito, então layout() o espelha (c3/c4 ficam à
// esquerda); ícone e textos vão por âncora e viram sozinhos.
//
// API pública:
//   icon, title, detail: string   (detail em metrics.textSecondary; textos externos sempre PlainText)
//   alert: bool                   ícone em danger (por exemplo sem conexão)
//   fontFamily: string            fonte do tema (repassada aos botões)
//   keyRow: int                   -2 automático, -1, 0/1/2
//   keyboardMode, focusVisible, strings, fg, bg, accent, danger, muted, metrics   repassados aos botões
//   filhos: Tile { onActivated: … }   (os botões; compact é ligado aqui; só os 2 últimos visíveis contam)
// Funções:
//   focusItems() → [Item]         botões visíveis
//   relayout()
Item {
    id: info

    property string icon: ""
    property string title: ""
    property string detail: ""
    property bool alert: false
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
    property bool keyable: false
    // Espelhamento efetivo (herdado do Island em RTL).
    readonly property bool rtl: LayoutMirroring.enabled
    // x lógico (da borda inicial) para x na tela.
    function _mx(x, w) { return info.rtl ? info.width - x - w : x; }

    default property alias buttons: holder.data

    implicitWidth: metrics.content
    implicitHeight: metrics.info
    width: implicitWidth

    // Margem interna da superfície; os botões ficam alinhados às colunas c3/c4
    // dentro dela (a última coluna recua o mesmo que o topo e a base).
    readonly property real inset: (metrics.info - metrics.compact) / 2

    function focusItems() {
        const out = [];
        for (let i = 0; i < holder.children.length; i++) {
            const c = holder.children[i];
            if (c.visible && ("span" in c) && typeof c.activate === "function") out.push(c);
        }
        return out.slice(-2);
    }

    property var _wired: []
    function relayout() { Qt.callLater(info.layout); }

    function layout() {
        const kids = [];
        for (let i = 0; i < holder.children.length; i++) {
            const c = holder.children[i];
            if (!("span" in c)) continue;
            if (info._wired.indexOf(c) < 0) {
                info._wired.push(c);
                c.visibleChanged.connect(info.relayout);
                if (c.stretchChanged) c.stretchChanged.connect(info.relayout);
                for (const p of ["fg", "bg", "accent", "danger", "muted", "metrics", "keyboardMode", "focusVisible", "strings", "fontFamily"])
                    if (p in c) c[p] = Qt.binding(() => info[p]);
                if ("compact" in c) c.compact = true;
            }
            if (c.visible) kids.push(c);
        }
        const shown = kids.slice(-2);

        const left = info.metrics.colX(2, 4);
        const right = info.metrics.content - info.inset;
        const w = (right - left - info.metrics.gap) / 2;
        const placeAt = (k, col, span) => {
            k.width = span === 2 ? right - left : w;
            k.x = info._mx(left + (col - 2) * (w + info.metrics.gap), k.width);
            k.y = info.inset;
            k.height = info.metrics.compact;
            if ("keyCol" in k) k.keyCol = col;
            if ("keySpan" in k) k.keySpan = span;
            if ("keyRow" in k) k.keyRow = info.resolvedKeyRow;
        };
        if (shown.length === 2) {
            placeAt(shown[0], 2, 1);
            placeAt(shown[1], 3, 1);
        } else if (shown.length === 1) {
            if (shown[0].stretch) placeAt(shown[0], 2, 2);
            else placeAt(shown[0], 3, 1);
        }
        info.keyable = shown.length > 0;
    }

    onResolvedKeyRowChanged: relayout()
    onRtlChanged: relayout()
    onWidthChanged: relayout()
    Component.onCompleted: layout()

    ContinuousRect {
        anchors.fill: parent
        radius: info.metrics.cardRadius
        color: Qt.rgba(info.fg.r, info.fg.g, info.fg.b, info.metrics.alphaIdle)
    }

    Row {
        // Âncora (e não x) para espelhar em RTL.
        anchors.left: parent.left
        anchors.leftMargin: 12
        width: info.metrics.colX(2, 4) - 12 - info.metrics.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        ContinuousRect {
            id: infoIcon
            visible: info.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: info.metrics.fit(18)
            color: Qt.rgba(info.fg.r, info.fg.g, info.fg.b, 0.10)

            Icon {
                anchors.centerIn: parent
                name: info.icon
                size: info.metrics.tileIcon
                color: info.alert ? info.danger : info.fg
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(info.metrics.msState); easing.type: Easing.OutCubic } }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (infoIcon.visible ? infoIcon.width + 12 : 0)
            spacing: 1
            Text {
                width: parent.width
                // Explícito para virar com o espelhamento: título latino e
                // detalhe em árabe ficam na mesma borda.
                horizontalAlignment: Text.AlignLeft
                text: info.title
                textFormat: Text.PlainText
                font.family: info.fontFamily
                font.pixelSize: info.metrics.tileLabel
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                color: info.fg
            }
            Text {
                width: parent.width
                visible: text !== ""
                horizontalAlignment: Text.AlignLeft
                text: info.detail
                textFormat: Text.PlainText
                font.family: info.fontFamily
                font.pixelSize: info.metrics.tileSublabel
                elide: Text.ElideRight
                color: info.metrics.textSecondary
            }
        }
    }

    Item {
        id: holder
        anchors.fill: parent
        onChildrenChanged: info.relayout()
    }
}
