pragma ComponentBehavior: Bound
import QtQuick
import "Motion.js" as Motion

// Seletor de telas (amendments §6): cinco ícones na pílula (200 x 42, topo
// 22, cap 21), na ordem theme.px.SCREEN_ORDER — o ícone k é Alt+k. Fica
// DENTRO do HoverBar, em coordenadas da janela. Os ícones têm x final fixo
// em relação ao centro e só acompanham morph.centerY: o recorte que alarga
// os revela (regra 2 do anti-glitch).
//
// Movimento (P):
// - Entrada: cada ícone entra em 90 ms depois de 50 + 12·rank ms (rank 0 para
//   os slots 2 e 3, 1 para 1 e 4, 2 para 0 e 5), com escala 0,85 -> 1 no
//   mesmo tempo, em torno do próprio centro.
// - Saída: todos somem juntos em 60 ms (P out, F).
// - Slot sob o ponteiro: círculo 30 com tinta a 10% (16% pressionado) e o
//   glifo vai de 90% a 100%; entra em 110 ms, sai em 70 ms.
//
// Sem rótulos nem dicas: seria conteúdo fora da forma. A dica da linha
// (LineHint) explica o gesto. A Mídia aparece sempre (posições estáveis).
//
//   hitTest(x, y) em coordenadas da janela -> "pick:<id>" | "pick:" (vãos) | ""
//   setHover(id)  destaca o slot (a IslandWindow chama com o ponteiro)
Item {
    id: root

    property Theme theme: null
    property var strings: null
    property var morph: null
    property bool rtl: false
    property bool shown: false
    // Botão apertado sobre o slot destacado (opcional; a IslandWindow liga).
    property bool pressed: false

    readonly property string hoverId: priv.hoverId
    implicitWidth: priv.px("PICKER_W", 236)
    implicitHeight: priv.px("PICKER_H", 42)

    // Ícone e rótulo de cada tela; a ordem é a de theme.px.SCREEN_ORDER.
    readonly property var screenMeta: ({
        launcher: { icon: "apps", label: "cc.apps" },
        themes: { icon: "palette", label: "cc.themes" },
        wallpapers: { icon: "wallpaper", label: "cc.wallpapers" },
        media: { icon: "music_note", label: "picker.media" },
        control: { icon: "tune", label: "picker.control" },
        power: { icon: "power_settings_new", label: "cc.power" }
    })
    readonly property var slots: (root.theme ? root.theme.px.SCREEN_ORDER : ["launcher", "themes", "media", "control", "power"])
        .map(id => Object.assign({ id: id }, root.screenMeta[id]))

    readonly property real cx: root.morph ? root.morph.centerX : root.width / 2
    readonly property real cy: root.morph ? root.morph.centerY : 43

    // Centro x do slot i: LTR left + 10 + 18 + 36·i (left = cx − 118); RTL espelha.
    function slotCenter(i) {
        const left = root.cx - priv.px("PICKER_W", 236) / 2;
        const c = left + priv.px("PICKER_PAD", 10) + priv.px("PICKER_PITCH", 36) / 2 + priv.px("PICKER_PITCH", 36) * i;
        return root.rtl ? 2 * root.cx - c : c;
    }

    // Slot: 36 de largura x a altura toda da forma. Os vãos (e o resto da
    // zona) devolvem "pick:" (o toque fecha o seletor).
    function hitTest(x, y) {
        if (!root.shown)
            return "";
        const halfW = priv.px("PICKER_W", 236) / 2 + priv.px("ZONE_PAD", 6);
        if (Math.abs(x - root.cx) > halfW || y < 0 || y > priv.px("ZONE_PICKER_H", 66))
            return "";
        const top = priv.px("PICKER_TOP", 22), bottom = top + priv.px("PICKER_H", 42);
        if (y >= top && y <= bottom) {
            const half = priv.px("PICKER_PITCH", 36) / 2;
            for (let i = 0; i < root.slots.length; i++) {
                if (Math.abs(x - root.slotCenter(i)) <= half)
                    return "pick:" + root.slots[i].id;
            }
        }
        return "pick:";
    }

    function setHover(id) {
        priv.hoverId = root.shown ? String(id || "") : "";
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
                anchors.centerIn: parent
                name: slot.modelData.icon
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
