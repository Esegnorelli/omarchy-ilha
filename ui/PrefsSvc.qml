import QtQuick

// Preferências da Ilha: as duas chaves da página "Ilha" (Central de controle)
// e reserveTop, só por `ilha setting` ou edição do shell.json.
// FINAL do Phase 0 (dono: lead). Porte do Prefs.qml da 1.x.
//
// Onde ficam: em ~/.config/omarchy/shell.json, dentro da barra:
//   "bar": { …, "ilha": { "focusedOnly": false, "livePeek": true, "reserveTop": false } }
//
// Por quê: a gravação passa pela API do host (shell.mutateShellConfig), que
// copia a barra, entrega ao mutador e grava o arquivo inteiro de forma
// atômica. A Ilha não abre arquivo nenhum: fora da própria pasta, só escreve
// na configuração que o host já administra. O host reinjeta barConfig na
// hora, então a leitura é ao vivo (e uma edição manual do shell.json também
// vale). `omarchy bar reset` troca a barra inteira: as chaves voltam ao padrão.
//
// Leitura: barConfig (injetado na Ilha) e, sem ele, shell.barConfig. Valor
// ausente ou que não seja booleano vale o padrão. Sem host (harness), ou se a
// gravação recusar, a escolha fica só na memória (local) até o shell reiniciar.
// Nada é gravado na partida: um `plugin add --enable` novo não precisa de passo.
//
//   focusedOnly  (false)  só o monitor focado do Hyprland desenha a cápsula
//   livePeek     (true)   o aviso ao vivo cresce e volta sozinho
//   reserveTop   (false)  reserva os 48 px do topo para a barra (as janelas
//                         começam abaixo). Desligada, a ilha flutua por cima
//                         das janelas e elas usam a tela inteira.
//
// A chave level2Dwell da 1.x não existe mais: o nível 2 abre só no clique.
// Ela é ignorada na leitura e apagada na próxima gravação.
QtObject {
    id: root

    // O Ilha.qml liga island.shell e island.barConfig.
    property var shell: null
    property var barConfig: null

    // As únicas chaves aceitas, com o padrão de cada uma.
    readonly property var defaults: ({ focusedOnly: false, livePeek: true, reserveTop: false })

    // Há host para gravar? Sem ele, a página avisa que vale até reiniciar.
    readonly property bool canPersist: !!root.shell && typeof root.shell.mutateShellConfig === "function"

    function isPlain(value) {
        return value !== null && value !== undefined && typeof value === "object" && !Array.isArray(value);
    }

    // bar.ilha como está gravado (ou um objeto vazio).
    readonly property var stored: {
        const fromIsland = root.isPlain(root.barConfig) ? root.barConfig : null;
        const fromShell = root.shell && root.isPlain(root.shell.barConfig) ? root.shell.barConfig : null;
        const bar = fromIsland || fromShell || ({});
        return root.isPlain(bar.ilha) ? bar.ilha : ({});
    }

    // Só na memória: usado quando não há host ou quando a gravação recusa.
    property var local: ({})

    function pick(key, def) {
        if (root.local && Object.prototype.hasOwnProperty.call(root.local, key))
            return !!root.local[key];
        const v = root.stored[key];
        return typeof v === "boolean" ? v : def;
    }

    readonly property bool focusedOnly: root.pick("focusedOnly", false)
    readonly property bool livePeek: root.pick("livePeek", true)
    readonly property bool reserveTop: root.pick("reserveTop", false)

    // Grava só a chave que mudou. true quando a escolha valeu (no arquivo ou
    // na memória); false para uma chave desconhecida.
    function set(key, value) {
        if (!Object.prototype.hasOwnProperty.call(root.defaults, key))
            return false;
        const want = !!value;
        let written = false;
        if (root.canPersist) {
            try {
                written = root.shell.mutateShellConfig(config => {
                    if (!root.isPlain(config.bar))
                        config.bar = {};
                    const cur = root.isPlain(config.bar.ilha) ? config.bar.ilha : {};
                    cur[key] = want;
                    // Sobra da 1.x: o nível 2 não tem mais chave.
                    delete cur.level2Dwell;
                    config.bar.ilha = cur;
                }) !== false;
            } catch (e) {
                console.warn("ilha: não foi possível gravar bar.ilha." + key + ": " + e);
                written = false;
            }
        }
        if (written) {
            // O arquivo manda: a sobra na memória sai.
            if (Object.prototype.hasOwnProperty.call(root.local, key)) {
                const next = Object.assign({}, root.local);
                delete next[key];
                root.local = next;
            }
        } else {
            const next = Object.assign({}, root.local);
            next[key] = want;
            root.local = next;
        }
        return true;
    }

    function toggle(key) {
        if (!Object.prototype.hasOwnProperty.call(root.defaults, key))
            return false;
        return root.set(key, !root[key]);
    }
}
