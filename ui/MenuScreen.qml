pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "Motion.js" as Motion

// Tela "Omarchy": o menu inteiro do Omarchy dentro da ilha, guiado pelos
// mesmos dados do plugin omarchy.menu (MenuSvc + OmarchyMenu.js). Um nível
// por vez. Tamanho fixo theme.screenSize("menu") = 514 x 460, cap 30.
//
// Duas camadas (motion F), como o Lançador:
// - Cabeçalho (headerItems): lupa e campo de busca, x preso às bordas vivas
//   da forma (edgeLeft / edgeRight), tamanho fixo. A busca procura nos
//   descendentes do nível aberto (na raiz, o menu inteiro), como o Omarchy:
//   primeiro os filhos diretos, depois o resto, cada linha com o caminho do
//   pai embaixo; linhas apagadas ficam fora.
// - Corpo (bodyItems): divisória em y 60; a faixa do caminho (y 61..97):
//   na raiz o glifo "menu", fora dela o botão Voltar; depois
//   "Omarchy › Acionar › Captura", os níveis de cima clicáveis (sobe até
//   ali); a lista em y 99 até 14 do fundo, linhas de 46 (7 e meia à vista:
//   a linha cortada diz que há mais), rolagem e um indicador fino.
//
// Linha (486 x 46): ladrilho 30 (raio 8, tinta 6,5%) em +8 com o glifo Nerd
// Font do JSONC (16, na fonte do host Commons.Style.fontFamily, ou na
// iconFont da entrada) ou o ícone do app; rótulo 14/500 em +50; na busca, o
// caminho 11/400 embaixo. À direita: ✓ (check, accentInk) quando `checked`
// deu certo, quando a linha é `disabled` ou é o valor atual de um provider;
// › (chevron) quando abre um submenu. `when` falso some; `disabled` fica a
// 40% e fora da seleção (cursor, ponteiro e Enter passam por cima).
//
// Seleção como no Lançador: um destaque só (tinta 12%, barra accent), que
// desliza 180 ms OutCubic; a lista rola junto; o hover só move o destaque
// com o ponteiro andando. Ao subir um nível, a seleção volta para a linha de
// onde se veio.
//
// Teclas (o campo repassa no Keys.onPressed dele): ↑/↓ e Tab/Shift+Tab (dão a
// volta), PgUp/PgDn ±6, Enter entra ou executa. Com a busca vazia: → entra ou
// executa, ← e Backspace sobem, Home/End vão à primeira e à última; com
// texto, essas ficam com o campo. ←/→ seguem a leitura (RTL troca). Esc
// limpa a busca e depois fecha (handleEscape false). handleBack (cápsula de
// navegação, Alt+←): limpa a busca, senão sobe um nível; na raiz, false.
// Mouse: clique entra ou executa; a roda rola.
//
// Ação: fecha a ilha (closeRequested) e roda o comando como o Omarchy
// (MenuSvc.runAction; ILHA_DEV=1 só registra). Linha de app (busca): abre
// pelo island.apps. Aplicativos (provider apps): a tela de Apps da Ilha, o
// porte do mesmo AppLibrary. Submenu com provider que a Ilha não conhece:
// fecha e abre o menu do próprio Omarchy naquele ponto.
//
// payload.menu (opcional): abre direto naquele id ou alias (resolveRoute);
// uma rota que é ação roda, como `omarchy menu summon <alias>`.
// Nada roda antes de opened() nem depois de closed() (MenuSvc.activate /
// deactivate).
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

    readonly property var dims: root.theme && root.island ? root.theme.screenSize("menu", root.island.screenGeometry(root.island.screenOutput)) : ({ w: 514, h: 460, k: 0 })
    implicitWidth: root.dims.w
    implicitHeight: root.dims.h

    // ---- Medidas ----
    readonly property real pitch: 46
    readonly property real inset: 14
    readonly property real listW: root.implicitWidth - 2 * root.inset
    readonly property real crumbTop: 61
    readonly property real crumbH: 36
    readonly property real listTop: 99
    readonly property real listH: Math.max(root.pitch, root.implicitHeight - root.listTop - root.inset)
    // Coluna dos rótulos (x no painel): o caminho começa nela.
    readonly property real labelX: root.inset + 50
    readonly property int pageRows: 6

    readonly property bool rtl: !!root.theme && root.theme.rtl
    readonly property var apps: root.island ? root.island.apps : null
    readonly property string query: field.text.trim()
    // Fonte dos glifos Nerd Font do JSONC (a do host) e os textos de vazio do
    // próprio menu do Omarchy (catálogo do host, já traduzido).
    readonly property string hostFont: Commons.Style.fontFamily
    readonly property string emptyText: root.query !== "" ? Commons.I18n.t("common.noMatchesFor").arg(root.query) : Commons.I18n.t("menu.nothingHere")

    // Teclas que o campo repassa: com texto, ←/→, Backspace e Home/End editam.
    readonly property var keysIdle: [Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_Home, Qt.Key_End,
        Qt.Key_Return, Qt.Key_Enter, Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Escape, Qt.Key_Left, Qt.Key_Right, Qt.Key_Backspace]
    readonly property var keysTyping: [Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown,
        Qt.Key_Return, Qt.Key_Enter, Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Escape]

    MenuSvc {
        id: svc
        omarchyPath: root.island ? String(root.island.omarchyPath || "") : ""
        apps: root.apps
        shell: root.island ? root.island.shell : null
        rootLabel: root.strings ? root.strings.t("picker.menu", "Omarchy") : "Omarchy"
        onUpdated: root.refresh(false)
    }

    // ---- Contrato: abrir / fechar / teclas ----

    function opened(payload) {
        root.snapping = true;
        priv.open = true;
        priv.navStack = [];
        priv.level = "root";
        priv.lastPoint = Qt.point(-1, -1);
        root.quietClear();
        svc.activate();
        Qt.callLater(() => root.snapping = false);
        if (root.openRoute(payload && payload.menu ? String(payload.menu) : ""))
            return;
        root.refresh(true);
        field.focusField();
    }

    // payload.menu: um id ou alias (como `omarchy menu summon <rota>`). Uma
    // rota que é ação roda; true quando a tela não fica (fechou ou trocou).
    // Fechar e trocar vão no próximo turno: dentro do opened() a pilha ainda
    // não marcou a tela como apresentada e ignoraria o pedido.
    function openRoute(route) {
        if (route === "" || !svc.loaded)
            return false;
        let target = svc.resolveRoute(route);
        let e = svc.item(target);
        if (e && e.kind === "link" && svc.item(e.target)) {
            target = e.target;
            e = svc.item(target);
        }
        if (!e)
            return false;
        if (e.provider === "apps" && e.kind === "action") {
            Qt.callLater(() => root.navigate("launcher", ({})));
            return true;
        }
        if (e.kind === "action" && e.action !== "") {
            Qt.callLater(() => root.closeRequested());
            svc.runAction(e.action);
            return true;
        }
        if (e.provider !== "" && !svc.knowsProvider(e.provider)) {
            Qt.callLater(() => root.closeRequested());
            svc.summonHostMenu(target);
            return true;
        }
        priv.level = target;
        svc.enterMenu(target);
        return false;
    }

    function closed() {
        priv.open = false;
        scrollAnim.stop();
        priv.lastPoint = Qt.point(-1, -1);
        svc.deactivate();
    }

    // Teclas que chegam à tela (foco fora do campo, ou `ilha run menu <tecla>`).
    function handleKey(event) {
        if (root.navKey(event))
            return true;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods !== 0)
            return false;
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

    // Voltar (cápsula, Alt+←): limpa a busca, senão sobe um nível; na raiz, false.
    function handleBack() {
        if (field.text !== "") {
            field.clear();
            return true;
        }
        return root.goBack();
    }

    // ---- Teclado ----

    // As teclas de lista (do campo ou da tela). true = tratada.
    function navKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        const typing = field.text !== "";
        // ←/→ pela leitura: em RTL a seta física troca de papel.
        const k = Commons.Util.readingKey(event);
        switch (k) {
        case Qt.Key_Up:
            root.move(-1, true);
            return true;
        case Qt.Key_Down:
            root.move(1, true);
            return true;
        case Qt.Key_Tab:
            if (mods !== 0)
                return false;
            root.move((event.modifiers & Qt.ShiftModifier) ? -1 : 1, true);
            return true;
        case Qt.Key_Backtab:
            if (mods !== 0)
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
            if (typing || mods !== 0)
                return false;
            root.select(root.firstSelectable(0, 1), false, true);
            return true;
        case Qt.Key_End:
            if (typing || mods !== 0)
                return false;
            root.select(root.firstSelectable(priv.rows.length - 1, -1), false, true);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate(priv.selected);
            return true;
        case Qt.Key_Right:
            if (typing || mods !== 0)
                return false;
            root.activate(priv.selected);
            return true;
        case Qt.Key_Left:
            if (typing || mods !== 0)
                return false;
            // Segurar a seta não despenca até a raiz.
            if (!event.isAutoRepeat)
                root.goBack();
            return true;
        case Qt.Key_Backspace:
            if ((event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) !== 0)
                return false;
            if (typing) {
                root.erase();
                return true;
            }
            if (!event.isAutoRepeat)
                root.goBack();
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

    // ---- Navegação entre níveis ----

    // Entra num submenu (ou segue um atalho). push: guarda o nível de agora.
    function enter(id, push) {
        let target = String(id || "root");
        let e = svc.item(target);
        if (e && e.kind === "link" && svc.item(e.target)) {
            target = e.target;
            e = svc.item(target);
        }
        if (!e) {
            target = "root";
            e = svc.item(target);
        }
        // Um provider que a Ilha não conhece: o menu do próprio Omarchy ali.
        if (e && e.provider !== "" && !svc.knowsProvider(e.provider)) {
            root.closeRequested();
            svc.summonHostMenu(target);
            return;
        }
        if (push && target !== priv.level)
            priv.navStack = priv.navStack.concat([priv.level]);
        priv.level = target;
        root.quietClear();
        svc.enterMenu(target);
        root.refresh(true);
    }

    // Sobe um nível (pela história, senão pelo pai). false na raiz.
    function goBack() {
        if (priv.level === "root")
            return false;
        const from = priv.level;
        let prev = "";
        if (priv.navStack.length > 0) {
            prev = priv.navStack[priv.navStack.length - 1];
            priv.navStack = priv.navStack.slice(0, priv.navStack.length - 1);
        } else {
            const e = svc.item(from);
            prev = e && e.parent ? e.parent : "root";
        }
        priv.level = svc.item(prev) ? prev : "root";
        root.quietClear();
        svc.enterMenu(priv.level);
        root.refresh(true);
        root.selectRowLeadingTo(from);
        return true;
    }

    // Clique num nível de cima do caminho.
    function jumpTo(id) {
        if (id === priv.level)
            return;
        const chain = svc.crumbs(priv.level).map(c => c.id);
        const at = chain.indexOf(id);
        const below = at >= 0 && at + 1 < chain.length ? chain[at + 1] : "";
        priv.navStack = [];
        priv.level = svc.item(id) ? id : "root";
        root.quietClear();
        svc.enterMenu(priv.level);
        root.refresh(true);
        if (below !== "")
            root.selectRowLeadingTo(below);
    }

    function selectRowLeadingTo(id) {
        for (let i = 0; i < priv.rows.length; i++) {
            const r = priv.rows[i];
            if ((r.itemId === id || r.target === id) && !r.disabled) {
                root.select(i, false, true);
                return;
            }
        }
    }

    function activate(i) {
        const r = priv.rows[i];
        if (!r || r.disabled)
            return;
        if (r.kind === "menu" || r.kind === "link") {
            root.enter(r.target !== "" ? r.target : r.itemId, true);
            return;
        }
        if (r.kind === "app") {
            if (root.apps && root.apps.launch(r.appId, r.label))
                root.closeRequested();
            return;
        }
        // Aplicativos: a tela de Apps da Ilha (o porte do AppLibrary do Omarchy).
        if (r.provider === "apps") {
            root.navigate("launcher", ({}));
            return;
        }
        if (r.action === "")
            return;
        const command = r.action;
        root.closeRequested();
        svc.runAction(command);
    }

    // ---- Linhas ----

    // Refaz as linhas do nível (ou da busca). reset: seleção na primeira e
    // lista no topo; senão a seleção segue a mesma linha e a rolagem fica.
    function refresh(reset) {
        if (!priv.open)
            return;
        const next = root.query !== "" ? svc.searchRows(priv.level, root.query) : svc.levelRows(priv.level);
        const sig = JSON.stringify(next);
        const keepId = reset ? "" : priv.selectedId;
        if (sig !== priv.sig) {
            const y = list.contentY;
            priv.sig = sig;
            priv.rows = next;
            if (!reset) {
                list.forceLayout();
                const maxY = Math.max(list.originY, list.originY + list.contentHeight - list.height);
                list.contentY = Math.max(list.originY, Math.min(maxY, y));
            }
        }
        let i = -1;
        if (keepId !== "") {
            for (let j = 0; j < priv.rows.length; j++) {
                if (priv.rows[j].itemId === keepId) {
                    i = j;
                    break;
                }
            }
        }
        if (reset) {
            scrollAnim.stop();
            list.positionViewAtBeginning();
            root.select(root.firstSelectable(0, 1), false, false);
        } else {
            root.select(root.firstSelectable(i >= 0 ? i : priv.selected, 1), false, false);
        }
        root.updateCrumbs();
    }

    function selectable(i) {
        return i >= 0 && i < priv.rows.length && !priv.rows[i].disabled;
    }

    // A primeira selecionável a partir de i, no sentido dir (sem dar a volta;
    // se não houver nesse sentido, tenta o outro). -1 se nenhuma.
    function firstSelectable(i, dir) {
        const n = priv.rows.length;
        if (n === 0)
            return -1;
        const from = Math.max(0, Math.min(n - 1, i));
        for (let k = from; k >= 0 && k < n; k += dir) {
            if (root.selectable(k))
                return k;
        }
        for (let k = from; k >= 0 && k < n; k -= dir) {
            if (root.selectable(k))
                return k;
        }
        return -1;
    }

    // Escolhe a linha i. animate: o destaque desliza; scroll: a lista rola até ela.
    function select(i, animate, scroll) {
        if (i < 0 || i >= priv.rows.length) {
            priv.selected = -1;
            priv.selectedId = "";
            return;
        }
        priv.jump = !animate;
        priv.selected = i;
        priv.selectedId = priv.rows[i].itemId;
        priv.jump = false;
        if (scroll)
            root.ensureVisible(i, animate);
    }

    // Passo de teclado, pulando as apagadas. wrap: dá a volta nas pontas (num salto).
    function move(delta, wrap) {
        const n = priv.rows.length;
        if (n === 0)
            return;
        const dir = delta < 0 ? -1 : 1;
        const at = priv.selected < 0 ? (dir > 0 ? -1 : n) : priv.selected;
        let k = at + delta;
        if (k < 0 || k >= n) {
            if (wrap) {
                k = ((k % n) + n) % n;
                for (let tries = 0; tries < n && !root.selectable(k); tries++)
                    k = ((k + dir) % n + n) % n;
                if (root.selectable(k))
                    root.select(k, false, true);
                return;
            }
            k = Math.max(0, Math.min(n - 1, k));
        }
        const target = root.firstSelectable(k, dir);
        if (target >= 0)
            root.select(target, true, true);
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
        if (priv.rows.length === 0 || priv.selected < 0)
            return;
        const top = list.originY + priv.selected * root.pitch;
        if (top >= list.contentY - 1 && top + root.pitch <= list.contentY + list.height + 1)
            return;
        const first = Math.ceil((list.contentY - list.originY - 1) / root.pitch);
        root.select(root.firstSelectable(first, 1), false, false);
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
        if (i >= 0 && i !== priv.selected && root.selectable(i))
            root.select(i, true, false);
    }

    // ---- Caminho ----

    // Os níveis com a largura de cada um; se não cabem, os de cima encolhem
    // (com reticências) e o atual fica com até 45% da faixa.
    function updateCrumbs() {
        const list0 = svc.crumbs(priv.level);
        const sepW = sepMetrics.advanceWidth + 2 * crumbRow.spacing;
        const avail = Math.max(60, crumbRow.width);
        const out = [];
        let total = 0;
        for (let i = 0; i < list0.length; i++) {
            const last = i === list0.length - 1;
            crumbMetrics.weight = last ? 600 : 500;
            crumbMetrics.text = list0[i].label;
            const w = Math.ceil(crumbMetrics.advanceWidth) + 1;
            out.push({ id: list0[i].id, label: list0[i].label, natural: w, cap: w, last: last });
            total += w + (i > 0 ? sepW : 0);
        }
        if (total > avail && out.length > 1) {
            const lastCap = Math.min(out[out.length - 1].natural, avail * 0.45);
            out[out.length - 1].cap = lastCap;
            const share = Math.max(24, (avail - lastCap - (out.length - 1) * sepW) / (out.length - 1));
            for (let j = 0; j < out.length - 1; j++)
                out[j].cap = Math.min(out[j].natural, share);
        } else if (total > avail) {
            out[0].cap = avail;
        }
        if (JSON.stringify(out) !== JSON.stringify(priv.crumbs))
            priv.crumbs = out;
    }

    // ---- Campo ----

    // Limpa sem contar como digitação (não refaz as linhas duas vezes).
    function quietClear() {
        priv.quiet = true;
        field.clear();
        priv.quiet = false;
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

    QtObject {
        id: priv
        property bool open: false
        property string level: "root"
        property var navStack: []
        property var rows: []
        property string sig: ""
        property var crumbs: []
        property int selected: 0
        property string selectedId: ""
        // Próxima troca de seleção sem deslizar.
        property bool jump: false
        // Limpeza programática do campo (não é digitação).
        property bool quiet: false
        property point lastPoint: Qt.point(-1, -1)
    }

    IlhaMetrics {
        id: crumbMetrics
        theme: root.theme
        size: 13
        weight: 500
    }
    IlhaMetrics {
        id: sepMetrics
        theme: root.theme
        size: 13
        weight: 500
        text: "›"
    }

    // ---- Cabeçalho (x preso às bordas vivas; tamanho fixo) ----
    Item {
        id: header
        width: root.implicitWidth
        height: 60

        Icon {
            id: glass
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
            width: root.implicitWidth - 56
            theme: root.theme
            fontSize: 14
            placeholder: root.strings ? root.strings.t("launcher.search") : ""
            forwarded: field.text === "" ? root.keysIdle : root.keysTyping
            onNavKey: event => root.fieldKey(event)
            onTextEdited: {
                if (!priv.quiet && root.island && root.current)
                    root.island.keyboardMode = true;
            }
            onTextChanged: {
                if (!priv.quiet)
                    root.refresh(true);
            }
        }
    }

    // ---- Corpo (layout final) ----
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

        // ---- Caminho: Voltar (ou o glifo do menu na raiz) e os níveis ----
        Item {
            id: crumbBar
            x: 0
            y: root.crumbTop
            width: root.implicitWidth
            height: root.crumbH

            // Centro na coluna dos ladrilhos (x 37).
            CircleButton {
                id: backButton
                anchors.left: parent.left
                anchors.leftMargin: root.inset + 8 + 1
                anchors.verticalCenter: parent.verticalCenter
                visible: priv.level !== "root"
                theme: root.theme
                icon: "chevron_left"
                flip: root.rtl
                size: 28
                glyphSize: 18
                fill: "transparent"
                hoverFill: root.theme ? root.theme.rowHover : "transparent"
                glyphColor: root.theme ? root.theme.inkMuted : "gray"
                hoverGlyphColor: root.theme ? root.theme.ink : "white"
                accessibleName: root.strings ? root.strings.t("common.back") : ""
                onClicked: root.goBack()
            }

            Icon {
                anchors.centerIn: backButton
                visible: priv.level === "root"
                name: "menu"
                size: 18
                color: root.theme ? root.theme.inkFaint : "gray"
            }

            Row {
                id: crumbRow
                anchors.left: parent.left
                anchors.leftMargin: root.labelX
                anchors.right: parent.right
                anchors.rightMargin: root.inset
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Repeater {
                    model: priv.crumbs

                    Row {
                        id: crumb
                        required property var modelData
                        required property int index
                        spacing: crumbRow.spacing

                        IlhaText {
                            visible: crumb.index > 0
                            theme: root.theme
                            size: 13
                            weight: 500
                            color: root.theme ? root.theme.inkFaint : "gray"
                            text: root.rtl ? "‹" : "›"
                        }

                        IlhaText {
                            id: crumbText
                            width: crumb.modelData.cap
                            theme: root.theme
                            size: 13
                            weight: crumb.modelData.last ? 600 : 500
                            color: !root.theme ? "white"
                                : crumb.modelData.last ? root.theme.ink
                                : crumbHover.hovered ? root.theme.ink : root.theme.inkMuted
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: crumb.modelData.label

                            Accessible.role: crumb.modelData.last ? Accessible.StaticText : Accessible.Button
                            Accessible.name: crumb.modelData.label

                            HoverHandler {
                                id: crumbHover
                                enabled: !crumb.modelData.last
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                enabled: !crumb.modelData.last
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: root.jumpTo(crumb.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ---- Lista ----
        Item {
            id: listArea
            x: root.inset
            y: root.listTop
            width: root.listW
            height: root.listH

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: priv.rows
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: false
                highlightRangeMode: ListView.NoHighlightRange
                currentIndex: -1
                pressDelay: 0
                Accessible.role: Accessible.List
                Accessible.name: root.strings ? root.strings.t("picker.menu", "Omarchy") : ""

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
                    opacity: priv.rows.length > 0 && priv.selected >= 0 ? 1 : 0

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
                        height: root.pitch - 1
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

                    readonly property bool isApp: row.modelData.kind === "app"
                    readonly property bool opens: row.modelData.kind === "menu" || row.modelData.kind === "link"
                    readonly property string glyph: String(row.modelData.icon || "")
                    readonly property string detail: String(row.modelData.detail || "")

                    z: 1
                    width: list.width
                    height: root.pitch

                    Accessible.role: Accessible.ListItem
                    Accessible.name: String(row.modelData.label || "")
                    Accessible.description: row.detail
                    Accessible.selected: row.index === priv.selected
                    Accessible.checked: row.modelData.checked === true

                    // Antes das linhas de mais fundo na busca: um fio.
                    Rectangle {
                        visible: row.modelData.drill === true
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        y: 0
                        height: 1
                        color: root.theme ? root.theme.alpha(root.theme.ink, 0.08) : "transparent"
                    }

                    Item {
                        anchors.fill: parent
                        // Apagada: o que já está instalado, não para escolher.
                        opacity: row.modelData.disabled ? 0.4 : 1

                        // Ladrilho do glifo.
                        Rectangle {
                            id: tile
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 8
                            visible: row.glyph !== "" || row.isApp
                            color: root.theme ? root.theme.alpha(root.theme.ink, 0.065) : "transparent"

                            // Glifo Nerd Font do JSONC, na fonte do host (ou na iconFont da entrada).
                            IlhaText {
                                anchors.fill: parent
                                visible: !row.isApp
                                theme: root.theme
                                size: 16
                                weight: 400
                                font.family: row.modelData.iconFont !== "" ? row.modelData.iconFont : root.hostFont
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: root.theme ? root.theme.alpha(root.theme.ink, 0.9) : "white"
                                text: row.glyph
                            }

                            Image {
                                id: appImage
                                anchors.centerIn: parent
                                visible: row.isApp
                                width: 20
                                height: 20
                                sourceSize: Qt.size(40, 40)
                                source: row.isApp && root.apps ? root.apps.iconSource(row.modelData.appIcon) : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                mipmap: true
                            }
                        }

                        // Rótulo: centrado; com o caminho (busca), linha de base em +20.
                        IlhaText {
                            id: labelText
                            anchors.left: parent.left
                            anchors.leftMargin: 50
                            width: list.width - 50 - trail.width - 16
                            y: (row.detail !== "" ? 20 : 28) - labelText.baselineOffset
                            theme: root.theme
                            size: 14
                            weight: 500
                            color: root.theme ? root.theme.alpha(root.theme.ink, 0.92) : "white"
                            // Explícito: o LayoutMirroring vira para a direita em RTL; implícito,
                            // o Qt alinha pela escrita do texto e nomes latinos ficam longe do ícone.
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: String(row.modelData.label || "")
                        }

                        // O caminho do pai (só na busca): linha de base em +35.
                        IlhaText {
                            anchors.left: parent.left
                            anchors.leftMargin: 50
                            width: labelText.width
                            y: 35 - baselineOffset
                            visible: row.detail !== ""
                            theme: root.theme
                            size: 11
                            weight: 400
                            color: root.theme ? root.theme.inkMuted : "gray"
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            // O separador aponta no sentido da leitura.
                            text: root.rtl ? row.detail.replace(/ › /g, " ‹ ") : row.detail
                        }

                        // À direita: ✓ e/ou ›.
                        Row {
                            id: trail
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Icon {
                                visible: row.modelData.checked === true
                                name: "check"
                                size: 16
                                color: root.theme ? root.theme.accentInk : "white"
                            }
                            Icon {
                                visible: row.opens
                                name: root.rtl ? "chevron_left" : "chevron_right"
                                size: 16
                                color: root.theme ? root.theme.inkMuted : "gray"
                            }
                        }
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: {
                            if (!root.selectable(row.index))
                                return;
                            root.select(row.index, false, false);
                            root.activate(row.index);
                        }
                    }
                }
            }

            // Hover: só o movimento real do ponteiro escolhe a linha.
            HoverHandler {
                id: listHover
                cursorShape: priv.rows.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPointChanged: {
                    if (listHover.hovered)
                        root.pointerMoved(listHover.point.position);
                }
                onHoveredChanged: {
                    if (!listHover.hovered)
                        priv.lastPoint = Qt.point(-1, -1);
                }
            }

            // Indicador de rolagem: 2 px na folga da borda final (dentro do recorte
            // seguro, CLIP_INSET · raio), só com mais linhas do que cabem.
            Rectangle {
                readonly property real span: Math.max(1, list.contentHeight)
                readonly property bool overflow: list.contentHeight > list.height + 1
                anchors.right: parent.right
                anchors.rightMargin: -4
                y: overflow ? Math.max(0, Math.min(list.height - height, (list.contentY - list.originY) / span * list.height)) : 0
                width: 2
                height: overflow ? Math.max(24, list.height * list.height / span) : 0
                radius: 1
                visible: overflow
                color: root.theme ? root.theme.alpha(root.theme.ink, 0.18) : "transparent"
            }
        }

        // Nível vazio ou busca sem resultado (os textos do próprio menu do Omarchy).
        IlhaText {
            x: root.inset
            y: root.listTop + (root.listH - height) / 2
            width: root.listW
            horizontalAlignment: Text.AlignHCenter
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            elide: Text.ElideRight
            opacity: priv.open && svc.loaded && priv.rows.length === 0 && !svc.providerPending(priv.level) ? 1 : 0
            text: root.emptyText
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
