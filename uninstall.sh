#!/bin/bash
# Switches back to the default Omarchy bar. Does not delete Ilha.
# To delete it: omarchy plugin remove esegnorelli.ilha
set -euo pipefail

omarchy bar use omarchy.bar
