pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "Motion.js" as Motion

// Menu de energia (screens §11; estudo "power"). Dono: Agent F.
//
// Painel 514 x 112, cap 30, folga 15. Cinco botões de 90,8 x 82 (vão 7,5,
// raio 22,5, fill card): Bloquear, Suspender, Sair, Reiniciar, Desligar.
// Um fade só (motion F): o conteúdo fica no layout final.
//
// - Uma seleção accent só, que desliza entre os botões (x em 160 ms OutCubic;
//   salta com snapping). A cor do conteúdo de cada botão segue quanto a
//   seleção o cobre (ink -> onAccent), então nunca há texto escuro sobre o
//   card no meio do deslize. Bloquear começa selecionado.
// - Ícone 20 com o centro em y 31 (tinta de 23 a 39); rótulo com a linha de
//   base em 57,3. O rótulo quebra em até 2 linhas, centrado; quando quebra,
//   o ícone sobe 6. Último recurso: encolhe até 10 px (Fit numa caixa de
//   2 linhas, quebrando só nas palavras). Tamanho 11/600:
//   é o que bate com as larguras do vídeo ("Power Off" 53 px, "Reboot" 38,
//   "Suspend" 48; a Inter é mais larga que a fonte dele).
// - Sair, Reiniciar e Desligar pedem um 2º toque em 3 s: o rótulo vira
//   "Toque de novo" e um anel accent pulsa em volta do botão. Um 2º toque com
//   menos de 350 ms é ignorado (clique duplo não desliga a máquina). Trocar a
//   seleção, Esc ou fechar desarma.
// - Suspender fica apagado (0,4) e fora da navegação quando o Omarchy
//   desligou o sono (toggle suspend-off ou omarchy-sleep-disabled; a mesma
//   condição do menu do Omarchy). Conferido a cada opened().
// - Mouse: o hover seleciona (só com o ponteiro andando: um ponteiro parado
//   sob o painel que abre não tira a seleção do Bloquear); o clique ativa.
//   Teclas: Left/Right (pela direção da tela), Tab/Shift+Tab (dão a volta),
//   Home/End, 1..5 (seleciona e ativa), Enter/Espaço, Esc.
// - Os comandos rodam 180 ms depois de fechar (a ação nunca aparece por
//   trás da ilha), num processo à parte, os mesmos do menu do Omarchy:
//   omarchy-system-lock, systemctl suspend, omarchy-system logout | reboot |
//   shutdown. ILHA_DEV=1 (harness): só registra no log, nunca executa.
// - RTL: a fileira espelha (Bloquear à direita), a seta do Sair também;
//   Left/Right seguem a tela.
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

    implicitWidth: 514
    implicitHeight: 112

    // ---- Medidas ----
    readonly property real pad: 15
    readonly property real gap: 7.5
    readonly property real btnW: (root.implicitWidth - 2 * root.pad - 4 * root.gap) / 5
    readonly property real btnH: 82
    readonly property real btnRadius: 22.5
    readonly property real pitch: root.btnW + root.gap
    // Rótulo: largura útil, linha de base (1 linha) e o quanto tudo sobe com 2.
    readonly property real labelW: root.btnW - 12
    readonly property real labelBase: 57.3
    readonly property real wrapLift: 6
    // Caixa de 2 linhas do rótulo (11 px: 13,3 por linha; o Qt arredonda a
    // altura da linha para cima, então sobra folga para o Fit não encolher à toa).
    readonly property real labelBox: 30
    readonly property real iconCenter: 31
    // Clique duplo não conta como 2º toque.
    readonly property int armGuardMs: 350
    // Anel do "toque de novo": quanto cresce a cada pulso.
    readonly property real ringSpread: 6

    readonly property bool rtl: !!root.theme && root.theme.rtl
    readonly property bool reduce: !root.theme || root.theme.reduceMotion

    // Ordem fixa do vídeo. Os comandos são os do menu do Omarchy. mirror: o
    // glifo tem direção (a seta do Sair) e espelha no RTL.
    readonly property var actions: [
        { id: "lock", icon: "lock", filled: false, mirror: false, label: "power.lock", confirm: false, command: ["omarchy-system-lock"] },
        { id: "suspend", icon: "bedtime", filled: true, mirror: false, label: "power.suspend", confirm: false, command: ["systemctl", "suspend"] },
        { id: "logout", icon: "logout", filled: false, mirror: true, label: "power.logout", confirm: true, command: ["omarchy-system", "logout"] },
        { id: "reboot", icon: "restart_alt", filled: false, mirror: false, label: "power.reboot", confirm: true, command: ["omarchy-system", "reboot"] },
        { id: "poweroff", icon: "power_settings_new", filled: false, mirror: false, label: "power.poweroff", confirm: true, command: ["omarchy-system", "shutdown"] }
    ]

    // x de um botão no sistema da tela (espelhado no RTL).
    function slotX(i) {
        const x = root.pad + i * root.pitch;
        return root.rtl ? root.implicitWidth - x - root.btnW : x;
    }

    function available(i) {
        const a = root.actions[i];
        return !!a && (a.id !== "suspend" || priv.suspendOk);
    }

    // ---- Contrato: abrir / fechar / teclas ----

    function opened(payload) {
        root.snapping = true;
        root.disarm();
        priv.pressed = -1;
        priv.lastPoint = Qt.point(-1, -1);
        priv.selected = 0;
        if (!sleepProbe.running)
            sleepProbe.running = true;
        Qt.callLater(() => root.snapping = false);
    }

    function closed() {
        root.disarm();
        priv.pressed = -1;
        priv.lastPoint = Qt.point(-1, -1);
    }

    function handleKey(event) {
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        const k = event.key;
        if (mods !== 0)
            return false;
        // Left/Right andam pela tela: no RTL, Right vai para o índice menor.
        const dir = root.rtl ? -1 : 1;
        switch (k) {
        case Qt.Key_Right:
            root.step(dir, false);
            return true;
        case Qt.Key_Left:
            root.step(-dir, false);
            return true;
        case Qt.Key_Tab:
            root.step((event.modifiers & Qt.ShiftModifier) ? -1 : 1, true);
            return true;
        case Qt.Key_Backtab:
            root.step(-1, true);
            return true;
        case Qt.Key_Home:
            root.select(root.nextAvailable(-1, 1, false));
            return true;
        case Qt.Key_End:
            root.select(root.nextAvailable(root.actions.length, -1, false));
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (!event.isAutoRepeat)
                root.activate(priv.selected);
            return true;
        default:
            break;
        }
        if (k >= Qt.Key_1 && k <= Qt.Key_5) {
            if (!event.isAutoRepeat)
                root.activate(k - Qt.Key_1);
            return true;
        }
        return false;
    }

    // Esc desarma primeiro; sem nada armado, a janela fecha.
    function handleEscape() {
        if (priv.armed >= 0) {
            root.disarm();
            return true;
        }
        return false;
    }

    // ---- Seleção e ações ----

    // Próximo índice disponível a partir de `from`, andando `delta`.
    function nextAvailable(from, delta, wrap) {
        const n = root.actions.length;
        let i = from;
        for (let tries = 0; tries < n; tries++) {
            i += delta;
            if (wrap)
                i = ((i % n) + n) % n;
            else if (i < 0 || i >= n)
                return priv.selected;
            if (root.available(i))
                return i;
        }
        return priv.selected;
    }

    function step(delta, wrap) {
        root.select(root.nextAvailable(priv.selected, delta, wrap));
    }

    function select(i) {
        if (i < 0 || i >= root.actions.length || !root.available(i) || i === priv.selected)
            return;
        if (priv.armed >= 0 && priv.armed !== i)
            root.disarm();
        priv.selected = i;
    }

    function arm(i) {
        priv.armed = i;
        priv.armedAt = Date.now();
        armTimer.restart();
    }

    function disarm() {
        armTimer.stop();
        priv.armed = -1;
    }

    function activate(i) {
        const a = root.actions[i];
        if (!a || !root.available(i))
            return;
        root.select(i);
        if (a.confirm) {
            if (priv.armed !== i) {
                root.arm(i);
                return;
            }
            if (Date.now() - priv.armedAt < root.armGuardMs)
                return;
        }
        root.run(a);
    }

    // Fecha a ilha e só depois executa (num processo à parte, que sobrevive à ilha).
    function run(a) {
        root.disarm();
        root.closeRequested();
        if (root.island && root.island.dev) {
            console.log("ilha(dev): energia " + a.id + " -> " + a.command.join(" ") + " (não executado)");
            return;
        }
        const wait = (Motion.TIMING.CLOSE_THEN_RUN_MS / 1000).toFixed(2);
        Quickshell.execDetached(["sh", "-c", "sleep \"$0\"; exec \"$@\"", wait].concat(a.command));
    }

    // O ponteiro andou (posição no sistema da tela).
    function pointerMoved(p) {
        const last = priv.lastPoint;
        if (Math.abs(p.x - last.x) < 0.5 && Math.abs(p.y - last.y) < 0.5)
            return;
        const first = last.x < 0;
        priv.lastPoint = p;
        if (first)
            return;
        const i = root.indexAt(p.x, p.y);
        if (i >= 0)
            root.select(i);
    }

    function indexAt(x, y) {
        if (y < root.pad || y > root.pad + root.btnH)
            return -1;
        for (let i = 0; i < root.actions.length; i++) {
            const bx = root.slotX(i);
            if (x >= bx && x <= bx + root.btnW)
                return i;
        }
        return -1;
    }

    QtObject {
        id: priv
        property int selected: 0
        property int armed: -1
        property real armedAt: 0
        property int pressed: -1
        property bool suspendOk: true
        property point lastPoint: Qt.point(-1, -1)
    }

    Timer {
        id: armTimer
        interval: Motion.TIMING.POWER_CONFIRM_MS
        onTriggered: priv.armed = -1
    }

    // O sono está desligado pelo Omarchy? (sai 0 = desligado; comando ausente = ligado)
    Process {
        id: sleepProbe
        command: ["sh", "-c", "omarchy-toggle-enabled suspend-off || omarchy-sleep-disabled"]
        onExited: (code, status) => {
            priv.suspendOk = code !== 0;
            if (!priv.suspendOk && priv.selected === 1)
                priv.selected = 0;
        }
    }

    Accessible.role: Accessible.Grouping
    Accessible.name: root.strings ? root.strings.t("cc.power") : ""

    // ---- Fundos dos botões ----
    Repeater {
        model: root.actions

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

    // ---- A seleção (uma só, desliza) ----
    Rectangle {
        id: selection
        x: root.slotX(priv.selected)
        y: root.pad
        width: root.btnW
        height: root.btnH
        radius: root.btnRadius
        color: root.theme ? root.theme.accent : "white"
        scale: priv.pressed >= 0 && priv.pressed === priv.selected ? 0.97 : 1
        Behavior on x {
            enabled: !root.snapping
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.POWER_SELECT) : 0; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
        }
    }

    // Anel do "toque de novo", em volta do botão armado.
    Rectangle {
        id: ring
        property real spread: 0
        readonly property bool live: priv.armed >= 0 && !root.reduce
        x: root.slotX(Math.max(0, priv.armed)) - ring.spread
        y: root.pad - ring.spread
        width: root.btnW + 2 * ring.spread
        height: root.btnH + 2 * ring.spread
        radius: root.btnRadius + ring.spread
        color: "transparent"
        border.width: 2
        border.color: root.theme ? root.theme.accent : "white"
        opacity: 0

        SequentialAnimation {
            running: ring.live
            loops: Animation.Infinite
            onStopped: {
                ring.spread = 0;
                ring.opacity = 0;
            }
            ParallelAnimation {
                NumberAnimation { target: ring; property: "spread"; from: 0; to: root.ringSpread; duration: Motion.FADE.DOT_PULSE.dur * 0.75; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 0.6; to: 0; duration: Motion.FADE.DOT_PULSE.dur * 0.75; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: Motion.FADE.DOT_PULSE.dur * 0.25 }
        }
    }

    // ---- Conteúdo dos botões (ícone, rótulo) e toques ----
    Repeater {
        model: root.actions

        Item {
            id: btn
            required property var modelData
            required property int index

            // Ponteiro neste botão. priv.selected é a seleção, não o hover.
            HoverHandler { id: btnHover }
            readonly property bool labelShown: !btn.armedHere && (btnHover.hovered || (root.keyboardMode && priv.selected === btn.index))
            readonly property bool usable: root.available(btn.index)
            readonly property bool armedHere: priv.armed === btn.index
            // Quanto a seleção cobre este botão (0..1): a cor segue o deslize.
            readonly property real cover: Math.max(0, 1 - Math.abs(selection.x - btn.x) / root.pitch)
            readonly property color ink: root.theme ? root.theme.mix(root.theme.ink, root.theme.onAccent, btn.cover) : "white"
            readonly property bool wraps: (btn.armedHere ? again.lineCount : label.lineCount) > 1

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
            Accessible.description: !btn.usable && root.strings ? root.strings.t("cc.unavailable") : (btn.armedHere ? again.text : "")
            Accessible.focusable: true
            Accessible.focused: priv.selected === btn.index
            Accessible.onPressAction: root.activate(btn.index)

            Item {
                anchors.fill: parent
                opacity: btn.usable ? 1 : 0.4

                Icon {
                    id: glyph
                    x: (btn.width - glyph.width) / 2
                    y: root.iconCenter - glyph.height / 2 - (btn.wraps ? root.wrapLift : 0)
                    name: btn.modelData.icon
                    filled: btn.modelData.filled
                    size: 20
                    color: btn.ink
                    transform: Scale {
                        origin.x: glyph.width / 2
                        xScale: root.rtl && btn.modelData.mirror ? -1 : 1
                    }
                    Behavior on y {
                        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
                    }
                }

                IlhaText {
                    id: label
                    x: (btn.width - label.width) / 2
                    y: root.labelBase - (label.lineCount > 1 ? root.wrapLift : 0) - label.baselineOffset
                    width: root.labelW
                    theme: root.theme
                    size: 11
                    weight: 600
                    color: btn.ink
                    height: root.labelBox
                    horizontalAlignment: Text.AlignHCenter
                    // Quebra nas palavras primeiro; só encolhe (até 10) se uma palavra não couber.
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 10
                    text: root.strings ? root.strings.t(btn.modelData.label) : ""
                    opacity: btn.labelShown ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.theme ? root.theme.dur(btn.labelShown ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // "Toque de novo", no lugar do rótulo enquanto armado.
                IlhaText {
                    id: again
                    x: (btn.width - again.width) / 2
                    y: root.labelBase - (again.lineCount > 1 ? root.wrapLift : 0) - again.baselineOffset
                    width: root.labelW
                    theme: root.theme
                    size: 11
                    weight: 600
                    color: btn.ink
                    height: root.labelBox
                    horizontalAlignment: Text.AlignHCenter
                    // Quebra nas palavras primeiro; só encolhe (até 10) se uma palavra não couber.
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 10
                    opacity: btn.armedHere ? 1 : 0
                    text: root.strings ? root.strings.t("common.pressAgain") : ""
                    Behavior on opacity {
                        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0; easing.type: Easing.OutCubic }
                    }
                }
            }

            TapHandler {
                id: tap
                enabled: btn.usable
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onPressedChanged: priv.pressed = tap.pressed ? btn.index : (priv.pressed === btn.index ? -1 : priv.pressed)
                onTapped: root.activate(btn.index)
            }
        }
    }

    // Hover: só o movimento real do ponteiro troca a seleção.
    HoverHandler {
        id: hover
        cursorShape: {
            const i = root.indexAt(hover.point.position.x, hover.point.position.y);
            return i >= 0 && root.available(i) ? Qt.PointingHandCursor : Qt.ArrowCursor;
        }
        onPointChanged: {
            if (hover.hovered)
                root.pointerMoved(hover.point.position);
        }
        onHoveredChanged: {
            if (!hover.hovered)
                priv.lastPoint = Qt.point(-1, -1);
        }
    }
}
