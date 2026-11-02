#!/bin/bash
# Prepara o sistema para a Ilha. A própria Ilha roda este script toda vez que
# carrega (Island.qml), porque `omarchy plugin add` só clona e valida: não há
# gancho de instalação. Pode rodar quantas vezes quiser.
#
#   setup.sh [--loaded-version X]   instala ou atualiza
#   setup.sh remove                 desfaz (uninstall.sh chama isto)
#
# O que faz:
#   1. Grava ~/.local/state/omarchy/toggles/hypr/zz-ilha.lua, que o Omarchy
#      carrega no fim da config do Hyprland. Ele roda hypr/init.lua deste
#      checkout: transparência nas janelas e o atalho Super+Z.
#   2. Não registra Super+Z se você já usa essa tecla (marca no-bind).
#   3. Confere os comandos de que os painéis dependem e avisa o que faltar.
#   4. Recarrega o Hyprland só quando algo acima mudou.
#   5. Com --loaded-version: se o manifest.json no disco tem outra versão, o
#      shell está rodando a Ilha antiga da memória (o Omarchy não limpa o
#      cache de QML ao recarregar plugins). Reinicia o shell uma vez.
set -uo pipefail

action=install
loaded_version=""
while (( $# > 0 )); do
  case $1 in
  remove) action=remove ;;
  --loaded-version) loaded_version=${2:-}; shift ;;
  esac
  shift
done

PLUGIN_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}
TOGGLES_DIR=$STATE_HOME/omarchy/toggles/hypr
ILHA_STATE=$STATE_HOME/omarchy/ilha
LOADER=$TOGGLES_DIR/zz-ilha.lua
STAMP=$ILHA_STATE/hypr.sha256
NO_BIND=$ILHA_STATE/no-bind

log() { echo "ilha-setup: $*" >&2; }

have_hyprland() {
  command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1
}

reload_hyprland() {
  have_hyprland && hyprctl reload >/dev/null 2>&1
}

if [[ $action == remove ]]; then
  # Também apaga o nome antigo, de quando só a transparência era copiada.
  rm -f "$LOADER" "$TOGGLES_DIR/zz-ilha-transparency.lua" "$STAMP" "$NO_BIND" "$ILHA_STATE/restarted-for"
  rmdir "$ILHA_STATE" 2>/dev/null
  reload_hyprland
  exit 0
fi

mkdir -p "$TOGGLES_DIR" "$ILHA_STATE" || { log "não deu para criar $TOGGLES_DIR"; exit 1; }
rm -f "$TOGGLES_DIR/zz-ilha-transparency.lua"

# 1. Carregador. Aponta para este checkout; some sozinho se o plugin sumir.
# O caminho vai como string longa do Lua; um ]] no caminho a quebraria.
if [[ $PLUGIN_DIR == *"]]"* ]]; then
  log "caminho do plugin não suportado: $PLUGIN_DIR"
  exit 1
fi
loader_text="-- Gerado por $PLUGIN_DIR/setup/setup.sh. Não edite: a Ilha o reescreve.
ilha_hypr_dir = [[$PLUGIN_DIR/hypr]]
local init = ilha_hypr_dir .. \"/init.lua\"
local file = io.open(init, \"r\")
if file then
  file:close()
  dofile(init)
end
"
if [[ ! -f $LOADER || $(<"$LOADER")$'\n' != "$loader_text" ]]; then
  printf '%s' "$loader_text" >"$LOADER.tmp" && mv -f "$LOADER.tmp" "$LOADER" || { log "não deu para gravar $LOADER"; exit 1; }
fi

# 2. Super+Z: conflito é um Super+Z (modmask 64) que não seja o da Ilha.
if have_hyprland && command -v jq >/dev/null 2>&1; then
  binds=$(hyprctl binds -j 2>/dev/null)
  if [[ -n $binds ]]; then
    if jq -e 'any(.[]; .modmask == 64 and (.key | ascii_downcase) == "z" and .description != "Ilha" and .submap == "")' <<<"$binds" >/dev/null 2>&1; then
      [[ -f $NO_BIND ]] || { : >"$NO_BIND"; log "Super+Z já está em uso; a Ilha não registra atalho"; }
    elif [[ -f $NO_BIND ]] && ! jq -e 'any(.[]; .modmask == 64 and (.key | ascii_downcase) == "z")' <<<"$binds" >/dev/null 2>&1; then
      # A tecla ficou livre de novo.
      rm -f "$NO_BIND"
    fi
  fi
fi

# 3. Dependências. Todas vêm na instalação base do Omarchy.
missing=()
for cmd in omarchy omarchy-shell hyprctl jq nmcli ip systemctl hyprpicker aether \
  omarchy-capture-screenrecording omarchy-reminder omarchy-update-available \
  omarchy-toggle-enabled omarchy-hyprland-toggle omarchy-hyprland-toggle-enabled \
  omarchy-hyprland-workspace-layout-current omarchy-hyprland-workspace-layout-toggle \
  omarchy-launch-floating-terminal-with-presentation; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
  log "faltam comandos (alguns painéis ficam limitados): ${missing[*]}"
fi

# 4. Recarrega só se o carregador, os arquivos hypr/ ou a marca mudaram.
stamp=$(cat "$LOADER" "$PLUGIN_DIR"/hypr/*.lua 2>/dev/null | sha256sum | cut -d' ' -f1)
[[ -f $NO_BIND ]] && stamp="$stamp no-bind"
if [[ ! -f $STAMP || $(<"$STAMP") != "$stamp" ]]; then
  if reload_hyprland; then
    printf '%s' "$stamp" >"$STAMP"
    log "Hyprland recarregado com a config da Ilha"
  fi
fi

# 5. Versão em memória diferente da do disco: reinicia o shell, uma vez por
# versão. Quem reinicia é o Hyprland, porque este script morre com o shell.
if [[ -n $loaded_version ]] && command -v jq >/dev/null 2>&1; then
  disk_version=$(jq -r '.version // empty' "$PLUGIN_DIR/manifest.json" 2>/dev/null)
  marker=$ILHA_STATE/restarted-for
  if [[ -n $disk_version && $disk_version != "$loaded_version" && $(cat "$marker" 2>/dev/null) != "$disk_version" ]]; then
    printf '%s' "$disk_version" >"$marker"
    log "versão $disk_version instalada, $loaded_version em memória; reiniciando o shell"
    have_hyprland && hyprctl dispatch 'hl.dsp.exec_cmd("omarchy-restart-shell")' >/dev/null 2>&1
  fi
fi
exit 0
