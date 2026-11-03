.pragma library

// Motion: as molas, os tempos das transições e os intervalos de
// comportamento da Ilha 2.0. Arquivo FINAL do Phase 0 (dono: lead). Mudanças
// passam pelo lead; os agentes só leem.
//
// Regras de uso (motion + amendments §2):
// - FADE: atrasos contados do T0 (o quadro da troca de face) e duração em ms.
//   Todos OutCubic, salvo indicação. Com Commons.Style.reduceMotion todo fade
//   vale 0 ms (use dur(ms, reduce)) e as molas pulam direto (SpringValue).
// - TIMING: intervalos de comportamento (temporizadores, esperas). O reduzir
//   movimento NÃO muda nenhum deles.
// - Um fade atrasado é sempre SequentialAnimation { PauseAnimation; NumberAnimation
//   sem `from` }, cancelado pela face seguinte (gen) e partindo da opacidade atual.

// ---- Molas (validadas com tmp/v2/architect/spring.py) ----
// hover: rest <-> L1 <-> L2, fechar tela, OSD, aviso e seletor.
// slow:  só L2 -> repouso (com o mergulho do topo, E).
// panel: abrir telas e trocar de tela.
var PRESETS = {
    hover: { k: 380, c: 30.4 },
    slow: { k: 225, c: 24 },
    panel: { k: 560, c: 36.9 }
};

// Altura interna da Central (subpáginas): tween, não mola.
var INNER = { ease: 170, curve: "OutCubic" };

// Integração: passos semi-implícitos de 1/240 s; quadro limitado a 1/30 s.
var SUBSTEP = 1 / 240;
var MAX_FRAME = 1 / 30;
// Assenta quando |alvo − valor| < 0,05 e |v| < 2/s.
var SETTLE_POS = 0.05;
var SETTLE_VEL = 2;

// ---- Fades e pequenos movimentos (ms) ----
var FADE = {
    // A) repouso -> L1: itens do L1 entram em 60 ms a partir do T0.
    L1_IN: { delay: 0, dur: 60 },
    // B) L1 -> repouso: itens do L1 saem em 90 ms a partir de T0 + 30.
    L1_OUT: { delay: 30, dur: 90 },
    // C) L1 -> L2
    L2_EQ_OUT: { delay: 0, dur: 60 },          // equalizador e ponto de privacidade saem
    L2_ICONS_IN: { delay: 70, dur: 60 },       // ícones da linha de cima
    L2_LABELS_IN: { delay: 130, dur: 80 },     // rótulos da linha de cima
    L2_DATE_IN: { delay: 60, dur: 70, dx: 5 }, // data: x = final + dir·5·(1 − opacidade)
    CAPSULE_STAGGER_IN: 25,                    // atraso por cápsula (i = 0 é a mais de fora)
    NETWORK_DELAY_IN: 25,
    BATTERY_DELAY_IN: 0,
    // D) L2 -> L1
    L2_DATE_OUT: { delay: 30, dur: 60, dx: 5 },
    L1_EQ_IN: { delay: 120, dur: 60 },
    CAPSULE_STAGGER_OUT: 10,                   // j = 0 é a mais de dentro
    NETWORK_LEAD_OUT: 15,                      // a rede sai 15 ms antes da bateria
    // E) L2 -> repouso: topo vai a 22 (hover) e é redirecionado a 10 (slow) em +50.
    DIP_TOP: 22,
    DIP_DELAY: 50,
    L2_ITEMS_OUT: { delay: 40, dur: 90 },
    // F) qualquer face -> tela
    CONTENT_OUT: { delay: 0, dur: 60 },        // relógio e conteúdo do hover saem
    SCREEN_IN: { delay: 16, dur: 130, blur: 8 },   // CC, Energia, Mídia (um fade só)
    HEADER_IN: { delay: 16, dur: 60 },         // cabeçalho preso às bordas vivas
    BODY_IN: { delay: 70, dur: 100, blur: 8 }, // corpo no layout final
    // G) tela A -> tela B
    SWAP_OUT: { delay: 0, dur: 50, blur: 6 },
    SWAP_IN: { delay: 30, dur: 130, blur: 8 },
    SWAP_BODY_IN: { delay: 70, dur: 100, blur: 8 },
    // H) tela -> repouso / L1
    SCREEN_OUT: { delay: 0, dur: 60, blur: 6 },
    CLOCK_IN_AFTER: { delay: 50, dur: 70 },    // também I-out
    L1_IN_AFTER: { delay: 90, dur: 60 },
    // I) * -> osd / osd -> *
    OSD_IN: { delay: 40, dur: 90 },
    OSD_OUT: { delay: 0, dur: 60 },
    OSD_VALUE: 120,                            // a barra redireciona em 120 ms
    // J) subpágina (Som, Tela, Ilha) dentro da Central
    SUB_CONTAINER: { delay: 0, dur: 160, curve: "OutQuint" },
    SUB_COLOR: 130,
    SUB_DIM: { delay: 0, dur: 120, to: 0.5 },
    SUB_CONTENT_IN: { delay: 40, dur: 80, blur: 6 },
    SUB_CONTENT_OUT: { delay: 0, dur: 50 },
    SUB_CONTAINER_BACK: { delay: 20, dur: 180 },
    SUB_UNDIM: { delay: 20, dur: 130 },
    SUB_CHEVRON_IN: { delay: 130, dur: 70 },
    // K) popover (Wi-Fi, Bluetooth)
    POP_CONTAINER: { delay: 0, dur: 130 },
    POP_TILE_OUT: { delay: 0, dur: 60 },
    POP_DIM: { delay: 0, dur: 120, to: 0.5 },
    POP_CONTENT_IN: { delay: 40, dur: 80, blur: 6 },
    POP_CONTENT_OUT: { delay: 0, dur: 50 },
    POP_CONTAINER_BACK: { delay: 50, dur: 130 },
    POP_UNDIM: { delay: 50, dur: 130 },
    POP_TILE_IN: { delay: 180, dur: 130 },
    CARD_HEIGHT: 160,                          // linha de senha, listas inline
    // L) micro-movimento
    HOVER: 110,                                // fundo de bloco, linha, botão
    CAPSULE_HOVER: 100,
    L2_HIGHLIGHT_IN: 120,                      // linear
    L2_HIGHLIGHT_OUT: 70,
    SWITCH: 140,
    SLIDER: 120,                               // só mudanças externas; nada ao arrastar
    LAUNCHER_HIGHLIGHT: 180,
    POWER_SELECT: 160,
    CAROUSEL: { dur: 300, curve: "OutQuad" },
    CAROUSEL_REBOUND: { px: 24, dur: 300, curve: "OutBack", overshoot: 1.2 },
    THEME_LIFT: { dur: 140, px: 8 },
    THEME_BORDER: 150,
    CLOCK_ROLL: { dur: 110, dy: 6 },
    WS_SWITCH: 180,                            // escala 1 <-> 1,25, cor e brilho
    EQ_PERIOD: 900,
    CARET: { solid: 600, period: 750, on: 250, fade: 180, low: 150, lowOpacity: 0.25 },
    THEME_COLORS: 150,
    IMAGE_IN: 120,                             // miniaturas
    ART_CROSSFADE: 200,
    DOT_PULSE: { dur: 1200, low: 0.45 },       // ponto de privacidade (InOutSine), só gravando
    REVEAL_SCROLL: 160,                        // Flickable rola até o cartão
    // Barra escondida
    HIDDEN_REST: 150,
    HIDDEN_SCREEN_IN: 80,
    HIDDEN_SCREEN_OUT: 120,
    // Amendments §2: marca do repouso
    MARK_OUT: 60,
    MARK_IN_FROM_L1: { delay: 140, dur: 80 },
    MARK_IN_FROM_L2: { delay: 200, dur: 80 },
    MARK_IN_AFTER: { delay: 50, dur: 70 },
    MARK_SWAP: { out: 60, inDelay: 60, inDur: 90 },
    MARK_HIGHLIGHT_IN: 110,
    MARK_HIGHLIGHT_OUT: 70,
    // Aviso ao vivo
    PEEK_IN: { delay: 40, dur: 90, glyphScaleFrom: 0.85 },
    PEEK_OUT: 60,
    PEEK_SWAP: { out: 60, inDelay: 40, inDur: 90 },
    // Seletor de telas: atraso = delay + step·rank
    PICKER_IN: { delay: 50, step: 12, dur: 90, scaleFrom: 0.85 },
    PICKER_OUT: 60,
    PICKER_HOVER_IN: 110,
    PICKER_HOVER_OUT: 70,
    // L2 direto (N: repouso -> L2; M: aviso -> L2)
    DIRECT_L2: { itemsDelay: 60, itemsDur: 90, clockDelay: 50, clockDur: 70 },
    // Dica da linha
    HINT_IN: { delay: 180, dur: 120, dyFrom: -4 },
    HINT_OUT: 150,
    HINT_OUT_FAST: 60,
    // Navegação abaixo da tela: entra depois do painel começar a abrir.
    NAV_IN: { delay: 90, dur: 120, dyFrom: -4 },
    NAV_OUT: 60,
    // Destaque de linha / cartão (raised -> rowHover -> raised)
    FLASH: { in: 150, hold: 300, out: 450 },
    // focusedOnly: a janela que perde / ganha o foco
    FOCUS_FADE: 150
};

// ---- Intervalos de comportamento (ms). O reduzir movimento não mexe aqui. ----
var TIMING = {
    LEAVE_GRACE_MS: 60,          // saída do hover
    HOVER_PICKER_GRACE_MS: 250,  // saída do hover com os ícones na pílula
    L2_COLLAPSE_MS: 2500,        // L2 com o ponteiro fora
    KEYBOARD_MOVE_PX: 8,         // ponteiro andou isto: sai do modo teclado
    RUN_TIMEOUT_MS: 3000,        // ilha run: espera a tela ficar pronta
    WARM_START_MS: 1500,         // pré-instancia as telas depois do início
    WARM_FOCUS_MS: 400,          // ... e depois de trocar o monitor focado
    RELEASE_MS: 60000,           // janela sem foco e sem tela: release()
    OSD_DEFAULT_MS: 1200,
    RESTART_NOTICE_MS: 8000,
    RESOLUTION_REVERT_S: 10,
    POWER_CONFIRM_MS: 3000,      // "Toque de novo"
    CLOSE_THEN_RUN_MS: 180,      // comandos depois de fechar (bloquear, energia)
    BRIGHTNESS_COMMIT_MS: 180,
    NIGHT_DEBOUNCE_MS: 120,
    MONITOR_POLL_MS: 5000,
    MONITOR_PAUSE_MS: 2000,
    AUDIO_POLL_MS: 5000,
    THEME_APPLY_FALLBACK_MS: 1500,
    WALLPAPER_CLOSE_MS: 1200,
    MEDIA_POSITION_MS: 1000,
    UPDATES_POLL_MS: 6 * 3600 * 1000,
    // Amendments §2
    PEEK_MS: 2600,
    PEEK_URGENT_MS: 4000,
    PEEK_TAIL_MS: 1000,
    PEEK_PENDING_TTL: 5000,
    PICKER_IDLE_MS: 2600,
    PICKER_LEAVE_MS: 700,
    LONG_PRESS_MS: 500,
    WHEEL_DECAY_MS: 200,
    WHEEL_STEP: 120,
    HINT_MS: 3000,
    SETTLE_MS: 4000,
    REMINDER_SOON_S: 300
};

// ---- Helpers puros ----

function clamp(v, lo, hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

function lerp(a, b, t) {
    return a + (b - a) * t;
}

// Duração efetiva de um fade: 0 com reduzir movimento.
function dur(ms, reduce) {
    return reduce ? 0 : ms;
}

// "hover" | "slow" | "panel" -> {k, c}; {ease, curve} -> null (tween).
function presetFor(motion) {
    if (typeof motion === "string")
        return PRESETS[motion] || PRESETS.hover;
    if (motion && typeof motion === "object" && motion.k !== undefined)
        return motion;
    if (motion && typeof motion === "object" && motion.ease !== undefined)
        return null;
    return PRESETS.hover;
}

function isEase(motion) {
    return !!motion && typeof motion === "object" && motion.ease !== undefined;
}

// Um quadro de mola: state {x, v} é atualizado e devolvido. dt em segundos.
function step(state, target, dt, preset) {
    var p = preset || PRESETS.hover;
    var t = clamp(dt, 0, MAX_FRAME);
    var n = Math.max(1, Math.ceil(t / SUBSTEP));
    var h = t / n;
    var x = state.x, v = state.v;
    for (var i = 0; i < n; i++) {
        var a = -p.k * (x - target) - p.c * v;
        v += a * h;
        x += v * h;
    }
    state.x = x;
    state.v = v;
    return state;
}

// pos/vel opcionais: os canais de progresso 0..1 precisam de um limiar
// ~50x menor que o de px, senão param a 2–4% do alvo e pulam.
function isSettled(x, v, target, pos, vel) {
    const p = pos === undefined ? SETTLE_POS : pos;
    const s = vel === undefined ? SETTLE_VEL : vel;
    return Math.abs(target - x) < p && Math.abs(v) < s;
}

// Curvas para o modo tween (t em 0..1).
function ease(t, curve) {
    var u = clamp(t, 0, 1);
    switch (curve) {
    case "Linear":
        return u;
    case "OutQuad":
        return 1 - (1 - u) * (1 - u);
    case "OutQuint":
        return 1 - Math.pow(1 - u, 5);
    case "InOutSine":
        return -(Math.cos(Math.PI * u) - 1) / 2;
    case "OutBack": {
        var s = 1.70158 * 1.2;
        var q = u - 1;
        return 1 + (s + 1) * q * q * q + s * q * q;
    }
    case "OutCubic":
    default:
        return 1 - Math.pow(1 - u, 3);
    }
}

// Rank de entrada de um ícone do seletor (P): 0 para 2 e 3, 1 para 1 e 4, 2 para 0 e 5.
function pickerRank(slot) {
    return slot === 2 || slot === 3 ? 0 : (slot === 1 || slot === 4 ? 1 : 2);
}
