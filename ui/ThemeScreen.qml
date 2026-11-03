pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import "Motion.js" as Motion

// Seletor de temas (screens §12; dono: Agent G). Painel 30 + 194k x 222
// (k = 2..4 cartões pela largura da tela), cap 30. Cresce da pílula.
//
// Duas camadas (motion F):
// - CABEÇALHO, preso às bordas vivas da forma (só x): lupa 13 a 16 px da
//   borda, o campo de busca a 40 px (largura fixa w − 146) e o contador
//   "12/18" a 16 px da borda direita. Centro em y 29. Sem título e sem
//   fundo de campo, como no vídeo.
// - CORPO, no layout final centrado: a faixa de cartões 187 x 98 (passo 194)
//   recortada em exatamente k passos (o vizinho ±2 aparece pela metade) e o
//   rodapé "Enter para aplicar".
//
// Cartão: o fundo do próprio tema, seis bolinhas de 14 px (as cores 1–6 do
// tema), o nome na cor de texto do tema. O escolhido sobe 8 px (140 ms) e
// ganha uma borda interna de 2 px no rawAccent do tema APLICADO (150 ms); os
// outros têm um aro de 1 px (tinta 5%) e opacidade 0,7^|d|. A bolinha de 6 px
// no canto marca o tema aplicado (ou o pedido agora, no quadro do Enter).
//
// Teclas (vêm do campo pelo navKey; `ilha run themes <tecla>` usa handleKey):
// ←/→ (trocadas em RTL), ↑/↓, Tab, PgUp/PgDn ±4, Home/End, Enter aplica, Esc
// limpa a busca e depois fecha. Mouse: clique centraliza, clique no do centro
// ou duplo clique aplica; roda um passo por 120.
//
// Aplicar: a marca pula na hora, `omarchy-theme-set` roda e a tela fecha
// quando o theme.name confirma, ou 1,5 s depois do Enter. Sem prévia ao vivo:
// as cores da ilha cruzam em 150 ms quando o host empurra a paleta.
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
    property list<Item> headerItems: [header]
    property list<Item> bodyItems: [body]
    signal navigate(string id, var payload)
    signal closeRequested()

    function opened(payload) {
        root.snapping = true;
        priv.waiting = false;
        applyFallback.stop();
        priv.userMoved = false;
        if (field.text !== "")
            field.clear();
        if (root.themesSvc)
            root.themesSvc.reload();
        root.resync();
        Qt.callLater(root.focusField);
        Qt.callLater(() => root.snapping = false);
    }

    function closed() {
        priv.waiting = false;
        applyFallback.stop();
    }

    // Teclas que chegaram pela janela (ilha run, ou sem foco no campo).
    // Esc e Ctrl+Tab ficam com a janela.
    function handleKey(event) {
        return root.nav(event, false);
    }

    function handleEscape() {
        if (field.text !== "") {
            field.clear();
            return true;
        }
        return false;
    }

    // ---- Medidas ----
    readonly property var dims: root.theme && root.island ? root.theme.screenSize("themes", root.island.screenGeometry(root.island.screenOutput)) : ({ w: 806, h: 222, k: 4 })
    implicitWidth: root.dims.w
    implicitHeight: root.dims.h

    readonly property real pitch: root.theme ? root.theme.px.THEMES_PITCH : 194
    // Recorte da faixa: exatamente k passos, centrado (15 px de cada lado).
    readonly property real inset: Math.max(12, (root.implicitWidth - root.pitch * Math.max(1, root.dims.k)) / 2)
    readonly property real liftPx: Motion.FADE.THEME_LIFT.px
    readonly property bool rtl: root.theme ? root.theme.rtl : false

    // ---- Dados ----
    readonly property var themesSvc: root.island ? root.island.themes : null
    readonly property var all: root.themesSvc ? root.themesSvc.themes : []
    readonly property var list: root.filterThemes(root.all, field.text)
    // A marca: o pedido agora (pula no Enter) ou o aplicado.
    readonly property string currentSlug: root.themesSvc ? (root.themesSvc.pendingCurrent || root.themesSvc.current) : ""

    function filterThemes(list, query) {
        const q = String(query || "").trim().toLowerCase();
        if (q === "")
            return list;
        return list.filter(t => t.slug.indexOf(q) !== -1 || t.name.toLowerCase().indexOf(q) !== -1);
    }

    function indexOfSlug(slug) {
        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i].slug === slug)
                return i;
        }
        return -1;
    }

    function digits(n) {
        return Commons.I18n.formatNumber(n);
    }

    // Recentra: no tema aplicado enquanto ninguém mexeu; depois, no escolhido.
    function resync() {
        let i = root.indexOfSlug(priv.userMoved ? priv.selSlug : root.currentSlug);
        if (i < 0)
            i = root.indexOfSlug(root.currentSlug);
        if (i < 0)
            i = 0;
        strip.jump(i, false);
        root.noteIndex();
    }

    function noteIndex() {
        const t = root.list[strip.index];
        priv.selSlug = t ? t.slug : "";
    }

    function move(n) {
        priv.userMoved = true;
        strip.step(n);
    }

    function focusField() {
        if (root.current && root.visible)
            field.focusField();
    }

    function activate(i) {
        priv.userMoved = true;
        if (i !== strip.index)
            strip.jump(i, true);
        root.applySelected();
    }

    function applySelected() {
        const t = root.list[strip.index];
        if (!t || priv.waiting || !root.themesSvc)
            return;
        if (t.slug === root.currentSlug) {
            // Já é o tema: nada para aplicar.
            root.closeRequested();
            return;
        }
        if (!root.themesSvc.apply(t.slug))
            return;
        priv.waiting = true;
        applyFallback.restart();
    }

    // Uma tecla. fromField: veio do campo (Esc e Ctrl+Tab são tratados aqui,
    // porque o campo já aceitou o evento e a janela não o vê).
    function nav(event, fromField) {
        const k = event.key;
        const mods = event.modifiers;
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            if (mods & Qt.ControlModifier) {
                if (!fromField)
                    return false;
                if (root.island)
                    root.island.cycle(k === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1);
                return true;
            }
            root.move(k === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1);
            return true;
        }
        const dir = root.theme ? root.theme.dir : 1;
        switch (k) {
        case Qt.Key_Left:
            root.move(-dir);
            return true;
        case Qt.Key_Right:
            root.move(dir);
            return true;
        case Qt.Key_Up:
            root.move(-1);
            return true;
        case Qt.Key_Down:
            root.move(1);
            return true;
        case Qt.Key_PageUp:
            root.move(-4);
            return true;
        case Qt.Key_PageDown:
            root.move(4);
            return true;
        case Qt.Key_Home:
            priv.userMoved = true;
            strip.jump(0, true);
            return true;
        case Qt.Key_End:
            priv.userMoved = true;
            strip.jump(root.list.length - 1, true);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.applySelected();
            return true;
        case Qt.Key_Escape:
            if (!fromField)
                return false;
            if (!root.handleEscape())
                root.closeRequested();
            return true;
        default:
            return false;
        }
    }

    // Lado esquerdo / direito no cabeçalho (bordas vivas), espelhado em RTL.
    function fromStart(off, w) {
        return root.rtl ? root.edgeRight - off - w : root.edgeLeft + off;
    }
    function fromEnd(off, w) {
        return root.rtl ? root.edgeLeft + off : root.edgeRight - off - w;
    }
    // No corpo (layout final): espelho em torno do centro do painel.
    function bodyX(x, w) {
        return root.rtl ? root.implicitWidth - x - w : x;
    }

    QtObject {
        id: priv
        property bool waiting: false
        property bool userMoved: false
        property string selSlug: ""
    }

    // Depois da troca: o count da faixa precisa já ter a lista nova.
    onListChanged: Qt.callLater(root.resync)
    onCurrentSlugChanged: {
        if (!priv.userMoved)
            Qt.callLater(root.resync);
    }
    // O campo só pega o foco visível (opened() roda antes do fade).
    onVisibleChanged: if (root.visible) Qt.callLater(root.focusField)
    onCurrentChanged: if (root.current) Qt.callLater(root.focusField)

    // Fecha sem esperar a confirmação depois de 1,5 s.
    Timer {
        id: applyFallback
        interval: Motion.TIMING.THEME_APPLY_FALLBACK_MS
        onTriggered: {
            if (!priv.waiting)
                return;
            priv.waiting = false;
            root.closeRequested();
        }
    }

    Connections {
        target: root.themesSvc
        function onApplied() {
            if (!priv.waiting)
                return;
            priv.waiting = false;
            applyFallback.stop();
            if (root.current)
                root.closeRequested();
        }
    }

    // ---- Cabeçalho (x preso às bordas vivas) ----
    Item {
        id: header
        width: root.implicitWidth
        height: 58

        Icon {
            x: root.fromStart(16, width)
            y: 29 - height / 2
            name: "search"
            size: 13
            color: root.theme ? root.theme.inkFaint : "gray"
        }

        FilterField {
            id: field
            x: root.fromStart(40, width)
            y: 29 - height / 2
            width: Math.max(120, root.implicitWidth - 146)
            theme: root.theme
            placeholder: root.strings ? root.strings.t("themes.search") : ""
            fontSize: 15
            onNavKey: event => root.nav(event, true)
        }

        IlhaText {
            id: counter
            x: root.fromEnd(16, width)
            y: 29 - height / 2
            theme: root.theme
            size: 12
            weight: 500
            tnum: true
            color: root.theme ? root.theme.inkFaint : "gray"
            opacity: root.list.length > 0 ? 1 : 0
            text: root.strings && root.list.length > 0
                ? root.strings.t("common.counter").arg(root.digits(strip.index + 1)).arg(root.digits(root.list.length))
                : ""
        }
    }

    // ---- Corpo (layout final, centrado) ----
    Item {
        id: body
        width: root.implicitWidth
        height: root.implicitHeight

        Carousel {
            id: strip
            x: root.inset
            // Cartão parado em y 68,5 do painel; o escolhido em 60,5.
            y: 52.5
            width: root.implicitWidth - 2 * root.inset
            height: 130
            count: root.list.length
            pitch: root.pitch
            itemWidth: 187
            itemHeight: 98
            dir: root.theme ? root.theme.dir : 1
            snapping: root.snapping
            reduceMotion: root.theme ? root.theme.reduceMotion : false
            delegate: cardDelegate
            onActivated: i => root.activate(i)
            onMoved: priv.userMoved = true
            onIndexChanged: root.noteIndex()
        }

        IlhaText {
            x: (root.implicitWidth - width) / 2
            y: 117 - height / 2
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            opacity: field.text !== "" && root.list.length === 0 ? 1 : 0
            text: root.strings ? root.strings.t("themes.empty") : ""
        }

        IlhaText {
            x: root.bodyX(root.implicitWidth - 16 - width, width)
            y: 199 - height / 2
            theme: root.theme
            size: 12
            weight: 500
            color: root.theme ? root.theme.inkFaint : "gray"
            opacity: root.list.length > 0 ? 1 : 0
            text: root.strings ? root.strings.t("common.enterToApply") : ""
        }
    }

    // ---- Cartão de um tema ----
    Component {
        id: cardDelegate

        Item {
            id: card
            property int index: 0
            property real d: 0
            property bool selected: false
            readonly property var t: root.list[card.index] || ({})
            readonly property bool applied: card.t.slug !== undefined && card.t.slug === root.currentSlug

            opacity: Math.pow(0.7, Math.abs(card.d))
            Accessible.role: Accessible.ListItem
            Accessible.name: card.t.name || ""
            Accessible.selected: card.selected

            Item {
                id: lift
                width: card.width
                height: card.height
                y: card.selected ? -root.liftPx : 0
                Behavior on y {
                    enabled: !root.snapping
                    // Sobe em 140 ms; o que perde a seleção desce em 180.
                    NumberAnimation {
                        duration: root.theme ? root.theme.dur(card.selected ? Motion.FADE.THEME_LIFT.dur : 180) : 0
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 13.5
                    antialiasing: true
                    color: card.t.bg || (root.theme ? root.theme.card : "black")
                }
                // Aro de 1 px (tinta 5%) em todos.
                Rectangle {
                    anchors.fill: parent
                    radius: 13.5
                    antialiasing: true
                    color: "transparent"
                    border.width: 1
                    border.color: root.theme ? root.theme.alpha(root.theme.ink, 0.05) : "transparent"
                }
                // Borda do escolhido: 2 px por dentro, no accent do tema aplicado.
                Rectangle {
                    anchors.fill: parent
                    radius: 13.5
                    antialiasing: true
                    color: "transparent"
                    border.width: 2
                    border.color: root.theme ? root.theme.rawAccent : "white"
                    opacity: card.selected ? 1 : 0
                    Behavior on opacity {
                        enabled: !root.snapping
                        NumberAnimation {
                            duration: root.theme ? root.theme.dur(Motion.FADE.THEME_BORDER) : 0
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Seis bolinhas de 14 px, passo 17,5, centros a 40,5 do topo.
                Row {
                    x: (card.width - (5 * 17.5 + 14)) / 2
                    y: 40.5 - 7
                    spacing: 3.5
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            width: 14
                            height: 14
                            radius: 7
                            antialiasing: true
                            color: card.t.dots && card.t.dots[index] ? card.t.dots[index]
                                : (root.theme ? root.theme.alpha(card.t.fg || root.theme.ink, 0.25) : "gray")
                        }
                    }
                }

                IlhaText {
                    x: 12
                    width: card.width - 24
                    y: 80 - height / 2
                    theme: root.theme
                    size: 12
                    weight: 500
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: card.t.fg || (root.theme ? root.theme.ink : "white")
                    text: card.t.slug || ""
                }

                // Tema aplicado: bolinha de 6 px a 10,5 do canto de cima (espelhada em RTL).
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    antialiasing: true
                    x: root.rtl ? 10.5 - 3 : card.width - 10.5 - 3
                    y: 10.5 - 3
                    color: root.theme ? root.theme.accent : "white"
                    opacity: card.applied ? 1 : 0
                }
            }
        }
    }
}
