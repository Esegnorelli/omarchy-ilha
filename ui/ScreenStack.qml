pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "Motion.js" as Motion

// As telas da ilha (Central, Apps, Energia, Temas, Papéis, Mídia) numa
// janela: um Loader por id, assíncrono, criado com as propriedades iniciais
// (setSource(url, props)), para nenhuma ligação ler `theme` nulo. Fica
// dentro do recorte do conteúdo (coordenadas da janela).
//
// Contrato de tela (todo arquivo de tela; files "SCREEN CONTRACT" + Phase 0):
//   in  island, theme, strings, current (bool), keyboardMode (bool), payload,
//       morph (o Morph da janela), edgeLeft / edgeRight (bordas vivas da
//       forma no sistema da PRÓPRIA tela: só camadas de cabeçalho ligam x nelas)
//   implicitWidth / implicitHeight = tamanho da ilha; heightMotion (var,
//   padrão "panel"); snapping (bool)
//   headerItems / bodyItems (list<Item>; vazio = um fade só)
//   opened(payload), closed(), handleKey(event) -> bool, handleEscape() -> bool
//   signals navigate(string id, var payload), closeRequested()
//   Nada roda (timers, varreduras, sondagens) antes de opened() nem depois de closed().
//
// Choreografias do conteúdo (motion F, G, H; a forma é da IslandWindow):
// - F (pílula -> tela): a tela já está no tamanho final, em x = cx − w/2,
//   y = 10, recortada pela forma, nunca escalada. A entrada vale desde o T0.
//   - Um fade só (Central, Energia, Mídia): 0 -> 1 em 130 ms a partir de
//     max(T0 + 16, pronto), desfoque 8 -> 0.
//   - Duas camadas (Apps, Temas, Papéis): cabeçalho 0 -> 1 em 60 ms a partir
//     de T0 + 16, sem desfoque; corpo 0 -> 1 em 100 ms depois de 70 ms,
//     desfoque 8 -> 0.
// - G (tela A -> tela B): A desliga no T0 e sai em 50 ms com desfoque 0 -> 6
//   (fica em cache, invisível); B entra como em F, mas o fade único começa
//   em 30 ms (o corpo em 70).
// - H (tela -> repouso / L1): sai em 60 ms com desfoque 0 -> 6; closed() só
//   depois do fade.
// - O desfoque usa MultiEffect (blurMax 16) numa camada ligada só enquanto
//   há desfoque; fora dos fades nenhuma tela tem camada.
// - Todo fade parte da opacidade atual (reabrir no meio da saída não pisca).
// - Reduzir movimento: tudo pula, sem desfoque.
//
// Pré-aquecimento: warm() cria todas as telas escondidas e inertes (a
// IslandWindow chama no monitor focado, 1,5 s depois do início e 400 ms
// depois de trocar o foco); release() solta as que não estão abertas (60 s
// sem foco). Telas em cache: invisíveis, desligadas, sem foco.
Item {
    id: root

    property var island: null
    property Theme theme: null
    property var strings: null
    property var morph: null
    property var window: null
    // Esta janela é a que mostra a tela agora.
    property bool active: false
    property string screenId: ""
    property var payload: null
    property bool keyboardMode: false

    // A tela aberta (depois de opened(); nula durante a saída).
    readonly property var current: priv.loader && priv.loader.presented && priv.loader.phase !== "out" ? priv.loader.item : null
    readonly property bool ready: root.current !== null

    // A tela pediu outra altura: a janela guarda e chama morph.heightTo.
    // Na abertura vem com "panel" (a mesma mola da forma); depois, com o
    // heightMotion da própria tela (a Central usa Motion.INNER).
    signal heightRequest(real h, var motion)

    readonly property var ids: ["control", "launcher", "power", "themes", "media"]

    function loaderFor(id) {
        const i = root.ids.indexOf(String(id || ""));
        return i >= 0 ? loaders.itemAt(i) : null;
    }

    // Pré-instancia todas as telas, escondidas e inertes.
    function warm() {
        if (!root.island)
            return;
        for (let i = 0; i < root.ids.length; i++) {
            const l = loaders.itemAt(i);
            if (l)
                l.ensure();
        }
    }

    // Solta as telas que não estão abertas nem saindo.
    function release() {
        for (let i = 0; i < root.ids.length; i++) {
            const l = loaders.itemAt(i);
            if (l && l !== priv.loader && l.phase === "hidden")
                l.drop();
        }
    }

    // fromFace "screen" = troca de tela (G); qualquer outra = abertura (F).
    function show(id, payload, fromFace) {
        const l = root.loaderFor(id);
        if (!l || !root.island)
            return false;
        const p = payload || ({});
        const t0 = Date.now();
        // Mesma tela já aberta, payload novo (ex.: `ilha open sound` com a
        // Central aberta): fecha e abre de novo no lugar, sem fade.
        if (priv.loader === l && l.presented && l.phase !== "out") {
            l.reopen(p);
            return true;
        }
        const swap = fromFace === "screen" && priv.loader !== null && priv.loader !== l;
        if (priv.loader && priv.loader !== l)
            priv.loader.conceal(swap ? "swap" : "out");
        // Reabrir no meio da própria saída: volta do ponto em que está (regra 7),
        // sem piscar nem passar por closed()/opened() se o payload é o mesmo.
        if (l.phase === "out" && l.presented && l.screen) {
            priv.loader = l;
            l.swapIn = swap;
            l.t0 = t0;
            l.resume(p);
            return true;
        }
        if (l.phase === "out")
            l.finishOut();
        priv.loader = l;
        l.swapIn = swap;
        l.t0 = t0;
        l.pendingPayload = p;
        l.ensure();
        l.reveal();
        return true;
    }

    function hide() {
        if (priv.loader)
            priv.loader.conceal("out");
        priv.loader = null;
    }

    function handleKey(event) {
        const c = root.current;
        return !!c && typeof c.handleKey === "function" && c.handleKey(event) === true;
    }

    function handleEscape() {
        const c = root.current;
        return !!c && typeof c.handleEscape === "function" && c.handleEscape() === true;
    }

    // Voltar dentro da tela (subpágina da Central). false = a tela não tem
    // para onde voltar e a navegação vai para a tela anterior.
    function handleBack() {
        const c = root.current;
        return !!c && typeof c.handleBack === "function" && c.handleBack() === true;
    }

    // Teclas que sobem de dentro da tela (um campo com foco) sem ninguém
    // aceitar: só as globais (Ctrl+Tab, Alt+n, Esc). A tela já viu a tecla.
    Keys.onPressed: event => {
        if (root.window && typeof root.window.globalKey === "function" && root.window.globalKey(event))
            event.accepted = true;
    }

    QtObject {
        id: priv
        property var loader: null
    }

    Repeater {
        id: loaders
        model: root.ids

        Loader {
            id: loader

            required property string modelData
            readonly property string screenKey: loader.modelData
            property var pendingPayload: null
            property bool wantShown: false
            // opened() chamado e closed() ainda não.
            property bool presented: false
            // hidden | in | shown | out
            property string phase: "hidden"
            property bool swapIn: false
            property real t0: 0
            // Desfoque da tela inteira (px) e as duas camadas.
            property real fxBlur: 0
            property real headerOp: 1
            property real bodyOp: 1
            property real bodyBlur: 0
            // Itens do corpo que ganharam camada de desfoque nossa.
            property var fxItems: []
            readonly property bool reduce: !root.theme || root.theme.reduceMotion
            // A tela carregada, sem tipo (os membros do contrato são duck-typed).
            readonly property var screen: loader.item

            asynchronous: true
            enabled: loader.phase === "in" || loader.phase === "shown"
            visible: loader.phase !== "hidden"
            opacity: 0
            focus: false
            x: root.morph ? root.morph.centerX - loader.width / 2 : 0
            y: root.theme ? root.theme.px.TOP : 10

            layer.enabled: loader.visible && loader.fxBlur > 0.05
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 16
                blur: Math.min(1, loader.fxBlur / 16)
            }

            // Desfoque de um item do corpo (camada ligada pela pilha).
            Component {
                id: bodyFx
                MultiEffect {
                    blurEnabled: true
                    blurMax: 16
                    blur: Math.min(1, loader.bodyBlur / 16)
                }
            }

            function itemsOf(name) {
                const it = loader.screen;
                const list = it ? it[name] : null;
                const out = [];
                if (list) {
                    for (let i = 0; i < list.length; i++) {
                        if (list[i])
                            out.push(list[i]);
                    }
                }
                return out;
            }

            function ensure() {
                if (loader.item || loader.status === Loader.Loading || !root.island)
                    return;
                const url = root.island.screenUrls[loader.screenKey];
                if (!url)
                    return;
                loader.setSource(url, {
                    island: root.island,
                    theme: root.theme,
                    strings: root.strings,
                    morph: root.morph,
                    keyboardMode: root.keyboardMode,
                    current: false
                });
            }

            function drop() {
                loader.wantShown = false;
                loader.stopAll();
                loader.phase = "hidden";
                loader.presented = false;
                loader.source = "";
            }

            function reveal() {
                loader.wantShown = true;
                if (loader.status === Loader.Ready && loader.item)
                    loader.present();
            }

            function present() {
                const it = loader.screen;
                if (!it || !loader.wantShown)
                    return;
                loader.wantShown = false;
                it.payload = loader.pendingPayload;
                if (typeof it.opened === "function")
                    it.opened(loader.pendingPayload);
                it.current = true;
                loader.presented = true;
                loader.phase = "in";
                root.heightRequest(it.implicitHeight, "panel");
                loader.startIn();
            }

            // Mesma tela, payload novo.
            function reopen(p) {
                const it = loader.screen;
                if (!it)
                    return;
                if (typeof it.closed === "function")
                    it.closed();
                it.payload = p;
                if (typeof it.opened === "function")
                    it.opened(p);
                it.current = true;
                root.heightRequest(it.implicitHeight, "panel");
            }

            function stopAll() {
                inSingle.stop();
                inLayered.stop();
                outAnim.stop();
            }

            // Ms que ainda faltam de um atraso contado do T0.
            function wait(delay) {
                return Math.max(0, delay - (Date.now() - loader.t0));
            }

            function startIn() {
                loader.stopAll();
                const headers = loader.itemsOf("headerItems");
                const bodies = loader.itemsOf("bodyItems");
                if (loader.reduce) {
                    loader.unbindLayers();
                    loader.opacity = 1;
                    loader.fxBlur = 0;
                    loader.phase = "shown";
                    return;
                }
                // Reaberta no meio da saída, ou uma tela de fade único.
                const midway = loader.opacity > 0.01;
                if (midway || headers.length + bodies.length === 0) {
                    const spec = loader.swapIn ? Motion.FADE.SWAP_IN : Motion.FADE.SCREEN_IN;
                    if (!midway)
                        loader.fxBlur = spec.blur;
                    inPause.duration = loader.wait(spec.delay);
                    inOpacity.duration = spec.dur;
                    inBlur.duration = spec.dur;
                    inSingle.start();
                    return;
                }
                // Duas camadas: a pilha opaca, cabeçalho e corpo do zero.
                loader.headerOp = 0;
                loader.bodyOp = 0;
                const bodySpec = loader.swapIn ? Motion.FADE.SWAP_BODY_IN : Motion.FADE.BODY_IN;
                loader.bodyBlur = bodySpec.blur;
                loader.bindLayers(headers, bodies);
                loader.fxBlur = 0;
                loader.opacity = 1;
                headerPause.duration = loader.wait(Motion.FADE.HEADER_IN.delay);
                headerFade.duration = Motion.FADE.HEADER_IN.dur;
                bodyPause.duration = loader.wait(bodySpec.delay);
                bodyFade.duration = bodySpec.dur;
                bodyUnblur.duration = bodySpec.dur;
                inLayered.start();
            }

            function bindLayers(headers, bodies) {
                const fx = [];
                for (const h of headers)
                    h.opacity = Qt.binding(() => loader.headerOp);
                for (const b of bodies) {
                    b.opacity = Qt.binding(() => loader.bodyOp);
                    // Só põe camada em quem não tem uma própria.
                    if (b.layer && !b.layer.enabled && !b.layer.effect) {
                        b.layer.effect = bodyFx;
                        b.layer.enabled = Qt.binding(() => loader.bodyBlur > 0.05);
                        fx.push(b);
                    }
                }
                loader.fxItems = fx;
            }

            function unbindLayers() {
                for (const h of loader.itemsOf("headerItems"))
                    h.opacity = 1;
                for (const b of loader.itemsOf("bodyItems"))
                    b.opacity = 1;
                for (const f of loader.fxItems) {
                    if (f && f.layer) {
                        f.layer.enabled = false;
                        f.layer.effect = null;
                    }
                }
                loader.fxItems = [];
                loader.headerOp = 1;
                loader.bodyOp = 1;
                loader.bodyBlur = 0;
            }

            // mode "swap" (G, 50 ms) ou "out" (H, 60 ms).
            function conceal(mode) {
                loader.wantShown = false;
                if (loader.phase === "hidden" || loader.phase === "out")
                    return;
                const it = loader.screen;
                if (it)
                    it.current = false;
                loader.phase = "out";
                inSingle.stop();
                inLayered.stop();
                if (loader.reduce) {
                    loader.opacity = 0;
                    loader.finishOut();
                    return;
                }
                const spec = mode === "swap" ? Motion.FADE.SWAP_OUT : Motion.FADE.SCREEN_OUT;
                outOpacity.duration = spec.dur;
                outBlur.duration = spec.dur;
                outBlur.to = spec.blur;
                outAnim.start();
            }

            // Reaberta durante o próprio fade de saída (show()).
            function resume(p) {
                outAnim.stop();
                loader.wantShown = false;
                loader.phase = "in";
                const it = loader.screen;
                it.current = true;
                if (JSON.stringify(p) !== JSON.stringify(it.payload || ({})))
                    loader.reopen(p);
                root.heightRequest(it.implicitHeight, "panel");
                loader.startIn();
            }

            function finishOut() {
                outAnim.stop();
                const it = loader.screen;
                const was = loader.presented;
                loader.presented = false;
                loader.phase = "hidden";
                loader.opacity = 0;
                loader.fxBlur = 0;
                loader.unbindLayers();
                if (it && was && typeof it.closed === "function")
                    it.closed();
            }

            onLoaded: {
                if (loader.wantShown)
                    loader.present();
            }
            onStatusChanged: {
                if (loader.status === Loader.Error)
                    console.warn("ilha: a tela " + loader.screenKey + " não carregou");
            }

            // F / G, fade único.
            SequentialAnimation {
                id: inSingle
                PauseAnimation {
                    id: inPause
                }
                ParallelAnimation {
                    NumberAnimation {
                        id: inOpacity
                        target: loader
                        property: "opacity"
                        to: 1
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        id: inBlur
                        target: loader
                        property: "fxBlur"
                        to: 0
                        easing.type: Easing.OutCubic
                    }
                }
                ScriptAction {
                    script: {
                        loader.fxBlur = 0;
                        loader.phase = "shown";
                    }
                }
            }

            // F / G, duas camadas.
            SequentialAnimation {
                id: inLayered
                ParallelAnimation {
                    SequentialAnimation {
                        PauseAnimation {
                            id: headerPause
                        }
                        NumberAnimation {
                            id: headerFade
                            target: loader
                            property: "headerOp"
                            to: 1
                            easing.type: Easing.OutCubic
                        }
                    }
                    SequentialAnimation {
                        PauseAnimation {
                            id: bodyPause
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                id: bodyFade
                                target: loader
                                property: "bodyOp"
                                to: 1
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                id: bodyUnblur
                                target: loader
                                property: "bodyBlur"
                                to: 0
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                ScriptAction {
                    script: {
                        loader.unbindLayers();
                        loader.phase = "shown";
                    }
                }
            }

            // G / H, saída (a pilha inteira).
            SequentialAnimation {
                id: outAnim
                ParallelAnimation {
                    NumberAnimation {
                        id: outOpacity
                        target: loader
                        property: "opacity"
                        to: 0
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        id: outBlur
                        target: loader
                        property: "fxBlur"
                        easing.type: Easing.OutCubic
                    }
                }
                ScriptAction {
                    script: loader.finishOut()
                }
            }

            Binding {
                when: loader.item !== null
                target: loader.item
                property: "keyboardMode"
                value: root.keyboardMode
            }
            Binding {
                when: loader.item !== null
                target: loader.item
                property: "edgeLeft"
                value: root.morph ? root.morph.left - loader.x : 0
            }
            Binding {
                when: loader.item !== null
                target: loader.item
                property: "edgeRight"
                value: root.morph ? root.morph.right - loader.x : 0
            }

            Connections {
                target: loader.item
                ignoreUnknownSignals: true
                function onImplicitHeightChanged() {
                    if (priv.loader === loader && loader.presented && loader.phase !== "out")
                        root.heightRequest(loader.screen.implicitHeight, loader.screen.heightMotion !== undefined ? loader.screen.heightMotion : "panel");
                }
                function onNavigate(id, payload) {
                    if (root.island && loader.presented)
                        root.island.open(id, root.island.screenOutput, payload);
                }
                function onCloseRequested() {
                    if (root.island && loader.presented)
                        root.island.close();
                }
            }
        }
    }
}
