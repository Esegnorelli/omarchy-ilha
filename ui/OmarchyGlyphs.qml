import QtQuick
import Quickshell
import Quickshell.Io

// Ícones do menu do Omarchy (omarchy-menu.jsonc), na fonte do shell. O arquivo
// é do pacote: uma atualização troca o glifo e a Ilha acompanha, sem recorte
// de fonte próprio.
QtObject {
    id: root

    property string omarchyPath: ""
    property var icons: ({})

    // Tela da Ilha → entrada do menu. Sem entrada, o chamador usa o Material.
    readonly property var screenIds: ({
        launcher: "apps",
        calendar: "appearance.top-bar.indicators.clock",
        themes: "appearance.theme",
        wallpapers: "appearance.background",
        capture: "trigger.capture",
        menu: "learn.omarchy",
        control: "setup",
        power: "system"
    })
    readonly property var statusIds: ({
        recording: "trigger.capture.screenrecord",
        dnd: "trigger.toggle.notifications-off",
        nightlight: "trigger.toggle.nightlight-on",
        stayAwake: "trigger.toggle.idle-lock-off",
        reminder: "trigger.reminder",
        update: "update",
        notifications: "trigger.toggle.notifications-off"
    })

    function glyph(id) {
        return String((root.icons && root.icons[id]) || "");
    }
    function screenGlyph(screenId) {
        return root.glyph(root.screenIds[screenId] || "");
    }
    function statusGlyph(key) {
        return root.glyph(root.statusIds[key] || "");
    }

    function parse(text) {
        const out = {};
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].replace(/\/\/.*$/, "");
            const m = /^\s*"([^"]+)"\s*:\s*\{.*?"icon"\s*:\s*"((?:\\.|[^"\\])*)"/.exec(line);
            if (!m)
                continue;
            try {
                out[m[1]] = JSON.parse("\"" + m[2] + "\"");
            } catch (e) {
                out[m[1]] = m[2];
            }
        }
        return out;
    }

    property FileView menuFile: FileView {
        id: menuFile
        path: root.omarchyPath !== "" ? root.omarchyPath + "/default/omarchy/omarchy-menu.jsonc" : ""
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.icons = root.parse(text())
        onFileChanged: reload()
    }
}
