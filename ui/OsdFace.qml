pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Commons as Commons
import "Motion.js" as Motion

// Desenho do OSD na pílula (screens §4). Dono: Agent I. Fica dentro do
// recorte do conteúdo da IslandWindow, centrado em cx e no centerY do morph;
// a janela cuida do fade da face (I) e do toque (OsdBridge.activate).
//
// Tamanhos (px lógicos; altura 40, topo 10, raio 20 — Theme.geometryFor "osd"):
// - Progresso: 304 = 16 | glifo 18 | 12 | barra 196 x 6 (raio 3, trilho
//   raised, preenchimento accent; mudo inkFaint) | 12 | valor 34 alinhado
//   na ponta (12,5 / 600 tnum ink) | 16. Se "100 %" no idioma não couber em
//   34, o valor cresce e a barra cede o mesmo tanto: o total fica 304.
// - Mensagem: clamp(16 + 18 + 12 + texto + 16, 200, 360); texto 13 / 500,
//   uma linha, elide. O grupo glifo + texto fica centrado.
// - Mídia: capa 24 (raio 6; sem capa, o glifo num quadrado raised) | 10 |
//   título 13 / 600 ink + 6 + artista 13 / 500 inkMuted; clamp 220..360.
// - Glifo: Material Symbols (payload.glyph) ou, para chave não-ASCII do host
//   (ex.: o glifo Nerd Font do download do yt-dlp), o próprio caractere na
//   fonte do sistema (Commons.Style.fontFamily).
//
// Movimento: um OSD novo (payload.seq novo) já nasce no valor; atualizações
// dentro do mesmo OSD levam a barra até o valor em 120 ms OutCubic (o arrasto
// não existe aqui). Trocar de tipo com o OSD aberto (volume -> mensagem)
// reapresenta o conteúdo em 90 ms depois de 40 ms. Reduzir movimento: tudo 0.
//
// RTL: o espelho é explícito (x' = largura − x − w); o espelhamento herdado
// da janela fica desligado aqui para não espelhar duas vezes. A barra enche
// da direita, o glifo vai para a direita e o valor para a esquerda.
//
// O último payload fica desenhado depois do hide(): o fade de saída mostra o
// que estava na tela, sem pular de tamanho.
Item {
    id: root

    property Theme theme: null
    property var strings: null
    // OsdBridge.payload: {kind, iconKey, glyph, rawGlyph, value, max, percent,
    // muted, text, title, artist, art, sticky, duration, internal, seq}
    property var payload: null

    // O que está desenhado (o último payload não nulo).
    readonly property var shown: priv.shown
    readonly property string kind: root.shown ? String(root.shown.kind || "message") : "message"
    readonly property bool rtl: !!root.theme && root.theme.rtl
    readonly property bool muted: !!root.shown && !!root.shown.muted

    // ---- Medidas (Theme.px e screens §4) ----
    readonly property real pad: 16
    readonly property real glyphBox: 18
    readonly property real glyphGap: 12
    readonly property real artBox: 24
    readonly property real artGap: 10
    readonly property real titleGap: 6
    readonly property real valueMin: 34
    readonly property real barBase: 196

    // Progresso: coluna do valor larga o bastante para "100 %" no idioma.
    readonly property real valueW: Math.max(root.valueMin, Math.min(72, Math.ceil(Math.max(fullMetrics.advanceWidth, valueMetrics.advanceWidth))))
    readonly property real barW: Math.max(120, root.barBase - (root.valueW - root.valueMin))

    // Mensagem e mídia: largura do texto medida (nunca de Row).
    readonly property real messageW: Math.ceil(messageMetrics.advanceWidth)
    readonly property real titleW: Math.ceil(titleMetrics.advanceWidth)
    readonly property real artistW: root.artistText !== "" ? Math.ceil(artistMetrics.advanceWidth) : 0
    readonly property real mediaTextW: root.titleW + (root.artistW > 0 ? root.titleGap + root.artistW : 0)
    readonly property real leadW: root.kind === "media" ? root.artBox : root.glyphBox
    readonly property real leadGap: root.kind === "media" ? root.artGap : root.glyphGap
    readonly property real textW: root.kind === "media" ? root.mediaTextW : root.messageW

    implicitWidth: root.kind === "progress" ? (root.theme ? root.theme.px.OSD_W : 304)
        : Math.max(root.kind === "media" ? 220 : 200, Math.min(480, root.pad + root.leadW + root.leadGap + root.textW + root.pad))
    implicitHeight: root.theme ? root.theme.px.OSD_H : 40

    // Grupo (mensagem e mídia): centrado quando a largura mínima sobra.
    readonly property real textRoom: Math.max(0, root.implicitWidth - 2 * root.pad - root.leadW - root.leadGap)
    readonly property real groupW: root.leadW + root.leadGap + Math.min(root.textW, root.textRoom)
    readonly property real groupX: root.kind === "progress" ? root.pad : Math.max(root.pad, (root.implicitWidth - root.groupW) / 2)

    // Título e artista dividem o espaço: o artista cede primeiro.
    readonly property real titleShownW: {
        const room = Math.min(root.textW, root.textRoom);
        if (root.artistW <= 0)
            return Math.min(root.titleW, room);
        const keep = Math.min(root.titleW, Math.max(room * 0.6, room - root.titleGap - root.artistW));
        return room - keep - root.titleGap < 24 ? Math.min(root.titleW, room) : keep;
    }
    readonly property real artistShownW: root.artistW <= 0 ? 0 : Math.max(0, Math.min(root.artistW, root.textRoom - root.titleShownW - root.titleGap))

    readonly property string valueText: root.shown ? String(root.shown.text || "") : ""
    readonly property string messageText: root.shown && root.kind === "message" ? String(root.shown.text || "") : ""
    readonly property string titleText: root.shown && root.kind === "media" ? String(root.shown.title || root.shown.text || "") : ""
    readonly property string artistText: root.shown && root.kind === "media" ? String(root.shown.artist || "") : ""
    readonly property string rawText: root.shown ? String(root.shown.rawGlyph || "") : ""
    readonly property string leadGlyph: root.shown && root.shown.glyph ? String(root.shown.glyph) : "info"
    readonly property string artUrl: root.shown && root.kind === "media" ? String(root.shown.art || "") : ""
    readonly property real target: !root.shown || root.kind !== "progress" ? 0 : Math.max(0, Math.min(1, Number(root.shown.value) / Math.max(1, Number(root.shown.max) || 100)))

    // Preenchimento mostrado (anima entre atualizações do mesmo OSD).
    property real fill: 0

    // Quem sabe o que o toque faz é a IslandWindow (OsdBridge.activate).
    signal clicked()

    Accessible.role: Accessible.StaticText
    Accessible.name: {
        if (!root.shown)
            return "";
        const s = root.strings;
        const key = String(root.shown.iconKey || "");
        const g = root.leadGlyph;
        if (root.kind === "media")
            return root.artistText !== "" && s ? s.t("bar.trackArtist").arg(root.titleText).arg(root.artistText) : root.titleText;
        if (!s)
            return root.valueText;
        if (root.kind === "progress") {
            if (root.muted && g.indexOf("volume_") === 0)
                return s.t("osd.muted");
            if (g.indexOf("volume_") === 0)
                return s.t("osd.volume") + " " + root.valueText;
            if (key === "brightness" || key === "display" || g === "light_mode")
                return s.t("osd.brightness") + " " + root.valueText;
            return root.valueText;
        }
        if (root.messageText === "" && g === "mic_off")
            return s.t("osd.micMuted");
        if (root.messageText === "" && g === "mic")
            return s.t("osd.micOn");
        return root.messageText;
    }

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    // x de um item numa linha LTR, espelhado em RTL.
    function mx(x, w) {
        return root.rtl ? root.width - x - w : x;
    }

    function dur(ms) {
        return root.theme ? root.theme.dur(ms) : ms;
    }

    onPayloadChanged: priv.take(root.payload)
    Component.onCompleted: priv.take(root.payload)

    QtObject {
        id: priv
        property var shown: null
        property int seq: -1
        property string kind: ""

        function take(p) {
            if (!p || typeof p !== "object")
                return;
            const seq = Number(p.seq) || 0;
            const kind = String(p.kind || "message");
            const fresh = seq !== priv.seq;
            const kindChanged = priv.kind !== "" && kind !== priv.kind;
            priv.shown = p;
            priv.seq = seq;
            priv.kind = kind;
            const f = root.target;
            if (fresh) {
                // OSD novo: nasce no valor (a face entra com o fade da janela).
                fillAnim.stop();
                root.fill = f;
                if (kindChanged && root.opacity > 0.01) {
                    // Troca de tipo com o OSD na tela: reapresenta o conteúdo.
                    contentIn.stop();
                    content.opacity = 0;
                    contentIn.start();
                } else {
                    contentIn.stop();
                    content.opacity = 1;
                }
            } else if (Math.abs(f - root.fill) > 0.0005 && (!fillAnim.running || fillAnim.to !== f)) {
                fillAnim.stop();
                fillAnim.from = root.fill;
                fillAnim.to = f;
                fillAnim.duration = root.dur(Motion.FADE.OSD_VALUE);
                fillAnim.start();
            }
        }
    }

    NumberAnimation {
        id: fillAnim
        target: root
        property: "fill"
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: contentIn
        PauseAnimation { duration: root.dur(Motion.FADE.OSD_IN.delay) }
        NumberAnimation {
            target: content
            property: "opacity"
            to: 1
            duration: root.dur(Motion.FADE.OSD_IN.dur)
            easing.type: Easing.OutCubic
        }
    }

    IlhaMetrics { id: messageMetrics; theme: root.theme; size: 13; weight: 500; text: root.messageText }
    IlhaMetrics { id: titleMetrics; theme: root.theme; size: 13; weight: 600; text: root.titleText }
    IlhaMetrics { id: artistMetrics; theme: root.theme; size: 13; weight: 500; text: root.artistText }
    IlhaMetrics { id: valueMetrics; theme: root.theme; size: 12.5; weight: 600; tnum: true; text: root.kind === "progress" ? root.valueText : "" }
    IlhaMetrics {
        id: fullMetrics
        theme: root.theme
        size: 12.5
        weight: 600
        tnum: true
        text: root.strings ? root.strings.t("common.percent").arg(Commons.I18n.formatNumber(100)) : "100%"
    }

    Item {
        id: content
        anchors.fill: parent

        // ---- Glifo (progresso e mensagem) ----
        Item {
            id: glyphCell
            readonly property bool wanted: root.kind !== "media"
            x: root.mx(root.groupX, root.glyphBox)
            y: (root.height - root.glyphBox) / 2
            width: root.glyphBox
            height: root.glyphBox
            opacity: glyphCell.wanted ? 1 : 0

            Icon {
                anchors.fill: parent
                size: root.glyphBox
                name: root.leadGlyph
                filled: !root.muted
                color: root.theme ? (root.muted ? root.theme.inkMuted : root.theme.ink) : "white"
                opacity: root.rawText === "" ? 1 : 0
            }
            // Chave não-ASCII do host: o glifo como veio, na fonte do sistema.
            IlhaText {
                anchors.centerIn: parent
                theme: root.theme
                size: root.glyphBox
                weight: 400
                font.family: Commons.Style.fontFamily
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: root.theme ? root.theme.ink : "white"
                text: root.rawText
                opacity: root.rawText !== "" ? 1 : 0
            }
        }

        // ---- Progresso: barra e valor ----
        Rectangle {
            id: track
            readonly property real lx: root.pad + root.glyphBox + root.glyphGap
            x: root.mx(track.lx, root.barW)
            y: (root.height - 6) / 2
            width: root.barW
            height: 6
            radius: 3
            color: root.theme ? root.theme.raised : "gray"
            opacity: root.kind === "progress" ? 1 : 0

            Rectangle {
                readonly property real w: Math.round(track.width * Math.max(0, Math.min(1, root.fill)) * 2) / 2
                x: root.rtl ? track.width - width : 0
                width: w
                height: track.height
                radius: track.radius
                color: root.theme ? (root.muted ? root.theme.inkFaint : root.theme.accent) : "white"
                Behavior on color {
                    ColorAnimation { duration: root.dur(Motion.FADE.OSD_VALUE); easing.type: Easing.OutCubic }
                }
            }
        }
        IlhaText {
            readonly property real lx: root.pad + root.glyphBox + root.glyphGap + root.barW + root.glyphGap
            x: root.mx(lx, root.valueW)
            anchors.verticalCenter: parent.verticalCenter
            width: root.valueW
            theme: root.theme
            size: 12.5
            weight: 600
            tnum: true
            maximumLineCount: 1
            elide: Text.ElideNone
            horizontalAlignment: root.rtl ? Text.AlignLeft : Text.AlignRight
            text: root.kind === "progress" ? root.valueText : ""
            opacity: root.kind === "progress" ? 1 : 0
        }

        // ---- Mensagem ----
        IlhaText {
            readonly property real lx: root.groupX + root.glyphBox + root.glyphGap
            readonly property real w: Math.min(root.messageW, root.textRoom)
            x: root.mx(lx, w)
            anchors.verticalCenter: parent.verticalCenter
            width: w
            theme: root.theme
            size: 13
            weight: 500
            maximumLineCount: 1
            elide: Text.ElideRight
            horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
            text: root.messageText
            opacity: root.kind === "message" ? 1 : 0
        }

        // ---- Mídia: capa, título e artista ----
        Item {
            id: artCell
            readonly property bool wanted: root.kind === "media"
            readonly property bool ready: art.status === Image.Ready && root.artUrl !== ""
            x: root.mx(root.groupX, root.artBox)
            y: (root.height - root.artBox) / 2
            width: root.artBox
            height: root.artBox
            opacity: artCell.wanted ? 1 : 0

            // Sem capa: o glifo da ação (nota, play, pausa…) num quadrado raised.
            Rectangle {
                anchors.fill: parent
                radius: 6
                color: root.theme ? root.theme.raised : "gray"
                opacity: artCell.ready ? 0 : 1
                Icon {
                    anchors.centerIn: parent
                    size: 16
                    name: root.leadGlyph
                    filled: true
                    color: root.theme ? root.theme.ink : "white"
                }
            }
            Image {
                id: art
                anchors.fill: parent
                source: artCell.wanted ? root.artUrl : ""
                sourceSize: Qt.size(48, 48)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                visible: false
            }
            Item {
                id: artMask
                anchors.fill: parent
                visible: false
                layer.enabled: artCell.wanted
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: "black"
                }
            }
            MultiEffect {
                anchors.fill: parent
                source: art
                visible: artCell.wanted && artCell.ready
                maskEnabled: true
                maskSource: artMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
        IlhaText {
            readonly property real lx: root.groupX + root.artBox + root.artGap
            x: root.mx(lx, root.titleShownW)
            anchors.verticalCenter: parent.verticalCenter
            width: root.titleShownW
            theme: root.theme
            size: 13
            weight: 600
            maximumLineCount: 1
            elide: Text.ElideRight
            horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
            text: root.titleText
            opacity: root.kind === "media" ? 1 : 0
        }
        IlhaText {
            readonly property real lx: root.groupX + root.artBox + root.artGap + root.titleShownW + root.titleGap
            x: root.mx(lx, root.artistShownW)
            anchors.verticalCenter: parent.verticalCenter
            width: root.artistShownW
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            maximumLineCount: 1
            elide: Text.ElideRight
            horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
            text: root.artistText
            opacity: root.kind === "media" && root.artistShownW > 0 ? 1 : 0
        }
    }
}
