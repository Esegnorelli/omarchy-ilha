import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons as Commons
import "Motion.js" as Motion

// Uma janela por monitor: a forma da ilha (Morph), a sombra, o recorte do
// conteúdo, o relógio único, o HoverBar, os desenhos do OSD e do aviso, as
// telas (ScreenStack), a dica da linha, a máscara de entrada e o teclado.
// Dono: Agent A.
//
// Face (amendments §1; primeira que casar):
//   screen > osd > peek > picker > hover2 (expanded) > hover1 (hovered && !markHold) > rest
// Cada troca de face (T0) chama applyFace(from, to): a forma vai ao alvo de
// Theme.geometryFor com a mola da transição, o relógio faz a sua parte, os
// desenhos do OSD e do aviso fazem fade, a pilha de telas abre/troca/fecha e
// a face é relatada ao Ilha (reportFace). Os itens do L1/L2, a marca do
// repouso e o seletor fazem os próprios fades no HoverBar.
//
// Molas da forma (motionFor): telas "panel"; L2 -> repouso "slow" com o
// mergulho do topo (E: 22 no hover já, 10 no slow em +50 ms); o resto "hover".
//
// Relógio (um só; regra 1): p (clockP) 0 = repouso/L1, 1 = L2; deslocamento
// dx = lerp(restDxSpring, l2ClockDx, p). restDxSpring mira restDx (marca ao
// lado, §4.2) só no repouso e 0 nas outras faces, então o relógio desliza em
// vez de pular (A, B, E, N, R). Entra em faces sem relógio (tela, OSD, aviso,
// seletor) saindo em 60 ms; p e dx vão ao repouso quando o fade termina. Ao
// voltar, p e dx pulam no T0 e ele aparece em 70 ms depois de 50 (H, I, M, P).
//
// Coordenadas: tudo que fica dentro do recorte usa coordenadas da janela (a
// camada `content` desfaz o deslocamento do recorte). Máscara e zona de
// hover usam o ALVO (zoneFor), nunca o valor animado (regra 6).
PanelWindow {
    id: win

    required property var modelData
    property var island: null

    screen: win.modelData

    // ---- Saídas ----
    readonly property string output: String(win.modelData.name)
    readonly property Theme theme: win.island ? win.island.theme : null
    readonly property real screenW: win.modelData.width
    readonly property real screenH: win.modelData.height
    readonly property real cx: win.screenW / 2

    // Esta janela é a que recebe telas e OSDs agora.
    readonly property bool isActive: !!win.island && win.island.screenOutput === win.output
    readonly property bool screenHere: !!win.island && win.island.screen !== "" && win.island.screenOutput === win.output
    readonly property bool osdHere: !!win.island && win.island.osd.showing && win.island.osd.output === win.output
    readonly property bool peekHere: !!win.island && win.island.peek.showing && win.island.peek.output === win.output
    readonly property bool pickerHere: !!win.island && win.island.pickerOutput === win.output
    readonly property bool expanded: !!win.island && win.island.expandedOutput === win.output
    readonly property bool isFocused: !!win.island && (win.island.dev || (!!Hyprland.focusedMonitor && String(Hyprland.focusedMonitor.name) === win.output))
    // Voltou ao repouso fora de foco (focusedOnly): a forma termina de
    // encolher antes do fade (choreografia S).
    property bool restFadingOut: false
    // Quem desenha a cápsula (amendments §10). "Face fora do repouso" usa a
    // face já aplicada (priv.lastFace, atribuída à mão) para não fazer laço
    // de ligação com `face`, que depende de `hovered`, que depende disto.
    readonly property bool drawsPill: !win.island || !win.island.prefs.focusedOnly || win.isFocused
        || win.screenHere || win.osdHere || win.peekHere || win.pickerHere || win.expanded
        || priv.lastFace !== "rest" || win.restFadingOut
    // A máscara de quem não desenha fica vazia desde o T0 (sem a folga do fade).
    readonly property bool inputAllowed: !win.island || !win.island.prefs.focusedOnly || win.isFocused
        || win.screenHere || win.osdHere || win.peekHere || win.pickerHere || win.expanded || priv.lastFace !== "rest"
    readonly property bool pointerInside: priv.inZone || priv.inStrip
    readonly property bool hovered: !!win.island && (win.pointerInside || grace.running || win.island.hoverOutput === win.output)
        && win.drawsPill && !win.island.barHidden
    // Ponteiro na coluna da marca do repouso: segura o repouso (toque na marca, §4.4).
    property bool markHold: false

    readonly property string face: win.screenHere ? "screen"
        : win.osdHere ? "osd"
        : win.peekHere ? "peek"
        : win.pickerHere ? "picker"
        : win.expanded ? "hover2"
        : (win.hovered && !win.markHold) ? "hover1"
        : "rest"
    readonly property int hoverLevel: win.face === "hover2" ? 2 : (win.face === "hover1" ? 1 : 0)
    readonly property bool layerOverlay: win.face === "screen" && !!win.island && win.island.fullscreenOn(win.output)

    // ---- Geometria-alvo ----
    // Altura viva da tela aberta (0 = a estática de Theme.screenSize).
    property real panelH: 0
    readonly property var ctx: ({
        clockW: clock.naturalWidth,
        privacy: !!win.island && win.island.status.privacy,
        sideL: bar.sideL,
        sideR: bar.sideR,
        osdW: osdFace.implicitWidth,
        markW: bar.restMarkW,
        peekW: peekFace.implicitWidth,
        screenW: win.screenW,
        screenH: win.screenH,
        screenId: win.island ? win.island.screen : "",
        panelH: win.panelH
    })
    readonly property var targetGeom: win.theme ? win.theme.geometryFor(win.face, win.ctx) : ({ w: 84, h: 32, top: 10, cap: 16 })
    // A face por baixo do OSD (a zona do OSD é unida com a dela).
    readonly property string underFace: win.expanded ? "hover2" : (win.hovered ? "hover1" : "rest")
    readonly property var zone: {
        if (!win.theme)
            return { x: 0, y: 0, w: 0, h: 0 };
        const c = Object.assign({}, win.ctx);
        if (win.face === "osd")
            c.under = win.theme.zoneFor(win.underFace, win.theme.geometryFor(win.underFace, win.ctx), win.ctx);
        return win.theme.zoneFor(win.face, win.targetGeom, c);
    }
    readonly property var strip: win.theme ? win.theme.stripRect(win.ctx) : ({ x: 0, y: 0, w: 0, h: 0 })
    // Navegação abaixo da tela aberta (alvo, como a zona).
    readonly property bool navOn: win.face === "screen" && win.inputOn && !!win.island && win.island.screen !== ""
    readonly property var navRect: win.theme && win.navOn ? win.theme.navRect(win.targetGeom, win.ctx) : ({ x: 0, y: 0, w: 0, h: 0 })
    readonly property bool inputOn: !!win.island && (win.island.barHidden ? win.face === "screen" : (win.inputAllowed || win.face === "screen"))
    readonly property bool stripOn: !!win.island && win.face !== "screen" && win.inputAllowed && win.drawsPill && !win.island.barHidden

    // Deslocamento do relógio no repouso (marca ao lado): restDx = dir·(markW/2 + 2).
    readonly property real restDxTarget: bar.restMarkW > 0 ? (win.theme ? win.theme.dir : 1) * (bar.restMarkW / 2 + 2) : 0

    // A marca está de fato na tela e tocável (porte do markLive da 1.x): um
    // HoverHandler que some pode não avisar a saída.
    readonly property bool markLive: win.face === "rest" && win.drawsPill && bar.restMarkW > 0
        && !!bar.restMark && bar.restMark.opacity > 0.5
    onMarkLiveChanged: if (!win.markLive) win.markHold = false

    // Aviso: ponteiro na zona segura o tempo.
    readonly property bool peekPointed: win.peekHere && win.pointerInside
    onPeekPointedChanged: if (win.island) win.island.peek.hold(win.peekPointed)

    // ---- Janela ----
    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: win.island ? win.island.devTop : 0
    implicitWidth: win.screenW
    implicitHeight: win.screenH - (win.island ? win.island.devTop : 0)
    color: "transparent"
    surfaceFormat.opaque: false
    visible: !win.island || win.island.devShown
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: !win.island || win.island.dev || win.island.barHidden ? 0 : win.island.barSize
    WlrLayershell.namespace: "omarchy-bar"
    // Top mantém o scanout direto da tela cheia; Overlay só com uma tela
    // aberta por cima de uma janela em tela cheia (e sempre no harness).
    WlrLayershell.layer: (win.island && win.island.dev) || win.layerOverlay ? WlrLayer.Overlay : WlrLayer.Top
    // OnDemand só com tela aberta aqui (nunca Exclusive: derruba o focus grab). No harness, nunca.
    WlrLayershell.keyboardFocus: win.face === "screen" && win.isActive && win.island && !win.island.dev ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        Region {
            x: win.inputOn ? win.zone.x : 0
            y: win.inputOn ? win.zone.y : 0
            width: win.inputOn ? win.zone.w : 0
            height: win.inputOn ? win.zone.h : 0
        }
        Region {
            x: win.strip.x
            y: 0
            width: win.stripOn ? win.strip.w : 0
            height: win.stripOn ? win.strip.h : 0
        }
        Region {
            x: win.navRect.x
            y: win.navRect.y
            width: win.navOn ? win.navRect.w : 0
            height: win.navOn ? win.navRect.h : 0
        }
    }

    HyprlandFocusGrab {
        windows: [win]
        active: win.face === "screen" && win.isActive && !!win.island && !win.island.dev
        onCleared: if (win.island) win.island.close()
    }

    // ---- Estado interno ----
    QtObject {
        id: priv
        property bool ready: false
        property string lastFace: "rest"
        property var motion: "hover"
        // Último alvo entregue à forma (só os campos que mudam são redirecionados).
        property var applied: null
        property bool inZone: false
        property bool inStrip: false
        property point kbAnchor: Qt.point(-1, -1)
        property string hit: ""
        // Seletor: o ponteiro passou por ele (sair fecha em 0,7 s; sem isso, 2,6 s).
        property bool pickerTouched: false
        // Tela entregue à pilha (G e payload novo).
        property string shownScreen: ""
        property var shownPayload: null
        // Opacidade da pílula: última barra escondida vista (duração do fade).
        property bool lastHidden: false
    }

    Morph {
        id: pill
        centerX: win.cx
        onSettled: if (win.restFadingOut && win.face === "rest") win.restFadingOut = false
    }

    // p do relógio: 0 = repouso / L1, 1 = L2. restDxSpring: a base do deslocamento.
    SpringValue { id: clockP; settlePos: 0.001; settleVel: 0.04 }   // progresso 0..1
    SpringValue { id: restDxSpring }

    // Fade de opacidade com atraso (regra "gen": um fade novo cancela o
    // anterior e parte da opacidade atual).
    component Fade: SequentialAnimation {
        id: fade
        property Item item: null
        property real value: 1
        property int wait: 0
        property int length: 0
        signal done()
        PauseAnimation {
            duration: fade.wait
        }
        NumberAnimation {
            target: fade.item
            property: "opacity"
            to: fade.value
            duration: fade.length
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: fade.done()
        }
    }

    function runFade(f, to, wait, length) {
        f.stop();
        if (!f.item)
            return;
        if (!win.theme || win.theme.reduceMotion || Math.abs(f.item.opacity - to) < 0.001) {
            f.item.opacity = to;
            f.done();
            return;
        }
        f.value = to;
        f.wait = Math.max(0, Math.round(wait));
        f.length = Math.max(0, Math.round(length));
        f.start();
    }

    Fade {
        id: clockFade
        item: clockLayer
        // Saiu de vez: p e dx vão ao repouso (F, I, P).
        onDone: {
            if (clockLayer.opacity < 0.01 && !win.clockWanted(win.face)) {
                clockP.snap(0);
                restDxSpring.snap(win.restDxTarget);
            }
        }
    }
    Fade {
        id: osdFade
        item: osdFace
    }
    Fade {
        id: peekFade
        item: peekFace
    }

    function clockWanted(f) {
        return f === "rest" || f === "hover1" || f === "hover2";
    }

    function motionFor(from, to) {
        if (to === "screen")
            return "panel";
        if (from === "hover2" && to === "rest")
            return "slow";
        return "hover";
    }

    function applyFace(from, to) {
        if (!win.island || !win.theme)
            return;
        const m = win.motionFor(from, to);
        priv.motion = m;
        const g = win.targetGeom;
        priv.applied = Object.assign({}, g);

        // ---- Forma ----
        if (m === "slow") {
            // E: w, h e cap vão no slow; o topo mergulha (22 no hover, depois 10 no slow em +50).
            pill.to({ w: g.w, h: g.h, cap: g.cap }, "slow");
            pill.topTo(Motion.FADE.DIP_TOP, "hover", 0);
            pill.topTo(g.top, "slow", Motion.FADE.DIP_DELAY);
        } else {
            pill.to(g, m);
        }

        // ---- Relógio: p e a base do deslocamento ----
        const hoverFaces = from === "rest" || from === "hover1" || from === "hover2";
        switch (to) {
        case "hover2":
            // C (do L1) e N (direto do repouso) andam; M (do aviso) e os outros pulam.
            if (hoverFaces) {
                clockP.go(1, "hover");
                restDxSpring.go(0, "hover");
            } else {
                clockP.snap(1);
                restDxSpring.snap(0);
            }
            break;
        case "hover1":
            if (hoverFaces) {
                clockP.go(0, "hover");
                restDxSpring.go(0, "hover");
            } else {
                clockP.snap(0);
                restDxSpring.snap(0);
            }
            break;
        case "rest":
            if (from === "hover2") {
                clockP.go(0, "slow");
                restDxSpring.go(win.restDxTarget, "slow");
            } else if (hoverFaces) {
                clockP.go(0, "hover");
                restDxSpring.go(win.restDxTarget, "hover");
            } else {
                clockP.snap(0);
                restDxSpring.snap(win.restDxTarget);
            }
            break;
        default:
            // tela, OSD, aviso, seletor: o relógio sai; p e dx no fim do fade.
            break;
        }

        // ---- Fades do relógio, do OSD e do aviso ----
        if (win.clockWanted(to)) {
            if (hoverFaces)
                win.runFade(clockFade, 1, 0, Motion.FADE.CLOCK_IN_AFTER.dur);
            else
                win.runFade(clockFade, 1, Motion.FADE.CLOCK_IN_AFTER.delay, Motion.FADE.CLOCK_IN_AFTER.dur);
        } else {
            win.runFade(clockFade, 0, 0, Motion.FADE.CONTENT_OUT.dur);
        }
        if (to === "osd")
            win.runFade(osdFade, 1, Motion.FADE.OSD_IN.delay, Motion.FADE.OSD_IN.dur);
        else if (from === "osd")
            win.runFade(osdFade, 0, 0, Motion.FADE.OSD_OUT.dur);
        if (to === "peek")
            win.runFade(peekFade, 1, Motion.FADE.PEEK_IN.delay, Motion.FADE.PEEK_IN.dur);
        else if (from === "peek")
            win.runFade(peekFade, 0, 0, Motion.FADE.PEEK_OUT);

        // ---- Telas ----
        if (to === "screen") {
            priv.shownScreen = win.island.screen;
            priv.shownPayload = win.island.screenPayload;
            keys.forceActiveFocus();   // um campo de busca da tela anterior não fica com o foco
            stack.show(win.island.screen, win.island.screenPayload, from);
        } else if (from === "screen") {
            stack.hide();
            priv.shownScreen = "";
            priv.shownPayload = null;
            win.panelH = 0;
        }

        // ---- Seletor ----
        if (to === "picker")
            priv.pickerTouched = win.pointerInside;

        if (to !== "rest")
            win.markHold = false;
        win.refreshHit();
        win.island.reportFace(win.output, to);
        win.hintOnFace(from, to);
    }

    // O ponteiro parado sobre a face nova: cursor e destaque do seletor certos
    // sem esperar o próximo movimento.
    function refreshHit() {
        const p = bar.pointer;
        const hit = win.pointerInside && win.face !== "screen" && p.x >= 0 ? bar.hitTest(p.x, p.y) : "";
        priv.hit = hit;
        if (bar.screenPicker)
            bar.screenPicker.setHover(win.face === "picker" && hit.indexOf("pick:") === 0 ? hit.slice(5) : "");
    }

    onFaceChanged: {
        const from = priv.lastFace;
        const to = win.face;
        // Antes de lastFace virar "rest": drawsPill não pisca para falso.
        // Com reduzir movimento a forma pula (sem settled): as duas janelas mudam na hora.
        if (to === "rest" && from !== "rest" && !!win.island && win.island.prefs.focusedOnly && !win.isFocused
                && !(win.theme && win.theme.reduceMotion)) {
            win.restFadingOut = true;
            fadeGuard.restart();
        }
        priv.lastFace = to;
        if (priv.ready)
            win.applyFace(from, to);
    }

    // Mudou o alvo sem mudar de face (largura do relógio, marca, aviso, OSD,
    // troca de tela): só os campos que mudaram vão, sem desfazer o mergulho do E.
    onTargetGeomChanged: {
        if (!priv.ready || win.face !== priv.lastFace)
            return;
        const g = win.targetGeom;
        const a = priv.applied || ({});
        const d = {};
        let any = false;
        for (const f of ["w", "h", "top", "cap"]) {
            // Nas telas a altura é do heightRequest (a Central usa o tween interno).
            if (f === "h" && win.face === "screen")
                continue;
            if (a[f] === undefined || Math.abs(g[f] - a[f]) > 0.01) {
                d[f] = g[f];
                any = true;
            }
        }
        priv.applied = Object.assign({}, a, g);
        if (any)
            pill.to(d, win.face === "screen" ? "panel" : "hover");
    }

    // R: a marca mudou no repouso; o relógio desliza para o novo lugar.
    onRestDxTargetChanged: {
        if (priv.ready && win.face === "rest")
            restDxSpring.go(win.restDxTarget, "hover");
    }

    // S: ganhou o foco com focusedOnly: a forma já nasce no repouso, só aparece.
    onIsFocusedChanged: {
        if (win.isFocused) {
            warmTimer.interval = Motion.TIMING.WARM_FOCUS_MS;
            warmTimer.restart();
            if (priv.ready && !!win.island && win.island.prefs.focusedOnly && win.face === "rest") {
                win.restFadingOut = false;
                pill.snap(win.targetGeom);
                priv.applied = Object.assign({}, win.targetGeom);
                clockP.snap(0);
                restDxSpring.snap(win.restDxTarget);
                clockFade.stop();
                clockLayer.opacity = 1;
            }
        }
    }

    // A tela mudou com a face já em "screen" (G) ou chegou payload novo.
    // Adiado: o open() muda payload e tela em passos; aqui já está tudo certo.
    function syncScreen() {
        if (!win.island || win.face !== "screen" || priv.lastFace !== "screen" || win.island.screen === "")
            return;
        if (win.island.screen !== priv.shownScreen) {
            priv.shownScreen = win.island.screen;
            priv.shownPayload = win.island.screenPayload;
            win.panelH = 0;
            keys.forceActiveFocus();   // um campo de busca da tela anterior não fica com o foco
            stack.show(win.island.screen, win.island.screenPayload, "screen");
            const g = win.targetGeom;
            priv.applied = Object.assign({}, g);
            pill.to(g, "panel");
        } else if (win.island.screenPayload !== priv.shownPayload) {
            priv.shownPayload = win.island.screenPayload;
            keys.forceActiveFocus();   // um campo de busca da tela anterior não fica com o foco
            stack.show(win.island.screen, win.island.screenPayload, "screen");
        }
    }

    Connections {
        target: win.island
        function onScreenChanged() {
            Qt.callLater(win.syncScreen);
        }
        function onScreenPayloadChanged() {
            Qt.callLater(win.syncScreen);
        }
        function onKeyboardModeChanged() {
            if (win.island.keyboardMode)
                priv.kbAnchor = Qt.point(-1, -1);
        }
    }

    Component.onCompleted: {
        priv.lastFace = win.face;
        priv.lastHidden = !!win.island && win.island.barHidden;
        pill.snap(win.targetGeom);
        priv.applied = Object.assign({}, win.targetGeom);
        clockP.snap(win.face === "hover2" ? 1 : 0);
        restDxSpring.snap(win.face === "rest" ? win.restDxTarget : 0);
        clockLayer.opacity = win.clockWanted(win.face) ? 1 : 0;
        osdFace.opacity = win.face === "osd" ? 1 : 0;
        peekFace.opacity = win.face === "peek" ? 1 : 0;
        surface.opacity = surface.pillLevel;
        priv.ready = true;
        if (win.island) {
            win.island.registerWindow(win.output, win);
            win.island.reportFace(win.output, win.face);
        }
        warmTimer.interval = Motion.TIMING.WARM_START_MS;
        warmTimer.restart();
    }
    Component.onDestruction: {
        if (win.island) {
            if (win.peekPointed)
                win.island.peek.hold(false);
            win.island.unregisterWindow(win.output, win);
        }
    }

    function debugState() {
        const r = v => Math.round(v * 10) / 10;
        return {
            face: win.face,
            nav: { on: win.navOn, rect: win.navRect, opacity: r(nav.opacity), y: r(nav.y), canBack: nav.canBack },
            drawsPill: win.drawsPill,
            isFocused: win.isFocused,
            restFadingOut: win.restFadingOut,
            hovered: win.hovered,
            pointerInside: win.pointerInside,
            markHold: win.markHold,
            pickerHere: win.pickerHere,
            peekHere: win.peekHere,
            layerOverlay: win.layerOverlay,
            visible: win.visible,
            opacity: r(surface.opacity),
            morph: { w: r(pill.w), h: r(pill.h), top: r(pill.top), cap: r(pill.cap), moving: pill.moving },
            target: win.targetGeom,
            zone: win.inputOn ? win.zone : null,
            strip: win.stripOn ? win.strip : null,
            wheel: wheelBand.width > 0 ? { x: wheelBand.x, y: wheelBand.y, w: wheelBand.width, h: wheelBand.height } : null,
            clock: { text: clock.text, width: clock.naturalWidth, opacity: r(clockLayer.opacity), p: r(clockP.value), restDx: r(restDxSpring.value), dx: r(clockLayer.dx) },
            osdOpacity: r(osdFace.opacity),
            peekOpacity: r(peekFace.opacity),
            markW: bar.restMarkW,
            hint: hint.shown,
            panelH: win.panelH,
            stack: { screen: priv.shownScreen, ready: stack.ready }
        };
    }

    // Nível de hover pedido por código (0 / 1 / 2).
    function setLevel(n) {
        if (!win.island)
            return;
        if (n >= 2) {
            win.island.setExpanded(win.output, true);
        } else {
            win.island.setExpanded(win.output, false);
            win.island.hoverOutput = n === 1 ? win.output : "";
        }
    }

    // ---- Ponteiro ----
    // Um caminho só para os dois HoverHandlers (zona e faixa de cima). A
    // ordem importa: markHold e a folga da saída mudam ANTES das bandeiras
    // de dentro/fora, senão a face passaria um instante pelo L1 (e a marca
    // piscaria) ao entrar em cima da marca.
    function trackPointer() {
        const inZone = zoneHover.hovered;
        const inStrip = stripHover.hovered;
        let p = Qt.point(-1, -1);
        if (inZone)
            p = Qt.point(zoneItem.x + zoneHover.point.position.x, zoneItem.y + zoneHover.point.position.y);
        else if (inStrip)
            p = Qt.point(stripItem.x + stripHover.point.position.x, stripItem.y + stripHover.point.position.y);
        const inside = inZone || inStrip;

        if (!inside) {
            win.markHold = false;
        } else if (win.face === "rest" || win.markHold) {
            const r = bar.markRect;
            win.markHold = win.markLive && r.width > 0 && p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height;
        }

        // Mais de 8 px de ponteiro: sai do modo teclado.
        if (inside && win.island && win.island.keyboardMode) {
            if (priv.kbAnchor.x < 0)
                priv.kbAnchor = p;
            else if (Math.abs(p.x - priv.kbAnchor.x) + Math.abs(p.y - priv.kbAnchor.y) > Motion.TIMING.KEYBOARD_MOVE_PX) {
                win.island.keyboardMode = false;
                priv.kbAnchor = Qt.point(-1, -1);
            }
        }

        bar.pointer = p;
        const hit = inside && win.face !== "screen" ? bar.hitTest(p.x, p.y) : "";
        priv.hit = hit;
        if (bar.screenPicker)
            bar.screenPicker.setHover(win.face === "picker" && hit.indexOf("pick:") === 0 ? hit.slice(5) : "");

        const was = win.pointerInside;
        if (was && !inside)
            grace.restart();
        priv.inZone = inZone;
        priv.inStrip = inStrip;
        if (inside)
            grace.stop();
        if (win.face === "picker" && inside)
            priv.pickerTouched = true;
    }

    // ---- Temporizadores de comportamento ----
    Timer {
        id: grace
        interval: Motion.TIMING.LEAVE_GRACE_MS
    }

    // L2 com o ponteiro fora por 2,5 s: volta ao repouso.
    Timer {
        interval: Motion.TIMING.L2_COLLAPSE_MS
        running: win.face === "hover2" && !win.pointerInside && !!win.island && win.island.hoverOutput !== win.output
        onTriggered: if (win.island) win.island.setExpanded(win.output, false)
    }

    // Seletor: some sozinho (2,6 s sem ponteiro; 0,7 s depois que o ponteiro sai).
    Timer {
        id: pickerClose
        interval: priv.pickerTouched ? Motion.TIMING.PICKER_LEAVE_MS : Motion.TIMING.PICKER_IDLE_MS
        running: win.face === "picker" && !win.pointerInside
        onTriggered: if (win.island && win.face === "picker") win.island.closePicker()
    }

    // focusedOnly: a forma terminou de encolher (ou passou do tempo): agora some.
    Timer {
        id: fadeGuard
        interval: 600
        onTriggered: win.restFadingOut = false
    }

    // Pré-aquecimento das telas no monitor focado; solta depois de 60 s sem foco.
    Timer {
        id: warmTimer
        onTriggered: if (win.isFocused) stack.warm()
    }
    Timer {
        interval: Motion.TIMING.RELEASE_MS
        running: !win.isFocused && !win.screenHere
        onTriggered: stack.release()
    }

    // `ilha run <tela> <tecla>`: a tecla vai quando a tela estiver pronta.
    Timer {
        interval: 40
        repeat: true
        running: win.screenHere && !!win.island && win.island.runPending
        onTriggered: {
            if (!stack.ready)
                return;
            const e = win.island.takePendingRun(win.island.screen);
            if (e)
                keys.dispatchKey(e);
        }
    }

    // ---- Desenho ----
    Item {
        id: surface
        anchors.fill: parent
        LayoutMirroring.enabled: !!win.island && win.island.rtl
        LayoutMirroring.childrenInherit: true

        // Opacidade da pílula: barra escondida (só telas aparecem) e focusedOnly.
        readonly property real pillLevel: !win.island ? 1
            : win.island.barHidden ? (win.face === "screen" ? 1 : 0)
            : (win.drawsPill ? 1 : 0)
        onPillLevelChanged: {
            if (!priv.ready)
                return;
            const hidden = !!win.island && win.island.barHidden;
            let d = Motion.FADE.FOCUS_FADE;
            if (hidden !== priv.lastHidden)
                d = Motion.FADE.HIDDEN_REST;
            else if (hidden)
                d = surface.pillLevel > 0.5 ? Motion.FADE.HIDDEN_SCREEN_IN : Motion.FADE.HIDDEN_SCREEN_OUT;
            priv.lastHidden = hidden;
            pillFade.stop();
            pillFade.to = surface.pillLevel;
            pillFade.duration = win.theme ? win.theme.dur(d) : 0;
            pillFade.start();
        }
        NumberAnimation {
            id: pillFade
            target: surface
            property: "opacity"
            easing.type: Easing.OutCubic
        }

        // ---- Zona de hover e toque (abaixo do conteúdo) ----
        Item {
            id: zoneItem
            x: win.zone.x
            y: win.zone.y
            width: win.inputOn ? win.zone.w : 0
            height: win.inputOn ? win.zone.h : 0

            HoverHandler {
                id: zoneHover
                cursorShape: win.face === "peek" || win.face === "osd" || win.markHold
                    || (priv.hit !== "" && priv.hit !== "pick:") ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPointChanged: win.trackPointer()
                onHoveredChanged: win.trackPointer()
            }

            TapHandler {
                id: tap
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                longPressThreshold: Motion.TIMING.LONG_PRESS_MS / 1000
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: (eventPoint, button) => {
                    const p = Qt.point(zoneItem.x + eventPoint.position.x, zoneItem.y + eventPoint.position.y);
                    if (button === Qt.RightButton)
                        win.secondary();
                    else
                        win.primary(p);
                }
                onLongPressed: win.secondary()
            }
            // Botão "voltar" do mouse sobre a tela aberta.
            TapHandler {
                acceptedButtons: Qt.BackButton
                enabled: win.face === "screen"
                onTapped: win.navBack()
            }
        }

        // Faixa invisível de 3 px na borda de cima: só abre o L1 (§8.1).
        Item {
            id: stripItem
            x: win.strip.x
            y: 0
            width: win.stripOn ? win.strip.w : 0
            height: win.stripOn ? win.strip.h : 0
            HoverHandler {
                id: stripHover
                onPointChanged: win.trackPointer()
                onHoveredChanged: win.trackPointer()
            }
        }

        // ---- Sombra e forma ----
        RectangularShadow {
            readonly property var sh: win.theme ? win.theme.shadowFor(pill.h) : ({ alpha: 0.5, blur: 30, dy: 5 })
            x: shape.x
            y: shape.y
            width: shape.width
            height: shape.height
            radius: shape.radius
            blur: sh.blur
            offset.y: sh.dy
            spread: 0
            color: Qt.rgba(0, 0, 0, sh.alpha)
        }

        Rectangle {
            id: shape
            x: pill.left
            y: pill.top
            width: Math.max(0, pill.w)
            height: Math.max(0, pill.h)
            radius: pill.radius
            antialiasing: true
            color: win.theme ? win.theme.surface : "black"
            border.width: 1
            border.color: win.theme ? win.theme.rim : "transparent"
        }

        // ---- Conteúdo, recortado com folga dos cantos (regra 5) ----
        Item {
            id: clipBox
            x: pill.left + pill.inset
            y: pill.top + pill.inset
            width: Math.max(0, pill.w - 2 * pill.inset)
            height: Math.max(0, pill.h - 2 * pill.inset)
            clip: true

            // Camada em coordenadas da janela.
            Item {
                id: content
                x: -clipBox.x
                y: -clipBox.y
                width: win.width
                height: win.height

                HoverBar {
                    id: bar
                    anchors.fill: parent
                    island: win.island
                    theme: win.theme
                    strings: win.island ? win.island.strings : null
                    morph: pill
                    output: win.output
                    level: win.hoverLevel
                    face: win.face
                    motion: priv.motion
                    statusPin: win.island && win.island.expandedOutput === win.output ? win.island.expandedPin : ""
                    markHovered: win.markHold
                    pressed: tap.pressed
                    clockLeft: win.cx + win.restDxTarget - clock.naturalWidth / 2
                    clockRight: win.cx + win.restDxTarget + clock.naturalWidth / 2
                    onExpand: if (win.island) win.island.setExpanded(win.output, true)
                    onCollapse: if (win.island) win.island.setExpanded(win.output, false)
                    onOpenScreen: (id, payload) => {
                        if (win.island)
                            win.island.open(id, win.output, payload);
                    }
                }

                // O relógio único (repouso, L1, L2).
                Item {
                    id: clockLayer
                    readonly property real dx: Motion.lerp(restDxSpring.value, bar.l2ClockDx, clockP.value)
                    x: win.cx + clockLayer.dx - clock.width / 2
                    y: pill.centerY - clock.height / 2
                    width: clock.width
                    height: clock.height
                    opacity: 1

                    HeroClock {
                        id: clock
                        theme: win.theme
                        now: win.island ? win.island.now : new Date()
                        twelveHour: !!win.island && win.island.clock12
                        scale: Motion.lerp(1, win.theme ? win.theme.px.L2_CLOCK_SCALE : 1.375, clockP.value)
                    }
                }

                OsdFace {
                    id: osdFace
                    theme: win.theme
                    strings: win.island ? win.island.strings : null
                    payload: win.island ? win.island.osd.payload : null
                    x: win.cx - width / 2
                    y: pill.centerY - height / 2
                    width: implicitWidth
                    height: implicitHeight
                    opacity: 0
                    visible: opacity > 0
                }

                PeekFace {
                    id: peekFace
                    theme: win.theme
                    strings: win.island ? win.island.strings : null
                    payload: win.island ? win.island.peek.payload : null
                    rtl: !!win.island && win.island.rtl
                    screenW: win.screenW
                    x: win.cx - width / 2
                    y: pill.centerY - height / 2
                    width: implicitWidth
                    height: implicitHeight
                    opacity: 0
                    visible: opacity > 0
                }

                ScreenStack {
                    id: stack
                    anchors.fill: parent
                    island: win.island
                    theme: win.theme
                    strings: win.island ? win.island.strings : null
                    morph: pill
                    window: win
                    active: win.screenHere
                    screenId: win.island ? win.island.screen : ""
                    payload: win.island ? win.island.screenPayload : null
                    keyboardMode: !!win.island && win.island.keyboardMode
                    onHeightRequest: (h, motion) => {
                        win.panelH = h;
                        if (win.face === "screen" && priv.lastFace === "screen" && win.theme)
                            pill.heightTo(Math.min(h, win.theme.maxPanelH(win.screenH)), motion);
                    }
                }
            }
        }

        // Faixa da roda sobre a tela aberta (§8.2): y 0..24, fora do recorte
        // (a parte de cima do painel não recebe nada recortada). Só roda; não
        // bloqueia toque.
        Item {
            id: wheelBand
            readonly property var band: win.theme ? win.theme.wheelBand(win.targetGeom, win.ctx) : ({ x: 0, y: 0, w: 0, h: 0 })
            x: band.x
            y: band.y
            width: win.face === "screen" ? band.w : 0
            height: win.face === "screen" ? band.h : 0
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (win.island && win.face === "screen")
                        win.island.wheelStep(event.angleDelta.y);
                }
            }
        }

        // Dica da linha: fora do recorte e da máscara (a entrada passa por ela).
        LineHint {
            id: hint
            theme: win.theme
            strings: win.island ? win.island.strings : null
            glassy: !!win.island && win.island.glassy
            cx: win.cx
            topY: (win.theme ? win.theme.px.L1_TOP + win.theme.px.L1_H + win.theme.px.HINT_GAP : 72)
            screenW: win.screenW
        }

        // Navegação: Voltar e as seis telas, presa à borda de baixo do painel.
        ScreenNav {
            id: nav
            theme: win.theme
            strings: win.island ? win.island.strings : null
            glassy: !!win.island && win.island.glassy
            rtl: !!win.island && win.island.rtl
            shown: win.navOn
            cx: win.cx
            topY: pill.top + pill.h + (win.theme ? win.theme.px.NAV_GAP : 8)
            current: win.island ? win.island.screen : ""
            canBack: !!win.island && win.island.canGoBack
            onBack: win.navBack()
            onPick: id => {
                if (win.island && id !== win.island.screen)
                    win.island.open(id, win.output);
            }
        }
    }

    // ---- Dica da linha (§7): primeira face hover1 da sessão ----
    function hintOnFace(from, to) {
        if (from === "hover1" && to !== "hover1") {
            hintDelay.stop();
            hintTimer.stop();
            // fast antes de shown: a duração certa vale no quadro da troca.
            hint.fast = to !== "rest";
            hint.shown = false;
        }
        if (to === "hover1" && win.island && !win.island.lineHintSeen && !win.island.barHidden && !win.island.restartNoticeShowing)
            hintDelay.restart();
    }
    Timer {
        id: hintDelay
        interval: Motion.FADE.HINT_IN.delay
        onTriggered: {
            if (win.face !== "hover1" || !win.island || win.island.lineHintSeen || win.island.barHidden || win.island.restartNoticeShowing)
                return;
            hint.fast = false;
            hint.shown = true;
            hintTimer.restart();
            Qt.callLater(() => {
                if (win.island)
                    win.island.lineHintSeen = true;
            });
        }
    }
    Timer {
        id: hintTimer
        interval: Motion.TIMING.HINT_MS
        onTriggered: {
            hint.fast = false;
            hint.shown = false;
        }
    }

    // ---- Toque (amendments §3) ----
    function primary(p) {
        if (!win.island)
            return;
        switch (win.face) {
        case "peek":
            win.island.peek.tap();
            return;
        case "osd":
            win.osdTap();
            return;
        case "screen":
            return;
        case "rest": {
            const hit = bar.hitTest(p.x, p.y);
            if (hit !== "")
                bar.activate(hit);
            else
                win.island.setExpanded(win.output, true);
            return;
        }
        default:
            bar.activate(bar.hitTest(p.x, p.y));
        }
    }

    function secondary() {
        if (!win.island)
            return;
        switch (win.face) {
        case "rest":
        case "hover1":
        case "hover2":
            win.island.openPicker(win.output);
            return;
        case "picker":
            win.island.closePicker();
            return;
        case "peek":
            win.island.peek.dismiss();
            return;
        default:
            return;
        }
    }

    // Toque no OSD (screens §4): o OsdBridge decide. Volume -> Central/Som;
    // brilho -> Central/Tela; mídia -> Mídia; aviso de reinício -> reinicia o
    // shell; contagem da resolução -> mantém; o resto dispensa.
    function osdTap() {
        if (!win.island.osd.activate(win.output))
            win.island.osd.hide();
    }

    // ---- Teclado ----
    // Teclas globais de qualquer tela: Ctrl+Tab / Ctrl+Shift+Tab, Alt+1..6
    // (SCREEN_ORDER) e a cadeia do Esc (handleEscape da tela, depois fecha).
    function globalKey(event) {
        if (!win.island || win.face !== "screen")
            return false;
        const k = event.key;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier);
        if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && (mods & Qt.ControlModifier)) {
            win.island.cycle(k === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1);
            return true;
        }
        if (k === Qt.Key_Left && mods === Qt.AltModifier) {
            if (!event.isAutoRepeat)
                win.navBack();
            return true;
        }
        if (k >= Qt.Key_1 && k <= Qt.Key_6 && mods === Qt.AltModifier) {
            if (!event.isAutoRepeat)
                win.altScreen(k - Qt.Key_1);
            return true;
        }
        if (k === Qt.Key_Escape) {
            if (stack.handleEscape())
                return true;
            win.island.close();
            return true;
        }
        return false;
    }

    // Voltar: a subpágina da Central fecha antes; depois, a tela anterior;
    // sem histórico, fecha.
    function navBack() {
        if (!win.island || win.face !== "screen")
            return false;
        if (stack.handleBack())
            return true;
        return win.island.back();
    }

    function altScreen(i) {
        if (!win.island || !win.theme)
            return;
        const id = win.theme.px.SCREEN_ORDER[i];
        if (id)
            win.island.open(id, win.output);
    }

    FocusScope {
        id: keys
        anchors.fill: parent
        focus: win.face === "screen"

        function dispatchKey(event) {
            const k = event.key;
            if (k === Qt.Key_Shift || k === Qt.Key_Control || k === Qt.Key_Meta || k === Qt.Key_Alt || k === Qt.Key_AltGr
                    || k === Qt.Key_Super_L || k === Qt.Key_Super_R)
                return false;
            if (win.island)
                win.island.keyboardMode = true;
            if (stack.handleKey(event))
                return true;
            return win.globalKey(event);
        }

        Keys.onPressed: event => {
            if (keys.dispatchKey(event))
                event.accepted = true;
        }

        // Duplicatas em Shortcut: passam na frente de um campo de texto com foco.
        Shortcut {
            sequences: ["Ctrl+Tab"]
            enabled: win.face === "screen"
            autoRepeat: true
            onActivated: if (win.island) win.island.cycle(1)
        }
        Shortcut {
            sequences: ["Ctrl+Shift+Tab", "Ctrl+Shift+Backtab", "Ctrl+Backtab"]
            enabled: win.face === "screen"
            autoRepeat: true
            onActivated: if (win.island) win.island.cycle(-1)
        }
        Shortcut {
            sequence: "Alt+Left"
            enabled: win.face === "screen"
            autoRepeat: false
            onActivated: win.navBack()
        }
        Shortcut {
            sequence: "Alt+1"
            enabled: win.face === "screen"
            autoRepeat: false
            onActivated: win.altScreen(0)
        }
        Shortcut {
            sequence: "Alt+2"
            enabled: win.face === "screen"
            autoRepeat: false
            onActivated: win.altScreen(1)
        }
        Shortcut {
            sequence: "Alt+3"
            enabled: win.face === "screen"
            autoRepeat: false
            onActivated: win.altScreen(2)
        }
        Shortcut {
            sequence: "Alt+4"
            enabled: win.face === "screen"
            autoRepeat: false
            onActivated: win.altScreen(3)
        }
        Shortcut {
            sequence: "Alt+5"
            enabled: win.face === "screen"
            autoRepeat: false
            onActivated: win.altScreen(4)
        }
        Shortcut {
            sequence: "Alt+6"
            enabled: win.face === "screen"
            autoRepeat: false
            onActivated: win.altScreen(5)
        }
    }
}
