-- A área flutuante força opacidade 1 com override e apaga a transparência
-- em toda janela dela. A Ilha reaplica o modo do Estilo por cima, em todas.
-- Vidro deixa o terminal em 1: o fundo dele vem do tema, para o texto não desbotar.
--
-- A Ilha copia este arquivo para ~/.local/state/omarchy/toggles/hypr/ como
-- zz-ilha-transparency.lua: o Omarchy carrega todo *.lua dali no fim da config.
-- Só age enquanto a Ilha é a barra ativa; trocar de barra ou remover o plugin
-- desliga sem precisar apagar nada.
--
-- O set_up_floating do Omarchy é local (não dá para embrulhar) e roda depois
-- dos toggles: no carregamento (workspace-layouts.lua) e ao vivo, quando
-- Super+L chama o.workspace_mode por hyprctl eval. Por isso a regra é
-- reaplicada num timer, depois do fim da config, e depois de cada
-- o.workspace_mode.

local home = os.getenv("HOME") or ""

local function state_home()
  local state = os.getenv("XDG_STATE_HOME")
  if state and state ~= "" then
    return state
  end
  return home .. "/.local/state"
end

local function exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function ilha_active()
  local file = io.open(home .. "/.config/omarchy/shell.json", "r")
  if not file then
    return false
  end
  local text = file:read("*a") or ""
  file:close()
  return text:find('"id"%s*:%s*"esegnorelli%.ilha"') ~= nil
end

local function apply()
  if not ilha_active() then
    return
  end
  local toggles = state_home() .. "/omarchy/toggles/hypr/"
  if exists(toggles .. "window-opaque.lua") then
    o.window(".*", { opacity = "1 1 override" })
  elseif exists(toggles .. "window-glassy.lua") then
    o.window(".*", { opacity = "0.75 0.75 override" })
    o.window({ tag = "transparent-window" }, { opacity = "1 1 override" })
  else
    o.window(".*", { opacity = "0.985 0.96 override" })
  end
end

-- Embrulha o.workspace_mode uma vez só, mesmo se o arquivo rodar de novo
-- (reload ou hyprctl eval) no mesmo estado Lua.
local function wrap_workspace_mode()
  if type(o) ~= "table" or type(o.workspace_mode) ~= "function" then
    return
  end
  if o.workspace_mode == ilha_workspace_mode then
    return
  end
  local original = o.workspace_mode
  ilha_workspace_mode = function(...)
    local result = original(...)
    apply()
    return result
  end
  o.workspace_mode = ilha_workspace_mode
end

apply()

if type(hl) == "table" and type(hl.timer) == "function" then
  hl.timer(function()
    apply()
    wrap_workspace_mode()
  end, { type = "oneshot", timeout = 1 })
else
  wrap_workspace_mode()
end
