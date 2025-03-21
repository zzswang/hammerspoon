local hotkey = require "hs.hotkey"
local caffeinate = require "hs.caffeinate"

-- 绑定快捷键
-- hyper + s: 让系统进入休眠模式
hotkey.bind(hyper, "s", function()
  caffeinate.systemSleep()
end)