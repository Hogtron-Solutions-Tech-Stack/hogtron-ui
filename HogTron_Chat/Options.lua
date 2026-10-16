-- Chat options tab. Every set() writes profile.chat and restyles the windows.
HogHealsChat = HogHealsChat or {}
local HHC = HogHealsChat
local HH = HogHeals

local Options = {}
HHC.Options = Options

local function c() return HH.db.profile.chat end
local function refresh() HHC.Chat.Refresh() end

local function toggle(key, name, order, desc)
  return { type = "toggle", name = name, desc = desc, order = order,
    get = function() return c()[key] and true or false end,
    set = function(_, v) c()[key] = v and true or false; refresh() end }
end

local function currentSize()
  local cf = _G.ChatFrame1
  local _, size = cf and cf.GetFont and cf:GetFont()
  return size and math.floor(size + 0.5) or 14
end

function Options.Build()
  return {
    type = "group", name = "Chat", order = 37,
    args = {
      about = { type = "description", order = 0, name = "Blizzard's own chat windows in the HogHeals look. Your tabs, channels and chat settings stay exactly as they are; only the look changes. Turning the restyle off fully undoes it after a /reload." },
      enabled = toggle("enabled", "Restyle chat", 1),
      fontSize = { type = "range", name = "Text size", order = 2, min = 8, max = 28, step = 1,
        get = function() return c().fontSize or currentSize() end,
        set = function(_, v) c().fontSize = v; refresh() end },
      outline = toggle("outline", "Outline the text", 3),
      backgroundAlpha = { type = "range", name = "Background opacity", order = 4, min = 0, max = 1, step = 0.05,
        get = function() return c().backgroundAlpha end, set = function(_, v) c().backgroundAlpha = v; refresh() end },
      shortChannels = toggle("shortChannels", "Short channel names ([1], [G], [P])", 5),
      classNames = toggle("classNames", "Player names in class colours", 6),
      urlCopy = toggle("urlCopy", "Clickable web links (click to copy)", 6.5),
      fade = toggle("fade", "Fade old messages", 7),
      hideButtons = toggle("hideButtons", "Hide the scroll buttons beside chat", 8, "Mouse wheel scrolls; Shift + wheel jumps to the top / bottom."),
      hideMenuButtons = toggle("hideMenuButtons", "Hide the chat menu / channel buttons", 9, "Needs a /reload to bring them back."),
    },
  }
end
