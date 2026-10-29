#!/bin/bash
# Ativa a Ilha como barra do Omarchy. Pode rodar de novo sem problema.
set -euo pipefail

# Versão avulsa antiga (~/Projects/quickshell): tira do autostart e fecha.
OLD="$HOME/Projects/quickshell/uninstall.sh"
if [[ -x $OLD ]] && grep -qF "Projects/quickshell" "$HOME/.config/hypr/autostart.lua" 2>/dev/null; then
  "$OLD"
fi

# A ilha respeita a flag "barra escondida"; garante que ela está desligada.
omarchy toggle bar off

omarchy-shell shell rescanPlugins
omarchy bar use esegnorelli.ilha
