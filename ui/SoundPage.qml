pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import "Motion.js" as Motion

// Subpágina Som da Central (screens §8; vídeo 11:19.7-11:20.7). Dono: Agent E.
//
// Coordenadas do cartão (x 22, y 21 no painel, 470 de largura; o fundo é do
// contêiner da Central, que também faz a transformação J e o fade):
// - Voltar 24 em (26, 34); título x 52, topo da maiúscula 26, 18.5 / 600.
// - "Saída" (topo da maiúscula 71.25, 12.5 / 500 inkMuted). Linhas de saída
//   a partir de y 96: 442 x 40.5, passo 45, raio 9.5, raised; círculo 30 a 8;
//   rótulo x 49.5, 14.5 (600 selecionada); ✓ a 15 da direita.
// - Barra de saída 11.5 abaixo das linhas: 398 x 28, "79%" alinhado à direita
//   da linha (12.5 inkMuted, tnum).
// - "Entrada" 15 abaixo da barra; linhas 23.5 abaixo do rótulo; barra 10.5
//   abaixo das linhas; 14 de margem embaixo.
// - cardH = 217.5 + 45·(min(nOut,5) + min(nIn,3)); lista vazia conta como uma
//   linha ("Nenhum dispositivo…"). Mais de 5 saídas / 3 entradas rolam dentro
//   da lista. Acima de maxHeight o corpo rola (o cabeçalho fica).
// - Toque no glifo da barra: mudo. Mudo: preenchimento inkFaint e glifo
//   volume_off / mic_off.
// - Teclado: Cima/Baixo andam (linhas e barras), Enter/Espaço escolhem a
//   linha ou alternam o mudo na barra, Esquerda/Direita ±5% (Shift ±1%,
//   espelhado em RTL), M muda a seção focada, Esc volta.
// - A sondagem de disponibilidade (AudioSvc.detailOpen) só roda aberta.
Item {
    id: root

    property var island: null
    property Theme theme: null
    property var strings: null
    property bool keyboardMode: false
    property real maxHeight: 900

    signal back()

    readonly property var audio: root.island ? root.island.audio : null
    readonly property int nOut: root.audio ? root.audio.sinks.length : 0
    readonly property int nIn: root.audio ? root.audio.sources.length : 0
    // Linhas visíveis (lista vazia ocupa uma, com o aviso).
    readonly property int visOut: Math.max(1, Math.min(root.nOut, 5))
    readonly property int visIn: Math.max(1, Math.min(root.nIn, 3))
    readonly property real fullHeight: 217.5 + 45 * (root.visOut + root.visIn)
    // O corpo começa abaixo do cabeçalho (voltar + título).
    readonly property real bodyTop: 52

    width: 470
    implicitWidth: 470
    implicitHeight: Math.min(root.fullHeight, Math.max(160, root.maxHeight))

    function opened() {
        priv.snapping = true;
        body.contentY = 0;
        outList.positionViewAtBeginning();
        inList.positionViewAtBeginning();
        priv.focusKey = "ov";
        if (root.audio)
            root.audio.detailOpen = true;
        Qt.callLater(() => priv.snapping = false);
    }

    function closed() {
        if (root.audio)
            root.audio.detailOpen = false;
    }

    function handleKey(event) {
        const k = event.key;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (mods !== 0)
            return false;
        const keys = priv.targets;
        let i = keys.indexOf(priv.focusKey);
        if (i < 0) {
            priv.focusKey = "ov";
            i = keys.indexOf("ov");
        }
        switch (k) {
        case Qt.Key_Down:
        case Qt.Key_Up: {
            const next = Math.max(0, Math.min(keys.length - 1, i + (k === Qt.Key_Down ? 1 : -1)));
            priv.focus(keys[next]);
            return true;
        }
        case Qt.Key_Home:
            priv.focus(keys[0]);
            return true;
        case Qt.Key_End:
            priv.focus(keys[keys.length - 1]);
            return true;
        case Qt.Key_Left:
        case Qt.Key_Right: {
            const slider = priv.focusKey === "ov" ? outSlider : priv.focusKey === "iv" ? inSlider : null;
            if (!slider)
                return true;
            const sign = (k === Qt.Key_Right ? 1 : -1) * (root.theme && root.theme.rtl ? -1 : 1);
            slider.nudge(sign * ((event.modifiers & Qt.ShiftModifier) ? 0.01 : 0.05));
            return true;
        }
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            priv.activate();
            return true;
        case Qt.Key_M:
            if (!root.audio)
                return true;
            if (priv.focusKey === "iv" || priv.focusKey.indexOf("i:") === 0)
                root.audio.setMicMuted(!root.audio.micMuted);
            else
                root.audio.toggleMute();
            return true;
        default:
            return false;
        }
    }

    function handleEscape() {
        root.back();
        return true;
    }

    function tr(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    function percent(v) {
        return root.tr("common.percent").arg(Commons.I18n.formatNumber(Math.round(v * 100)));
    }

    // Topo da maiúscula -> y do texto (Inter: ascendente 0.96875, maiúscula 0.7275).
    function capY(capTop, size) {
        return capTop - 0.24125 * Math.round(size);
    }

    QtObject {
        id: priv
        property bool snapping: false
        // "o:N" linha de saída, "ov" barra de saída, "i:N" entrada, "iv" barra de entrada.
        property string focusKey: "ov"

        readonly property var targets: {
            const t = [];
            for (let i = 0; i < root.nOut; i++)
                t.push("o:" + i);
            t.push("ov");
            for (let i = 0; i < root.nIn; i++)
                t.push("i:" + i);
            t.push("iv");
            return t;
        }

        function focus(key) {
            priv.focusKey = key;
            let item = null;
            if (key === "ov")
                item = outSlider;
            else if (key === "iv")
                item = inSlider;
            else {
                const list = key.indexOf("o:") === 0 ? outList : inList;
                const idx = Number(key.slice(2));
                list.positionViewAtIndex(idx, ListView.Contain);
                item = list;
            }
            priv.reveal(item);
        }

        // Mantém o item focado à vista no corpo que rola.
        function reveal(item) {
            if (!item || body.contentHeight <= body.height)
                return;
            const p = item.mapToItem(content, 0, 0);
            const pad = 8;
            let y = body.contentY;
            if (p.y < y + pad)
                y = p.y - pad;
            else if (p.y + item.height > y + body.height - pad)
                y = p.y + item.height - body.height + pad;
            body.contentY = Math.max(0, Math.min(body.contentHeight - body.height, y));
        }

        function activate() {
            const a = root.audio;
            if (!a)
                return;
            const key = priv.focusKey;
            if (key === "ov")
                a.toggleMute();
            else if (key === "iv")
                a.setMicMuted(!a.micMuted);
            else if (key.indexOf("o:") === 0) {
                const row = a.sinks[Number(key.slice(2))];
                if (row)
                    a.selectSink(row.node);
            } else if (key.indexOf("i:") === 0) {
                const row = a.sources[Number(key.slice(2))];
                if (row)
                    a.selectSource(row.node);
            }
        }

        function volumeGlyph(v, muted) {
            if (muted || v <= 0)
                return "volume_off";
            if (v <= 0.33)
                return "volume_mute";
            if (v <= 0.66)
                return "volume_down";
            return "volume_up";
        }
    }

    // Uma lista que some do fim leva o foco para a barra da seção.
    onNOutChanged: if (priv.focusKey.indexOf("o:") === 0 && Number(priv.focusKey.slice(2)) >= root.nOut) priv.focusKey = "ov"
    onNInChanged: if (priv.focusKey.indexOf("i:") === 0 && Number(priv.focusKey.slice(2)) >= root.nIn) priv.focusKey = "iv"

    // ---- Cabeçalho ----
    CircleButton {
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 22
        theme: root.theme
        icon: "chevron_left"
        flip: !!root.theme && root.theme.rtl
        size: 24
        glyphSize: 14
        accessibleName: root.tr("common.back")
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
        text: root.tr("sound.title")
    }

    // ---- Corpo (rola só acima de maxHeight) ----
    Flickable {
        id: body
        y: root.bodyTop
        width: parent.width
        height: Math.max(0, root.height - root.bodyTop)
        contentWidth: width
        contentHeight: root.fullHeight - root.bodyTop
        interactive: body.contentHeight > body.height + 0.5
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Item {
            id: content
            width: body.width
            height: body.contentHeight

            // Saída
            IlhaText {
                id: outLabel
                anchors.left: parent.left
                anchors.leftMargin: 14
                y: root.capY(71.25, 12.5) - root.bodyTop
                theme: root.theme
                size: 12.5
                weight: 500
                color: root.theme ? root.theme.inkMuted : "gray"
                text: root.tr("sound.output")
            }

            ListView {
                id: outList
                anchors.left: parent.left
                anchors.leftMargin: 14
                y: 96 - root.bodyTop
                width: 442
                height: 45 * root.visOut - 4.5
                spacing: 4.5
                clip: true
                interactive: root.nOut > 5
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                model: root.nOut
                delegate: ListRow {
                    id: outRow
                    required property int index
                    readonly property var d: root.audio && outRow.index < root.audio.sinks.length ? root.audio.sinks[outRow.index] : null
                    width: 442
                    rowHeight: 40.5
                    circleSize: 30
                    circleInset: 8
                    labelSize: 14.5
                    labelWeight: 500
                    radius: 9.5
                    theme: root.theme
                    icon: outRow.d ? outRow.d.glyph : ""
                    label: outRow.d ? outRow.d.label : ""
                    selected: !!outRow.d && outRow.d.selected
                    trailing: outRow.selected ? "check" : ""
                    focused: root.keyboardMode && priv.focusKey === "o:" + outRow.index
                    onClicked: {
                        priv.focusKey = "o:" + outRow.index;
                        if (root.audio && outRow.d)
                            root.audio.selectSink(outRow.d.node);
                    }
                }
            }
            IlhaText {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: outList.top
                anchors.verticalCenterOffset: 20.25
                opacity: root.nOut === 0 ? 1 : 0
                theme: root.theme
                size: 13
                weight: 500
                color: root.theme ? root.theme.inkMuted : "gray"
                text: root.tr("sound.noOutput")
            }

            IlhaSlider {
                id: outSlider
                anchors.left: parent.left
                anchors.leftMargin: 14
                y: outList.y + outList.height + 11.5
                width: 398
                barHeight: 28
                theme: root.theme
                enabled: !!root.audio && root.audio.hasOutput
                value: root.audio ? root.audio.volume : 0
                glyph: priv.volumeGlyph(outSlider.shownValue, !!root.audio && root.audio.muted)
                fillColor: root.theme ? (root.audio && root.audio.muted ? root.theme.inkFaint : root.theme.accent) : "white"
                glyphColor: root.theme ? (root.audio && root.audio.muted ? root.theme.surface : root.theme.onAccent) : "black"
                focused: root.keyboardMode && priv.focusKey === "ov"
                accessibleName: root.tr("sound.output")
                onMoved: v => {
                    priv.focusKey = "ov";
                    if (root.audio)
                        root.audio.setVolume(v);
                }
                onGlyphTapped: if (root.audio) root.audio.toggleMute()
            }
            IlhaText {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: outSlider.verticalCenter
                theme: root.theme
                size: 12.5
                weight: 500
                tnum: true
                color: root.theme ? root.theme.inkMuted : "gray"
                text: root.percent(outSlider.shownValue)
            }

            // Entrada
            IlhaText {
                id: inLabel
                anchors.left: parent.left
                anchors.leftMargin: 14
                y: root.capY(outSlider.y + outSlider.height + 15, 12.5)
                theme: root.theme
                size: 12.5
                weight: 500
                color: root.theme ? root.theme.inkMuted : "gray"
                text: root.tr("sound.input")
            }

            ListView {
                id: inList
                anchors.left: parent.left
                anchors.leftMargin: 14
                y: outSlider.y + outSlider.height + 15 + 23.5
                width: 442
                height: 45 * root.visIn - 4.5
                spacing: 4.5
                clip: true
                interactive: root.nIn > 3
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                model: root.nIn
                delegate: ListRow {
                    id: inRow
                    required property int index
                    readonly property var d: root.audio && inRow.index < root.audio.sources.length ? root.audio.sources[inRow.index] : null
                    width: 442
                    rowHeight: 40.5
                    circleSize: 30
                    circleInset: 8
                    labelSize: 14.5
                    labelWeight: 500
                    radius: 9.5
                    theme: root.theme
                    icon: inRow.d ? inRow.d.glyph : ""
                    label: inRow.d ? inRow.d.label : ""
                    selected: !!inRow.d && inRow.d.selected
                    trailing: inRow.selected ? "check" : ""
                    focused: root.keyboardMode && priv.focusKey === "i:" + inRow.index
                    onClicked: {
                        priv.focusKey = "i:" + inRow.index;
                        if (root.audio && inRow.d)
                            root.audio.selectSource(inRow.d.node);
                    }
                }
            }
            IlhaText {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: inList.top
                anchors.verticalCenterOffset: 20.25
                opacity: root.nIn === 0 ? 1 : 0
                theme: root.theme
                size: 13
                weight: 500
                color: root.theme ? root.theme.inkMuted : "gray"
                text: root.tr("sound.noInput")
            }

            IlhaSlider {
                id: inSlider
                anchors.left: parent.left
                anchors.leftMargin: 14
                y: inList.y + inList.height + 10.5
                width: 398
                barHeight: 28
                theme: root.theme
                enabled: !!root.audio && root.audio.hasInput
                value: root.audio ? root.audio.micVolume : 0
                glyph: root.audio && (root.audio.micMuted || inSlider.shownValue <= 0) ? "mic_off" : "mic"
                fillColor: root.theme ? (root.audio && root.audio.micMuted ? root.theme.inkFaint : root.theme.accent) : "white"
                glyphColor: root.theme ? (root.audio && root.audio.micMuted ? root.theme.surface : root.theme.onAccent) : "black"
                focused: root.keyboardMode && priv.focusKey === "iv"
                accessibleName: root.tr("sound.input")
                onMoved: v => {
                    priv.focusKey = "iv";
                    if (root.audio)
                        root.audio.setMicVolume(v);
                }
                onGlyphTapped: if (root.audio) root.audio.setMicMuted(!root.audio.micMuted)
            }
            IlhaText {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: inSlider.verticalCenter
                theme: root.theme
                size: 12.5
                weight: 500
                tnum: true
                color: root.theme ? root.theme.inkMuted : "gray"
                text: root.percent(inSlider.shownValue)
            }
        }
    }
}
