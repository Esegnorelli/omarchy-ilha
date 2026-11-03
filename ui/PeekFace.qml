pragma ComponentBehavior: Bound
import QtQuick
import "Motion.js" as Motion

// Desenho do aviso ao vivo (amendments §9.4). Dono: Agent I. Só desenha:
// toque e hover são da IslandWindow (hitTest devolve "peek" na zona
// inteira). Fica dentro do recorte do conteúdo, como o OsdFace, centrado em
// cx e no centerY do morph (30 assentado).
//
// Geometria (exata):
//   groupW = 18 + 10 + textW     (urgente: textW = min(appW, 120) + 8 + summaryW)
//   peekW  = clamp(16 + groupW + 16, 160, min(480, telaW − 48))
//   grupo centrado: left = (peekW − min(groupW, peekW − 32)) / 2
// - Glifo 18 (cor do tom), texto 10 px depois: 13 / 500 com tnum (os
//   segundos da gravação nunca mexem na largura; só 9:59 -> 10:00 muda).
// - Urgente: app 12,5 / 500 inkMuted (elide em 120) + 8 + resumo 13 / 600.
// - O texto que não cabe faz elide no fim.
// - RTL: o grupo espelha (glifo à direita) e o texto alinha à direita. O
//   espelhamento herdado da janela fica desligado aqui: o espelho é explícito.
//
// Movimento (I+, I+ swap; reduzir movimento = 0):
// - Entrada (repouso -> aviso): o conteúdo entra em 90 ms depois de 40 ms e
//   o glifo cresce de 0,85 a 1 no mesmo tempo (no próprio centro).
// - Troca (outro aviso por cima): o antigo sai em 60 ms; o novo entra em
//   90 ms depois de 40 ms. A forma só muda a largura (implicitWidth novo).
// - Mesma frase atualizada (o relógio da gravação): troca no lugar, sem fade.
// - Saída: payload vira nulo, mas o último conteúdo fica desenhado; quem faz
//   o fade é a janela. Duas camadas (A/B) alternam, cada uma no seu layout
//   final, centradas: nada depende da largura viva do morph.
Item {
    id: root

    property Theme theme: null
    property var strings: null
    // status.peekFor(key, row): {key, icon, filled, tone, text, app, summary, urgent[, rowKey]}
    property var payload: null
    property bool rtl: false
    property real screenW: 1920

    // Medidas da camada da frente (o aviso atual ou o último).
    readonly property bool urgent: root.front.urgent
    readonly property real appW: root.front.appW
    readonly property real textW: root.front.textW
    readonly property real groupW: root.front.groupW
    implicitWidth: root.front.peekW
    implicitHeight: root.theme ? root.theme.px.PEEK_H : 40

    readonly property PeekContent front: priv.useB ? layerB : layerA
    readonly property PeekContent back: priv.useB ? layerA : layerB

    Accessible.role: Accessible.Button
    Accessible.name: {
        const p = root.front.p;
        if (!p)
            return "";
        if (p.urgent && root.strings)
            return root.strings.t("peek.urgent").arg(String(p.summary || p.text || ""));
        return String(p.text || "");
    }

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    function dur(ms) {
        return root.theme ? root.theme.dur(ms) : ms;
    }

    // A mesma frase (mudou só o texto vivo) ou outra?
    function identity(p) {
        if (!p)
            return "";
        return String(p.key || "") + "|" + (p.urgent ? String(p.rowKey || "") + "|" + String(p.summary || "") : "");
    }

    onPayloadChanged: priv.take(root.payload)
    Component.onCompleted: priv.take(root.payload)

    QtObject {
        id: priv
        property bool useB: false
        // Sem aviso na tela (a próxima chegada é uma entrada, não uma troca).
        property bool idle: true

        function take(p) {
            if (!p || typeof p !== "object") {
                priv.idle = true;
                return;
            }
            const cur = root.front;
            if (priv.idle) {
                // Entrada: a camada da frente recebe e entra; a de trás some.
                priv.idle = false;
                root.back.stopAll();
                root.back.opacity = 0;
                root.back.p = null;
                cur.p = p;
                cur.enter();
                return;
            }
            if (root.identity(cur.p) === root.identity(p)) {
                cur.p = p;
                return;
            }
            // Troca: a de trás recebe o novo e vira a da frente.
            const next = root.back;
            next.stopAll();
            next.p = p;
            priv.useB = !priv.useB;
            cur.leave();
            next.swapIn();
        }
    }

    component PeekContent: Item {
        id: c

        property var p: null

        readonly property bool urgent: !!c.p && !!c.p.urgent
        readonly property string appText: c.urgent ? String(c.p.app || "") : ""
        readonly property string mainText: !c.p ? "" : String(c.urgent ? (c.p.summary || c.p.text || "") : (c.p.text || ""))
        readonly property real appW: c.appText !== "" ? Math.min(120, Math.ceil(appMetrics.advanceWidth)) : 0
        readonly property real textW: c.appW + (c.appW > 0 ? 8 : 0) + Math.ceil(mainMetrics.advanceWidth)
        readonly property real groupW: 18 + 10 + c.textW
        readonly property real maxW: Math.min(root.theme ? root.theme.px.PEEK_MAX_W : 480, root.screenW - 48)
        readonly property real peekW: Math.max(root.theme ? root.theme.px.PEEK_MIN_W : 160, Math.min(c.maxW, 16 + c.groupW + 16))
        readonly property real shownGroupW: Math.min(c.groupW, c.peekW - 32)
        readonly property real groupLeft: (c.peekW - c.shownGroupW) / 2
        readonly property real mainW: Math.max(0, c.shownGroupW - 28 - (c.appW > 0 ? c.appW + 8 : 0))

        // x de um item na linha LTR do grupo, espelhado em RTL.
        function gx(x, w) {
            return root.rtl ? c.peekW - c.groupLeft - x - w : c.groupLeft + x;
        }

        function stopAll() {
            inAnim.stop();
            outAnim.stop();
            glyph.scale = 1;
        }

        // I+: entra em 90 ms depois de 40 ms; o glifo cresce junto.
        function enter() {
            c.stopAll();
            c.opacity = 0;
            glyph.scale = Motion.FADE.PEEK_IN.glyphScaleFrom;
            inPause.duration = root.dur(Motion.FADE.PEEK_IN.delay);
            inFade.duration = root.dur(Motion.FADE.PEEK_IN.dur);
            inScale.duration = root.dur(Motion.FADE.PEEK_IN.dur);
            inAnim.start();
        }

        // Troca: o novo entra em 90 ms depois de 40 ms.
        function swapIn() {
            c.stopAll();
            c.opacity = 0;
            glyph.scale = Motion.FADE.PEEK_IN.glyphScaleFrom;
            inPause.duration = root.dur(Motion.FADE.PEEK_SWAP.inDelay);
            inFade.duration = root.dur(Motion.FADE.PEEK_SWAP.inDur);
            inScale.duration = root.dur(Motion.FADE.PEEK_SWAP.inDur);
            inAnim.start();
        }

        // Troca: o antigo sai em 60 ms (parte da opacidade atual).
        function leave() {
            inAnim.stop();
            outAnim.duration = root.dur(Motion.FADE.PEEK_SWAP.out);
            outAnim.start();
        }

        x: (root.width - c.peekW) / 2
        y: 0
        width: c.peekW
        height: root.height
        opacity: 0

        IlhaMetrics { id: appMetrics; theme: root.theme; size: 12.5; weight: 500; text: c.appText }
        IlhaMetrics { id: mainMetrics; theme: root.theme; size: 13; weight: c.urgent ? 600 : 500; tnum: !c.urgent; text: c.mainText }

        SequentialAnimation {
            id: inAnim
            PauseAnimation { id: inPause }
            ParallelAnimation {
                NumberAnimation { id: inFade; target: c; property: "opacity"; to: 1; easing.type: Easing.OutCubic }
                NumberAnimation { id: inScale; target: glyph; property: "scale"; to: 1; easing.type: Easing.OutCubic }
            }
        }
        NumberAnimation {
            id: outAnim
            target: c
            property: "opacity"
            to: 0
            easing.type: Easing.OutCubic
        }

        Icon {
            id: glyph
            x: c.gx(0, 18)
            y: (c.height - 18) / 2
            size: root.theme ? root.theme.px.PEEK_GLYPH : 18
            name: c.p ? String(c.p.icon || "") : ""
            filled: !!c.p && !!c.p.filled
            color: root.theme && c.p ? root.theme.toneColor(c.p.tone) : "white"
        }

        // Urgente: o app antes do resumo.
        IlhaText {
            x: c.gx(28, c.appW)
            anchors.verticalCenter: parent.verticalCenter
            width: c.appW
            theme: root.theme
            size: 12.5
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            maximumLineCount: 1
            elide: Text.ElideRight
            horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
            text: c.appText
            opacity: c.appW > 0 ? 1 : 0
        }

        IlhaText {
            readonly property real lx: 28 + (c.appW > 0 ? c.appW + 8 : 0)
            x: c.gx(lx, c.mainW)
            anchors.verticalCenter: parent.verticalCenter
            width: c.mainW
            theme: root.theme
            size: 13
            weight: c.urgent ? 600 : 500
            tnum: !c.urgent
            maximumLineCount: 1
            elide: Text.ElideRight
            horizontalAlignment: root.rtl ? Text.AlignRight : Text.AlignLeft
            text: c.mainText
        }
    }

    PeekContent { id: layerA }
    PeekContent { id: layerB }
}
