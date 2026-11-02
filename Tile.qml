import QtQuick
import qs.Commons as Commons
import "TileArm.js" as TileArm

// Bloco de ação da grade (spec §3.2). Substitui os tiles do Controle, o
// PowerButton, os botões de Captura/Ferramentas e a confirmação de "limpar
// lembretes".
//
// API pública:
//   icon, label, sublabel: string    ícone Material Symbols, rótulo (12 DemiBold, uma linha que
//                                    encolhe até 10 px antes de cortar), sublinha (11 metrics.textSecondary)
//   detail: string                   3ª linha opcional; com ela o layout vira ícone à esquerda (tiles largos)
//   detailMono: bool                 detail em monospace (padrão: a fonte do tema)
//   trailingIcon: string             ícone 18 muted à direita; com ele o card usa o layout largo
//   kind: "action" | "toggle" | "confirm"
//   shape: "card" | "capsule" | "round"
//       card     o cartão de sempre (empilhado, largo, rosto de ícone ou compacto)
//       capsule  cápsula com um círculo de ícone à esquerda, nome e sublinha
//       round    o tile inteiro é o círculo (só o ícone; o nome vai no hoverNote)
//   on: bool                         ligado. Card: fundo neutro mais claro (14%) e ícone em accent;
//                                    só tone: "danger" pinta o card inteiro.
//                                    Capsule, round e iconFace: só o círculo do ícone acende.
//   tone: "accent" | "danger"        cor do estado ligado (círculo, disco ou card danger)
//   standby: bool                    ligado mas parado (Wi-Fi sem rede): com on, o círculo
//                                    fica em accent a 22% e o ícone em accent, em vez de sólido
//   busy: bool                       sublinha "Aplicando…", 60%, não ativa
//   spinIcon: bool                   o ícone gira (1,2 s por volta) enquanto visível
//   available: bool                  false = 35% (45% no rosto de ícone), sublinha = unavailableText, não ativa
//   unavailableText: string          motivo mostrado quando indisponível
//   span: 1–4, stretch: bool         lidos pelo GridRow
//   keyHint: string                  letra manual; vazio = automática pela posição (keyRow/keyCol)
//   showBadge: bool                  mostra o KeyBadge (padrão true)
//   badgeText: string                contagem pequena em accent no canto do disco (rosto de ícone)
//   closesIsland: bool               metadado: a ação fecha a ilha antes de rodar (o estado usa)
//   compact: bool                    linha única, 32 px (InfoRow, segmentos), em cápsula
//   iconFace: bool                   ícone num disco de 40 px no centro e o nome numa linha
//   faceIconSize: int                glifo dentro do disco (24)
//   cornerRadius: int                >= 0 troca o raio calculado
//   keyboardMode: bool               letras cheias só no modo teclado
//   focusVisible: bool               o GridRow/PanelGrid liga depois que o usuário navegou;
//                                    com foco, preenche a 14% e desenha um anel de 1 px accent
//   strings: Commons.Translations    para "Aplicando…" / "Confirmar?" (o grid repassa)
//   fg, bg, accent, danger, muted, metrics, fontFamily
//   keyRow, keyCol, keySpan          preenchidos pelo GridRow (posição na grade)
//   readonly armed: bool, letter: string, hovered: bool
//   readonly hoverNote: string       "rótulo · sublinha" (o round mostra no rodapé)
//   readonly noteShown: bool         round com hover há msTooltip
// Sinal:  activated()                ação, toggle ou 2ª ativação de um confirm
// Funções:
//   activate() → bool                o que clique/tecla/Enter fazem; false se nada aconteceu
//   disarm()                         desarma um confirm
//   pulse()                          só a animação de toque (0.97)
//
// Confirm: 1ª ativação arma por 4 s; a 2ª (clique, mesma tecla ou Enter) roda;
// uma 2ª com menos de 350 ms é ignorada; armar um desarma os outros (TileArm.js);
// Esc chama TileArm.disarmAll() pelo PanelGrid. Armado é o único estado que
// tinge o corpo inteiro (danger a 20%).
Item {
    id: tile

    property string icon: ""
    property string label: ""
    property string sublabel: ""
    property string detail: ""
    property bool detailMono: false
    property string trailingIcon: ""
    property string kind: "action"
    property string shape: "card"
    property bool on: false
    property string tone: "accent"
    property bool standby: false
    property bool busy: false
    property bool spinIcon: false
    property bool available: true
    property string unavailableText: ""
    property int span: 1
    property bool stretch: false
    property string keyHint: ""
    property bool showBadge: true
    property string badgeText: ""
    property bool closesIsland: false
    property bool compact: false
    property bool iconFace: false
    property int faceIconSize: 24
    property int cornerRadius: -1
    property bool keyboardMode: false
    property bool focusVisible: false
    property var strings: null

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
    property string fontFamily: Commons.Style.fontFamily
    property Metrics metrics: Metrics {}

    // Posição na grade (o GridRow escreve).
    property int keyRow: -1
    property int keyCol: -1
    property int keySpan: span

    readonly property bool armed: _armed
    readonly property bool hovered: hover.hovered
    readonly property string letter: {
        if (!showBadge) return "";
        if (keyHint !== "") return keyHint;
        const rows = ["QWER", "ASDF", "ZXCV"];
        if (keyRow < 0 || keyRow > 2 || keyCol < 0 || keyCol > 3) return "";
        return rows[keyRow][keyCol];
    }
    readonly property bool interactive: available && !busy && visible && enabled

    signal activated()

    implicitWidth: shape === "round" ? implicitHeight : metrics.col
    implicitHeight: compact ? metrics.compact : metrics.tile

    // Um tile focado que fica indisponível mantém a flag até perder o foco
    // (o Qt não deixa desligá-la no item com foco ativo).
    activeFocusOnTab: interactive || activeFocus
    Accessible.role: Accessible.Button
    Accessible.name: shape === "round" ? tile.hoverNote : tile.label
    Accessible.description: tile.sublabel
    Accessible.checkable: tile.kind === "toggle"
    Accessible.checked: tile.on

    // ---------- Confirmação ----------
    property bool _armed: false
    property double _armedAt: 0

    function activate() {
        if (!tile.interactive) return false;
        tile.pulse();
        if (tile.kind === "confirm") {
            if (!tile._armed) {
                tile._armed = true;
                tile._armedAt = Date.now();
                armTimer.restart();
                TileArm.arm(tile);
                return true;
            }
            if (Date.now() - tile._armedAt < tile.metrics.msArmGuard) return true;
            tile.disarm();
            tile.activated();
            return true;
        }
        tile.activated();
        return true;
    }

    function disarm() {
        armTimer.stop();
        tile._armed = false;
        TileArm.release(tile);
    }

    // Pulso de toque: o mesmo 0.97 do clique, para teclas.
    property bool _pulsing: false
    function pulse() {
        tile._pulsing = true;
        pulseTimer.restart();
    }

    Timer { id: armTimer; interval: tile.metrics.msArm; onTriggered: tile.disarm() }
    Timer { id: pulseTimer; interval: Math.max(1, Commons.Style.duration(tile.metrics.msPress)); onTriggered: tile._pulsing = false }

    onVisibleChanged: if (!visible && _armed) disarm()
    onInteractiveChanged: if (!interactive && _armed) disarm()
    Component.onDestruction: TileArm.release(tile)

    // ---------- Nota do round ----------
    // O round não tem texto: depois de msTooltip de hover o nome e o estado
    // aparecem no rodapé do painel (o estado lê noteShown/hoverNote).
    readonly property string hoverNote: shownSublabel !== "" ? label + " · " + shownSublabel : label
    // O Timer não repetido desliga running ao disparar; por isso a nota só
    // apaga quando o hover acaba, não quando o timer para.
    readonly property bool _noteHover: shape === "round" && hover.hovered && visible
    property bool _noteShown: false
    readonly property bool noteShown: _noteShown && _noteHover
    on_NoteHoverChanged: if (!_noteHover) _noteShown = false
    Timer {
        id: noteTimer
        interval: tile.metrics.msTooltip
        running: tile._noteHover
        onTriggered: tile._noteShown = true
    }

    // ---------- Aparência ----------
    readonly property bool filled: _armed || on
    readonly property bool hot: hover.hovered && interactive
    readonly property bool focusShown: activeFocus && focusVisible
    readonly property bool pressedNow: (tap.pressed && interactive) || _pulsing
    // Accent nunca pinta um card inteiro: ligado, o card fica num neutro mais
    // claro com o ícone em accent. Só o tom danger ainda tinge o corpo;
    // capsule, round e o rosto de ícone acendem apenas o círculo do ícone.
    readonly property bool fillsWhole: shape === "card" && !iconFace
    readonly property bool wholeOn: on && !_armed && fillsWhole && tone === "danger"
    readonly property bool cardOn: on && !_armed && fillsWhole && !wholeOn
    readonly property bool roundOn: on && !_armed && shape === "round" && !standby
    readonly property color toneColor: tone === "danger" ? danger : accent
    // Ligado parado: o círculo acende só um véu da cor, o ícone fica na cor.
    readonly property bool standbyOn: on && standby && !_armed
    readonly property color standbyColor: Qt.rgba(toneColor.r, toneColor.g, toneColor.b, hot ? 0.28 : 0.22)
    readonly property real neutralAlpha: focusShown || pressedNow ? metrics.alphaPressed
                                         : hot ? metrics.alphaHover : metrics.alphaIdle
    readonly property color fillColor: {
        if (_armed) return Qt.rgba(danger.r, danger.g, danger.b, 0.2);
        if (shape === "round") {
            if (standbyOn) return standbyColor;
            if (on) return hot ? Qt.lighter(toneColor, 1.08) : toneColor;
            return Qt.rgba(fg.r, fg.g, fg.b, focusShown || pressedNow ? 0.18 : hot ? 0.16 : 0.10);
        }
        if (wholeOn) {
            const c = metrics.plate(toneColor);
            return hot ? Qt.lighter(c, 1.08) : c;
        }
        return Qt.rgba(fg.r, fg.g, fg.b, cardOn ? (hot || pressedNow ? 0.18 : metrics.alphaPressed) : neutralAlpha);
    }
    // Tinta sobre accent sólido é a cor do fundo; no resto, fg.
    readonly property bool solidInk: wholeOn || roundOn
    readonly property color ink: solidInk ? bg : fg
    readonly property color subInk: solidInk ? Qt.rgba(bg.r, bg.g, bg.b, 0.78)
                                   : _armed ? danger : metrics.textSecondary
    readonly property color iconInk: _armed ? danger
                                   : solidInk ? bg
                                   : cardOn ? toneColor
                                   : kind === "confirm" ? Qt.rgba(danger.r, danger.g, danger.b, 0.85)
                                   : (hot ? accent : fg)
    readonly property real radius: Math.max(0, cornerRadius >= 0 ? cornerRadius
                                        : (compact || shape !== "card") ? metrics.fit(height / 2)
                                        : iconFace ? metrics.cardRadius : metrics.tileRadius)
    // Círculo do ícone da cápsula (44 px num tile de 60).
    readonly property real circle: Math.max(0, height - 16)
    readonly property color circleColor: _armed ? danger : standbyOn ? standbyColor : on ? toneColor : Qt.rgba(fg.r, fg.g, fg.b, 0.10)
    readonly property color circleInk: standbyOn ? toneColor : _armed || on ? bg : fg

    readonly property string layoutKind: shape === "round" ? "round"
                                       : compact ? "compact"
                                       : shape === "capsule" ? "capsule"
                                       : detail !== "" || trailingIcon !== "" ? "wide"
                                       : iconFace ? "face" : "stack"

    readonly property string shownLabel: _armed ? (strings ? strings.t("grid.confirm") : label) : label
    // No rosto de ícone o estado mora na cor. A linha de baixo só troca o nome
    // quando há algo para dizer: confirmando, aplicando ou indisponível.
    readonly property string faceCaption: (_armed || busy || (!available && unavailableText !== "")) && shownSublabel !== ""
                                          ? shownSublabel : shownLabel
    readonly property string shownSublabel: _armed ? label
                                          : busy ? (strings ? strings.t("grid.busy") : sublabel)
                                          : (!available && unavailableText !== "") ? unavailableText
                                          : sublabel

    opacity: !available ? (iconFace ? 0.45 : metrics.opacityUnavailable) : (busy ? metrics.opacityBusy : 1)
    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }

    // Ícone com giro opcional (spinIcon), igual em todos os layouts.
    component TileIcon: Icon {
        id: tileIcon
        filled: tile.filled
        RotationAnimator on rotation {
            from: 0
            to: 360
            duration: Commons.Style.duration(1200)
            loops: Animation.Infinite
            running: tile.spinIcon && tileIcon.visible && Commons.Style.duration(1200) > 0
            onRunningChanged: if (!running) tileIcon.rotation = 0
        }
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
    }

    // O conteúdo encolhe junto com o fundo.
    Item {
        id: body
        anchors.fill: parent
        scale: tile.pressedNow ? tile.metrics.pressScale : 1
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(tile.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }

        ContinuousRect {
            anchors.fill: parent
            radius: tile.radius
            color: tile.fillColor
            // Sem contorno em repouso; o confirm avisa pela cor do ícone.
            borderWidth: 0
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
        }

        // ----- Rosto de ícone: disco de 40 px no centro, nome numa linha -----
        Item {
            visible: tile.layoutKind === "face"
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 6
            anchors.bottomMargin: 6

            ContinuousRect {
                id: faceDisc
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -9
                width: 40
                height: 40
                radius: tile.metrics.fit(20)
                color: tile._armed ? Qt.rgba(tile.danger.r, tile.danger.g, tile.danger.b, 0.2)
                       : tile.standbyOn ? tile.standbyColor
                       : tile.on ? tile.toneColor : Qt.rgba(tile.fg.r, tile.fg.g, tile.fg.b, 0.08)
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }

                TileIcon {
                    anchors.centerIn: parent
                    name: tile.icon
                    size: tile.faceIconSize
                    color: tile.standbyOn ? tile.toneColor : tile.on && !tile._armed ? tile.bg : tile.iconInk
                }

                // Contagem: pílula accent sólida no canto do disco.
                ContinuousRect {
                    visible: tile.badgeText !== ""
                    x: parent.width - width / 2 - 4
                    y: -4
                    width: Math.max(16, badgeLabel.implicitWidth + 8)
                    height: 16
                    radius: tile.metrics.fit(8)
                    color: tile.accent
                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: tile.badgeText
                        textFormat: Text.PlainText
                        font.family: tile.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                        color: tile.bg
                    }
                }
            }
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                horizontalAlignment: Text.AlignHCenter
                text: tile.faceCaption
                textFormat: Text.PlainText
                font.family: tile.fontFamily
                font.pixelSize: tile.metrics.tileSublabel
                font.weight: Font.Medium
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 11
                elide: Text.ElideRight
                color: tile._armed ? tile.danger : tile.ink
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
            }
        }

        // ----- Layout empilhado (padrão): ícone no alto, textos embaixo -----
        Item {
            visible: tile.layoutKind === "stack"
            anchors.fill: parent
            anchors.margins: tile.metrics.tilePadding

            TileIcon {
                id: stackIcon
                // Âncora (e não x) para espelhar em RTL e não cair sobre a letra.
                anchors.left: parent.left
                anchors.leftMargin: -2
                anchors.top: parent.top
                anchors.topMargin: -2
                width: tile.metrics.tileIcon + 4
                height: tile.metrics.tileIcon + 4
                name: tile.icon
                size: tile.metrics.tileIcon
                color: tile.iconInk
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -2
                spacing: 0

                Text {
                    width: parent.width
                    // Explícito para virar com o espelhamento (título latino
                    // na mesma borda da sublinha em árabe).
                    horizontalAlignment: Text.AlignLeft
                    text: tile.shownLabel
                    textFormat: Text.PlainText
                    font.family: tile.fontFamily
                    font.pixelSize: tile.metrics.tileLabel
                    font.weight: Font.DemiBold
                    // Uma linha só, para todos os cartões da fileira terem a
                    // mesma linha de base: um rótulo longo encolhe até 10 px
                    // e só então corta.
                    maximumLineCount: 1
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 11
                    elide: Text.ElideRight
                    color: tile.ink
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    horizontalAlignment: Text.AlignLeft
                    text: tile.shownSublabel
                    textFormat: Text.PlainText
                    font.family: tile.fontFamily
                    font.pixelSize: tile.metrics.tileSublabel
                    elide: Text.ElideRight
                    color: tile.subInk
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
            }
        }

        // ----- Layout largo (detail ou trailingIcon): ícone à esquerda, até três linhas -----
        Item {
            visible: tile.layoutKind === "wide"
            anchors.fill: parent
            anchors.leftMargin: tile.metrics.tilePadding + 2
            anchors.rightMargin: tile.metrics.tilePadding + tile.metrics.badge + 4

            TileIcon {
                id: wideIcon
                // Âncora (e não x implícito 0) para espelhar junto com a coluna em RTL.
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: tile.metrics.tileIcon + 4
                height: tile.metrics.tileIcon + 4
                name: tile.icon
                size: tile.metrics.tileIcon
                color: tile.iconInk
            }
            Icon {
                id: wideTrailing
                visible: tile.trailingIcon !== ""
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                name: tile.trailingIcon
                size: 18
                color: tile.solidInk ? tile.subInk : tile.muted
            }
            Column {
                anchors.left: wideIcon.right
                anchors.leftMargin: 10
                anchors.right: wideTrailing.visible ? wideTrailing.left : parent.right
                anchors.rightMargin: wideTrailing.visible ? 8 : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignLeft
                    text: tile.shownLabel
                    textFormat: Text.PlainText
                    font.family: tile.fontFamily
                    font.pixelSize: tile.metrics.tileLabel
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: tile.ink
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    horizontalAlignment: Text.AlignLeft
                    text: tile.shownSublabel
                    textFormat: Text.PlainText
                    font.family: tile.fontFamily
                    font.pixelSize: tile.metrics.tileSublabel
                    elide: Text.ElideRight
                    color: tile.subInk
                }
                Text {
                    width: parent.width
                    visible: text !== "" && !tile._armed
                    horizontalAlignment: Text.AlignLeft
                    text: tile.detail
                    textFormat: Text.PlainText
                    font.pixelSize: tile.metrics.tileSublabel
                    font.family: tile.detailMono ? "monospace" : tile.fontFamily
                    elide: Text.ElideMiddle
                    color: tile.subInk
                }
            }
        }

        // ----- Cápsula: círculo do ícone à esquerda, nome e sublinha -----
        Item {
            visible: tile.layoutKind === "capsule"
            anchors.fill: parent

            ContinuousRect {
                id: capCircle
                // Âncora (e não x) para espelhar junto com a coluna em RTL.
                anchors.left: parent.left
                anchors.leftMargin: (tile.height - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: tile.circle
                height: tile.circle
                radius: tile.metrics.fit(width / 2)
                color: tile.circleColor
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }

                TileIcon {
                    anchors.centerIn: parent
                    name: tile.icon
                    size: 20
                    color: tile.circleInk
                }
            }
            Column {
                anchors.left: capCircle.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: tile.letter !== "" ? 14 + tile.metrics.badge + 6 : 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    // Explícito (AlignLeft vira à direita no espelhamento):
                    // "Wi-Fi" fica na mesma borda da sublinha em árabe.
                    horizontalAlignment: Text.AlignLeft
                    text: tile.shownLabel
                    textFormat: Text.PlainText
                    font.family: tile.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: tile.fg
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    horizontalAlignment: Text.AlignLeft
                    text: tile.shownSublabel
                    textFormat: Text.PlainText
                    font.family: tile.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    color: tile._armed ? tile.danger : tile.metrics.textSecondary
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
            }
        }

        // ----- Round: o tile inteiro é o círculo -----
        TileIcon {
            visible: tile.layoutKind === "round"
            anchors.centerIn: parent
            name: tile.icon
            size: 22
            color: tile._armed ? tile.danger : tile.standbyOn ? tile.toneColor : tile.roundOn ? tile.bg : tile.fg
        }

        // ----- Layout compacto: linha única centrada, letra à direita -----
        Item {
            id: compactArea
            visible: tile.layoutKind === "compact"
            anchors.fill: parent
            anchors.rightMargin: tile.letter !== "" ? tile.metrics.badge + 6 : 0
            anchors.leftMargin: tile.letter !== "" ? 6 : 0

            Row {
                anchors.centerIn: parent
                spacing: 6
                TileIcon {
                    id: compactIcon
                    visible: tile.icon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    name: tile.icon
                    size: 16
                    color: tile.iconInk
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Segmentos estreitos ("Arredondado", "Transparente"):
                    // encolhe até 10 px antes de cortar.
                    width: Math.min(implicitWidth, compactArea.width - 8 - (compactIcon.visible ? compactIcon.width + 6 : 0))
                    text: tile.shownLabel
                    textFormat: Text.PlainText
                    font.family: tile.fontFamily
                    font.pixelSize: tile.metrics.tileLabel
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 11
                    font.weight: tile.filled ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                    color: tile._armed ? tile.danger : tile.ink
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
            }
        }

        // No round a letra mora dentro do círculo, embaixo do ícone (e não
        // na borda, onde sumia sobre o accent); a cor segue o preenchimento.
        KeyBadge {
            readonly property bool middle: tile.compact || tile.layoutKind === "capsule"
            readonly property bool inCircle: tile.layoutKind === "round"
            anchors.right: inCircle ? undefined : parent.right
            anchors.rightMargin: tile.layoutKind === "capsule" ? 14 : tile.compact ? 8 : 9
            anchors.horizontalCenter: inCircle ? parent.horizontalCenter : undefined
            anchors.top: middle || inCircle ? undefined : parent.top
            anchors.topMargin: 9
            // Sem âncora vertical no round: y põe a letra no pé do círculo.
            y: inCircle ? parent.height - height - Math.max(2, Math.round(tile.height * 0.07)) : 0
            anchors.verticalCenter: middle ? parent.verticalCenter : undefined
            letter: tile.letter
            keyboardMode: tile.keyboardMode
            strong: tile.hot || tile.focusShown
            // Fora do modo teclado o round não mostra a letra só por estar ligado.
            onFill: tile.solidInk && (!inCircle || tile.keyboardMode || strong)
            fg: tile.fg
            bg: tile.bg
            accent: tile.accent
            muted: tile.muted
            fontFamily: tile.fontFamily
            metrics: tile.metrics
        }
    }

    // Foco de teclado: 1 px accent a 55% sobre a borda, só depois de navegar.
    ContinuousRect {
        anchors.fill: parent
        radius: tile.radius
        color: "transparent"
        borderWidth: 1
        borderColor: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.55)
        opacity: tile.focusShown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(tile.metrics.msPress); easing.type: Easing.OutCubic } }
    }

    HoverHandler {
        id: hover
        cursorShape: tile.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: tap
        onTapped: tile.activate()
    }
}
