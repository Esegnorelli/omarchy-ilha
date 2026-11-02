#!/bin/bash
# Switches back to the default Omarchy bar. Does not delete Ilha.
# To delete it: omarchy plugin remove esegnorelli.ilha
set -euo pipefail

omarchy bar use omarchy.bar
# The window transparency hook Ilha copied; it is inert without Ilha anyway.
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr/zz-ilha-transparency.lua"
