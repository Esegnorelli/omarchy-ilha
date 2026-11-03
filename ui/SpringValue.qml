import QtQuick
import qs.Commons as Commons
import "Motion.js" as Motion

// Um escalar animado por mola amortecida (massa 1), integrado em passos
// semi-implícitos de 1/240 s. FINAL do Phase 0 (dono: lead).
//
//   go(alvo, "hover" | "slow" | "panel" | {ease: ms, curve}, atrasoMs = 0)
//   snap(valor)
//
// - Redirecionar no meio do caminho mantém valor e velocidade.
// - O FrameAnimation só roda enquanto há movimento ou um alvo atrasado.
// - O quadro é limitado a 1/30 s; assenta com |alvo − valor| < 0,05 e |v| < 2/s.
// - {ease, curve} faz um tween a partir do valor atual (velocidade zerada).
// - Atraso: espera atrasoMs em tempo de quadro e então mira. Um go() novo
//   (com ou sem atraso) cancela o atrasado que ainda não começou.
// - Reduzir movimento: go() pula direto para o alvo, sem atraso.
Item {
    id: root

    visible: false

    readonly property real value: priv.x
    readonly property real velocity: priv.v
    readonly property real target: priv.target
    readonly property bool moving: priv.active
    // Limiar de assentamento. O padrão serve para px; um progresso 0..1 usa
    // settlePos 0.001 / settleVel 0.04 (senão para a 2–4% do alvo e pula).
    property real settlePos: Motion.SETTLE_POS
    property real settleVel: Motion.SETTLE_VEL

    // O valor final chegou (por mola, tween ou snap com mudança).
    signal settled()

    function go(to, motion, delayMs) {
        const t = Number(to);
        if (!isFinite(t))
            return;
        if (Commons.Style.reduceMotion) {
            root.snap(t);
            return;
        }
        const d = Number(delayMs) || 0;
        if (d > 0) {
            priv.pending = { to: t, motion: motion };
            priv.delayLeft = d;
            return;
        }
        priv.pending = null;
        priv.start(t, motion);
    }

    function snap(to) {
        const t = Number(to);
        if (!isFinite(t))
            return;
        const changed = priv.active || priv.x !== t;
        priv.pending = null;
        priv.easeSpec = null;
        priv.x = t;
        priv.v = 0;
        priv.target = t;
        priv.active = false;
        if (changed)
            root.settled();
    }

    QtObject {
        id: priv

        property real x: 0
        property real v: 0
        property real target: 0
        property bool active: false
        property var preset: null
        // Tween: {dur, curve, from, elapsed}
        property var easeSpec: null
        property var pending: null
        property real delayLeft: 0

        function start(t, motion) {
            priv.target = t;
            if (Motion.isEase(motion)) {
                priv.preset = null;
                priv.easeSpec = {
                    dur: Math.max(1, Number(motion.ease) || 1),
                    curve: motion.curve || "OutCubic",
                    from: priv.x,
                    elapsed: 0
                };
                priv.v = 0;
                priv.active = priv.x !== t;
                if (!priv.active)
                    priv.easeSpec = null;
                return;
            }
            priv.easeSpec = null;
            priv.preset = Motion.presetFor(motion);
            if (Motion.isSettled(priv.x, priv.v, t, root.settlePos, root.settleVel)) {
                const was = priv.active || priv.x !== t;
                priv.x = t;
                priv.v = 0;
                priv.active = false;
                if (was)
                    root.settled();
                return;
            }
            priv.active = true;
        }

        function finish() {
            priv.x = priv.target;
            priv.v = 0;
            priv.easeSpec = null;
            priv.active = false;
            root.settled();
        }

        function tick(dt) {
            if (priv.pending !== null) {
                priv.delayLeft -= dt * 1000;
                if (priv.delayLeft <= 0) {
                    const p = priv.pending;
                    priv.pending = null;
                    priv.start(p.to, p.motion);
                }
            }
            if (!priv.active)
                return;
            if (priv.easeSpec !== null) {
                const e = priv.easeSpec;
                e.elapsed += dt * 1000;
                const u = Math.min(1, e.elapsed / e.dur);
                const nx = Motion.lerp(e.from, priv.target, Motion.ease(u, e.curve));
                priv.v = dt > 0 ? (nx - priv.x) / dt : 0;
                priv.x = nx;
                if (u >= 1)
                    priv.finish();
                return;
            }
            const s = Motion.step({ x: priv.x, v: priv.v }, priv.target, dt, priv.preset);
            if (Motion.isSettled(s.x, s.v, priv.target, root.settlePos, root.settleVel)) {
                priv.finish();
                return;
            }
            priv.x = s.x;
            priv.v = s.v;
        }
    }

    FrameAnimation {
        running: priv.active || priv.pending !== null
        onTriggered: priv.tick(Math.min(frameTime, Motion.MAX_FRAME))
    }
}
