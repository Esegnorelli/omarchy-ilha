import QtQuick
import Quickshell
import Quickshell.Io

// Harness de desenvolvimento da Ilha 2.0 (nunca carregado pelo Omarchy).
//
// dev/harness.sh copia este arquivo para $XDG_RUNTIME_DIR/ilha-harness/<nome>/
// shell.qml, ao lado de um link Commons -> $OMARCHY_PATH/shell/Commons, e roda
// `ILHA_DEV=1 ILHA_REPO=<repo> qs -p <pasta>`. É um processo à parte, com
// caches novos: o shell do usuário nunca é reiniciado nem tocado.
//
// Carrega <repo>/ui/Ilha.qml como o host carrega uma barra, mas sem host:
// shell = null, barWidgetRegistry = null, pluginRegistry = null. Passa
// omarchyPath, o manifest.json do repo e, se ILHA_DEV_BARCONFIG tiver um
// JSON, esse barConfig.
ShellRoot {
    id: root

    readonly property string repo: Quickshell.env("ILHA_REPO")

    FileView {
        id: manifestFile
        path: root.repo + "/manifest.json"
        blockLoading: true
        printErrors: false
    }

    Loader {
        id: bar
        source: "file://" + root.repo + "/ui/Ilha.qml"
        onLoaded: {
            bar.item.omarchyPath = Quickshell.env("OMARCHY_PATH");
            try {
                bar.item.manifest = JSON.parse(manifestFile.text());
            } catch (e) {
                console.warn("harness: manifest.json ilegível: " + e);
            }
            const bc = Quickshell.env("ILHA_DEV_BARCONFIG");
            if (bc) {
                try {
                    bar.item.barConfig = JSON.parse(bc);
                } catch (e) {
                    console.warn("harness: ILHA_DEV_BARCONFIG inválido: " + e);
                }
            }
            console.log("harness: Ilha carregada de " + root.repo);
        }
        onStatusChanged: if (bar.status === Loader.Error) console.warn("harness: ui/Ilha.qml não carregou")
    }
}
