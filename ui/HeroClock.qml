pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "Motion.js" as Motion

// O relógio da ilha: UM por janela, para repouso, L1 e L2 (regra 1 do
// anti-glitch). No L2 é a mesma instância escalada 1,375 e deslocada; a
// escala, o deslocamento e a opacidade vêm de quem o usa (IslandWindow).
//
// - text: "HH:mm", ou "h:mm" com twelveHour (sem AM/PM), com os algarismos
//   do idioma (Commons.I18n.formatNumber por algarismo). Sempre LTR.
// - naturalWidth: largura medida (IlhaMetrics 16/500/tnum) — alimenta
//   geometryFor ctx.clockW. Nunca a largura de um Row.
//
// Rolagem do minuto (motion L, medida no vídeo em 05:05): só os algarismos
// que mudaram andam. O velho sobe 6 px e some; o novo vem de 6 px abaixo e
// aparece; 110 ms OutCubic. O tnum mantém a largura fixa, então nada se
// desloca na horizontal.
// Por que colunas recortadas e não um Text por caractere: a Inter sobe os
// dois-pontos entre algarismos (calt). Cada coluna desenha o texto INTEIRO
// e mostra só a sua faixa; assim a forma do texto é sempre a do texto todo.
// Fora da rolagem (quase sempre) é um Text só.
// Troca de idioma, de formato (12/24 h) ou de quantidade de caracteres
// (9:59 -> 10:00 no formato de 12 h) não rola: troca direto.
Item {
    id: root

    property Theme theme: null
    property var now: new Date()
    property color color: root.theme ? root.theme.ink : "white"
    property bool twelveHour: false

    readonly property string text: priv.text
    readonly property real naturalWidth: Math.ceil(metrics.advanceWidth)

    function format(d) {
        const date = d instanceof Date ? d : new Date();
        let h = date.getHours();
        if (root.twelveHour) {
            h = h % 12;
            if (h === 0)
                h = 12;
        }
        const m = date.getMinutes();
        const raw = (root.twelveHour ? String(h) : (h < 10 ? "0" + h : String(h))) + ":" + (m < 10 ? "0" + m : String(m));
        let out = "";
        for (let i = 0; i < raw.length; i++) {
            const ch = raw.charAt(i);
            out += ch >= "0" && ch <= "9" ? Commons.I18n.formatNumber(Number(ch)) : ch;
        }
        return out;
    }

    // Recalcula o texto. fromClock: a mudança veio do minuto (pode rolar).
    function refresh(fromClock) {
        const d = root.now instanceof Date ? root.now : new Date();
        const key = d.getHours() * 60 + d.getMinutes();
        const next = root.format(d);
        const prev = priv.text;
        const roll = fromClock && priv.minuteKey >= 0 && key !== priv.minuteKey
            && prev !== "" && next !== prev && next.length === prev.length
            && !!root.theme && root.theme.dur(Motion.FADE.CLOCK_ROLL.dur) > 0;
        priv.minuteKey = key;
        roll_.stop();
        if (roll) {
            priv.old = prev;
            priv.text = next;
            priv.t = 0;
            priv.rolling = true;
            roll_.start();
        } else {
            priv.rolling = false;
            priv.old = "";
            priv.t = 1;
            priv.text = next;
        }
    }

    onNowChanged: root.refresh(true)
    onTwelveHourChanged: root.refresh(false)
    Connections {
        target: Commons.I18n
        function onZeroDigitChanged() {
            root.refresh(false);
        }
        function onLanguageChanged() {
            root.refresh(false);
        }
    }
    Component.onCompleted: root.refresh(false)

    implicitWidth: root.naturalWidth
    implicitHeight: 20
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    Accessible.role: Accessible.StaticText
    Accessible.name: root.text

    QtObject {
        id: priv
        // Valor inicial já certo (antes do primeiro refresh) para a largura
        // nunca começar em zero.
        property string text: root.format(root.now)
        property string old: ""
        // Progresso da rolagem: 0 = início, 1 = fim.
        property real t: 1
        property bool rolling: false
        property int minuteKey: -1
    }

    NumberAnimation {
        id: roll_
        target: priv
        property: "t"
        from: 0
        to: 1
        duration: root.theme ? root.theme.dur(Motion.FADE.CLOCK_ROLL.dur) : 0
        easing.type: Easing.OutCubic
        onFinished: {
            priv.rolling = false;
            priv.old = "";
        }
    }

    IlhaMetrics {
        id: metrics
        theme: root.theme
        size: 16
        weight: 500
        tnum: true
        text: root.text
    }

    // Deslocamento comum de todas as cópias: centradas na caixa.
    readonly property real textX: (root.width - metrics.advanceWidth) / 2
    readonly property real textY: (root.height - still.implicitHeight) / 2

    // O texto parado (fora da rolagem).
    IlhaText {
        id: still
        x: root.textX
        y: root.textY
        opacity: priv.rolling ? 0 : 1
        theme: root.theme
        size: 16
        weight: 500
        tnum: true
        color: root.color
        text: root.text
    }

    // Durante a rolagem: uma coluna por caractere, cada uma com o texto
    // inteiro recortado na sua faixa. Só existe nos 110 ms da rolagem.
    Repeater {
        model: priv.rolling ? root.text.length : 0

        Item {
            id: cell

            required property int index
            readonly property bool changed: priv.old.charAt(cell.index) !== root.text.charAt(cell.index)
            readonly property real dy: Motion.FADE.CLOCK_ROLL.dy
            // Bordas da coluna pelas larguras de avanço do prefixo; a primeira
            // e a última ganham folga para a tinta fora do avanço.
            readonly property real x0: cell.index === 0 ? -4 : root.textX + pre0.advanceWidth
            readonly property real x1: cell.index === root.text.length - 1 ? root.width + 4 : root.textX + pre1.advanceWidth

            x: cell.x0
            y: -cell.dy - 4
            width: Math.max(0, cell.x1 - cell.x0)
            height: root.height + 2 * (cell.dy + 4)
            clip: true

            IlhaMetrics {
                id: pre0
                theme: root.theme
                size: 16
                weight: 500
                tnum: true
                text: root.text.slice(0, cell.index)
            }
            IlhaMetrics {
                id: pre1
                theme: root.theme
                size: 16
                weight: 500
                tnum: true
                text: root.text.slice(0, cell.index + 1)
            }

            // O texto novo (parado nas colunas que não mudaram).
            IlhaText {
                x: root.textX - cell.x0
                y: root.textY + cell.dy + 4 + (cell.changed ? cell.dy * (1 - priv.t) : 0)
                opacity: cell.changed ? priv.t : 1
                theme: root.theme
                size: 16
                weight: 500
                tnum: true
                color: root.color
                text: root.text
            }
            // O texto velho, subindo e sumindo, só onde mudou.
            IlhaText {
                visible: cell.changed
                x: root.textX - cell.x0
                y: root.textY + cell.dy + 4 - cell.dy * priv.t
                opacity: 1 - priv.t
                theme: root.theme
                size: 16
                weight: 500
                tnum: true
                color: root.color
                text: priv.old
            }
        }
    }
}
