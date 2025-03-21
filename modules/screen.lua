local window = require "hs.window"
local hotkey = require "hs.hotkey"
local mouse = require "hs.mouse"

-- 绑定快捷键
-- move active window to previous monitor
hotkey.bind(hyper, "[", function()
  window.focusedWindow():moveOneScreenWest()
end)

-- move active window to next monitor
hotkey.bind(hyper, "]", function()
  window.focusedWindow():moveOneScreenEast()
end)

-- move mouse cursor to next monitor
hotkey.bind(hyper, "0", function()
  local currentScreen = mouse.getCurrentScreen()
  local nextScreen = currentScreen:next()
  if nextScreen then
    local frame = nextScreen:frame()
    mouse.setAbsolutePosition({x = frame.x + frame.w / 2, y = frame.y + frame.h / 2})
  end
end)