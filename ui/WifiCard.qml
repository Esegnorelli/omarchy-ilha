pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import qs.Commons as Commons
import "Motion.js" as Motion

// Popover de Wi-Fi da Central (screens §6 e o cartão 5b do estudo do
// vídeo). Dono: Agent D. A Central desenha o recipiente (transformação K,
// cor, dimmer, clique fora); este Item é o conteúdo do cartão, preso ao
// canto de cima e recortado por ele.
//
// Coordenadas do cartão (largura 470):
// - Cabeçalho: voltar 24 centrado em (26, 34); título 18.5/600 em x 52;
//   interruptor 43 x 24 a 14 da direita, centrado em y 34.
//   O voltar é secundário (hover do cabeçalho ou do botão).
// - Bloco de estado em y 68:
//   rede conectada  442 x 69, raio 12.5, círculo accent 41 com wifi,
//                   SSID 16/600, "Conectado · WPA2 · sinal de 60%",
//                   pílula "Desconectar" (neutra) a 12 da direita;
//   cabo            a mesma linha com lan e "Cabo · 192.168.x.x", sem pílula;
//   desligado / sem rádio / sem conexão: faixa raised de 42 com o texto 13.
// - "Redes" com o centro a blockBottom + 20 (cap top 152 no vídeo) e
//   "● Procurando" à direita (fim a 15 da borda) durante a primeira
//   varredura da abertura.
// - Linhas de rede a partir de blockBottom + 42: 442 x 48, passo 52.5, raio
//   10.5, círculo 35 rowIcon com as barras, nome 15.5/600, "Protegida" /
//   "Aberta" 12, pílula "Conectar" (accentSoft). Até 5 visíveis; o resto
//   rola. Varredura terminada sem nada: "Nenhuma rede encontrada" (30).
// - Rede protegida e desconhecida: a linha cresce para 96 em 160 ms OutCubic
//   e mostra o campo de senha (418 x 34, raio 10, card) com "Conectar"
//   dentro. Senha errada: "Senha incorreta" em danger e o campo limpo.
// - Rede conhecida: um × de 22 aparece no hover (ou com o foco do teclado)
//   ao lado da pílula e esquece a rede.
// - Rede corporativa (802.1X) desconhecida: fecha a ilha e abre o nmtui
//   (pede usuário e senha), em vez de um campo que não bastaria.
//
// cardH = blockBottom + 34 + (n > 0 ? 8 + linhas : (scanDone ? 38 : 0)) + 12,
// linhas = min(n, 5)·52.5 − 4.5 (+ 48 com a senha aberta). Com o rádio
// desligado: blockBottom + 12. O popover não muda os 513 da Central, então
// o cartão nunca passa de 513 − 42: as linhas visíveis diminuem antes.
//
// Teclado (handleKey): ↑/↓ (Home/End, PgUp/PgDn) andam entre a rede
// conectada e as linhas; Enter conecta / desconecta / abre a senha; Espaço
// liga e desliga o rádio; Delete esquece a rede conhecida; Esc fecha a senha
// e depois volta. Os anéis de foco só aparecem no modo teclado.
//
// Atividade só entre opened() e closed(): a varredura (net.scanning) e a
// sincronização da lista.
Item {
    id: root

    property var island: null
    property Theme theme: null
    property var strings: null
    property bool keyboardMode: false
    property real maxHeight: 900

    signal back()
    // Pede o foco do campo de senha da linha (clique no corpo, Enter).
    signal fieldFocusRequested(string ssid)

    readonly property var net: root.island ? root.island.net : null

    // ---- Estado da tela ----
    // "wifi" | "wired" | "off" | "unavailable" | "idle"
    readonly property string block: !root.net ? "unavailable"
        : root.net.connected ? "wifi"
        : root.net.wired ? "wired"
        : !root.net.wifiAvailable ? "unavailable"
        : !root.net.wifiEnabled ? "off"
        : "idle"
    readonly property real blockH: root.block === "wifi" || root.block === "wired" ? 69 : 42
    readonly property real blockBottom: 68 + root.blockH
    readonly property bool showList: !!root.net && root.net.wifiAvailable && root.net.wifiEnabled
    readonly property int count: netModel.count
    readonly property bool pwOpen: priv.passwordSsid !== "" && root.indexOfSsid(priv.passwordSsid) >= 0
    readonly property real pwExtra: root.pwOpen ? 48 : 0
    readonly property real limitH: Math.min(root.maxHeight, (root.theme ? root.theme.px.CC_H : 513) - 42)
    readonly property int visibleRows: root.count <= 0 ? 0
        : Math.max(1, Math.min(root.count, 5, Math.floor((root.limitH - (root.blockBottom + 34 + 8 + 12 + root.pwExtra) + 4.5) / 52.5)))
    readonly property real listH: root.visibleRows > 0 ? root.visibleRows * 52.5 - 4.5 + root.pwExtra : 0

    width: 470
    implicitWidth: 470
    implicitHeight: !root.showList ? root.blockBottom + 12
        : root.blockBottom + 34 + (root.count > 0 ? 8 + root.listH : (root.net.scanDone ? 38 : 0)) + 12

    LayoutMirroring.enabled: !!root.theme && root.theme.rtl
    LayoutMirroring.childrenInherit: true

    // ---- Contrato do cartão ----

    function opened() {
        priv.snapping = true;
        priv.live = true;
        priv.passwordSsid = "";
        root.syncList();
        const keys = root.focusKeys();
        priv.selAuto = true;
        priv.selKey = keys.length > 0 ? keys[0] : "";
        list.positionViewAtBeginning();
        if (root.net)
            root.net.scanning = true;
        Qt.callLater(() => priv.snapping = false);
    }

    function closed() {
        if (root.net)
            root.net.scanning = false;
        priv.live = false;
        root.closePassword();
        priv.selKey = "";
    }

    function handleKey(event) {
        if (!root.net)
            return false;
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        switch (event.key) {
        case Qt.Key_Up:
            root.moveSel(-1);
            return true;
        case Qt.Key_Down:
            root.moveSel(1);
            return true;
        case Qt.Key_Home:
            root.moveSel(-1000);
            return true;
        case Qt.Key_End:
            root.moveSel(1000);
            return true;
        case Qt.Key_PageUp:
            root.moveSel(-5);
            return true;
        case Qt.Key_PageDown:
            root.moveSel(5);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            // Enter segurado não desconecta nem reconecta em rajada.
            if (!event.isAutoRepeat)
                root.activateSel();
            return true;
        case Qt.Key_Space:
            if (!event.isAutoRepeat)
                root.toggleRadio();
            return true;
        case Qt.Key_Delete:
            root.forgetSel();
            return true;
        }
        return false;
    }

    function handleEscape() {
        if (priv.passwordSsid !== "") {
            root.closePassword();
            return true;
        }
        root.back();
        return true;
    }

    // ---- Lista (ListModel com diferença por SSID: as linhas vivas mantêm
    // hover, campo de senha e posição quando o rádio atualiza o sinal) ----

    function indexOfSsid(ssid) {
        for (let i = 0; i < netModel.count; i++)
            if (netModel.get(i).ssid === ssid)
                return i;
        return -1;
    }

    function syncList() {
        const all = root.net && root.showList ? root.net.networks : [];
        const rows = all.filter(r => !r.active);
        const keys = rows.map(r => r.ssid);
        for (let i = netModel.count - 1; i >= 0; i--)
            if (keys.indexOf(netModel.get(i).ssid) < 0)
                netModel.remove(i);
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            const item = { ssid: r.ssid, signal: r.signal, secured: r.secured, known: r.known, enterprise: r.enterprise };
            let j = -1;
            for (let k = i; k < netModel.count; k++) {
                if (netModel.get(k).ssid === r.ssid) {
                    j = k;
                    break;
                }
            }
            if (j < 0) {
                netModel.insert(i, item);
                continue;
            }
            if (j !== i)
                netModel.move(j, i, 1);
            const cur = netModel.get(i);
            for (const f in item)
                if (cur[f] !== item[f])
                    netModel.setProperty(i, f, item[f]);
        }
        if (priv.passwordSsid !== "" && keys.indexOf(priv.passwordSsid) < 0)
            root.closePassword();
        // A escolha do usuário segue a mesma rede quando a ordem muda. Antes
        // de ele mexer, a seleção fica no topo (as redes chegam depois da
        // abertura, quando o scanner liga, e a primeira a chegar não é a
        // primeira da lista).
        const fk = root.focusKeys();
        if (priv.selAuto || fk.indexOf(priv.selKey) < 0)
            priv.selKey = fk.length > 0 ? fk[0] : "";
        Qt.callLater(root.updateSelRow);
    }

    // Ordem do foco do teclado: a rede conectada, depois as linhas.
    function focusKeys() {
        const keys = [];
        if (root.block === "wifi")
            keys.push("conn");
        for (let i = 0; i < netModel.count; i++)
            keys.push(netModel.get(i).ssid);
        return keys;
    }

    function moveSel(delta) {
        const keys = root.focusKeys();
        if (keys.length === 0) {
            priv.selKey = "";
            return;
        }
        let i = keys.indexOf(priv.selKey);
        if (i < 0)
            i = delta > 0 ? -1 : keys.length;
        i = Math.max(0, Math.min(keys.length - 1, i + delta));
        if (priv.passwordSsid !== "" && keys[i] !== priv.passwordSsid)
            root.closePassword();
        priv.selAuto = false;
        priv.selKey = keys[i];
        root.ensureVisible(keys[i]);
    }

    function ensureVisible(key) {
        const i = root.indexOfSsid(key);
        if (i >= 0)
            list.positionViewAtIndex(i, ListView.Contain);
        else if (key === "conn")
            list.positionViewAtBeginning();
    }

    // A linha selecionada (para o anel desenhado fora do recorte da lista).
    function updateSelRow() {
        const i = root.indexOfSsid(priv.selKey);
        root.selRow = i >= 0 ? list.itemAtIndex(i) : null;
    }

    function rowFor(ssid) {
        const i = root.indexOfSsid(ssid);
        return i >= 0 ? netModel.get(i) : null;
    }

    function activateSel() {
        const key = priv.selKey;
        if (key === "conn") {
            if (root.net && !root.net.busy)
                root.net.disconnect();
            return;
        }
        if (key !== "")
            root.activateRow(key);
    }

    // Ação principal de uma linha (corpo, pílula ou Enter).
    function activateRow(ssid) {
        if (!root.net)
            return;
        const r = root.rowFor(ssid);
        if (!r)
            return;
        priv.selAuto = false;
        priv.selKey = ssid;
        if (priv.passwordSsid === ssid) {
            root.fieldFocusRequested(ssid);
            return;
        }
        if (root.net.busy)
            return;
        if (r.secured && !r.known && r.enterprise) {
            root.closePassword();
            if (root.island)
                root.island.close();
            root.net.connectInTerminal(ssid);
            return;
        }
        if (r.secured && !r.known) {
            root.openPassword(ssid);
            return;
        }
        root.closePassword();
        root.net.connect({ ssid: ssid }, "");
    }

    function submitPassword(ssid, text) {
        if (!root.net || root.net.busy || String(text || "").length === 0)
            return;
        root.net.connect({ ssid: ssid }, String(text));
    }

    function forgetSel() {
        const r = root.rowFor(priv.selKey);
        if (r && r.known && root.net && !root.net.busy)
            root.net.forget({ ssid: r.ssid });
    }

    function toggleRadio() {
        if (root.net && root.net.wifiAvailable)
            root.net.setWifiEnabled(!root.net.wifiEnabled);
    }

    function openPassword(ssid) {
        if (priv.passwordSsid === ssid)
            return;
        if (!priv.restoreItem) {
            const f = root.Window.activeFocusItem;
            if (f && !root.owns(f))
                priv.restoreItem = f;
        }
        priv.passwordSsid = ssid;
        priv.selAuto = false;
        priv.selKey = ssid;
        root.ensureVisible(ssid);
        revealTimer.restart();
    }

    // Fecha o campo e devolve o foco a quem tinha antes (o catcher de teclas
    // da janela), mas só se o foco ainda estiver aqui dentro.
    function closePassword() {
        if (priv.passwordSsid === "")
            return;
        priv.passwordSsid = "";
        const back = priv.restoreItem;
        priv.restoreItem = null;
        const cur = root.Window.activeFocusItem;
        // O popover fechado pelo mouse desliga o campo antes daqui: o foco já
        // caiu no item raiz da janela e também precisa voltar.
        if (back && (!cur || cur === root.Window.contentItem || root.owns(cur)))
            back.forceActiveFocus();
    }

    function owns(item) {
        for (let p = item; p; p = p.parent)
            if (p === root)
                return true;
        return false;
    }

    function percent(v) {
        return Commons.I18n.formatNumber(Math.max(0, Math.round(v)));
    }

    function t(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    QtObject {
        id: priv
        property bool live: false
        property bool snapping: false
        property string passwordSsid: ""
        property string selKey: ""            // "conn" | SSID | ""
        property bool selAuto: true           // seleção ainda não escolhida pelo usuário
        property Item restoreItem: null
    }

    ListModel {
        id: netModel
    }

    Connections {
        target: root.net
        function onNetworksChanged() {
            if (priv.live)
                root.syncList();
        }
        function onLastErrorChanged() {
            // Senha errada: a linha volta a pedir a senha.
            if (priv.live && root.net.lastError === "wrong-password" && root.net.errorSsid !== "")
                root.openPassword(root.net.errorSsid);
        }
        function onBusyChanged() {
            // Conectou: a linha sobe para o bloco da rede conectada.
            if (priv.live && !root.net.busy && root.net.lastError === "" && root.net.connected && root.net.ssid === priv.passwordSsid)
                root.closePassword();
        }
    }

    property Item selRow: null
    Connections {
        target: priv
        function onSelKeyChanged() {
            root.updateSelRow();
        }
    }

    onShowListChanged: if (priv.live) root.syncList()
    onBlockChanged: if (priv.live) root.syncList()

    // Depois da animação da linha, garante a linha aberta inteira à vista.
    Timer {
        id: revealTimer
        interval: Motion.FADE.CARD_HEIGHT + 20
        onTriggered: root.ensureVisible(priv.passwordSsid)
    }

    // Alturas que animam junto com a linha e com a Central (160 ms).
    property real blockBottomShown: root.blockBottom
    Behavior on blockBottomShown {
        enabled: !priv.snapping
        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
    }
    property real listShownH: root.listH
    Behavior on listShownH {
        enabled: !priv.snapping
        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
    }

    // ---- Cabeçalho ----

    // Cabeçalho: o hover dele mostra o chevron de voltar (secundário; Esc, Alt+←, a navegação e o toque fora também voltam).
    Item {
        id: headerBand
        anchors.left: parent.left
        anchors.right: parent.right
        y: 0
        height: 60
        HoverHandler { id: headerHover }
    }
    CircleButton {
        id: backBtn
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 22
        theme: root.theme
        icon: "chevron_left"
        flip: !!root.theme && root.theme.rtl
        size: 24
        glyphSize: 14
        accessibleName: root.t("common.back")
        veil: (headerHover.hovered || backBtn.hovered) ? 1 : 0
        onClicked: root.back()
    }

    IlhaText {
        anchors.left: parent.left
        anchors.leftMargin: 52
        anchors.right: wifiSwitch.left
        anchors.rightMargin: 12
        y: 33 - height / 2
        theme: root.theme
        size: 18.5
        weight: 600
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("wifi.title")
    }

    IlhaSwitch {
        id: wifiSwitch
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 22
        theme: root.theme
        enabled: !!root.net && root.net.wifiAvailable && root.net.wifiHardwareEnabled
        checked: !!root.net && root.net.wifiEnabled
        accessibleName: root.t("wifi.title")
        onToggled: root.toggleRadio()
    }

    // ---- Bloco de estado ----

    ListRow {
        id: connRow
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 68
        width: 442
        opacity: root.block === "wifi" ? 1 : 0
        enabled: root.block === "wifi"
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
        theme: root.theme
        rowHeight: 69
        circleSize: 41
        circleInset: 10.5
        iconSize: 18
        radius: 12.5
        icon: "wifi"
        iconFilled: true
        iconAccent: true
        label: root.net && root.net.ssid !== "" ? root.net.ssid : root.t("cc.wifi")
        labelSize: 16
        sublabel: {
            if (!root.net)
                return "";
            const sec = root.net.security !== "" ? root.net.security : root.t(root.net.securityOpen ? "wifi.open" : "wifi.secured");
            return root.t("wifi.connectedDetail").arg(sec).arg(root.percent(root.net.signal));
        }
        sublabelSize: 12.5
        pillText: root.net && root.net.busyKind === "disconnect" ? "" : root.t("common.disconnect")
        pillStyle: "neutral"
        pillInset: 12
        focused: root.keyboardMode && priv.selKey === "conn"
        onPillClicked: if (root.net && !root.net.busy) root.net.disconnect()
    }

    ListRow {
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 68
        width: 442
        opacity: root.block === "wired" ? 1 : 0
        enabled: false
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
        theme: root.theme
        rowHeight: 69
        circleSize: 41
        circleInset: 10.5
        iconSize: 18
        radius: 12.5
        icon: "lan"
        iconAccent: true
        label: root.t("cc.ethernet")
        labelSize: 16
        sublabel: root.net ? root.t("wifi.wired").arg(root.net.wiredIp !== "" ? root.net.wiredIp : root.net.wiredIface) : ""
        sublabelSize: 12.5
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 68
        width: 442
        height: 42
        radius: 12.5
        color: root.theme ? root.theme.raised : "transparent"
        opacity: root.blockH === 42 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }

        IlhaText {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            size: 13
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            text: root.block === "off" ? root.t("wifi.off")
                : root.block === "unavailable" ? root.t("cc.unavailable")
                : root.net && root.net.wifiConnecting ? root.t("common.connecting")
                : root.t("cc.notConnected")
        }
    }

    // ---- Redes ----

    IlhaText {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: scanTag.left
        anchors.rightMargin: 12
        y: root.blockBottomShown + 20 - height / 2
        opacity: root.showList ? 1 : 0
        theme: root.theme
        size: 12.5
        weight: 500
        color: root.theme ? root.theme.inkMuted : "gray"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("wifi.networks")
    }

    // "● Procurando" durante a primeira varredura desta abertura.
    Row {
        id: scanTag
        anchors.right: parent.right
        anchors.rightMargin: 15
        y: root.blockBottomShown + 20 - height / 2
        spacing: 6
        opacity: root.showList && !!root.net && root.net.scanning && !root.net.scanDone ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(120) : 0 }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 4.5
            height: 4.5
            radius: 2.25
            color: root.theme ? root.theme.inkMuted : "gray"
        }
        IlhaText {
            theme: root.theme
            size: 12.5
            weight: 500
            color: root.theme ? root.theme.inkMuted : "gray"
            text: root.t("common.scanning")
        }
    }

    IlhaText {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: root.blockBottomShown + 42
        height: 30
        verticalAlignment: Text.AlignVCenter
        opacity: root.showList && root.count === 0 && !!root.net && root.net.scanDone ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(120) : 0 }
        }
        theme: root.theme
        size: 13
        weight: 400
        color: root.theme ? root.theme.inkMuted : "gray"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("wifi.noNetworks")
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: root.blockBottomShown + 42
        width: 442
        height: root.count > 0 ? root.listShownH : 0
        spacing: 4.5
        clip: true
        model: netModel
        opacity: root.showList ? 1 : 0
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: false
        cacheBuffer: 1200

        add: Transition {
            enabled: !priv.snapping
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
        displaced: Transition {
            enabled: !priv.snapping
            NumberAnimation { property: "y"; duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
        }
        move: Transition {
            enabled: !priv.snapping
            NumberAnimation { property: "y"; duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: row

            required property int index
            required property string ssid
            required property int signal
            required property bool secured
            required property bool known
            required property bool enterprise

            readonly property bool open: priv.passwordSsid !== "" && priv.passwordSsid === row.ssid
            readonly property bool busyHere: !!root.net && root.net.busyKind !== "" && root.net.busySsid === row.ssid
            readonly property bool connecting: row.busyHere && root.net.busyKind === "connect"
            readonly property bool failed: !!root.net && root.net.lastError !== "" && root.net.errorSsid === row.ssid
            readonly property bool focusedRow: root.keyboardMode && priv.selKey === row.ssid
            readonly property bool hovered: bodyArea.containsMouse || pillArea.containsMouse || forgetBtn.hovered
                || fieldHover.hovered || submitArea.containsMouse
            readonly property string sublabel: row.connecting ? root.t("common.connecting")
                : row.failed ? root.t(root.net.lastError === "wrong-password" ? "wifi.wrongPassword" : "wifi.failed")
                : root.t(row.secured ? "wifi.secured" : "wifi.open")

            width: 442
            height: row.open ? 96 : 48
            Behavior on height {
                enabled: !priv.snapping
                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
            }

            Accessible.role: Accessible.Button
            Accessible.name: row.ssid
            Accessible.description: row.sublabel

            onOpenChanged: {
                if (row.open) {
                    Qt.callLater(() => field.forceActiveFocus());
                } else {
                    field.clear();
                }
            }
            onFailedChanged: {
                if (row.failed && root.net.lastError === "wrong-password") {
                    field.clear();
                    if (row.open)
                        field.forceActiveFocus();
                }
            }

            Connections {
                target: root
                function onFieldFocusRequested(ssid) {
                    if (ssid === row.ssid)
                        field.forceActiveFocus();
                }
            }

            Component.onCompleted: if (row.ssid === priv.selKey) Qt.callLater(root.updateSelRow)

            Item {
                id: visual
                anchors.fill: parent

                Rectangle {
                    anchors.fill: parent
                    radius: 10.5
                    color: root.theme ? (row.hovered ? root.theme.rowHover : root.theme.raised) : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                    }
                }

                MouseArea {
                    id: bodyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.open)
                            field.forceActiveFocus();
                        else
                            root.activateRow(row.ssid);
                    }
                }

                Rectangle {
                    id: circle
                    anchors.left: parent.left
                    anchors.leftMargin: 6.5
                    y: 6.5
                    width: 35
                    height: 35
                    radius: 17.5
                    color: root.theme ? root.theme.rowIcon : "transparent"

                    Icon {
                        anchors.centerIn: parent
                        name: root.net ? root.net.signalIcon(row.signal) : "network_wifi_1_bar"
                        size: 16
                        color: root.theme ? root.theme.ink : "white"
                    }
                }

                Column {
                    anchors.left: circle.right
                    anchors.leftMargin: 11.5
                    anchors.right: actions.left
                    anchors.rightMargin: 10
                    y: (48 - height) / 2
                    spacing: 1

                    IlhaText {
                        width: parent.width
                        theme: root.theme
                        size: 15.5
                        weight: 600
                        color: root.theme ? root.theme.alpha(root.theme.ink, 0.92) : "white"
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        text: row.ssid
                    }
                    IlhaText {
                        width: parent.width
                        theme: root.theme
                        size: 12
                        weight: 400
                        color: root.theme ? (row.failed ? root.theme.danger : root.theme.inkMuted) : "gray"
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignLeft
                        text: row.sublabel
                    }
                }

                // × (esquecer) e a pílula; no RTL a ordem espelha junto.
                Row {
                    id: actions
                    anchors.right: parent.right
                    anchors.rightMargin: 10.5
                    y: 24 - height / 2
                    spacing: 6

                    CircleButton {
                        id: forgetBtn
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.known
                        opacity: !row.open && !row.busyHere && (row.hovered || row.focusedRow) ? 1 : 0
                        enabled: opacity > 0.5
                        Behavior on opacity {
                            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                        }
                        theme: root.theme
                        icon: "close"
                        size: 22
                        glyphSize: 13
                        fill: "transparent"
                        hoverFill: root.theme ? root.theme.pressOverlay : "transparent"
                        glyphColor: root.theme ? root.theme.inkFaint : "gray"
                        hoverGlyphColor: root.theme ? root.theme.ink : "white"
                        accessibleName: root.t("common.forget")
                        onClicked: if (root.net && !root.net.busy) root.net.forget({ ssid: row.ssid })
                    }

                    Rectangle {
                        id: pill
                        anchors.verticalCenter: parent.verticalCenter
                        height: 25.5
                        width: Math.max(66, pillMetrics.advanceWidth + 24)
                        radius: height / 2
                        opacity: row.open || row.busyHere ? 0 : 1
                        enabled: opacity > 0.5
                        Behavior on opacity {
                            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                        }
                        color: !root.theme ? "transparent"
                            : pillArea.containsMouse ? root.theme.mix(root.theme.accentSoft, root.theme.accent, 0.12)
                            : root.theme.accentSoft
                        Behavior on color {
                            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                        }

                        IlhaMetrics {
                            id: pillMetrics
                            theme: root.theme
                            size: 12.5
                            weight: 600
                            text: root.t("common.connect")
                        }
                        IlhaText {
                            anchors.centerIn: parent
                            theme: root.theme
                            size: 12.5
                            weight: 600
                            color: root.theme ? root.theme.accentInk : "white"
                            text: root.t("common.connect")
                        }
                        MouseArea {
                            id: pillArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activateRow(row.ssid)
                        }
                    }
                }

                // Campo de senha (só a linha aberta; recortado enquanto cresce).
                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: 48
                    height: Math.max(0, parent.height - 48)
                    clip: true
                    opacity: row.open ? 1 : 0
                    enabled: row.open
                    Behavior on opacity {
                        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                    }

                    Rectangle {
                        id: fieldBox
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        y: 2
                        width: 418
                        height: 34
                        radius: 10
                        color: root.theme ? root.theme.card : "transparent"
                        border.width: 1
                        border.color: root.theme && field.activeFocus ? root.theme.alpha(root.theme.accent, 0.55) : "transparent"
                        Behavior on border.color {
                            ColorAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                        }

                        HoverHandler {
                            id: fieldHover
                            cursorShape: Qt.IBeamCursor
                        }

                        QQC.TextField {
                            id: field
                            anchors.fill: parent
                            readonly property real padNear: 12
                            readonly property real padFar: submit.width + 8
                            leftPadding: root.theme && root.theme.rtl ? field.padFar : field.padNear
                            rightPadding: root.theme && root.theme.rtl ? field.padNear : field.padFar
                            topPadding: 0
                            bottomPadding: 0
                            background: Item {}
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignLeft
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            color: root.theme ? root.theme.ink : "white"
                            placeholderText: root.t("wifi.password")
                            placeholderTextColor: root.theme ? root.theme.inkFaint : "gray"
                            selectionColor: root.theme ? root.theme.alpha(root.theme.accent, 0.35) : "gray"
                            selectedTextColor: root.theme ? root.theme.ink : "white"
                            selectByMouse: true
                            renderType: Text.QtRendering
                            font.family: root.theme ? root.theme.fontFamily : ""
                            font.pixelSize: 14
                            font.variableAxes: ({ "wght": 400 })
                            Accessible.name: root.t("wifi.password")

                            cursorDelegate: Rectangle {
                                width: 2
                                height: 15
                                radius: 1
                                color: root.theme ? root.theme.accentInk : "white"
                                visible: field.activeFocus
                            }

                            Keys.onPressed: event => {
                                switch (event.key) {
                                case Qt.Key_Escape:
                                    root.closePassword();
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    root.submitPassword(row.ssid, field.text);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Up:
                                case Qt.Key_Down:
                                    root.closePassword();
                                    root.moveSel(event.key === Qt.Key_Up ? -1 : 1);
                                    event.accepted = true;
                                    break;
                                case Qt.Key_Tab:
                                case Qt.Key_Backtab:
                                    event.accepted = true;
                                    break;
                                }
                            }
                        }

                        // "Conectar" dentro do campo.
                        Rectangle {
                            id: submit
                            readonly property bool ready: field.text.length > 0 && !row.connecting
                            anchors.right: parent.right
                            anchors.rightMargin: 4.25
                            anchors.verticalCenter: parent.verticalCenter
                            height: 25.5
                            width: Math.max(66, pillMetrics.advanceWidth + 24)
                            radius: height / 2
                            opacity: submit.ready ? 1 : 0.45
                            color: !root.theme ? "transparent"
                                : submitArea.containsMouse && submit.ready ? root.theme.mix(root.theme.accentSoft, root.theme.accent, 0.12)
                                : root.theme.accentSoft
                            Behavior on opacity {
                                NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
                            }

                            IlhaText {
                                anchors.centerIn: parent
                                theme: root.theme
                                size: 12.5
                                weight: 600
                                color: root.theme ? root.theme.accentInk : "white"
                                text: root.t("common.connect")
                            }
                            MouseArea {
                                id: submitArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: submit.ready
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.submitPassword(row.ssid, field.text)
                            }
                        }
                    }
                }
            }
        }
    }

    // Anel do teclado da linha selecionada, fora do recorte da lista (o
    // recorte cortaria o anel nas bordas). Some se a linha sai da vista.
    Item {
        id: ringBox
        readonly property real rowTop: root.selRow ? root.selRow.y - list.contentY : 0
        readonly property bool inView: !!root.selRow && ringBox.rowTop >= -0.5
            && ringBox.rowTop + root.selRow.height <= list.height + 0.5
        anchors.left: list.left
        y: list.y + ringBox.rowTop
        width: list.width
        height: root.selRow ? root.selRow.height : 48

        FocusRing {
            theme: root.theme
            shown: root.keyboardMode && ringBox.inView && root.showList
            itemRadius: 10.5
        }
    }
}
