-- A área flutuante força opacidade 1 com override e apaga a transparência
-- em toda janela dela. A Ilha reaplica o modo do Estilo por cima, em todas.
-- Vidro deixa o terminal em 1: o fundo dele vem do tema, para o texto não desbotar.

local function toggle_dir()
  local state = os.getenv("XDG_STATE_HOME")
  if state and state ~= "" then
    return state .. "/omarchy/toggles/hypr/"
  end
  return (os.getenv("HOME") or "") .. "/.local/state/omarchy/toggles/hypr/"
end

local function exists(name)
  local file = io.open(toggle_dir() .. name, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function apply()
  if exists("window-opaque.lua") then
    o.window(".*", { opacity = "1 1 override" })
  elseif exists("window-glassy.lua") then
    o.window(".*", { opacity = "0.75 0.75 override" })
    o.window({ tag = "transparent-window" }, { opacity = "1 1 override" })
  else
    o.window(".*", { opacity = "0.985 0.96 override" })
  end
end

apply()

if type(set_up_floating) == "function" then
  local original = set_up_floating
  set_up_floating = function(...)
    original(...)
    apply()
  end
end
