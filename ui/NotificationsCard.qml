pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
import "Motion.js" as Motion

// Cartão de notificações da Central (screens §5, amendments §12.1 e §12.2):
// cabeçalho "Notificações" + "Limpar" + o botão de Ajustes da Ilha, e a
// lista do StatusSvc: as
// da tela primeiro, depois o histórico de 24 h depois do clearedAt.
//
// Medidas (cartão 486 x 200, raio 21, fill card; coordenadas do cartão):
// - "Notificações" em x 15, topo das maiúsculas em 15 (12,5 / 500 inkMuted).
//   "Limpar" (12 accentInk) 10 depois do rótulo, só quando há linhas: chama
//   status.clearAll() (dismissAll do Omarchy + clearedAt = agora).
// - Ajustes da Ilha: CircleButton 26 no canto direito do cabeçalho (glifo 15),
//   secundário (hover do cartão ou foco). É a origem da página de ajustes;
//   Apps, Temas, Papéis e Energia não ficam aqui (já estão no seletor e na navegação).
// - Lista y 44..h − 10, recortada, sem barra. Linhas 458 x 48, vão 4, raio
//   12, fill raised. Ícone 28 em x 10; resumo 13,5 / 600 ink em x 48; corpo
//   12 inkMuted numa linha (sem corpo: o app); idade 11,5 inkFaint à direita
//   ("agora", "5 min", "2 h", "3 d"). Da tela: ponto accent de 6 antes da
//   idade e, no hover, o fechar de 22 (status.dismiss(resumo)).
//   A ListView começa 4 px antes e termina 4 px depois (topMargin /
//   bottomMargin), para o anel de foco da primeira e da última linha caber.
// - Vazio: "Nenhuma notificação", 13 inkMuted, topo das maiúsculas em 39.
// - RTL: tudo por âncoras (espelham com o LayoutMirroring herdado); os x
//   explícitos da faixa passam por mx().
//
// Teclado (a Central entrega o foco aqui ao descer da linha da Tela):
//   faixa [Limpar?, Ajustes da Ilha] e depois uma linha por notificação.
//   Esquerda/Direita andam na faixa pela posição visual;
//   Cima/Baixo entre a faixa e as linhas; Tab / Shift+Tab em ordem. Enter
//   ativa; Delete dispensa uma da tela; Enter na mais nova da tela chama
//   invokeLast e fecha a ilha. handleKey devolve false quando o foco sai pelo
//   topo (Cima na faixa) ou pelas pontas da ordem (Tab): a Central assume.
//
// flash(row): acha a primeira linha da tela com a mesma key (senão o mesmo
// app + resumo, senão qualquer linha), põe a lista nela e pulsa o fundo
// raised -> rowHover -> raised (FLASH 150 / 300 / 450); no modo teclado foca
// a linha. Se a linha ainda não chegou (live.json atrasado), tenta de novo
// quando as linhas mudarem, por até 2 s.
Item {
    id: root

    property var island: null
    property Theme theme: null
    property var strings: null
    property bool keyboardMode: false
    HoverHandler { id: cardHover }
    // Opacidade do botão Ajustes (origem da J). Anéis somem com subpágina aberta.
    property real settingsOpacity: 1
    property bool ringsShown: true

    readonly property var status: root.island ? root.island.status : null
    readonly property var rows: root.status && root.status.visibleRows ? root.status.visibleRows : []
    // O botão Ajustes da Ilha (a Central mede o retângulo de origem da J).
    readonly property Item settingsButton: settingsBtn
    readonly property bool hasFocus: priv.focus !== ""

    signal openSettings()
    signal closeRequested()

    implicitWidth: 486
    implicitHeight: 200

    // ---- Foco do teclado ----

    // Foca a primeira notificação; sem linhas, o primeiro item da faixa.
    function focusFirstRow() {
        if (root.rows.length > 0)
            root.focusRowAt(0);
        else
            root.focusStrip(-1);
    }

    // Foca o item da faixa mais perto de x (coordenadas do cartão); x < 0 = o primeiro.
    function focusStrip(x) {
        const ids = root.stripIds();
        let best = ids[0];
        if (x >= 0) {
            let bestD = Infinity;
            for (let i = 0; i < ids.length; i++) {
                const d = Math.abs(root.centerXOf(ids[i]) - x);
                if (d < bestD) {
                    bestD = d;
                    best = ids[i];
                }
            }
        }
        priv.focus = best;
        priv.lastStrip = best;
        return true;
    }

    // Foca um atalho pelo id ("settings", "launcher", …); false se não existe.
    function focusShortcut(id) {
        if (root.stripIds().indexOf(id) === -1)
            return false;
        priv.focus = id;
        priv.lastStrip = id;
        return true;
    }

    function clearFocus() {
        priv.focus = "";
    }

    // Centro x do item focado (coordenadas do cartão), para a Central subir no lugar certo.
    function focusX() {
        if (priv.focus === "row" || priv.focus === "")
            return root.width / 2;
        return root.centerXOf(priv.focus);
    }

    function handleKey(event) {
        if (priv.focus === "")
            return false;
        const k = event.key;
        const mods = event.modifiers || 0;
        if (mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        const onRow = priv.focus === "row";
        switch (k) {
        case Qt.Key_Left:
        case Qt.Key_Right:
            if (!onRow)
                root.moveStrip(k === Qt.Key_Right ? 1 : -1);
            return true;
        case Qt.Key_Down:
            if (!onRow) {
                if (root.rows.length > 0)
                    root.focusRowAt(0);
            } else if (priv.focusRow < root.rows.length - 1) {
                root.focusRowAt(priv.focusRow + 1);
            }
            return true;
        case Qt.Key_Up:
            if (!onRow)
                return false;
            if (priv.focusRow > 0)
                root.focusRowAt(priv.focusRow - 1);
            else
                root.focusStrip(priv.lastStrip !== "" ? root.centerXOf(priv.lastStrip) : -1);
            return true;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            return root.stepOrder(k === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1);
        case Qt.Key_PageDown:
        case Qt.Key_End:
            if (root.rows.length > 0)
                root.focusRowAt(root.rows.length - 1);
            return true;
        case Qt.Key_PageUp:
        case Qt.Key_Home:
            if (root.rows.length > 0)
                root.focusRowAt(0);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.activate(priv.focus, k === Qt.Key_Space);
            return true;
        case Qt.Key_Delete:
            if (onRow) {
                const r = root.rows[priv.focusRow];
                if (r && r.live && root.status)
                    root.status.dismiss(r.summary);
            }
            return true;
        default:
            return false;
        }
    }

    // Destaque de uma linha (amendments §12.2).
    function flash(row) {
        const want = row || ({});
        const i = root.findRow(want);
        if (i < 0) {
            priv.pendingFlash = want;
            priv.pendingAt = Date.now();
            return;
        }
        priv.pendingFlash = null;
        list.positionViewAtIndex(i, ListView.Beginning);
        priv.flashIndex = i;
        priv.flashLevel = 0;
        flashAnim.restart();
        if (root.keyboardMode) {
            priv.focus = "row";
            priv.focusRow = i;
        }
    }

    // ---- Auxiliares ----

    function t(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    function ms(v) {
        return root.theme ? root.theme.dur(v) : 0;
    }

    // x calculado em LTR -> x na direção do idioma (RTL: espelhado no cartão).
    function mx(x, w) {
        return root.theme && root.theme.rtl ? root.width - x - w : x;
    }

    function stripIds() {
        return root.rows.length > 0 ? ["clear", "settings"] : ["settings"];
    }

    function stripItem(id) {
        if (id === "clear")
            return clearHit;
        if (id === "settings")
            return settingsBtn;
        return null;
    }

    function centerXOf(id) {
        const it = root.stripItem(id);
        if (!it)
            return root.width / 2;
        return it.mapToItem(root, it.width / 2, 0).x;
    }

    // Anda na faixa pela posição VISUAL (dir +1 = para a direita da tela).
    function moveStrip(dir) {
        const ids = root.stripIds();
        const cur = root.centerXOf(priv.focus);
        let best = "", bestD = Infinity;
        for (let i = 0; i < ids.length; i++) {
            const d = (root.centerXOf(ids[i]) - cur) * dir;
            if (d > 1 && d < bestD) {
                bestD = d;
                best = ids[i];
            }
        }
        if (best !== "") {
            priv.focus = best;
            priv.lastStrip = best;
        }
    }

    // Ordem do Tab: a faixa (ordem de leitura) e depois as linhas. false nas pontas.
    function stepOrder(step) {
        const ids = root.stripIds();
        const order = ids.concat(root.rows.map((r, i) => "row:" + i));
        const cur = priv.focus === "row" ? "row:" + priv.focusRow : priv.focus;
        const at = order.indexOf(cur);
        const next = at + step;
        if (at < 0 || next < 0 || next >= order.length)
            return false;
        const id = order[next];
        if (id.indexOf("row:") === 0) {
            root.focusRowAt(Number(id.slice(4)));
        } else {
            priv.focus = id;
            priv.lastStrip = id;
        }
        return true;
    }

    function focusRowAt(i) {
        const n = root.rows.length;
        if (n === 0)
            return;
        const at = Math.max(0, Math.min(n - 1, i));
        priv.focus = "row";
        priv.focusRow = at;
        list.positionViewAtIndex(at, ListView.Contain);
    }

    function activate(id, space) {
        switch (id) {
        case "clear":
            if (root.status)
                root.status.clearAll();
            // "Limpar" some com as linhas: o foco vai para o primeiro atalho.
            priv.focus = "settings";
            priv.lastStrip = "settings";
            break;
        case "settings":
            root.openSettings();
            break;
        case "row":
            if (!space && priv.focusRow === 0)
                root.invokeNewest();
            break;
        default:
            break;
        }
    }

    // A mais nova da tela é a linha 0 (live primeiro, a mais nova antes).
    function invokeNewest() {
        const r = root.rows[0];
        if (!r || !r.live || !root.status)
            return;
        root.status.invokeLast();
        root.closeRequested();
    }

    function findRow(want) {
        const key = String(want.key || ""), app = String(want.app || ""), summary = String(want.summary || "");
        const list = root.rows;
        const same = r => (key !== "" && String(r.key) === key);
        const alike = r => summary !== "" && String(r.summary) === summary && (app === "" || String(r.app) === app);
        const passes = [r => r.live && same(r), r => r.live && alike(r), r => same(r), r => alike(r)];
        for (let p = 0; p < passes.length; p++) {
            for (let i = 0; i < list.length; i++) {
                if (passes[p](list[i]))
                    return i;
            }
        }
        return -1;
    }

    // Imagem de uma linha: a do remetente (image://qsimage/…), um caminho
    // absoluto, um nome do tema de ícones, ou o ícone do app (DesktopEntries).
    // "" quando nada serve (o cartão mostra o glifo do Omarchy ou a inicial).
    function imageFor(r) {
        const v = String(r.icon || "");
        if (/^image:\/\/qsimage\/[0-9]+\/[0-9]+$/.test(v) || v.indexOf("file://") === 0)
            return v;
        if (v.charAt(0) === "/")
            return "file://" + v;
        if (/^[A-Za-z0-9_][A-Za-z0-9_.-]{0,255}$/.test(v)) {
            const themed = Quickshell.iconPath(v, true);
            if (themed)
                return themed;
        }
        const app = String(r.app || "");
        if (app !== "") {
            const entry = DesktopEntries.heuristicLookup(app);
            const name = entry ? String(entry.icon || "") : "";
            if (name.charAt(0) === "/")
                return "file://" + name;
            if (name !== "") {
                const found = Quickshell.iconPath(name, true);
                if (found)
                    return found;
            }
        }
        return "";
    }

    // Idade curta ("agora", "5 min", "2 h", "3 d") com os algarismos do idioma.
    // island.now (minuto) é a dependência que atualiza.
    function ageText(ts) {
        let at = Number(ts) || 0;
        if (at <= 0)
            return "";
        if (at < 1e12)
            at *= 1000;
        const nowMs = Math.max(root.island && root.island.now ? root.island.now.getTime() : 0, Date.now());
        const mins = Math.floor((nowMs - at) / 60000);
        const f = Commons.I18n.formatNumber;
        if (mins < 1)
            return root.t("cc.timeNow");
        if (mins < 60)
            return root.t("cc.timeMinutes").arg(f(mins));
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return root.t("cc.timeHours").arg(f(hours));
        return root.t("cc.timeDays").arg(f(Math.floor(hours / 24)));
    }

    function initial(r) {
        const s = String(r.app || r.summary || "").trim();
        return s !== "" ? s.charAt(0).toLocaleUpperCase() : "";
    }

    onRowsChanged: {
        if (priv.focus === "row" && priv.focusRow >= root.rows.length) {
            if (root.rows.length > 0)
                priv.focusRow = root.rows.length - 1;
            else
                root.focusStrip(-1);
        }
        if (priv.focus === "clear" && root.rows.length === 0)
            priv.focus = "settings";
        if (priv.pendingFlash && Date.now() - priv.pendingAt < 2000) {
            const want = priv.pendingFlash;
            Qt.callLater(() => {
                if (priv.pendingFlash === want)
                    root.flash(want);
            });
        } else {
            priv.pendingFlash = null;
        }
    }

    QtObject {
        id: priv
        // "" | "clear" | "settings" | "row"
        property string focus: ""
        property int focusRow: 0
        property string lastStrip: ""
        // Destaque (flash)
        property int flashIndex: -1
        property real flashLevel: 0
        property var pendingFlash: null
        property real pendingAt: 0
    }

    SequentialAnimation {
        id: flashAnim
        NumberAnimation {
            target: priv
            property: "flashLevel"
            to: 1
            duration: root.ms(Motion.FADE.FLASH.in)
            easing.type: Easing.OutCubic
        }
        // A espera é um intervalo de destaque, não movimento: fica mesmo com reduzir movimento.
        PauseAnimation {
            duration: Motion.FADE.FLASH.hold
        }
        NumberAnimation {
            target: priv
            property: "flashLevel"
            to: 0
            duration: root.ms(Motion.FADE.FLASH.out)
            easing.type: Easing.OutCubic
        }
        onFinished: priv.flashIndex = -1
    }


    Rectangle {
        anchors.fill: parent
        radius: 21
        color: root.theme ? root.theme.card : "transparent"
    }

    // ---- Cabeçalho ----
    IlhaText {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: 15
        y: 15 - (label.baselineOffset - 0.7275 * label.font.pixelSize)
        theme: root.theme
        size: 12.5
        weight: 500
        color: root.theme ? root.theme.inkMuted : "gray"
        text: root.t("cc.notifications")
    }

    IlhaText {
        id: clearText
        anchors.left: label.right
        anchors.leftMargin: 10
        anchors.baseline: label.baseline
        visible: root.rows.length > 0
        theme: root.theme
        size: 12
        weight: 500
        color: root.theme ? (clearArea.containsMouse ? root.theme.ink : root.theme.accentInk) : "white"
        text: root.t("common.clear")
        Behavior on color {
            ColorAnimation { duration: root.ms(Motion.FADE.HOVER) }
        }
    }
    // Alvo do clique e do anel do "Limpar" (um pouco maior que o texto).
    Item {
        id: clearHit
        anchors.fill: clearText
        anchors.margins: -4
        visible: clearText.visible
        Accessible.role: Accessible.Button
        Accessible.name: clearText.text

        MouseArea {
            id: clearArea
            anchors.fill: parent
            anchors.margins: -2
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.status) root.status.clearAll()
        }
        FocusRing {
            theme: root.theme
            shown: root.keyboardMode && root.ringsShown && priv.focus === "clear"
            itemRadius: 6
        }
    }

    // Ajustes da Ilha, à direita do cabeçalho. Secundário: hover do cartão ou foco.
    // Apps, Temas, Papéis e Energia já estão no seletor e na cápsula de navegação.
    CircleButton {
        id: settingsBtn
        x: root.mx(root.width - 12 - 26, 26)
        readonly property string host: root.island && root.island.glyphs ? root.island.glyphs.glyph("setup") : ""
        y: 8
        opacity: root.settingsOpacity
        veil: (cardHover.hovered || settingsBtn.hovered || (root.keyboardMode && priv.focus === "settings")) ? 1 : 0
        theme: root.theme
        icon: settingsBtn.host === "" ? "settings" : ""
        glyph: settingsBtn.host
        size: 26
        glyphSize: 15
        fill: "transparent"
        hoverFill: root.theme ? root.theme.rowHover : "transparent"
        glyphColor: root.theme ? root.theme.inkFaint : "gray"
        hoverGlyphColor: root.theme ? root.theme.ink : "white"
        focused: root.keyboardMode && root.ringsShown && priv.focus === "settings"
        accessibleName: root.t("cc.ilhaSettings")
        onClicked: root.openSettings()
    }

    // ---- Vazio ----
    IlhaText {
        id: empty
        anchors.left: parent.left
        anchors.leftMargin: 15
        y: 39 - (empty.baselineOffset - 0.7275 * empty.font.pixelSize)
        visible: root.rows.length === 0
        theme: root.theme
        size: 13
        weight: 400
        color: root.theme ? root.theme.inkMuted : "gray"
        text: root.t("cc.noNotifications")
    }

    // ---- Lista ----
    ListView {
        id: list
        x: 10
        y: 40
        width: 466
        height: root.height - 40 - 6
        topMargin: 4
        bottomMargin: 4
        clip: true
        spacing: 4
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        interactive: list.contentHeight > list.height - 8
        highlightMoveDuration: 0

        delegate: Item {
            id: row
            required property var modelData
            required property int index

            readonly property bool live: !!row.modelData.live
            // Só a mais nova da tela responde ao clique (invokeLast).
            readonly property bool actionable: row.live && row.index === 0
            readonly property string second: String(row.modelData.body || "") !== "" ? String(row.modelData.body)
                : (String(row.modelData.app || "") !== String(row.modelData.summary || "") ? String(row.modelData.app || "") : "")
            readonly property bool pointed: rowHover.hovered
            // Espaço à direita do texto: a idade (e o ponto) ou o fechar, o que for maior.
            readonly property real reserve: Math.max(12 + age.implicitWidth + (row.live ? 12 : 0), 10 + 22) + 8

            width: 466
            height: 48

            Rectangle {
                id: plate
                x: 4
                width: 458
                height: 48
                radius: 12
                color: !root.theme ? "transparent" : (row.actionable && row.pointed ? root.theme.rowHover : root.theme.raised)
                Behavior on color {
                    ColorAnimation { duration: root.ms(Motion.FADE.HOVER) }
                }

                Accessible.role: Accessible.ListItem
                Accessible.name: String(row.modelData.summary || "")
                Accessible.description: row.second

                // Pulso do flash: raised -> rowHover -> raised.
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.theme ? root.theme.rowHover : "transparent"
                    opacity: priv.flashIndex === row.index ? priv.flashLevel : 0
                }

                HoverHandler {
                    id: rowHover
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: row.actionable
                    cursorShape: row.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.invokeNewest()
                }

                // Ícone: imagem, glifo do Omarchy ou a inicial.
                Item {
                    id: thumb
                    width: 28
                    height: 28
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property string src: root.imageFor(row.modelData)
                    readonly property bool pictured: pic.status === Image.Ready && thumb.src !== ""
                    readonly property string raw: String(row.modelData.rawGlyph || "")

                    Image {
                        id: pic
                        anchors.fill: parent
                        source: thumb.src
                        sourceSize.width: 56
                        sourceSize.height: 56
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                        opacity: thumb.pictured ? 1 : 0
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: root.theme ? root.theme.rowIcon : "gray"
                        opacity: thumb.pictured ? 0 : 1

                        IlhaText {
                            anchors.centerIn: parent
                            theme: root.theme
                            size: thumb.raw !== "" ? 15 : 13
                            weight: 600
                            color: root.theme ? root.theme.ink : "white"
                            text: thumb.raw !== "" ? thumb.raw : root.initial(row.modelData)
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: thumb.raw === "" && root.initial(row.modelData) === ""
                            name: "notifications"
                            size: 15
                            color: root.theme ? root.theme.inkMuted : "gray"
                        }
                    }
                }

                Column {
                    id: lines
                    anchors.left: parent.left
                    anchors.leftMargin: 48
                    anchors.right: parent.right
                    anchors.rightMargin: row.reserve
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    IlhaText {
                        id: summary
                        width: lines.width
                        theme: root.theme
                        size: 13.5
                        weight: 600
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        text: String(row.modelData.summary || "")
                    }
                    IlhaText {
                        width: lines.width
                        visible: row.second !== ""
                        theme: root.theme
                        size: 12
                        weight: 400
                        color: root.theme ? root.theme.inkMuted : "gray"
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        text: row.second
                    }
                }

                // Idade na linha do resumo (mesma linha de base).
                IlhaText {
                    id: age
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    y: lines.y + summary.y + summary.baselineOffset - age.baselineOffset
                    theme: root.theme
                    size: 11.5
                    weight: 400
                    tnum: true
                    color: root.theme ? root.theme.inkFaint : "gray"
                    text: root.ageText(row.modelData.ts)
                    opacity: row.live && row.pointed ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation { duration: root.ms(Motion.FADE.HOVER); easing.type: Easing.OutCubic }
                    }
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    visible: row.live
                    anchors.right: age.left
                    anchors.rightMargin: 6
                    y: age.y + age.baselineOffset - 0.3638 * age.font.pixelSize - 3
                    color: root.theme ? root.theme.accent : "white"
                    opacity: age.opacity
                }

                CircleButton {
                    id: dismissBtn
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: row.live && row.pointed ? 1 : 0
                    enabled: dismissBtn.opacity > 0.5
                    theme: root.theme
                    icon: "close"
                    size: 22
                    glyphSize: 14
                    fill: "transparent"
                    hoverFill: root.theme ? root.theme.pressOverlay : "transparent"
                    glyphColor: root.theme ? root.theme.inkMuted : "gray"
                    hoverGlyphColor: root.theme ? root.theme.ink : "white"
                    accessibleName: root.t("cc.dismiss")
                    onClicked: if (root.status) root.status.dismiss(row.modelData.summary)
                    Behavior on opacity {
                        NumberAnimation { duration: root.ms(Motion.FADE.HOVER); easing.type: Easing.OutCubic }
                    }
                }

                FocusRing {
                    theme: root.theme
                    shown: root.keyboardMode && root.ringsShown && priv.focus === "row" && priv.focusRow === row.index
                    itemRadius: 12
                }
            }
        }
    }
}
