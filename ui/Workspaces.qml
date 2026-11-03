import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons as Commons

// Workspaces numerados de um monitor, como a barra do Omarchy os vê: cada
// monitor tem um bloco de dez (1–10, 11–20, …; default/hypr/monitor-workspaces.lua)
// e a pílula mostra os slots block*10+1 .. block*10+max(5, maior que existe
// no bloco), com ativo / ocupado / urgente. Uma instância por janela
// (HoverBar), ligada ao nome do monitor (`output`).
//
// - items: [{id, slot, label, wide, active, occupied, urgent}]
//   label: o slot com os algarismos do idioma (I18n.formatNumber); o décimo
//   aparece como "10" e é o único largo (wide).
// - groupWidth: Σ larguras (12, ou 16 se wide) + 4·(N − 1) — 76 para N = 5.
// - focus(id): hyprctl dispatch 'o.workspaces.focus(slot, "MON")' (o mesmo
//   que Super + n faz); um workspace de fora do bloco vai pelo id.
//
// O bloco vem de $XDG_STATE_HOME/omarchy/monitors/workspaces (linhas
// "bloco<TAB>conector<TAB>identidade"), o mesmo arquivo que a barra do
// Omarchy lê; o caminho antigo omarchy/monitor-workspaces é a reserva. Sem
// arquivo, vale o bloco do workspace que o monitor mostra.
//
// Os modelos são arrays novos a cada mudança: quem desenha usa `count` como
// modelo e lê items[index], assim os delegados ficam e as trocas animam.
QtObject {
    id: root

    // ---- Entradas ----
    property string output: ""

    // ---- Monitor do Hyprland desta janela ----
    readonly property var monitor: {
        const list = Hyprland.monitors.values;
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].name) === root.output)
                return list[i];
        }
        return null;
    }
    readonly property int activeId: root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1

    // ---- Bloco do monitor ----
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    // conector -> bloco (arquivo atual e o antigo)
    property var blocks: ({})
    property var legacyBlocks: ({})

    function readBlocks(text, minFields) {
        const next = {};
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const fields = lines[i].split("\t");
            if (fields.length >= minFields && fields[1] !== "") {
                const b = parseInt(fields[0], 10);
                if (!isNaN(b) && b >= 0)
                    next[fields[1]] = b;
            }
        }
        return next;
    }

    readonly property int block: {
        const b = root.blocks[root.output];
        if (b !== undefined)
            return b;
        const l = root.legacyBlocks[root.output];
        if (l !== undefined)
            return l;
        return root.activeId > 0 ? Math.floor((root.activeId - 1) / 10) : 0;
    }

    // ---- Slots ----
    readonly property var items: {
        const base = root.block * 10;
        const src = Hyprland.workspaces.values;
        const byId = {};
        let n = 5;
        for (let i = 0; i < src.length; i++) {
            const id = src[i].id;
            if (id > base && id <= base + 10) {
                byId[id] = src[i];
                n = Math.max(n, id - base);
            }
        }
        const out = [];
        for (let slot = 1; slot <= n; slot++) {
            const id = base + slot;
            const ws = byId[id] || null;
            const tops = ws && ws.toplevels ? ws.toplevels.values : [];
            out.push({
                id: id,
                slot: slot,
                label: Commons.I18n.formatNumber(slot),
                wide: slot >= 10,
                active: id === root.activeId,
                occupied: tops.length > 0,
                urgent: !!(ws && ws.urgent)
            });
        }
        return out;
    }
    readonly property int count: root.items.length
    readonly property real groupWidth: {
        let w = 0;
        for (let i = 0; i < root.items.length; i++)
            w += root.items[i].wide ? 16 : 12;
        return w + 4 * Math.max(0, root.items.length - 1);
    }

    // ---- Ações ----
    function focus(id) {
        const n = Number(id);
        if (!(n > 0))
            return;
        const name = root.output.replace(/["\\]/g, "");
        const expr = Math.floor((n - 1) / 10) === root.block
            ? "o.workspaces.focus(" + ((n - 1) % 10 + 1) + ", \"" + name + "\")"
            : "hl.dsp.focus({ workspace = \"" + n + "\" })";
        Quickshell.execDetached(["hyprctl", "dispatch", expr]);
    }

    function refresh() {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
    }

    // ---- Arquivos de bloco ----
    property FileView blocksFile: FileView {
        id: blocksView
        path: root.stateHome + "/omarchy/monitors/workspaces"
        watchChanges: true
        printErrors: false
        onFileChanged: blocksView.reload()
        onLoaded: root.blocks = root.readBlocks(blocksView.text(), 3)
        onLoadFailed: root.blocks = ({})
    }

    property FileView legacyFile: FileView {
        id: legacyView
        path: root.stateHome + "/omarchy/monitor-workspaces"
        watchChanges: true
        printErrors: false
        onFileChanged: legacyView.reload()
        onLoaded: root.legacyBlocks = root.readBlocks(legacyView.text(), 2)
        onLoadFailed: root.legacyBlocks = ({})
    }

    // O Quickshell credita toda troca de workspace ao monitor focado e não
    // vê o workspace para onde um monitor cai quando o dele sai; mover
    // workspaces entre monitores também troca os outros. Como a barra do
    // Omarchy, pergunta ao Hyprland — só a janela do monitor focado, para
    // que N janelas não façam N perguntas.
    property Connections hyprEvents: Connections {
        target: Hyprland
        function onRawEvent(event) {
            const name = event ? String(event.name) : "";
            if (name !== "workspacev2" && name !== "moveworkspacev2" && name !== "changeworkspaceid")
                return;
            if (root.monitor && root.monitor.focused)
                root.refresh();
        }
    }
}
