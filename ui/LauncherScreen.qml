pragma ComponentBehavior: Bound

import QtQuick
import "Motion.js" as Motion

// Lançador (screens §10; estudo "launcher"). Dono: Agent F.
//
// Painel 514 x 368, cap 27, altura fixa. Duas camadas (motion F):
// - Cabeçalho (headerItems): lupa e campo de busca com x preso às bordas
//   vivas da forma (edgeLeft / edgeRight), tamanho fixo. Entram em 60 ms
//   desde T0 + 16, sem desfoque (a pilha cuida do fade).
// - Corpo (bodyItems): divisória, lista e aviso de vazio no layout final;
//   entram em 100 ms depois de 70 ms, com desfoque (a pilha cuida).
//
// Medidas (vídeo, 1080p): lupa com tinta de 13,5 px a partir de +15,75 e
// centro em y 31,5 (glifo 18: a tinta do "search" ocupa 0,73 da caixa);
// campo em +42 com 458 de largura; divisória de 1 px em y 60, x 14..500;
// lista em y 72, linhas de 47, 6 visíveis (sem rolagem visível, sem 7ª
// linha); destaque 486 x 46, raio 8, tinta a 12%, barra accent 3 x 23 em
// +1,5; ladrilho 33 (raio 9, tinta 6,5%) em +10,5 com o ícone de 21; nome
// em +56. Os tamanhos de texto seguem as larguras medidas no vídeo (a Inter
// é mais larga que a fonte dele): nome 14/600 ("Bluetooth Manager" 128 px
// contra 127,5), descrição 11/400 (211 contra 215), busca 14 (o vídeo diz
// "mesmo tamanho dos nomes").
//
// Seleção: um destaque só, que desliza 180 ms OutCubic (0 com snapping ou
// num salto). A lista rola junto, com a mesma curva, para a linha escolhida
// ficar à vista. O hover move o destaque só quando o ponteiro ANDA (um
// ponteiro parado sobre a lista que abre, rola ou se refaz a cada tecla
// nunca rouba a seleção, para o Enter não abrir o app errado); a seleção
// fica onde o hover deixou. A roda rola a lista; se a seleção sair de vista,
// passa para a primeira linha inteira à vista.
//
// Teclas (o campo repassa no próprio Keys.onPressed, então o TextInput não
// come nenhuma): Up/Down e Tab/Shift+Tab (dão a volta, num salto), PgUp/PgDn
// ±6, Enter abre e fecha, Esc limpa e, com o campo vazio, fecha. Left/Right,
// Home/End ficam com o texto. Ctrl+Tab troca de tela.
//
// Consulta vazia: todos os apps visíveis, A–Z; com texto, pela pontuação do
// AppSearch.js (island.apps). Sem resultado: "Nenhum app encontrado".
// Nada roda antes de opened() (o cursor do campo só pisca com foco).
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

    implicitWidth: 514
    implicitHeight: 368

    // ---- Medidas ----
    readonly property real pitch: 47
    readonly property int visibleRows: 6
    readonly property real listTop: 72
    readonly property real inset: 14
    readonly property real listW: root.implicitWidth - 2 * root.inset
    readonly property int pageRows: 6

    readonly property bool rtl: !!root.theme && root.theme.rtl
    readonly property var apps: root.island ? root.island.apps : null
    readonly property var rows: root.apps ? root.apps.results(field.text) : []

    // ---- Contrato: abrir / fechar / teclas ----

    function opened(payload) {
        root.snapping = true;
        priv.quiet = true;
        field.clear();
        priv.quiet = false;
        root.resetSelection();
        priv.lastPoint = Qt.point(-1, -1);
        if (root.apps)
            root.apps.refresh();
        field.focusField();
        Qt.callLater(() => root.snapping = false);
    }

    function closed() {
        scrollAnim.stop();
        priv.lastPoint = Qt.point(-1, -1);
    }

    // Teclas que chegam à tela (foco fora do campo, ou `ilha run launcher <tecla>`).
    function handleKey(event) {
        if (root.navKey(event))
            return true;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods !== 0)
            return false;
        if (event.key === Qt.Key_Backspace) {
            root.erase();
            return true;
        }
        const t = String(event.text || "");
        if (t.length === 1 && t >= " " && t !== "\u007f") {
            root.typeText(t);
            return true;
        }
        return false;
    }

    // Esc: primeiro limpa a busca; com o campo vazio, a janela fecha.
    function handleEscape() {
        if (field.text !== "") {
            field.clear();
            return true;
        }
        return false;
    }

    // ---- Navegação ----

    // As teclas de lista (do campo ou da tela). true = tratada.
    function navKey(event) {
        const ctrl = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0;
        switch (event.key) {
        case Qt.Key_Up:
            root.move(-1, true);
            return true;
        case Qt.Key_Down:
            root.move(1, true);
            return true;
        case Qt.Key_Tab:
            if (ctrl)
                return false;
            root.move((event.modifiers & Qt.ShiftModifier) ? -1 : 1, true);
            return true;
        case Qt.Key_Backtab:
            if (ctrl)
                return false;
            root.move(-1, true);
            return true;
        case Qt.Key_PageUp:
            root.move(-root.pageRows, false);
            return true;
        case Qt.Key_PageDown:
            root.move(root.pageRows, false);
            return true;
        case Qt.Key_Home:
            root.select(0, false, true);
            return true;
        case Qt.Key_End:
            root.select(root.rows.length - 1, false, true);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate(priv.selected);
            return true;
        default:
            return false;
        }
    }

    // Do campo (Keys.onPressed dele já aceitou o evento).
    function fieldKey(event) {
        if (root.island)
            root.island.keyboardMode = true;
        if (root.navKey(event))
            return;
        const k = event.key;
        if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && (event.modifiers & Qt.ControlModifier)) {
            if (root.island)
                root.island.cycle(k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
            return;
        }
        if (k === Qt.Key_Escape && !root.handleEscape())
            root.closeRequested();
    }

    // Escolhe a linha i. animate: o destaque desliza; scroll: a lista rola até ela.
    function select(i, animate, scroll) {
        const n = root.rows.length;
        if (n === 0) {
            priv.selected = -1;
            return;
        }
        const k = Math.max(0, Math.min(n - 1, i));
        priv.jump = !animate;
        priv.selected = k;
        priv.jump = false;
        if (scroll)
            root.ensureVisible(k, animate);
    }

    // Passo de teclado. wrap: dá a volta nas pontas (num salto, sem varrer a lista).
    function move(delta, wrap) {
        const n = root.rows.length;
        if (n === 0)
            return;
        const at = priv.selected < 0 ? 0 : priv.selected;
        const k = at + delta;
        if (wrap && (k < 0 || k >= n)) {
            root.select(((k % n) + n) % n, false, true);
            return;
        }
        root.select(k, true, true);
    }

    function resetSelection() {
        scrollAnim.stop();
        root.select(0, false, false);
        list.positionViewAtBeginning();
    }

    // Rola o mínimo para a linha i ficar inteira à vista.
    function ensureVisible(i, animate) {
        if (i < 0)
            return;
        const top = list.originY + i * root.pitch;
        const bottom = top + root.pitch;
        const minY = list.originY;
        const maxY = Math.max(minY, list.originY + list.contentHeight - list.height);
        let y = scrollAnim.running ? scrollAnim.to : list.contentY;
        if (top < y)
            y = top;
        else if (bottom > y + list.height)
            y = bottom - list.height;
        y = Math.max(minY, Math.min(maxY, y));
        scrollAnim.stop();
        if (Math.abs(y - list.contentY) < 0.5)
            return;
        if (animate && !root.snapping && root.theme && !root.theme.reduceMotion) {
            scrollAnim.from = list.contentY;
            scrollAnim.to = y;
            scrollAnim.start();
        } else {
            list.contentY = y;
        }
    }

    // A roda tirou a seleção de vista: fica a primeira linha inteira à vista.
    function keepSelectionInView() {
        const n = root.rows.length;
        if (n === 0 || priv.selected < 0)
            return;
        const top = list.originY + priv.selected * root.pitch;
        if (top >= list.contentY - 1 && top + root.pitch <= list.contentY + list.height + 1)
            return;
        const first = Math.ceil((list.contentY - list.originY - 1) / root.pitch);
        root.select(first, false, false);
    }

    // O ponteiro andou sobre a lista (posição no sistema da lista).
    function pointerMoved(p) {
        const last = priv.lastPoint;
        if (Math.abs(p.x - last.x) < 0.5 && Math.abs(p.y - last.y) < 0.5)
            return;
        const first = last.x < 0;
        priv.lastPoint = p;
        // A primeira leitura só marca: o ponteiro já estava ali quando a lista surgiu.
        if (first)
            return;
        const i = list.indexAt(p.x, p.y + list.contentY);
        if (i >= 0 && i !== priv.selected)
            root.select(i, true, false);
    }

    function activate(i) {
        const r = root.rows[i];
        if (!r || !root.apps)
            return;
        if (root.apps.launch(r.id, r.name))
            root.closeRequested();
    }

    // Texto que chegou fora do campo: entra no campo (o FilterField não tem
    // insert(); o TextField é o único filho visual dele).
    function fieldInput() {
        const kids = field.children;
        for (let i = 0; i < kids.length; i++) {
            if (typeof kids[i].insert === "function")
                return kids[i];
        }
        return null;
    }

    function typeText(t) {
        field.focusField();
        const input = root.fieldInput();
        if (input)
            input.insert(input.cursorPosition, t);
    }

    function erase() {
        const input = root.fieldInput();
        if (input && input.cursorPosition > 0)
            input.remove(input.cursorPosition - 1, input.cursorPosition);
    }

    onRowsChanged: root.resetSelection()

    QtObject {
        id: priv
        property int selected: 0
        // Próxima troca de seleção sem deslizar.
        property bool jump: false
        // Limpeza programática do campo (não é digitação).
        property bool quiet: false
        property point lastPoint: Qt.point(-1, -1)
    }

    // ---- Cabeçalho (x preso às bordas vivas; tamanho fixo) ----
    Item {
        id: header
        width: root.implicitWidth
        height: 60

        Icon {
            id: glass
            // Tinta do glifo em +15,75 (a caixa de 18 tem 2,25 de folga).
            x: root.rtl ? root.edgeRight - 13.5 - glass.width : root.edgeLeft + 13.5
            y: 31.5 - glass.height / 2
            name: "search"
            size: 18
            color: root.theme ? root.theme.inkFaint : "gray"
        }

        FilterField {
            id: field
            x: root.rtl ? root.edgeRight - 42 - field.width : root.edgeLeft + 42
            y: 31.5 - field.height / 2
            width: 458
            theme: root.theme
            fontSize: 14
            placeholder: root.strings ? root.strings.t("launcher.search") : ""
            // Left/Right e Home/End ficam com o texto; o resto anda a lista.
            forwarded: [Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_Return, Qt.Key_Enter,
                Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Escape]
            onNavKey: event => root.fieldKey(event)
            onTextEdited: {
                if (!priv.quiet && root.island && root.current)
                    root.island.keyboardMode = true;
            }
        }
    }

    // ---- Corpo (layout final, centrado) ----
    Item {
        id: body
        width: root.implicitWidth
        height: root.implicitHeight

        // Divisória de 1 px com pontas suaves (3 px).
        Rectangle {
            x: root.inset
            y: 60
            width: root.listW
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.theme ? root.theme.alpha(root.theme.ink, 0) : "transparent" }
                GradientStop { position: 3 / root.listW; color: root.theme ? root.theme.alpha(root.theme.ink, 0.05) : "transparent" }
                GradientStop { position: 1 - 3 / root.listW; color: root.theme ? root.theme.alpha(root.theme.ink, 0.05) : "transparent" }
                GradientStop { position: 1; color: root.theme ? root.theme.alpha(root.theme.ink, 0) : "transparent" }
            }
        }

        Item {
            id: listArea
            x: root.inset
            y: root.listTop
            width: root.listW
            height: root.visibleRows * root.pitch

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: root.rows
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                highlightRangeMode: ListView.NoHighlightRange
                currentIndex: -1
                pressDelay: 0
                reuseItems: true
                Accessible.role: Accessible.List
                Accessible.name: root.strings ? root.strings.t("cc.apps") : ""

                onMovementStarted: scrollAnim.stop()
                onMovementEnded: root.keepSelectionInView()

                // O destaque: um só, atrás das linhas, deslizando na própria curva.
                Item {
                    id: highlight
                    parent: list.contentItem
                    z: 0
                    x: 0
                    y: list.originY + Math.max(0, priv.selected) * root.pitch
                    width: list.width
                    height: root.pitch
                    opacity: root.rows.length > 0 && priv.selected >= 0 ? 1 : 0

                    Behavior on y {
                        enabled: !root.snapping && !priv.jump
                        NumberAnimation {
                            duration: root.theme ? root.theme.dur(Motion.FADE.LAUNCHER_HIGHLIGHT) : 0
                            easing.type: Easing.OutCubic
                        }
                    }

                    Rectangle {
                        y: 0.5
                        width: parent.width
                        height: 46
                        radius: 8
                        color: root.theme ? root.theme.alpha(root.theme.ink, 0.12) : "transparent"

                        // Barra accent do lado de dentro da borda inicial (espelha no RTL).
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 1.5
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 23
                            radius: 1.5
                            color: root.theme ? root.theme.accent : "white"
                        }
                    }
                }

                delegate: Item {
                    id: row

                    required property var modelData
                    required property int index

                    readonly property string desc: String(row.modelData.desc || "")

                    z: 1
                    width: list.width
                    height: root.pitch

                    Accessible.role: Accessible.ListItem
                    Accessible.name: String(row.modelData.name || "")
                    Accessible.description: row.desc
                    Accessible.selected: row.index === priv.selected

                    // Ladrilho do ícone.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 10.5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 33
                        height: 33
                        radius: 9
                        color: root.theme ? root.theme.alpha(root.theme.ink, 0.065) : "transparent"

                        Image {
                            id: appImage
                            anchors.centerIn: parent
                            width: 21
                            height: 21
                            sourceSize: Qt.size(42, 42)
                            source: root.apps ? root.apps.iconSource(row.modelData.iconName) : ""
                            fillMode: Image.PreserveAspectFit
                            // Do cache depois da primeira vez: os ícones não "pipocam".
                            asynchronous: false
                            smooth: true
                            mipmap: true
                            opacity: appImage.status === Image.Ready ? 1 : 0
                        }

                        // Sem ícone que carregue: o glifo de apps.
                        Icon {
                            anchors.centerIn: parent
                            name: "apps"
                            size: 18
                            color: root.theme ? root.theme.inkMuted : "gray"
                            opacity: appImage.status === Image.Ready ? 0 : 1
                        }
                    }

                    // Nome: linha de base em +21 (com descrição) ou centrado (sem).
                    IlhaText {
                        id: nameText
                        anchors.left: parent.left
                        anchors.leftMargin: 56
                        width: list.width - 56 - 14
                        y: (row.desc !== "" ? 21 : 28.6) - nameText.baselineOffset
                        theme: root.theme
                        size: 14
                        weight: 600
                        // Explícito: o LayoutMirroring vira para a direita em RTL; implícito,
                        // o Qt alinha pela escrita do texto e nomes latinos ficam longe do ícone.
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: String(row.modelData.name || "")
                    }

                    // Descrição (GenericName, senão Comment): linha de base em +36.
                    IlhaText {
                        id: descText
                        anchors.left: parent.left
                        anchors.leftMargin: 56
                        width: list.width - 56 - 14
                        y: 36 - descText.baselineOffset
                        theme: root.theme
                        size: 11
                        weight: 400
                        color: root.theme ? root.theme.inkMuted : "gray"
                        // Explícito: o LayoutMirroring vira para a direita em RTL; implícito,
                        // o Qt alinha pela escrita do texto e nomes latinos ficam longe do ícone.
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        opacity: row.desc !== "" ? 1 : 0
                        text: row.desc
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: {
                            root.select(row.index, false, false);
                            root.activate(row.index);
                        }
                    }
                }
            }

            // Hover: só o movimento real do ponteiro escolhe a linha.
            HoverHandler {
                id: listHover
                cursorShape: root.rows.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPointChanged: {
                    if (listHover.hovered)
                        root.pointerMoved(listHover.point.position);
                }
                onHoveredChanged: {
                    if (!listHover.hovered)
                        priv.lastPoint = Qt.point(-1, -1);
                }
            }
        }

        // Sem resultado: o aviso no meio do bloco da lista.
        IlhaText {
            x: root.inset
            y: root.listTop + (root.visibleRows * root.pitch - height) / 2
            width: root.listW
            horizontalAlignment: Text.AlignHCenter
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            elide: Text.ElideRight
            opacity: root.rows.length === 0 ? 1 : 0
            text: root.strings ? root.strings.t("launcher.empty") : ""
        }
    }

    // A lista rola com a mesma curva e duração do destaque.
    NumberAnimation {
        id: scrollAnim
        target: list
        property: "contentY"
        duration: root.theme ? root.theme.dur(Motion.FADE.LAUNCHER_HIGHLIGHT) : 0
        easing.type: Easing.OutCubic
    }
}
