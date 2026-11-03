pragma ComponentBehavior: Bound
import QtQuick

// Tema e papel de parede numa tela só (id "themes"; "wallpapers" é apelido e
// abre já na fileira de baixo). Duas fileiras, uma sobre a outra, na largura
// dos papéis de parede:
//
// - Em cima, os temas (ThemeScreen embutida): busca, contador e os cartões
//   com a imagem de prévia, as cores e o nome de cada tema.
// - Embaixo, os papéis de parede do tema atual (WallpaperScreen embutida).
//
// Teclado: ↑/↓ trocam de fileira; ←/→, Home/End, PgUp/PgDn e Enter valem na
// fileira ativa (a borda do escolhido só aparece nela). O campo de busca fica
// com o foco o tempo todo, então digitar sempre filtra os temas. O ponteiro
// em cima de uma fileira a ativa.
//
// Aplicar um tema não fecha a tela: a fileira de baixo passa a mostrar os
// papéis do tema novo. Aplicar um papel também não fecha (dá para
// experimentar outro); só o takeover do Omarchy (Super+Ctrl+W) fecha, porque
// o script dele terminou. Esc limpa a busca e depois fecha.
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
    // Fade único (as fileiras têm camadas próprias que a pilha não enxerga).
    property list<Item> headerItems
    property list<Item> bodyItems
    signal navigate(string id, var payload)
    signal closeRequested()

    // "themes" | "walls"
    property string row: "themes"

    function opened(payload) {
        root.snapping = true;
        const p = payload || ({});
        const request = root.island && root.island.pickers && root.island.pickers.pending;
        root.row = p.row === "walls" || request ? "walls" : "themes";
        themesRow.opened(p);
        wallsRow.opened(p);
        Qt.callLater(() => root.snapping = false);
    }

    function closed() {
        themesRow.closed();
        wallsRow.closed();
    }

    // Teclas que chegaram pela janela (`ilha run`, ou sem foco no campo).
    function handleKey(event) {
        const k = event.key;
        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        if (!mods && (k === Qt.Key_Up || k === Qt.Key_Down)) {
            root.rowKey(event);
            return true;
        }
        return root.row === "walls" ? wallsRow.handleKey(event) : themesRow.handleKey(event);
    }

    function handleEscape() {
        return themesRow.handleEscape();
    }

    // ↑/↓ trocam de fileira; o resto, vindo do campo com os papéis ativos, vai para eles.
    function rowKey(event) {
        const k = event.key;
        if (k === Qt.Key_Up) {
            root.row = "themes";
            return;
        }
        if (k === Qt.Key_Down) {
            root.row = "walls";
            return;
        }
        if (root.row === "walls")
            wallsRow.handleKey(event);
    }

    implicitWidth: themesRow.implicitWidth
    implicitHeight: (root.theme ? root.theme.px.THEMES_ROW_H : 180) + wallsRow.implicitHeight

    ThemeScreen {
        id: themesRow
        y: 0
        width: implicitWidth
        height: implicitHeight
        embedded: true
        active: root.row === "themes"
        island: root.island
        theme: root.theme
        strings: root.strings
        morph: root.morph
        current: root.current
        keyboardMode: root.keyboardMode
        payload: root.payload
        edgeLeft: root.edgeLeft
        edgeRight: root.edgeRight
        onRowKey: event => root.rowKey(event)
        onCloseRequested: root.closeRequested()
        onNavigate: (id, payload) => root.navigate(id, payload)
        // Tema aplicado: segue para os papéis dele.
        onThemeApplied: {
            root.row = "walls";
            if (root.island && root.island.themes)
                root.island.themes.reloadWallpapers();
        }

        HoverHandler {
            onHoveredChanged: if (hovered) root.row = "themes"
        }
    }

    // Filete entre as fileiras.
    Rectangle {
        x: 16
        y: (root.theme ? root.theme.px.THEMES_ROW_H : 180) - 0.5
        width: root.implicitWidth - 32
        height: 1
        color: root.theme ? root.theme.alpha(root.theme.ink, 0.07) : "gray"
    }

    WallpaperScreen {
        id: wallsRow
        y: root.theme ? root.theme.px.THEMES_ROW_H : 180
        width: implicitWidth
        height: implicitHeight
        embedded: true
        active: root.row === "walls"
        island: root.island
        theme: root.theme
        strings: root.strings
        morph: root.morph
        current: root.current
        keyboardMode: root.keyboardMode
        payload: root.payload
        edgeLeft: root.edgeLeft
        edgeRight: root.edgeRight
        onRowKey: event => root.rowKey(event)
        onCloseRequested: root.closeRequested()
        onNavigate: (id, payload) => root.navigate(id, payload)

        HoverHandler {
            onHoveredChanged: if (hovered) root.row = "walls"
        }
    }
}
