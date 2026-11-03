import QtQuick
import Quickshell
import Quickshell.Io

// Estado próprio da Ilha, em $XDG_STATE_HOME/esegnorelli.ilha (padrão
// ~/.local/state/esegnorelli.ilha):
//
//   state.json      {clearedAt, nightK}   escrito só por este arquivo
//   game-mode.json  o modo jogo da 1.x     só lido aqui (o StatusSvc grava)
//
// - clearedAt: ms (Date.now()) da última "Limpar" das notificações. O
//   histórico mostra só o que fechou depois disso (e nas últimas 24 h).
// - nightK: temperatura preferida da luz noturna (2500..5800 K).
// - Gravar = atribuir: `store.clearedAt = Date.now()`. A gravação sai num
//   lote curto (uma escrita para várias mudanças seguidas) e é atômica.
// - Uma chave hintSeen antiga (a dica de primeira vez saiu na 2.0) é
//   ignorada na leitura e some na próxima gravação. Chaves desconhecidas
//   também não voltam: o arquivo é sempre exatamente {clearedAt, nightK}.
// - legacyGameMode: o objeto do game-mode.json ({animations, gaps,
//   transparency}) enquanto o arquivo existe; {} se existe mas não se lê;
//   null sem arquivo. Ligado = o arquivo existe (regra da 1.x).
// - ready: a primeira leitura do state.json terminou (com ou sem arquivo).
//
// Harness (ILHA_DEV=1): lê o arquivo de verdade, mas nunca grava; as
// mudanças ficam na memória até o harness parar.
QtObject {
    id: root

    property real clearedAt: 0
    property int nightK: 4000
    readonly property var legacyGameMode: priv.gameMode
    readonly property bool ready: priv.loaded

    // Pasta e arquivos (a mesma pasta do game-mode.json da 1.x).
    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/esegnorelli.ilha"
    readonly property string statePath: root.dir + "/state.json"
    readonly property string gameModePath: root.dir + "/game-mode.json"
    readonly property bool dev: Quickshell.env("ILHA_DEV") === "1"

    // Relê o game-mode.json (o StatusSvc chama depois de ligar ou desligar).
    function reloadGameMode() {
        gameModeFile.reload();
    }

    onClearedAtChanged: root.scheduleSave()
    onNightKChanged: root.scheduleSave()

    function scheduleSave() {
        // Valores que vieram do próprio arquivo não voltam para ele.
        if (!priv.loaded || priv.applying)
            return;
        saveTimer.restart();
    }

    function clampK(k) {
        const v = Math.round(Number(k));
        return isFinite(v) ? Math.max(2500, Math.min(5800, v)) : 4000;
    }

    function applyText(text) {
        let data = null;
        try {
            data = JSON.parse(String(text || ""));
        } catch (e) {
            data = null;
        }
        priv.applying = true;
        if (data && typeof data === "object" && !Array.isArray(data)) {
            const c = Number(data.clearedAt);
            if (isFinite(c) && c >= 0)
                root.clearedAt = c;
            if (data.nightK !== undefined)
                root.nightK = root.clampK(data.nightK);
        }
        priv.applying = false;
    }

    function write() {
        if (root.dev)
            return;
        const body = JSON.stringify({ clearedAt: Math.round(root.clearedAt), nightK: root.clampK(root.nightK) }) + "\n";
        if (priv.dirReady) {
            stateFile.setText(body);
            return;
        }
        // Primeira gravação da sessão: garante a pasta antes.
        priv.pendingBody = body;
        if (!mkdirProc.running)
            mkdirProc.running = true;
    }

    readonly property QtObject _priv: QtObject {
        id: priv
        property bool loaded: false
        property bool applying: false
        property bool dirReady: false
        property string pendingBody: ""
        property var gameMode: null
    }

    readonly property Timer _saveTimer: Timer {
        id: saveTimer
        interval: 150
        onTriggered: root.write()
    }

    readonly property Process _mkdirProc: Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.dir]
        onExited: (code, status) => {
            priv.dirReady = code === 0;
            if (priv.dirReady && priv.pendingBody !== "") {
                stateFile.setText(priv.pendingBody);
                priv.pendingBody = "";
            }
        }
    }

    readonly property FileView _stateFile: FileView {
        id: stateFile
        path: root.statePath
        printErrors: false
        atomicWrites: true
        // Só lê na partida: este arquivo é nosso, ninguém mais escreve nele.
        watchChanges: false
        onLoaded: {
            priv.dirReady = true;
            root.applyText(stateFile.text());
            priv.loaded = true;
        }
        onLoadFailed: error => {
            priv.loaded = true;
        }
    }

    readonly property FileView _gameModeFile: FileView {
        id: gameModeFile
        path: root.gameModePath
        printErrors: false
        watchChanges: true
        onFileChanged: gameModeFile.reload()
        onLoaded: {
            let data = null;
            try {
                data = JSON.parse(gameModeFile.text());
            } catch (e) {
                data = null;
            }
            priv.gameMode = data && typeof data === "object" && !Array.isArray(data) ? data : ({});
        }
        onLoadFailed: error => {
            priv.gameMode = null;
        }
    }

    // A pasta: pega a criação e a remoção do game-mode.json (o FileView de
    // um arquivo que ainda não existe não percebe quando ele aparece).
    readonly property FileView _dirWatch: FileView {
        path: root.dir
        printErrors: false
        watchChanges: true
        onFileChanged: gameModeFile.reload()
    }
}
