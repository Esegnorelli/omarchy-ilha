-- Entrada da Ilha na config do Hyprland.
--
-- setup/setup.sh grava ~/.local/state/omarchy/toggles/hypr/zz-ilha.lua, que o
-- Omarchy carrega no fim da config (todo *.lua daquela pasta). Esse arquivo só
-- define ilha_hypr_dir e roda este. Assim um `omarchy plugin update` muda o
-- comportamento sem copiar nada de novo, e remover o plugin desliga tudo.
--
-- Nada aqui age enquanto outra barra estiver ativa.

local home = os.getenv("HOME") or ""
local dir = ilha_hypr_dir or (home .. "/.config/omarchy/plugins/esegnorelli.ilha/hypr")

local function ilha_active()
  local file = io.open(home .. "/.config/omarchy/shell.json", "r")
  if not file then
    return false
  end
  local text = file:read("*a") or ""
  file:close()
  return text:find('"id"%s*:%s*"esegnorelli%.ilha"') ~= nil
end

if not ilha_active() then
  return
end

for _, name in ipairs({ "transparency", "bindings" }) do
  local path = dir .. "/" .. name .. ".lua"
  local ok, err = pcall(dofile, path)
  if not ok then
    print("ilha: " .. path .. ": " .. tostring(err))
  end
end
