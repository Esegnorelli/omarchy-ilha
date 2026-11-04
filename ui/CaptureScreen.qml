pragma ComponentBehavior: Bound

import QtQuick
import "Motion.js" as Motion

// Captura (screens: "capture"): o menu Captura do Omarchy na ilha. Dono:
// agente da Captura. Painel 514 x 236 (theme.screenSize("capture")), cap 30,
// um fade só (como a Energia).
//
//   fileira  y 15..97    cinco botões de 90,8 x 82, vão 7,5, raio 22,5 (as
//                        medidas da Energia): Captura de tela · Gravar tela ·
//                        Texto · Código QR · Cor (a ordem do menu do Omarchy)
//   faixa    y 109..221  as opções do botão escolhido: até quatro de 238 x 52
//                        (2 x 2, vão 8, raio 22,5); com três, a de baixo ocupa
//                        a largura toda; com uma, a faixa inteira.
//     Captura de tela  Região · Janela · Tela inteira
//     Gravar tela      Sem áudio · Com áudio da área de trabalho · … + microfone
//                      · … + webcam (apagada sem webcam: omarchy-hw-webcam)
//                      Gravando: um cartão só, "Gravando 0:42", que para.
//     Texto, QR, Cor   não têm modos; a faixa traz os extras: Compartilhar a
//                      área de transferência, um arquivo ou uma pasta, e o
//                      Histórico da área de transferência.
//
// - Uma seleção só (accent), como na Energia. Na fileira ela desliza entre os
//   botões (160 ms OutCubic; salta com snapping) e o conteúdo segue quanto a
//   seleção o cobre (ink -> onAccent). Na faixa, a opção escolhida fica
//   accent e o botão dono da faixa fica raised (marca de quem são as opções).
// - A faixa troca de dono com um fade (50 ms some, troca, 110 ms volta).
// - Ações (todas fecham a ilha e rodam CLOSE_THEN_RUN_MS depois, num processo
//   à parte, os comandos do menu do Omarchy; CaptureSvc.run):
//     Captura de tela    omarchy-capture-screenshot (inteligente: arrasta uma
//                        região, clica numa janela ou fora delas para a tela)
//     Região / Janela / Tela inteira
//                        omarchy-capture-screenshot region | windows | fullscreen
//     Gravar tela        não grava: desce para os modos (no Omarchy é um submenu)
//     Sem áudio          omarchy-capture-screenrecording
//     Área de trabalho   omarchy-capture-screenrecording --with-desktop-audio
//     + microfone        … --with-desktop-audio --with-microphone-audio
//     + webcam           omarchy-capture-screenrecording-with-webcam
//     Parar (gravando)   omarchy-capture-screenrecording --stop-recording (o do StatusSvc)
//     Texto              omarchy-capture-text
//     Código QR          omarchy-capture-qr
//     Cor                sh -c 'pkill hyprpicker || hyprpicker -a'
//     Compartilhar       omarchy-menu-share clipboard | file | folder
//     Histórico          omarchy-shell shell summon omarchy.clipboard
//   ILHA_DEV=1 (harness): só registra no log, nunca executa.
// - Gravando (island.status.recording): o 2º botão vira "Parar gravação",
//   com o stop_circle e o tempo (status.recordingClock) em danger, e a ilha
//   abre com ele escolhido, para Enter parar.
// - Teclas: Esquerda/Direita pela tela (no RTL a Direita vai para o índice
//   menor), Baixo entra na faixa (a opção mais perto do botão), Cima volta,
//   Tab/Shift+Tab dão a volta na fileira em que a seleção está, Home/End,
//   1..5 (ativa o botão), Enter/Espaço ativa, Esc fecha.
// - Mouse: o hover escolhe (só com o ponteiro andando, como na Energia). Na
//   fileira, um ponteiro descendo em direção à faixa só troca o dono se
//   ainda estiver sobre o botão 140 ms depois: atravessar outro botão no
//   caminho até uma opção não troca a faixa. O clique ativa.
// - Rótulos: os do menu do Omarchy (trigger.capture.*, trigger.share.*,
//   trigger.clipboard-history), lidos pelo CaptureSvc no idioma da Ilha;
//   "Parar gravação" é o bar.stopRecording do shell (Commons.I18n). Região,
//   Janela e Tela inteira são chaves da Ilha (capture.*).
// - Textos longos: quebram (no meio da palavra só se ela não couber) e o Fit
//   encolhe até 10 px antes de cortar com reticências.
// - RTL: as posições espelham à mão (como a Energia); dentro de cada opção,
//   as âncoras seguem o LayoutMirroring da janela.
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
    property list<Item> headerItems
    property list<Item> bodyItems
    signal navigate(string id, var payload)
    signal closeRequested()

    readonly property var dims: root.theme && root.island ? root.theme.screenSize("capture", root.island.screenGeometry(root.island.screenOutput)) : ({ w: 514, h: 236, k: 0 })
    implicitWidth: root.dims.w
    implicitHeight: root.dims.h

    // ---- Medidas ----
    readonly property real pad: 15
    readonly property real gap: 7.5
    readonly property real btnW: (root.implicitWidth - 2 * root.pad - 4 * root.gap) / 5
    readonly property real btnH: 82
    readonly property real btnRadius: 22.5
    readonly property real pitch: root.btnW + root.gap
    // Rótulo do botão (as medidas da Energia): largura útil, linha de base com
    // 1 linha, quanto tudo sobe com 2 e a caixa de 2 linhas do Fit.
    readonly property real labelW: root.btnW - 12
    readonly property real labelBase: 57.3
    readonly property real wrapLift: 6
    readonly property real labelBox: 30
    readonly property real iconCenter: 31
    // Faixa das opções.
    readonly property real bandTop: root.pad + root.btnH + 12
    readonly property real bandH: root.implicitHeight - root.pad - root.bandTop
    readonly property real cellGap: 8
    readonly property real cellH: (root.bandH - root.cellGap) / 2
    readonly property real cellRadius: 22.5
    // Ponteiro descendo para a faixa: espera parada antes de trocar o dono.
    readonly property int ownerDwellMs: 140

    readonly property bool rtl: !!root.theme && root.theme.rtl
    readonly property bool reduce: !root.theme || root.theme.reduceMotion
    readonly property var status: root.island ? root.island.status : null
    readonly property bool recording: !!root.status && root.status.recording === true
    readonly property string recordingText: !root.recording || !root.strings ? ""
        : (root.status.recordingSeconds >= 0 ? root.strings.t("bar.recording").arg(root.status.recordingClock) : root.strings.t("bar.recordingNow"))

    CaptureSvc {
        id: svc
        onWebcamOkChanged: root.validate()
    }

    function menu(key, fallback) {
        return svc.label(key, fallback);
    }

    function t(key, fallback) {
        return root.strings ? root.strings.t(key, fallback) : String(fallback || key);
    }

    // ---- O que cada botão e cada opção faz ----
    // Os comandos são os do menu do Omarchy (default/omarchy/omarchy-menu.jsonc).
    readonly property var mains: [
        { id: "screenshot", icon: "photo_camera", label: root.menu("trigger.capture.screenshot", "Screenshot"), command: ["omarchy-capture-screenshot"] },
        { id: "record", icon: "fiber_manual_record", label: root.menu("trigger.capture.screenrecord", "Screenrecord"), command: [] },
        { id: "text", icon: "text_fields", label: root.menu("trigger.capture.text", "Text"), command: ["omarchy-capture-text"] },
        { id: "qr", icon: "qr_code_scanner", label: root.menu("trigger.capture.qr", "QR Code"), command: ["omarchy-capture-qr"] },
        { id: "color", icon: "colorize", label: root.menu("trigger.capture.color", "Color"), command: ["sh", "-c", "pkill hyprpicker || hyprpicker -a"] }
    ]

    readonly property var shotModes: [
        { id: "region", icon: "screenshot_region", title: root.t("capture.region", "Region"), subtitle: "", webcam: false, command: ["omarchy-capture-screenshot", "region"] },
        { id: "window", icon: "select_window", title: root.t("capture.window", "Window"), subtitle: "", webcam: false, command: ["omarchy-capture-screenshot", "windows"] },
        { id: "fullscreen", icon: "screenshot_monitor", title: root.t("capture.fullscreen", "Full screen"), subtitle: "", webcam: false, command: ["omarchy-capture-screenshot", "fullscreen"] }
    ]

    readonly property var recModes: [
        { id: "rec-no-audio", icon: "volume_off", title: root.menu("trigger.capture.screenrecord.no-audio", "With no audio"), subtitle: "", webcam: false, command: ["omarchy-capture-screenrecording"] },
        { id: "rec-desktop-audio", icon: "volume_up", title: root.menu("trigger.capture.screenrecord.desktop-audio", "With desktop audio"), subtitle: "", webcam: false, command: ["omarchy-capture-screenrecording", "--with-desktop-audio"] },
        { id: "rec-microphone", icon: "mic", title: root.menu("trigger.capture.screenrecord.microphone", "With desktop + microphone audio"), subtitle: "", webcam: false, command: ["omarchy-capture-screenrecording", "--with-desktop-audio", "--with-microphone-audio"] },
        { id: "rec-webcam", icon: "videocam", title: root.menu("trigger.capture.screenrecord.webcam", "With desktop + microphone audio + webcam"), subtitle: "", webcam: true, command: ["omarchy-capture-screenrecording-with-webcam"] }
    ]

    // Gravando: o título é o tempo (recordingText, no próprio cartão).
    readonly property var stopItems: [
        { id: "stop", icon: "fiber_manual_record", title: "", subtitle: root.menu("trigger.capture.screenrecord.stop", "Stop Screenrecording"), webcam: false, command: ["omarchy-capture-screenrecording", "--stop-recording"] }
    ]

    readonly property var extras: [
        { id: "share-clipboard", icon: "share", title: root.menu("trigger.share.clipboard", "Clipboard"), subtitle: root.menu("trigger.share", "Share"), webcam: false, command: ["omarchy-menu-share", "clipboard"] },
        { id: "share-file", icon: "share", title: root.menu("trigger.share.file", "File"), subtitle: root.menu("trigger.share", "Share"), webcam: false, command: ["omarchy-menu-share", "file"] },
        { id: "share-folder", icon: "share", title: root.menu("trigger.share.folder", "Folder"), subtitle: root.menu("trigger.share", "Share"), webcam: false, command: ["omarchy-menu-share", "folder"] },
        { id: "clipboard-history", icon: "history", title: root.menu("trigger.clipboard-history", "Clipboard History"), subtitle: "", webcam: false, command: ["omarchy-shell", "shell", "summon", "omarchy.clipboard"] }
    ]

    function itemsFor(owner) {
        if (owner === 0)
            return root.shotModes;
        if (owner === 1)
            return root.recording ? root.stopItems : root.recModes;
        return root.extras;
    }

    // As opções que a faixa mostra agora (seguem o dono com o fade).
    readonly property var shownItems: root.itemsFor(priv.shownOwner)

    function usable(entry) {
        return !!entry && (!entry.webcam || svc.webcamOk);
    }

    // ---- Geometria (sistema da tela; espelhada no RTL) ----

    function slotX(i) {
        const x = root.pad + i * root.pitch;
        return root.rtl ? root.implicitWidth - x - root.btnW : x;
    }

    // Opção i de n: até 2 linhas; a de cima leva ceil(n/2) opções e cada
    // linha divide a largura toda. Uma opção só ocupa a faixa inteira.
    function cellRect(i, n) {
        const fullW = root.implicitWidth - 2 * root.pad;
        let x = root.pad, y = root.bandTop, w = fullW, h = root.bandH;
        if (n > 1) {
            const top = Math.ceil(n / 2);
            const rowIdx = i < top ? 0 : 1;
            const cols = rowIdx === 0 ? top : n - top;
            const col = rowIdx === 0 ? i : i - top;
            w = (fullW - (cols - 1) * root.cellGap) / cols;
            h = root.cellH;
            x = root.pad + col * (w + root.cellGap);
            y = root.bandTop + rowIdx * (root.cellH + root.cellGap);
        }
        return { x: root.rtl ? root.implicitWidth - x - w : x, y: y, w: w, h: h };
    }

    // O que está sob o ponto: {row: 0 | 1, i} ou null.
    function hitAt(px, py) {
        if (py >= root.pad && py <= root.pad + root.btnH) {
            for (let i = 0; i < root.mains.length; i++) {
                const bx = root.slotX(i);
                if (px >= bx && px <= bx + root.btnW)
                    return { row: 0, i: i };
            }
            return null;
        }
        const items = root.shownItems;
        for (let j = 0; j < items.length; j++) {
            const r = root.cellRect(j, items.length);
            if (px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h)
                return { row: 1, i: j };
        }
        return null;
    }

    // ---- Contrato: abrir / fechar / teclas ----

    function opened(payload) {
        root.snapping = true;
        dwell.stop();
        priv.pending = -1;
        priv.sticky = -1;
        priv.pressed = -1;
        priv.pressedCell = -1;
        priv.lastPoint = Qt.point(-1, -1);
        priv.trail = [];
        priv.row = 0;
        priv.cell = 0;
        // Gravando: abre no Parar, para Enter parar a gravação.
        priv.owner = root.recording ? 1 : 0;
        root.syncBand();
        svc.probe();
        Qt.callLater(() => root.snapping = false);
    }

    function closed() {
        dwell.stop();
        bandSwap.stop();
        priv.pending = -1;
        priv.sticky = -1;
        priv.pressed = -1;
        priv.pressedCell = -1;
        priv.lastPoint = Qt.point(-1, -1);
        priv.trail = [];
    }

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods !== 0)
            return false;
        const k = event.key;
        switch (k) {
        case Qt.Key_Right:
        case Qt.Key_Left: {
            const dx = k === Qt.Key_Right ? 1 : -1;
            if (priv.row === 0)
                root.mainMove(dx);
            else
                root.bandMove(dx, 0);
            return true;
        }
        case Qt.Key_Down:
            if (priv.row === 0)
                root.enterBand();
            else
                root.bandMove(0, 1);
            return true;
        case Qt.Key_Up:
            if (priv.row === 1)
                root.bandMove(0, -1);
            return true;
        case Qt.Key_Tab:
            root.cycle((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
            return true;
        case Qt.Key_Backtab:
            root.cycle(-1);
            return true;
        case Qt.Key_Home:
        case Qt.Key_End:
            root.edge(k === Qt.Key_Home);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (!event.isAutoRepeat)
                root.activateCurrent();
            return true;
        default:
            break;
        }
        if (k >= Qt.Key_1 && k <= Qt.Key_5) {
            if (!event.isAutoRepeat)
                root.activateMain(k - Qt.Key_1);
            return true;
        }
        return false;
    }

    // Esc fecha a janela (nada a desarmar aqui).
    function handleEscape() {
        return false;
    }

    // ---- Seleção ----

    function selectMain(i) {
        if (i < 0 || i >= root.mains.length)
            return;
        priv.owner = i;
        priv.row = 0;
    }

    // Esquerda/Direita pela tela: no RTL a Direita vai para o índice menor.
    function mainMove(dx) {
        root.selectMain(priv.owner + (root.rtl ? -dx : dx));
    }

    // A faixa mostra já as opções do dono (corta o fade no meio).
    function syncBand() {
        bandSwap.stop();
        band.opacity = 1;
        priv.shownOwner = priv.owner;
    }

    function swapBand() {
        if (priv.shownOwner === priv.owner)
            return;
        if (root.snapping || root.reduce || priv.row === 1)
            root.syncBand();
        else
            bandSwap.restart();
    }

    function selectCell(i) {
        root.syncBand();
        const items = root.itemsFor(priv.owner);
        if (i < 0 || i >= items.length || !root.usable(items[i]))
            return;
        priv.cell = i;
        priv.row = 1;
    }

    // Baixo na fileira: a opção da linha de cima mais perto do botão.
    function enterBand() {
        const items = root.itemsFor(priv.owner);
        const ox = root.slotX(priv.owner) + root.btnW / 2;
        let best = -1, bestKey = Infinity;
        for (let i = 0; i < items.length; i++) {
            if (!root.usable(items[i]))
                continue;
            const r = root.cellRect(i, items.length);
            const key = r.y * 10000 + Math.abs(r.x + r.w / 2 - ox);
            if (key < bestKey) {
                bestKey = key;
                best = i;
            }
        }
        if (best >= 0)
            root.selectCell(best);
        return best >= 0;
    }

    // Anda na faixa pela tela (dx na mesma linha, dy entre as linhas). Cima
    // na linha de cima volta para a fileira.
    function bandMove(dx, dy) {
        const items = root.itemsFor(priv.owner);
        const n = items.length;
        const c = root.cellRect(priv.cell, n);
        const cx = c.x + c.w / 2, cy = c.y + c.h / 2;
        let best = -1, bestKey = Infinity;
        for (let i = 0; i < n; i++) {
            if (i === priv.cell || !root.usable(items[i]))
                continue;
            const r = root.cellRect(i, n);
            const rx = r.x + r.w / 2, ry = r.y + r.h / 2;
            let key;
            if (dx !== 0) {
                if (Math.abs(ry - cy) > 1 || (rx - cx) * dx <= 0)
                    continue;
                key = Math.abs(rx - cx);
            } else {
                if ((ry - cy) * dy <= 0)
                    continue;
                key = Math.abs(ry - cy) * 10000 + Math.abs(rx - cx);
            }
            if (key < bestKey) {
                bestKey = key;
                best = i;
            }
        }
        if (best >= 0)
            root.selectCell(best);
        else if (dy < 0)
            priv.row = 0;
    }

    // Tab dá a volta na fileira em que a seleção está.
    function cycle(delta) {
        if (priv.row === 0) {
            const n = root.mains.length;
            root.selectMain(((priv.owner + delta) % n + n) % n);
            return;
        }
        const items = root.itemsFor(priv.owner);
        const n = items.length;
        for (let step = 1; step <= n; step++) {
            const i = ((priv.cell + delta * step) % n + n) % n;
            if (root.usable(items[i])) {
                root.selectCell(i);
                return;
            }
        }
    }

    // Home/End: o primeiro / o último da fileira em que a seleção está.
    function edge(first) {
        if (priv.row === 0) {
            root.selectMain(first ? 0 : root.mains.length - 1);
            return;
        }
        const items = root.itemsFor(priv.owner);
        for (let s = 0; s < items.length; s++) {
            const i = first ? s : items.length - 1 - s;
            if (root.usable(items[i])) {
                root.selectCell(i);
                return;
            }
        }
    }

    // A gravação começou ou parou, ou a webcam sumiu, com a seleção na faixa.
    function validate() {
        if (priv.row !== 1)
            return;
        const items = root.itemsFor(priv.owner);
        if (priv.cell < items.length && root.usable(items[priv.cell]))
            return;
        if (!root.enterBand())
            priv.row = 0;
    }

    onRecordingChanged: root.validate()

    // ---- Ações ----

    function activateCurrent() {
        if (priv.row === 1)
            root.activateCell(priv.cell);
        else
            root.activateMain(priv.owner);
    }

    function activateMain(i) {
        const m = root.mains[i];
        if (!m)
            return;
        dwell.stop();
        priv.pending = -1;
        root.selectMain(i);
        if (m.id === "record") {
            if (root.recording) {
                root.run(root.stopItems[0]);
                return;
            }
            // Como no menu do Omarchy, Gravar tela não grava: escolhe-se o modo.
            root.syncBand();
            root.enterBand();
            return;
        }
        root.run(m);
    }

    function activateCell(i) {
        const items = root.itemsFor(priv.owner);
        const entry = items[i];
        if (!root.usable(entry))
            return;
        root.selectCell(i);
        root.run(entry);
    }

    // Fecha a ilha e só depois executa (CaptureSvc.run: CLOSE_THEN_RUN_MS).
    function run(entry) {
        dwell.stop();
        root.closeRequested();
        svc.run(entry.id, entry.command);
    }

    // ---- Ponteiro ----

    // O ponteiro andou (posição no sistema da tela).
    function pointerMoved(p) {
        const last = priv.lastPoint;
        if (Math.abs(p.x - last.x) < 0.5 && Math.abs(p.y - last.y) < 0.5)
            return;
        const first = last.x < 0;
        priv.lastPoint = p;
        const trail = priv.trail.slice(-3);
        trail.push({ x: p.x, y: p.y });
        priv.trail = trail;
        if (first)
            return;
        const hit = root.hitAt(p.x, p.y);
        if (!hit || hit.row !== 0 || hit.i !== priv.sticky)
            priv.sticky = -1;
        if (!hit) {
            dwell.stop();
            priv.pending = -1;
            return;
        }
        if (hit.row === 1) {
            dwell.stop();
            priv.pending = -1;
            root.selectCell(hit.i);
            return;
        }
        if (hit.i === priv.sticky)
            return;
        if (hit.i === priv.owner || !root.headingDown()) {
            dwell.stop();
            priv.pending = -1;
            root.selectMain(hit.i);
            return;
        }
        if (priv.pending !== hit.i) {
            priv.pending = hit.i;
            dwell.restart();
        }
    }

    // Os últimos passos do ponteiro descem (em direção à faixa)?
    function headingDown() {
        const tr = priv.trail;
        if (tr.length < 2)
            return false;
        const dx = tr[tr.length - 1].x - tr[0].x;
        const dy = tr[tr.length - 1].y - tr[0].y;
        return dy > 0 && dy >= 0.15 * Math.abs(dx);
    }

    QtObject {
        id: priv
        // Botão dono da faixa (e escolhido na fileira).
        property int owner: 0
        // O dono cujas opções a faixa mostra (atrasa no fade).
        property int shownOwner: 0
        // 0 = fileira, 1 = faixa.
        property int row: 0
        property int cell: 0
        property int pressed: -1
        property int pressedCell: -1
        // Botão à espera do tempo parado (ponteiro descendo).
        property int pending: -1
        // Botão clicado que mandou a seleção para a faixa: o tremor do
        // ponteiro sobre ele não a traz de volta.
        property int sticky: -1
        property point lastPoint: Qt.point(-1, -1)
        property var trail: []

        onOwnerChanged: root.swapBand()
    }

    Timer {
        id: dwell
        interval: root.ownerDwellMs
        onTriggered: {
            const p = priv.lastPoint;
            const hit = root.hitAt(p.x, p.y);
            if (hit && hit.row === 0 && hit.i === priv.pending)
                root.selectMain(hit.i);
            priv.pending = -1;
        }
    }

    // A faixa troca de dono: some, troca, volta (sempre da opacidade atual).
    SequentialAnimation {
        id: bandSwap
        NumberAnimation {
            target: band
            property: "opacity"
            to: 0
            duration: Motion.FADE.SWAP_OUT.dur
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: priv.shownOwner = priv.owner
        }
        NumberAnimation {
            target: band
            property: "opacity"
            to: 1
            duration: Motion.FADE.HOVER
            easing.type: Easing.OutCubic
        }
    }

    Accessible.role: Accessible.Grouping
    Accessible.name: root.menu("trigger.capture", "Capture")

    // ---- Fileira: fundos dos botões ----
    Repeater {
        model: root.mains

        Rectangle {
            id: plate
            required property int index
            x: root.slotX(plate.index)
            y: root.pad
            width: root.btnW
            height: root.btnH
            radius: root.btnRadius
            color: root.theme ? root.theme.card : "transparent"
            scale: priv.pressed === plate.index ? 0.97 : 1
            Behavior on scale {
                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
            }
        }
    }

    // ---- Fileira: a seleção (uma só, desliza) ----
    Rectangle {
        id: selection
        // 1 = a seleção está na fileira (accent); 0 = na faixa (só marca o dono).
        property real lit: priv.row === 0 ? 1 : 0
        Behavior on lit {
            enabled: !root.snapping
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
        }
        x: root.slotX(priv.owner)
        y: root.pad
        width: root.btnW
        height: root.btnH
        radius: root.btnRadius
        color: root.theme ? root.theme.mix(root.theme.raised, root.theme.accent, selection.lit) : "white"
        scale: priv.pressed >= 0 && priv.pressed === priv.owner ? 0.97 : 1
        Behavior on x {
            enabled: !root.snapping
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.POWER_SELECT) : 0; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
        }
    }

    // ---- Fileira: conteúdo dos botões (ícone, rótulo) e toques ----
    Repeater {
        model: root.mains

        Item {
            id: btn
            required property var modelData
            required property int index
            // Ponteiro neste botão. priv.owner é a seleção, não o hover.
            HoverHandler { id: btnHover }
            readonly property bool labelShown: btn.stopHere
                || btnHover.hovered
                || (root.keyboardMode && priv.row === 0 && priv.owner === btn.index)

            readonly property bool stopHere: btn.modelData.id === "record" && root.recording
            // Quanto a seleção accent cobre este botão (0..1): a cor segue o deslize.
            readonly property real cover: Math.max(0, 1 - Math.abs(selection.x - btn.x) / root.pitch) * selection.lit
            readonly property color ink: root.theme ? root.theme.mix(root.theme.ink, root.theme.onAccent, btn.cover) : "white"
            readonly property color glyphInk: root.theme ? root.theme.mix(btn.stopHere ? root.theme.danger : root.theme.ink, root.theme.onAccent, btn.cover) : "white"
            // Gravando: o tempo ao lado do Parar ("0:42"; vazio sem a hora do início).
            readonly property string clock: btn.stopHere && root.status ? String(root.status.recordingClock || "") : ""
            // Ícone (e tempo) centrados juntos na linha do ícone.
            readonly property real headW: btn.clock !== "" ? glyph.width + 4 + clockText.implicitWidth : glyph.width
            readonly property real headX: (btn.width - btn.headW) / 2
            readonly property real headY: root.iconCenter - (label.lineCount > 1 ? root.wrapLift : 0)

            x: root.slotX(btn.index)
            y: root.pad
            width: root.btnW
            height: root.btnH
            scale: priv.pressed === btn.index ? 0.97 : 1
            Behavior on scale {
                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
            }

            Accessible.role: Accessible.Button
            Accessible.name: label.text
            Accessible.description: btn.stopHere ? root.recordingText : ""
            Accessible.focusable: true
            Accessible.focused: priv.row === 0 && priv.owner === btn.index
            Accessible.onPressAction: root.activateMain(btn.index)

            Icon {
                id: glyph
                x: root.rtl ? btn.headX + btn.headW - glyph.width : btn.headX
                y: btn.headY - glyph.height / 2
                name: btn.stopHere ? "stop_circle" : btn.modelData.icon
                // O ponto de gravar é cheio (o REC); o Parar também.
                filled: btn.stopHere || btn.modelData.id === "record"
                size: btn.clock !== "" ? 16 : 20
                color: btn.glyphInk
                Behavior on y {
                    NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
                }
            }

            IlhaText {
                id: clockText
                visible: btn.clock !== ""
                x: root.rtl ? btn.headX : btn.headX + glyph.width + 4
                y: btn.headY - clockText.height / 2
                theme: root.theme
                size: 13
                weight: 600
                tnum: true
                color: btn.glyphInk
                text: btn.clock
            }

            IlhaText {
                id: label
                x: (btn.width - label.width) / 2
                y: root.labelBase - (label.lineCount > 1 ? root.wrapLift : 0) - label.baselineOffset
                width: root.labelW
                height: root.labelBox
                theme: root.theme
                size: 11
                weight: 600
                color: btn.ink
                horizontalAlignment: Text.AlignHCenter
                // Quebra nas palavras (e no meio de uma palavra comprida, como
                // "Bildschirmaufnahme"); só encolhe (até 10) se ainda não couber
                // na caixa de 2 linhas. Sem maximumLineCount: com ele o Qt corta
                // na 2ª linha em vez de encolher.
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                fontSizeMode: Text.Fit
                minimumPixelSize: 10
                text: btn.stopHere ? svc.shellLabel("bar.stopRecording", "Stop recording") : btn.modelData.label
                readonly property bool reveal: btn.labelShown
                opacity: reveal ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.theme ? root.theme.dur(reveal ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                        easing.type: Easing.OutCubic
                    }
                }
            }

            TapHandler {
                id: tap
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onPressedChanged: priv.pressed = tap.pressed ? btn.index : (priv.pressed === btn.index ? -1 : priv.pressed)
                onTapped: {
                    root.activateMain(btn.index);
                    // Gravar tela mandou a seleção para a faixa: o tremor do
                    // ponteiro sobre o botão não a traz de volta.
                    if (priv.row === 1)
                        priv.sticky = btn.index;
                }
            }
        }
    }

    // ---- Faixa: as opções do botão escolhido ----
    Item {
        id: band
        anchors.fill: parent

        Repeater {
            // No máximo quatro opções; os itens não são recriados a cada troca.
            model: 4

            Item {
                id: cell
                required property int index

                readonly property var entry: cell.index < root.shownItems.length ? root.shownItems[cell.index] : null
                readonly property var box: root.cellRect(cell.index, root.shownItems.length)
                readonly property bool isStop: !!cell.entry && cell.entry.id === "stop"
                readonly property bool usable: root.usable(cell.entry)
                readonly property bool chosen: priv.row === 1 && priv.cell === cell.index && priv.shownOwner === priv.owner
                // O cartão de gravando, que ocupa a faixa inteira.
                readonly property bool big: cell.box.h > root.cellH + 1
                readonly property string title: cell.isStop ? root.recordingText : (cell.entry ? cell.entry.title : "")
                readonly property string subtitle: cell.entry ? cell.entry.subtitle : ""
                readonly property color ink: !root.theme ? "white" : (cell.chosen ? root.theme.onAccent : root.theme.ink)

                visible: cell.entry !== null
                x: cell.box.x
                y: cell.box.y
                width: cell.box.w
                height: cell.box.h
                scale: priv.pressedCell === cell.index ? 0.97 : 1
                Behavior on scale {
                    NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
                }

                Accessible.role: Accessible.Button
                Accessible.name: cell.title
                Accessible.description: !cell.usable && root.strings ? root.strings.t("cc.unavailable") : cell.subtitle
                Accessible.focusable: cell.usable
                Accessible.focused: cell.chosen
                Accessible.onPressAction: root.activateCell(cell.index)

                Rectangle {
                    anchors.fill: parent
                    radius: root.cellRadius
                    color: !root.theme ? "transparent" : (cell.chosen ? root.theme.accent : root.theme.card)
                    Behavior on color {
                        enabled: !root.snapping
                        ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                    }
                }

                Item {
                    anchors.fill: parent
                    opacity: cell.usable ? 1 : 0.4

                    Rectangle {
                        id: disc
                        readonly property real d: cell.big ? 52 : 36
                        width: disc.d
                        height: disc.d
                        radius: disc.d / 2
                        anchors.left: parent.left
                        anchors.leftMargin: cell.big ? 30 : 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: !root.theme ? "transparent" : (cell.chosen ? root.theme.mix(root.theme.accent, root.theme.onAccent, 0.16) : root.theme.iconIdle)
                        Behavior on color {
                            enabled: !root.snapping
                            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                        }

                        Icon {
                            id: cellGlyph
                            anchors.centerIn: parent
                            name: cell.entry ? cell.entry.icon : ""
                            size: cell.big ? 22 : 16
                            filled: cell.isStop
                            color: !root.theme ? "white" : (cell.isStop && !cell.chosen ? root.theme.danger : cell.ink)
                        }

                        // Gravando: o ponto pulsa 1 <-> 0,45 em 1200 ms (InOutSine), como na barra.
                        SequentialAnimation {
                            id: pulse
                            running: cell.isStop && root.current && root.recording && !root.reduce
                            loops: Animation.Infinite
                            onRunningChanged: if (!pulse.running) cellGlyph.opacity = 1
                            NumberAnimation {
                                target: cellGlyph
                                property: "opacity"
                                to: Motion.FADE.DOT_PULSE.low
                                duration: Motion.FADE.DOT_PULSE.dur / 2
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                target: cellGlyph
                                property: "opacity"
                                to: 1
                                duration: Motion.FADE.DOT_PULSE.dur / 2
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    Column {
                        anchors.left: disc.right
                        anchors.leftMargin: cell.big ? 16 : 10
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: cell.big ? 4 : 1

                        IlhaText {
                            id: cellTitle
                            readonly property bool solo: cell.subtitle === ""
                            width: parent.width
                            // Com subtítulo: uma linha na altura natural da fonte (as
                            // escritas altas, como o árabe, caem numa fonte de linha
                            // maior). Sozinho: quebra numa caixa da altura da opção e o
                            // Fit encolhe até 10 antes de cortar (sem maximumLineCount:
                            // com ele o Qt corta na 2ª linha em vez de encolher).
                            // (undefined volta à altura implícita, sem laço com implicitHeight.)
                            height: cellTitle.solo ? cell.height - 10 : undefined
                            theme: root.theme
                            size: cell.big ? 17 : 13
                            weight: 600
                            tnum: cell.isStop
                            color: cell.ink
                            horizontalAlignment: Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: cellTitle.solo ? Text.Wrap : Text.NoWrap
                            elide: Text.ElideRight
                            fontSizeMode: cellTitle.solo ? Text.Fit : Text.FixedSize
                            minimumPixelSize: 10
                            text: cell.title
                        }

                        IlhaText {
                            width: parent.width
                            visible: cell.subtitle !== ""
                            theme: root.theme
                            size: cell.big ? 12.5 : 11
                            weight: 500
                            color: !root.theme ? "gray" : (cell.chosen ? root.theme.alpha(root.theme.onAccent, 0.72) : root.theme.inkMuted)
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                            text: cell.subtitle
                        }
                    }
                }

                TapHandler {
                    id: cellTap
                    enabled: cell.usable && cell.visible
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onPressedChanged: priv.pressedCell = cellTap.pressed ? cell.index : (priv.pressedCell === cell.index ? -1 : priv.pressedCell)
                    onTapped: root.activateCell(cell.index)
                }
            }
        }
    }

    // Hover: só o movimento real do ponteiro troca a seleção.
    HoverHandler {
        id: hover
        cursorShape: {
            const hit = root.hitAt(hover.point.position.x, hover.point.position.y);
            if (!hit)
                return Qt.ArrowCursor;
            if (hit.row === 0)
                return Qt.PointingHandCursor;
            return root.usable(root.shownItems[hit.i]) ? Qt.PointingHandCursor : Qt.ArrowCursor;
        }
        onPointChanged: {
            if (hover.hovered)
                root.pointerMoved(hover.point.position);
        }
        onHoveredChanged: {
            if (!hover.hovered) {
                priv.lastPoint = Qt.point(-1, -1);
                priv.trail = [];
                priv.sticky = -1;
                dwell.stop();
                priv.pending = -1;
            }
        }
    }
}
