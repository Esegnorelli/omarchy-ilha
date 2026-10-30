#!/bin/bash
# Switches the Omarchy bar to Ilha. Safe to run again.
# The usual install is: omarchy plugin add <url> --enable
# Omarchy does not run this file on install.
set -euo pipefail

omarchy-shell shell rescanPlugins
omarchy plugin enable esegnorelli.ilha
