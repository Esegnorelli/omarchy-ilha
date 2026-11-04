pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.Commons as Commons
import "Motion.js" as Motion

// Conteúdo do L2, a marca do repouso e o seletor de telas.
// Camada do tamanho da janela, sem layout próprio e sem nada que
// aceite hover: fica dentro do recorte do conteúdo da IslandWindow, em
// coordenadas da janela, recebe o ponteiro (`pointer`) e responde hitTest.
// O relógio NÃO é daqui (um só por janela, da IslandWindow); daqui saem
// l2ClockDx e as larguras que alimentam geometryFor.
//
// L2 (faixa de 52, topo 10, e a fileira dos módulos do Omarchy
// embaixo quando há módulos): uma linha só em morph.bandY. O contexto
// fica em morph.left + 34. À direita ficam o glifo do estado em
// morph.right − 37, o texto 11 antes e, 11 antes do texto, a rede e a
// bateria próprias (só sem omarchy.network/omarchy.power na fileira). No
// centro ficam o relógio (1,375, da janela) e a data 11 px depois. Em RTL
// todo x espelha com x' = 2·cx − x − largura.
//
// A linha do L2 some fora dele; a marca só no repouso; a data sai ao
// deixar o L2. O mergulho do topo é da IslandWindow. Cada troca de face
// recomeça os fades a partir da opacidade atual (regra 7).
//
// hitTest(x, y) (coordenadas da janela) ->
//   "context" | "center" | "status"                                  (L2)
//   "mark" | "mark:media"                                            (repouso)
//   "pick:<screenId>" | "pick:" | "clock" | "ws:<id>"                (seletor)
//   "widget"                                                         (L2)
//   ""                                                               (vazio)
// activate(hit) executa: ws -> foco; mark:media -> Mídia; mark -> dono
// (§4.5); pick:<id> -> island.open(id); pick: e clock -> L2; widget -> o
// próprio módulo; context -> Mídia (player) ou Apps; center -> Central;
// status -> ação da linha (fixada por statusPin); "" no L2 -> collapse().
Item {
    id: root

    // ---- Entradas ----
    property var island: null
    property Theme theme: null
    property var strings: null
    property var morph: null
    property string output: ""
    // Face da janela (rest, hover2, picker, peek, osd, screen).
    property string face: "rest"
    property var motion: "hover"
    // Ponteiro em coordenadas da janela (destaques de módulo); (-1, -1) fora.
    property point pointer: Qt.point(-1, -1)
    // L2 fixado numa linha de estado (amendments §5.1).
    property string statusPin: ""
    property var status: root.island ? root.island.status : null
    property var media: root.island ? root.island.media : null
    // A IslandWindow liga a partir de markHold (destaque da marca).
    property bool markHovered: false
    // Bordas do relógio no repouso (ALVO, já com restDx), em coordenadas da janela.
    property real clockLeft: 0
    property real clockRight: 0
    // Botão apertado na zona (opcional): o slot do seletor mostra o 16%.
    property bool pressed: false

    // ---- Saídas ----
    readonly property bool rtl: root.theme ? root.theme.rtl : false
    readonly property real cx: root.morph ? root.morph.centerX : root.width / 2
    // Data do L2 e o deslocamento do relógio no L2.
    readonly property real dateW: Math.ceil(dateMetrics.advanceWidth)
    readonly property real l2ClockDx: -(root.theme ? root.theme.dir : 1) * (root.dateW + root.dims.dateGap) / 2
    // Módulo do L2 sob o ponteiro: "" | "context" | "center" | "status".
    readonly property string hoverModule: {
        if (root.face !== "hover2" || !priv.movedInL2 || root.pointer.x < 0)
            return "";
        const h = root.hitTest(root.pointer.x, root.pointer.y);
        return h === "context" || h === "center" || h === "status" ? h : "";
    }
    // O que está sob o ponteiro agora (hitTest) e se merece a mãozinha.
    readonly property string hoverHit: root.pointer.x >= 0 ? root.hitTest(root.pointer.x, root.pointer.y) : ""
    readonly property bool wantsHand: root.hoverHit !== "" && root.hoverHit !== "pick:"
    // Marca do repouso: largura (geometryFor ctx.markW) e coluna (janela).
    readonly property real restMarkW: mark.markW
    // Largura do seletor (workspaces + relógio + ícones).
    readonly property real pickerW: picker.implicitWidth
    // Seletor: deslocamento do relógio até a vaga dele.
    readonly property real pickerClockDx: picker.clockDx
    // Fileira dos módulos do Omarchy no L2 (largura viva; 0 sem módulos).
    readonly property real modsW: mods.implicitWidth
    readonly property bool modsPointerOver: mods.pointerOver
    // Um painel de módulo do Omarchy aberto: o L2 fica.
    readonly property bool widgetsPopoutOpen: mods.popoutOpen
    readonly property rect markRect: {
        if (root.face !== "rest" || mark.markW <= 0)
            return Qt.rect(0, 0, 0, 0);
        const w = root.geomRest.w;
        const pad = root.px("ZONE_REST_PAD", 8), zh = root.px("ZONE_REST_H", 46);
        const zoneLeft = root.cx - w / 2 - pad, zoneRight = root.cx + w / 2 + pad;
        if (root.rtl)
            return Qt.rect(mark.markLeft - 4, 0, zoneRight - (mark.markLeft - 4), zh);
        return Qt.rect(zoneLeft, 0, mark.markLeft + mark.markW + 4 - zoneLeft, zh);
    }
    readonly property string pickerHoverId: picker.hoverId
    readonly property var screenPicker: picker
    readonly property var restMark: mark

    signal openScreen(string id, var payload)
    signal collapse()
    signal expand()

    // ---- Medidas do layout (px lógicos) ----
    readonly property var dims: ({
        // Rede e bateria próprias
        netW: 19.25, netH: 16,
        battBodyW: 33, battBodyH: 16.5, battR: 5.5, battNubGap: 1.4, battNubW: 2.75, battNubH: 8.25,
        // L2 (uma linha em morph.bandY)
        ctxIconX: 34, ctxLabelX: 58, ctxIcon: 14,
        labelMax: 200, statusGlyph: 15, statusInset: 37, statusGap: 11, netBattGap2: 10, dateGap: 11,
        // Destaques do L2
        hlH: 25, hlR: 10, hlCenterPad: 14, hlCenterH: 36, hlCenterR: 12, hlPad: 10
    })
    readonly property real battFullW: root.dims.battBodyW + root.dims.battNubGap + root.dims.battNubW

    function px(name, fallback) {
        return root.theme && root.theme.px[name] !== undefined ? root.theme.px[name] : fallback;
    }

    // Espelho de um centro calculado em LTR.
    function mir(c) {
        return root.rtl ? 2 * root.cx - c : c;
    }
    // Espelho de um x (borda esquerda) calculado em LTR.
    function mirX(x, w) {
        return root.rtl ? 2 * root.cx - x - w : x;
    }

    // %1, %2… sem avisos quando um catálogo não tem o marcador.
    function fmt(pattern, args) {
        return String(pattern || "").replace(/%(\d)/g, (m, n) => args[Number(n) - 1] !== undefined ? String(args[Number(n) - 1]) : m);
    }
    function tr(key) {
        return root.strings ? root.strings.t(key) : key;
    }

    // ---- Estado vindo dos serviços ----
    readonly property var net: root.island ? root.island.net : null
    readonly property bool netWired: !!root.net && root.net.wired
    readonly property bool netWifi: !!root.net && !root.netWired && root.net.connected
    readonly property int netBars: root.netWifi ? Math.max(0, Math.min(4, root.net.bars)) : 0

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!root.battery && root.battery.isLaptopBattery && root.battery.isPresent
    readonly property real batteryLevel: root.hasBattery ? Math.max(0, Math.min(1, root.battery.percentage)) : 0
    // A rede e a bateria próprias somem quando o módulo do Omarchy já está na fileira.
    readonly property bool hostNet: mods.liveIds.indexOf("omarchy.network") !== -1
    readonly property bool hostPower: mods.liveIds.indexOf("omarchy.power") !== -1
    readonly property bool nativeBatt: root.hasBattery && !root.hostPower
    readonly property bool batteryCharging: root.hasBattery && !UPower.onBattery
    readonly property bool batteryLow: root.hasBattery && UPower.onBattery && root.batteryLevel <= 0.15

    readonly property string netAccessible: root.netWired ? root.tr("bar.ethernet")
        : root.netWifi ? root.fmt(root.tr("bar.wifiSignal"), [Commons.I18n.formatNumber(Math.round(Number(root.net.signal) || 0))])
        : root.tr("bar.offline")
    readonly property string battAccessible: root.fmt(root.tr(root.batteryCharging ? "bar.batteryCharging" : "bar.battery"),
        [Commons.I18n.formatNumber(Math.round(root.batteryLevel * 100))])


    // ---- Geometria-alvo das faces (nunca animada) ----
    readonly property real clockW: Math.max(0, root.clockRight - root.clockLeft)
    readonly property real screenW: root.cx * 2
    readonly property var geomRest: root.theme ? root.theme.geometryFor("rest", { clockW: root.clockW, markW: mark.markW, screenW: root.screenW }) : ({ w: 84, h: 32, top: 10, cap: 16 })
    readonly property var geomL2: root.theme ? root.theme.geometryFor("hover2", { screenW: root.screenW, modsW: root.modsW, bandW: root.l2FitW }) : ({ w: 718, h: 52, top: 10, cap: 26 })
    readonly property real l2Left: root.cx - root.geomL2.w / 2
    readonly property real l2Right: root.cx + root.geomL2.w / 2



    // ---- Linha de estado do L2 (fixada por statusPin) ----
    readonly property var line: {
        const s = root.status;
        if (!s)
            return { key: "", text: "", icon: "notifications", filled: false, tone: "calm", action: "" };
        return root.statusPin !== "" && s.isOn(root.statusPin) ? s.statusFor(root.statusPin) : s.statusLine;
    }
    readonly property bool lineClickable: !!root.line && String(root.line.action || "") !== ""
    readonly property real statusW: Math.ceil(statusMetrics.advanceWidth)
    readonly property real statusShownW: Math.min(root.statusW, root.dims.labelMax)

    // ---- Linha de contexto do L2 ----
    // Janela focada neste monitor (no workspace que ele mostra, ou num especial).
    readonly property var focusedTop: {
        const mon = workspaces.monitor;
        const active = mon ? mon.activeWorkspace : null;
        const t = Hyprland.activeToplevel;
        if (t && t.monitor && String(t.monitor.name) === root.output) {
            const ws = t.workspace;
            if (ws && (ws.id < 0 || !active || ws.id === active.id))
                return t;
        }
        const list = active && active.toplevels ? active.toplevels.values : [];
        return list.length > 0 ? list[0] : null;
    }
    readonly property string appClass: {
        const t = root.focusedTop;
        if (!t)
            return "";
        if (t.wayland && t.wayland.appId)
            return String(t.wayland.appId);
        const o = t.lastIpcObject;
        return o && o["class"] ? String(o["class"]) : "";
    }
    readonly property var appEntry: root.appClass !== "" ? DesktopEntries.heuristicLookup(root.appClass) : null
    readonly property string appName: {
        if (root.appEntry && root.appEntry.name)
            return String(root.appEntry.name);
        const cls = root.appClass;
        const title = root.focusedTop ? String(root.focusedTop.title || "").trim() : "";
        // Web apps têm classe gerada ("chrome-site__-Default"): o título diz mais.
        if (cls === "" || /^(chrome|chromium|brave|msedge|vivaldi)-/.test(cls))
            return title;
        const name = cls.split(".").pop().replace(/[-_]+/g, " ").trim();
        return name === "" ? title : name.charAt(0).toUpperCase() + name.slice(1);
    }
    readonly property string appIconPath: root.appEntry && root.appEntry.icon ? Quickshell.iconPath(String(root.appEntry.icon), true) : ""
    function normId(s) {
        return String(s || "").toLowerCase().replace(/\.desktop$/, "").trim();
    }
    // A janela focada é o app do player atual?
    readonly property bool playerApp: {
        if (!root.media || !root.media.hasTrack || root.appClass === "")
            return false;
        const cls = root.normId(root.appClass);
        const eid = root.appEntry ? root.normId(root.appEntry.id) : "";
        const ids = [root.normId(root.media.playerDesktopId), root.normId(root.media.playerName)];
        for (let i = 0; i < ids.length; i++) {
            const id = ids[i];
            if (id === "")
                continue;
            if (id === cls || id === eid || cls.endsWith("." + id) || id.endsWith("." + cls))
                return true;
        }
        return false;
    }
    readonly property bool ctxDesktop: !root.focusedTop
    readonly property bool ctxPlayer: !root.ctxDesktop && root.playerApp
    // Separador do padrão "%1 · %2" (título · artista).
    readonly property string trackSep: {
        const m = /^%1(.*)%2$/.exec(root.tr("bar.trackArtist"));
        return m ? m[1] : " · ";
    }
    readonly property string ctxTitleText: root.ctxDesktop ? root.tr("bar.desktop") : (root.ctxPlayer ? String(root.media.title) : root.appName)
    readonly property string ctxRestText: root.ctxPlayer && String(root.media.artist || "") !== "" ? root.trackSep + String(root.media.artist) : ""
    readonly property real ctxTitleW: Math.ceil(ctxTitleMetrics.advanceWidth)
    readonly property real ctxRestW: root.ctxRestText === "" ? 0 : Math.ceil(ctxRestMetrics.advanceWidth)
    readonly property real ctxTitleShownW: root.ctxTitleW + root.ctxRestW <= root.dims.labelMax ? root.ctxTitleW
        : (root.ctxRestW <= 0 ? root.dims.labelMax : Math.min(root.ctxTitleW, Math.max(root.dims.labelMax - root.ctxRestW, 120)))
    readonly property real ctxRestShownW: Math.max(0, Math.min(root.ctxRestW, root.dims.labelMax - root.ctxTitleShownW))
    readonly property real ctxLabelW: root.ctxTitleShownW + root.ctxRestShownW

    // ---- Data do L2 ----
    readonly property string dateText: {
        const d = root.island && root.island.now instanceof Date ? root.island.now : new Date();
        const loc = Qt.locale(Commons.I18n.formatLocale);
        return root.fmt(root.tr("bar.datePattern"), [
            loc.dayName(d.getDay(), Locale.ShortFormat),
            loc.monthName(d.getMonth(), Locale.ShortFormat),
            Commons.I18n.formatNumber(d.getDate())
        ]);
    }
    // Grupo do centro (relógio a 1,375 + 11 + data) e onde a data começa (LTR).
    readonly property real centerGroupW: root.clockW * root.px("L2_CLOCK_SCALE", 1.375) + root.dims.dateGap + root.dateW
    readonly property real dateLeftLTR: root.cx - root.centerGroupW / 2 + root.clockW * root.px("L2_CLOCK_SCALE", 1.375) + root.dims.dateGap
    // Rede e bateria próprias: só sem o módulo do Omarchy na fileira.
    readonly property bool netOn: !root.hostNet
    readonly property bool battOn: root.nativeBatt
    readonly property real l2LeftExtent: root.dims.ctxLabelX + root.ctxLabelW
    readonly property real l2IndW: (root.netOn ? root.dims.netW : 0)
        + (root.battOn ? root.battFullW : 0)
        + (root.netOn && root.battOn ? root.dims.netBattGap2 : 0)
        + (root.netOn || root.battOn ? root.dims.statusGap : 0)
    // O texto do estado entra sempre na conta (o "Tudo em dia" escondido não encolhe a pílula).
    readonly property real l2RightExtent: root.dims.statusInset + root.dims.statusGlyph + root.dims.statusGap + root.statusShownW + root.l2IndW
    // Os lados grudam nas bordas e o centro fica no meio: a soma deixa o lado
    // maior em cima do relógio. A largura usa o maior dos dois, duas vezes.
    readonly property real l2FitW: {
        const gap = 18;
        const side = Math.max(root.l2LeftExtent, root.l2RightExtent);
        const band = 2 * side + root.centerGroupW + 2 * gap;
        const mods = root.modsW > 0 ? root.modsW + 2 * root.px("L2_MOD_PAD", 24) : 0;
        return Math.ceil(Math.max(band, mods));
    }
    // À direita, em LTR: [rede][10][bateria][11][texto][11][glifo][37] até a borda viva.
    readonly property real statusEdgeR: (root.morph ? root.morph.right : 0) - root.dims.statusInset - root.dims.statusGlyph - root.dims.statusGap
    readonly property real indRight: root.statusEdgeR - root.statusShownW - root.dims.statusGap
    readonly property real l2BattC: root.indRight - root.battFullW / 2
    readonly property real l2NetC: (root.battOn ? root.indRight - root.battFullW - root.dims.netBattGap2 : root.indRight) - root.dims.netW / 2

    // ---- hitTest / activate ----
    function hitTest(x, y) {
        switch (root.face) {
        case "rest": {
            const r = root.markRect;
            if (r.width > 0 && x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height) {
                // A coluna inteira conta como a marca (§4.4).
                const mx = Math.max(mark.markLeft, Math.min(mark.markLeft + mark.markW, x));
                return mark.hitTest(mx, Math.max(0, Math.min(y, r.height))) || "mark";
            }
            return mark.hitTest(x, y);
        }
        case "picker":
            return picker.hitTest(x, y);
        case "hover2":
            return root.hitL2(x, y);
        default:
            return "";
        }
    }


    function hitL2(x, y) {
        const lx = root.rtl ? 2 * root.cx - x : x;
        const top = root.px("TOP", 10);
        const cy = top + root.px("L2_H", 52) / 2;
        const L = root.l2Left, R = root.l2Right;
        if (Math.abs(lx - root.cx) <= root.centerGroupW / 2 + root.dims.hlCenterPad && Math.abs(y - cy) <= root.dims.hlCenterH / 2)
            return "center";
        if (Math.abs(y - cy) <= root.dims.hlH / 2) {
            if (lx >= L + root.dims.ctxIconX - root.dims.hlPad && lx <= L + root.dims.ctxLabelX + root.ctxLabelW + root.dims.hlPad)
                return "context";
            const glyphRight = R - root.dims.statusInset;
            const textLeft = glyphRight - root.dims.statusGlyph - root.dims.statusGap - root.statusShownW;
            if (root.lineClickable && lx >= textLeft - root.dims.hlPad && lx <= glyphRight + root.dims.hlPad)
                return "status";
        }
        // Fileira dos módulos: o próprio widget trata o clique.
        const bandBottom = top + root.px("L2_H", 52);
        if (root.modsW > 0 && y > bandBottom && Math.abs(lx - root.cx) <= root.modsW / 2 + 4)
            return "widget";
        return "";
    }

    function activate(hit) {
        const h = String(hit || "");
        if (!root.island)
            return false;
        if (h.indexOf("pick:") === 0) {
            const id = h.slice(5);
            if (id === "") {
                // Vão do L1: sobe um nível.
                return root.island.setExpanded(root.output, true);
            }
            root.island.keyboardMode = false;
            return root.island.open(id, root.output);
        }
        if (h === "clock")
            return root.island.setExpanded(root.output, true);
        if (h === "mark:media")
            return root.island.open("media", root.output);
        if (h === "mark") {
            const key = mark.markKey;
            const owner = root.status && key !== "" ? root.status.ownerFor(key) : "";
            if (owner === "l2")
                return root.island.setExpanded(root.output, true, key);
            if (owner === "control")
                return root.island.open("control", root.output);
            if (owner === "control:display")
                return root.island.open("control", root.output, { sub: "display", focus: "stayAwake" });
            return false;
        }
        if (h === "context")
            return root.island.open(root.ctxPlayer ? "media" : "launcher", root.output);
        if (h === "center")
            return root.island.open("control", root.output);
        if (h === "status") {
            const action = String(root.line && root.line.action ? root.line.action : "");
            if (action === "")
                return false;
            if (action.indexOf("open:") === 0)
                return root.island.open(action.slice(5), root.output);
            return root.status.runAction(action);
        }
        if (h.indexOf("ws:") === 0) {
            workspaces.focus(Number(h.slice(3)));
            return true;
        }
        if (h === "") {
            if (root.face === "hover2")
                root.collapse();
            return true;
        }
        return false;
    }

    // ---- Choreografia ----
    QtObject {
        id: priv
        property string lastFace: "rest"
        // O ponteiro andou desde que o L2 abriu (o destaque só aparece então).
        property bool movedInL2: false
    }

    onPointerChanged: if (root.face === "hover2") priv.movedInL2 = true

    // Um fade: espera `delay`, depois vai a `to` em `dur` (OutCubic), sempre
    // a partir da opacidade atual. Reduzir movimento: pula direto.
    function fade(f, to, delay, dur) {
        f.stop();
        const item = f.item;
        if (!item)
            return;
        const reduce = !root.theme || root.theme.reduceMotion;
        if (reduce || (delay <= 0 && dur <= 0) || Math.abs(item.opacity - to) < 0.001) {
            item.opacity = to;
            return;
        }
        f.wait = Math.max(0, delay);
        f.to = to;
        f.span = Math.max(1, dur);
        f.start();
    }


    function choreo(from, to) {
        const F = Motion.FADE;
        // A linha do L2 some na hora fora do L2.
        if (to !== "hover2") {
            root.fade(iconsF, 0, 0, 0);
            root.fade(labelsF, 0, 0, 0);
            root.fade(modsF, 0, 0, 0);
            priv.movedInL2 = false;
        }
        // Marca: só no repouso; entra conforme de onde vem.
        if (to === "rest") {
            const m = from === "hover2" ? F.MARK_IN_FROM_L2 : F.MARK_IN_AFTER;
            root.fade(markF, 1, m.delay, m.dur);
        } else {
            root.fade(markF, 0, 0, F.MARK_OUT);
        }
        switch (to) {
        case "hover2":
            root.fade(iconsF, 1, F.L2_ICONS_IN.delay, F.L2_ICONS_IN.dur);
            root.fade(labelsF, 1, F.L2_LABELS_IN.delay, F.L2_LABELS_IN.dur);
            root.fade(dateF, 1, F.L2_DATE_IN.delay, F.L2_DATE_IN.dur);
            root.fade(modsF, 1, F.L2_MODS_IN.delay, F.L2_MODS_IN.dur);
            break;
        case "rest":
            root.fade(dateF, 0, from === "hover2" ? F.L2_DATE_OUT.delay : 0, from === "hover2" ? F.L2_DATE_OUT.dur : F.CONTENT_OUT.dur);
            break;
        default:
            // Tela, OSD, aviso e seletor: o conteúdo do L2 sai em 60 ms.
            root.fade(dateF, 0, 0, F.CONTENT_OUT.dur);
            break;
        }
    }

    // Estado parado de uma face (início, sem animação).
    function snapFace(f) {
        const l2 = f === "hover2";
        const pairs = [[markF, f === "rest" ? 1 : 0],
                       [iconsF, l2 ? 1 : 0], [labelsF, l2 ? 1 : 0], [dateF, l2 ? 1 : 0], [modsF, l2 ? 1 : 0]];
        for (let i = 0; i < pairs.length; i++) {
            pairs[i][0].stop();
            pairs[i][0].item.opacity = pairs[i][1];
        }
    }

    onFaceChanged: {
        const from = priv.lastFace;
        priv.lastFace = root.face;
        root.choreo(from, root.face);
    }

    Component.onCompleted: {
        priv.lastFace = root.face;
        root.snapFace(root.face);
    }

    // ---- Componentes ----

    // Fade com espera: SequentialAnimation { PauseAnimation; NumberAnimation sem `from` }.
    component Fader: SequentialAnimation {
        id: fader
        property Item item: null
        property alias wait: faderPause.duration
        property alias to: faderNum.to
        property alias span: faderNum.duration
        PauseAnimation {
            id: faderPause
            duration: 0
        }
        NumberAnimation {
            id: faderNum
            target: fader.item
            property: "opacity"
            easing.type: Easing.OutCubic
        }
    }

    // Rede no tamanho do L2 (19,25 x 16): 4 barras do Wi-Fi, ou o glifo do
    // cabo / sem rede. Sempre LTR.
    component NetIndicator: Item {
        id: ni
        property Theme theme: null
        property bool wifi: false
        property bool wired: false
        property int bars: 0
        readonly property real barW: 3.78
        readonly property real barGap: (ni.width - 4 * ni.barW) / 3
        width: 19.25
        height: 16
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Repeater {
            model: [5.5, 8.9, 12.4, 15.8]
            Rectangle {
                required property var modelData
                required property int index
                x: index * (ni.barW + ni.barGap)
                y: ni.height - height
                width: ni.barW
                height: modelData
                radius: 1
                color: !ni.theme ? "white" : (index < ni.bars ? ni.theme.accentInk : ni.theme.alpha(ni.theme.ink, 0.30))
                opacity: ni.wifi ? 1 : 0
            }
        }

        Icon {
            anchors.centerIn: parent
            size: 20.6
            name: ni.wired ? "lan" : "wifi_off"
            color: ni.theme ? ni.theme.alpha(ni.theme.ink, ni.wired ? 0.80 : 0.45) : "white"
            opacity: ni.wifi ? 0 : 1
        }
    }

    // Bateria no tamanho do L2: corpo 33 x 16,5 (raio 5,5) com o nível em
    // corte reto, pino 2,75 x 8,25 a 1,4 px. Carregando: raio no meio.
    component BatteryIndicator: Item {
        id: bi
        property Theme theme: null
        property real level: 0
        property bool charging: false
        property bool low: false
        width: 33 + 1.4 + 2.75
        height: 16.5
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Rectangle {
            width: 33
            height: bi.height
            radius: 5.5
            color: bi.theme ? bi.theme.mix(bi.theme.surface, bi.theme.accent, 0.20) : "gray"
        }
        Item {
            width: Math.round(33 * bi.level)
            height: bi.height
            clip: true
            Rectangle {
                width: 33
                height: bi.height
                radius: 5.5
                color: !bi.theme ? "white" : (bi.low ? bi.theme.danger : bi.theme.accent)
            }
        }
        Rectangle {
            x: 33 + 1.4
            y: (bi.height - height) / 2
            width: 2.75
            height: 8.25
            radius: 1.2
            color: bi.theme ? bi.theme.mix(bi.theme.surface, bi.theme.accent, 0.25) : "gray"
        }
        Icon {
            x: (33 - width) / 2
            y: (bi.height - height) / 2
            size: 13.75
            name: "bolt"
            filled: true
            color: bi.theme ? bi.theme.onAccent : "black"
            opacity: bi.charging ? 1 : 0
        }
    }


    Fader { id: iconsF; item: iconsLayer }
    Fader { id: labelsF; item: labelsLayer }
    Fader { id: dateF; item: dateLayer }
    Fader { id: modsF; item: modsLayer }
    Fader { id: markF; item: mark }

    Workspaces {
        id: workspaces
        output: root.output
    }


    IlhaMetrics {
        id: dateMetrics
        theme: root.theme
        size: 14
        weight: 500
        text: root.dateText
    }
    IlhaMetrics {
        id: statusMetrics
        theme: root.theme
        size: 13
        weight: 500
        tnum: true
        text: root.line ? String(root.line.text || "") : ""
    }
    IlhaMetrics {
        id: ctxTitleMetrics
        theme: root.theme
        size: 13
        weight: 500
        text: root.ctxTitleText
    }
    IlhaMetrics {
        id: ctxRestMetrics
        theme: root.theme
        size: 13
        weight: 500
        text: root.ctxRestText
    }


    // ---- Destaques dos módulos do L2 (tinta a 10%; entra 120 ms linear, sai 70 ms) ----
    Rectangle {
        id: ctxHighlight
        readonly property bool lit: root.hoverModule === "context"
        readonly property real l: root.morph ? root.morph.left + root.dims.ctxIconX - root.dims.hlPad : 0
        readonly property real w: root.dims.ctxLabelX - root.dims.ctxIconX + root.ctxLabelW + 2 * root.dims.hlPad
        x: root.mirX(ctxHighlight.l, ctxHighlight.w)
        y: (root.morph ? root.morph.bandY : 36) - height / 2
        width: ctxHighlight.w
        height: root.dims.hlH
        radius: root.dims.hlR
        color: root.theme ? root.theme.hoverOverlay : "transparent"
        opacity: ctxHighlight.lit ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: root.theme ? root.theme.dur(ctxHighlight.lit ? Motion.FADE.L2_HIGHLIGHT_IN : Motion.FADE.L2_HIGHLIGHT_OUT) : 0
                easing.type: ctxHighlight.lit ? Easing.Linear : Easing.OutCubic
            }
        }
    }
    Rectangle {
        id: centerHighlight
        readonly property bool lit: root.hoverModule === "center"
        x: root.cx - width / 2
        y: (root.morph ? root.morph.bandY : 36) - height / 2
        width: root.centerGroupW + 2 * root.dims.hlCenterPad
        height: root.dims.hlCenterH
        radius: root.dims.hlCenterR
        color: root.theme ? root.theme.hoverOverlay : "transparent"
        opacity: centerHighlight.lit ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: root.theme ? root.theme.dur(centerHighlight.lit ? Motion.FADE.L2_HIGHLIGHT_IN : Motion.FADE.L2_HIGHLIGHT_OUT) : 0
                easing.type: centerHighlight.lit ? Easing.Linear : Easing.OutCubic
            }
        }
    }
    Rectangle {
        id: statusHighlight
        readonly property bool lit: root.hoverModule === "status"
        readonly property real r: root.morph ? root.morph.right - root.dims.statusInset + root.dims.hlPad : 0
        readonly property real w: root.dims.statusGlyph + root.dims.statusGap + root.statusShownW + 2 * root.dims.hlPad
        x: root.mirX(statusHighlight.r - statusHighlight.w, statusHighlight.w)
        y: (root.morph ? root.morph.bandY : 36) - height / 2
        width: statusHighlight.w
        height: root.dims.hlH
        radius: root.dims.hlR
        color: root.theme ? root.theme.hoverOverlay : "transparent"
        opacity: statusHighlight.lit ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: root.theme ? root.theme.dur(statusHighlight.lit ? Motion.FADE.L2_HIGHLIGHT_IN : Motion.FADE.L2_HIGHLIGHT_OUT) : 0
                easing.type: statusHighlight.lit ? Easing.Linear : Easing.OutCubic
            }
        }
    }


    // ---- L2, a linha: ícones (presos às bordas vivas) ----
    Item {
        id: iconsLayer
        anchors.fill: parent
        opacity: 0
        readonly property real rowY: root.morph ? root.morph.bandY : 36

        // Contexto: capa (player), ícone do app (dessaturado) ou o ponto da área de trabalho.
        Item {
            id: ctxIcon
            x: root.mirX((root.morph ? root.morph.left : 0) + root.dims.ctxIconX, root.dims.ctxIcon)
            y: iconsLayer.rowY - root.dims.ctxIcon / 2
            width: root.dims.ctxIcon
            height: root.dims.ctxIcon

            ClippingRectangle {
                anchors.fill: parent
                radius: 3
                color: "transparent"
                opacity: root.ctxPlayer && art.status === Image.Ready ? 1 : 0
                Image {
                    id: art
                    anchors.fill: parent
                    source: root.ctxPlayer && root.media ? String(root.media.artUrl || "") : ""
                    sourceSize.width: 28
                    sourceSize.height: 28
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                }
            }
            Icon {
                anchors.fill: parent
                size: root.dims.ctxIcon
                name: "music_note"
                color: root.theme ? root.theme.accentInk : "white"
                opacity: root.ctxPlayer && art.status !== Image.Ready ? 1 : 0
            }
            Image {
                id: appImage
                anchors.fill: parent
                source: !root.ctxPlayer && !root.ctxDesktop ? root.appIconPath : ""
                sourceSize.width: 28
                sourceSize.height: 28
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                opacity: appImage.status === Image.Ready ? 0.85 : 0
                layer.enabled: appImage.status === Image.Ready && iconsLayer.opacity > 0
                layer.effect: MultiEffect {
                    saturation: -0.7
                }
            }
            Icon {
                anchors.fill: parent
                size: root.dims.ctxIcon
                name: "desktop_windows"
                color: root.theme ? root.theme.inkMuted : "white"
                opacity: !root.ctxPlayer && !root.ctxDesktop && appImage.status !== Image.Ready ? 1 : 0
            }
            Rectangle {
                anchors.centerIn: parent
                width: 5
                height: 5
                radius: 2.5
                color: root.theme ? root.theme.alpha(root.theme.accent, 0.45) : "white"
                opacity: root.ctxDesktop ? 1 : 0
            }
        }

        // Estado: glifo de 15 com a borda direita em morph.right − 37.
        Icon {
            id: statusGlyph
            x: root.mirX((root.morph ? root.morph.right : 0) - root.dims.statusInset - root.dims.statusGlyph, root.dims.statusGlyph)
            y: iconsLayer.rowY - root.dims.statusGlyph / 2
            size: root.dims.statusGlyph
            readonly property string host: root.island && root.island.glyphs && root.line ? root.island.glyphs.statusGlyph(root.line.key) : ""
            name: host === "" ? (root.line ? String(root.line.icon || "") : "") : ""
            glyph: host
            filled: !!root.line && !!root.line.filled
            color: root.theme && root.line ? root.theme.toneColor(root.line.tone) : "white"
        }
        NetIndicator {
            id: netItem
            theme: root.theme
            wifi: root.netWifi
            wired: root.netWired
            bars: root.netBars
            x: root.mir(root.l2NetC) - width / 2
            y: iconsLayer.rowY - height / 2
            opacity: root.netOn ? 1 : 0
            Accessible.role: Accessible.StaticText
            Accessible.name: root.netAccessible
        }
        BatteryIndicator {
            id: battItem
            theme: root.theme
            level: root.batteryLevel
            charging: root.batteryCharging
            low: root.batteryLow
            x: root.mir(root.l2BattC) - width / 2
            y: iconsLayer.rowY - height / 2
            opacity: root.battOn ? 1 : 0
            Accessible.role: Accessible.StaticText
            Accessible.name: root.battAccessible
        }
    }

    // ---- L2, a linha: rótulos (relativos aos ícones) ----
    Item {
        id: labelsLayer
        anchors.fill: parent
        opacity: 0
        readonly property real rowY: root.morph ? root.morph.bandY : 36
        readonly property real ctxX: (root.morph ? root.morph.left : 0) + root.dims.ctxLabelX

        IlhaText {
            id: ctxTitle
            x: root.mirX(labelsLayer.ctxX, width)
            y: labelsLayer.rowY - height / 2
            width: root.ctxTitleShownW
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.alpha(root.theme.ink, 0.95) : "white"
            elide: root.ctxTitleShownW < root.ctxTitleW ? Text.ElideRight : Text.ElideNone
            maximumLineCount: 1
            text: root.ctxTitleText
            Accessible.role: Accessible.Button
            Accessible.name: root.ctxTitleText + root.ctxRestText
        }
        IlhaText {
            x: root.mirX(labelsLayer.ctxX + root.ctxTitleShownW, width)
            y: labelsLayer.rowY - height / 2
            width: root.ctxRestShownW
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.inkMuted : "white"
            elide: root.ctxRestShownW < root.ctxRestW ? Text.ElideRight : Text.ElideNone
            maximumLineCount: 1
            text: root.ctxRestText
            opacity: root.ctxRestText !== "" ? 1 : 0
            Accessible.ignored: true
        }

        IlhaText {
            id: statusText
            readonly property real edgeR: root.statusEdgeR
            // "Tudo em dia" (chave vazia) é secundário: aparece com o ponteiro no grupo do estado. O glifo fica.
            readonly property bool quiet: !root.line || String(root.line.key || "") === ""
            opacity: !statusText.quiet || root.hoverModule === "status" ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: root.theme ? root.theme.dur((!statusText.quiet || root.hoverModule === "status") ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                    easing.type: Easing.OutCubic
                }
            }
            x: root.mirX(statusText.edgeR - width, width)
            y: labelsLayer.rowY - height / 2
            width: root.statusShownW
            theme: root.theme
            size: 13
            weight: 500
            tnum: true
            horizontalAlignment: Text.AlignRight
            elide: root.statusShownW < root.statusW ? Text.ElideRight : Text.ElideNone
            maximumLineCount: 1
            text: root.line ? String(root.line.text || "") : ""
            Accessible.role: root.lineClickable ? Accessible.Button : Accessible.StaticText
            Accessible.name: statusText.text
        }
    }

    // ---- L2, centro: a data (o relógio é da janela) ----
    Item {
        id: dateLayer
        anchors.fill: parent
        opacity: 0

        IlhaText {
            // Entra e sai deslizando 5 px para fora: x = final + dir·5·(1 − opacidade).
            x: root.mirX(root.dateLeftLTR, root.dateW) + (root.theme ? root.theme.dir : 1) * Motion.FADE.L2_DATE_IN.dx * (1 - dateLayer.opacity)
            y: (root.morph ? root.morph.bandY : 36) - height / 2
            width: root.dateW
            theme: root.theme
            size: 14
            weight: 500
            color: root.theme ? root.theme.inkDate : "white"
            text: root.dateText
            Accessible.role: Accessible.StaticText
            Accessible.name: root.dateText
        }
    }

    // ---- L2, fileira dos módulos do Omarchy (abaixo da faixa) ----
    // Nunca `visible: false` aqui: os widgets leem a visibilidade herdada para a largura.
    Item {
        id: modsLayer
        anchors.fill: parent
        opacity: 0
        Rectangle {
            visible: root.modsW > 0
            x: (root.morph ? root.morph.left : 0) + root.px("L2_MOD_PAD", 24)
            y: (root.morph ? root.morph.top : 10) + root.px("L2_H", 52)
            width: Math.max(0, (root.morph ? root.morph.w : 0) - 2 * root.px("L2_MOD_PAD", 24))
            height: 1
            color: root.theme ? root.theme.alpha(root.theme.ink, 0.08) : "transparent"
        }
        OmarchyWidgets {
            id: mods
            island: root.island
            output: root.output
            rtl: root.rtl
            shown: root.face === "hover2"
            glyph: root.theme ? root.theme.alpha(root.theme.ink, 0.9) : Commons.Color.bar.text
            accent: root.theme ? root.theme.accent : Commons.Color.bar.text
            divider: root.theme ? root.theme.alpha(root.theme.ink, 0.12) : "gray"
            // KeyboardPanel abre em barSizeFor + gapsOut: a borda de baixo do L2, na tela.
            popupFloor: (root.island ? root.island.devTop : 0) + root.geomL2.top + root.geomL2.h
            x: root.cx - width / 2
            y: (root.morph ? root.morph.top : 10) + root.px("L2_H", 52) + root.px("L2_MOD_DY", 17) - height / 2
            width: implicitWidth
            height: implicitHeight
        }
    }

    // ---- Marca do repouso ----
    RestMark {
        id: mark
        anchors.fill: parent
        theme: root.theme
        strings: root.strings
        status: root.status
        media: root.media
        morph: root.morph
        rtl: root.rtl
        clockLeft: root.clockLeft
        clockRight: root.clockRight
        highlighted: root.markHovered
    }

    // ---- Seletor de telas ----
    ScreenPicker {
        id: picker
        anchors.fill: parent
        theme: root.theme
        strings: root.strings
        morph: root.morph
        rtl: root.rtl
        shown: root.face === "picker"
        pressed: root.pressed
        workspaces: workspaces
        clockW: root.clockW
        glyphs: root.island ? root.island.glyphs : null
    }
}
