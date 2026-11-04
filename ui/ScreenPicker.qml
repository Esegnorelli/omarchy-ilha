pragma ComponentBehavior: Bound
import QtQuick
import "Motion.js" as Motion

// L1 (amendments §6): workspaces · relógio · telas (SCREEN_ORDER), na pílula
// (largura viva, 42 de altura, topo 22, cap 21). O ícone k é Alt+k. Fica
// DENTRO do HoverBar, em coordenadas da janela. Os ícones têm x final fixo
// em relação ao centro e só acompanham morph.bandY: o recorte que alarga
// os revela (regra 2 do anti-glitch). O texto do relógio é o HeroClock da
// janela; aqui só a vaga e o realce.
//
// Movimento (P):
// - Entrada: cada ícone entra em 90 ms depois de 50 + 12·rank ms (rank 0 para
//   os slots 2 e 3, 1 para 1 e 4, 2 para 0 e 5), com escala 0,85 -> 1 no
//   mesmo tempo, em torno do próprio centro.
// - Saída: todos somem juntos em 60 ms (P out, F).
// - Slot sob o ponteiro: círculo 30 com tinta a 10% (16% pressionado) e o
//   glifo vai de 90% a 100%; entra em 110 ms, sai em 70 ms.
//
// Sem rótulos: seria conteúdo fora da forma. A Mídia aparece sempre
// (posições estáveis).
//
//   hitTest(x, y) -> "ws:<id>" | "clock" | "pick:<id>" | "pick:" (vãos, sobem ao L2) | ""
//   setHover(hit) destaca o hit cru (a IslandWindow chama com o ponteiro)
Item {
    id: root

    property Theme theme: null
    property var strings: null
    property var morph: null
    property bool rtl: false
    // Glifos do menu do Omarchy (a HoverBar liga). Vazio: o Material de screenMeta.
    property var glyphs: null
    property bool shown: false
    // Botão apertado sobre o slot destacado (opcional; a IslandWindow liga).
    property bool pressed: false

    readonly property string hoverId: priv.hoverId
    // Workspaces numerados do monitor (o modelo do HoverBar), à esquerda do relógio.
    property var workspaces: null
    readonly property var wsItems: root.workspaces ? root.workspaces.items : []
    readonly property real wsCapH: 22
    readonly property real wsGap: 4
    function wsCapW(it) {
        return it && it.wide ? 28 : 22;
    }
    readonly property real wsW: {
        const list = root.wsItems;
        let w = 0;
        for (let i = 0; i < list.length; i++)
            w += root.wsCapW(list[i]);
        return list.length > 0 ? w + root.wsGap * (list.length - 1) : 0;
    }
    // Filete entre os workspaces e o relógio (8 + 1 + 8). Some sem workspaces.
    readonly property real divW: root.wsW > 0 ? 17 : 0
    // Vaga do relógio no meio. O filete até os ícones fica sempre.
    property real clockW: 44
    readonly property real clockSlotW: root.clockW + 2 * priv.px("PICKER_CLOCK_PAD", 10)
    readonly property real clockDivW: 17
    readonly property real iconsW: root.slots.length * priv.px("PICKER_PITCH", 36)
    readonly property real totalW: 2 * priv.px("PICKER_PAD", 10) + root.wsW + root.divW + root.clockSlotW + root.clockDivW + root.iconsW
    implicitWidth: root.totalW
    implicitHeight: priv.px("PICKER_H", 42)

    // Ícone e rótulo de cada tela; a ordem é a de theme.px.SCREEN_ORDER.
    readonly property var screenMeta: ({
        launcher: { icon: "apps", label: "cc.apps" },
        themes: { icon: "palette", label: "cc.themes" },
        calendar: { icon: "calendar_month", label: "picker.calendar" },
        capture: { icon: "photo_camera", label: "picker.capture" },
        menu: { icon: "menu", label: "picker.menu" },
        control: { icon: "tune", label: "picker.control" },
        power: { icon: "power_settings_new", label: "cc.power" }
    })
    readonly property var slots: (root.theme ? root.theme.px.SCREEN_ORDER : ["launcher", "calendar", "themes", "capture", "menu", "control", "power"])
        .map(id => Object.assign({ id: id }, root.screenMeta[id]))

    readonly property real cx: root.morph ? root.morph.centerX : root.width / 2
    readonly property real cy: root.morph ? root.morph.bandY : 43
    readonly property real clockCx: {
        const c = root.cx - root.totalW / 2 + priv.px("PICKER_PAD", 10) + root.wsW + root.divW + root.clockSlotW / 2;
        return root.rtl ? 2 * root.cx - c : c;
    }
    readonly property real clockDx: root.clockCx - root.cx

    // Centro x do slot i: LTR left + 10 + workspaces + filete + relógio + filete + 18 + 36·i.
    function slotCenter(i) {
        const left = root.cx - root.totalW / 2;
        const c = left + priv.px("PICKER_PAD", 10) + root.wsW + root.divW + root.clockSlotW + root.clockDivW + priv.px("PICKER_PITCH", 36) / 2 + priv.px("PICKER_PITCH", 36) * i;
        return root.rtl ? 2 * root.cx - c : c;
    }

    // Centro x da cápsula do workspace i (o 1 à esquerda; RTL espelha).
    function wsCenter(i) {
        const list = root.wsItems;
        let c = root.cx - root.totalW / 2 + priv.px("PICKER_PAD", 10);
        for (let j = 0; j < i; j++)
            c += root.wsCapW(list[j]) + root.wsGap;
        c += root.wsCapW(list[i]) / 2;
        return root.rtl ? 2 * root.cx - c : c;
    }

    // Slot: 36 de largura x a altura toda da forma. Os vãos (e o resto da
    // zona) devolvem "pick:" (o toque sobe ao L2).
    function hitTest(x, y) {
        if (!root.shown)
            return "";
        const halfW = root.totalW / 2 + priv.px("ZONE_PAD", 6);
        if (Math.abs(x - root.cx) > halfW || y < 0 || y > priv.px("ZONE_PICKER_H", 66))
            return "";
        const top = priv.px("PICKER_TOP", 22), bottom = top + priv.px("PICKER_H", 42);
        if (y >= top && y <= bottom) {
            const list = root.wsItems;
            for (let w = 0; w < list.length; w++) {
                if (Math.abs(x - root.wsCenter(w)) <= root.wsCapW(list[w]) / 2 + root.wsGap / 2)
                    return "ws:" + list[w].id;
            }
            if (Math.abs(x - root.clockCx) <= root.clockSlotW / 2)
                return "clock";
            const half = priv.px("PICKER_PITCH", 36) / 2;
            for (let i = 0; i < root.slots.length; i++) {
                if (Math.abs(x - root.slotCenter(i)) <= half)
                    return "pick:" + root.slots[i].id;
            }
        }
        return "pick:";
    }

    function setHover(hit) {
        const h = root.shown ? String(hit || "") : "";
        priv.hoverId = h.indexOf("pick:") === 0 ? h.slice(5) : (h.indexOf("ws:") === 0 || h === "clock" ? h : "");
    }

    onShownChanged: if (!root.shown) priv.hoverId = ""

    QtObject {
        id: priv
        property string hoverId: ""

        function px(name, fallback) {
            return root.theme && root.theme.px[name] !== undefined ? root.theme.px[name] : fallback;
        }
    }

    Accessible.role: Accessible.Grouping
    Accessible.name: root.strings ? root.strings.t("picker.title") : ""

    // ---- Workspaces numerados ----
    // Ativo em accent; ocupado tingido; vazio apagado; urgente em danger.
    Repeater {
        model: root.workspaces ? root.workspaces.count : 0

        Rectangle {
            id: wsCap
            required property int index
            readonly property var it: root.wsItems[wsCap.index] || ({})
            readonly property bool hot: priv.hoverId === "ws:" + wsCap.it.id
            x: root.wsCenter(wsCap.index) - width / 2
            y: root.cy - height / 2
            width: root.wsCapW(wsCap.it)
            height: root.wsCapH
            radius: height / 2
            antialiasing: true
            opacity: root.shown ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: root.theme ? root.theme.dur(root.shown ? Motion.FADE.PICKER_IN.dur : Motion.FADE.PICKER_OUT) : 0
                    easing.type: Easing.OutCubic
                }
            }
            color: !root.theme ? "gray"
                : wsCap.it.urgent ? root.theme.danger
                : wsCap.it.active ? root.theme.accent
                : wsCap.it.occupied ? root.theme.alpha(root.theme.accent, wsCap.hot ? 0.34 : 0.22)
                : root.theme.alpha(root.theme.ink, wsCap.hot ? 0.14 : 0.07)

            IlhaText {
                anchors.centerIn: parent
                theme: root.theme
                size: 11.5
                weight: wsCap.it.active ? 700 : 600
                tnum: true
                color: !root.theme ? "white"
                    : (wsCap.it.active || wsCap.it.urgent) ? root.theme.onAccent
                    : wsCap.it.occupied ? root.theme.ink
                    : root.theme.inkFaint
                text: wsCap.it.label || ""
            }
        }
    }

    // Filete entre os workspaces e o relógio.
    Rectangle {
        visible: root.divW > 0
        readonly property real lx: root.cx - root.totalW / 2 + priv.px("PICKER_PAD", 10) + root.wsW + root.divW / 2
        x: (root.rtl ? 2 * root.cx - lx : lx) - 0.5
        y: root.cy - 9
        width: 1
        height: 18
        color: root.theme ? root.theme.alpha(root.theme.ink, 0.12) : "gray"
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(90) : 0 }
        }
    }

    // Filete entre o relógio e os ícones (sempre presente).
    Rectangle {
        visible: true
        readonly property real lx: root.cx - root.totalW / 2 + priv.px("PICKER_PAD", 10) + root.wsW + root.divW + root.clockSlotW + root.clockDivW / 2
        x: (root.rtl ? 2 * root.cx - lx : lx) - 0.5
        y: root.cy - 9
        width: 1
        height: 18
        color: root.theme ? root.theme.alpha(root.theme.ink, 0.12) : "gray"
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(90) : 0 }
        }
    }

    // Realce do relógio. O texto é o HeroClock da janela, desenhado por cima.
    Rectangle {
        id: clockHover
        readonly property bool hot: priv.hoverId === "clock"
        x: root.clockCx - width / 2
        y: root.cy - height / 2
        width: root.clockW + 16
        height: priv.px("PICKER_HOVER", 30)
        radius: height / 2
        color: root.theme ? (clockHover.hot && root.pressed ? root.theme.pressOverlay : root.theme.hoverOverlay) : "transparent"
        opacity: root.shown && clockHover.hot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.theme ? root.theme.dur(clockHover.hot ? Motion.FADE.PICKER_HOVER_IN : Motion.FADE.PICKER_HOVER_OUT) : 0; easing.type: Easing.OutCubic } }
    }


    Repeater {
        id: slotRepeater
        model: root.slots

        Item {
            id: slot
            required property var modelData
            required property int index
            readonly property bool hot: priv.hoverId === slot.modelData.id
            readonly property real pitch: priv.px("PICKER_PITCH", 36)

            x: root.slotCenter(slot.index) - slot.pitch / 2
            y: root.cy - height / 2
            width: slot.pitch
            height: priv.px("PICKER_H", 42)
            opacity: 0
            scale: Motion.FADE.PICKER_IN.scaleFrom

            Accessible.role: Accessible.Button
            Accessible.name: root.strings ? root.strings.t(slot.modelData.label) : slot.modelData.id

            function enter() {
                outAnim.stop();
                const reduce = !root.theme || root.theme.reduceMotion;
                if (reduce) {
                    inAnim.stop();
                    slot.opacity = 1;
                    slot.scale = 1;
                    return;
                }
                // Partindo do zero: a escala volta a 0,85 antes de entrar.
                if (slot.opacity <= 0.01)
                    slot.scale = Motion.FADE.PICKER_IN.scaleFrom;
                inPause.duration = Motion.FADE.PICKER_IN.delay + Motion.FADE.PICKER_IN.step * Motion.pickerRank(slot.index);
                inAnim.restart();
            }

            function leave() {
                inAnim.stop();
                if (!root.theme || root.theme.reduceMotion) {
                    outAnim.stop();
                    slot.opacity = 0;
                    return;
                }
                outAnim.restart();
            }

            SequentialAnimation {
                id: inAnim
                PauseAnimation { id: inPause }
                ParallelAnimation {
                    NumberAnimation {
                        target: slot
                        property: "opacity"
                        to: 1
                        duration: Motion.FADE.PICKER_IN.dur
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: slot
                        property: "scale"
                        to: 1
                        duration: Motion.FADE.PICKER_IN.dur
                        easing.type: Easing.OutCubic
                    }
                }
            }
            NumberAnimation {
                id: outAnim
                target: slot
                property: "opacity"
                to: 0
                duration: Motion.FADE.PICKER_OUT
                easing.type: Easing.OutCubic
            }

            Connections {
                target: root
                function onShownChanged() {
                    if (root.shown)
                        slot.enter();
                    else
                        slot.leave();
                }
            }
            Component.onCompleted: {
                if (root.shown)
                    slot.enter();
            }

            // Círculo do slot sob o ponteiro.
            Rectangle {
                anchors.centerIn: parent
                width: priv.px("PICKER_HOVER", 30)
                height: width
                radius: width / 2
                color: root.theme ? (slot.hot && root.pressed ? root.theme.pressOverlay : root.theme.hoverOverlay) : "transparent"
                opacity: slot.hot ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: root.theme ? root.theme.dur(slot.hot ? Motion.FADE.PICKER_HOVER_IN : Motion.FADE.PICKER_HOVER_OUT) : 0
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Icon {
                readonly property string host: root.glyphs ? root.glyphs.screenGlyph(slot.modelData.id) : ""
                anchors.centerIn: parent
                name: host === "" ? slot.modelData.icon : ""
                glyph: host
                size: priv.px("PICKER_GLYPH", 18)
                color: root.theme ? (slot.hot ? root.theme.ink : root.theme.alpha(root.theme.ink, 0.90)) : "white"
                Behavior on color {
                    ColorAnimation {
                        duration: root.theme ? root.theme.dur(slot.hot ? Motion.FADE.PICKER_HOVER_IN : Motion.FADE.PICKER_HOVER_OUT) : 0
                    }
                }
            }
        }
    }
}
