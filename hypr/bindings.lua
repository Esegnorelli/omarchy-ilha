-- Atalho da Ilha: Super+Z abre ou fecha o último painel.
--
-- Super+Z está livre nos atalhos padrão do Omarchy (Super+Ctrl+Z é zoom). Se
-- você já usa Super+Z, setup/setup.sh grava a marca no-bind e a Ilha não
-- registra nada. Para trocar a tecla, crie a sua em ~/.config/hypr/bindings.lua
-- (por exemplo SUPER + ALT + Z) chamando o mesmo comando.

local state = os.getenv("XDG_STATE_HOME")
if not state or state == "" then
  state = (os.getenv("HOME") or "") .. "/.local/state"
end

local marker = io.open(state .. "/omarchy/ilha/no-bind", "r")
if marker then
  marker:close()
  return
end

o.bind("SUPER + Z", "Ilha", "omarchy-shell ilha toggle last")
