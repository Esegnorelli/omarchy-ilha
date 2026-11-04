pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import "Motion.js" as Motion

// Subpágina Tela da Central (screens §9 + amendments §12.3; vídeo
// 11:32.9-11:36.8). Dono: Agent E.
//
// Coordenadas do cartão (x 22, y 21 no painel, 470 de largura; o fundo é do
// contêiner da Central, que faz a transformação J e o fade):
// - Voltar 24 em (26, 34); título x 52, topo da maiúscula 26, 18.5 / 600. O chevron é secundário (hover do cabeçalho).
// - Um subcartão por monitor: 442 de largura, raio 16.5, raised, vão 11, o
//   primeiro em y 67.5, 163.5 de altura:
//   círculo 30 em (13.5, 13.5) (accent no monitor focado); nome x 52.5 (topo
//   da maiúscula 15.75, 14.5 / 600); "1920×1200 · 144 Hz · 1.0×" (32.25, 12
//   inkMuted) é secundária (hover do cartão ou foco b/s/r/m/k); "em foco" 12.5 accentInk a 13.5 da direita (só com 2+ telas);
//   brilho x 9.75, y 52.5, 379.5 x 27, trackRaised; a porcentagem é secundária (hover da barra, arraste ou foco b:);
//   fichas de escala em y 85.5 (30 de altura, vão 4.5, a partir de x 12);
//   linha Resolução em y 122 (28.5, recuo 10.5, raio 9, hover rowHover).
//   Clique na linha: até 6 modos inline, 30 px cada (o subcartão cresce em
//   160 ms OutCubic). Escolher um modo mostra a linha "Manter esta
//   resolução? Revertendo em 10 s" com Reverter / Manter (a contagem vive no
//   MonitorSvc e reverte sozinha; com a subpágina fora de vista o OsdBridge
//   leva a contagem para a pílula).
// - Luz noturna, 89 de altura: círculo dark_mode, "Luz noturna", "4000 K" secundário (hover do cartão ou foco n/nk),
//   interruptor a 12 da direita; barra x 9.75 .. direita − 12, y 51.75, 26,
//   2500..5800 K (mais preenchida = mais quente), 40% de opacidade desligada.
//   Cada movimento grava 120 ms depois (StatusSvc.setTemperature).
// - Manter acordado (amendments §12.3), 11 abaixo: 442 x 60, raio 16.5;
//   círculo 30 em (13.5, 15) com coffee 16; título (14, 14.5 / 600);
//   subtítulo (32, 12 inkMuted); interruptor a 12 da direita. Linha ou
//   interruptor: status.setStayAwake(!stayAwake).
// - cardH = 67.5 + 174.5·monitores + 89 + 11 + 60 + 16 (+ listas inline).
//   Acima de maxHeight o corpo rola (o cabeçalho fica; Cima/Baixo e a roda;
//   o item focado ou a lista aberta ficam à vista).
// - reveal("stayAwake"): rola até o cartão (160 ms; direto logo depois de
//   abrir), pulsa o fundo (FLASH 150 / 300 / 450) e, no modo teclado, foca o
//   interruptor.
// - Teclado: Cima/Baixo andam (brilho, escalas, resolução, modos, manter,
//   luz noturna, temperatura, manter acordado); Esquerda/Direita mexem na
//   barra (±5%, Shift ±1%) ou andam nas fichas e nos botões (espelhado em
//   RTL); Enter/Espaço escolhem ou alternam; Esc fecha a lista aberta, depois
//   volta.
Item {
    id: root

    property var island: null
    property Theme theme: null
    property var strings: null
    property bool keyboardMode: false
    property real maxHeight: 900

    signal back()

    readonly property var monitors: root.island ? root.island.monitors : null
    readonly property var status: root.island ? root.island.status : null
    readonly property int count: root.monitors ? root.monitors.displays.length : 0
    readonly property var pending: root.monitors ? root.monitors.pendingResolution : null
    // O corpo começa abaixo do cabeçalho (voltar + título).
    readonly property real bodyTop: 52

    // Altura-alvo do subcartão de um monitor (a viva anima 160 ms).
    function cardHeightFor(i) {
        const d = root.monitors && i < root.monitors.displays.length ? root.monitors.displays[i] : null;
        if (!d)
            return 163.5;
        const n = d.modes ? d.modes.length : 0;
        const list = priv.expanded === d.name && n > 1 ? 4 + 30 * n : 0;
        const confirm = root.pending && root.pending.name === d.name ? 42 : 0;
        return 163.5 + list + confirm;
    }

    readonly property real fullHeight: {
        let h = 67.5;
        for (let i = 0; i < root.count; i++)
            h += root.cardHeightFor(i) + 11;
        return h + 89 + 11 + 60 + 16;
    }

    width: 470
    implicitWidth: 470
    implicitHeight: Math.min(root.fullHeight, Math.max(160, root.maxHeight))

    function opened() {
        priv.snapping = true;
        priv.openedAt = Date.now();
        priv.expanded = "";
        scrollAnim.stop();
        body.contentY = 0;
        priv.focusKey = "b:" + Math.max(0, root.focusedIndex());
        if (root.monitors) {
            priv.pollWas = root.monitors.polling;
            root.monitors.polling = true;
        }
        Qt.callLater(() => priv.snapping = false);
    }

    function closed() {
        nightTimer.stop();
        priv.flushNight();
        priv.expanded = "";
        if (root.monitors)
            root.monitors.polling = priv.pollWas;
    }

    function handleKey(event) {
        const k = event.key;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods !== 0)
            return false;
        const keys = priv.targets;
        let i = keys.indexOf(priv.focusKey);
        if (i < 0) {
            priv.focusKey = keys.length > 0 ? keys[0] : "";
            i = 0;
        }
        const key = priv.focusKey;
        const kind = key.split(":")[0];
        const idx = Number(key.split(":")[1]);
        switch (k) {
        case Qt.Key_Down:
        case Qt.Key_Up:
            priv.focus(keys[Math.max(0, Math.min(keys.length - 1, i + (k === Qt.Key_Down ? 1 : -1)))]);
            return true;
        case Qt.Key_Home:
            priv.focus(keys[0]);
            return true;
        case Qt.Key_End:
            priv.focus(keys[keys.length - 1]);
            return true;
        case Qt.Key_Left:
        case Qt.Key_Right: {
            const sign = (k === Qt.Key_Right ? 1 : -1) * (root.theme && root.theme.rtl ? -1 : 1);
            const step = (event.modifiers & Qt.ShiftModifier) ? 0.01 : 0.05;
            if (kind === "b") {
                const s = priv.slider(idx);
                if (s && s.enabled)
                    s.nudge(sign * step);
            } else if (kind === "nk") {
                if (nightSlider.enabled)
                    nightSlider.nudge(sign * step);
            } else if (kind === "s") {
                const d = root.display(idx);
                const n = d && d.scales ? d.scales.length : 0;
                priv.chip = Math.max(0, Math.min(n - 1, priv.chip + sign));
            } else if (kind === "k") {
                priv.pill = sign > 0 ? 1 : 0;
            }
            return true;
        }
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            priv.activate();
            return true;
        default:
            return false;
        }
    }

    function handleEscape() {
        if (priv.expanded !== "") {
            const i = root.indexOf(priv.expanded);
            priv.expanded = "";
            if (i >= 0 && priv.focusKey.indexOf("m:") === 0)
                priv.focusKey = "r:" + i;
            return true;
        }
        root.back();
        return true;
    }

    // what: "stayAwake".
    function reveal(what) {
        if (String(what || "") !== "stayAwake")
            return;
        if (root.keyboardMode)
            priv.focusKey = "a";
        // Logo depois de abrir: rola direto e pulsa depois do fade de entrada.
        const fresh = priv.snapping || Date.now() - priv.openedAt < 120;
        Qt.callLater(() => {
            priv.scrollTo(awake, !fresh);
            flashAnim.restartAfter(fresh ? Motion.FADE.SCREEN_IN.delay + Motion.FADE.SCREEN_IN.dur : 0);
        });
    }

    // ---- Ajudas ----
    function tr(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    function num(n, decimals) {
        return Commons.I18n.formatNumber(n, decimals);
    }

    // Topo da maiúscula -> y do texto (Inter: ascendente 0.96875, maiúscula 0.7275).
    function capY(capTop, size) {
        return capTop - 0.24125 * Math.round(size);
    }

    function display(i) {
        return root.monitors && i >= 0 && i < root.monitors.displays.length ? root.monitors.displays[i] : null;
    }

    function indexOf(name) {
        for (let i = 0; i < root.count; i++) {
            if (root.monitors.displays[i].name === name)
                return i;
        }
        return -1;
    }

    function focusedIndex() {
        for (let i = 0; i < root.count; i++) {
            if (root.monitors.displays[i].focused)
                return i;
        }
        return 0;
    }

    function scaleText(s) {
        const n = Number(s) || 1;
        return root.tr("display.scale").arg(root.num(n, n % 1 === 0 ? 1 : undefined));
    }

    function modeText(m) {
        return m ? root.tr("display.mode").arg(root.num(m.width)).arg(root.num(m.height)).arg(root.num(Math.round(m.refresh))) : "";
    }

    function summaryText(d) {
        return d ? root.tr("display.summary").arg(root.num(d.width)).arg(root.num(d.height)).arg(root.num(Math.round(d.refresh))).arg(root.scaleText(d.scale)) : "";
    }

    // Temperatura <-> barra: mais preenchida = mais quente (menos K).
    function kelvinFor(v) {
        return Math.round((5800 - Math.max(0, Math.min(1, v)) * 3300) / 50) * 50;
    }

    function valueForKelvin(k) {
        return Math.max(0, Math.min(1, (5800 - (Number(k) || 4000)) / 3300));
    }

    QtObject {
        id: priv
        property bool snapping: false
        property real openedAt: 0
        // Nome do monitor com a lista de modos aberta ("" = nenhuma).
        property string expanded: ""
        property bool pollWas: false
        // "b:i" brilho, "s:i" escalas, "r:i" resolução, "m:i:k" modo, "k:i"
        // manter/reverter, "n" luz noturna, "nk" temperatura, "a" manter acordado.
        property string focusKey: "b:0"
        // Ficha focada na linha de escalas e botão focado na linha manter (0 reverter, 1 manter).
        property int chip: 0
        property int pill: 1
        // Temperatura escolhida esperando o debounce (-1 = nada).
        property int nightK: -1

        readonly property var targets: {
            const t = [];
            for (let i = 0; i < root.count; i++) {
                const d = root.monitors.displays[i];
                t.push("b:" + i, "s:" + i);
                if (d.modes && d.modes.length > 1) {
                    t.push("r:" + i);
                    if (priv.expanded === d.name) {
                        for (let k = 0; k < d.modes.length; k++)
                            t.push("m:" + i + ":" + k);
                    }
                }
                if (root.pending && root.pending.name === d.name)
                    t.push("k:" + i);
            }
            t.push("n", "nk", "a");
            return t;
        }

        function focus(key) {
            if (!key)
                return;
            priv.focusKey = key;
            const parts = key.split(":");
            const d = root.display(Number(parts[1]));
            if (parts[0] === "s" && d)
                priv.chip = Math.max(0, d.scaleIndex);
            if (parts[0] === "k")
                priv.pill = 1;
            priv.scrollTo(priv.itemFor(key), true);
        }

        // itemAt devolve Item: o delegado sai como var para ler os membros dele.
        function cardAt(i): var {
            return monRepeater.itemAt(i);
        }

        function slider(i) {
            const card = priv.cardAt(i);
            return card ? card.brightness : null;
        }

        function itemFor(key) {
            const parts = key.split(":");
            if (parts[0] === "n" || parts[0] === "nk")
                return night;
            if (parts[0] === "a")
                return awake;
            const card = priv.cardAt(Number(parts[1]));
            return card ? card.partFor(parts[0], Number(parts[2])) : null;
        }

        function activate() {
            const parts = priv.focusKey.split(":");
            const kind = parts[0];
            const i = Number(parts[1]);
            const d = root.display(i);
            const m = root.monitors;
            switch (kind) {
            case "s":
                // A escala atual não roda o script de novo (ele regrava o arquivo de monitores).
                if (d && m && d.scales[priv.chip] !== undefined && priv.chip !== d.scaleIndex)
                    m.setScale(d.name, d.scales[priv.chip]);
                break;
            case "r":
                if (d)
                    priv.toggleList(d.name);
                break;
            case "m":
                if (d && m && d.modes[Number(parts[2])]) {
                    m.setResolution(d.name, d.modes[Number(parts[2])]);
                    priv.expanded = "";
                    // O modo atual não cria contagem: o foco volta para a linha Resolução.
                    priv.focusKey = d.modeIndex === Number(parts[2]) ? "r:" + i : "k:" + i;
                    priv.pill = 1;
                }
                break;
            case "k":
                if (m) {
                    if (priv.pill === 1)
                        m.keepResolution();
                    else
                        m.revertResolution();
                }
                priv.focusKey = "r:" + i;
                break;
            case "n":
                if (root.status)
                    root.status.setNightlight(!root.status.nightlight);
                break;
            case "a":
                if (root.status)
                    root.status.setStayAwake(!root.status.stayAwake);
                break;
            default:
                break;
            }
        }

        function toggleList(name) {
            priv.expanded = priv.expanded === name ? "" : name;
            if (priv.expanded !== "") {
                const i = root.indexOf(name);
                // Depois do crescimento, a lista inteira fica à vista.
                listReveal.card = priv.cardAt(i);
                listReveal.restart();
            }
        }

        // Rola o corpo até o item ficar inteiro à vista.
        function scrollTo(item, animate) {
            if (!item || body.contentHeight <= body.height + 0.5)
                return;
            const p = item.mapToItem(content, 0, 0);
            const pad = 10;
            let y = body.contentY;
            if (p.y + item.height > y + body.height - pad)
                y = p.y + item.height - body.height + pad;
            if (p.y < y + pad)
                y = p.y - pad;
            y = Math.max(0, Math.min(body.contentHeight - body.height, y));
            if (Math.abs(y - body.contentY) < 0.5)
                return;
            scrollAnim.stop();
            if (animate && !priv.snapping && root.theme && root.theme.dur(Motion.FADE.REVEAL_SCROLL) > 0) {
                scrollAnim.to = y;
                scrollAnim.start();
            } else {
                body.contentY = y;
            }
        }

        function queueNight(k) {
            priv.nightK = k;
            nightTimer.restart();
        }

        function flushNight() {
            if (priv.nightK < 0)
                return;
            const k = priv.nightK;
            priv.nightK = -1;
            if (root.status)
                root.status.setTemperature(k);
        }
    }

    // Temperatura: grava 120 ms depois do último movimento.
    Timer {
        id: nightTimer
        interval: Motion.TIMING.NIGHT_DEBOUNCE_MS
        onTriggered: priv.flushNight()
    }

    // Lista de modos aberta: rola até ela depois do crescimento do cartão.
    Timer {
        id: listReveal
        property Item card: null
        interval: Motion.FADE.CARD_HEIGHT + 20
        onTriggered: priv.scrollTo(listReveal.card, true)
    }

    NumberAnimation {
        id: scrollAnim
        target: body
        property: "contentY"
        duration: root.theme ? root.theme.dur(Motion.FADE.REVEAL_SCROLL) : 0
        easing.type: Easing.OutCubic
    }

    // A linha "manter" que some (manteve, reverteu ou o tempo acabou) devolve
    // o foco para a linha Resolução do mesmo monitor.
    onPendingChanged: {
        if (priv.focusKey.indexOf("k:") === 0 && priv.targets.indexOf(priv.focusKey) < 0)
            priv.focusKey = "r:" + priv.focusKey.slice(2);
    }

    // Lista que some (monitor desligado) não deixa o foco solto.
    onCountChanged: {
        if (priv.targets.indexOf(priv.focusKey) < 0)
            priv.focusKey = "b:" + Math.max(0, Math.min(root.count - 1, root.focusedIndex()));
        if (priv.expanded !== "" && root.indexOf(priv.expanded) < 0)
            priv.expanded = "";
    }

    // ---- Botão de pílula (manter / reverter) ----
    component Pill: Rectangle {
        id: pill
        property Theme theme: null
        property string text: ""
        property bool accent: false
        property bool focused: false
        signal clicked()

        implicitHeight: 25.5
        implicitWidth: Math.max(60, Math.ceil(pillMetrics.advanceWidth) + 24)
        radius: height / 2
        color: !pill.theme ? "transparent"
            : pill.accent ? (pillArea.containsMouse ? pill.theme.mix(pill.theme.accent, pill.theme.ink, 0.08) : pill.theme.accent)
            : (pillArea.containsMouse ? pill.theme.alpha(pill.theme.ink, 0.16) : pill.theme.alpha(pill.theme.ink, 0.10))
        Behavior on color {
            ColorAnimation { duration: pill.theme ? pill.theme.dur(Motion.FADE.HOVER) : 0 }
        }

        Accessible.role: Accessible.Button
        Accessible.name: pill.text

        IlhaMetrics {
            id: pillMetrics
            theme: pill.theme
            size: 12.5
            weight: 600
            text: pill.text
        }
        IlhaText {
            anchors.centerIn: parent
            theme: pill.theme
            size: 12.5
            weight: 600
            color: pill.theme ? (pill.accent ? pill.theme.onAccent : pill.theme.ink) : "white"
            text: pill.text
        }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
        FocusRing {
            theme: pill.theme
            shown: pill.focused
            itemRadius: pill.height / 2
        }
    }

    // ---- Cabeçalho ----
    // Cabeçalho: o hover dele mostra o chevron de voltar (secundário; Esc, Alt+←, a navegação e o toque fora também voltam).
    Item {
        id: headerBand
        anchors.left: parent.left
        anchors.right: parent.right
        y: 0
        height: root.bodyTop
        HoverHandler { id: headerHover }
    }
    CircleButton {
        id: backBtn
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 22
        theme: root.theme
        icon: "chevron_left"
        flip: !!root.theme && root.theme.rtl
        size: 24
        glyphSize: 14
        accessibleName: root.tr("common.back")
        veil: (headerHover.hovered || backBtn.hovered) ? 1 : 0
        onClicked: root.back()
    }
    IlhaText {
        anchors.left: parent.left
        anchors.leftMargin: 52
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: root.capY(26, 18.5)
        theme: root.theme
        size: 18.5
        weight: 600
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.tr("display.title")
    }

    // ---- Corpo (rola só acima de maxHeight) ----
    Flickable {
        id: body
        y: root.bodyTop
        width: parent.width
        height: Math.max(0, root.height - root.bodyTop)
        contentWidth: width
        contentHeight: content.height
        interactive: body.contentHeight > body.height + 0.5
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onMovementStarted: scrollAnim.stop()

        Item {
            id: content
            width: body.width
            height: cards.y + cards.height + 16

            Column {
                id: cards
                anchors.left: parent.left
                anchors.leftMargin: 14
                y: 67.5 - root.bodyTop
                width: 442
                spacing: 11

                // ---- Um subcartão por monitor ----
                Repeater {
                    id: monRepeater
                    model: root.count

                    Rectangle {
                        id: mon
                        required property int index
                        readonly property var d: root.display(mon.index)
                        readonly property string name: mon.d ? mon.d.name : ""
                        HoverHandler { id: monHover }
                        // Foco do teclado dentro deste cartão (b:, s:, r:, m:, k: com o índice dele).
                        readonly property bool keyed: {
                            const p = priv.focusKey.split(":");
                            return root.keyboardMode && p.length >= 2 && Number(p[1]) === mon.index
                                && (p[0] === "b" || p[0] === "s" || p[0] === "r" || p[0] === "m" || p[0] === "k");
                        }
                        readonly property int modeCount: mon.d && mon.d.modes ? mon.d.modes.length : 0
                        readonly property int scaleCount: mon.d && mon.d.scales ? mon.d.scales.length : 0
                        readonly property bool expanded: priv.expanded !== "" && priv.expanded === mon.name && mon.modeCount > 1
                        readonly property bool confirming: !!root.pending && root.pending.name === mon.name
                        readonly property real listH: mon.expanded ? 4 + 30 * mon.modeCount : 0
                        readonly property alias brightness: brightSlider

                        // Parte do cartão para rolar até ela (teclado).
                        function partFor(kind, k) {
                            if (kind === "m") {
                                const row = modeRepeater.itemAt(k);
                                return row ? row : mon;
                            }
                            return kind === "b" ? brightSlider : kind === "s" ? chips : kind === "r" ? resRow : kind === "k" ? confirmRow : mon;
                        }

                        width: 442
                        height: root.cardHeightFor(mon.index)
                        radius: 16.5
                        color: root.theme ? root.theme.raised : "transparent"
                        clip: true
                        Behavior on height {
                            enabled: !priv.snapping
                            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 13.5
                            y: 13.5
                            width: 30
                            height: 30
                            radius: 15
                            color: root.theme ? (mon.d && mon.d.focused ? root.theme.accent : root.theme.rowIcon) : "gray"
                            Behavior on color {
                                ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                            }
                            Icon {
                                anchors.centerIn: parent
                                name: "desktop_windows"
                                size: 14
                                filled: !!mon.d && mon.d.focused
                                color: root.theme ? (mon.d && mon.d.focused ? root.theme.onAccent : root.theme.ink) : "white"
                            }
                        }
                        IlhaText {
                            anchors.left: parent.left
                            anchors.leftMargin: 52.5
                            anchors.right: parent.right
                            anchors.rightMargin: focusedLabel.opacity > 0 ? focusedLabel.width + 24 : 13.5
                            y: root.capY(15.75, 14.5)
                            theme: root.theme
                            size: 14.5
                            weight: 600
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                            text: mon.name
                        }
                        IlhaText {
                            anchors.left: parent.left
                            anchors.leftMargin: 52.5
                            anchors.right: parent.right
                            anchors.rightMargin: 13.5
                            y: root.capY(32.25, 12)
                            theme: root.theme
                            size: 12
                            weight: 400
                            color: root.theme ? root.theme.inkMuted : "gray"
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                            text: root.summaryText(mon.d)
                            readonly property bool reveal: monHover.hovered || mon.keyed
                            opacity: reveal ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: root.theme ? root.theme.dur(reveal ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                        IlhaText {
                            id: focusedLabel
                            anchors.right: parent.right
                            anchors.rightMargin: 13.5
                            y: 28.5 - height / 2
                            opacity: root.count > 1 && !!mon.d && mon.d.focused ? 1 : 0
                            theme: root.theme
                            size: 12.5
                            weight: 500
                            color: root.theme ? root.theme.accentInk : "white"
                            text: root.tr("display.focused")
                            Behavior on opacity {
                                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                            }
                        }

                        // Brilho
                        Item {
                            id: brightRowHit
                            anchors.left: parent.left
                            anchors.right: parent.right
                            y: brightSlider.y
                            height: brightSlider.height
                            HoverHandler { id: brightRowHover }
                        }
                        IlhaSlider {
                            id: brightSlider
                            anchors.left: parent.left
                            anchors.leftMargin: 9.75
                            y: 52.5
                            width: 379.5
                            barHeight: 27
                            theme: root.theme
                            trackColor: root.theme ? root.theme.trackRaised : "black"
                            glyph: "light_mode"
                            enabled: !!mon.d && mon.d.hasBrightness
                            value: mon.d && mon.d.hasBrightness ? mon.d.brightness / 100 : 0
                            focused: root.keyboardMode && priv.focusKey === "b:" + mon.index
                            accessibleName: mon.d && !mon.d.hasBrightness ? root.tr("display.noBrightness") : mon.name
                            onMoved: v => {
                                priv.focusKey = "b:" + mon.index;
                                if (root.monitors && mon.d)
                                    root.monitors.setBrightness(mon.name, v * 100);
                            }
                        }
                        IlhaText {
                            anchors.left: brightSlider.left
                            anchors.leftMargin: 40
                            anchors.right: brightSlider.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: brightSlider.verticalCenter
                            opacity: mon.d && !mon.d.hasBrightness ? 1 : 0
                            theme: root.theme
                            size: 12
                            weight: 500
                            color: root.theme ? root.theme.inkMuted : "gray"
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                            text: root.tr("display.noBrightness")
                        }
                        IlhaText {
                            anchors.right: parent.right
                            anchors.rightMargin: 13.5
                            anchors.verticalCenter: brightSlider.verticalCenter
                            theme: root.theme
                            size: 12.5
                            weight: 500
                            tnum: true
                            color: root.theme ? root.theme.inkMuted : "gray"
                            text: root.tr("common.percent").arg(root.num(Math.round(brightSlider.shownValue * 100)))
                            HoverHandler { id: brightPctHover }
                            readonly property bool reveal: brightRowHover.hovered || brightSlider.hovered || brightSlider.dragging || brightPctHover.hovered || (root.keyboardMode && priv.focusKey === "b:" + mon.index)
                            opacity: (mon.d && mon.d.hasBrightness && reveal) ? 1 : 0
                            Behavior on opacity {
                                enabled: !!(mon.d && mon.d.hasBrightness)
                                NumberAnimation {
                                    duration: root.theme ? root.theme.dur(reveal ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // Escalas
                        Row {
                            id: chips
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            y: 85.5
                            spacing: 4.5
                            Repeater {
                                model: mon.scaleCount
                                Chip {
                                    id: chip
                                    required property int index
                                    readonly property string value: mon.d && mon.d.scales[chip.index] !== undefined ? String(mon.d.scales[chip.index]) : "1"
                                    theme: root.theme
                                    text: root.scaleText(chip.value)
                                    selected: !!mon.d && mon.d.scaleIndex === chip.index
                                    focused: root.keyboardMode && priv.focusKey === "s:" + mon.index && priv.chip === chip.index
                                    onClicked: {
                                        priv.focusKey = "s:" + mon.index;
                                        priv.chip = chip.index;
                                        if (root.monitors && !chip.selected)
                                            root.monitors.setScale(mon.name, chip.value);
                                    }
                                }
                            }
                        }

                        // Resolução
                        Item {
                            id: resRow
                            anchors.left: parent.left
                            anchors.leftMargin: 10.5
                            anchors.right: parent.right
                            anchors.rightMargin: 10.5
                            y: 122
                            height: 28.5
                            readonly property bool canOpen: mon.modeCount > 1

                            Accessible.role: Accessible.Button
                            Accessible.name: root.tr("display.resolution") + " " + root.modeText(mon.d)

                            Rectangle {
                                anchors.fill: parent
                                radius: 9
                                color: root.theme ? (resArea.containsMouse && resRow.canOpen ? root.theme.rowHover : root.theme.alpha(root.theme.rowHover, 0)) : "transparent"
                                Behavior on color {
                                    ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                                }
                            }
                            MouseArea {
                                id: resArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: resRow.canOpen
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    priv.focusKey = "r:" + mon.index;
                                    priv.toggleList(mon.name);
                                }
                            }
                            IlhaText {
                                id: resLabel
                                anchors.left: parent.left
                                anchors.leftMargin: 7.5
                                anchors.verticalCenter: parent.verticalCenter
                                theme: root.theme
                                size: 12.5
                                weight: 500
                                color: root.theme ? root.theme.inkMuted : "gray"
                                text: root.tr("display.resolution")
                            }
                            Icon {
                                id: resChevron
                                anchors.right: parent.right
                                anchors.rightMargin: 1.5
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: resRow.canOpen ? 1 : 0
                                name: root.theme && root.theme.rtl ? "chevron_left" : "chevron_right"
                                size: 14
                                color: root.theme ? root.theme.inkMuted : "gray"
                                rotation: mon.expanded ? 90 * (root.theme && root.theme.rtl ? -1 : 1) : 0
                                Behavior on rotation {
                                    enabled: !priv.snapping
                                    NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
                                }
                            }
                            IlhaText {
                                anchors.left: resLabel.right
                                anchors.leftMargin: 12
                                anchors.right: resChevron.left
                                anchors.rightMargin: resRow.canOpen ? 2 : -14
                                anchors.verticalCenter: parent.verticalCenter
                                theme: root.theme
                                size: 12.5
                                weight: 600
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignRight
                                text: root.modeText(mon.d)
                            }
                            FocusRing {
                                theme: root.theme
                                shown: root.keyboardMode && priv.focusKey === "r:" + mon.index
                                itemRadius: 9
                            }
                        }

                        // Modos inline (até 6, 30 px cada)
                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 10.5
                            anchors.right: parent.right
                            anchors.rightMargin: 10.5
                            y: 154.5
                            opacity: mon.expanded ? 1 : 0
                            enabled: mon.expanded
                            Behavior on opacity {
                                enabled: !priv.snapping
                                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.SUB_CONTENT_IN.dur) : 0; easing.type: Easing.OutCubic }
                            }

                            Repeater {
                                id: modeRepeater
                                model: mon.modeCount
                                Item {
                                    id: modeRow
                                    required property int index
                                    readonly property var m: mon.d && mon.d.modes[modeRow.index] ? mon.d.modes[modeRow.index] : null
                                    readonly property bool current: !!mon.d && mon.d.modeIndex === modeRow.index
                                    width: parent ? parent.width : 421
                                    height: 30

                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: root.modeText(modeRow.m)
                                    Accessible.checked: modeRow.current

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 9
                                        color: root.theme ? (modeArea.containsMouse ? root.theme.rowHover : root.theme.alpha(root.theme.rowHover, 0)) : "transparent"
                                        Behavior on color {
                                            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                                        }
                                    }
                                    MouseArea {
                                        id: modeArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.monitors && modeRow.m && !modeRow.current)
                                                root.monitors.setResolution(mon.name, modeRow.m);
                                            priv.expanded = "";
                                            priv.focusKey = modeRow.current ? "r:" + mon.index : "k:" + mon.index;
                                            priv.pill = 1;
                                        }
                                    }
                                    IlhaText {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 7.5
                                        anchors.right: parent.right
                                        anchors.rightMargin: 24
                                        anchors.verticalCenter: parent.verticalCenter
                                        theme: root.theme
                                        size: 12.5
                                        weight: modeRow.current ? 600 : 500
                                        color: root.theme ? (modeRow.current ? root.theme.ink : root.theme.alpha(root.theme.ink, 0.9)) : "white"
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignLeft
                                        text: root.modeText(modeRow.m)
                                    }
                                    Icon {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 1.5
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: modeRow.current ? 1 : 0
                                        name: "check"
                                        size: 14
                                        color: root.theme ? root.theme.inkMuted : "gray"
                                    }
                                    FocusRing {
                                        theme: root.theme
                                        shown: root.keyboardMode && priv.focusKey === "m:" + mon.index + ":" + modeRow.index
                                        itemRadius: 9
                                    }
                                }
                            }
                        }

                        // Manter esta resolução?
                        Rectangle {
                            id: confirmRow
                            anchors.left: parent.left
                            anchors.leftMargin: 10.5
                            anchors.right: parent.right
                            anchors.rightMargin: 10.5
                            y: 150.5 + mon.listH + 6
                            height: 36
                            radius: 10
                            color: root.theme ? root.theme.alpha(root.theme.accent, 0.14) : "transparent"
                            opacity: mon.confirming ? 1 : 0
                            enabled: mon.confirming
                            Behavior on opacity {
                                enabled: !priv.snapping
                                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
                            }

                            IlhaText {
                                id: confirmText
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: pills.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                theme: root.theme
                                size: 12
                                weight: 500
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignLeft
                                text: root.tr("display.keepPrompt").arg(root.num(mon.confirming ? root.pending.secondsLeft : 0))
                                Accessible.role: Accessible.StaticText
                                Accessible.name: confirmText.text
                            }
                            Row {
                                id: pills
                                anchors.right: parent.right
                                anchors.rightMargin: 5.25
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Pill {
                                    theme: root.theme
                                    text: root.tr("common.revert")
                                    focused: root.keyboardMode && priv.focusKey === "k:" + mon.index && priv.pill === 0
                                    onClicked: {
                                        priv.focusKey = "r:" + mon.index;
                                        if (root.monitors)
                                            root.monitors.revertResolution();
                                    }
                                }
                                Pill {
                                    theme: root.theme
                                    accent: true
                                    text: root.tr("common.keep")
                                    focused: root.keyboardMode && priv.focusKey === "k:" + mon.index && priv.pill === 1
                                    onClicked: {
                                        priv.focusKey = "r:" + mon.index;
                                        if (root.monitors)
                                            root.monitors.keepResolution();
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Luz noturna (89) ----
                Rectangle {
                    id: night
                    readonly property bool on: !!root.status && root.status.nightlight
                    // K mostrado: o do arraste, o que espera o debounce, ou o do serviço.
                    readonly property int kelvin: nightSlider.dragging ? root.kelvinFor(nightSlider.shownValue)
                        : priv.nightK >= 0 ? priv.nightK
                        : (root.status ? root.status.nightTemperature : 4000)
                    HoverHandler { id: nightHover }
                    readonly property bool pointed: nightHover.hovered || nightSlider.hovered
                    width: 442
                    height: 89
                    radius: 16.5
                    color: root.theme ? root.theme.raised : "transparent"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 13.5
                        y: 12
                        width: 30
                        height: 30
                        radius: 15
                        color: root.theme ? (night.on ? root.theme.accent : root.theme.rowIcon) : "gray"
                        Behavior on color {
                            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.SWITCH) : 0 }
                        }
                        Icon {
                            anchors.centerIn: parent
                            name: "dark_mode"
                            size: 14
                            filled: true
                            color: root.theme ? (night.on ? root.theme.onAccent : root.theme.ink) : "white"
                        }
                    }
                    IlhaText {
                        anchors.left: parent.left
                        anchors.leftMargin: 52.5
                        anchors.right: parent.right
                        anchors.rightMargin: 67
                        y: root.capY(14.25, 14.5)
                        theme: root.theme
                        size: 14.5
                        weight: 600
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        text: root.tr("cc.nightLight")
                    }
                    IlhaText {
                        anchors.left: parent.left
                        anchors.leftMargin: 52.5
                        y: root.capY(30.75, 12)
                        theme: root.theme
                        size: 12
                        weight: 400
                        tnum: true
                        color: root.theme ? root.theme.inkMuted : "gray"
                        text: root.tr("display.kelvin").arg(root.num(night.kelvin))
                        readonly property bool reveal: night.pointed || (root.keyboardMode && (priv.focusKey === "n" || priv.focusKey === "nk"))
                        opacity: reveal ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: root.theme ? root.theme.dur(reveal ? Motion.FADE.REVEAL_IN : Motion.FADE.REVEAL_OUT) : 0
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                    IlhaSwitch {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        y: 27 - height / 2
                        theme: root.theme
                        checked: night.on
                        focused: root.keyboardMode && priv.focusKey === "n"
                        accessibleName: root.tr("cc.nightLight")
                        onToggled: {
                            priv.focusKey = "n";
                            if (root.status)
                                root.status.setNightlight(!root.status.nightlight);
                        }
                    }
                    IlhaSlider {
                        id: nightSlider
                        anchors.left: parent.left
                        anchors.leftMargin: 9.75
                        y: 51.75
                        width: 442 - 9.75 - 12
                        barHeight: 26
                        theme: root.theme
                        trackColor: root.theme ? root.theme.trackRaised : "black"
                        glyph: "dark_mode"
                        glyphFilled: true
                        enabled: night.on
                        value: root.valueForKelvin(priv.nightK >= 0 ? priv.nightK : (root.status ? root.status.nightTemperature : 4000))
                        focused: root.keyboardMode && priv.focusKey === "nk"
                        accessibleName: root.tr("cc.nightLight")
                        onMoved: v => {
                            priv.focusKey = "nk";
                            priv.queueNight(root.kelvinFor(v));
                        }
                        onCommitted: v => {
                            priv.queueNight(root.kelvinFor(v));
                            nightTimer.stop();
                            priv.flushNight();
                        }
                    }
                }

                // ---- Manter acordado (442 x 60) ----
                Rectangle {
                    id: awake
                    readonly property bool on: !!root.status && root.status.stayAwake
                    width: 442
                    height: 60
                    radius: 16.5
                    color: root.theme ? (awakeArea.containsMouse ? root.theme.rowHover : root.theme.raised) : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                    }

                    Accessible.role: Accessible.CheckBox
                    Accessible.name: root.tr("display.stayAwake")
                    Accessible.checkable: true
                    Accessible.checked: awake.on

                    // Pulso do reveal(): raised -> rowHover -> raised.
                    Rectangle {
                        id: flash
                        anchors.fill: parent
                        radius: parent.radius
                        color: root.theme ? root.theme.rowHover : "transparent"
                        opacity: 0
                    }
                    SequentialAnimation {
                        id: flashAnim
                        property int lead: 0
                        function restartAfter(ms) {
                            flashAnim.stop();
                            flash.opacity = 0;
                            flashAnim.lead = Math.max(0, ms);
                            flashAnim.start();
                        }
                        PauseAnimation { duration: flashAnim.lead }
                        NumberAnimation { target: flash; property: "opacity"; to: 1; duration: root.theme ? root.theme.dur(Motion.FADE.FLASH.in) : 0; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: Motion.FADE.FLASH.hold }
                        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: root.theme ? root.theme.dur(Motion.FADE.FLASH.out) : 0; easing.type: Easing.OutCubic }
                    }

                    MouseArea {
                        id: awakeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            priv.focusKey = "a";
                            if (root.status)
                                root.status.setStayAwake(!root.status.stayAwake);
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 13.5
                        y: 15
                        width: 30
                        height: 30
                        radius: 15
                        color: root.theme ? (awake.on ? root.theme.accent : root.theme.rowIcon) : "gray"
                        Behavior on color {
                            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.SWITCH) : 0 }
                        }
                        Icon {
                            anchors.centerIn: parent
                            name: "coffee"
                            size: 16
                            filled: awake.on
                            color: root.theme ? (awake.on ? root.theme.onAccent : root.theme.ink) : "white"
                        }
                    }
                    IlhaText {
                        anchors.left: parent.left
                        anchors.leftMargin: 52.5
                        anchors.right: parent.right
                        anchors.rightMargin: 67
                        y: root.capY(14, 14.5)
                        theme: root.theme
                        size: 14.5
                        weight: 600
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        text: root.tr("display.stayAwake")
                    }
                    IlhaText {
                        anchors.left: parent.left
                        anchors.leftMargin: 52.5
                        anchors.right: parent.right
                        anchors.rightMargin: 67
                        y: root.capY(32, 12)
                        theme: root.theme
                        size: 12
                        weight: 400
                        color: root.theme ? root.theme.inkMuted : "gray"
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        text: root.tr(awake.on ? "display.stayAwakeHint" : "common.off")
                    }
                    IlhaSwitch {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        theme: root.theme
                        checked: awake.on
                        focused: root.keyboardMode && priv.focusKey === "a"
                        accessibleName: root.tr("display.stayAwake")
                        onToggled: {
                            priv.focusKey = "a";
                            if (root.status)
                                root.status.setStayAwake(!root.status.stayAwake);
                        }
                    }
                }
            }
        }
    }
}
