import QtQuick
import qs.Commons as Commons

// O `bar` que a Ilha entrega a um widget do Omarchy hospedado na pílula
// (OmarchyWidgets). Espelha a API que a barra padrão dá aos widgets
// (shell/Ui/PluginBarApi.qml e o que Bar.qml liga nela): cores, fonte,
// posição, tamanho, coordenação de popout, dicas e `run`.
//
// - barSize é o tamanho de widget da barra padrão (Style.bar.sizeHorizontal),
//   para os widgets se desenharem como na barra.
// - barSizeFor(tela) é a borda de baixo da cápsula: os painéis centrados na
//   barra (centerOnBar) abrem logo abaixo da pílula. Os outros já abrem
//   abaixo do próprio widget (PopupCard.anchor).
// - O popout ativo é um só por janela: OmarchyWidgets guarda e fecha o
//   anterior, como Bar.requestPopout.
QtObject {
    id: api

    // ---- Ligados pelo OmarchyWidgets ----
    property var host: null
    property string pluginId: ""
    property string moduleName: ""
    // A fachada sem serviços do widget (pluginShellForBarEntry) e a da Ilha,
    // que é a barra e pode pedir os serviços do Omarchy (firstPartyServiceFor:
    // os indicadores leem dele o Não perturbe, o manter acordado e afins).
    property var entryShell: null
    property var barShell: null
    property real popupFloor: 64
    // Glifos na pílula (sempre escura). Em tema claro Color.bar.text é escuro.
    property color glyph: Commons.Color.bar.text

    readonly property QtObject shell: QtObject {
        function firstPartyServiceFor(id) {
            const b = api.barShell;
            return b && typeof b.firstPartyServiceFor === "function" ? b.firstPartyServiceFor(id) : null;
        }
        function serviceFor(id) {
            const e = api.entryShell;
            return e && typeof e.serviceFor === "function" ? e.serviceFor(id) : null;
        }
        function summon(id, payloadJson) {
            const e = api.entryShell || api.barShell;
            return e && typeof e.summon === "function" ? e.summon(id, payloadJson) : false;
        }
        function hide(id) {
            const e = api.entryShell || api.barShell;
            return e && typeof e.hide === "function" ? e.hide(id) : false;
        }
        function toggle(id, payloadJson) {
            const e = api.entryShell || api.barShell;
            return e && typeof e.toggle === "function" ? e.toggle(id, payloadJson) : false;
        }
        function isPluginOpen(id) {
            const e = api.entryShell || api.barShell;
            return e && typeof e.isPluginOpen === "function" ? e.isPluginOpen(id) : false;
        }
        function updateEntryInline(id, settings) {
            const e = api.entryShell;
            return e && typeof e.updateEntryInline === "function" ? e.updateEntryInline(id, settings) : false;
        }
        function mutateShellConfig(mutator) {
            const e = api.entryShell;
            return e && typeof e.mutateShellConfig === "function" ? e.mutateShellConfig(mutator) : false;
        }
    }

    // ---- Estado de apresentação (como Bar.qml) ----
    readonly property color foreground: Commons.Color.bar.text
    readonly property color barForeground: api.glyph
    readonly property color background: Commons.Color.bar.background
    readonly property color urgent: Commons.Color.bar.active
    readonly property string fontFamily: Commons.Style.font.family
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: Commons.Style.bar.sizeHorizontal
    readonly property bool transparent: false
    readonly property bool foregroundAnimationEnabled: true
    readonly property bool centerSectionRevealHeld: false
    readonly property bool traySectionDragActive: false
    readonly property bool traySectionPopoutOpen: !!api.host && !!api.host.activePopout && api.host.ownerModule(api.host.activePopout) === "omarchy.tray"
    property bool centerHoverRevealSuppressed: false
    readonly property var activePopout: api.host ? api.host.activePopout : null
    property var clickTargets: []
    readonly property var layoutConfig: api.host ? api.host.layoutConfig : ({})
    readonly property var foreignPopoutMarker: ({ foreign: true })

    function setCenterHoverRevealSuppressed(value) {
        api.centerHoverRevealSuppressed = !!value;
    }
    function showTooltip(target, text) {
    }
    function hideTooltip(target) {
    }
    function registerClickTarget(target) {
        if (target && api.clickTargets.indexOf(target) === -1)
            api.clickTargets = api.clickTargets.concat([target]);
    }
    function unregisterClickTarget(target) {
        api.clickTargets = api.clickTargets.filter(t => t !== target);
    }
    function requestPopout(owner) {
        if (api.host)
            api.host.requestPopout(owner);
    }
    function releasePopout(owner) {
        if (api.host)
            api.host.releasePopout(owner);
    }
    function notePopoutCard(card) {
    }
    function popoutCardFor(owner) {
        return null;
    }
    function switchPanelFrom(owner, direction) {
        return api.host ? api.host.switchPanelFrom(owner, direction) : false;
    }
    function targetBelongsToWindow(target, window) {
        return !!target && !!window && !!target.QsWindow && target.QsWindow.window === window;
    }
    function moduleWidgets(id) {
        return api.host ? api.host.moduleWidgets(String(id || "")) : [];
    }
    function barSizeFor(screenName) {
        return api.popupFloor;
    }
    function run(command) {
        const c = String(command || "");
        if (c === "")
            return;
        if (api.host && api.host.dry) {
            console.log("ilha (dev): bar.run " + c);
            return;
        }
        Commons.Util.execDetached(c);
    }
}
