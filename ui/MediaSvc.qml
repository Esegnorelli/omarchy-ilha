import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "Motion.js" as Motion

// Música: a faixa atual, o player e os comandos de transporte. Um só por
// ilha (island.media). Dono: Agent H.
//
// Fonte: o serviço omarchy.media do host (shell.firstPartyServiceFor), o
// mesmo player ativo da barra padrão, com a mesma escolha (preferido, o que
// toca há mais tempo, depois o ocioso com faixa). Sem host (harness, host
// antigo), o MPRIS direto com a escolha simples da 1.x: o selecionado, senão
// o que toca, senão o primeiro com faixa.
//
// - hasTrack: há título ou artista. Sem isso nada de música aparece.
// - title / artist / album numa linha só (sem marcação); um player que só
//   manda o artista vira título.
// - position / length em segundos; canSeek só com posição e duração.
// - O MPRIS não avisa o avanço da posição: positionPolling (a tela de Mídia
//   liga enquanto está aberta) pede a leitura a cada MEDIA_POSITION_MS, só
//   tocando. Fora disso, nada roda.
// - loopState: "none" | "track" | "playlist".
// - playerName: nome curto (Spotify, Firefox…). playerIconName: o ícone do
//   app pelo .desktop (Quickshell.iconPath), nunca um Material Symbol.
//   playerDesktopId: o desktopEntry do player.
// - trackChangedAt: Date.now() da última troca de faixa (crossfade da capa).
// - Comandos sem OSD do host: o controle já está na tela.
QtObject {
    id: root

    // ---- Entradas ----
    property var shell: null

    // ---- Estado ----
    // Os players com algum metadado, na ordem do host (tocando primeiro).
    readonly property var players: root.mediaService ? (root.mediaService.sourcePlayers || []) : priv.ownPlayers
    readonly property var player: root.mediaService ? (root.mediaService.activePlayer || null) : priv.ownPlayer
    readonly property bool hasTrack: !!root.player && !!(root.player.trackTitle || root.player.trackArtist)
    readonly property bool playing: root.hasTrack && root.player.isPlaying === true
    readonly property string title: root.hasTrack ? root.oneLine(root.player.trackTitle || root.player.trackArtist, 160) : ""
    readonly property string artist: root.hasTrack && root.player.trackTitle ? root.oneLine(root.player.trackArtist, 120) : ""
    readonly property string album: root.hasTrack ? root.oneLine(root.player.trackAlbum, 120) : ""
    readonly property string artUrl: root.hasTrack && root.player.trackArtUrl ? String(root.player.trackArtUrl) : ""
    readonly property real position: root.player && root.player.positionSupported ? Math.max(0, Number(root.player.position) || 0) : 0
    readonly property real length: root.player && root.player.lengthSupported && Number(root.player.length) > 0 ? Number(root.player.length) : 0
    readonly property bool canSeek: !!root.player && root.player.canSeek === true && root.player.positionSupported === true && root.length > 0
    readonly property bool canPrevious: !!root.player && root.player.canGoPrevious === true
    readonly property bool canNext: !!root.player && root.player.canGoNext === true
    readonly property bool canPlayPause: !!root.player && (root.player.canTogglePlaying === true || root.player.canPlay === true || root.player.canPause === true)
    readonly property bool shuffleSupported: !!root.player && root.player.shuffleSupported === true && root.player.canControl === true
    readonly property bool loopSupported: !!root.player && root.player.loopSupported === true && root.player.canControl === true
    readonly property bool shuffle: root.shuffleSupported && root.player.shuffle === true
    readonly property string loopState: {
        if (!root.loopSupported)
            return "none";
        const s = root.player.loopState;
        return s === MprisLoopState.Track ? "track" : (s === MprisLoopState.Playlist ? "playlist" : "none");
    }
    readonly property string playerName: root.labelFor(root.player)
    readonly property string playerDesktopId: root.player ? String(root.player.desktopEntry || "") : ""
    readonly property string playerIconName: {
        const id = root.playerDesktopId;
        const name = id !== "" ? id : (root.player ? String(root.player.identity || "") : "");
        if (name === "")
            return "";
        const entry = DesktopEntries.heuristicLookup(name);
        return entry && entry.icon ? String(entry.icon) : "";
    }
    readonly property real trackChangedAt: priv.trackChangedAt
    property bool positionPolling: false
    // Abrir a tela (ou trocar de player) lê a posição na hora, mesmo pausado.
    onPositionPollingChanged: root.readPosition()
    onPlayerChanged: root.readPosition()
    function readPosition() {
        if (root.positionPolling && root.player)
            root.player.positionChanged();
    }

    // ---- Comandos ----
    function playPause() {
        root.act("playPause");
    }
    function next() {
        root.act("next");
    }
    function previous() {
        root.act("previous");
    }
    // Vai para `seconds` (absoluto). Para meio segundo antes do fim (o player
    // pularia a faixa).
    function seek(seconds) {
        const p = root.player;
        if (!root.canSeek || !p)
            return false;
        const to = Math.max(0, Math.min(root.length - 0.5, Number(seconds) || 0));
        p.position = to;
        p.positionChanged();
        return true;
    }
    function setShuffle(on) {
        if (!root.shuffleSupported)
            return false;
        root.player.shuffle = !!on;
        return true;
    }
    // Desligado -> lista -> faixa -> desligado.
    function cycleLoop() {
        if (!root.loopSupported)
            return false;
        const p = root.player;
        const now = p.loopState;
        p.loopState = now === MprisLoopState.None ? MprisLoopState.Playlist : (now === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None);
        return true;
    }
    // O próximo player da lista vira o ativo (só com mais de um).
    function selectNext() {
        const list = root.players;
        if (!list || list.length < 2)
            return false;
        const key = root.keyOf(root.player);
        let at = -1;
        for (let i = 0; i < list.length; i++) {
            if (root.keyOf(list[i]) === key)
                at = i;
        }
        const next = list[(at + 1) % list.length];
        const nextKey = root.keyOf(next);
        if (root.mediaService && typeof root.mediaService.selectPlayer === "function")
            root.mediaService.selectPlayer(nextKey);
        else
            priv.ownKey = nextKey;
        return true;
    }

    // ---- Ajudantes ----
    function serviceFor(id) {
        if (!root.shell || typeof root.shell.firstPartyServiceFor !== "function")
            return null;
        try {
            return root.shell.firstPartyServiceFor(id) || null;
        } catch (e) {
            return null;
        }
    }
    readonly property var mediaService: root.serviceFor("omarchy.media")

    function keyOf(p) {
        if (!p)
            return "";
        if (root.mediaService && typeof root.mediaService.playerKey === "function") {
            const k = String(root.mediaService.playerKey(p) || "");
            if (k !== "")
                return k;
        }
        return String(p.dbusName || p.desktopEntry || p.identity || "");
    }

    // Nome curto do player (o mesmo critério da barra do Omarchy).
    function labelFor(p) {
        if (!p)
            return "";
        const name = String(p.identity || p.desktopEntry || "").trim();
        if (name !== "")
            return root.oneLine(name, 32);
        const dbus = String(p.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "").replace(/\.instance[0-9_]+$/, "");
        return root.oneLine(dbus, 32);
    }

    function oneLine(value, maxLen) {
        let text = String(value === null || value === undefined ? "" : value);
        text = text.replace(/[\u0000-\u001f\u007f]+/g, " ");
        text = text.replace(/<[^>]{0,200}>/g, " ");
        text = text.replace(/\s+/g, " ").trim();
        return text.length > maxLen ? text.slice(0, maxLen) : text;
    }

    // playPause / next / previous. Pelo host quando há (mesma escolha de
    // player e a mesma ordem de "tocou por último"); sem OSD.
    function act(action) {
        const p = root.player;
        if (root.mediaService && typeof root.mediaService.runAction === "function") {
            root.mediaService.runAction(action, false, root.keyOf(p));
            return true;
        }
        if (!p)
            return false;
        if (action === "next" && p.canGoNext) {
            p.next();
            return true;
        }
        if (action === "previous" && p.canGoPrevious) {
            p.previous();
            return true;
        }
        if (action === "playPause") {
            if (p.isPlaying && p.canPause) {
                p.pause();
                return true;
            }
            if (!p.isPlaying && p.canPlay) {
                p.play();
                return true;
            }
            if (p.canTogglePlaying) {
                p.togglePlaying();
                return true;
            }
        }
        return false;
    }

    // Assinatura da faixa: muda com título, artista, álbum ou capa.
    readonly property string trackSignature: root.player ? [root.player.trackTitle || "", root.player.trackArtist || "", root.player.trackAlbum || "", root.player.trackArtUrl || ""].join("\u001f") : ""
    onTrackSignatureChanged: priv.trackChangedAt = Date.now()

    readonly property QtObject _priv: QtObject {
        id: priv

        property real trackChangedAt: 0
        // Só sem host: o player escolhido pelo selectNext.
        property string ownKey: ""

        // Reserva sem host: os players do MPRIS com algum metadado, tocando primeiro.
        readonly property var ownPlayers: {
            if (root.mediaService)
                return [];
            const list = Mpris.players ? Mpris.players.values : [];
            const out = [];
            for (let i = 0; i < list.length; i++) {
                const p = list[i];
                if (p && (p.trackTitle || p.trackArtist || p.identity || p.desktopEntry))
                    out.push(p);
            }
            out.sort((a, b) => (!!a.isPlaying === !!b.isPlaying) ? 0 : (a.isPlaying ? -1 : 1));
            return out;
        }
        readonly property var ownPlayer: {
            const list = priv.ownPlayers;
            if (list.length === 0)
                return null;
            if (priv.ownKey !== "") {
                for (let i = 0; i < list.length; i++) {
                    if (root.keyOf(list[i]) === priv.ownKey)
                        return list[i];
                }
            }
            for (let j = 0; j < list.length; j++) {
                if (list[j].isPlaying)
                    return list[j];
            }
            for (let k = 0; k < list.length; k++) {
                if (list[k].trackTitle)
                    return list[k];
            }
            return list[0];
        }
    }

    // A posição só anda com a tela de Mídia aberta e tocando.
    readonly property Timer _positionTimer: Timer {
        interval: Motion.TIMING.MEDIA_POSITION_MS
        repeat: true
        triggeredOnStart: true
        running: root.positionPolling && root.playing && root.player !== null
        onTriggered: {
            if (root.player)
                root.player.positionChanged();
        }
    }
}
