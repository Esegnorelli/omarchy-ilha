pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons

// Os widgets da barra do Omarchy, dentro da pílula. A Ilha lê o bar.layout
// do shell.json (Ilha.hostedEntries: as seções na ordem da barra padrão,
// menos o que a própria Ilha desenha, que são o menu, os workspaces e o
// relógio) e monta cada widget com o componente que o host entrega a uma barra
// (barWidgetRegistry.widgets[id].component), como Bar.qml faz no WidgetHost:
// injeta bar (BarFacade), moduleName, settings e fixedEdge.
//
// Assim cada painel do Omarchy (clima, Elsewhen, Tailscale, Dropbox, agentes,
// Superwhisper, bandeja, layout de teclado, indicadores, áudio com o mixer,
// Bluetooth, rede, tela, bateria e energia) abre do próprio widget, logo
// abaixo da pílula, igual à barra padrão, e acompanha o Omarchy quando ele
// muda. Os widgets ficam vivos o tempo todo (os painéis e os alvos de IPC
// deles também); só aparecem e recebem clique no L2.
//
// Um popout por janela: requestPopout fecha o anterior (Bar.requestPopout).
// Um painel aberto segura o L2 (popoutOpen).
Item {
    id: root

    property var island: null
    property string output: ""
    property bool shown: false
    // Borda de baixo da cápsula (barSizeFor dos widgets).
    property real popupFloor: 64
    property bool rtl: false
    property color glyph: Commons.Color.bar.text
    property color accent: Commons.Color.bar.text
    property color divider: Qt.rgba(1, 1, 1, 0.12)
    // Filete entre seções do bar.layout: 6 + 1 + 6.
    readonly property real divW: 13

    readonly property bool dry: Quickshell.env("ILHA_DEV") === "1"
    readonly property var registry: root.island ? root.island.barWidgetRegistry : null
    readonly property var entries: root.island ? root.island.hostedEntries : []
    readonly property var layoutConfig: root.island && root.island.barConfig && root.island.barConfig.layout ? root.island.barConfig.layout : ({})

    property var activePopout: null
    readonly property bool popoutOpen: root.activePopout !== null

    implicitWidth: row.implicitWidth
    implicitHeight: Commons.Style.bar.sizeHorizontal

    // Quem faz o fade é o HoverBar. O clique só vale no L2 (ou com um painel aberto).
    enabled: root.shown || root.popoutOpen

    // moduleName dos slots vivos, na ordem. O laço lê s.live, então a binding acompanha.
    readonly property var liveIds: {
        const out = [];
        for (let i = 0; i < rep.count; i++) {
            const s = rep.itemAt(i);
            if (s && s.live)
                out.push(s.moduleName);
        }
        return out;
    }
    // Seção do slot vivo mais próximo antes de i, ou "".
    function prevLiveSection(i) {
        for (let j = i - 1; j >= 0; j--) {
            const s = rep.itemAt(j);
            if (s && s.live)
                return s.section;
        }
        return "";
    }
    readonly property bool pointerOver: rowHover.hovered
    // Painel de módulo não fica órfão quando o L2 sai.
    onShownChanged: {
        if (root.shown || !root.activePopout)
            return;
        const p = root.activePopout;
        root.activePopout = null;
        if (typeof p.close === "function")
            p.close();
    }

    // Ponteiro parado num módulo segura o L2, mesmo que o botão do módulo
    // tire o hover da zona.
    HoverHandler { id: rowHover }

    function requestPopout(owner) {
        if (root.activePopout === owner)
            return;
        const prev = root.activePopout;
        if (prev) {
            if (typeof prev.closeForPopoutSwitch === "function")
                prev.closeForPopoutSwitch();
            else if (typeof prev.close === "function")
                prev.close();
        }
        root.activePopout = owner;
    }
    function releasePopout(owner) {
        if (root.activePopout === owner)
            root.activePopout = null;
    }

    // Itens vivos desta janela, na ordem do layout.
    function slots() {
        const out = [];
        for (let i = 0; i < rep.count; i++) {
            const s = rep.itemAt(i);
            if (s && s.item)
                out.push(s);
        }
        return out;
    }
    // Diagnóstico (ilha state): o que cada slot carregou.
    function debugSlots() {
        const out = [];
        for (let i = 0; i < rep.count; i++) {
            const s = rep.itemAt(i);
            if (!s) {
                out.push({ i: i, slot: false });
                continue;
            }
            out.push({ id: s.moduleName, comp: !!s.component, status: s.loaderStatus, item: !!s.item,
                       visible: !!s.item && s.item.visible === true, w: s.item ? Math.round(s.item.implicitWidth) : -1,
                       panel: root.isPanel(s.item) });
        }
        return { count: rep.count, implicitWidth: Math.round(root.implicitWidth), shown: root.shown, slots: out };
    }

    function ownerModule(owner) {
        const list = root.slots();
        for (let i = 0; i < list.length; i++) {
            if (list[i].item === owner)
                return list[i].moduleName;
        }
        return "";
    }
    // Todos os vivos de um id (os outros monitores também), como Bar.moduleWidgets.
    function moduleWidgets(id) {
        return root.island && typeof root.island.hostedWidgets === "function" ? root.island.hostedWidgets(id) : root.localWidgets(id);
    }
    function localWidgets(id) {
        return root.slots().filter(s => s.moduleName === id).map(s => s.item);
    }
    // Um item com painel (open, close, opened), como Bar.findPanelWidget.
    function isPanel(item) {
        return !!item && typeof item.open === "function" && typeof item.close === "function" && item.opened !== undefined;
    }
    function panelFor(id) {
        const list = root.slots();
        for (let i = 0; i < list.length; i++) {
            if (list[i].moduleName === id && root.isPanel(list[i].item))
                return list[i].item;
        }
        return null;
    }
    // Os painéis de uma seção, na ordem, só os que aparecem (Super+Ctrl+1..9).
    function panelIds(section) {
        const list = root.slots();
        const out = [];
        for (let i = 0; i < list.length; i++) {
            const s = list[i];
            if (s.section === section && s.moduleName !== "omarchy.tray" && root.isPanel(s.item) && s.item.visible)
                out.push(s.moduleName);
        }
        return out;
    }
    function switchPanelFrom(owner, direction) {
        const list = root.slots().filter(s => root.isPanel(s.item) && s.item.visible);
        let at = -1;
        for (let i = 0; i < list.length; i++) {
            if (list[i].item === owner)
                at = i;
        }
        if (at < 0 || list.length < 2)
            return false;
        const next = list[(at + (direction < 0 ? -1 : 1) + list.length) % list.length];
        next.item.open();
        return true;
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            id: rep
            model: root.entries

            Item {
                id: slot
                required property var modelData
                required property int index
                readonly property string moduleName: String(slot.modelData.id || "")
                readonly property string section: String(slot.modelData.section || "")
                // Os indicadores aparecem todos (os inativos esmaecidos, cada um um
                // botão de ligar). Na barra padrão eles se revelam no hover e crescem
                // para o lado de fora; na cápsula centrada esse crescimento empurra
                // tudo meia largura, o ícone foge do ponteiro e o clique não acerta.
                readonly property var settings: slot.moduleName === "omarchy.indicators"
                    ? Object.assign({}, slot.modelData.settings || ({}), { alwaysShow: true })
                    : (slot.modelData.settings || ({}))
                readonly property var component: {
                    const reg = root.registry;
                    const w = reg && reg.widgets ? reg.widgets[slot.moduleName] : null;
                    return w && w.component ? w.component : null;
                }
                readonly property var item: loader.item
                readonly property int loaderStatus: loader.status
                // Sempre visível: o item herda a visibilidade do slot, então ler
                // item.visible aqui só vale se o slot já está à vista. Um widget
                // que se esconde sozinho (atualização, layout de teclado) zera a largura.
                readonly property bool live: !!slot.item && slot.item.visible === true
                readonly property bool leads: {
                    if (!slot.live)
                        return false;
                    const prev = root.prevLiveSection(slot.index);
                    return prev !== "" && prev !== slot.section;
                }
                readonly property real lead: slot.leads ? root.divW : 0
                width: slot.live ? slot.lead + slot.item.implicitWidth + 4 : 0
                height: root.implicitHeight

                // A fachada de shell sem serviços que o host dá a uma barra de
                // terceiros. Pedida uma vez, fora de binding: o host guarda a
                // fachada nova no próprio estado ao criar (binding loop).
                property var entryShell: null
                Component.onCompleted: Qt.callLater(() => {
                    const sh = root.island ? root.island.shell : null;
                    if (sh && typeof sh.pluginShellForBarEntry === "function")
                        slot.entryShell = sh.pluginShellForBarEntry(slot.moduleName, slot.moduleName);
                })

                BarFacade {
                    id: facade
                    host: root
                    pluginId: slot.moduleName
                    moduleName: slot.moduleName
                    entryShell: slot.entryShell
                    barShell: root.island ? root.island.shell : null
                    popupFloor: root.popupFloor
                    glyph: root.glyph
                }

                Loader {
                    id: loader
                    x: root.rtl ? 2 : slot.lead + 2
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: slot.component
                    onLoaded: {
                        slot.inject();
                        Qt.callLater(slot.inject);
                    }
                }

                // Filete de seção. O x do slot não espelha; o Row sim.
                Rectangle {
                    visible: slot.leads
                    x: root.rtl ? slot.width - root.divW / 2 - 0.5 : root.divW / 2 - 0.5
                    y: (slot.height - 14) / 2
                    width: 1
                    height: 14
                    color: root.divider
                }
                // Indicador de painel aberto, como o openPanelIndicator da barra padrão.
                Rectangle {
                    readonly property real iw: slot.item ? slot.item.implicitWidth : 0
                    visible: slot.live && (root.isPanel(slot.item) ? slot.item.opened === true : root.activePopout === slot.item)
                    width: Math.max(10, Math.round(iw * 0.55))
                    height: 2
                    radius: 1
                    x: loader.x + (iw - width) / 2
                    y: slot.height - 3
                    color: root.accent
                }

                function inject() {
                    const target = slot.item;
                    if (!target)
                        return;
                    if ("fixedEdge" in target)
                        target.fixedEdge = "center";
                    if ("bar" in target)
                        target.bar = facade;
                    if ("moduleName" in target)
                        target.moduleName = slot.moduleName;
                    if ("settings" in target)
                        target.settings = slot.settings;
                }
                onSettingsChanged: slot.inject()
            }
        }
    }

    Component.onCompleted: if (root.island && typeof root.island.registerWidgetHost === "function") root.island.registerWidgetHost(root)
    Component.onDestruction: if (root.island && typeof root.island.unregisterWidgetHost === "function") root.island.unregisterWidgetHost(root)
}
