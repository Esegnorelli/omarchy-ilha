import QtQuick
import qs.Commons as Commons

// Medidas da ilha (spec §3.1). Uma instância no Island, repassada aos estados
// pela propriedade "metrics"; os blocos (Tile, GridRow, PanelGrid, LabeledRow,
// InfoRow, PanelFooter) aceitam a mesma instância e criam a própria se ninguém
// passar.
//
// API pública (somente leitura):
//   col, gap, content, pad, width         grade de 4 colunas: 4·128 + 3·8 = 536; ilha 568
//   strip, zoneL, zoneC, zoneR, iconSlot   faixa fixa do topo (216 | 104 | 216, 6 × 36), 50 px
//   tile, compact, slim, info              alturas: tile 72, botão compacto 32, LabeledRow 44, InfoRow 56
//   caption, captionGap, footer            legenda 16 + 4; rodapé 20
//   tileRadius, rowRadius                  14 e 12 (pílula = altura / 2)
//   padTop, padBottom, chrome              8 acima, 8 + rodapé + 12 abaixo; chrome = 94 + linhas
//   panelMax                               teto de altura de um painel (700)
//   colX(c, columns), spanWidth(s, columns)  posição e largura em px de colunas (columns = 4 ou 3)
//   panelHeight(rowsHeight)                altura total da ilha para um painel
//   alpha*, opacity*                       níveis de tinta derivados de fg/accent
//   ms*                                    durações base (sempre passar por Commons.Style.duration)
QtObject {
    // ---------- Grade ----------
    readonly property int col: 128
    readonly property int gap: 8
    readonly property int content: 4 * col + 3 * gap          // 536
    readonly property int pad: 16
    readonly property int width: content + 2 * pad             // 568

    // ---------- Faixa ----------
    readonly property int strip: 50
    readonly property int zoneL: 216
    readonly property int zoneC: 104
    readonly property int zoneR: 216
    readonly property int iconSlot: 36                         // 6 × 36 = 216
    readonly property int caretWidth: 16
    readonly property int caretHeight: 3

    // ---------- Linhas ----------
    readonly property int tile: 72
    readonly property int tileIcon: 20
    readonly property int tileLabel: 12
    readonly property int tileSublabel: 11
    readonly property int tilePadding: 12
    readonly property int compact: 32                          // botões do InfoRow
    readonly property int segment: 36                          // segmentos do LabeledRow
    readonly property int slim: 44                             // LabeledRow
    readonly property int info: 56                             // InfoRow
    readonly property int caption: 16
    readonly property int captionGap: 4
    readonly property int captionText: 11
    readonly property int footer: 20
    readonly property int footerText: 11
    readonly property int badge: 14
    readonly property int ring: 2

    // Cantos do Estilo. Arredondado guarda o desenho da grade. Reto fecha
    // os botões. Tema acompanha o raio das janelas.
    property string corners: "rounded"
    readonly property int themeCorner: Commons.Style.cornerRadius
    readonly property int tileRadius: corners === "sharp" ? 2
        : corners === "theme" ? Math.max(2, Math.min(14, themeCorner > 0 ? themeCorner : 2)) : 14
    readonly property int rowRadius: corners === "sharp" ? 2
        : corners === "theme" ? Math.max(2, Math.min(12, themeCorner > 0 ? themeCorner : 2)) : 12

    // ---------- Chrome do painel ----------
    readonly property int padTop: 8
    readonly property int padBottom: 12
    // faixa 50 + 8 + linhas + 8 + rodapé 20 + 12 = 98 + linhas
    readonly property int chrome: strip + padTop + gap + footer + padBottom
    readonly property int panelMax: 700

    // ---------- Tinta (alfa sobre fg/accent) ----------
    readonly property real alphaIdle: 0.06
    readonly property real alphaHover: 0.10
    readonly property real alphaPill: 0.18
    readonly property real opacityBusy: 0.6
    readonly property real opacityUnavailable: 0.35
    readonly property real opacityBadgeFaint: 0.4

    // ---------- Tempo (ms, antes de Commons.Style.duration) ----------
    readonly property int msPress: 120
    readonly property int msState: 180
    readonly property int msFadeOut: 120
    readonly property int msFadeIn: 160
    readonly property int msDwell: 150
    readonly property int msTooltip: 600
    readonly property int msArm: 4000
    readonly property int msArmGuard: 350
    readonly property int msCloseFirst: 350
    readonly property int msBreath: 260
    readonly property real breathScale: 1.015
    readonly property real pressScale: 0.97
    readonly property int pointerModeThreshold: 8

    // ---------- Funções ----------
    function colWidth(columns) {
        const n = columns === 3 ? 3 : 4;
        return (content - (n - 1) * gap) / n;
    }
    function colX(c, columns) {
        return c * (colWidth(columns) + gap);
    }
    function spanWidth(s, columns) {
        return s * colWidth(columns) + (s - 1) * gap;
    }
    function panelHeight(rowsHeight) {
        return chrome + rowsHeight;
    }
}
