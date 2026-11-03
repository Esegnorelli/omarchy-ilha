import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons as Commons

// Takeovers dos seletores do Omarchy (host_contract "PICKER TAKEOVERS";
// dono: Agent G). As teclas e o menu de Plano de fundo e de Tema abrem as
// telas da Ilha no lugar do seletor de imagens do host.
//
// Plano de fundo (Super+Ctrl+W, Super+Ctrl+Space, Menu > Plano de fundo):
//   omarchy-theme-bg-switcher -> omarchy-menu-images -> IPC image-selector open.
// - Um Commons.ShellIpc com o alvo "image-selector" e as assinaturas exatas
//   do host (open com 7 strings, preload com 4, cancel com 1, ping) se põe na
//   frente do IpcRegistry (o do host deixa de liderar e se desliga sozinho).
// - open: se o takeover está ligado, há selectionFile e doneFile e TODAS as
//   linhas são de ~/.local/state/omarchy/current/theme/backgrounds/ ou de
//   ~/.config/omarchy/backgrounds/, guarda o pedido (pending) e abre a tela
//   de papéis com as linhas dele. Qualquer outro pedido (Plymouth…) vai para
//   o handler do host, sem mudança.
// - finish(path) grava a escolha no selectionFile e cria o doneFile ("" =
//   sem escolha). Também roda no Esc, na perda de foco, ao trocar de tela e
//   na destruição, para o script que espera nunca travar.
// - O host volta a liderar sozinho quando a Ilha sai (unregister). Se o
//   formato do registro mudar, a Ilha não lidera e o seletor do host segue.
//
// Tema (Super+Ctrl+T, Super+Shift+Ctrl+Space, Menu > Tema):
//   `shell summon omarchy.image-picker {"source":"themes"}`.
// - O PluginShellApi não expõe os panelLoaders, então a Ilha não vê o
//   `opened` do picker. Ela vê o evento do Hyprland `openlayer>>
//   omarchy-image-selector` (a superfície mapeia transparente: o picker só
//   se revela depois de dois quadros e das prévias decodificadas). Como todo
//   pedido image-selector passa por aqui, uma superfície que abre sem um
//   pedido repassado é o seletor de temas: shell.hide() e a tela de temas.
// - Só com o alvo image-selector liderando (senão não dá para distinguir).
//
// Chaves de emergência: takeoverBackgrounds e takeoverThemes (o Ilha.qml
// liga; desligadas no harness). Desligadas, o seletor do host funciona igual.
QtObject {
    id: root

    // ---- Entradas ----
    property var island: null
    property var shell: null

    // ---- Chaves de emergência (Phase 2) ----
    property bool takeoverBackgrounds: true
    property bool takeoverThemes: true

    // ---- Estado ----
    // Pedido do script: {rows: [{path, thumb, name, video}], selected, selectionFile, doneFile} | null.
    property var pending: null

    // O alvo image-selector existe (host presente e algum takeover ligado).
    readonly property bool active: !!root.shell && (root.takeoverBackgrounds || root.takeoverThemes)
        && !(root.island && root.island.dev)
    // A Ilha lidera o alvo (o handler está ligado no registro).
    readonly property bool leading: root.active && ipc.enabled

    readonly property string home: Quickshell.env("HOME")
    readonly property var backgroundDirs: [
        root.home + "/.local/state/omarchy/current/theme/backgrounds/",
        root.home + "/.config/omarchy/backgrounds/"
    ]

    // Grava a escolha e cria o doneFile (uma vez por pedido).
    function finish(path) {
        const p = root.pending;
        if (!p)
            return;
        root.pending = null;
        if (!p.selectionFile || !p.doneFile)
            return;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"; : > \"$3\"", "ilha", String(path || ""), p.selectionFile, p.doneFile]);
    }

    // Repassa um open ao handler do host; "unknown" sem host (o script falha
    // limpo, como quando o summon do host falha).
    function forwardOpen(imageDirs, imageRowsB64, selectedImage, selectionFile, doneFile, showLabels, filterable) {
        const host = root.hostHandler();
        priv.forwardedAt = Date.now();
        if (!host || typeof host.open !== "function")
            return "unknown";
        return host.open(String(imageDirs || ""), String(imageRowsB64 || ""), String(selectedImage || ""),
            String(selectionFile || ""), String(doneFile || ""), String(showLabels || ""), String(filterable || ""));
    }

    // ---- Interno ----

    function hostHandler() {
        const reg = Commons.IpcRegistry;
        const list = reg && Array.isArray(reg.handlers) ? reg.handlers : [];
        for (let i = 0; i < list.length; i++) {
            const h = list[i];
            if (h && h !== ipc && h.target === "image-selector")
                return h;
        }
        return null;
    }

    // Põe o handler da Ilha à frente do do host no registro.
    function lead() {
        if (!root.active)
            return;
        const reg = Commons.IpcRegistry;
        if (!reg || !Array.isArray(reg.handlers) || typeof reg.touch !== "function")
            return;
        const list = reg.handlers;
        const at = list.indexOf(ipc);
        if (at < 0)
            return;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].target === "image-selector") {
                if (i === at)
                    return;
                break;
            }
        }
        const next = list.slice();
        next.splice(at, 1);
        next.unshift(ipc);
        reg.handlers = next;
        reg.touch();
    }

    // Base64 -> texto UTF-8 (caminhos com acento sobrevivem; Qt.atob devolve
    // bytes soltos e está obsoleto).
    function decodeRows(b64) {
        const s = String(b64 || "").replace(/[^A-Za-z0-9+\/]/g, "");
        const map = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        const bytes = [];
        let buf = 0, bits = 0;
        for (let i = 0; i < s.length; i++) {
            buf = ((buf << 6) | map.indexOf(s.charAt(i))) & 0xffffff;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                bytes.push((buf >> bits) & 0xff);
            }
        }
        let out = "";
        for (let i = 0; i < bytes.length;) {
            const b = bytes[i];
            let cp = 0xfffd, n = 1;
            if (b < 0x80) {
                cp = b;
            } else if ((b & 0xe0) === 0xc0) {
                cp = b & 0x1f;
                n = 2;
            } else if ((b & 0xf0) === 0xe0) {
                cp = b & 0x0f;
                n = 3;
            } else if ((b & 0xf8) === 0xf0) {
                cp = b & 0x07;
                n = 4;
            }
            for (let k = 1; k < n; k++)
                cp = (cp << 6) | ((bytes[i + k] || 0) & 0x3f);
            out += String.fromCodePoint(cp);
            i += n;
        }
        return out;
    }

    function parseRows(text) {
        const out = [];
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            if (lines[i] === "")
                continue;
            const parts = lines[i].split("\t");
            const path = parts[0];
            const video = /\.(mp4|m4v|mov|webm|mkv|avi)$/i.test(path);
            let thumb = String(parts[1] || "");
            if (thumb === "" || thumb === path || /\.failed$/.test(thumb))
                thumb = video ? "" : path;
            out.push({ path: path, thumb: thumb, name: path.substring(path.lastIndexOf("/") + 1), video: video });
        }
        return out;
    }

    function isBackground(path) {
        const p = String(path || "");
        if (p === "" || p.indexOf("/../") !== -1 || p.indexOf("/./") !== -1)
            return false;
        for (let i = 0; i < root.backgroundDirs.length; i++) {
            if (p.indexOf(root.backgroundDirs[i]) === 0)
                return true;
        }
        return false;
    }

    function handleOpen(imageDirs, imageRowsB64, selectedImage, selectionFile, doneFile, showLabels, filterable) {
        const rows = root.parseRows(root.decodeRows(imageRowsB64));
        const ours = root.takeoverBackgrounds && !!root.island
            && String(selectionFile || "") !== "" && String(doneFile || "") !== ""
            && rows.length > 0 && rows.every(r => root.isBackground(r.path));
        if (!ours)
            return root.forwardOpen(imageDirs, imageRowsB64, selectedImage, selectionFile, doneFile, showLabels, filterable);
        // Um pedido anterior ainda aberto termina vazio (o script dele não trava).
        if (root.pending && root.pending.doneFile !== String(doneFile))
            root.finish("");
        root.pending = {
            rows: rows,
            selected: String(selectedImage || ""),
            selectionFile: String(selectionFile),
            doneFile: String(doneFile)
        };
        root.island.keyboardMode = true;
        if (!root.island.open("wallpapers", root.island.focusedOutput(), { keyboard: true, takeover: true }))
            root.finish("");
        return "ok";
    }

    function handleCancel(doneFile) {
        if (root.pending && root.pending.doneFile === String(doneFile || "")) {
            root.finish("");
            // Os papéis de parede vivem na tela de temas (fileira de baixo).
            if (root.island && root.island.screen === "themes")
                root.island.close();
            return "ok";
        }
        const host = root.hostHandler();
        return host && typeof host.cancel === "function" ? host.cancel(String(doneFile || "")) : "ok";
    }

    function handlePreload(imageRowsB64, selectedImage, showLabels, filterable) {
        const host = root.hostHandler();
        const out = host && typeof host.preload === "function"
            ? host.preload(String(imageRowsB64 || ""), String(selectedImage || ""), String(showLabels || ""), String(filterable || ""))
            : "ok";
        // Linhas de papéis do tema: aquece a lista da Ilha também.
        const rows = root.parseRows(root.decodeRows(imageRowsB64));
        if (root.island && root.island.themes && rows.length > 0 && rows.every(r => root.isBackground(r.path)))
            root.island.themes.reloadWallpapers();
        return out;
    }

    // A superfície do seletor do host mapeou.
    function hostPickerOpened() {
        // Um pedido que a Ilha repassou (Plymouth, pastas de fora): é do host.
        if (priv.hostOwned || Date.now() - priv.forwardedAt < 5000) {
            priv.hostOwned = true;
            return;
        }
        if (!root.takeoverThemes || !root.leading || !root.shell || !root.island)
            return;
        Qt.callLater(() => {
            if (typeof root.shell.isPluginOpen === "function" && !root.shell.isPluginOpen("omarchy.image-picker"))
                return;
            if (typeof root.shell.hide === "function")
                root.shell.hide("omarchy.image-picker");
            root.island.keyboardMode = true;
            root.island.open("themes", root.island.focusedOutput(), { keyboard: true });
        });
    }

    // O alvo é posto fora de binding: lido no meio da avaliação de `enabled`
    // do ShellIpc, um binding de target tocaria o registro e faria laço.
    function syncTarget() {
        const t = root.active ? "image-selector" : "";
        if (ipc.target !== t)
            ipc.target = t;
        Qt.callLater(root.lead);
    }

    onActiveChanged: Qt.callLater(root.syncTarget)
    Component.onCompleted: Qt.callLater(root.syncTarget)
    Component.onDestruction: root.finish("")

    property QtObject internals: QtObject {
        id: priv
        property real forwardedAt: 0
        property bool hostOwned: false
    }

    property Commons.ShellIpc handler: Commons.ShellIpc {
        id: ipc

        function open(imageDirs: string, imageRowsB64: string, selectedImage: string, selectionFile: string,
                      doneFile: string, showLabels: string, filterable: string): string {
            return root.handleOpen(imageDirs, imageRowsB64, selectedImage, selectionFile, doneFile, showLabels, filterable);
        }

        function preload(imageRowsB64: string, selectedImage: string, showLabels: string, filterable: string): string {
            return root.handlePreload(imageRowsB64, selectedImage, showLabels, filterable);
        }

        function cancel(doneFile: string): string {
            return root.handleCancel(doneFile);
        }

        function ping(): string {
            return "ok";
        }
    }

    // Outra tela (ou nenhuma) com um pedido aberto: o script recebe "nada".
    property Connections screenWatch: Connections {
        target: root.island
        function onScreenChanged() {
            if (root.pending && root.island && root.island.screen !== "themes")
                root.finish("");
        }
    }

    // Superfícies do seletor do host abrindo e fechando (só com o takeover de temas).
    property Connections layerWatch: Connections {
        target: Hyprland
        enabled: root.takeoverThemes && root.active
        function onRawEvent(event) {
            if (!event || event.data !== "omarchy-image-selector")
                return;
            if (event.name === "openlayer") {
                root.hostPickerOpened();
            } else if (event.name === "closelayer") {
                priv.hostOwned = false;
                priv.forwardedAt = 0;
            }
        }
    }
}
