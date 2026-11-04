import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Motion.js" as Motion

// Serviço da tela de Captura: os rótulos que o próprio Omarchy já traduz, a
// guarda da webcam e a execução das ações. Uma instância por tela, criada
// dentro da CaptureScreen (não é um serviço da ilha). Dono: agente da Captura.
//
// - Rótulos: o catálogo do menu do Omarchy,
//   $OMARCHY_PATH/default/i18n/<idioma>/menu.json ({"chave": {"label": "…"}}),
//   por cima do en/menu.json; o idioma é o do Commons.I18n, o mesmo que a
//   Ilha segue. label(chave, reserva): idioma -> inglês -> reserva -> chave.
//   Os arquivos são vigiados: trocar o idioma relê sem reiniciar.
//   shellLabel(chave, reserva): o catálogo do shell (Commons.I18n).
// - Webcam: omarchy-hw-webcam (a guarda "when" da entrada de webcam no menu;
//   só lê o que o udev já registrou). probe() a cada opened() da tela.
// - run(id, argv): o comando num processo à parte, CLOSE_THEN_RUN_MS depois
//   (sh -c 'sleep …; exec "$@"'), para a ilha já ter fechado e não sair na
//   captura. Quem chama fecha a ilha antes. ILHA_DEV=1 (harness): só
//   registra no log, nunca executa.
QtObject {
    id: root

    readonly property bool dev: Quickshell.env("ILHA_DEV") === "1"
    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    readonly property string language: Commons.I18n.language

    // ---- Rótulos do menu do Omarchy ----
    readonly property var englishMenu: root.parseCatalog(root.englishFile.text())
    readonly property var languageMenu: root.parseCatalog(root.languageFile.text())

    function label(key, fallback) {
        const k = String(key || "");
        const fromLang = root.labelIn(root.languageMenu, k);
        if (fromLang !== "")
            return fromLang;
        const fromEn = root.labelIn(root.englishMenu, k);
        if (fromEn !== "")
            return fromEn;
        return fallback !== undefined ? String(fallback) : k;
    }

    // Um rótulo do catálogo do shell do Omarchy (default/i18n/<idioma>/shell.json).
    function shellLabel(key, fallback) {
        return Commons.I18n.t(key, fallback);
    }

    function labelIn(catalog, key) {
        const entry = catalog ? catalog[key] : null;
        const v = entry && typeof entry === "object" ? entry.label : entry;
        return typeof v === "string" ? v : "";
    }

    function parseCatalog(raw) {
        try {
            const parsed = JSON.parse(raw || "{}");
            return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    function catalogPath(code) {
        return root.omarchyPath !== "" ? root.omarchyPath + "/default/i18n/" + code + "/menu.json" : "";
    }

    // ---- Webcam ----
    // Sem resposta ainda: disponível (o menu do Omarchy pergunta a cada abertura).
    property bool webcamOk: true

    function probe() {
        if (!root.webcamProbe.running)
            root.webcamProbe.running = true;
    }

    // ---- Execução ----
    function run(id, argv) {
        const cmd = Array.isArray(argv) ? argv.map(a => String(a)) : [];
        if (cmd.length === 0)
            return;
        if (root.dev) {
            console.log("ilha(dev): captura " + id + " -> " + cmd.join(" ") + " (não executado)");
            return;
        }
        const wait = (Motion.TIMING.CLOSE_THEN_RUN_MS / 1000).toFixed(2);
        Quickshell.execDetached(["sh", "-c", "sleep \"$0\"; exec \"$@\"", wait].concat(cmd));
    }

    // ---- Arquivos e processos ----
    property FileView englishFile: FileView {
        path: root.catalogPath("en")
        watchChanges: true
        printErrors: false
        blockLoading: true
        onFileChanged: reload()
    }

    property FileView languageFile: FileView {
        path: root.language !== "en" ? root.catalogPath(root.language) : ""
        watchChanges: true
        printErrors: false
        blockLoading: true
        onFileChanged: reload()
    }

    // Sai 0 = há uma webcam que dá para abrir.
    property Process webcamProbe: Process {
        command: ["omarchy-hw-webcam"]
        onExited: (code, status) => root.webcamOk = code === 0
    }
}
