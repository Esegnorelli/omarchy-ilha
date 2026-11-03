pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons as Commons
import "Motion.js" as Motion

// Central de controle (screens §5, motion J/K, amendments §12): a grade
// 2 x (bloco, bloco, redondo), os cartões de Som e Tela com barra e o cartão
// de notificações; os popovers Wi-Fi e Bluetooth (K) e as subpáginas Som,
// Tela e Ilha (J) num contêiner único que nasce da origem (bloco, seta ou
// botão) e cresce até o cartão.
//
// Medidas (tela 514 x 513, cap 30; margem 14, conteúdo 486, vão 11):
// - Linha 1 (faixa 14..74): bloco A em x 14 e bloco B em x 227 (202 x 57,
//   y + 1,5), redondo em x 440 (60). Linha 2 (85..145): mesmas colunas.
// - Som y 156 (486 x 61), Tela y 228 (486 x 60), Notificações y 299 (486 x 200).
// - Cartões com barra: raio 21, fill card; título (15, topo das maiúsculas
//   11) 15 / 600; seta 24 centrada em (w − 23, 14), fill raised, hover
//   iconIdle; barra x 10..w − 10, y 29, 24 de altura.
// - RTL: x' = 514 − x − largura (mx); dentro dos cartões as âncoras espelham.
//
// Contêiner (popover e subpágina): x 22, w 470, raio 21, fill card.
// - Subpágina (J): y 21; a tela cresce para max(513, cardH + 42).
// - Popover (K): centrado na altura da tela (que fica 513 enquanto couber).
// - cardH = implicitHeight do cartão, limitado a maxHeight − 42 (acima disso
//   a subpágina rola sozinha). implicitHeight = max(513, cardH + 42).
// - J: nasce no retângulo da seta (24, raio 12) ou do botão Ajustes da Ilha
//   (26, raio 13), cor surface -> card em 130 ms, geometria em 160 ms
//   OutQuint; a seta some em T0; a grade escurece até 0,5 em 120 ms e fica
//   desligada; o conteúdo (no layout final, preso ao canto de cima e
//   recortado) entra em 80 ms depois de 40, desfoque 6 -> 0.
//   Volta: conteúdo sai em 50 ms; o contêiner volta à origem em 180 ms
//   depois de 20 (card -> surface); a grade clareia em 130 ms depois de 20 e
//   volta a aceitar clique no fim; a seta reaparece em 70 ms depois de 130,
//   enquanto o contêiner some no mesmo intervalo.
// - K: nasce no retângulo do bloco (raio 28,5) e vai ao cartão em 130 ms
//   OutCubic (cor junto); o bloco some em 60 ms. Volta: conteúdo em 50 ms;
//   contêiner e grada em 130 ms depois de 50; o bloco reaparece em 130 ms
//   depois de 180 (uns 310 ms no total, como no vídeo).
// - Com o cartão aberto, mudanças de altura (senha, listas) andam 160 ms OutCubic.
// - A captura de clique fora (área toda, abaixo do cartão) fecha no press.
//
// payload: { sub?, focus?: "notifications" | "stayAwake", key?, app?, summary?, keyboard? }
// - sub abre direto, sem transformação (a tela inteira já entra com o fade F).
// - focus "notifications": em T0 + 150 ms, notifications.flash({key, app, summary}).
// - focus "stayAwake": sempre com sub "display"; em T0 + 150 ms, display.reveal("stayAwake").
// - Payload novo com a Central já na tela: a troca anima (J/K da origem certa).
//
// Teclado (anéis só com keyboardMode):
//   [Wi-Fi, Foco, Bloquear] / [Bluetooth, Modo jogo, Luz noturna] /
//   [Som, seta] / [Tela, seta] / faixa do cartão de notificações / linhas.
//   Setas andam pela posição visual; Tab / Shift+Tab em ordem; Enter = ação
//   principal (abre popover / subpágina, alterna); Espaço = círculo do bloco
//   (rádio) ou mudo na barra de Som. Nas barras, Esquerda/Direita ±5 %
//   (Shift ±1 %); M silencia (Som). Ctrl / Alt ficam para as teclas globais.
//   Esc fecha a subpágina (handleEscape), depois a ilha.
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
    property var heightMotion: Motion.INNER
    property bool snapping: false
    property list<Item> headerItems
    property list<Item> bodyItems
    signal navigate(string id, var payload)
    signal closeRequested()

    // ---- Próprio ----
    readonly property string sub: priv.sub
    readonly property real maxHeight: root.island && root.theme ? root.theme.maxPanelH(root.island.screenGeometry(root.island.screenOutput).h) : 926
    readonly property var subItem: root.itemFor(priv.sub)
    readonly property bool isPopover: root.popover(priv.sub)
    readonly property var status: root.island ? root.island.status : null
    readonly property var net: root.island ? root.island.net : null
    readonly property var audio: root.island ? root.island.audio : null
    readonly property var monitors: root.island ? root.island.monitors : null

    implicitWidth: 514
    implicitHeight: priv.sub !== "" && root.subItem ? Math.max(513, root.cardHeightFor(root.subItem) + 42) : 513

    // ---- Subpágina / popover ----

    function openSub(name, sourceItem) {
        const n = String(name || "");
        const it = root.itemFor(n);
        if (!it)
            return;
        if (root.snapping || !priv.isOpen) {
            root.snapSub(n);
            return;
        }
        if (n === priv.sub)
            return;
        if (priv.sub !== "") {
            root.swapSub(n);
            return;
        }
        openAnim.stop();
        closeAnim.stop();
        swapAnim.stop();
        // Voltando no meio da volta do mesmo cartão: segue do estado atual.
        const reversing = priv.closing && priv.shownSub === n;
        if (!reversing) {
            if (priv.shownSub !== "")
                root.finishClose();
            root.setSource(n, sourceItem || root.sourceFor(n));
            box.t = 0;
            box.tone = 0;
            content.opacity = 0;
            content.blurPx = Motion.FADE.SUB_CONTENT_IN.blur;
        }
        box.opacity = 1;
        priv.closing = false;
        priv.opening = true;
        priv.gridEnabled = false;
        priv.sub = n;
        priv.shownSub = n;
        root.syncIslandSub();
        root.activateSub(n);
        openAnim.pop = root.popover(n);
        openAnim.restart();
    }

    function closeSub() {
        if (priv.sub === "")
            return;
        const n = priv.sub;
        if (root.snapping || !priv.isOpen) {
            root.deactivateSub();
            root.resetMain();
            root.syncIslandSub();
            return;
        }
        openAnim.stop();
        swapAnim.stop();
        // O destino fica onde está (a tela encolhe para 513 já em T0) e a
        // altura do cartão também: o closed() do cartão só roda depois que o
        // conteúdo sumiu (ScriptAction do closeAnim), para nada mudar à vista.
        priv.frozenDstY = priv.liveDstY;
        priv.frozenCardH = priv.shownCardH;
        priv.closing = true;
        priv.opening = false;
        priv.sub = "";
        root.syncIslandSub();
        // O foco do teclado volta para a origem (seta, bloco ou Ajustes da Ilha).
        if (root.keyboardMode) {
            if (n === "ilha") {
                priv.focus = "";
                notifications.focusShortcut("settings");
            } else {
                root.focusCell(root.cellForSub(n));
            }
        }
        closeAnim.pop = root.popover(n);
        closeAnim.restart();
    }

    // opened() / closed() de um cartão, uma vez só cada (nunca dois opened seguidos).
    function activateSub(name) {
        if (priv.liveSub === name)
            return;
        root.deactivateSub();
        const it = root.itemFor(name);
        if (!it)
            return;
        priv.liveSub = name;
        if (typeof it.opened === "function")
            it.opened();
    }

    function deactivateSub() {
        if (priv.liveSub === "")
            return;
        const it = root.itemFor(priv.liveSub);
        priv.liveSub = "";
        if (it && typeof it.closed === "function")
            it.closed();
    }

    // ---- Contrato de tela ----

    function opened(payload) {
        const p = payload || ({});
        // Payload novo com a Central já na tela (ilha open sound, toque no
        // aviso…): o ScreenStack chama closed() + opened(p) no lugar, com
        // current ainda true (priv.reopen), e a troca anima daqui.
        const again = priv.reopen || (priv.isOpen && root.current);
        priv.reopen = false;
        priv.isOpen = true;
        // Brilho vivo enquanto a Central está aberta: lê na hora e a cada 5 s.
        if (root.monitors)
            root.monitors.polling = true;
        if (!again) {
            root.snapping = true;
            root.resetMain();
            priv.brightPreview = -1;
            notifications.clearFocus();
            priv.focus = root.keyboardMode ? "wifi" : "";
        }
        let want = p.sub ? String(p.sub) : "";
        if (p.focus === "stayAwake")
            want = "display";
        if (!root.itemFor(want))
            want = "";
        if (want !== "" && want === priv.sub)
            root.activateSub(want);         // mesmo cartão: só volta a atividade
        else if (want !== "")
            root.openSub(want, null);
        else if (again && priv.sub !== "")
            root.closeSub();
        focusTimer.stop();
        if (p.focus === "notifications" || p.focus === "stayAwake") {
            priv.focusWhat = String(p.focus);
            priv.flashRow = { key: p.key || "", app: p.app || "", summary: p.summary || "" };
            focusTimer.interval = again ? 220 : 150;
            focusTimer.start();
        }
        if (!again)
            Qt.callLater(() => root.snapping = false);
    }

    function closed() {
        focusTimer.stop();
        // Ainda current: é o ScreenStack reabrindo no lugar (payload novo). O
        // desenho e o cartão ficam como estão; o opened(p) seguinte anima a
        // troca e para o cartão só quando ele sair de vista.
        if (root.current && priv.isOpen) {
            priv.reopen = true;
            return;
        }
        root.deactivateSub();
        root.resetMain();
        priv.isOpen = false;
        if (root.monitors)
            root.monitors.polling = false;
        priv.focus = "";
        priv.brightPreview = -1;
        notifications.clearFocus();
    }

    function handleKey(event) {
        // Enter/Espaço segurado não repete a ação: o repeat do Hyprland (40/s)
        // ligaria e desligaria o Wi-Fi, o Bluetooth ou um ajuste em rajada.
        // As setas continuam repetindo.
        const ek = event.key;
        if (event.isAutoRepeat && (ek === Qt.Key_Return || ek === Qt.Key_Enter || ek === Qt.Key_Space))
            return true;
        if (priv.sub !== "") {
            const it = root.subItem;
            return !!it && typeof it.handleKey === "function" && it.handleKey(event);
        }
        const k = event.key;
        const mods = event.modifiers || 0;
        // Ctrl+Tab, Alt+1..6 e afins são da janela.
        if (mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        const shift = !!(mods & Qt.ShiftModifier);
        if (notifications.hasFocus) {
            if (notifications.handleKey(event))
                return true;
            if (k === Qt.Key_Up) {
                const p = notifications.mapToItem(root, notifications.focusX(), 0);
                root.focusNearest(3, p.x);
                return true;
            }
            if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
                root.focusCell(k === Qt.Key_Backtab || shift ? "displayChevron" : "wifi");
                return true;
            }
            return false;
        }
        const nav = [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Tab, Qt.Key_Backtab,
                     Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Home, Qt.Key_End];
        if (priv.focus === "") {
            if (nav.indexOf(k) === -1)
                return false;
            root.focusCell("wifi");
            return true;
        }
        const onSlider = priv.focus === "sound" || priv.focus === "display";
        switch (k) {
        case Qt.Key_Left:
        case Qt.Key_Right: {
            const visualDir = k === Qt.Key_Right ? 1 : -1;
            if (onSlider) {
                // A barra cresce da direita em RTL: a seta segue o lado visual.
                const grow = visualDir * (root.theme && root.theme.rtl ? -1 : 1);
                root.sliderFor(priv.focus).nudge(grow * (shift ? 0.01 : 0.05));
            } else {
                root.focusSideways(visualDir);
            }
            return true;
        }
        case Qt.Key_Up:
        case Qt.Key_Down:
            root.focusVertical(k === Qt.Key_Down ? 1 : -1);
            return true;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            root.focusLinear(k === Qt.Key_Backtab || shift ? -1 : 1);
            return true;
        case Qt.Key_Home:
            root.focusCell("wifi");
            return true;
        case Qt.Key_End:
            notifications.focusFirstRow();
            priv.focus = "";
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.primary(priv.focus);
            return true;
        case Qt.Key_Space:
            root.secondary(priv.focus);
            return true;
        case Qt.Key_M:
            if (priv.focus === "sound" || priv.focus === "soundChevron") {
                if (root.audio)
                    root.audio.toggleMute();
                return true;
            }
            return false;
        default:
            return false;
        }
    }

    function handleEscape() {
        if (priv.sub === "")
            return false;
        const it = root.subItem;
        if (it && typeof it.handleEscape === "function" && it.handleEscape())
            return true;
        root.closeSub();
        return true;
    }

    // ---- Auxiliares ----

    function t(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    function ms(v) {
        return root.theme ? root.theme.dur(v) : 0;
    }

    // x calculado em LTR -> x na direção do idioma.
    function mx(x, w) {
        return root.theme && root.theme.rtl ? root.implicitWidth - x - w : x;
    }

    function itemFor(name) {
        switch (String(name || "")) {
        case "sound":
            return soundPage;
        case "display":
            return displayPage;
        case "ilha":
            return ilhaPage;
        case "wifi":
            return wifiCard;
        case "bluetooth":
            return btCard;
        default:
            return null;
        }
    }

    function popover(name) {
        return name === "wifi" || name === "bluetooth";
    }

    function cardHeightFor(it) {
        return it ? Math.max(0, Math.min(it.implicitHeight, root.maxHeight - 42)) : 0;
    }

    // O item de onde o contêiner nasce (e para onde volta).
    function sourceFor(name) {
        switch (String(name || "")) {
        case "sound":
            return soundCard.chevron;
        case "display":
            return displayCard.chevron;
        case "ilha":
            return notifications.settingsButton;
        case "wifi":
            return wifiTile;
        case "bluetooth":
            return btTile;
        default:
            return null;
        }
    }

    function cellForSub(name) {
        switch (String(name || "")) {
        case "sound":
            return "soundChevron";
        case "display":
            return "displayChevron";
        case "wifi":
            return "wifi";
        case "bluetooth":
            return "bt";
        default:
            return "";
        }
    }

    function setSource(name, src) {
        priv.srcKey = name;
        if (src) {
            const p = src.mapToItem(root, 0, 0);
            priv.srcX = p.x;
            priv.srcY = p.y;
            priv.srcW = src.width;
            priv.srcH = src.height;
        } else {
            priv.srcX = 22 + 470 / 2 - 12;
            priv.srcY = 21;
            priv.srcW = 24;
            priv.srcH = 24;
        }
        priv.srcR = Math.min(priv.srcW, priv.srcH) / 2;
    }

    // Abre já no estado final (payload.sub na abertura, snapping).
    function snapSub(name) {
        openAnim.stop();
        closeAnim.stop();
        swapAnim.stop();
        root.setSource(name, root.sourceFor(name));
        priv.opening = false;
        priv.closing = false;
        priv.sub = name;
        priv.shownSub = name;
        box.t = 1;
        box.tone = 1;
        box.opacity = 1;
        content.opacity = 1;
        content.blurPx = 0;
        grid.opacity = Motion.FADE.SUB_DIM.to;
        priv.gridEnabled = false;
        priv.sourceOpacity = 0;
        root.syncIslandSub();
        root.activateSub(name);
    }

    // Troca direta de um cartão para outro com a Central na tela: só o
    // conteúdo troca (fade de entrada); a altura e o y andam no Behavior.
    function swapSub(name) {
        openAnim.stop();
        closeAnim.stop();
        root.setSource(name, root.sourceFor(name));
        priv.opening = false;
        priv.closing = false;
        priv.sub = name;
        priv.shownSub = name;
        box.t = 1;
        box.tone = 1;
        box.opacity = 1;
        grid.opacity = Motion.FADE.SUB_DIM.to;
        priv.gridEnabled = false;
        priv.sourceOpacity = 0;
        root.syncIslandSub();
        root.activateSub(name);
        content.opacity = 0;
        content.blurPx = Motion.FADE.SUB_CONTENT_IN.blur;
        swapAnim.restart();
    }

    // Fim da volta: o contêiner some e a grade volta inteira.
    function finishClose() {
        closeAnim.stop();
        priv.closing = false;
        priv.shownSub = "";
        priv.srcKey = "";
        priv.sourceOpacity = 1;
        box.t = 0;
        box.tone = 0;
        box.opacity = 1;
        content.opacity = 0;
        content.blurPx = 0;
        grid.opacity = 1;
        priv.gridEnabled = true;
        // Um cartão que ainda rodava sem ser o alvo para aqui.
        if (priv.liveSub !== "" && priv.liveSub !== priv.sub)
            root.deactivateSub();
    }

    // Estado da grade, sem animação (abertura e fechamento da Central).
    function resetMain() {
        openAnim.stop();
        closeAnim.stop();
        swapAnim.stop();
        priv.sub = "";
        priv.opening = false;
        root.finishClose();
    }

    // isBarWidgetOpen / toggle do host leem island.screenSub.
    function syncIslandSub() {
        if (root.island && root.island.screen === "control")
            root.island.screenSub = priv.sub;
    }

    // ---- Ações ----

    function toggleDnd() {
        if (root.status)
            root.status.setDnd(!root.status.dnd);
    }

    function toggleGame() {
        if (root.status)
            root.status.setGameMode(!root.status.gameMode);
    }

    function toggleNight() {
        if (root.status)
            root.status.setNightlight(!root.status.nightlight);
    }

    function toggleWifiRadio() {
        if (root.net && root.net.wifiAvailable)
            root.net.setWifiEnabled(!root.net.wifiEnabled);
    }

    function toggleBtPower() {
        if (root.net && root.net.btAvailable)
            root.net.setBtEnabled(!root.net.btEnabled);
    }

    // Bloquear: a ilha fecha e o comando roda 180 ms depois (CLOSE_THEN_RUN_MS).
    function lock() {
        root.closeRequested();
        lockTimer.restart();
    }

    function runDetached(cmd) {
        // No harness (ILHA_DEV) nada de bloquear a sessão de verdade.
        if (root.island && root.island.dev) {
            console.log("ilha (dev): " + cmd.join(" "));
            return;
        }
        Quickshell.execDetached(cmd);
    }

    function setVolume(v) {
        if (root.audio)
            root.audio.setVolume(Math.max(0, Math.min(1, v)));
    }

    // Brilho: a barra mostra o valor na hora; o MonitorSvc grava (com o próprio debounce).
    function setBrightness(v) {
        const m = root.focusedMonitor;
        if (!m || !root.monitors)
            return;
        priv.brightPreview = Math.max(0, Math.min(1, v));
        previewTimer.restart();
        root.monitors.setBrightness(m.name, Math.round(priv.brightPreview * 100));
    }

    function volumeGlyph() {
        const a = root.audio;
        if (!a || a.muted || a.volume <= 0.005)
            return "volume_off";
        if (a.volume <= 0.33)
            return "volume_mute";
        if (a.volume <= 0.66)
            return "volume_down";
        return "volume_up";
    }

    function wifiSubtitle() {
        const n = root.net;
        if (!n)
            return "";
        if (!n.wifiAvailable)
            return root.t(n.wired ? "cc.ethernet" : "cc.unavailable");
        if (!n.wifiEnabled)
            return root.t("common.off");
        if (n.connected && String(n.ssid || "") !== "")
            return String(n.ssid);
        if (n.wired)
            return root.t("cc.ethernet");
        return root.t("cc.notConnected");
    }

    function btSubtitle() {
        const n = root.net;
        if (!n || !n.btAvailable)
            return root.t("bt.noAdapter");
        if (!n.btEnabled)
            return root.t("common.off");
        const c = Number(n.connectedCount) || 0;
        if (c > 0 && root.strings)
            return root.strings.tn("cc.connectedCount", c).arg(Commons.I18n.formatNumber(c));
        return root.t("common.on");
    }

    readonly property var focusedMonitor: root.monitors ? root.monitors.focused : null
    readonly property bool hasBrightness: !!root.focusedMonitor && root.focusedMonitor.hasBrightness !== false

    // ---- Grade do teclado ----

    readonly property var cellRows: [["wifi", "focus", "lock"], ["bt", "game", "night"], ["sound", "soundChevron"], ["display", "displayChevron"]]

    function cellItem(id) {
        switch (id) {
        case "wifi":
            return wifiTile;
        case "focus":
            return focusTile;
        case "lock":
            return lockButton;
        case "bt":
            return btTile;
        case "game":
            return gameTile;
        case "night":
            return nightButton;
        case "sound":
            return soundCard.slider;
        case "soundChevron":
            return soundCard.chevron;
        case "display":
            return displayCard.slider;
        case "displayChevron":
            return displayCard.chevron;
        default:
            return null;
        }
    }

    function sliderFor(id) {
        return id === "sound" ? soundCard.slider : displayCard.slider;
    }

    function cellCenterX(id) {
        const it = root.cellItem(id);
        return it ? it.mapToItem(root, it.width / 2, 0).x : 0;
    }

    function rowOfCell(id) {
        for (let r = 0; r < root.cellRows.length; r++) {
            if (root.cellRows[r].indexOf(id) !== -1)
                return r;
        }
        return -1;
    }

    function focusCell(id) {
        if (!root.cellItem(id))
            return;
        notifications.clearFocus();
        priv.focus = id;
    }

    // A célula da linha r mais perto de x (coordenadas da Central).
    function focusNearest(r, x) {
        const cells = root.cellRows[Math.max(0, Math.min(root.cellRows.length - 1, r))];
        let best = cells[0], bestD = Infinity;
        for (let i = 0; i < cells.length; i++) {
            const d = Math.abs(root.cellCenterX(cells[i]) - x);
            if (d < bestD) {
                bestD = d;
                best = cells[i];
            }
        }
        root.focusCell(best);
    }

    function focusSideways(dir) {
        const r = root.rowOfCell(priv.focus);
        if (r < 0)
            return;
        const cur = root.cellCenterX(priv.focus);
        let best = "", bestD = Infinity;
        const cells = root.cellRows[r];
        for (let i = 0; i < cells.length; i++) {
            const d = (root.cellCenterX(cells[i]) - cur) * dir;
            if (d > 1 && d < bestD) {
                bestD = d;
                best = cells[i];
            }
        }
        if (best !== "")
            root.focusCell(best);
    }

    function focusVertical(dir) {
        const r = root.rowOfCell(priv.focus);
        if (r < 0)
            return;
        const x = root.cellCenterX(priv.focus);
        const next = r + dir;
        if (next < 0)
            return;
        if (next >= root.cellRows.length) {
            // Desce para a faixa do cartão de notificações.
            const p = root.mapToItem(notifications, x, 0);
            notifications.focusStrip(p.x);
            priv.focus = "";
            return;
        }
        root.focusNearest(next, x);
    }

    function focusLinear(step) {
        const order = [].concat.apply([], root.cellRows);
        const at = order.indexOf(priv.focus);
        const next = at + step;
        if (next >= order.length) {
            notifications.focusStrip(-1);
            priv.focus = "";
            return;
        }
        if (next < 0)
            return;
        root.focusCell(order[next]);
    }

    function primary(id) {
        switch (id) {
        case "wifi":
            root.openSub("wifi", wifiTile);
            break;
        case "focus":
            root.toggleDnd();
            break;
        case "lock":
            root.lock();
            break;
        case "bt":
            root.openSub("bluetooth", btTile);
            break;
        case "game":
            root.toggleGame();
            break;
        case "night":
            root.toggleNight();
            break;
        case "sound":
        case "soundChevron":
            root.openSub("sound", soundCard.chevron);
            break;
        case "display":
        case "displayChevron":
            root.openSub("display", displayCard.chevron);
            break;
        default:
            break;
        }
    }

    function secondary(id) {
        switch (id) {
        case "wifi":
            root.toggleWifiRadio();
            break;
        case "bt":
            root.toggleBtPower();
            break;
        case "sound":
            if (root.audio)
                root.audio.toggleMute();
            break;
        case "display":
            break;
        default:
            root.primary(id);
            break;
        }
    }

    function ringOn(id) {
        return root.keyboardMode && priv.sub === "" && priv.focus === id;
    }

    QtObject {
        id: priv
        // Alvo ("" = grade) e o que o contêiner mostra (fica até o fim da volta).
        property string sub: ""
        property string shownSub: ""
        property bool opening: false
        property bool closing: false
        readonly property bool steady: priv.shownSub !== "" && !priv.opening && !priv.closing
        property bool gridEnabled: true
        // Entre opened() e closed(); reopen = closed() do ScreenStack com a tela ainda na frente.
        property bool isOpen: false
        property bool reopen: false
        // O cartão com opened() chamado e closed() ainda não ("" = nenhum).
        property string liveSub: ""
        // Origem do contêiner (coordenadas da Central) e quem fica escondido.
        property string srcKey: ""
        property real srcX: 0
        property real srcY: 0
        property real srcW: 24
        property real srcH: 24
        property real srcR: 12
        property real sourceOpacity: 1
        readonly property var shownItem: root.itemFor(priv.shownSub)
        readonly property real shownCardH: root.cardHeightFor(priv.shownItem)
        // y do cartão: 21 na subpágina; centrado na tela no popover.
        readonly property real liveDstY: root.popover(priv.shownSub) ? Math.round((root.implicitHeight - priv.shownCardH) / 2) : 21
        property real frozenDstY: 21
        property real frozenCardH: 0
        // Altura do contêiner e do conteúdo (congelada durante a volta).
        readonly property real boxCardH: priv.closing ? priv.frozenCardH : priv.shownCardH
        // Célula focada pelo teclado ("" = nenhuma ou dentro do cartão de notificações).
        property string focus: ""
        // payload.focus pendente.
        property string focusWhat: ""
        property var flashRow: ({})
        // Brilho mostrado enquanto o serviço não confirma (-1 = nenhum).
        property real brightPreview: -1
    }

    // O cartão de notificações pegou o foco (descida, Tab, flash no modo
    // teclado): a grade solta o dela, para nunca haver dois anéis.
    Connections {
        target: notifications
        function onHasFocusChanged() {
            if (notifications.hasFocus)
                priv.focus = "";
        }
    }

    Timer {
        id: focusTimer
        interval: 150
        onTriggered: {
            if (priv.focusWhat === "notifications")
                notifications.flash(priv.flashRow);
            else if (priv.focusWhat === "stayAwake" && typeof displayPage.reveal === "function")
                displayPage.reveal("stayAwake");
            priv.focusWhat = "";
        }
    }

    Timer {
        id: lockTimer
        interval: Motion.TIMING.CLOSE_THEN_RUN_MS
        onTriggered: root.runDetached(["omarchy", "system", "lock"])
    }

    Timer {
        id: previewTimer
        interval: Motion.TIMING.MONITOR_PAUSE_MS
        onTriggered: priv.brightPreview = -1
    }

    // ---- J / K ----

    ParallelAnimation {
        id: openAnim
        property bool pop: false

        NumberAnimation {
            target: box
            property: "t"
            to: 1
            duration: root.ms(openAnim.pop ? Motion.FADE.POP_CONTAINER.dur : Motion.FADE.SUB_CONTAINER.dur)
            easing.type: openAnim.pop ? Easing.OutCubic : Easing.OutQuint
        }
        NumberAnimation {
            target: box
            property: "tone"
            to: 1
            duration: root.ms(openAnim.pop ? Motion.FADE.POP_CONTAINER.dur : Motion.FADE.SUB_COLOR)
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: grid
            property: "opacity"
            to: Motion.FADE.SUB_DIM.to
            duration: root.ms(openAnim.pop ? Motion.FADE.POP_DIM.dur : Motion.FADE.SUB_DIM.dur)
            easing.type: Easing.OutCubic
        }
        // K: o bloco some em 60 ms; J: a seta some em T0.
        NumberAnimation {
            target: priv
            property: "sourceOpacity"
            to: 0
            duration: openAnim.pop ? root.ms(Motion.FADE.POP_TILE_OUT.dur) : 0
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            PauseAnimation {
                duration: root.ms(openAnim.pop ? Motion.FADE.POP_CONTENT_IN.delay : Motion.FADE.SUB_CONTENT_IN.delay)
            }
            ParallelAnimation {
                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 1
                    duration: root.ms(openAnim.pop ? Motion.FADE.POP_CONTENT_IN.dur : Motion.FADE.SUB_CONTENT_IN.dur)
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: content
                    property: "blurPx"
                    to: 0
                    duration: root.ms(openAnim.pop ? Motion.FADE.POP_CONTENT_IN.dur : Motion.FADE.SUB_CONTENT_IN.dur)
                    easing.type: Easing.OutCubic
                }
            }
        }
        onFinished: priv.opening = false
    }

    ParallelAnimation {
        id: closeAnim
        property bool pop: false

        SequentialAnimation {
            NumberAnimation {
                target: content
                property: "opacity"
                to: 0
                duration: root.ms(closeAnim.pop ? Motion.FADE.POP_CONTENT_OUT.dur : Motion.FADE.SUB_CONTENT_OUT.dur)
                easing.type: Easing.OutCubic
            }
            // Conteúdo invisível: agora o cartão para (varredura, sondagem…).
            ScriptAction {
                script: root.deactivateSub()
            }
        }
        SequentialAnimation {
            PauseAnimation {
                duration: root.ms(closeAnim.pop ? Motion.FADE.POP_CONTAINER_BACK.delay : Motion.FADE.SUB_CONTAINER_BACK.delay)
            }
            ParallelAnimation {
                NumberAnimation {
                    target: box
                    property: "t"
                    to: 0
                    duration: root.ms(closeAnim.pop ? Motion.FADE.POP_CONTAINER_BACK.dur : Motion.FADE.SUB_CONTAINER_BACK.dur)
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: box
                    property: "tone"
                    to: 0
                    duration: root.ms(closeAnim.pop ? Motion.FADE.POP_CONTAINER_BACK.dur : Motion.FADE.SUB_CONTAINER_BACK.dur)
                    easing.type: Easing.OutCubic
                }
            }
        }
        SequentialAnimation {
            PauseAnimation {
                duration: root.ms(closeAnim.pop ? Motion.FADE.POP_UNDIM.delay : Motion.FADE.SUB_UNDIM.delay)
            }
            NumberAnimation {
                target: grid
                property: "opacity"
                to: 1
                duration: root.ms(closeAnim.pop ? Motion.FADE.POP_UNDIM.dur : Motion.FADE.SUB_UNDIM.dur)
                easing.type: Easing.OutCubic
            }
        }
        // A origem reaparece (K: o bloco; J: a seta, em cruz com o contêiner).
        SequentialAnimation {
            PauseAnimation {
                duration: root.ms(closeAnim.pop ? Motion.FADE.POP_TILE_IN.delay : Motion.FADE.SUB_CHEVRON_IN.delay)
            }
            NumberAnimation {
                target: priv
                property: "sourceOpacity"
                to: 1
                duration: root.ms(closeAnim.pop ? Motion.FADE.POP_TILE_IN.dur : Motion.FADE.SUB_CHEVRON_IN.dur)
                easing.type: Easing.OutCubic
            }
        }
        SequentialAnimation {
            PauseAnimation {
                duration: root.ms(closeAnim.pop ? Motion.FADE.POP_CONTAINER_BACK.delay + Motion.FADE.POP_CONTAINER_BACK.dur : Motion.FADE.SUB_CHEVRON_IN.delay)
            }
            NumberAnimation {
                target: box
                property: "opacity"
                to: 0
                duration: closeAnim.pop ? 0 : root.ms(Motion.FADE.SUB_CHEVRON_IN.dur)
                easing.type: Easing.OutCubic
            }
        }
        onFinished: root.finishClose()
    }

    // Troca de cartão com o contêiner aberto: só o conteúdo entra.
    SequentialAnimation {
        id: swapAnim
        PauseAnimation {
            duration: root.ms(Motion.FADE.SUB_CONTENT_IN.delay)
        }
        ParallelAnimation {
            NumberAnimation {
                target: content
                property: "opacity"
                to: 1
                duration: root.ms(Motion.FADE.SUB_CONTENT_IN.dur)
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: content
                property: "blurPx"
                to: 0
                duration: root.ms(Motion.FADE.SUB_CONTENT_IN.dur)
                easing.type: Easing.OutCubic
            }
        }
    }

    // ---- Cartão com barra (Som, Tela) ----
    component SliderCard: Rectangle {
        id: card

        property Theme theme: null
        property string title: ""
        property string glyph: ""
        property real value: 0
        property bool active: true
        property bool muted: false
        property string note: ""
        property string chevronName: ""
        property string sliderName: ""
        property bool sliderFocused: false
        property bool chevronFocused: false
        property real chevronOpacity: 1
        readonly property Item chevron: chev
        readonly property IlhaSlider slider: bar

        signal moved(real v)
        signal committed(real v)
        signal glyphTapped()
        signal openRequested()

        width: 486
        radius: 21
        color: card.theme ? card.theme.card : "transparent"

        IlhaText {
            id: heading
            anchors.left: parent.left
            anchors.leftMargin: 15
            y: 11 - (heading.baselineOffset - 0.7275 * heading.font.pixelSize)
            theme: card.theme
            size: 15
            weight: 600
            text: card.title
        }
        IlhaText {
            anchors.right: chev.left
            anchors.rightMargin: 10
            anchors.baseline: heading.baseline
            visible: card.note !== ""
            theme: card.theme
            size: 12.5
            weight: 500
            color: card.theme ? card.theme.inkMuted : "gray"
            text: card.note
        }
        CircleButton {
            id: chev
            anchors.right: parent.right
            anchors.rightMargin: 23 - 12
            y: 14 - 12
            opacity: card.chevronOpacity
            theme: card.theme
            icon: "chevron_right"
            flip: !!card.theme && card.theme.rtl
            size: 24
            glyphSize: 14
            fill: card.theme ? card.theme.raised : "transparent"
            hoverFill: card.theme ? card.theme.iconIdle : "transparent"
            glyphColor: card.theme ? card.theme.inkMuted : "gray"
            focused: card.chevronFocused
            accessibleName: card.chevronName
            onClicked: card.openRequested()
        }
        IlhaSlider {
            id: bar
            x: 10
            y: 29
            width: card.width - 20
            theme: card.theme
            glyph: card.glyph
            value: card.value
            enabled: card.active
            fillColor: card.theme ? (card.muted ? card.theme.inkFaint : card.theme.accent) : "white"
            glyphColor: card.theme ? (card.muted ? card.theme.ink : card.theme.onAccent) : "black"
            focused: card.sliderFocused
            accessibleName: card.sliderName
            onMoved: v => card.moved(v)
            onCommitted: v => card.committed(v)
            onGlyphTapped: card.glyphTapped()
        }
    }

    // ---- Grade ----
    Item {
        id: grid
        anchors.fill: parent
        enabled: priv.gridEnabled

        ToggleTile {
            id: wifiTile
            x: root.mx(14, 202)
            y: 15.5
            opacity: priv.srcKey === "wifi" ? priv.sourceOpacity : 1
            theme: root.theme
            title: root.t("cc.wifi")
            subtitle: root.wifiSubtitle()
            icon: !root.net ? "wifi_off" : (!root.net.wifiAvailable && root.net.wired ? "lan" : (root.net.wifiEnabled ? "wifi" : "wifi_off"))
            active: !!root.net && root.net.wifiAvailable && root.net.wifiEnabled
            focused: root.ringOn("wifi")
            onClicked: root.openSub("wifi", wifiTile)
            onIconClicked: root.toggleWifiRadio()
        }
        ToggleTile {
            id: focusTile
            x: root.mx(227, 202)
            y: 15.5
            theme: root.theme
            title: root.t("cc.focus")
            subtitle: root.t(root.status && root.status.dnd ? "common.on" : "common.off")
            icon: "do_not_disturb_on"
            active: !!root.status && root.status.dnd
            focused: root.ringOn("focus")
            onClicked: root.toggleDnd()
            onIconClicked: root.toggleDnd()
        }
        IlhaRoundButton {
            id: lockButton
            x: root.mx(440, 60)
            y: 14
            theme: root.theme
            icon: "lock"
            focused: root.ringOn("lock")
            accessibleName: root.t("cc.lock")
            onClicked: root.lock()
        }
        ToggleTile {
            id: btTile
            x: root.mx(14, 202)
            y: 86.5
            opacity: priv.srcKey === "bluetooth" ? priv.sourceOpacity : 1
            theme: root.theme
            title: root.t("cc.bluetooth")
            subtitle: root.btSubtitle()
            icon: root.net && root.net.btAvailable && root.net.btEnabled ? "bluetooth" : "bluetooth_disabled"
            active: !!root.net && root.net.btAvailable && root.net.btEnabled
            focused: root.ringOn("bt")
            onClicked: root.openSub("bluetooth", btTile)
            onIconClicked: root.toggleBtPower()
        }
        ToggleTile {
            id: gameTile
            x: root.mx(227, 202)
            y: 86.5
            theme: root.theme
            title: root.t("cc.gameMode")
            subtitle: root.t(root.status && root.status.gameMode ? "common.on" : "common.off")
            icon: root.status && root.status.gameMode ? "toggle_on" : "toggle_off"
            active: !!root.status && root.status.gameMode
            focused: root.ringOn("game")
            onClicked: root.toggleGame()
            onIconClicked: root.toggleGame()
        }
        IlhaRoundButton {
            id: nightButton
            x: root.mx(440, 60)
            y: 85
            theme: root.theme
            icon: "dark_mode"
            filled: true
            active: !!root.status && root.status.nightlight
            focused: root.ringOn("night")
            accessibleName: root.t("cc.nightLight")
            onClicked: root.toggleNight()
        }

        SliderCard {
            id: soundCard
            x: 14
            y: 156
            height: 61
            theme: root.theme
            title: root.t("cc.sound")
            glyph: root.volumeGlyph()
            value: root.audio ? Math.max(0, Math.min(1, root.audio.volume)) : 0
            muted: !!root.audio && root.audio.muted
            chevronName: root.t("cc.soundSettings")
            sliderName: root.t("osd.volume")
            chevronOpacity: priv.srcKey === "sound" ? priv.sourceOpacity : 1
            sliderFocused: root.ringOn("sound")
            chevronFocused: root.ringOn("soundChevron")
            onMoved: v => root.setVolume(v)
            onCommitted: v => root.setVolume(v)
            onGlyphTapped: if (root.audio) root.audio.toggleMute()
            onOpenRequested: root.openSub("sound", soundCard.chevron)
        }

        SliderCard {
            id: displayCard
            x: 14
            y: 228
            height: 60
            theme: root.theme
            title: root.t("cc.display")
            glyph: "light_mode"
            value: priv.brightPreview >= 0 ? priv.brightPreview
                : (root.focusedMonitor ? Math.max(0, Math.min(1, (Number(root.focusedMonitor.brightness) || 0) / 100)) : 0)
            active: root.hasBrightness
            note: root.hasBrightness ? "" : root.t("display.noBrightness")
            chevronName: root.t("cc.displaySettings")
            sliderName: root.t("osd.brightness")
            chevronOpacity: priv.srcKey === "display" ? priv.sourceOpacity : 1
            sliderFocused: root.ringOn("display")
            chevronFocused: root.ringOn("displayChevron")
            onMoved: v => root.setBrightness(v)
            onCommitted: v => root.setBrightness(v)
            onOpenRequested: root.openSub("display", displayCard.chevron)
        }

        NotificationsCard {
            id: notifications
            x: 14
            y: 299
            island: root.island
            theme: root.theme
            strings: root.strings
            keyboardMode: root.keyboardMode
            ringsShown: priv.sub === ""
            settingsOpacity: priv.srcKey === "ilha" ? priv.sourceOpacity : 1
            onNavigate: id => root.navigate(id, ({}))
            onOpenSettings: root.openSub("ilha", notifications.settingsButton)
            onCloseRequested: root.closeRequested()
        }
    }

    // Clique fora do cartão (área toda, abaixo do contêiner): fecha já no press.
    MouseArea {
        anchors.fill: parent
        enabled: priv.sub !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: root.closeSub()
    }

    // ---- Contêiner do popover / subpágina ----
    Rectangle {
        id: box

        // 0 = na origem, 1 = no cartão; tone 0 = surface, 1 = card.
        property real t: 0
        property real tone: 0
        readonly property real dstY: priv.closing ? priv.frozenDstY : priv.liveDstY

        visible: priv.shownSub !== ""
        x: Motion.lerp(priv.srcX, 22, box.t)
        y: Motion.lerp(priv.srcY, box.dstY, box.t)
        width: Motion.lerp(priv.srcW, 470, box.t)
        height: Motion.lerp(priv.srcH, priv.boxCardH, box.t)
        radius: Motion.lerp(priv.srcR, 21, box.t)
        color: root.theme ? root.theme.mix(root.theme.surface, root.theme.card, box.tone) : "transparent"
        clip: true

        // Com o cartão aberto, a altura (e o centro do popover) anda 160 ms.
        Behavior on y {
            enabled: priv.steady && !root.snapping
            NumberAnimation { duration: root.ms(Motion.FADE.CARD_HEIGHT); easing.type: Easing.OutCubic }
        }
        Behavior on height {
            enabled: priv.steady && !root.snapping
            NumberAnimation { duration: root.ms(Motion.FADE.CARD_HEIGHT); easing.type: Easing.OutCubic }
        }

        // Clique no fundo do cartão não chega à captura de fora.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        // Conteúdo no layout final, preso ao canto de cima e recortado.
        Item {
            id: content

            property real blurPx: 0

            width: 470
            height: priv.boxCardH
            opacity: 0
            enabled: priv.sub !== "" && !priv.closing
            layer.enabled: content.opacity > 0 && content.opacity < 1 && content.blurPx > 0.05
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 16
                blur: content.blurPx / 16
            }

            SoundPage {
                id: soundPage
                visible: priv.shownSub === "sound"
                width: 470
                height: root.cardHeightFor(soundPage)
                island: root.island
                theme: root.theme
                strings: root.strings
                keyboardMode: root.keyboardMode
                maxHeight: root.maxHeight - 42
                onBack: root.closeSub()
            }
            DisplayPage {
                id: displayPage
                visible: priv.shownSub === "display"
                width: 470
                height: root.cardHeightFor(displayPage)
                island: root.island
                theme: root.theme
                strings: root.strings
                keyboardMode: root.keyboardMode
                maxHeight: root.maxHeight - 42
                onBack: root.closeSub()
            }
            IlhaPage {
                id: ilhaPage
                visible: priv.shownSub === "ilha"
                width: 470
                height: root.cardHeightFor(ilhaPage)
                island: root.island
                theme: root.theme
                strings: root.strings
                keyboardMode: root.keyboardMode
                maxHeight: root.maxHeight - 42
                prefs: root.island ? root.island.prefs : null
                onBack: root.closeSub()
            }
            WifiCard {
                id: wifiCard
                visible: priv.shownSub === "wifi"
                width: 470
                height: root.cardHeightFor(wifiCard)
                island: root.island
                theme: root.theme
                strings: root.strings
                keyboardMode: root.keyboardMode
                maxHeight: root.maxHeight - 42
                onBack: root.closeSub()
            }
            BluetoothCard {
                id: btCard
                visible: priv.shownSub === "bluetooth"
                width: 470
                height: root.cardHeightFor(btCard)
                island: root.island
                theme: root.theme
                strings: root.strings
                keyboardMode: root.keyboardMode
                maxHeight: root.maxHeight - 42
                onBack: root.closeSub()
            }
        }
    }
}
