pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Commons as Commons
import "Motion.js" as Motion

// Seletor de papel de parede (screens §13; dono: Agent G). Painel
// 32 + 196k x 232 (k = 2..5 miniaturas pela largura da tela), cap 30.
//
// Duas camadas (motion F):
// - CABEÇALHO, preso às bordas vivas (só x): "Papel de parede" 15,5/600 a
//   15 px da borda (topo das maiúsculas em 21,5) e o tema atual 12 inkFaint
//   a 15 px da borda direita, na mesma linha de base.
// - CORPO, no layout final centrado: a faixa (centro em y 120, passo 196,
//   recortada em exatamente k passos) e o rodapé em y 209: o nome do arquivo
//   à esquerda; "3/7 · Enter para aplicar" à direita.
//
// Miniatura 189 x 116, raio 12. Escala 1 / 0,9 / 0,8 e opacidade
// max(0,4, 1 − 0,3|d|), contínuas na posição da faixa. A escolhida tem uma
// borda interna de 2,25 px em accent (cruza em 70 ms); a bolinha de 6 px a
// 12 do canto marca o papel atual (ou o pedido agora). Imagens: a miniatura
// JPEG da coluna 2 do --print-rows, assíncrona, sourceSize 378 x 232, entra
// em 120 ms sobre um fundo quase preto; só carrega o que está perto da faixa.
// Vídeo sem miniatura: um bloco com o glifo de filme.
//
// Duas origens:
// - Própria (`ilha open wallpapers`, Ctrl+Tab, seletor): ThemesSvc.wallpapers.
//   Enter roda `omarchy-theme-bg-set` e a tela fecha quando ele sai (no
//   máximo 1,2 s).
// - Takeover (Super+Ctrl+W, menu Plano de fundo): o pedido do script
//   (PickerBridge.pending, com as linhas dele). Enter grava a escolha e cria
//   o doneFile; o script do Omarchy aplica. Esc, perda de foco ou outra tela
//   devolvem uma escolha vazia (PickerBridge), para o script nunca travar.
Item {
    id: root

    // ---- Contrato de tela ----
    property var island: null
    property Theme theme: null
    property var strings: null
    property var morph: null
    property bool current: false
    property bool keyboardMode: false
    property var payload: null
    property real edgeLeft: 0
    property real edgeRight: root.implicitWidth
    property var heightMotion: "panel"
    property bool snapping: false
    property list<Item> headerItems: [header]
    property list<Item> bodyItems: [body]
    signal navigate(string id, var payload)
    signal closeRequested()

    function opened(payload) {
        root.snapping = true;
        priv.applying = false;
        priv.takeoverApplied = false;
        closeFallback.stop();
        priv.userMoved = false;
        priv.request = root.pickers && root.pickers.pending ? root.pickers.pending : null;
        // Também liga o tema atual (cabeçalho) e relê o papel atual (marca).
        if (root.themesSvc)
            root.themesSvc.reloadWallpapers();
        root.resync();
        Qt.callLater(() => root.snapping = false);
    }

    function closed() {
        closeFallback.stop();
        // Takeover ainda aberto (Esc, outra tela): o script recebe "nada".
        if (priv.request && root.pickers && root.pickers.pending === priv.request)
            root.pickers.finish("");
        priv.applying = false;
    }

    function handleKey(event) {
        const k = event.key;
        const mods = event.modifiers;
        // Ctrl+Tab, Alt+n e Esc ficam com a janela.
        if (mods & (Qt.ControlModifier | Qt.AltModifier))
            return false;
        const dir = root.theme ? root.theme.dir : 1;
        const page = Math.max(1, root.dims.k);
        switch (k) {
        case Qt.Key_Left:
            root.move(-dir);
            return true;
        case Qt.Key_Right:
            root.move(dir);
            return true;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            root.move(-1);
            return true;
        case Qt.Key_Down:
            root.move(1);
            return true;
        case Qt.Key_Tab:
            root.move(mods & Qt.ShiftModifier ? -1 : 1);
            return true;
        case Qt.Key_PageUp:
            root.move(-page);
            return true;
        case Qt.Key_PageDown:
            root.move(page);
            return true;
        case Qt.Key_Home:
            priv.userMoved = true;
            strip.jump(0, true);
            return true;
        case Qt.Key_End:
            priv.userMoved = true;
            strip.jump(root.list.length - 1, true);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.applySelected();
            return true;
        default:
            return false;
        }
    }

    function handleEscape() {
        return false;
    }

    // ---- Medidas ----
    readonly property var dims: root.theme && root.island ? root.theme.screenSize("wallpapers", root.island.screenGeometry(root.island.screenOutput)) : ({ w: 1012, h: 232, k: 5 })
    implicitWidth: root.dims.w
    implicitHeight: root.dims.h

    readonly property real pitch: root.theme ? root.theme.px.WALLS_PITCH : 196
    readonly property real inset: Math.max(12, (root.implicitWidth - root.pitch * Math.max(1, root.dims.k)) / 2)
    readonly property bool rtl: root.theme ? root.theme.rtl : false
    // Altura das maiúsculas da Inter (1490/2048 do em).
    readonly property real capRatio: 0.7275

    // ---- Dados ----
    readonly property var themesSvc: root.island ? root.island.themes : null
    readonly property var pickers: root.island ? root.island.pickers : null
    readonly property var list: priv.request ? priv.request.rows : (root.themesSvc ? root.themesSvc.wallpapers : [])
    readonly property bool ready: !!priv.request || (!!root.themesSvc && root.themesSvc.wallpapersReady)
    // A miniatura com a marca do atual (o pedido agora, senão o aplicado).
    readonly property int markedIndex: {
        const svc = root.themesSvc;
        if (!svc)
            return -1;
        const want = svc.pendingWallpaper || svc.currentWallpaper;
        return want !== "" ? svc.wallpaperIndex(root.list, want) : -1;
    }

    function digits(n) {
        return Commons.I18n.formatNumber(n);
    }

    function indexOfPath(path) {
        const p = String(path || "");
        if (p === "")
            return -1;
        for (let i = 0; i < root.list.length; i++) {
            if (root.list[i].path === p)
                return i;
        }
        return -1;
    }

    // Recentra: no escolhido pelo usuário, senão no pedido do script, senão no atual.
    function resync() {
        let i = priv.userMoved ? root.indexOfPath(priv.selPath) : -1;
        if (i < 0 && priv.request && priv.request.selected)
            i = root.indexOfPath(priv.request.selected);
        if (i < 0)
            i = root.markedIndex;
        if (i < 0)
            i = 0;
        strip.jump(i, false);
        root.noteIndex();
    }

    function noteIndex() {
        const w = root.list[strip.index];
        priv.selPath = w ? w.path : "";
    }

    function move(n) {
        priv.userMoved = true;
        strip.step(n);
    }

    function activate(i) {
        priv.userMoved = true;
        if (i !== strip.index)
            strip.jump(i, true);
        root.applySelected();
    }

    function applySelected() {
        const w = root.list[strip.index];
        if (!w || priv.applying)
            return;
        if (priv.request) {
            // O script aplica; a ilha só marca e espera o link mudar.
            if (root.themesSvc)
                root.themesSvc.noteWallpaper(w.path);
            if (root.pickers)
                root.pickers.finish(w.path);
            priv.applying = true;
            priv.takeoverApplied = true;
            closeFallback.restart();
            return;
        }
        if (!root.themesSvc)
            return;
        if (strip.index === root.markedIndex && root.themesSvc.pendingWallpaper === "") {
            // Já é o papel atual.
            root.closeRequested();
            return;
        }
        if (!root.themesSvc.applyWallpaper(w.path))
            return;
        priv.applying = true;
        closeFallback.restart();
    }

    function finishApply() {
        if (!priv.applying)
            return;
        priv.applying = false;
        closeFallback.stop();
        if (root.current)
            root.closeRequested();
    }

    // Lado esquerdo / direito no cabeçalho (bordas vivas), espelhado em RTL.
    function fromStart(off, w) {
        return root.rtl ? root.edgeRight - off - w : root.edgeLeft + off;
    }
    function fromEnd(off, w) {
        return root.rtl ? root.edgeLeft + off : root.edgeRight - off - w;
    }
    // No corpo (layout final): espelho em torno do centro do painel.
    function bodyX(x, w) {
        return root.rtl ? root.implicitWidth - x - w : x;
    }

    QtObject {
        id: priv
        // Pedido do takeover mostrado agora ({rows, selected, selectionFile, doneFile}).
        property var request: null
        property bool applying: false
        property bool takeoverApplied: false
        property bool userMoved: false
        property string selPath: ""
    }

    // Depois da troca: o count da faixa precisa já ter a lista nova.
    onListChanged: Qt.callLater(root.resync)
    onMarkedIndexChanged: {
        if (!priv.userMoved && !priv.applying)
            Qt.callLater(root.resync);
    }

    // Fecha mesmo sem resposta (WALLPAPER_CLOSE_MS).
    Timer {
        id: closeFallback
        interval: Motion.TIMING.WALLPAPER_CLOSE_MS
        onTriggered: root.finishApply()
    }

    Connections {
        target: root.themesSvc
        // Própria: o `omarchy-theme-bg-set` saiu.
        function onWallpaperBusyChanged() {
            if (!priv.takeoverApplied && root.themesSvc && !root.themesSvc.wallpaperBusy)
                root.finishApply();
        }
        // Takeover: o link passou a apontar para o escolhido.
        function onPendingWallpaperChanged() {
            if (priv.takeoverApplied && root.themesSvc && root.themesSvc.pendingWallpaper === "")
                root.finishApply();
        }
    }

    // Outro pedido do script com a tela já aberta: troca as linhas.
    Connections {
        target: root.pickers
        function onPendingChanged() {
            if (!root.current || !root.pickers || !root.pickers.pending || root.pickers.pending === priv.request)
                return;
            priv.request = root.pickers.pending;
            priv.applying = false;
            priv.takeoverApplied = false;
            priv.userMoved = false;
            root.resync();
        }
    }

    // ---- Cabeçalho (x preso às bordas vivas) ----
    Item {
        id: header
        width: root.implicitWidth
        height: 44

        IlhaText {
            id: title
            x: root.fromStart(15, width)
            // Topo das maiúsculas em 21,5.
            y: 21.5 + root.capRatio * Math.round(title.size) - title.baselineOffset
            theme: root.theme
            size: 15.5
            weight: 600
            color: root.theme ? root.theme.alpha(root.theme.ink, 0.88) : "white"
            text: root.strings ? root.strings.t("wallpapers.title") : ""
        }

        IlhaText {
            id: themeName
            x: root.fromEnd(15, width)
            y: title.y + title.baselineOffset - themeName.baselineOffset
            width: Math.min(implicitWidth, 260)
            elide: Text.ElideRight
            theme: root.theme
            size: 12
            weight: 500
            color: root.theme ? root.theme.inkFaint : "gray"
            // O tema dos papéis mostrados (o do disco), senão o atual.
            text: root.themesSvc ? (root.themesSvc.wallpapersTheme || root.themesSvc.current) : ""
        }
    }

    // ---- Corpo (layout final, centrado) ----
    Item {
        id: body
        width: root.implicitWidth
        height: root.implicitHeight

        // Máscara única dos cantos de 12 px (todas as miniaturas usam).
        Rectangle {
            id: thumbMask
            width: 189
            height: 116
            radius: 12
            antialiasing: true
            visible: false
            layer.enabled: true
            layer.smooth: true
        }

        Carousel {
            id: strip
            x: root.inset
            // Centro da faixa em y 120.
            y: 120 - height / 2
            width: root.implicitWidth - 2 * root.inset
            height: 140
            count: root.list.length
            pitch: root.pitch
            itemWidth: 189
            itemHeight: 116
            dir: root.theme ? root.theme.dir : 1
            snapping: root.snapping
            reduceMotion: root.theme ? root.theme.reduceMotion : false
            delegate: thumbDelegate
            onActivated: i => root.activate(i)
            onMoved: priv.userMoved = true
            onIndexChanged: root.noteIndex()
        }

        IlhaText {
            x: (root.implicitWidth - width) / 2
            y: 120 - height / 2
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            opacity: root.ready && root.list.length === 0 ? 1 : 0
            text: root.strings ? root.strings.t("wallpapers.empty") : ""
        }

        // Rodapé: nome do arquivo de um lado; "3/7 · Enter para aplicar" do outro.
        IlhaText {
            id: fileName
            x: root.bodyX(16, width)
            y: 209 - height / 2
            width: Math.max(0, Math.min(implicitWidth, 600, root.implicitWidth - 32 - footGroup.width - 24))
            elide: Text.ElideRight
            theme: root.theme
            size: 12
            weight: 500
            color: root.theme ? root.theme.inkFaint : "gray"
            text: root.list[strip.index] ? root.list[strip.index].name : ""
        }

        Item {
            id: footGroup
            readonly property real gap: 10
            width: counter.width + gap + dot.width + gap + enterHint.width
            height: 20
            x: root.bodyX(root.implicitWidth - 16 - width, width)
            y: 209 - height / 2
            opacity: root.list.length > 0 ? 1 : 0

            // A ordem interna também espelha em RTL (o contador fica na ponta).
            IlhaText {
                id: counter
                x: root.rtl ? footGroup.width - width : 0
                y: (footGroup.height - height) / 2
                theme: root.theme
                size: 12
                weight: 500
                tnum: true
                color: root.theme ? root.theme.inkFaint : "gray"
                text: root.strings && root.list.length > 0
                    ? root.strings.t("common.counter").arg(root.digits(strip.index + 1)).arg(root.digits(root.list.length))
                    : ""
            }
            Rectangle {
                id: dot
                width: 2.5
                height: 2.5
                radius: 1.25
                antialiasing: true
                x: root.rtl ? footGroup.width - counter.width - footGroup.gap - width : counter.width + footGroup.gap
                y: (footGroup.height - height) / 2
                color: root.theme ? root.theme.alpha(root.theme.ink, 0.15) : "gray"
            }
            IlhaText {
                id: enterHint
                x: root.rtl ? 0 : footGroup.width - width
                y: (footGroup.height - height) / 2
                theme: root.theme
                size: 12
                weight: 500
                color: root.theme ? root.theme.inkFaint : "gray"
                text: root.strings ? root.strings.t("common.enterToApply") : ""
            }
        }
    }

    // ---- Uma miniatura ----
    Component {
        id: thumbDelegate

        Item {
            id: cell
            property int index: 0
            property real d: 0
            property bool selected: false
            readonly property var w: root.list[cell.index] || ({})
            readonly property real ad: Math.abs(cell.d)
            // Perto da faixa (ou já vista): carrega a imagem e a mantém.
            readonly property bool near: cell.ad <= strip.reach
            property bool seen: false
            onNearChanged: if (cell.near) cell.seen = true
            Component.onCompleted: if (cell.near) cell.seen = true
            readonly property string source: cell.w.thumb && root.themesSvc ? root.themesSvc.fileUrl(cell.w.thumb) : ""

            scale: cell.ad <= 1 ? 1 - 0.1 * cell.ad : Math.max(0.8, 0.9 - 0.1 * (cell.ad - 1))
            opacity: Math.max(0.4, 1 - 0.3 * cell.ad)
            Accessible.role: Accessible.ListItem
            Accessible.name: cell.w.name || ""
            Accessible.selected: cell.selected

            // Fundo quase preto enquanto a imagem carrega.
            Rectangle {
                anchors.fill: parent
                radius: 12
                antialiasing: true
                color: root.theme ? root.theme.mix(root.theme.surface, root.theme.ink, 0.02) : "black"
            }

            // Vídeo sem miniatura: bloco com o glifo de filme.
            Rectangle {
                anchors.fill: parent
                radius: 12
                antialiasing: true
                visible: cell.w.video === true && cell.source === ""
                color: root.theme ? root.theme.raised : "gray"
                Icon {
                    anchors.centerIn: parent
                    name: "movie"
                    size: 28
                    color: root.theme ? root.theme.inkMuted : "gray"
                }
            }

            Item {
                id: pic
                anchors.fill: parent
                visible: cell.source !== ""
                layer.enabled: cell.source !== ""
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: thumbMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                Image {
                    id: img
                    anchors.fill: parent
                    source: cell.near || cell.seen ? cell.source : ""
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(378, 232)
                    opacity: img.status === Image.Ready ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.theme ? root.theme.dur(Motion.FADE.IMAGE_IN) : 0
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            // Borda da escolhida: 2,25 px por dentro, em accent.
            Rectangle {
                anchors.fill: parent
                radius: 12
                antialiasing: true
                color: "transparent"
                border.width: 2.25
                border.color: root.theme ? root.theme.accent : "white"
                opacity: cell.selected ? 1 : 0
                Behavior on opacity {
                    enabled: !root.snapping
                    NumberAnimation {
                        duration: root.theme ? root.theme.dur(70) : 0
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Papel atual: bolinha de 6 px a 12 do canto de cima (espelhada em RTL).
            Rectangle {
                width: 6
                height: 6
                radius: 3
                antialiasing: true
                x: root.rtl ? 12 - 3 : cell.width - 12 - 3
                y: 12 - 3
                color: root.theme ? root.theme.accent : "white"
                opacity: cell.index === root.markedIndex ? 1 : 0
            }
        }
    }
}
