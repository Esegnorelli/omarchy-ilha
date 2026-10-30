import QtQuick
import qs.Commons as Commons
import "TileArm.js" as TileArm

// Bloco de ação da grade (spec §3.2). Substitui os tiles do Controle, o
// PowerButton, os botões de Captura/Ferramentas e a confirmação de "limpar
// lembretes".
//
// API pública:
//   icon, label, sublabel: string    ícone Material Symbols, rótulo (12 DemiBold), sublinha (11 muted)
//   detail: string                   3ª linha opcional; com ela o layout vira ícone à esquerda (tiles largos)
//   kind: "action" | "toggle" | "confirm"
//   on: bool                         ligado (preenchido em accent, ou danger com tone: "danger")
//   tone: "accent" | "danger"        cor do preenchimento quando on
//   busy: bool                       sublinha "Aplicando…", 60%, não ativa
//   available: bool                  false = 35%, sublinha = unavailableText (ou sublabel), não ativa
//   unavailableText: string          motivo mostrado quando indisponível
//   span: 1–4, stretch: bool         lidos pelo GridRow
//   keyHint: string                  letra manual; vazio = automática pela posição (keyRow/keyCol)
//   showBadge: bool                  mostra o KeyBadge (padrão true)
//   closesIsland: bool               metadado: a ação fecha a ilha antes de rodar (o estado usa)
//   compact: bool                    linha única, 32 px (InfoRow, segmentos)
//   iconFace: bool                   ícone no centro e o nome numa linha (Controle)
//   keyboardMode: bool               anel de foco e letras cheias só no modo teclado
//   strings: Commons.Translations    para "Aplicando…" / "Confirmar?" (o grid repassa)
//   fg, bg, accent, danger, muted, metrics
//   keyRow, keyCol, keySpan          preenchidos pelo GridRow (posição na grade)
//   readonly armed: bool, letter: string
// Sinal:  activated()                ação, toggle ou 2ª ativação de um confirm
// Funções:
//   activate() → bool                o que clique/tecla/Enter fazem; false se nada aconteceu
//   disarm()                         desarma um confirm
//   pulse()                          só a animação de toque (0.97)
//
// Confirm: 1ª ativação arma por 4 s; a 2ª (clique, mesma tecla ou Enter) roda;
// uma 2ª com menos de 350 ms é ignorada; armar um desarma os outros (TileArm.js);
// Esc chama TileArm.disarmAll() pelo PanelGrid.
Item {
    id: tile

    property string icon: ""
    property string label: ""
    property string sublabel: ""
    property string detail: ""
    property string kind: "action"
    property bool on: false
    property string tone: "accent"
    property bool busy: false
    property bool available: true
    property string unavailableText: ""
    property int span: 1
    property bool stretch: false
    property string keyHint: ""
    property bool showBadge: true
    property bool closesIsland: false
    property bool compact: false
    property bool iconFace: false
    property bool keyboardMode: false
    property var strings: null

    property color fg: Commons.Color.bar.text
    property color bg: Commons.Color.bar.background
    property color accent: Commons.Color.accent
    property color danger: Commons.Color.urgent
    property color muted: Commons.Color.muted
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

    implicitWidth: metrics.col
    implicitHeight: compact ? metrics.compact : metrics.tile

    // Um tile focado que fica indisponível mantém a flag até perder o foco
    // (o Qt não deixa desligá-la no item com foco ativo).
    activeFocusOnTab: interactive || activeFocus
    Accessible.role: Accessible.Button
    Accessible.name: tile.label
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

    // ---------- Aparência ----------
    readonly property bool filled: _armed || on
    readonly property bool glassOpen: metrics.glass !== "opaque"
    readonly property color fillColor: _armed ? (glassOpen ? metrics.plate(danger) : danger)
                                        : (on ? (glassOpen ? metrics.plate(tone === "danger" ? danger : accent)
                                                           : (tone === "danger" ? danger : accent))
                                              : Qt.rgba(fg.r, fg.g, fg.b, hover.hovered && interactive ? metrics.alphaHover : metrics.alphaIdle))
    readonly property color ink: filled && !glassOpen ? bg : fg
    readonly property color subInk: filled && !glassOpen ? Qt.rgba(bg.r, bg.g, bg.b, 0.78) : muted
    readonly property color iconInk: filled && !glassOpen ? bg : (hover.hovered && interactive ? accent : fg)
    readonly property real radius: Math.max(0, compact ? metrics.rowRadius - 2 : metrics.tileRadius)

    readonly property string shownLabel: _armed ? (strings ? strings.t("grid.confirm") : label) : label
    // No rosto de ícone o estado mora na cor. A linha de baixo só troca o nome
    // quando há algo para dizer: confirmando, aplicando ou indisponível.
    readonly property string faceCaption: (_armed || busy) && shownSublabel !== ""
                                          ? shownSublabel : shownLabel
    readonly property string shownSublabel: _armed ? label
                                          : busy ? (strings ? strings.t("grid.busy") : sublabel)
                                          : (!available && unavailableText !== "") ? unavailableText
                                          : sublabel

    opacity: !available ? metrics.opacityUnavailable : (busy ? metrics.opacityBusy : 1)
    Behavior on opacity { NumberAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }

    // O conteúdo encolhe junto; o anel de foco fica fora para não pulsar.
    Item {
        id: body
        anchors.fill: parent
        scale: (tap.pressed && tile.interactive) || tile._pulsing ? tile.metrics.pressScale : 1
        Behavior on scale {
            NumberAnimation { duration: Commons.Style.duration(tile.metrics.msPress); easing.type: Easing.Bezier; easing.bezierCurve: Commons.Style.easeOut }
        }

        ContinuousRect {
            anchors.fill: parent
            radius: tile.radius
            color: tile.fillColor
            // Confirm em repouso: contorno fino em danger, avisa sem gritar.
            borderWidth: tile.kind === "confirm" && !tile.filled ? 1 : 0
            borderColor: Qt.rgba(tile.danger.r, tile.danger.g, tile.danger.b, 0.55)
            Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
        }

        // ----- Rosto de ícone: glifo no centro, nome numa linha -----
        Item {
            visible: tile.iconFace && !tile.compact && tile.detail === ""
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 6
            anchors.bottomMargin: 6

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -9
                name: tile.icon
                size: 26
                filled: tile.filled
                color: tile.iconInk
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
            }
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                horizontalAlignment: Text.AlignHCenter
                text: tile.faceCaption
                textFormat: Text.PlainText
                font.pixelSize: tile.metrics.tileSublabel
                font.weight: Font.Medium
                elide: Text.ElideRight
                color: tile.ink
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
            }
        }

        // ----- Layout empilhado (padrão): ícone no alto, textos embaixo -----
        Item {
            visible: !tile.iconFace && !tile.compact && tile.detail === ""
            anchors.fill: parent
            anchors.margins: tile.metrics.tilePadding

            Icon {
                id: stackIcon
                x: -2
                y: -2
                width: tile.metrics.tileIcon + 4
                height: tile.metrics.tileIcon + 4
                name: tile.icon
                size: tile.metrics.tileIcon
                filled: tile.filled
                color: tile.iconInk
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -2
                spacing: 0

                Text {
                    width: parent.width
                    text: tile.shownLabel
                    textFormat: Text.PlainText
                    font.pixelSize: tile.metrics.tileLabel
                    font.weight: Font.DemiBold
                    // Sem sublinha, um rótulo longo ("Área de transferência")
                    // quebra em duas linhas em vez de cortar.
                    wrapMode: Text.WordWrap
                    maximumLineCount: tile.shownSublabel === "" ? 2 : 1
                    lineHeight: 0.95
                    elide: Text.ElideRight
                    color: tile.ink
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: tile.shownSublabel
                    textFormat: Text.PlainText
                    font.pixelSize: tile.metrics.tileSublabel
                    elide: Text.ElideRight
                    color: tile.subInk
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
            }
        }

        // ----- Layout largo (com detail): ícone à esquerda, três linhas -----
        Item {
            visible: !tile.compact && tile.detail !== ""
            anchors.fill: parent
            anchors.leftMargin: tile.metrics.tilePadding + 2
            anchors.rightMargin: tile.metrics.tilePadding + tile.metrics.badge + 4

            Icon {
                id: wideIcon
                anchors.verticalCenter: parent.verticalCenter
                width: tile.metrics.tileIcon + 4
                height: tile.metrics.tileIcon + 4
                name: tile.icon
                size: tile.metrics.tileIcon
                filled: tile.filled
                color: tile.iconInk
                Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
            }
            Column {
                anchors.left: wideIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: tile.shownLabel
                    textFormat: Text.PlainText
                    font.pixelSize: tile.metrics.tileLabel
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    color: tile.ink
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: tile.shownSublabel
                    textFormat: Text.PlainText
                    font.pixelSize: tile.metrics.tileSublabel
                    elide: Text.ElideRight
                    color: tile.subInk
                }
                Text {
                    width: parent.width
                    visible: text !== "" && !tile._armed
                    text: tile.detail
                    textFormat: Text.PlainText
                    font.pixelSize: tile.metrics.tileSublabel
                    font.family: "monospace"
                    elide: Text.ElideMiddle
                    color: tile.subInk
                }
            }
        }

        // ----- Layout compacto: linha única centrada, letra à direita -----
        Item {
            id: compactArea
            visible: tile.compact
            anchors.fill: parent
            anchors.rightMargin: tile.letter !== "" ? tile.metrics.badge + 6 : 0
            anchors.leftMargin: tile.letter !== "" ? 6 : 0

            Row {
                anchors.centerIn: parent
                spacing: 6
                Icon {
                    id: compactIcon
                    visible: tile.icon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    name: tile.icon
                    size: 16
                    filled: tile.filled
                    color: tile.iconInk
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, compactArea.width - 16 - (compactIcon.visible ? compactIcon.width + 6 : 0))
                    text: tile.shownLabel
                    textFormat: Text.PlainText
                    font.pixelSize: tile.metrics.tileLabel
                    font.weight: tile.filled ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                    color: tile.ink
                    Behavior on color { ColorAnimation { duration: Commons.Style.duration(tile.metrics.msState); easing.type: Easing.OutCubic } }
                }
            }
        }

        KeyBadge {
            anchors.right: parent.right
            anchors.rightMargin: tile.compact ? 8 : 9
            anchors.top: tile.compact ? undefined : parent.top
            anchors.topMargin: 9
            anchors.verticalCenter: tile.compact ? parent.verticalCenter : undefined
            letter: tile.letter
            keyboardMode: tile.keyboardMode
            strong: (tile.hovered && tile.interactive) || (tile.activeFocus && tile.keyboardMode)
            onFill: tile.filled
            fg: tile.fg
            bg: tile.bg
            accent: tile.accent
            muted: tile.muted
            metrics: tile.metrics
        }
    }

    // Anel de foco: 2 px accent, raio + 2, só depois de usar o teclado.
    ContinuousRect {
        anchors.fill: parent
        anchors.margins: -tile.metrics.ring
        radius: tile.radius + tile.metrics.ring
        color: "transparent"
        borderWidth: tile.metrics.ring
        borderColor: tile.accent
        opacity: tile.activeFocus && tile.keyboardMode ? 1 : 0
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
