-- A área flutuante força opacidade 1 com override e apaga a transparência
-- em toda janela dela. A Ilha reaplica o modo do Estilo por cima, em todas.
-- Vidro deixa o terminal em 1: o fundo dele vem do tema, para o texto não desbotar.
--
-- Carregado por hypr/init.lua, só com a Ilha ativa.
--
-- O set_up_floating do Omarchy é local (não dá para embrulhar) e roda depois
-- dos toggles: no carregamento (workspace-layouts.lua) e ao vivo, quando
-- Super+L chama o.workspace_mode por hyprctl eval. Por isso a regra é
-- reaplicada num timer, depois do fim da config, e depois de cada
-- o.workspace_mode.

local function toggles_dir()
  local state = os.getenv("XDG_STATE_HOME")
  if not state or state == "" then
    state = (os.getenv("HOME") or "") .. "/.local/state"
  end
  return state .. "/omarchy/toggles/hypr/"
end

local function exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function apply()
  local toggles = toggles_dir()
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
-- no mesmo estado Lua.
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
