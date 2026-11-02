#!/bin/bash
# Switches the Omarchy bar to Ilha. Safe to run again.
# The usual install is: omarchy plugin add <url> --enable
# Omarchy does not run this file; Ilha runs setup/setup.sh itself when it loads.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
omarchy-shell shell rescanPlugins
omarchy plugin enable esegnorelli.ilha
bash setup/setup.sh
