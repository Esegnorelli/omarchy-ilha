.pragma library

// Copiado de Omarchy shell/plugins/menu/MenuModel.js (MIT, Copyright (c) David
// Heinemeier Hansson). Só o que a tela "Omarchy" da Ilha usa: leitura do
// JSONC, merge com a extensão do usuário, traduções, visibilidade, busca,
// rotas, as linhas de provider e o script das condições (when / checked /
// disabled). As funções copiadas estão sem mudanças além dos comentários em
// português; o que é só da Ilha fica no fim do arquivo, marcado. Dono na
// Ilha 2.x: o agente da tela Omarchy.

// ---- Leitura do JSONC (cópia) ----

// JSONC aqui é JSON com comentários de linha inteira e vírgulas sobrando.
function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

function normalizeAliases(value) {
  if (Array.isArray(value)) return value.filter(function(v) { return v })
  if (typeof value === "string" && value) return [value]
  return []
}

// O id com pontos é a árvore: trigger.capture é filho de trigger. O tipo é
// inferido: com action é ação, com target é atalho, o resto é submenu.
function normalizeItem(id, raw) {
  var value = raw || {}
  var aliases = normalizeAliases(value.aliases)
  var parent = value.parent
  if (parent === undefined)
    parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root"
  if (id === "root") parent = ""

  var kind = value.action ? "action" : (value.target ? "link" : "menu")

  return {
    id: id,
    parent: parent,
    kind: kind,
    icon: value.icon || "",
    iconFont: value.iconFont || "",
    label: value.label || id,
    title: value.title || "",
    target: value.target || "",
    description: value.description || "",
    action: value.action || "",
    provider: value.provider || "",
    aliases: aliases,
    // Termos só de busca: entram no nameSearchText, nunca no resolveRoute.
    searchTerms: normalizeAliases(value.searchTerms),
    when: value.when || "",
    checked: value.checked || "",
    disabled: value.disabled || ""
  }
}

// null quando o texto não é um menu (arquivo pego no meio de uma gravação).
// Um arquivo só de comentários ainda é um menu vazio.
function readMenuJsonc(raw) {
  var stripped = stripJsonc(raw)
  if (!stripped.trim()) return []

  var parsed
  try {
    parsed = JSON.parse(stripped)
  } catch (e) {
    return null
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null

  var source = (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items))
    ? parsed.items
    : parsed
  var out = []
  for (var id in source) {
    var entry = source[id]
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) continue
    out.push(normalizeItem(id, entry))
  }
  return out
}

// Uma leitura no meio de uma gravação não troca linhas boas por nada. O menu
// padrão (required) nunca é vazio de verdade: vazio também é meio de gravação.
function keepMenuRows(previous, raw, required) {
  var items = readMenuJsonc(raw)
  if (!items || (required && items.length === 0)) return previous
  return items
}

// A extensão do usuário entra por cima do padrão, campo a campo: reusar um id
// troca só os campos declarados e mantém a posição; ids novos vão para o fim.
// A raiz é injetada quando nenhum dos dois a declara (rótulo do catálogo).
function mergeMenuSources(defaultItems, userItems, rootLabel) {
  var nextItems = ({})
  var nextOrder = []
  var sources = [defaultItems || [], userItems || []]

  for (var s = 0; s < sources.length; s++) {
    var src = sources[s]
    for (var i = 0; i < src.length; i++) {
      var entry = src[i]
      if (!entry || !entry.id) continue
      if (!nextItems[entry.id]) nextOrder.push(entry.id)
      var prior = nextItems[entry.id] || {}
      var merged = {}
      for (var k in prior) merged[k] = prior[k]
      for (var k2 in entry) merged[k2] = entry[k2]
      merged.id = entry.id
      nextItems[entry.id] = merged
    }
  }

  if (!nextItems.root) {
    nextItems.root = { id: "root", parent: "", kind: "menu", icon: "", iconFont: "", label: (typeof rootLabel === "string" && rootLabel) ? rootLabel : "Go", title: "", target: "", description: "", aliases: [], searchTerms: [], when: "", checked: "", disabled: "", action: "", provider: "" }
    nextOrder.unshift("root")
  }
  for (var k3 = 0; k3 < nextOrder.length; k3++) nextItems[nextOrder[k3]].order = k3

  return {
    items: nextItems,
    itemOrder: nextOrder
  }
}

// As duas trocas abaixo devolvem mapas novos para quem chama atribuir de uma
// vez: nunca escrevem nos mapas recebidos (um `var` do QML às vezes perde a
// escrita no lugar, e a linha some ou duplica).

// Troca todas as linhas de app pelo conjunto atual.
function mergeAppRows(items, itemOrder, appRows) {
  var source = items || ({})
  var order = Array.isArray(itemOrder) ? itemOrder : []
  var rows = Array.isArray(appRows) ? appRows : []
  var nextItems = ({})
  var nextOrder = []

  for (var i = 0; i < order.length; i++) {
    var id = order[i]
    var existing = source[id]
    if (!existing || existing.kind === "app") continue
    nextItems[id] = existing
    nextOrder.push(id)
  }

  for (var j = 0; j < rows.length; j++) {
    var row = rows[j]
    if (!row || !row.id || nextItems[row.id]) continue
    row.order = nextOrder.length
    nextItems[row.id] = row
    nextOrder.push(row.id)
  }

  return { items: nextItems, itemOrder: nextOrder }
}

// Troca as linhas que um provider deu, sem mexer no resto.
function swapProviderRows(items, itemOrder, menuId, rows) {
  var source = items || ({})
  var order = Array.isArray(itemOrder) ? itemOrder : []
  var incoming = Array.isArray(rows) ? rows : []
  var nextItems = ({})
  var nextOrder = []

  for (var i = 0; i < order.length; i++) {
    var id = order[i]
    var existing = source[id]
    if (!existing || existing.providerMenu === menuId) continue
    nextItems[id] = existing
    nextOrder.push(id)
  }

  for (var j = 0; j < incoming.length; j++) {
    var row = incoming[j]
    if (!row || !row.id || nextItems[row.id]) continue
    row.providerMenu = menuId
    row.order = nextOrder.length
    nextItems[row.id] = row
    nextOrder.push(row.id)
  }

  return { items: nextItems, itemOrder: nextOrder }
}

// ---- Árvore, rotas, caminhos (cópia) ----

function item(items, id) {
  return items && items[id] ? items[id] : null
}

// Uma rota é um id ou um alias declarado no JSONC; o id exato vence, e linhas
// de app nunca são rota. Texto desconhecido segue como id literal.
function resolveRoute(items, itemOrder, input) {
  var raw = String(input || "").toLowerCase().replace(/_/g, "-")
  if (!raw || raw === "go" || raw === "menu") return "root"
  if (item(items, raw)) return raw
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var entry = item(items, order[i])
    if (!entry || entry.kind === "app" || !entry.aliases) continue
    for (var j = 0; j < entry.aliases.length; j++) {
      var alias = String(entry.aliases[j] || "").toLowerCase().replace(/_/g, "-")
      if (alias === raw) return entry.id
    }
  }
  return raw
}

function slugify(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "item"
}

function depthFor(items, id) {
  var depth = 0
  var current = item(items, id)
  var guard = 0

  while (current && current.parent && current.parent !== "root" && guard < 32) {
    depth += 1
    current = item(items, current.parent)
    guard += 1
  }

  return depth
}

function pathFor(items, id) {
  var labels = []
  var current = item(items, id)
  var guard = 0

  while (current && current.id !== "root" && guard < 32) {
    labels.unshift(current.label)
    current = item(items, current.parent)
    guard += 1
  }

  return labels.join(" › ")
}

function parentPathFor(items, id) {
  var entry = item(items, id)
  if (!entry || !entry.parent || entry.parent === "root") return ""
  return pathFor(items, entry.parent)
}

function isDescendantOf(items, id, ancestorId) {
  if (ancestorId === "root") return id !== "root"

  var current = item(items, id)
  var guard = 0
  while (current && current.parent && guard < 32) {
    if (current.parent === ancestorId) return true
    current = item(items, current.parent)
    guard += 1
  }

  return false
}

// ---- Visibilidade e busca (cópia) ----

// `when` falso esconde a linha; um submenu sem nenhum descendente visível some
// junto (os de provider ficam: as linhas chegam na hora).
function isVisible(items, itemOrder, whenResults, entry, depth) {
  if (!entry) return false
  if (entry.when && whenResults && whenResults[entry.id] === false) return false
  if (entry.kind !== "menu" && entry.kind !== "link") return true
  if (entry.provider) return true

  var guard = depth || 0
  if (guard >= 32) return false

  var target = entry.kind === "link" ? entry.target : entry.id
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var child = item(items, order[i])
    if (child && child.parent === target && isVisible(items, itemOrder, whenResults, child, guard + 1)) return true
  }

  return false
}

// `disabled` verdadeiro: a linha fica, apagada e fora da seleção (o que já
// está instalado nas listas de Instalar).
function isDisabled(disabledResults, entry) {
  if (!entry || !entry.disabled) return false
  return !!(disabledResults && disabledResults[entry.id])
}

function searchableToken(value) {
  return String(value || "").replace(/[._-]+/g, " ")
}

function leafIdFor(id) {
  var parts = String(id || "").split(".")
  return parts.length > 0 ? parts[parts.length - 1] : id
}

function nameSearchText(entry) {
  if (!entry) return ""
  var aliases = []
  var values = (Array.isArray(entry.aliases) ? entry.aliases : []).concat(Array.isArray(entry.searchTerms) ? entry.searchTerms : [])
  for (var i = 0; i < values.length; i++) aliases.push(searchableToken(values[i]))
  return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")].join(" ").toLowerCase()
}

function termInSearchWords(term, text) {
  var words = String(text || "").toLowerCase().split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i] === term) return true
  }
  return false
}

function descriptionTextMatches(query, text) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termInSearchWords(terms[i], text)) return false
  }
  return true
}

function matchesQuery(entry, query, visible) {
  if (!entry || entry.id === "root") return false
  if (!visible) return false

  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)

  for (var i = 0; i < terms.length; i++) {
    if (!terms[i]) continue
    if (nameText.indexOf(terms[i]) >= 0) continue
    if (termInSearchWords(terms[i], descriptionText)) continue
    return false
  }

  return true
}

function searchScore(items, entry, query) {
  var needle = String(query || "").toLowerCase().trim()
  var label = entry.label.toLowerCase()
  var nameText = nameSearchText(entry)
  var descriptionText = String(entry.description || "").toLowerCase()
  var score = 80

  if (label === needle) score = entry.parent === "root" ? 2 : 0
  // Um app instalado cujo nome tem a busca como palavra inteira vence as
  // entradas de mesmo rótulo (Instalar › Zen).
  else if (entry.kind === "app" && label.split(/\s+/).indexOf(needle) >= 0) score = 0
  else if (label.indexOf(needle) === 0) score = 10
  else if (label.indexOf(needle) >= 0) score = 30
  else if (nameText.indexOf(needle) >= 0) score = 40
  else if (descriptionTextMatches(needle, descriptionText)) score = 60

  if (entry.kind === "menu" || entry.kind === "link") score -= 2
  // Linhas de app ficam depois de todo o menu; ganham do empate dentro da faixa.
  if (entry.kind === "app") score -= 5

  return score * 1000 + depthFor(items, entry.id) * 25 + entry.order
}

// ---- Condições: um script bash por lote (cópia) ----

// Comandos de que várias linhas leem um valor (Padrões › Navegador compara
// sete linhas com `omarchy-default-browser`): rodam uma vez só, de saída.
var GUARD_READERS = [
  "omarchy-bar background",
  "omarchy-bar get omarchy.power showPercentage",
  "omarchy-bar get omarchy.clock format",
  "omarchy-bar get omarchy.clock verticalFormat",
  "omarchy-bar position",
  "omarchy-channel-current",
  "omarchy-default-agent",
  "omarchy-default-browser",
  "omarchy-default-editor",
  "omarchy-default-terminal",
  "omarchy-default-dictation",
  "omarchy-dns",
  "omarchy-dock autohide",
  "omarchy-dock position",
  "omarchy-hyprland-corners",
  "omarchy-hyprland-window-transparency",
  "omarchy-hyprland-workspace-layout-default",
  "omarchy-shell notifications isDnd",
  "omarchy-toggle-nightlight --status"
]

// Presença de pacote e de comando respondida dentro do processo, de um
// instantâneo do `pacman -Q` (com os provides) guardado em
// $XDG_RUNTIME_DIR/omarchy-menu-packages e carimbado com o banco local do
// pacman: o mesmo cache que o menu do Omarchy usa.
function guardPackageSnapshot() {
  var build = '{ set -o pipefail; pacman -Qq && LC_ALL=C pacman -Qi'
    + " | awk '/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, \"\") }"
    + ' provides && $0 != "None" { n = split($0, p, " ");'
    + ' for (i = 1; i <= n; i++) { sub(/[<>=].*/, "", p[i]); print p[i] } }\' && echo /; } 2>/dev/null'
  var stamp = 'stat -c "%d:%i:%.9Y:%.9Z" -- "$__omarchy_pkg_db/local" 2>/dev/null'

  return '__omarchy_pkg_db=${OMARCHY_PACMAN_DB_PATH:-$(pacman-conf DBPath 2>/dev/null)} || __omarchy_pkg_db=""\n'
    + '__omarchy_pkg_db=${__omarchy_pkg_db%/}\n'
    + '__omarchy_pkg_cache=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/omarchy-menu-packages}\n'
    + '__omarchy_pkg_stamp=""\n'
    + '[[ -z $__omarchy_pkg_db ]] || __omarchy_pkg_stamp=$(' + stamp + ') || __omarchy_pkg_stamp=""\n'
    + '__omarchy_pkg_names=()\n'
    + 'if [[ -n $__omarchy_pkg_cache && -n $__omarchy_pkg_stamp ]]'
    + ' && { IFS= read -r __omarchy_pkg_line && [[ $__omarchy_pkg_line == "$__omarchy_pkg_stamp" ]]'
    + ' && mapfile -t __omarchy_pkg_names; } 2>/dev/null <"$__omarchy_pkg_cache"; then :\n'
    + 'else\n'
    + '  __omarchy_pkg_names=()\n'
    + '  [[ ! -e $__omarchy_pkg_db/db.lck ]] || __omarchy_pkg_stamp=""\n'
    + '  mapfile -t __omarchy_pkg_names < <(' + build + ')\n'
    + '  if ((${#__omarchy_pkg_names[@]})) && [[ ${__omarchy_pkg_names[-1]} == "/" ]]; then unset "__omarchy_pkg_names[-1]"; else __omarchy_pkg_stamp=""; fi\n'
    + '  if [[ -n $__omarchy_pkg_cache && -n $__omarchy_pkg_stamp && ! -e $__omarchy_pkg_db/db.lck ]]'
    + ' && [[ $(' + stamp + ') == "$__omarchy_pkg_stamp" ]]; then\n'
    + '    { printf "%s\\n" "$__omarchy_pkg_stamp" "${__omarchy_pkg_names[@]}" >"$__omarchy_pkg_cache.$$"'
    + ' && mv -f -- "$__omarchy_pkg_cache.$$" "$__omarchy_pkg_cache"; } 2>/dev/null'
    + ' || rm -f -- "$__omarchy_pkg_cache.$$" 2>/dev/null || :\n'
    + '  fi\n'
    + 'fi\n'
}

function guardHelpers() {
  return 'declare -A __omarchy_pkgs=()\n'
    + guardPackageSnapshot()
    + 'for __omarchy_pkg in "${__omarchy_pkg_names[@]}"; do __omarchy_pkgs[$__omarchy_pkg]=1; done\n'
    + '__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]] && return 0; '
    + '[[ $1 == *[\\<\\>=]* ]] && { pacman -Q "$1" &>/dev/null; return; }; return 1; }\n'
    + 'omarchy-pkg-present() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 1; done; return 0; }\n'
    + 'omarchy-pkg-missing() { local p; for p in "$@"; do __omarchy_pkg_has "$p" || return 0; done; return 1; }\n'
    + 'omarchy-cmd-present() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 1; done; return 0; }\n'
    + 'omarchy-cmd-missing() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 0; done; return 1; }\n'
}

// Os leitores começam todos juntos, antes do instantâneo de pacotes, cada um
// numa substituição de processo; o lote lê a saída de cada um em seguida.
function guardPrelude(guards) {
  var start = ""
  var collect = ""

  for (var i = 0; i < GUARD_READERS.length; i++) {
    if (guards.indexOf(guardReaderSlot(i)) < 0) continue
    var value = "__omarchy_read_" + i
    var fd = "__omarchy_read_fd_" + i
    start += "exec {" + fd + "}< <(" + GUARD_READERS[i] + " 2>/dev/null)\n"
    collect += "IFS= read -r -d '' " + value + " <&$" + fd + " || :\n"
      + "exec {" + fd + "}<&-\n"
      + value + "=${" + value + "%\"${" + value + "##*[!$'\\n']}\"}\n"
  }

  return start + guardHelpers() + collect
}

function guardReaderSlot(index) {
  return "${__omarchy_read_" + index + "}"
}

function substituteGuardReaders(expression) {
  for (var i = 0; i < GUARD_READERS.length; i++)
    expression = expression.split("$(" + GUARD_READERS[i] + ")").join(guardReaderSlot(i))

  return expression
}

function guardLine(id, tag, expression) {
  return "if { " + substituteGuardReaders(expression) + "; } >/dev/null 2>&1; then echo "
    + id + ":" + tag + ":1; else echo " + id + ":" + tag + ":0; fi\n"
}

// Quantos subshells dividem as condições (o lote dura o que dura a mais lenta).
var GUARD_GROUPS = 8

// Uma ação que só pede ao shell para chamar um plugin roda dentro do processo.
function summonAction(action) {
  var match = /^omarchy-shell shell summon ([A-Za-z0-9._-]+)(?: '([^']*)')?$/.exec(String(action || ""))
  if (!match) return null
  return { id: match[1], payload: match[2] || "{}" }
}

// Troca label / title / description pelo catálogo do idioma
// (default/i18n/<código>/menu.json). O rótulo em inglês continua buscável em
// searchTerms. Aplicado ao menu padrão antes do merge com o usuário.
function applyTranslations(items, catalog) {
  var source = Array.isArray(items) ? items : []
  var strings = (catalog && typeof catalog === "object") ? catalog : ({})
  var out = []
  for (var i = 0; i < source.length; i++) {
    var entry = source[i]
    var translated = entry && strings[entry.id]
    if (!translated || typeof translated !== "object") {
      out.push(entry)
      continue
    }
    var next = {}
    for (var k in entry) next[k] = entry[k]
    if (translated.label) {
      if (translated.label !== entry.label && entry.label) {
        var terms = Array.isArray(entry.searchTerms) ? entry.searchTerms.slice() : []
        if (terms.indexOf(entry.label) < 0) terms.push(entry.label)
        next.searchTerms = terms
      }
      next.label = translated.label
    }
    if (translated.title) next.title = translated.title
    if (translated.description) next.description = translated.description
    out.push(next)
  }
  return out
}

// ======================================================================
// Só da Ilha (não vem do Omarchy).
// ======================================================================

// O guardScript do Omarchy avalia o menu inteiro; a Ilha avalia só o que a
// tela mostra. Mesmo script (prelúdio, leitores, instantâneo de pacotes, oito
// grupos em paralelo, status != 0 se algum grupo morreu), a partir de uma
// lista de pedidos [{id, tag, expression}] (tag: "w" | "c" | "d").
function guardScriptFor(requests) {
  var lines = []
  var list = Array.isArray(requests) ? requests : []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (r && r.id && r.tag && r.expression) lines.push(guardLine(r.id, r.tag, r.expression))
  }
  if (lines.length === 0) return ""

  var groups = []
  for (var j = 0; j < lines.length; j++) {
    var group = j % GUARD_GROUPS
    groups[group] = (groups[group] || "") + lines[j]
  }

  var script = guardPrelude(lines.join("")) + "__omarchy_groups=()\n"
  for (var k = 0; k < groups.length; k++) script += "{\n" + groups[k] + "} &\n__omarchy_groups+=($!)\n"
  return script + "__omarchy_failed=0\n"
    + 'for __omarchy_group in "${__omarchy_groups[@]}"; do wait "$__omarchy_group" || __omarchy_failed=1; done\n'
    + "((__omarchy_failed == 0))\n"
}

// As condições de que uma linha precisa para ser desenhada: as dela (when,
// checked, disabled) e, num submenu sem provider, o `when` de todos os
// descendentes (o isVisible desce a árvore). Devolve [{id, tag, expression}].
function guardNeeds(items, itemOrder, entry) {
  var out = []
  if (!entry) return out
  if (entry.when) out.push({ id: entry.id, tag: "w", expression: entry.when })
  if (entry.checked) out.push({ id: entry.id, tag: "c", expression: entry.checked })
  if (entry.disabled) out.push({ id: entry.id, tag: "d", expression: entry.disabled })
  if ((entry.kind !== "menu" && entry.kind !== "link") || entry.provider) return out

  var target = entry.kind === "link" ? entry.target : entry.id
  if (!target) return out
  var order = Array.isArray(itemOrder) ? itemOrder : []
  for (var i = 0; i < order.length; i++) {
    var e = item(items, order[i])
    if (e && e.when && e.id !== entry.id && isDescendantOf(items, e.id, target))
      out.push({ id: e.id, tag: "w", expression: e.when })
  }
  return out
}

// Os ids do caminho até a raiz (sem a raiz), do mais alto ao atual.
function chainFor(items, id) {
  var ids = []
  var current = item(items, id)
  var guard = 0
  while (current && current.id !== "root" && guard < 32) {
    ids.unshift(current.id)
    current = item(items, current.parent)
    guard += 1
  }
  return ids
}
