import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "OmarchyMenu.js" as OmarchyMenu
import "Motion.js" as Motion

// O menu do Omarchy como dados, para a tela "Omarchy" (MenuScreen). Lê o
// mesmo que o plugin omarchy.menu (shell/plugins/menu/Menu.qml) e do mesmo
// jeito; a lógica pura é o porte em OmarchyMenu.js. Instanciado dentro da
// tela.
//
// Fontes (Menu.qml, linhas 56–65 e 282–316):
// - $OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc (o menu padrão) e
//   ~/.config/omarchy/extensions/omarchy-menu.jsonc (a extensão do usuário,
//   só leitura). O padrão recebe a tradução antes do merge; a extensão entra
//   por cima, campo a campo (mergeMenuSources). A raiz injetada leva o rótulo
//   do catálogo.
// - Idioma: Commons.I18n.language, a mesma regra do Menu.qml
//   (OMARCHY_LANGUAGE_FILE, senão ~/.config/omarchy/language; código fora de
//   /^[a-z]{2,3}(-[A-Za-z]{2})?$/ vira "en"). Catálogo em
//   $OMARCHY_PATH/default/i18n/<idioma>/menu.json ({id: {label, title,
//   description}}); sem catálogo, o inglês do JSONC.
// - Os arquivos só são lidos depois do primeiro activate() (a tela abriu) e
//   relidos a cada abertura; enquanto a tela está aberta, mudanças no disco
//   entram na hora (watchChanges).
//
// Condições (Menu.qml, linhas 1199–1272; MenuModel.guardScript): when,
// checked e disabled são comandos de shell, avaliados num `bash -lc` só, com
// os leitores compartilhados, o instantâneo de pacotes e oito grupos em
// paralelo. Diferença: o Omarchy avalia o menu inteiro a cada abertura; aqui
// só o que a tela pede (as linhas do nível e, para um submenu, o `when` dos
// descendentes, que decidem se ele aparece; na busca, as primeiras linhas que
// casam). Cache curto: resposta vale 10 s e fica velha a cada abertura; a
// velha continua valendo para desenhar até a nova chegar (o Omarchy abre com
// as respostas da última vez). Um lote por vez; o resto espera na fila. Sem
// resposta, `when` mostra (só um falso explícito esconde), como no Omarchy.
//
// Providers (Menu.qml, linhas 318–527): fonts, power-profiles, kernels e
// languages são os mesmos scripts de uma linha (label\tvalor\tatual[\tbusca]),
// só leitura, em `bash -lc`; volatile roda de novo a cada entrada no
// submenu. apps vem do island.apps (AppsSvc, o porte do AppLibrary): linhas
// para a busca. Um provider que a Ilha não conhece (um Omarchy mais novo):
// knowsProvider() é false e a tela abre o menu do próprio Omarchy ali.
//
// Ação (Menu.qml, linhas 164–172 e 938–945): runAction(comando). Um
// `omarchy-shell shell summon <plugin> '<json>'` vai pelo shell.summon do
// host quando ele aceita; o resto por `bash -lc`, como o Util.execDetached
// do Omarchy, 180 ms depois (a ilha fecha antes, Motion.TIMING.CLOSE_THEN_RUN_MS).
// ILHA_DEV=1 (harness): só registra no log, nunca executa.
//
// API:
//   in      omarchyPath, apps (island.apps), shell (island.shell), rootLabel
//   estado  loaded, items, itemOrder; sinal updated() (itens, condições ou
//           providers mudaram: a tela refaz as linhas)
//   activate() / deactivate()                       (opened / closed da tela)
//   item(id), resolveRoute(texto), crumbs(id) -> [{id, label}]
//   levelRows(id) -> linhas                         (pede as condições do nível)
//   searchRows(id, consulta) -> linhas              (descendentes de id)
//   enterMenu(id), knowsProvider(nome), providerPending(id)
//   runAction(comando), summonHostMenu(id)
// Linha: {itemId, kind, icon, iconFont, appIcon, appId, label, target,
//         detail, action, provider, checked, disabled, drill}
QtObject {
    id: root

    // ---- Entradas ----
    property string omarchyPath: ""
    property var apps: null
    property var shell: null
    // Rótulo da raiz no caminho (a tela passa o nome da tela, "Omarchy").
    property string rootLabel: "Omarchy"

    // ---- Estado ----
    property bool loaded: false
    property var items: ({})
    property var itemOrder: []
    property var whenResults: ({})
    property var checkedResults: ({})
    property var disabledResults: ({})
    signal updated()

    readonly property string basePath: root.omarchyPath !== "" ? root.omarchyPath : String(Quickshell.env("OMARCHY_PATH") || "")
    readonly property bool dev: Quickshell.env("ILHA_DEV") === "1"
    readonly property string language: Commons.I18n.language
    readonly property string defaultMenuPath: root.basePath + "/default/omarchy/omarchy-menu.jsonc"
    readonly property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
    readonly property string catalogPath: root.basePath + "/default/i18n/" + root.language + "/menu.json"

    // Validade de uma resposta de condição (ms) e teto de linhas da busca
    // com condições avaliadas por vez.
    readonly property int guardTtlMs: 10000
    readonly property int searchGuardCap: 120

    // ---- Providers (os mesmos scripts do Menu.qml) ----
    readonly property var providers: ({
        "fonts": {
            script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
            icon: "",
            volatile: true,
            actionFor: value => "omarchy-font-set " + Commons.Util.shellQuote(value)
        },
        "power-profiles": {
            script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
            icon: "󰐋",
            // Os nomes são ids do powerprofilesctl: só o rótulo é traduzido (catálogo do host).
            labelFor: value => {
                if (value === "power-saver")
                    return Commons.I18n.t("menu.powerProfilePowerSaver");
                if (value === "balanced")
                    return Commons.I18n.t("menu.powerProfileBalanced");
                if (value === "performance")
                    return Commons.I18n.t("menu.powerProfilePerformance");
                return value;
            },
            actionFor: value => "omarchy-powerprofiles-set autodetect " + Commons.Util.shellQuote(value)
        },
        "kernels": {
            script: "current=$(omarchy-kernel get 2>/dev/null); omarchy-kernel list 2>/dev/null | while read -r k; do [[ -z $k ]] && continue; printf '%s\\t%s\\t%s\\n' \"$k\" \"$k\" \"$current\"; done",
            icon: "",
            volatile: true,
            actionFor: value => "omarchy-kernel set " + Commons.Util.shellQuote(value)
        },
        "languages": {
            script: "current=$(omarchy-language 2>/dev/null); omarchy-language list 2>/dev/null | while IFS=$'\\t' read -r name code english; do [[ -z $code ]] && continue; printf '%s\\t%s\\t%s\\t%s\\n' \"$name\" \"$code\" \"$current\" \"$english\"; done",
            icon: "",
            volatile: true,
            actionFor: value => "omarchy-language " + Commons.Util.shellQuote(value)
        }
    })

    // ---- Ciclo ----

    // A tela abriu: lê (ou relê) os arquivos e deixa velhas as condições.
    function activate() {
        priv.active = true;
        priv.epoch = Date.now();
        if (!priv.started) {
            priv.started = true;
        } else {
            defaultFile.reload();
            userFile.reload();
            catalogFile.reload();
        }
    }

    // A tela fechou: para os processos e esquece as filas (nada roda fechado).
    function deactivate() {
        priv.active = false;
        priv.guardQueue = [];
        priv.providerQueue = [];
        priv.inflight = ({});
        if (guardProc.running) {
            guardProc.cancelled = true;
            guardProc.running = false;
        }
        if (providerProc.running) {
            providerProc.cancelled = true;
            providerProc.running = false;
        }
    }

    // ---- Consultas ----

    function item(id) {
        return OmarchyMenu.item(root.items, id);
    }

    function resolveRoute(input) {
        return OmarchyMenu.resolveRoute(root.items, root.itemOrder, input);
    }

    // O caminho de id até a raiz, com a raiz na frente: [{id, label}].
    function crumbs(id) {
        const out = [{ id: "root", label: root.rootLabel }];
        const chain = OmarchyMenu.chainFor(root.items, id);
        for (let i = 0; i < chain.length; i++) {
            const e = root.item(chain[i]);
            if (e)
                out.push({ id: e.id, label: String(e.label || e.id) });
        }
        return out;
    }

    function isVisible(entry) {
        return OmarchyMenu.isVisible(root.items, root.itemOrder, root.whenResults, entry);
    }

    function isDisabled(entry) {
        return OmarchyMenu.isDisabled(root.disabledResults, entry);
    }

    function isChecked(entry) {
        if (!entry)
            return false;
        if (entry.isCurrent === true)
            return true;
        return !!(entry.checked && root.checkedResults[entry.id]);
    }

    function knowsProvider(name) {
        const n = String(name || "");
        return n === "" || n === "apps" || root.providers[n] !== undefined;
    }

    // O provider deste submenu ainda não respondeu (a tela não diz "vazio").
    function providerPending(id) {
        const e = root.item(id);
        if (!e || !e.provider || !root.knowsProvider(e.provider))
            return false;
        if (e.provider === "apps")
            return !root.apps;
        return !priv.providersLoaded[id] || priv.providerQueue.indexOf(id) !== -1 || (providerProc.running && providerProc.menuId === id);
    }

    function displayRow(entry, detail, drill) {
        const kind = String(entry.kind || "action");
        return {
            itemId: entry.id,
            kind: kind,
            icon: String(entry.icon || ""),
            iconFont: String(entry.iconFont || ""),
            appIcon: String(entry.appIcon || ""),
            appId: String(entry.appId || ""),
            label: String(entry.label || entry.id),
            target: kind === "link" ? String(entry.target || "") : entry.id,
            detail: String(detail || ""),
            action: String(entry.action || ""),
            provider: String(entry.provider || ""),
            checked: root.isChecked(entry) || root.isDisabled(entry),
            disabled: root.isDisabled(entry),
            drill: !!drill
        };
    }

    // As linhas de um nível (Menu.qml, rebuildDisplay sem busca).
    function levelRows(id) {
        const active = root.item(id) ? id : "root";
        const rows = [];
        const needs = [];
        for (let i = 0; i < root.itemOrder.length; i++) {
            const child = root.item(root.itemOrder[i]);
            if (!child || child.parent !== active)
                continue;
            if (child.kind !== "app")
                Array.prototype.push.apply(needs, OmarchyMenu.guardNeeds(root.items, root.itemOrder, child));
            if (!root.isVisible(child))
                continue;
            rows.push(root.displayRow(child, ""));
        }
        // Os apps em ordem alfabética, como no Omarchy.
        if (active === "apps") {
            rows.sort((a, b) => {
                const x = a.label.toLowerCase(), y = b.label.toLowerCase();
                return x < y ? -1 : x > y ? 1 : (a.itemId < b.itemId ? -1 : a.itemId > b.itemId ? 1 : 0);
            });
        }
        root.ensureGuards(needs);
        return rows;
    }

    // A busca (Menu.qml, rebuildDisplay com busca): os descendentes de id que
    // casam, primeiro os filhos diretos, depois o resto; detalhe = o caminho
    // do pai. Linhas apagadas ficam fora (a busca lista o que dá para fazer).
    function searchRows(id, query) {
        const active = root.item(id) ? id : "root";
        const q = String(query || "").trim();
        if (q === "")
            return root.levelRows(active);
        root.loadProvidersForSearch(active);
        const near = [];
        const far = [];
        const matched = [];
        for (let i = 0; i < root.itemOrder.length; i++) {
            const entry = root.item(root.itemOrder[i]);
            if (!entry || entry.id === "root")
                continue;
            if (!OmarchyMenu.isDescendantOf(root.items, entry.id, active))
                continue;
            if (!OmarchyMenu.matchesQuery(entry, q, true))
                continue;
            const score = OmarchyMenu.searchScore(root.items, entry, q);
            matched.push({ entry: entry, score: score });
            if (!root.isVisible(entry) || root.isDisabled(entry))
                continue;
            const row = root.displayRow(entry, OmarchyMenu.parentPathFor(root.items, entry.id));
            row.score = score;
            row.path = OmarchyMenu.pathFor(root.items, entry.id);
            if (entry.parent === active)
                near.push(row);
            else
                far.push(row);
        }
        const bySearch = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path);
        near.sort(bySearch);
        far.sort(bySearch);
        if (near.length > 0 && far.length > 0)
            far[0].drill = true;

        // As condições das primeiras que casam (as visíveis e as escondidas
        // por uma resposta velha, que pode ter mudado).
        matched.sort((a, b) => a.score - b.score);
        const needs = [];
        for (let j = 0; j < matched.length && j < root.searchGuardCap; j++) {
            if (matched[j].entry.kind !== "app")
                Array.prototype.push.apply(needs, OmarchyMenu.guardNeeds(root.items, root.itemOrder, matched[j].entry));
        }
        root.ensureGuards(needs);
        return near.concat(far);
    }

    // Entrar num submenu: o provider volátil roda de novo; o resto, uma vez.
    function enterMenu(id) {
        const e = root.item(id);
        if (!e || !e.provider)
            return;
        const spec = root.providers[e.provider];
        if (spec && spec.volatile)
            priv.providersLoaded = Object.assign({}, priv.providersLoaded, { [id]: false });
        root.loadProvider(id);
    }

    // ---- Ação ----

    function runAction(command) {
        const cmd = String(command || "");
        if (cmd === "")
            return;
        // Harness: nunca executa, só registra.
        if (root.dev) {
            console.log("ilha(dev): menu -> " + cmd + " (não executado)");
            return;
        }
        const summon = OmarchyMenu.summonAction(cmd);
        if (summon && root.shell && typeof root.shell.summon === "function" && root.shell.summon(summon.id, summon.payload))
            return;
        // Mesma forma do Util.execDetached do Omarchy (bash -lc), numa linha à
        // parte depois da espera: o comando é lido como está.
        const wait = (Motion.TIMING.CLOSE_THEN_RUN_MS / 1000).toFixed(2);
        Quickshell.execDetached(["bash", "-lc", "sleep " + wait + "\n" + cmd]);
    }

    // O menu do Omarchy naquele ponto (o comando que bin/omarchy-menu usa).
    function summonHostMenu(id) {
        root.runAction("omarchy-shell shell summon omarchy.menu " + Commons.Util.shellQuote(JSON.stringify({ menu: String(id || "root") })));
    }

    // ---- Condições ----

    function guardKey(id, tag) {
        return id + ":" + tag;
    }

    // Pede as respostas que faltam ou estão velhas (fora da tela aberta, nada).
    function ensureGuards(needs) {
        if (!priv.active || !needs || needs.length === 0)
            return;
        const now = Date.now();
        const cache = priv.cache;
        const queued = ({});
        for (let i = 0; i < priv.guardQueue.length; i++)
            queued[root.guardKey(priv.guardQueue[i].id, priv.guardQueue[i].tag)] = true;
        const add = [];
        for (let j = 0; j < needs.length; j++) {
            const n = needs[j];
            const key = root.guardKey(n.id, n.tag);
            if (queued[key] || priv.inflight[key] !== undefined)
                continue;
            const c = cache[key];
            if (c && c.expr === n.expression && c.at >= priv.epoch && now - c.at < root.guardTtlMs)
                continue;
            queued[key] = true;
            add.push(n);
        }
        if (add.length === 0)
            return;
        priv.guardQueue = priv.guardQueue.concat(add);
        Qt.callLater(root.pump);
    }

    // Respostas do lote -> cache -> os três mapas (sempre objetos novos).
    function applyGuards(text, asked) {
        const cache = Object.assign({}, priv.cache);
        const now = Date.now();
        const answered = ({});
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            const colon = line.lastIndexOf(":");
            if (colon < 0)
                continue;
            const rest = line.substring(0, colon);
            const tagAt = rest.lastIndexOf(":");
            if (tagAt < 0)
                continue;
            const key = rest;
            if (asked[key] === undefined)
                continue;
            cache[key] = { v: line.substring(colon + 1) === "1", at: now, expr: asked[key] };
            answered[key] = true;
        }
        // Sem resposta (um grupo morreu): fica a anterior, marcada como tentada,
        // para não pedir de novo em laço.
        for (const key in asked) {
            if (answered[key])
                continue;
            const old = cache[key];
            cache[key] = { v: old ? old.v : undefined, at: now, expr: asked[key] };
        }
        priv.cache = cache;
        const w = ({}), c = ({}), d = ({});
        for (const key in cache) {
            const v = cache[key].v;
            if (v === undefined)
                continue;
            const tagAt = key.lastIndexOf(":");
            const id = key.substring(0, tagAt);
            const tag = key.substring(tagAt + 1);
            if (tag === "w")
                w[id] = v;
            else if (tag === "c")
                c[id] = v;
            else if (tag === "d")
                d[id] = v;
        }
        root.whenResults = w;
        root.checkedResults = c;
        root.disabledResults = d;
    }

    // ---- Providers ----

    function loadProvider(id) {
        const e = root.item(id);
        if (!e || !e.provider || priv.providersLoaded[id])
            return;
        if (e.provider === "apps") {
            priv.providersLoaded = Object.assign({}, priv.providersLoaded, { [id]: true });
            root.mergeApps();
            return;
        }
        if (!root.providers[e.provider] || !priv.active)
            return;
        if (priv.providerQueue.indexOf(id) === -1 && !(providerProc.running && providerProc.menuId === id))
            priv.providerQueue = priv.providerQueue.concat([id]);
        Qt.callLater(root.pump);
    }

    // Busca: os providers dos submenus dentro do nível (Menu.qml, loadProvidersForSearch).
    function loadProvidersForSearch(active) {
        for (let i = 0; i < root.itemOrder.length; i++) {
            const e = root.item(root.itemOrder[i]);
            if (!e || !e.provider || priv.providersLoaded[e.id])
                continue;
            if (active !== "root" && e.id !== active && !OmarchyMenu.isDescendantOf(root.items, e.id, active))
                continue;
            root.loadProvider(e.id);
        }
    }

    // Linhas do provider (Menu.qml, mergeProviderRows): o valor atual ganha o ✓.
    function mergeProviderRows(text, menuId, key) {
        const spec = root.providers[key];
        if (!spec)
            return;
        const lines = String(text || "").split("\n");
        const rows = [];
        const taken = ({});
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line)
                continue;
            const parts = line.split("\t");
            const rawLabel = parts[0] || "";
            const label = spec.labelFor ? spec.labelFor(rawLabel) : rawLabel;
            const value = parts[1] || parts[0] || "";
            const current = parts[2] || "";
            if (!label)
                continue;
            // Valores diferentes podem virar o mesmo slug (Fira Code / Fira-Code).
            let rowId = menuId + "." + OmarchyMenu.slugify(value);
            while (taken[rowId])
                rowId += "-";
            taken[rowId] = true;
            rows.push({
                id: rowId, parent: menuId, kind: "action",
                icon: spec.icon || "", iconFont: "", label: label, title: "", target: "",
                description: "", action: spec.actionFor(value), provider: "",
                aliases: [], searchTerms: (parts[3] ? [parts[3]] : []).concat(label !== rawLabel ? [rawLabel] : []),
                when: "", checked: "", disabled: "", order: 0,
                isCurrent: value === current
            });
        }
        const merged = OmarchyMenu.swapProviderRows(root.items, root.itemOrder, menuId, rows);
        root.items = merged.items;
        root.itemOrder = merged.itemOrder;
    }

    // Os apps do island.apps como linhas (Menu.qml, mergeAppRows).
    function mergeApps() {
        if (!root.apps || typeof root.apps.results !== "function")
            return;
        const list = root.apps.results("");
        const rows = [];
        for (let i = 0; i < list.length; i++) {
            const a = list[i];
            const appId = String(a.id || "");
            if (appId === "")
                continue;
            const desc = String(a.desc || "");
            rows.push({
                id: "apps." + appId, parent: "apps", kind: "app",
                icon: "", iconFont: "", appIcon: String(a.iconName || ""), appId: appId,
                label: String(a.name || appId), title: "", target: "", description: desc,
                action: "", provider: "", aliases: desc !== "" ? [desc] : [], searchTerms: [],
                when: "", checked: "", disabled: "", order: 0
            });
        }
        const merged = OmarchyMenu.mergeAppRows(root.items, root.itemOrder, rows);
        root.items = merged.items;
        root.itemOrder = merged.itemOrder;
        Qt.callLater(() => root.updated());
    }

    // ---- Fila: um lote de condições e um provider por vez ----

    function pump() {
        if (!priv.active)
            return;
        if (!guardProc.running && priv.guardQueue.length > 0) {
            const batch = priv.guardQueue;
            priv.guardQueue = [];
            const asked = ({});
            for (let i = 0; i < batch.length; i++)
                asked[root.guardKey(batch[i].id, batch[i].tag)] = batch[i].expression;
            const script = OmarchyMenu.guardScriptFor(batch);
            if (script !== "") {
                priv.inflight = asked;
                guardProc.collected = "";
                guardProc.cancelled = false;
                guardProc.command = ["bash", "-lc", script];
                guardProc.running = true;
            }
        }
        if (!providerProc.running) {
            while (priv.providerQueue.length > 0) {
                const id = priv.providerQueue[0];
                priv.providerQueue = priv.providerQueue.slice(1);
                const e = root.item(id);
                const spec = e && e.provider ? root.providers[e.provider] : null;
                if (!spec || priv.providersLoaded[id])
                    continue;
                priv.providersLoaded = Object.assign({}, priv.providersLoaded, { [id]: true });
                providerProc.menuId = id;
                providerProc.providerKey = e.provider;
                providerProc.revision = priv.revision;
                providerProc.collected = "";
                providerProc.cancelled = false;
                providerProc.command = ["bash", "-lc", spec.script];
                providerProc.running = true;
                break;
            }
        }
    }

    // ---- Montagem (Menu.qml, rebuildItemsFromSources) ----

    function rebuild() {
        if (!priv.defaultSettled || !priv.userSettled || !priv.catalogSettled)
            return;
        const translated = OmarchyMenu.applyTranslations(priv.defaultItems, priv.catalog);
        const rootCatalog = priv.catalog.root;
        const merged = OmarchyMenu.mergeMenuSources(translated, priv.userItems, rootCatalog && rootCatalog.label);
        priv.revision += 1;
        priv.providersLoaded = ({});
        priv.providerQueue = [];
        root.items = merged.items;
        root.itemOrder = merged.itemOrder;
        root.loaded = priv.defaultItems.length > 0;
        root.updated();
    }

    function parseCatalog(raw) {
        try {
            const parsed = JSON.parse(raw || "{}");
            return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    // ---- Interno ----

    property QtObject privState: QtObject {
        id: priv
        property bool started: false
        property bool active: false
        property real epoch: 0
        property int revision: 0
        property var defaultItems: []
        property var userItems: []
        property var catalog: ({})
        property bool defaultSettled: false
        property bool userSettled: false
        property bool catalogSettled: false
        property string defaultRaw: ""
        property string userRaw: ""
        property string catalogRaw: ""
        // "id:tag" -> {v, at, expr}
        property var cache: ({})
        // "id:tag" -> expressão do lote no ar
        property var inflight: ({})
        property var guardQueue: []
        property var providersLoaded: ({})
        property var providerQueue: []
    }

    property FileView defaultFileView: FileView {
        id: defaultFile
        path: priv.started ? root.defaultMenuPath : ""
        watchChanges: priv.active
        blockLoading: true
        printErrors: false
        onLoaded: {
            const raw = text();
            const changed = raw !== priv.defaultRaw || !priv.defaultSettled;
            priv.defaultRaw = raw;
            priv.defaultItems = OmarchyMenu.keepMenuRows(priv.defaultItems, raw, true);
            priv.defaultSettled = true;
            if (changed)
                root.rebuild();
        }
        onLoadFailed: {
            priv.defaultSettled = true;
            root.rebuild();
        }
        onFileChanged: reload()
    }

    property FileView userFileView: FileView {
        id: userFile
        path: priv.started ? root.userMenuPath : ""
        watchChanges: priv.active
        blockLoading: true
        printErrors: false
        onLoaded: {
            const raw = text();
            const changed = raw !== priv.userRaw || !priv.userSettled;
            priv.userRaw = raw;
            priv.userItems = OmarchyMenu.keepMenuRows(priv.userItems, raw, false);
            priv.userSettled = true;
            if (changed)
                root.rebuild();
        }
        onLoadFailed: {
            const changed = priv.userItems.length > 0 || !priv.userSettled;
            priv.userItems = [];
            priv.userRaw = "";
            priv.userSettled = true;
            if (changed)
                root.rebuild();
        }
        onFileChanged: reload()
    }

    property FileView catalogFileView: FileView {
        id: catalogFile
        path: priv.started ? root.catalogPath : ""
        watchChanges: priv.active
        blockLoading: true
        printErrors: false
        onLoaded: {
            const raw = text();
            const changed = raw !== priv.catalogRaw || !priv.catalogSettled;
            priv.catalogRaw = raw;
            priv.catalog = root.parseCatalog(raw);
            priv.catalogSettled = true;
            if (changed)
                root.rebuild();
        }
        onLoadFailed: {
            const changed = priv.catalogRaw !== "" || !priv.catalogSettled;
            priv.catalog = ({});
            priv.catalogRaw = "";
            priv.catalogSettled = true;
            if (changed)
                root.rebuild();
        }
        onFileChanged: reload()
    }

    property Process guardRunner: Process {
        id: guardProc
        property string collected: ""
        property bool cancelled: false
        stdout: SplitParser {
            onRead: data => guardProc.collected += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            const asked = priv.inflight;
            priv.inflight = ({});
            // Um lote morto no meio só respondeu parte: o que respondeu vale,
            // o resto fica com a resposta anterior (applyGuards).
            if (!guardProc.cancelled && priv.active) {
                root.applyGuards(guardProc.collected, asked);
                root.updated();
            }
            // A fila que esperou este lote (inclusive depois de reabrir).
            Qt.callLater(root.pump);
        }
    }

    property Process providerRunner: Process {
        id: providerProc
        property string menuId: ""
        property string providerKey: ""
        property string collected: ""
        property int revision: 0
        property bool cancelled: false
        stdout: SplitParser {
            onRead: data => providerProc.collected += data + "\n"
        }
        onExited: () => {
            const p = providerProc;
            if (p.cancelled || !priv.active) {
                // Não terminou: roda de novo na próxima vez.
                priv.providersLoaded = Object.assign({}, priv.providersLoaded, { [p.menuId]: false });
            } else if (p.revision === priv.revision) {
                root.mergeProviderRows(p.collected, p.menuId, p.providerKey);
                root.updated();
            }
            // A fila que esperou este provider (inclusive depois de reabrir).
            Qt.callLater(root.pump);
        }
    }

    // Lista de apps nova (instalou, removeu): as linhas de app acompanham.
    property Connections appsWatcher: Connections {
        target: root.apps
        ignoreUnknownSignals: true
        function onEntriesChanged() {
            if (priv.active && priv.providersLoaded["apps"])
                root.mergeApps();
        }
    }
}
