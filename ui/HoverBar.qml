pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.Commons as Commons
import "Motion.js" as Motion

// Conteúdo dos níveis de hover (L1 e L2), a marca do repouso e o seletor de
// telas. Camada do tamanho da janela, sem layout próprio e sem nada que
// aceite hover: fica dentro do recorte do conteúdo da IslandWindow, em
// coordenadas da janela, recebe o ponteiro (`pointer`) e responde hitTest.
// O relógio NÃO é daqui (um só por janela, da IslandWindow); daqui saem
// l2ClockDx e as larguras que alimentam geometryFor.
//
// Layout (px lógicos, LTR; em RTL todo x calculado espelha com
// x' = 2·cx − x − largura; relógio, bateria e barras de rede seguem LTR):
// - L1 (h 42, topo 22): cápsulas a partir de L + 33; à direita, com o fim do
//   pino da bateria em R − 37: equalizador (com faixa), 10, ponto de
//   privacidade, 10, rede (14), 9, bateria (27,5). sideL = 33 + G + 23;
//   sideR = 37 + rightW + 23 (Theme.geometryFor usa max dos dois).
// - L2 (718 x 75, topo 10): linha de cima presa às bordas vivas (contexto em
//   morph.left + 34; estado com o glifo em morph.right − 37); cápsulas a 1,33
//   em L + 33,6; rede e bateria a 1,0 com o corpo da bateria em R − 37; no
//   centro o relógio (1,375, da janela) e a data 11 px depois.
// - Cada item da linha de baixo tem uma mola p (0 = vaga do L1, 1 = vaga do
//   L2): x = lerp(xL1, xL2, p), y = centerY + 12,5·p, escala lerp(sL1, sL2, p).
//   Nada depende de morph.w / morph.h; só a linha de cima segue as bordas.
//
// Choreografias (motion + amendments §13): A, B, C, D, E (o mergulho do
// topo é da IslandWindow), F, H, I, M, N, P e as entradas e saídas da marca.
// Cada troca de face recomeça os fades a partir da opacidade atual (regra 7).
//
// hitTest(x, y) (coordenadas da janela) ->
//   "ws:<id>" | "eq" | "privacy" | "context" | "center" | "status"   (L1/L2)
//   "mark" | "mark:media"                                            (repouso)
//   "pick:<screenId>" | "pick:"                                      (seletor)
//   ""                                                               (vazio)
// activate(hit) executa: ws -> foco; eq / mark:media -> Mídia; mark -> dono
// (§4.5); pick:<id> -> island.open(id); pick: -> closePicker; context ->
// Mídia (player) ou Apps; center -> Central; status -> ação da linha
// (fixada por statusPin); "" ou privacy no L1 -> expand(); "" no L2 -> collapse().
Item {
    id: root

    // ---- Entradas ----
    property var island: null
    property Theme theme: null
    property var strings: null
    property var morph: null
    property string output: ""
    // Nível de hover 0 / 1 / 2 e a face da janela (rest, hover1, hover2, picker, peek, osd, screen).
    property int level: 0
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
    // Larguras laterais do L1 (geometryFor ctx.sideL / sideR).
    readonly property real sideL: root.dims.l1InsetL + workspaces.groupWidth + root.dims.l1Gap
    readonly property real sideR: root.dims.l1InsetR + root.rightW + root.dims.l1Gap
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
    readonly property bool wantsHand: root.hoverHit !== "" && root.hoverHit !== "privacy" && root.hoverHit !== "pick:"
    // Marca do repouso: largura (geometryFor ctx.markW) e coluna (janela).
    readonly property real restMarkW: mark.markW
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
        // Cápsulas: 12 x 16 (16 x 16 para "10"), raio 6, vão 4.
        capW: 12, capWide: 16, capH: 16, capR: 6, capGap: 4,
        // L1: margens e vãos
        l1InsetL: 33, l1InsetR: 37, l1Gap: 23,
        eqW: 11.5, eqH: 12, eqGap: 10, dot: 8, dotGap: 10, netW1: 14, netGap: 9, battW1: 27.5,
        // Rede e bateria desenhadas no tamanho do L2
        netW: 19.25, netH: 16,
        battBodyW: 33, battBodyH: 16.5, battR: 5.5, battNubGap: 1.4, battNubW: 2.75, battNubH: 8.25,
        // L2
        capLeft2: 33.6, rowDy: 12.5, topRow: 23.5, ctxIconX: 34, ctxLabelX: 58, ctxIcon: 14,
        labelMax: 200, statusGlyph: 15, statusInset: 37, statusGap: 11, netBattGap2: 10, dateGap: 11,
        // Destaques do L2
        hlTop: 11, hlH: 25, hlR: 10, hlCenterPad: 14, hlCenterH: 36, hlCenterR: 12, hlPad: 10
    })
    readonly property real battFullW: root.dims.battBodyW + root.dims.battNubGap + root.dims.battNubW

    function px(name, fallback) {
        return root.theme && root.theme.px[name] !== undefined ? root.theme.px[name] : fallback;
    }
    readonly property real s1: root.px("L1_INDICATOR_SCALE", 0.727)
    readonly property real s2: root.px("L2_CAPSULE_SCALE", 1.33)

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
    readonly property bool batteryCharging: root.hasBattery && !UPower.onBattery
    readonly property bool batteryLow: root.hasBattery && UPower.onBattery && root.batteryLevel <= 0.15

    readonly property string netAccessible: root.netWired ? root.tr("bar.ethernet")
        : root.netWifi ? root.fmt(root.tr("bar.wifiSignal"), [Commons.I18n.formatNumber(Math.round(Number(root.net.signal) || 0))])
        : root.tr("bar.offline")
    readonly property string battAccessible: root.fmt(root.tr(root.batteryCharging ? "bar.batteryCharging" : "bar.battery"),
        [Commons.I18n.formatNumber(Math.round(root.batteryLevel * 100))])

    readonly property bool eqShown: !!root.media && root.media.hasTrack
    readonly property bool privacyShown: !!root.status && root.status.privacy
    readonly property real rightW: (root.eqShown ? root.dims.eqW + root.dims.eqGap : 0) + (root.privacyShown ? root.dims.dot + root.dims.dotGap : 0)
        + root.dims.netW1 + (root.hasBattery ? root.dims.netGap + root.dims.battW1 : 0)

    // ---- Geometria-alvo das faces (nunca animada) ----
    readonly property real clockW: Math.max(0, root.clockRight - root.clockLeft)
    readonly property real screenW: root.cx * 2
    readonly property var geomRest: root.theme ? root.theme.geometryFor("rest", { clockW: root.clockW, markW: mark.markW, screenW: root.screenW }) : ({ w: 84, h: 32, top: 10, cap: 16 })
    readonly property var geomL1: root.theme ? root.theme.geometryFor("hover1", { clockW: root.clockW, sideL: root.sideL, sideR: root.sideR, screenW: root.screenW }) : ({ w: 308, h: 42, top: 22, cap: 21 })
    readonly property var geomL2: root.theme ? root.theme.geometryFor("hover2", { screenW: root.screenW }) : ({ w: 718, h: 75, top: 10, cap: 31 })
    readonly property real l2Left: root.cx - root.geomL2.w / 2
    readonly property real l2Right: root.cx + root.geomL2.w / 2

    // Meia largura do L1 desenhada: pula para o alvo, mas desliza (hover)
    // quando o L1 já está à vista e o conteúdo muda (música, workspace novo):
    // os itens acompanham a forma em vez de pular.
    SpringValue { id: l1Half }
    readonly property real l1HalfTarget: root.geomL1.w / 2
    onL1HalfTargetChanged: {
        if (root.face === "hover1" && capsLayer.opacity > 0.01)
            l1Half.go(root.l1HalfTarget, "hover");
        else
            l1Half.snap(root.l1HalfTarget);
    }
    readonly property real l1LeftLive: root.cx - l1Half.value
    readonly property real l1RightLive: root.cx + l1Half.value

    // Cápsulas: deslocamento e largura de cada uma (unidades do L1).
    readonly property var capGeo: {
        const out = [];
        let off = 0;
        const items = workspaces.items;
        for (let i = 0; i < items.length; i++) {
            const w = items[i].wide ? root.dims.capWide : root.dims.capW;
            out.push({ off: off, w: w });
            off += w + root.dims.capGap;
        }
        return out;
    }
    function capCenterL1(g, left) {
        return left + root.dims.l1InsetL + g.off + g.w / 2;
    }
    function capCenterL2(g) {
        return root.l2Left + root.dims.capLeft2 + root.s2 * (g.off + g.w / 2);
    }

    // Grupo da direita do L1 (centros LTR) a partir da borda direita R.
    function rightL1(R) {
        const netRight = root.hasBattery ? R - root.dims.l1InsetR - root.dims.battW1 - root.dims.netGap : R - root.dims.l1InsetR;
        const netC = netRight - root.dims.netW1 / 2;
        const battC = R - root.dims.l1InsetR - root.battFullW * root.s1 / 2;
        const privC = netRight - root.dims.netW1 - root.dims.dotGap - root.dims.dot / 2;
        const eqRight = root.privacyShown ? netRight - root.dims.netW1 - root.dims.dotGap - root.dims.dot - root.dims.eqGap : netRight - root.dims.netW1 - root.dims.eqGap;
        return { netC: netC, battC: battC, privC: privC, eqC: eqRight - root.dims.eqW / 2 };
    }
    // Rede e bateria no L2 (centros LTR): o corpo da bateria termina em R − 37.
    readonly property real battC2: root.l2Right - root.dims.statusInset - root.dims.battBodyW + root.battFullW / 2
    readonly property real netC2: (root.hasBattery ? root.l2Right - root.dims.statusInset - root.dims.battBodyW - root.dims.netBattGap2 : root.l2Right - root.dims.statusInset) - root.dims.netW / 2

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
        case "hover1":
            return root.hitL1(x, y);
        case "hover2":
            return root.hitL2(x, y);
        default:
            return "";
        }
    }

    function hitL1(x, y) {
        const top = root.px("L1_TOP", 22), bottom = top + root.px("L1_H", 42);
        if (y < top || y > bottom)
            return "";
        const lx = root.rtl ? 2 * root.cx - x : x;
        const L = root.cx - root.geomL1.w / 2, R = root.cx + root.geomL1.w / 2;
        // Cápsula: o passo inteiro (largura + vão) x a altura da pílula.
        const items = workspaces.items;
        for (let i = 0; i < items.length && i < root.capGeo.length; i++) {
            const g = root.capGeo[i];
            if (Math.abs(lx - root.capCenterL1(g, L)) <= g.w / 2 + root.dims.capGap / 2)
                return "ws:" + items[i].id;
        }
        const rg = root.rightL1(R);
        if (root.eqShown && Math.abs(lx - rg.eqC) <= 14)
            return "eq";
        if (root.privacyShown && Math.abs(lx - rg.privC) <= root.dims.dot / 2 + 5)
            return "privacy";
        return "";
    }

    function hitL2(x, y) {
        const lx = root.rtl ? 2 * root.cx - x : x;
        const top = root.px("TOP", 10);
        const cy = top + root.geomL2.h / 2;
        // Centro: o grupo relógio + data, 14 px a mais de cada lado, 36 de altura.
        if (Math.abs(lx - root.cx) <= root.centerGroupW / 2 + root.dims.hlCenterPad && Math.abs(y - (cy - 1)) <= root.dims.hlCenterH / 2)
            return "center";
        const rowTop = top + root.dims.hlTop, rowBottom = top + root.dims.hlTop + root.dims.hlH;
        if (y >= rowTop && y <= rowBottom) {
            const L = root.l2Left, R = root.l2Right;
            if (lx >= L + root.dims.ctxIconX - root.dims.hlPad && lx <= L + root.dims.ctxLabelX + root.ctxLabelW + root.dims.hlPad)
                return "context";
            const glyphRight = R - root.dims.statusInset;
            const textLeft = glyphRight - root.dims.statusGlyph - root.dims.statusGap - root.statusShownW;
            if (root.lineClickable && lx >= textLeft - root.dims.hlPad && lx <= glyphRight + root.dims.hlPad)
                return "status";
            return "";
        }
        // Cápsulas da linha de baixo: o passo inteiro a 1,33, da linha de cima até o fim da zona.
        if (y > rowBottom && y <= root.px("ZONE_L2_H", 91)) {
            const items = workspaces.items;
            for (let i = 0; i < items.length && i < root.capGeo.length; i++) {
                const g = root.capGeo[i];
                if (Math.abs(lx - root.capCenterL2(g)) <= root.s2 * (g.w / 2 + root.dims.capGap / 2))
                    return "ws:" + items[i].id;
            }
        }
        return "";
    }

    function activate(hit) {
        const h = String(hit || "");
        if (!root.island)
            return false;
        if (h.indexOf("pick:") === 0) {
            const id = h.slice(5);
            if (id === "") {
                root.island.closePicker();
                return true;
            }
            root.island.keyboardMode = false;
            return root.island.open(id, root.output);
        }
        if (h === "mark:media" || h === "eq")
            return root.island.open("media", root.output);
        if (h === "mark") {
            const owner = root.status ? root.status.markOwner : "";
            if (owner === "l2")
                return root.island.setExpanded(root.output, true, root.status.markKey);
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
        if (h === "" || h === "privacy") {
            // Relógio -> linha -> clique: o menu das telas (o L2 largo fica para o
            // atalho do calendário e para as linhas de estado da marca).
            if (root.face === "hover1")
                root.island.openPicker(root.output);
            else if (root.face === "hover2" && h === "")
                root.collapse();
            return true;
        }
        return false;
    }

    // ---- Choreografia ----
    QtObject {
        id: priv
        property string lastFace: "rest"
        // Alvo do p dos itens da linha de baixo (0 = L1, 1 = L2).
        property real pTarget: 0
        // O ponteiro andou desde que o L2 abriu (o destaque só aparece então).
        property bool movedInL2: false
        // Ordem para as molas p das cápsulas: mode 0 pula, 1 desliza sem
        // escalonar, 2 expande (C), 3 recolhe (D, E).
        signal pCommand(real v, string motion, int mode)
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

    // p de todos os itens com o escalonamento de C (expandindo: cápsula i
    // com 25·i, a de fora primeiro; bateria 0, rede 25) ou de D/E (recolhendo:
    // a de dentro primeiro, 10·j; a rede sai 15 ms antes da bateria).
    function moveP(v, motion, expanding) {
        const F = Motion.FADE;
        priv.pTarget = v;
        priv.pCommand(v, motion, expanding ? 2 : 3);
        netP.go(v, motion, expanding ? F.NETWORK_DELAY_IN : 0);
        battP.go(v, motion, expanding ? F.BATTERY_DELAY_IN : F.NETWORK_LEAD_OUT);
    }

    // p sem escalonamento: pula se a camada está invisível (N, M, H, P…),
    // senão desliza (uma volta rápida no meio de outra transição).
    function placeP(v) {
        priv.pTarget = v;
        const hidden = capsLayer.opacity < 0.02;
        priv.pCommand(v, "hover", hidden ? 0 : 1);
        if (hidden) {
            netP.snap(v);
            battP.snap(v);
        } else {
            netP.go(v, "hover", 0);
            battP.go(v, "hover", 0);
        }
    }

    function choreo(from, to) {
        const F = Motion.FADE;
        // Linha de cima do L2: some na hora fora do L2 (D, E, F, P).
        if (to !== "hover2") {
            root.fade(iconsF, 0, 0, 0);
            root.fade(labelsF, 0, 0, 0);
            priv.movedInL2 = false;
        }
        // Marca: só no repouso; entra conforme de onde vem.
        if (to === "rest") {
            const m = from === "hover1" ? F.MARK_IN_FROM_L1 : (from === "hover2" ? F.MARK_IN_FROM_L2 : F.MARK_IN_AFTER);
            root.fade(markF, 1, m.delay, m.dur);
        } else {
            root.fade(markF, 0, 0, F.MARK_OUT);
        }

        switch (to) {
        case "hover1":
            if (from === "hover2") {
                // D
                root.fade(dateF, 0, F.L2_DATE_OUT.delay, F.L2_DATE_OUT.dur);
                root.moveP(0, "hover", false);
                root.fade(capsF, 1, 0, F.L1_IN.dur);
                root.fade(l1F, 1, F.L1_EQ_IN.delay, F.L1_EQ_IN.dur);
            } else {
                // A (do repouso), H (de uma tela), P out (do seletor), I out (OSD, aviso)
                const t = from === "rest" ? F.L1_IN : ((from === "screen" || from === "picker") ? F.L1_IN_AFTER : F.CLOCK_IN_AFTER);
                root.placeP(0);
                root.fade(capsF, 1, t.delay, t.dur);
                root.fade(l1F, 1, t.delay, t.dur);
                root.fade(dateF, 0, 0, F.CONTENT_OUT.dur);
            }
            break;
        case "hover2":
            if (from === "hover1") {
                // C
                root.moveP(1, "hover", true);
                root.fade(capsF, 1, 0, F.L1_IN.dur);
                root.fade(l1F, 0, F.L2_EQ_OUT.delay, F.L2_EQ_OUT.dur);
            } else {
                // N (repouso), M (aviso) e os outros caminhos diretos: p pula para 1.
                root.placeP(1);
                root.fade(capsF, 1, F.DIRECT_L2.itemsDelay, F.DIRECT_L2.itemsDur);
                root.fade(l1F, 0, 0, F.CONTENT_OUT.dur);
            }
            root.fade(iconsF, 1, F.L2_ICONS_IN.delay, F.L2_ICONS_IN.dur);
            root.fade(labelsF, 1, F.L2_LABELS_IN.delay, F.L2_LABELS_IN.dur);
            root.fade(dateF, 1, F.L2_DATE_IN.delay, F.L2_DATE_IN.dur);
            break;
        case "rest":
            if (from === "hover1") {
                // B
                root.fade(capsF, 0, F.L1_OUT.delay, F.L1_OUT.dur);
                root.fade(l1F, 0, F.L1_OUT.delay, F.L1_OUT.dur);
            } else if (from === "hover2") {
                // E: as cápsulas voltam com o escalonamento de D na mola lenta.
                root.fade(dateF, 0, F.L2_DATE_OUT.delay, F.L2_DATE_OUT.dur);
                root.moveP(0, "slow", false);
                root.fade(capsF, 0, F.L2_ITEMS_OUT.delay, F.L2_ITEMS_OUT.dur);
                root.fade(l1F, 0, 0, F.CONTENT_OUT.dur);
            } else {
                root.fade(capsF, 0, 0, F.CONTENT_OUT.dur);
                root.fade(l1F, 0, 0, F.CONTENT_OUT.dur);
                root.fade(dateF, 0, 0, F.CONTENT_OUT.dur);
            }
            break;
        default:
            // F (tela), I (OSD), aviso e P (seletor): todo o conteúdo do hover sai em 60 ms.
            root.fade(capsF, 0, 0, F.CONTENT_OUT.dur);
            root.fade(l1F, 0, 0, F.CONTENT_OUT.dur);
            root.fade(dateF, 0, 0, F.CONTENT_OUT.dur);
            break;
        }
    }

    // Estado parado de uma face (início, sem animação).
    function snapFace(f) {
        const l2 = f === "hover2";
        const l1 = f === "hover1";
        const pairs = [[markF, f === "rest" ? 1 : 0], [capsF, l1 || l2 ? 1 : 0], [l1F, l1 ? 1 : 0],
                       [iconsF, l2 ? 1 : 0], [labelsF, l2 ? 1 : 0], [dateF, l2 ? 1 : 0]];
        for (let i = 0; i < pairs.length; i++) {
            pairs[i][0].stop();
            pairs[i][0].item.opacity = pairs[i][1];
        }
        priv.pTarget = l2 ? 1 : 0;
        priv.pCommand(priv.pTarget, "hover", 0);
        netP.snap(priv.pTarget);
        battP.snap(priv.pTarget);
    }

    onFaceChanged: {
        const from = priv.lastFace;
        priv.lastFace = root.face;
        root.choreo(from, root.face);
    }

    Component.onCompleted: {
        priv.lastFace = root.face;
        root.syncCaps();
        l1Half.snap(root.l1HalfTarget);
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

    // Equalizador do L1: 3 barras de 2,5 (vão 2) no accent. Tocando: alturas
    // 4..12 em seno, fases 0 / 0,33 / 0,66, período 900 ms (só enquanto o L1
    // aparece; parado com reduzir movimento). Pausado: 5 / 9 / 6 a 45%.
    component Equalizer: Item {
        id: eqz
        property Theme theme: null
        property bool playing: false
        property bool animating: false
        property real phase: 0
        width: 11.5
        height: 12
        LayoutMirroring.enabled: false

        FrameAnimation {
            id: eqFrames
            running: eqz.animating
            onTriggered: eqz.phase = (eqz.phase + Math.min(eqFrames.frameTime, Motion.MAX_FRAME) * 1000 / Motion.FADE.EQ_PERIOD) % 1
        }

        Item {
            anchors.fill: parent
            opacity: eqz.playing ? 1 : 0.45
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real still: [5, 9, 6][index]
                    x: index * 4.5
                    y: eqz.height - height
                    width: 2.5
                    radius: 1.25
                    height: eqz.playing && eqz.animating ? 8 + 4 * Math.sin(2 * Math.PI * (eqz.phase + index * 0.33)) : still
                    color: eqz.theme ? eqz.theme.accent : "white"
                }
            }
        }
    }

    Fader { id: capsF; item: capsLayer }
    Fader { id: l1F; item: l1Layer }
    Fader { id: iconsF; item: iconsLayer }
    Fader { id: labelsF; item: labelsLayer }
    Fader { id: dateF; item: dateLayer }
    Fader { id: markF; item: mark }

    Workspaces {
        id: workspaces
        output: root.output
        onCountChanged: root.syncCaps()
    }

    // Uma linha por cápsula, mexida só nas pontas: um workspace novo cria um
    // delegado e os outros ficam (a mola p e os fades não recomeçam).
    ListModel {
        id: capModel
    }
    function syncCaps() {
        const n = workspaces.count;
        while (capModel.count < n)
            capModel.append({ slot: capModel.count });
        while (capModel.count > n)
            capModel.remove(capModel.count - 1);
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

    // Progressos 0..1: limiar fino (ver SpringValue).
    SpringValue { id: netP; settlePos: 0.001; settleVel: 0.04 }
    SpringValue { id: battP; settlePos: 0.001; settleVel: 0.04 }

    // ---- Destaques dos módulos do L2 (tinta a 10%; entra 120 ms linear, sai 70 ms) ----
    Rectangle {
        id: ctxHighlight
        readonly property bool lit: root.hoverModule === "context"
        readonly property real l: root.morph ? root.morph.left + root.dims.ctxIconX - root.dims.hlPad : 0
        readonly property real w: root.dims.ctxLabelX - root.dims.ctxIconX + root.ctxLabelW + 2 * root.dims.hlPad
        x: root.mirX(ctxHighlight.l, ctxHighlight.w)
        y: (root.morph ? root.morph.top : 10) + root.dims.hlTop
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
        y: (root.morph ? root.morph.centerY : 47.5) - 1 - height / 2
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
        y: (root.morph ? root.morph.top : 10) + root.dims.hlTop
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

    // ---- Linha de baixo: cápsulas, rede e bateria (L1 e L2) ----
    Item {
        id: capsLayer
        anchors.fill: parent
        opacity: 0

        Repeater {
            id: capRepeater
            model: capModel

            Item {
                id: cap
                required property int index
                readonly property var d: workspaces.items[cap.index] || ({ id: 0, label: "", wide: false, active: false, occupied: false, urgent: false })
                readonly property var g: root.capGeo[cap.index] || ({ off: 0, w: root.dims.capW })
                readonly property real p: capP.value
                readonly property bool hot: root.hoverHit === "ws:" + cap.d.id
                // Escala própria do ativo (1,25), animada na troca de workspace.
                property real activeK: cap.d.active ? 1.25 : 1
                Behavior on activeK {
                    NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.WS_SWITCH) : 0; easing.type: Easing.OutCubic }
                }

                x: root.mir(Motion.lerp(root.capCenterL1(cap.g, root.l1LeftLive), root.capCenterL2(cap.g), cap.p)) - width / 2
                y: (root.morph ? root.morph.centerY : 43) + root.dims.rowDy * cap.p - height / 2
                width: cap.g.w
                height: root.dims.capH
                scale: Motion.lerp(1, root.s2, cap.p) * cap.activeK

                Accessible.role: Accessible.Button
                Accessible.name: root.fmt(root.tr("bar.workspace"), [cap.d.label])

                SpringValue { id: capP; settlePos: 0.001; settleVel: 0.04 }
                Connections {
                    target: priv
                    function onPCommand(v, motion, mode) {
                        if (mode === 0)
                            capP.snap(v);
                        else if (mode === 1)
                            capP.go(v, motion, 0);
                        else
                            capP.go(v, motion, mode === 2 ? Motion.FADE.CAPSULE_STAGGER_IN * cap.index
                                                          : Motion.FADE.CAPSULE_STAGGER_OUT * (workspaces.count - 1 - cap.index));
                    }
                }

                // Uma cápsula nova (workspace criado) entra em 100 ms.
                opacity: 0
                NumberAnimation {
                    id: capIn
                    target: cap
                    property: "opacity"
                    to: 1
                    duration: root.theme ? root.theme.dur(Motion.FADE.CAPSULE_HOVER) : 0
                    easing.type: Easing.OutCubic
                }
                Component.onCompleted: {
                    capP.snap(priv.pTarget);
                    if (capsLayer.opacity > 0.01)
                        capIn.start();
                    else
                        cap.opacity = 1;
                }

                // Brilho do ativo: sombra no accent a 45%, blur 6.
                RectangularShadow {
                    anchors.fill: parent
                    radius: root.dims.capR
                    blur: 6
                    spread: 0
                    color: root.theme ? root.theme.alpha(root.theme.accent, 0.45) : "transparent"
                    opacity: cap.d.active ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.WS_SWITCH) : 0; easing.type: Easing.OutCubic }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: root.dims.capR
                    antialiasing: true
                    color: !root.theme ? "gray"
                        : cap.d.active ? root.theme.accent
                        : cap.d.urgent ? root.theme.mix(root.theme.surface, root.theme.danger, 0.45)
                        : cap.d.occupied ? root.theme.mix(root.theme.surface, root.theme.accent, 0.40)
                        : root.theme.mix(root.theme.surface, root.theme.ink, 0.15)
                    Behavior on color {
                        ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.WS_SWITCH) : 0; easing.type: Easing.OutCubic }
                    }
                }
                // Hover: +8% de tinta em 100 ms.
                Rectangle {
                    anchors.fill: parent
                    radius: root.dims.capR
                    color: root.theme ? root.theme.alpha(root.theme.ink, 0.08) : "transparent"
                    opacity: cap.hot ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CAPSULE_HOVER) : 0 }
                    }
                }
                IlhaText {
                    anchors.centerIn: parent
                    theme: root.theme
                    size: 10
                    weight: 600
                    tnum: true
                    color: !root.theme ? "white"
                        : cap.d.active ? root.theme.onAccent
                        : cap.d.urgent ? root.theme.ink
                        : root.theme.alpha(root.theme.ink, cap.d.occupied ? 0.92 : 0.45)
                    text: cap.d.label
                    Behavior on color {
                        ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.WS_SWITCH) : 0 }
                    }
                }
            }
        }

        NetIndicator {
            id: netItem
            theme: root.theme
            wifi: root.netWifi
            wired: root.netWired
            bars: root.netBars
            readonly property real c: Motion.lerp(root.rightL1(root.l1RightLive).netC, root.netC2, netP.value)
            x: root.mir(netItem.c) - width / 2
            y: (root.morph ? root.morph.centerY : 43) + root.dims.rowDy * netP.value - height / 2
            scale: Motion.lerp(root.s1, 1, netP.value)
            Accessible.role: Accessible.StaticText
            Accessible.name: root.netAccessible
        }

        BatteryIndicator {
            id: battItem
            theme: root.theme
            level: root.batteryLevel
            charging: root.batteryCharging
            low: root.batteryLow
            readonly property real c: Motion.lerp(root.rightL1(root.l1RightLive).battC, root.battC2, battP.value)
            x: root.mir(battItem.c) - width / 2
            y: (root.morph ? root.morph.centerY : 43) + root.dims.rowDy * battP.value - height / 2
            scale: Motion.lerp(root.s1, 1, battP.value)
            opacity: root.hasBattery ? 1 : 0
            Accessible.role: Accessible.StaticText
            Accessible.name: root.battAccessible
        }
    }

    // ---- Só no L1: equalizador e ponto de privacidade ----
    Item {
        id: l1Layer
        anchors.fill: parent
        opacity: 0
        readonly property var slots: root.rightL1(root.l1RightLive)

        Equalizer {
            id: eqItem
            theme: root.theme
            playing: !!root.media && root.media.playing
            animating: root.eqShown && eqItem.playing && root.face === "hover1" && l1Layer.opacity > 0.01
                && !(root.theme && root.theme.reduceMotion)
            x: root.mir(l1Layer.slots.eqC) - width / 2
            y: (root.morph ? root.morph.centerY : 43) - height / 2
            opacity: root.eqShown ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
            }
        }

        Item {
            id: dotSlot
            x: root.mir(l1Layer.slots.privC) - width / 2
            y: (root.morph ? root.morph.centerY : 43) - height / 2
            width: root.dims.dot
            height: root.dims.dot
            opacity: root.privacyShown ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: dot
                anchors.fill: parent
                radius: width / 2
                color: root.theme ? root.theme.danger : "red"
            }
            // Pulsa 1 <-> 0,45 em 1200 ms (InOutSine) só gravando e com o L1 à vista.
            SequentialAnimation {
                id: pulse
                running: !!root.status && root.status.recording && root.face === "hover1" && !(root.theme && root.theme.reduceMotion)
                loops: Animation.Infinite
                onRunningChanged: if (!pulse.running) dot.opacity = 1
                NumberAnimation {
                    target: dot
                    property: "opacity"
                    to: Motion.FADE.DOT_PULSE.low
                    duration: Motion.FADE.DOT_PULSE.dur / 2
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: dot
                    property: "opacity"
                    to: 1
                    duration: Motion.FADE.DOT_PULSE.dur / 2
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    // ---- L2, linha de cima: ícones (presos às bordas vivas) ----
    Item {
        id: iconsLayer
        anchors.fill: parent
        opacity: 0
        readonly property real rowY: (root.morph ? root.morph.top : 10) + root.dims.topRow

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
            name: root.line ? String(root.line.icon || "") : ""
            filled: !!root.line && !!root.line.filled
            color: root.theme && root.line ? root.theme.toneColor(root.line.tone) : "white"
        }
    }

    // ---- L2, linha de cima: rótulos (relativos aos ícones) ----
    Item {
        id: labelsLayer
        anchors.fill: parent
        opacity: 0
        readonly property real rowY: (root.morph ? root.morph.top : 10) + root.dims.topRow
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
            readonly property real edgeR: (root.morph ? root.morph.right : 0) - root.dims.statusInset - root.dims.statusGlyph - root.dims.statusGap
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
            y: (root.morph ? root.morph.centerY : 47.5) - 1 - height / 2
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
    }
}
