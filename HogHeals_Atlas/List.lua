-- List: one scrolling column of rows, the only widget the Atlas window is made of. A fixed number of row buttons
-- is created once and repainted from a data array; the mouse wheel moves the offset. No scroll-frame templates:
-- they differ per client generation, a plain offset does not.
--
-- A data row is a table: text, right (right-aligned text), mid (middle column, lists made with opts.midX),
-- color / rightColor / midColor = { r, g, b }, icon (texture),
-- header (true = section title), selected, indent (px), item (item id: gives the row an item tooltip).
local A = HogHealsAtlas

local List = {}
List.__index = List
A.List = List

local C = A.COLORS

local function solid(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end
A.solid = solid

-- Forever: SetText on a template-less FontString throws "Font not set". Always a template.
local function text(parent, c, justify, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetTextColor(c[1], c[2], c[3])
  if justify then fs:SetJustifyH(justify) end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end
A.text = text

--- A flat text button: label, cyan when on. Returns the button (button.label = its FontString).
function A.button(parent, label, width, height, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 20)
  b.bg = solid(b, "BACKGROUND", C.panel)
  b.bg:SetAllPoints(b)
  b.label = text(b, C.cream, "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(label)
  b:SetScript("OnClick", function(self, btn) if onClick then onClick(self, btn) end end)
  b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.17, 0.17, 0.21, 1) end)
  b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1) end)
  function b:SetOn(on)
    self.on = on and true or false
    local c = self.on and C.cyan or C.cream
    self.label:SetTextColor(c[1], c[2], c[3])
  end
  return b
end

function List.New(parent, opts)
  local self = setmetatable({ opts = opts, data = {}, offset = 0, rows = {} }, List)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(opts.width, opts.rows * opts.rowHeight)
  self.frame = f
  f.bg = solid(f, "BACKGROUND", C.ink, 0.6)
  f.bg:SetAllPoints(f)
  if f.EnableMouseWheel then f:EnableMouseWheel(true) end
  f:SetScript("OnMouseWheel", function(_, delta) self:Scroll(-(delta or 0) * 3) end)
  self.empty = text(f, C.grey, "CENTER")
  self.empty:SetPoint("TOP", f, "TOP", 0, -10)
  self.empty:SetWidth(opts.width - 20)
  if self.empty.SetWordWrap then self.empty:SetWordWrap(true) end

  for i = 1, opts.rows do
    local r = CreateFrame("Button", nil, f)
    r:SetSize(opts.width, opts.rowHeight)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * opts.rowHeight)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.sel = solid(r, "BACKGROUND", C.cyan, 0.18)
    r.sel:SetAllPoints(r)
    r.sel:Hide()
    r.hover = solid(r, "BACKGROUND", C.cream, 0.06)
    r.hover:SetAllPoints(r)
    r.hover:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(opts.rowHeight - 2, opts.rowHeight - 2)
    r.icon:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.icon:Hide()
    r.left = text(r, C.cream, "LEFT")
    r.right = text(r, C.grey, "RIGHT")
    r.right:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    if opts.midX then
      r.mid = text(r, C.grey, "LEFT")
      r.mid:SetPoint("LEFT", r, "LEFT", opts.midX, 0)
      r.mid:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    end
    r:SetScript("OnClick", function(row, btn)
      if row.data and not row.data.header and opts.onClick then opts.onClick(row.data, btn, row) end
    end)
    r:SetScript("OnEnter", function(row)
      if not row.data then return end
      if not row.data.header then row.hover:Show() end
      if row.data.item and A.Window then A.Window.ItemTooltip(row, row.data.item, row.data.tip)
      elseif row.data.tip and A.Window then A.Window.TextTooltip(row, row.data.tip) end
    end)
    r:SetScript("OnLeave", function(row)
      row.hover:Hide()
      local tip = rawget(_G, "GameTooltip")
      if type(tip) == "table" and tip.Hide then tip:Hide() end
    end)
    self.rows[i] = r
  end
  return self
end

function List:SetData(data, emptyText)
  self.data = data or {}
  self.emptyText = emptyText
  local max = math.max(0, #self.data - self.opts.rows)
  if self.offset > max then self.offset = max end
  self:Render()
end

function List:Scroll(by)
  local max = math.max(0, #self.data - self.opts.rows)
  local to = math.min(max, math.max(0, self.offset + by))
  if to ~= self.offset then self.offset = to self:Render() end
end

function List:Render()
  local o = self.opts
  for i, r in ipairs(self.rows) do
    local d = self.data[i + self.offset]
    r.data = d
    if d then
      local x = 6 + (d.indent or 0)
      if d.icon then
        r.icon:SetTexture(d.icon)
        r.icon:ClearAllPoints()
        r.icon:SetPoint("LEFT", r, "LEFT", 2 + (d.indent or 0), 0)
        r.icon:Show()
        x = x + o.rowHeight
      else
        r.icon:Hide()
      end
      r.left:ClearAllPoints()
      r.left:SetPoint("LEFT", r, "LEFT", x, 0)
      if r.mid and d.mid and not d.header then
        r.left:SetPoint("RIGHT", r, "LEFT", o.midX - 8, 0)
        r.mid:SetText(d.mid)
        local mc = d.midColor or C.grey
        r.mid:SetTextColor(mc[1], mc[2], mc[3])
        r.mid:Show()
      else
        r.left:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        if r.mid then r.mid:Hide() end
      end
      r.left:SetText(d.text or "")
      local c = d.color or (d.header and C.cyan) or C.cream
      r.left:SetTextColor(c[1], c[2], c[3])
      r.right:SetText(d.right or "")
      local rc = d.rightColor or C.grey
      r.right:SetTextColor(rc[1], rc[2], rc[3])
      if d.selected then r.sel:Show() else r.sel:Hide() end
      r:Show()
    else
      r:Hide()
    end
  end
  if #self.data == 0 and self.emptyText then
    self.empty:SetText(self.emptyText)
    self.empty:Show()
  else
    self.empty:Hide()
  end
  self.shown = math.min(#self.data, o.rows)
end
