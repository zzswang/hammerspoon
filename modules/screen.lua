local window = require "hs.window"
local hotkey = require "hs.hotkey"

-- 绑定快捷键
-- move active window to previous monitor
hotkey.bind(hyper, "[", function()
  window.focusedWindow():moveOneScreenWest()
end)

-- move active window to next monitor
hotkey.bind(hyper, "]", function()
  window.focusedWindow():moveOneScreenEast()
end)