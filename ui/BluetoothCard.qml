pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import "Motion.js" as Motion

// Popover de Bluetooth da Central (screens §7 e o cartão 5a do estudo do
// vídeo). Dono: Agent D. A Central desenha o recipiente (transformação K,
// cor, dimmer, clique fora); este Item é o conteúdo do cartão.
//
// Coordenadas do cartão (largura 470):
// - Cabeçalho igual ao do Wi-Fi: voltar, "Bluetooth" 18.5/600, interruptor
//   O voltar é secundário (hover do cabeçalho ou do botão).
//   (omarchy-bluetooth-power).
// - Sem adaptador ou desligado: faixa raised de 42 em y 68 com o texto 13.
// - "Salvos" com o centro em y 75 (cap top ~71 no vídeo), só com aparelhos
//   lembrados; linhas a partir de y 96: 442 x 48, passo 52.5, raio 10.5,
//   círculo 35 com o ícone do aparelho (accent quando conectado), nome
//   15.5/600, "Salvo" / "Conectado" / "Bateria 80%" 12, pílula "Conectar"
//   (accentSoft) ou "Desconectar" (tinta 10%) a 10.5 da direita. Até 4
//   visíveis; o resto rola.
// - "Por perto": 10 abaixo dos salvos (ou em y 65 sem salvos), 20 de altura,
//   com "● Procurando" enquanto o BlueZ procura. Linhas com "Parear", até 4
//   visíveis; sem nenhuma, a dica de pareamento (28). Margem de baixo 9.
//
// cardH = topoPerto + 24 + (perto > 0 ? 52.5·min(n,4) − 4.5 : 28) + 9,
// topoPerto = salvos > 0 ? 96 + 52.5·min(s,4) − 4.5 + 10 : 65
// (267.5 com 2 salvos e nada por perto, como no vídeo). Como no Wi-Fi, o
// cartão não passa de 513 − 42: primeiro encolhe "Por perto", depois os
// salvos (mínimo de 1 linha visível em cada).
//
// O clique no corpo de uma linha conecta ou pareia; nunca desconecta (só a
// pílula "Desconectar" faz isso). Conectar um fone troca a saída de áudio
// (NetSvc).
//
// Teclado (handleKey): ↑/↓ (Home/End, PgUp/PgDn) entre salvos e por perto;
// Enter conecta / desconecta / pareia; Espaço liga e desliga o Bluetooth;
// Esc volta. Anéis só no modo teclado.
//
// Atividade só entre opened() e closed(): a descoberta (net.discovering) e
// a sincronização das listas.
Item {
    id: root

    property var island: null
    property Theme theme: null
    property var strings: null
    property bool keyboardMode: false
    property real maxHeight: 900

    signal back()

    readonly property var net: root.island ? root.island.net : null

    // ---- Estado da tela ----
    readonly property bool btOn: !!root.net && root.net.btAvailable && root.net.btEnabled
    readonly property int sCount: savedModel.count
    readonly property int nCount: nearbyModel.count
    readonly property real limitH: Math.min(root.maxHeight, (root.theme ? root.theme.px.CC_H : 513) - 42)
    // Linhas visíveis: até 4 + 4; acima do limite, tira uma linha da lista
    // mais comprida (no empate, de "Por perto") até caber, nunca abaixo de 1.
    readonly property var caps: {
        let a = Math.min(root.sCount, 4);
        let b = Math.min(root.nCount, 4);
        while (root.heightFor(a, b) > root.limitH) {
            if (b >= a && b > 1)
                b--;
            else if (a > 1)
                a--;
            else
                break;
        }
        return { saved: a, nearby: b };
    }
    readonly property real savedH: root.sCount > 0 ? 52.5 * root.caps.saved - 4.5 : 0
    readonly property real nearbyTop: root.sCount > 0 ? 96 + root.savedH + 10 : 65
    readonly property real nearbyH: root.nCount > 0 ? 52.5 * root.caps.nearby - 4.5 : 28

    width: 470
    implicitWidth: 470
    implicitHeight: root.btOn ? root.nearbyTop + 24 + root.nearbyH + 9 : 68 + 42 + 12

    LayoutMirroring.enabled: !!root.theme && root.theme.rtl
    LayoutMirroring.childrenInherit: true

    function heightFor(a, b) {
        const top = root.sCount > 0 ? 96 + 52.5 * a - 4.5 + 10 : 65;
        return top + 24 + (root.nCount > 0 ? 52.5 * b - 4.5 : 28) + 9;
    }

    // ---- Contrato do cartão ----

    function opened() {
        priv.snapping = true;
        priv.live = true;
        if (root.net)
            root.net.discovering = true;
        priv.selAuto = true;
        root.syncLists();
        const keys = root.focusKeys();
        priv.selKey = keys.length > 0 ? keys[0] : "";
        savedList.positionViewAtBeginning();
        nearbyList.positionViewAtBeginning();
        Qt.callLater(() => priv.snapping = false);
    }

    function closed() {
        if (root.net)
            root.net.discovering = false;
        priv.live = false;
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
            root.moveSel(-4);
            return true;
        case Qt.Key_PageDown:
            root.moveSel(4);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!event.isAutoRepeat)
                root.activate(priv.selKey);
            return true;
        case Qt.Key_Space:
            if (!event.isAutoRepeat)
                root.togglePower();
            return true;
        }
        return false;
    }

    function handleEscape() {
        root.back();
        return true;
    }

    // ---- Listas (ListModel com diferença por endereço) ----

    function rowItem(r) {
        return {
            address: String(r.address || ""),
            devName: String(r.name || ""),
            glyph: String(r.icon || "bluetooth"),
            isConnected: !!r.connected,
            isPaired: !!r.paired,
            battery: typeof r.battery === "number" ? Math.round(r.battery) : -1,
            pending: String(r.pending || "")
        };
    }

    function syncModel(model, rows) {
        const keys = rows.map(r => String(r.address || ""));
        for (let i = model.count - 1; i >= 0; i--)
            if (keys.indexOf(model.get(i).address) < 0)
                model.remove(i);
        for (let i = 0; i < rows.length; i++) {
            const item = root.rowItem(rows[i]);
            let j = -1;
            for (let k = i; k < model.count; k++) {
                if (model.get(k).address === item.address) {
                    j = k;
                    break;
                }
            }
            if (j < 0) {
                model.insert(i, item);
                continue;
            }
            if (j !== i)
                model.move(j, i, 1);
            const cur = model.get(i);
            for (const f in item)
                if (cur[f] !== item[f])
                    model.setProperty(i, f, item[f]);
        }
    }

    function syncLists() {
        root.syncModel(savedModel, root.btOn && root.net ? root.net.saved : []);
        root.syncModel(nearbyModel, root.btOn && root.net ? root.net.nearby : []);
        // Antes de o usuário mexer, a seleção fica no topo; depois, segue o
        // mesmo aparelho quando a ordem muda.
        const keys = root.focusKeys();
        if (priv.selAuto || keys.indexOf(priv.selKey) < 0)
            priv.selKey = keys.length > 0 ? keys[0] : "";
        Qt.callLater(root.updateSelRow);
    }

    // Chaves do foco: "s:<endereço>" para salvos, "n:<endereço>" por perto.
    function focusKeys() {
        const keys = [];
        for (let i = 0; i < savedModel.count; i++)
            keys.push("s:" + savedModel.get(i).address);
        for (let i = 0; i < nearbyModel.count; i++)
            keys.push("n:" + nearbyModel.get(i).address);
        return keys;
    }

    function indexIn(model, address) {
        for (let i = 0; i < model.count; i++)
            if (model.get(i).address === address)
                return i;
        return -1;
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
        priv.selAuto = false;
        priv.selKey = keys[i];
        const address = keys[i].slice(2);
        if (keys[i].indexOf("s:") === 0)
            savedList.positionViewAtIndex(root.indexIn(savedModel, address), ListView.Contain);
        else
            nearbyList.positionViewAtIndex(root.indexIn(nearbyModel, address), ListView.Contain);
    }

    // Conecta, desconecta ou pareia, conforme a linha.
    function activate(key) {
        if (!root.net || key === "")
            return;
        const saved = key.indexOf("s:") === 0;
        const address = key.slice(2);
        const model = saved ? savedModel : nearbyModel;
        const i = root.indexIn(model, address);
        if (i < 0)
            return;
        const r = model.get(i);
        priv.selAuto = false;
        priv.selKey = key;
        if (r.pending !== "")
            return;
        if (!saved)
            root.net.pairDevice(address);
        else if (r.isConnected)
            root.net.disconnectDevice(address);
        else
            root.net.connectDevice(address);
    }

    function togglePower() {
        if (root.net && root.net.btAvailable)
            root.net.setBtEnabled(!root.net.btEnabled);
    }

    function t(key) {
        return root.strings ? root.strings.t(key) : "";
    }

    function savedSublabel(r) {
        if (r.pending === "connecting" || r.pending === "pairing")
            return root.t("common.connecting");
        if (r.isConnected)
            return r.battery >= 0 ? root.t("bt.batteryLevel").arg(Commons.I18n.formatNumber(r.battery)) : root.t("bt.connected");
        return root.t("bt.saved");
    }

    QtObject {
        id: priv
        property bool live: false
        property bool snapping: false
        property string selKey: ""
        property bool selAuto: true
    }

    // A linha selecionada (para o anel desenhado fora do recorte das listas).
    property Item selRow: null
    readonly property ListView selList: priv.selKey.indexOf("n:") === 0 ? nearbyList : savedList

    function updateSelRow() {
        const saved = priv.selKey.indexOf("s:") === 0;
        const i = priv.selKey === "" ? -1 : root.indexIn(saved ? savedModel : nearbyModel, priv.selKey.slice(2));
        root.selRow = i >= 0 ? (saved ? savedList : nearbyList).itemAtIndex(i) : null;
    }

    Connections {
        target: priv
        function onSelKeyChanged() {
            root.updateSelRow();
        }
    }

    ListModel {
        id: savedModel
    }

    ListModel {
        id: nearbyModel
    }

    Connections {
        target: root.net
        function onSavedChanged() {
            if (priv.live)
                root.syncLists();
        }
        function onNearbyChanged() {
            if (priv.live)
                root.syncLists();
        }
    }

    onBtOnChanged: if (priv.live) root.syncLists()

    // Alturas que animam com as linhas (160 ms, como a Central).
    property real savedShownH: root.savedH
    Behavior on savedShownH {
        enabled: !priv.snapping
        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
    }
    property real nearbyTopShown: root.nearbyTop
    Behavior on nearbyTopShown {
        enabled: !priv.snapping
        NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.CARD_HEIGHT) : 0; easing.type: Easing.OutCubic }
    }
    property real nearbyShownH: root.nCount > 0 ? root.nearbyH : 0
    Behavior on nearbyShownH {
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
        anchors.right: btSwitch.left
        anchors.rightMargin: 12
        y: 33 - height / 2
        theme: root.theme
        size: 18.5
        weight: 600
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("bt.title")
    }

    IlhaSwitch {
        id: btSwitch
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 22
        theme: root.theme
        enabled: !!root.net && root.net.btAvailable
        checked: !!root.net && root.net.btEnabled
        accessibleName: root.t("bt.title")
        onToggled: root.togglePower()
    }

    // ---- Sem adaptador / desligado ----

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 68
        width: 442
        height: 42
        radius: 12.5
        color: root.theme ? root.theme.raised : "transparent"
        opacity: root.btOn ? 0 : 1
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
            text: root.t(root.net && root.net.btAvailable ? "bt.off" : "bt.noAdapter")
        }
    }

    // ---- Salvos ----

    IlhaText {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 75 - height / 2
        opacity: root.btOn && root.sCount > 0 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(Motion.FADE.HOVER) : 0 }
        }
        theme: root.theme
        size: 12.5
        weight: 500
        color: root.theme ? root.theme.inkMuted : "gray"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("bt.saved")
    }

    ListView {
        id: savedList
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: 96
        width: 442
        height: root.sCount > 0 ? root.savedShownH : 0
        spacing: 4.5
        clip: true
        model: savedModel
        opacity: root.btOn ? 1 : 0
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

        delegate: ListRow {
            id: srow

            required property string address
            required property string devName
            required property string glyph
            required property bool isConnected
            required property bool isPaired
            required property int battery
            required property string pending

            width: 442
            theme: root.theme
            icon: srow.glyph
            iconAccent: srow.isConnected
            label: srow.devName
            sublabel: root.savedSublabel(srow)
            pillText: srow.pending !== "" ? "" : root.t(srow.isConnected ? "common.disconnect" : "common.connect")
            pillStyle: srow.isConnected ? "neutral" : "accent"
            onClicked: if (!srow.isConnected) root.activate("s:" + srow.address)
            onPillClicked: root.activate("s:" + srow.address)
            Component.onCompleted: if (priv.selKey === "s:" + srow.address) Qt.callLater(root.updateSelRow)
        }
    }

    // ---- Por perto ----

    IlhaText {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: btScanTag.left
        anchors.rightMargin: 12
        y: root.nearbyTopShown + 10 - height / 2
        opacity: root.btOn ? 1 : 0
        theme: root.theme
        size: 12.5
        weight: 500
        color: root.theme ? root.theme.inkMuted : "gray"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("bt.nearby")
    }

    // "● Procurando" enquanto o BlueZ procura de fato.
    Row {
        id: btScanTag
        anchors.right: parent.right
        anchors.rightMargin: 15
        y: root.nearbyTopShown + 10 - height / 2
        spacing: 6
        opacity: root.btOn && !!root.net && root.net.discovering && !!root.net.adapter && root.net.adapter.discovering ? 1 : 0
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
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: root.nearbyTopShown + 24
        height: 28
        verticalAlignment: Text.AlignVCenter
        opacity: root.btOn && root.nCount === 0 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: root.theme ? root.theme.dur(120) : 0 }
        }
        theme: root.theme
        size: 13
        weight: 400
        color: root.theme ? root.theme.inkMuted : "gray"
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        text: root.t("bt.hint")
    }

    ListView {
        id: nearbyList
        anchors.left: parent.left
        anchors.leftMargin: 14
        y: root.nearbyTopShown + 24
        width: 442
        height: root.nCount > 0 ? root.nearbyShownH : 0
        spacing: 4.5
        clip: true
        model: nearbyModel
        opacity: root.btOn ? 1 : 0
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

        delegate: ListRow {
            id: nrow

            required property string address
            required property string devName
            required property string glyph
            required property string pending

            width: 442
            theme: root.theme
            icon: nrow.glyph
            label: nrow.devName
            sublabel: nrow.pending !== "" ? root.t("common.connecting") : ""
            pillText: nrow.pending !== "" ? "" : root.t("bt.pair")
            pillStyle: "accent"
            onClicked: root.activate("n:" + nrow.address)
            onPillClicked: root.activate("n:" + nrow.address)
            Component.onCompleted: if (priv.selKey === "n:" + nrow.address) Qt.callLater(root.updateSelRow)
        }
    }

    // Anel do teclado da linha selecionada, fora do recorte das listas.
    Item {
        id: ringBox
        readonly property real rowTop: root.selRow ? root.selRow.y - root.selList.contentY : 0
        readonly property bool inView: !!root.selRow && ringBox.rowTop >= -0.5
            && ringBox.rowTop + root.selRow.height <= root.selList.height + 0.5
        anchors.left: savedList.left
        y: root.selList.y + ringBox.rowTop
        width: 442
        height: 48

        FocusRing {
            theme: root.theme
            shown: root.keyboardMode && ringBox.inView && root.btOn
            itemRadius: 10.5
        }
    }
}
