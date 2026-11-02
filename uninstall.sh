#!/bin/bash
# Switches back to the default Omarchy bar and undoes setup/setup.sh.
# Does not delete Ilha. To delete it: omarchy plugin remove esegnorelli.ilha
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
omarchy bar use omarchy.bar
bash setup/setup.sh remove
