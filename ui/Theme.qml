import QtQuick
import qs.Commons as Commons

// Tema da Ilha 2.0: cores derivadas do tema do Omarchy, fontes, medidas fixas
// e a geometria de cada face. FINAL do Phase 0 (dono: lead). Uma instância só
// (island.theme), repassada a tudo como `theme`.
//
// Cores: lê só Commons.Color (foreground, background, accent, urgent). Nunca
// chama loadColors e nunca grava a paleta. As quatro bases animam 150 ms
// (0 com reduzir movimento) e todos os tokens seguem.
// - A ilha é sempre escura: surface = 10% da base escura sobre o preto.
// - accent (preenchimentos) sobe em direção à tinta até 3:1 contra surface;
//   accentInk (texto, glifos finos, barras do Wi-Fi, cursor) até 4,5:1.
// - onAccent é #000 ou #fff, o que contrastar mais com accent.
// - danger: urgent levantado até 3:1.
//
// Texto: Inter Ilha2 (fonts/InterIlha2.ttf). O Qt NÃO aplica font.weight ao
// eixo wght da fonte variável: use IlhaText / IlhaMetrics (que passam
// font.variableAxes), nunca Text com font.weight.
//
// Medidas: theme.px.NOME (constantes; QML não aceita propriedade com
// maiúscula). Ordem das telas: theme.px.SCREEN_ORDER.
QtObject {
    id: theme

    // ---- Entradas (o Ilha.qml liga) ----
    // Arquivo do toggle bar-glassy ou window-glassy presente: sombra limitada.
    property bool glassy: false

    readonly property bool rtl: Commons.I18n.rightToLeft
    readonly property int dir: theme.rtl ? -1 : 1
    readonly property bool reduceMotion: Commons.Style.reduceMotion

    // Duração efetiva de um fade (0 com reduzir movimento).
    function dur(ms) {
        return theme.reduceMotion ? 0 : ms;
    }

    // ---- Fontes ----
    property FontLoader interLoader: FontLoader {
        source: Qt.resolvedUrl("../fonts/InterIlha2.ttf")
    }
    property FontLoader symbolsLoader: FontLoader {
        source: Qt.resolvedUrl("../fonts/MaterialSymbolsRoundedIlha2.ttf")
    }
    readonly property string fontFamily: theme.interLoader.status === FontLoader.Ready ? theme.interLoader.name : Commons.Style.fontFamily
    readonly property string iconFamily: theme.symbolsLoader.status === FontLoader.Ready ? theme.symbolsLoader.name : "Material Symbols Rounded"

    // ---- Funções de cor ----
    function mix(a, b, t) {
        const ca = Qt.color(a), cb = Qt.color(b);
        const u = Math.max(0, Math.min(1, t));
        return Qt.rgba(ca.r + (cb.r - ca.r) * u, ca.g + (cb.g - ca.g) * u, ca.b + (cb.b - ca.b) * u, ca.a + (cb.a - ca.a) * u);
    }

    function alpha(c, a) {
        const cc = Qt.color(c);
        return Qt.rgba(cc.r, cc.g, cc.b, Math.max(0, Math.min(1, a)));
    }

    // Luminância relativa (WCAG 2.x).
    function lum(c) {
        const cc = Qt.color(c);
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(cc.r) + 0.7152 * f(cc.g) + 0.0722 * f(cc.b);
    }

    function contrast(a, b) {
        const la = theme.lum(a), lb = theme.lum(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    // c misturada em direção a `toward` em passos de 0,08 até contraste >= ratio contra `against`.
    function lift(c, toward, ratio, against) {
        for (let i = 0; i <= 13; i++) {
            const m = theme.mix(c, toward, Math.min(1, i * 0.08));
            if (theme.contrast(m, against) >= ratio)
                return m;
        }
        return Qt.color(toward);
    }

    function darker(a, b) {
        return theme.lum(a) <= theme.lum(b) ? Qt.color(a) : Qt.color(b);
    }

    function lighter(a, b) {
        return theme.lum(a) > theme.lum(b) ? Qt.color(a) : Qt.color(b);
    }

    // ---- Bases animadas (não grave: são ligadas ao Commons.Color) ----
    property color baseDark: theme.darker(Commons.Color.background, Commons.Color.foreground)
    property color baseInk: theme.lighter(Commons.Color.background, Commons.Color.foreground)
    property color baseAccent: Commons.Color.accent
    property color baseUrgent: Commons.Color.urgent
    Behavior on baseDark { ColorAnimation { duration: theme.dur(150) } }
    Behavior on baseInk { ColorAnimation { duration: theme.dur(150) } }
    Behavior on baseAccent { ColorAnimation { duration: theme.dur(150) } }
    Behavior on baseUrgent { ColorAnimation { duration: theme.dur(150) } }

    // ---- Tokens ----
    readonly property color surface: theme.mix("#000000", theme.baseDark, 0.10)
    readonly property color ink: theme.baseInk
    readonly property color card: theme.mix(theme.surface, theme.ink, 0.06)
    readonly property color raised: theme.mix(theme.surface, theme.ink, 0.14)
    readonly property color tileHover: theme.mix(theme.surface, theme.ink, 0.15)
    readonly property color iconIdle: theme.mix(theme.surface, theme.ink, 0.17)
    readonly property color chipFill: theme.mix(theme.surface, theme.ink, 0.18)
    readonly property color rowHover: theme.mix(theme.surface, theme.ink, 0.23)
    readonly property color rowIcon: theme.mix(theme.surface, theme.ink, 0.24)
    readonly property color track: theme.mix(theme.card, "#000000", 0.40)
    readonly property color trackRaised: theme.mix(theme.raised, "#000000", 0.45)
    readonly property color accent: theme.lift(theme.baseAccent, theme.ink, 3.0, theme.surface)
    readonly property color accentInk: theme.lift(theme.baseAccent, theme.ink, 4.5, theme.surface)
    readonly property color rawAccent: theme.baseAccent
    readonly property color onAccent: theme.contrast("#000000", theme.accent) >= theme.contrast("#ffffff", theme.accent) ? "#000000" : "#ffffff"
    readonly property color accentSoft: theme.mix(theme.surface, theme.accent, 0.15)
    readonly property color inkMuted: theme.mix(theme.surface, theme.ink, 0.55)
    readonly property color inkDate: theme.mix(theme.surface, theme.ink, 0.60)
    readonly property color inkFaint: theme.mix(theme.surface, theme.ink, 0.40)
    readonly property color danger: theme.lift(theme.baseUrgent, theme.ink, 3.0, theme.surface)
    // Sobreposição de hover (tinta a 10%), aro de 1 px (6%) e anel de foco (só no modo teclado).
    readonly property color hoverOverlay: theme.alpha(theme.ink, 0.10)
    readonly property color pressOverlay: theme.alpha(theme.ink, 0.16)
    readonly property color rim: theme.alpha(theme.ink, 0.06)
    readonly property color focusRing: theme.accent
    readonly property real focusRingWidth: 2
    readonly property real focusRingGap: 2

    // Tom de um estado (StatusSvc: statusLine.tone, markTone, peekFor().tone) -> cor.
    //   danger        perigo (gravando, sessão remota, sudo sem senha, urgente)
    //   accentInk     accent para texto/glifo
    //   accentInkSoft accentInk a 75% (lembrete, atualização, manter acordado)
    //   ink           tinta a 85% (Não perturbe na marca e no aviso)
    //   inkSoft       tinta a 70% (Não perturbe na linha do L2)
    //   calm          mix(surface, accent, 0.75) ("Tudo em dia")
    function toneColor(tone) {
        switch (String(tone || "")) {
        case "danger":
            return theme.danger;
        case "accentInk":
            return theme.accentInk;
        case "accentInkSoft":
            return theme.alpha(theme.accentInk, 0.75);
        case "inkSoft":
            return theme.alpha(theme.ink, 0.70);
        case "calm":
            return theme.mix(theme.surface, theme.accent, 0.75);
        case "ink":
        default:
            return theme.alpha(theme.ink, 0.85);
        }
    }

    // ---- Medidas fixas (px lógicos numa tela 1920x1080) ----
    readonly property var px: ({
        // Pílula
        TOP: 10,
        REST_H: 32, REST_CAP: 16, REST_MIN_W: 84, REST_CLOCK_PAD: 40,
        L2_W: 718, L2_H: 52, L2_CAP: 26, L2_MOD_H: 40, L2_MOD_DY: 17, L2_MOD_PAD: 24,
        OSD_H: 40, OSD_CAP: 20, OSD_W: 304,
        // Telas
        PANEL_W: 514, PANEL_CAP: 30, LAUNCHER_CAP: 27,
        CC_H: 588, LAUNCHER_H: 368, POWER_H: 112, MEDIA_H: 218,
        CALENDAR_H: 420, CAPTURE_H: 236, MENU_H: 460,
        THEMES_PAD: 30, THEMES_PITCH: 194, THEMES_KMIN: 2, THEMES_KMAX: 5,
        // Tema e papel de parede numa tela só: a fileira de temas (sem rodapé) em cima.
        THEMES_ROW_H: 180,
        WALLS_H: 232, WALLS_PAD: 32, WALLS_PITCH: 196, WALLS_KMIN: 2, WALLS_KMAX: 5,
        // Limites: w <= screenW − 48; h <= screenH − 10 − 72
        EDGE: 48, PANEL_BOTTOM_GAP: 72,
        // Recorte seguro do conteúdo: inset = CLIP_INSET · radius
        CLIP_INSET: 0.2929,
        // Janela e zonas de hover (alvo, nunca animadas)
        ZONE: 48,
        ZONE_REST_PAD: 8, ZONE_REST_H: 46,
        ZONE_PAD: 6, ZONE_PICKER_H: 66, ZONE_PEEK_H: 56,
        OSD_ZONE_PAD: 6,
        // Escalas do L2
        L2_CLOCK_SCALE: 1.375,
        // Marca do repouso
        MARK_ICON: 16, MARK_GLYPH: 14, MARK_TIME_GAP: 4, MARK_BARS_GAP: 5, MARK_BARS_W: 9,
        MARK_GAP: 8, MARK_TRIM: 4,
        // Seletor de telas
        // Reserva: a largura de verdade vem do ScreenPicker (workspaces + relógio + ícones).
        PICKER_W: 272, PICKER_H: 42, PICKER_TOP: 22, PICKER_CAP: 21,
        PICKER_PAD: 10, PICKER_CLOCK_PAD: 10, PICKER_PITCH: 36, PICKER_GLYPH: 18, PICKER_HOVER: 30,
        // Aviso ao vivo
        PEEK_H: 40, PEEK_TOP: 10, PEEK_CAP: 20, PEEK_MIN_W: 160, PEEK_MAX_W: 480, PEEK_GLYPH: 18,
        // Navegação abaixo da tela aberta (cabe no PANEL_BOTTOM_GAP: 8 + 40 < 72)
        NAV_H: 40, NAV_GAP: 8, NAV_PAD: 6, NAV_PITCH: 36, NAV_DIV: 9,
        // Borda de cima e roda
        STRIP_W: 600, STRIP_H: 3, WHEEL_BAND: 14,
        // Ordem única das telas (seletor, Alt+1..6, Ctrl+Tab, roda)
        // (Temas e Papéis de parede são uma tela só: "themes".)
        // A Música mora na Central (cartão "tocando agora"); a tela continua pelo cartão e pelo OSD de mídia.
        SCREEN_ORDER: ["launcher", "calendar", "themes", "capture", "menu", "control", "power"]
    })

    // ---- Geometria ----

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    // Altura máxima de uma tela.
    function maxPanelH(screenH) {
        return Math.max(120, (Number(screenH) || 1080) - 10 - theme.px.PANEL_BOTTOM_GAP);
    }

    // Tamanho estático de cada tela: {w, h, k}. k = cartões visíveis (temas/papéis).
    function screenSize(id, ctx) {
        const c = ctx || {};
        const sw = Number(c.screenW) || 1920;
        const maxW = sw - theme.px.EDGE;
        const maxH = theme.maxPanelH(c.screenH);
        const P = theme.px;
        let w = P.PANEL_W, h = P.CC_H, k = 0;
        switch (String(id || "")) {
        case "launcher":
            h = P.LAUNCHER_H;
            break;
        case "power":
            h = P.POWER_H;
            break;
        case "media":
            h = P.MEDIA_H;
            break;
        case "calendar":
            h = P.CALENDAR_H;
            break;
        case "capture":
            h = P.CAPTURE_H;
            break;
        case "menu":
            h = P.MENU_H;
            break;
        case "themes": {
            // Tela unida: a largura dos papéis de parede, a fileira de temas em cima.
            const kw = theme.clamp(Math.floor((maxW - P.WALLS_PAD) / P.WALLS_PITCH), P.WALLS_KMIN, P.WALLS_KMAX);
            w = P.WALLS_PAD + P.WALLS_PITCH * kw;
            k = kw;
            h = P.THEMES_ROW_H + P.WALLS_H;
            break;
        }
        case "themeRow": {
            // A fileira de temas dentro da tela unida (mesma largura).
            const kw = theme.clamp(Math.floor((maxW - P.WALLS_PAD) / P.WALLS_PITCH), P.WALLS_KMIN, P.WALLS_KMAX);
            w = P.WALLS_PAD + P.WALLS_PITCH * kw;
            k = theme.clamp(Math.floor((w - P.THEMES_PAD) / P.THEMES_PITCH), P.THEMES_KMIN, P.THEMES_KMAX);
            h = P.THEMES_ROW_H;
            break;
        }
        case "wallpapers":
            k = theme.clamp(Math.floor((maxW - P.WALLS_PAD) / P.WALLS_PITCH), P.WALLS_KMIN, P.WALLS_KMAX);
            w = P.WALLS_PAD + P.WALLS_PITCH * k;
            h = P.WALLS_H;
            break;
        case "control":
        default:
            break;
        }
        return { w: Math.min(w, maxW), h: Math.min(h, maxH), k: k };
    }

    // Alvo da forma para uma face: {w, h, top, cap}.
    // ctx: {clockW, osdW, markW, peekW, screenW, screenH,
    //       screenId, panelH, pickerW, modsW, bandW}. panelH (> 0) é a altura viva da tela aberta.
    function geometryFor(face, ctx) {
        const c = ctx || {};
        const P = theme.px;
        const sw = Number(c.screenW) || 1920;
        const maxW = sw - P.EDGE;
        const clockW = Number(c.clockW) || 44;
        switch (face) {
        case "hover2": {
            // Cabe no conteúdo (ctx.bandW). Sem medida, a reserva de 718.
            const mw = Number(c.modsW) || 0;
            const band = Number(c.bandW) || 0;
            const mods = mw > 0 ? Math.ceil(mw) + 2 * P.L2_MOD_PAD : 0;
            const w = band > 0 ? Math.max(band, mods) : (mw > 0 ? Math.max(P.L2_W, mods) : P.L2_W);
            return { w: Math.min(maxW, w), h: P.L2_H + (mw > 0 ? P.L2_MOD_H : 0), top: P.TOP, cap: P.L2_CAP };
        }
        case "osd":
            return { w: Math.min(maxW, Number(c.osdW) || P.OSD_W), h: P.OSD_H, top: P.TOP, cap: P.OSD_CAP };
        case "peek":
            return { w: theme.clamp(Number(c.peekW) || P.PEEK_MIN_W, P.PEEK_MIN_W, Math.min(P.PEEK_MAX_W, maxW)), h: P.PEEK_H, top: P.PEEK_TOP, cap: P.PEEK_CAP };
        case "picker":
            // workspaces + relógio + ícones (ctx.pickerW).
            return { w: Math.min(maxW, Number(c.pickerW) || P.PICKER_W), h: P.PICKER_H, top: P.PICKER_TOP, cap: P.PICKER_CAP };
        case "screen": {
            const s = theme.screenSize(c.screenId, c);
            const ph = Number(c.panelH) || 0;
            const h = ph > 0 ? Math.min(ph, theme.maxPanelH(c.screenH)) : s.h;
            return { w: s.w, h: h, top: P.TOP, cap: c.screenId === "launcher" ? P.LAUNCHER_CAP : P.PANEL_CAP };
        }
        case "rest":
        default: {
            const base = Math.max(P.REST_MIN_W, Math.ceil(clockW) + P.REST_CLOCK_PAD);
            const mw = Number(c.markW) || 0;
            return { w: Math.min(maxW, base + (mw > 0 ? mw + 4 : 0)), h: P.REST_H, top: P.TOP, cap: P.REST_CAP };
        }
        }
    }

    // Zona de hover e máscara de uma face, em coordenadas da janela: {x, y, w, h}.
    // geom é o ALVO (geometryFor), nunca o valor animado. ctx: {screenW, under}
    // (under = zona da face por baixo do OSD, para a união).
    function zoneFor(face, geom, ctx) {
        const c = ctx || {};
        const P = theme.px;
        const cx = (Number(c.screenW) || 1920) / 2;
        const g = geom || theme.geometryFor(face, c);
        const box = (pad, h) => ({ x: Math.floor(cx - g.w / 2 - pad), y: 0, w: Math.ceil(g.w + 2 * pad), h: h });
        switch (face) {
        case "hover2":
            return box(P.ZONE_PAD, Math.ceil(g.top + g.h + P.ZONE_PAD));
        case "picker":
            return box(P.ZONE_PAD, P.ZONE_PICKER_H);
        case "peek":
            return box(P.ZONE_PAD, P.ZONE_PEEK_H);
        case "osd": {
            const o = { x: Math.floor(cx - g.w / 2 - P.OSD_ZONE_PAD), y: 0, w: Math.ceil(g.w + 2 * P.OSD_ZONE_PAD), h: Math.ceil(g.top + g.h + P.OSD_ZONE_PAD) };
            return c.under ? theme.unite(o, c.under) : o;
        }
        case "screen":
            // O retângulo da tela unido à faixa de 0..10 acima dela (a roda chega à borda).
            return { x: Math.floor(cx - g.w / 2), y: 0, w: Math.ceil(g.w), h: Math.ceil(g.top + g.h) };
        case "rest":
        default:
            return box(P.ZONE_REST_PAD, P.ZONE_REST_H);
        }
    }

    // Retângulo-alvo da navegação abaixo de uma tela (geom = geometryFor("screen")).
    function navRect(geom, ctx) {
        const P = theme.px;
        const sw = Number((ctx || {}).screenW) || 1920;
        const w = 2 * P.NAV_PAD + P.NAV_PITCH + P.NAV_DIV + P.SCREEN_ORDER.length * P.NAV_PITCH;
        return { x: Math.floor(sw / 2 - w / 2), y: Math.floor(geom.top + geom.h + P.NAV_GAP), w: Math.ceil(w), h: P.NAV_H };
    }

    // Faixa invisível de 3 px na borda de cima (só abre o seletor).
    function stripRect(ctx) {
        const sw = Number((ctx || {}).screenW) || 1920;
        const w = Math.min(theme.px.STRIP_W, sw - theme.px.EDGE);
        return { x: Math.floor(sw / 2 - w / 2), y: 0, w: Math.ceil(w), h: theme.px.STRIP_H };
    }

    // Faixa da roda sobre uma tela aberta: x da tela, y 0..(10 + 14).
    function wheelBand(geom, ctx) {
        const sw = Number((ctx || {}).screenW) || 1920;
        return { x: Math.floor(sw / 2 - geom.w / 2), y: 0, w: Math.ceil(geom.w), h: theme.px.TOP + theme.px.WHEEL_BAND };
    }

    // Menor retângulo que contém os dois.
    function unite(a, b) {
        if (!a || a.w <= 0 || a.h <= 0)
            return b;
        if (!b || b.w <= 0 || b.h <= 0)
            return a;
        const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
        return { x: x, y: y, w: Math.max(a.x + a.w, b.x + b.w) - x, h: Math.max(a.y + a.h, b.y + b.h) - y };
    }

    // Sombra para a altura viva da forma: {alpha, blur, dy}. Com vidro, limitada
    // (nenhum pixel fora da forma passa de 0,28 — medido no Phase 2).
    function shadowFor(h) {
        const k = theme.clamp(((Number(h) || 32) - 32) / 80, 0, 1);
        if (theme.glassy)
            return { alpha: 0.34 + 0.04 * k, blur: 36 + 16 * k, dy: 3 + 3 * k };
        return { alpha: 0.48 + 0.07 * k, blur: 30 + 16 * k, dy: 5 + 4 * k };
    }

    // Espelho de um x calculado em LTR (RTL: x' = 2·cx − x − largura).
    function mirrorX(x, width, cx) {
        return theme.rtl ? 2 * cx - x - width : x;
    }
}
