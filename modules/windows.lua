local screen = require "hs.screen"
local hotkey = require "hs.hotkey"
local window = require "hs.window"
local hints = require "hs.hints"

-- 定义窗口宽度和高度状态
local widthStates = {2/3, 1/2, 1/3}  -- 窗口宽度状态（注意顺序为2/3, 1/2, 1/3）
local heightStates = {2/3, 1/2, 1/3} -- 窗口高度状态（用于上和下）

-- 保存每个屏幕上被隐藏的窗口的状态
local hiddenWindowsOnScreens = {}

-- 禅模式的开关标志，每个屏幕独立记录
local zenModeActiveOnScreens = {}

-- 定义一个全局表，用于按窗口ID存储其上一个大小和位置
local windowStateTracker = {}

-- 定义误差阈值，用于确认当前窗口是否大致处于某种宽度或高度状态
local margin = 0.01  -- 允许的误差为 1%

local maxWidth = 1  -- 用于保存窗口最大化时的宽度百分比
local centerState = 1  -- 用于切换居中状态
local windowMaximized = false  -- 用于维护窗口全屏状态

-- 辅助函数：获取当前窗口和屏幕
local function getCurrentWindowAndScreen()
    local win = hs.window.focusedWindow()
    if not win then return nil, nil end
    return win, win:screen()
end

-- 判断当前窗口是否已经贴住某个边界
local function isWindowAside(direction)
  local win, screen = getCurrentWindowAndScreen()
  if not win then return false end

  local f = win:frame()
  local max = screen:frame()

  -- 根据方向判断窗口是否贴住特定边
  if direction == 'left' then
      return math.abs(f.x - max.x) < margin * max.w  -- 窗口左侧接近屏幕左侧
  elseif direction == 'right' then
      return math.abs(f.x + f.w - max.x - max.w) < margin * max.w  -- 窗口右侧接近屏幕右侧
  elseif direction == 'up' then
      return math.abs(f.y - max.y) < margin * max.h  -- 窗口顶部接近屏幕顶部
  elseif direction == 'down' then
      return math.abs(f.y + f.h - max.y - max.h) < margin * max.h  -- 窗口底部接近屏幕底部
  end
  return false
end

-- 在宽度状态（2/3, 1/2, 1/3）之间切换，给定当前宽度，找出下一个宽度
local function findNextWidth(currentWidth)
  for i, w in ipairs(widthStates) do
      if math.abs(currentWidth - w) < margin then
          return widthStates[(i % #widthStates) + 1]  -- 返回下一档
      end
  end
  return widthStates[1]  -- 如果不在某一档内，则返回最大状态 (2/3)
end

-- 在当前宽度状态下，切换到下一档
local function switchToNextWidth(direction)
  local win, screen = getCurrentWindowAndScreen()
  if not win then return end

  local f = win:frame()
  local max = screen:frame()
  local currentWidth = f.w / max.w

  -- 找到下一个宽度状态
  local nextWidth = findNextWidth(currentWidth)

  -- 根据方向来设置窗口的新尺寸和位置
  if direction == "left" then
      win:setFrame({x = max.x, y = f.y, w = max.w * nextWidth, h = f.h})
  elseif direction == "right" then
      win:setFrame({x = max.x + (max.w - max.w * nextWidth), y = f.y, w = max.w * nextWidth, h = f.h})
  end
end

-- 辅助函数：从当前高度查找下一个状态
local function findNextHeight(currentHeight)
  for i, h in ipairs(heightStates) do
      if math.abs(currentHeight - h) < margin then
          return heightStates[(i % #heightStates) + 1]  -- 返回下一档
      end
  end
  return heightStates[1]  -- 默认返回最大高度状态 (2/3)
end

-- 在当前高度状态下，切换到下一档
local function switchToNextHeight(direction)
  local win, screen = getCurrentWindowAndScreen()
  if not win then return end

  local f = win:frame()
  local max = screen:frame()
  local currentHeight = f.h / max.h

  -- 找到下一个高度状态
  local nextHeight = findNextHeight(currentHeight)

  -- 根据方向来设置窗口的新尺寸
  if direction == "up" then
      win:setFrame({x = f.x, y = max.y, w = f.w, h = max.h * nextHeight})
  elseif direction == "down" then
      win:setFrame({x = f.x, y = max.y + (max.h - max.h * nextHeight), w = f.w, h = max.h * nextHeight})
  end
end

-- 移动窗口到指定的边，如果已经贴边，则切换宽度
local function moveWindowToSide(direction)
  local win = getCurrentWindowAndScreen()
  if not win then return end

  -- 检查是否已经贴在对应边
  if isWindowAside(direction) then
      -- 如果已贴边，则在宽度状态之间切换
      if direction == "left" or direction == "right" then
        switchToNextWidth(direction)
      -- 如果已贴边，则在高度状态之间切换
      elseif direction == "up" or direction == "down" then
        switchToNextHeight(direction)
      end
  else
      -- 如果未贴边，将窗口移动到对应边
      local win, screen = getCurrentWindowAndScreen()
      local f = win:frame()
      local max = screen:frame()

      if direction == 'left' then
          win:setFrame({x = max.x, y = f.y, w = f.w, h = f.h})
      elseif direction == 'right' then
          win:setFrame({x = max.x + (max.w - f.w), y = f.y, w = f.w, h = f.h})
      elseif direction == 'up' then
          win:setFrame({x = f.x, y = max.y, w = f.w, h = f.h})
      elseif direction == 'down' then
          win:setFrame({x = f.x, y = max.y + (max.h - f.h), w = f.w, h = f.h})
      end
  end
end

-- 辅助函数：记录窗口的当前状态（左右和宽度或上下和高度）
local function saveWindowState(win)
    local id = win:id()  -- 获取窗口的 ID
    local f = win:frame()

    windowStateTracker[id] = {
        x = f.x,
        y = f.y,
        w = f.w,
        h = f.h
    }
end

-- 辅助函数：恢复窗口到记录的状态
local function restoreWindowState(win)
    local id = win:id()  -- 获取窗口的 ID
    if not windowStateTracker[id] then return end -- 如果没有记录，直接返回

    local f = win:frame()
    win:setFrame({
        x = windowStateTracker[id].x,
        y = windowStateTracker[id].y,
        w = windowStateTracker[id].w,
        h = windowStateTracker[id].h
    })
end

-- 辅助函数：检查窗口是否全宽
local function isFullWidth(win)
    local screen = win:screen()
    local f = win:frame()
    local max = screen:frame()

    -- 计算宽度容忍误差值（margin的百分比 * 屏幕宽度）
    local widthErrorMargin = margin * max.w

    -- 判断窗口宽度是否为全屏宽度
    return math.abs(f.x - max.x) < widthErrorMargin and math.abs(f.w - max.w) < widthErrorMargin
end

-- 辅助函数：检查窗口是否全高
local function isFullHeight(win)
    local screen = win:screen()
    local f = win:frame()
    local max = screen:frame()

    -- 计算高度容忍误差值（margin的百分比 * 屏幕高度）
    local heightErrorMargin = margin * max.h

    -- 判断窗口高度是否为全屏高度
    return math.abs(f.y - max.y) < heightErrorMargin and math.abs(f.h - max.h) < heightErrorMargin
end

-- 辅助函数：检查窗口是否全屏
local function isFullScreen(win)
    local screen = win:screen()
    local f = win:frame()
    local max = screen:frame()

    -- 计算宽度与高度的容忍误差值
    local widthErrorMargin = margin * max.w
    local heightErrorMargin = margin * max.h

    -- 判断窗口是否全屏：即既全宽又全高
    return math.abs(f.x - max.x) < widthErrorMargin and math.abs(f.w - max.w) < widthErrorMargin and
           math.abs(f.y - max.y) < heightErrorMargin and math.abs(f.h - max.h) < heightErrorMargin
end

-- 辅助函数：检查窗口是否被居中
local function isCentered(win)
    local screen = win:screen()
    local f = win:frame()
    local max = screen:frame()

    -- 计算参照位置: 居中时窗口的 x 和 y
    local centerX = max.x + (max.w - f.w) / 2
    local centerY = max.y + (max.h - f.h) / 2

    -- 允许一个小的偏差用于判断是否完全居中，使用屏幕宽度和高度的 margin
    local xErrorMargin = margin * max.w
    local yErrorMargin = margin * max.h

    return math.abs(f.x - centerX) < xErrorMargin and math.abs(f.y - centerY) < yErrorMargin
end

-- 辅助函数：隐藏当前屏幕上所有窗口，除了当前活动窗口
local function hideOtherWindowsOnCurrentScreen(currentWindow)
    -- 获取当前窗口所在的屏幕
    local currentScreen = currentWindow:screen()

    -- 初始化此屏幕的隐藏窗口列表
    hiddenWindowsOnScreens[currentScreen:id()] = {}
    
    -- 获取所有当前屏幕上的可见窗口
    local allWindows = window.visibleWindows()

    -- 遍历所有窗口，隐藏当前屏幕上的其他窗口
    for _, win in ipairs(allWindows) do
        if win ~= currentWindow and win:screen() == currentScreen then
            if win:isVisible() then
                hiddenWindowsOnScreens[currentScreen:id()][win:id()] = win
                win:application():hide() -- 隐藏该应用程序的窗口
            end
        end
    end
end

-- 辅助函数：显示之前隐藏在当前屏幕上的窗口
local function restoreHiddenWindowsOnCurrentScreen(screen)
    local hiddenWindows = hiddenWindowsOnScreens[screen:id()]
    if hiddenWindows then
        for id, win in pairs(hiddenWindows) do
            if win and win:application() then
                win:application():unhide() -- 恢复应用程序
            end
        end
    end
    hiddenWindowsOnScreens[screen:id()] = nil -- 清空恢复的数据
end

-- 辅助函数：调整当前窗口大小到禅模式
local function optimizeZenWindow(win)
    local screenFrame = win:screen():frame() -- 当前窗口所在屏幕的尺寸
    local optimizedHeight = screenFrame.h * 0.95 -- 高度设置为屏幕高度的90%
    local optimizedWidth = optimizedHeight * 1.618  -- 宽度设置为高度的黄金比例

    if optimizedWidth > screenFrame.w then
        optimizedWidth = screenFrame.w * 0.9  -- 如果宽度超出屏幕宽度，设置为屏幕宽度的90%
        optimizedHeight = optimizedWidth / 1.618  -- 重新计算高度
    end

    -- 计算居中的 x, y
    local newX = screenFrame.x + (screenFrame.w - optimizedWidth) / 2
    local newY = screenFrame.y + (screenFrame.h - optimizedHeight) / 2

    -- 设置窗口的大小和位置
    win:setFrame({
        x = newX,
        y = newY,
        w = optimizedWidth,
        h = optimizedHeight
    })
end

-- 窗口移动到左侧，切换宽度
hotkey.bind(hyper, "left", function() moveWindowToSide('left') end)

-- 窗口移动到右侧，切换宽度
hotkey.bind(hyper, "right", function() moveWindowToSide('right') end)

-- 窗口移动到上方，切换高度
hotkey.bind(hyper, "up", function() moveWindowToSide('up') end)

-- 窗口移动到下方，切换高度
hotkey.bind(hyper, "down", function() moveWindowToSide('down') end)



-- 调用方法：全屏宽度，或者恢复原来的大小和位置
hotkey.bind(hyper, "w", function()
    local win = hs.window.focusedWindow()
    if not win then return end

    if isFullWidth(win) then
        -- 窗口当前是全宽状态，需要恢复到它之前的状态
        restoreWindowState(win)
    else
        -- 记住窗口当前的宽度和位置
        saveWindowState(win)

        -- 将窗口宽度设置为全屏
        local f = win:frame()
        local screen = win:screen()
        local max = screen:frame()

        win:setFrame({
            x = max.x,
            y = f.y,      -- 保持当前的 y
            w = max.w,    -- 设置为全宽
            h = f.h       -- 保持当前的高度
        })
    end
end)

-- 调用方法：全屏高度，或者恢复原来的大小和位置
hotkey.bind(hyper, "h", function()
    local win = hs.window.focusedWindow()
    if not win then return end

    if isFullHeight(win) then
        -- 窗口当前是全高状态，需要恢复到它之前的状态
        restoreWindowState(win)
    else
        -- 记住窗口当前的高度和位置
        saveWindowState(win)

        -- 将窗口高度设置为全屏
        local f = win:frame()
        local screen = win:screen()
        local max = screen:frame()

        win:setFrame({
            x = f.x,      -- 保持当前的 x
            y = max.y,    -- 设置为全高
            w = f.w,      -- 保持当前的宽度
            h = max.h     -- 设置为全高度
        })
    end
end)

-- 调用方法：全屏，或者恢复原来的大小和位置
hotkey.bind(hyper, "f", function()
    local win = hs.window.focusedWindow()
    if not win then return end

    if isFullScreen(win) then
        -- 窗口当前是全屏状态，需要恢复到它之前的状态
        restoreWindowState(win)
    else
        -- 记住窗口当前的大小和位置
        saveWindowState(win)

        -- 将窗口设置为全屏
        local screen = win:screen()
        local max = screen:frame()

        win:setFrame(max)  -- 全屏展开窗口
    end
end)

-- 让窗口居中，按一次居中，再按一次恢復
hotkey.bind(hyper, "c", function()
    local win = hs.window.focusedWindow()
    if not win then return end

    if isCentered(win) then
        -- 如果窗口已居中，恢复到之前的大小和位置
        restoreWindowState(win)
    else
        -- 记住窗口当前的位置，以便恢复
        saveWindowState(win)

        -- 让窗口居中显示，保持宽度和高度不变
        local f = win:frame()
        local screen = win:screen()
        local max = screen:frame()

        local newX = max.x + (max.w - f.w) / 2  -- 计算新的 x 值（居中）
        local newY = max.y + (max.h - f.h) / 2  -- 计算新的 y 值（居中）

        win:setFrame({
            x = newX,
            y = newY,
            w = f.w,
            h = f.h
        })
    end
end)

-- 绑定快捷键：⌃⌥⌘ + z 切换禅模式
hotkey.bind(hyper, "z", function ()
    local win = window.focusedWindow()  -- 获取当前活动窗口
    if not win then return end           -- 如果没有窗口聚焦则返回

    -- 获取当前屏幕
    local currentScreen = win:screen()
    
    -- 禅模式是否已在当前屏幕上激活
    if zenModeActiveOnScreens[currentScreen:id()] then
        -- 禅模式已激活，恢复当前屏幕上隐藏的窗口
        restoreWindowState(win)                      -- 恢复当前窗口的大小和位置
        restoreHiddenWindowsOnCurrentScreen(currentScreen)  -- 恢复当前屏幕上的窗口
        zenModeActiveOnScreens[currentScreen:id()] = false  -- 重置当前屏幕的禅模式状态
    else
        -- 激活禅模式：只影响当前屏幕的内容
        saveWindowState(win)                         -- 保存当前窗口状态
        hideOtherWindowsOnCurrentScreen(win)         -- 隐藏当前屏幕上的其他窗口
        optimizeZenWindow(win)                   -- 优化当前窗口大小并居中
        zenModeActiveOnScreens[currentScreen:id()] = true  -- 记录禅模式已激活
    end
end)


-- 窗口放大 10%，并确保不超出屏幕范围，同时保持窗口中心
hotkey.bind(hyper, "=", function()
    local win, screen = getCurrentWindowAndScreen()
    if not win then return end
    local f = win:frame()               -- 当前窗口的尺寸
    local max = screen:frame()          -- 屏幕的整体尺寸

    -- 当前窗口中心点计算
    local centerX = f.x + f.w / 2
    local centerY = f.y + f.h / 2

    -- 放大 10%
    local newWidth = math.min(f.w * 1.1, max.w)
    local newHeight = math.min(f.h * 1.1, max.h)

    -- 如果增加后的高度已经达到屏幕的高度，则宽度继续增加，保持纵横比
    if newHeight >= max.h then
        newWidth = math.min(f.w * 1.1, max.w)
    end

    -- 重新计算窗口的位置，让中心点保持不变
    local newX = math.max(max.x, centerX - newWidth / 2)
    local newY = math.max(max.y, centerY - newHeight / 2)

    -- 确保窗口不会超出屏幕的右边或底边
    if newX + newWidth > max.x + max.w then newX = max.x + max.w - newWidth end
    if newY + newHeight > max.y + max.h then newY = max.y + max.h - newHeight end

    -- 设置调整后的窗口尺寸和位置
    win:setFrame({
        x = newX,
        y = newY,
        w = newWidth,
        h = newHeight
    })
end)

-- 窗口缩小 10%，并确保大小不能小于屏幕的1/3，同时保持窗口中心
hotkey.bind(hyper, "-", function()
    local win, screen = getCurrentWindowAndScreen()
    if not win then return end
    local f = win:frame()               -- 当前窗口的尺寸
    local max = screen:frame()          -- 屏幕的整体尺寸

    -- 当前窗口中心点计算
    local centerX = f.x + f.w / 2
    local centerY = f.y + f.h / 2

    -- 确保窗口不能小于屏幕大小的1/3
    local newWidth = math.max(f.w * 0.9, max.w / 3)
    local newHeight = math.max(f.h * 0.9, max.h / 3)

    -- 重新计算窗口的位置，让中心点保持不变
    local newX = math.max(max.x, centerX - newWidth / 2)
    local newY = math.max(max.y, centerY - newHeight / 2)

    -- 确保窗口不会超出屏幕的右边或底边
    if newX + newWidth > max.x + max.w then newX = max.x + max.w - newWidth end
    if newY + newHeight > max.y + max.h then newY = max.y + max.h - newHeight end

    -- 设置调整后的窗口尺寸和位置
    win:setFrame({
        x = newX,
        y = newY,
        w = newWidth,
        h = newHeight
    })
end)

-- display a keyboard hint for switching focus to each window
hotkey.bind(hyper, '/', function()
    hints.windowHints()
    -- Display current application window
    -- hints.windowHints(hs.window.focusedWindow():application():allWindows())
end)

-- 绑定快捷键，让窗口快速切换
switcher_space = hs.window.switcher.new(hs.window.filter.new():setCurrentSpace(true):setDefaultFilter{}) -- include minimized/hidden windows, current Space only
hotkey.bind(hyper, ".", function()
    -- windowSwitcher:next()    -- 切换到下一个窗口
    switcher_space:next()
end)
hotkey.bind(hyper, ",", function()
    -- windowSwitcher:next()    -- 切换到下一个窗口
    switcher_space:previous()
end)