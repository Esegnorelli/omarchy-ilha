pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "Motion.js" as Motion

// Navegação das telas: uma cápsula pequena logo abaixo da tela aberta, com
// Voltar e os seis destinos na ordem de theme.px.SCREEN_ORDER (o ícone k é
// Alt+k, como no seletor). A tela atual fica marcada em accent.
//
// - Desenhada pela IslandWindow FORA do recorte do conteúdo; a máscara de
//   entrada ganha o retângulo-alvo dela (navRect) só com uma tela aberta.
// - Acompanha a borda de baixo do painel (topY vem do valor animado da
//   forma), então nenhuma tela muda de tamanho.
// - Voltar: a IslandWindow decide (subpágina da Central, tela anterior ou
//   fechar). Alt+← e o botão "voltar" do mouse fazem o mesmo.
// - Entra 90 ms depois da tela, em 120 ms descendo 4 px; sai em 60 ms.
//
//   Largura = 2·NAV_PAD + NAV_PITCH (Voltar) + NAV_DIV + 6·NAV_PITCH; altura NAV_H.
Item {
    id: root

    property Theme theme: null
    property var strings: null
    property bool glassy: false
    property bool rtl: false
    property bool shown: false
    property real cx: 960
    property real topY: 0
    // Tela aberta (marcada) e se há para onde voltar além de fechar.
    property string current: ""
    property bool canBack: false

    signal back()
    signal pick(string id)

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

    readonly property real pitch: priv.px("NAV_PITCH", 36)
    readonly property real pad: priv.px("NAV_PAD", 6)
    readonly property real div: priv.px("NAV_DIV", 9)
    implicitWidth: 2 * root.pad + root.pitch + root.div + root.slots.length * root.pitch
    implicitHeight: priv.px("NAV_H", 40)

    // Deslocamento da entrada (−4 -> 0).
    property real dy: 0
    x: root.cx - root.implicitWidth / 2
    y: root.topY + root.dy
    width: root.implicitWidth
    height: root.implicitHeight
    opacity: 0
    visible: root.opacity > 0
    enabled: root.shown

    Accessible.role: Accessible.Grouping
    Accessible.name: root.strings ? root.strings.t("picker.title") : ""
    Accessible.ignored: !root.shown

    // x do slot k em LTR (0 = Voltar, 1..6 = destinos); RTL espelha.
    function slotX(k) {
        const lx = k === 0 ? root.pad : root.pad + root.pitch + root.div + (k - 1) * root.pitch;
        return root.rtl ? root.width - lx - root.pitch : lx;
    }

    onShownChanged: {
        fadeIn.stop();
        fadeOut.stop();
        if (!root.theme || root.theme.reduceMotion) {
            root.dy = 0;
            root.opacity = root.shown ? 1 : 0;
            return;
        }
        if (root.shown) {
            root.dy = Motion.FADE.NAV_IN.dyFrom * (1 - root.opacity);
            fadeIn.start();
        } else {
            fadeOut.start();
        }
    }

    SequentialAnimation {
        id: fadeIn
        PauseAnimation { duration: Motion.FADE.NAV_IN.delay }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1
                duration: Motion.FADE.NAV_IN.dur
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "dy"
                to: 0
                duration: Motion.FADE.NAV_IN.dur
                easing.type: Easing.OutCubic
            }
        }
    }
    NumberAnimation {
        id: fadeOut
        target: root
        property: "opacity"
        to: 0
        duration: Motion.FADE.NAV_OUT
        easing.type: Easing.OutCubic
    }

    QtObject {
        id: priv
        function px(name, fallback) {
            return root.theme && root.theme.px[name] !== undefined ? root.theme.px[name] : fallback;
        }
    }

    RectangularShadow {
        anchors.fill: bg
        radius: bg.radius
        blur: 18
        offset.y: 3
        spread: 0
        color: Qt.rgba(0, 0, 0, root.glassy ? 0.30 : 0.40)
    }
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.height / 2
        antialiasing: true
        color: root.theme ? root.theme.surface : "black"
        border.width: 1
        border.color: root.theme ? root.theme.rim : "transparent"
    }

    // Filete entre Voltar e os destinos.
    Rectangle {
        x: root.rtl ? root.width - root.pad - root.pitch - root.div / 2 - 0.5 : root.pad + root.pitch + root.div / 2 - 0.5
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 18
        color: root.theme ? root.theme.alpha(root.theme.ink, 0.12) : "gray"
    }

    // Um botão redondo da cápsula.
    component NavSlot: Item {
        id: slot
        property string icon: ""
        property string label: ""
        property bool marked: false
        property bool mirrorGlyph: false
        signal activated()

        width: root.pitch
        height: root.height

        Accessible.role: Accessible.Button
        Accessible.name: slot.label
        Accessible.onPressAction: slot.activated()

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: slot.activated()
        }

        Rectangle {
            anchors.centerIn: parent
            width: priv.px("PICKER_HOVER", 30)
            height: width
            radius: width / 2
            color: !root.theme ? "transparent"
                : slot.marked ? root.theme.accentSoft
                : (tap.pressed ? root.theme.pressOverlay : root.theme.hoverOverlay)
            opacity: slot.marked || hover.hovered || tap.pressed ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: root.theme ? root.theme.dur(hover.hovered ? Motion.FADE.PICKER_HOVER_IN : Motion.FADE.PICKER_HOVER_OUT) : 0
                    easing.type: Easing.OutCubic
                }
            }
        }

        Icon {
            anchors.centerIn: parent
            name: slot.icon
            size: priv.px("PICKER_GLYPH", 18)
            color: !root.theme ? "white"
                : slot.marked ? root.theme.accentInk
                : (hover.hovered ? root.theme.ink : root.theme.alpha(root.theme.ink, 0.80))
            transform: Scale {
                origin.x: 9
                xScale: slot.mirrorGlyph ? -1 : 1
            }
        }
    }

    NavSlot {
        x: root.slotX(0)
        icon: "chevron_left"
        mirrorGlyph: root.rtl
        label: root.strings ? root.strings.t("common.back") : "Back"
        onActivated: root.back()
    }

    Repeater {
        model: root.slots
        NavSlot {
            required property var modelData
            required property int index
            x: root.slotX(index + 1)
            icon: modelData.icon
            label: root.strings ? root.strings.t(modelData.label) : modelData.id
            marked: root.current === modelData.id
            onActivated: root.pick(modelData.id)
        }
    }
}
