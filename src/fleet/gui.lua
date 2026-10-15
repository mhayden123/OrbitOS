-- Retained focus and editing state over an immediate-mode, cell-based display.
-- Rendering uses term.blit, never print/read, so content cannot scroll the screen.
local M = {}

function M.clean(text)
  return tostring(text or ""):gsub("[%z\1-\31\127-\255]", " ")
end

function M.wrap(text, width)
  local lines, line = {}, ""
  for word in M.clean(text):gmatch("%S+") do
    if #line > 0 and #line + #word + 1 > width then lines[#lines + 1], line = line, "" end
    while #word > width do
      if #line > 0 then lines[#lines + 1], line = line, "" end
      lines[#lines + 1], word = word:sub(1, width), word:sub(width + 1)
    end
    if #word > 0 then line = line == "" and word or line .. " " .. word end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end

function M.new(display, keys)
  local self = { widgets = {}, focus = nil, cursors = {}, shift = false, ctrl = false, previous = {} }
  local fg, bg

  function self.begin(title, subtitle)
    self.width, self.height = display.getSize()
    self.color = display.isColor()
    self.left = math.floor((self.width - math.min(40, self.width)) / 2) + 1
    self.size = math.min(40, self.width)
    self.rows, self.widgets = {}, {}
    for y = 1, self.height do
      self.rows[y] = { text = string.rep(" ", self.width), fg = string.rep("0", self.width), bg = string.rep("f", self.width) }
    end
    self.fill(1, 1, self.size, 1, self.color and "b" or "0")
    self.text(2, 1, title, self.size - 2, self.color and "0" or "f", self.color and "b" or "0")
    self.text(2, 2, subtitle or "", self.size - 2, "8")
    self.text(2, self.height, "Tab/Arrows Enter Esc", self.size - 2, "8")
  end

  local function splice(value, x, text) return value:sub(1, x - 1) .. text .. value:sub(x + #text) end

  function self.text(x, y, text, width, color, background)
    if y < 1 or y > self.height then return end
    local absolute = x + self.left - 1
    local value = M.clean(text):sub(1, math.max(0, math.min(width or self.size, self.size - x + 1)))
    if absolute < 1 then value, absolute = value:sub(2 - absolute), 1 end
    value = value:sub(1, math.max(0, self.width - absolute + 1))
    if #value == 0 then return end
    local row = self.rows[y]
    color = color or "0"
    if not self.color and color ~= "0" and color ~= "7" and color ~= "8" and color ~= "f" then color = "0" end
    row.text = splice(row.text, absolute, value)
    row.fg = splice(row.fg, absolute, string.rep(color, #value))
    if background then row.bg = splice(row.bg, absolute, string.rep(background, #value)) end
  end

  function self.fill(x, y, width, height, color)
    for row = y, y + height - 1 do self.text(x, row, string.rep(" ", width), width, "0", color) end
  end

  function self.paragraph(y, text, count, color)
    for i, line in ipairs(M.wrap(text, self.size - 4)) do
      if i > count then break end
      self.text(3, y + i - 1, line, self.size - 4, color)
    end
  end

  function self.button(id, label, x, y, width, action, options)
    options = options or {}
    self.widgets[#self.widgets + 1] = {
      id = id, label = label, x = x, y = y, width = width, height = options.height or 2,
      action = action or id, enabled = options.enabled ~= false, danger = options.danger,
      sub = options.sub, kind = "button",
    }
  end

  function self.field(id, label, y, value, change, options)
    options = options or {}
    self.text(3, y, label, self.size - 4, "8")
    self.widgets[#self.widgets + 1] = {
      id = id, x = 3, y = y + 1, width = self.size - 4, height = 2,
      value = value, change = change, numeric = options.numeric, max = options.max or 12,
      enabled = true, kind = "field", enter = options.enter,
    }
  end

  function self.footer(backLabel, nextLabel, nextAction, enabled, danger)
    local half = math.floor((self.size - 5) / 2)
    self.button("back", backLabel or "Back", 2, self.height - 2, half, "back")
    if nextLabel then
      self.button("next", nextLabel, 4 + half, self.height - 2, self.size - half - 4,
        nextAction or "next", { enabled = enabled, danger = danger })
    end
  end

  function self.progress(y, done, total)
    local width = self.size - 4
    local filled = total > 0 and math.floor(math.min(1, done / total) * width) or 0
    self.text(3, y, string.rep("#", filled) .. string.rep("-", width - filled), width, self.color and "5" or "0")
  end

  function self.find(id)
    for i, widget in ipairs(self.widgets) do if widget.id == id then return widget, i end end
  end

  function self.moveFocus(amount)
    local _, current = self.find(self.focus)
    current = current or (amount > 0 and 0 or 1)
    for _ = 1, #self.widgets do
      current = (current - 1 + amount) % #self.widgets + 1
      if self.widgets[current].enabled then self.focus = self.widgets[current].id; return end
    end
    self.focus = nil
  end

  function self.finish()
    local focus = self.find(self.focus)
    if not focus or not focus.enabled then self.moveFocus(1) end
    self.cursor = nil
    for _, w in ipairs(self.widgets) do
      local selected = self.focus == w.id
      bg = not w.enabled and "f" or selected and (self.color and "b" or "0") or "7"
      fg = not w.enabled and "8" or selected and not self.color and "f" or "0"
      if w.danger and w.enabled and self.color and not selected then bg = "e" end
      self.fill(w.x, w.y, w.width, w.height, bg)
      if w.kind == "field" then
        local cursor = math.min(self.cursors[w.id] or #w.value, #w.value)
        self.cursors[w.id] = cursor
        local offset = math.max(0, cursor - (w.width - 3))
        self.text(w.x, w.y, selected and ">" or " ", 1, fg, bg)
        self.text(w.x + 1, w.y, w.value:sub(offset + 1), w.width - 2, fg, bg)
        if selected then self.cursor = { x = self.left + w.x + cursor - offset, y = w.y } end
      else
        self.text(w.x, w.y, selected and ">" or " ", 1, fg, bg)
        self.text(w.x + 1, w.y, w.label, w.width - 2, fg, bg)
        if w.sub then self.text(w.x + 1, w.y + 1, w.sub, w.width - 2, fg, bg) end
      end
    end
    display.setCursorBlink(false)
    for y, row in ipairs(self.rows) do
      local signature = row.text .. row.fg .. row.bg
      if self.previous[y] ~= signature then
        display.setCursorPos(1, y)
        display.blit(row.text, row.fg, row.bg)
        self.previous[y] = signature
      end
    end
    for y = self.height + 1, #self.previous do self.previous[y] = nil end
    if self.cursor then display.setCursorPos(self.cursor.x, self.cursor.y); display.setCursorBlink(true) end
  end

  local function insert(w, text)
    text = M.clean(text)
    local pos = self.cursors[w.id] or #w.value
    local updated = w.value:sub(1, pos) .. text .. w.value:sub(pos + 1)
    if #updated > w.max or (w.numeric and not updated:match("^%-?%d*$")) then return end
    w.change(updated)
    self.cursors[w.id] = pos + #text
  end

  function self.event(event, a, b, c)
    local w = self.find(self.focus)
    if event == "term_resize" then self.previous = {}; return end
    if event == "key_up" then
      if a == keys.leftShift or a == keys.rightShift then self.shift = false end
      if a == keys.leftCtrl or a == keys.rightCtrl then self.ctrl = false end
    elseif event == "mouse_click" and a == 1 and self.color then
      local x = b - self.left + 1
      for _, widget in ipairs(self.widgets) do
        if widget.enabled and x >= widget.x and x < widget.x + widget.width
          and c >= widget.y and c < widget.y + widget.height then
          self.focus = widget.id
          if widget.kind == "button" then return widget.action end
          local old = self.cursors[widget.id] or #widget.value
          local offset = math.max(0, old - (widget.width - 3))
          self.cursors[widget.id] = math.max(0, math.min(#widget.value, x - widget.x - 1 + offset))
          return
        end
      end
    elseif event == "key" then
      if b == true and (a == keys.enter or a == keys.numPadEnter or a == keys.space) then return end
      if a == keys.leftShift or a == keys.rightShift then self.shift = true; return end
      if a == keys.leftCtrl or a == keys.rightCtrl then self.ctrl = true; return end
      if a == keys.escape then return "back" end
      if a == keys.tab then self.moveFocus(self.shift and -1 or 1); return end
      if a == keys.up or a == keys.down then self.moveFocus(a == keys.up and -1 or 1); return end
      if w and w.kind == "field" then
        local pos = self.cursors[w.id] or #w.value
        if a == keys.left then self.cursors[w.id] = math.max(0, pos - 1)
        elseif a == keys.right then self.cursors[w.id] = math.min(#w.value, pos + 1)
        elseif a == keys.home then self.cursors[w.id] = 0
        elseif a == keys["end"] then self.cursors[w.id] = #w.value
        elseif a == keys.backspace and pos > 0 then
          w.change(w.value:sub(1, pos - 1) .. w.value:sub(pos + 1)); self.cursors[w.id] = pos - 1
        elseif a == keys.delete then w.change(w.value:sub(1, pos) .. w.value:sub(pos + 2))
        elseif a == keys.u and self.ctrl then w.change(""); self.cursors[w.id] = 0
        elseif a == keys.enter or a == keys.numPadEnter then self.focus = w.enter or "next" end
      elseif a == keys.left or a == keys.right then self.moveFocus(a == keys.left and -1 or 1)
      elseif (a == keys.enter or a == keys.numPadEnter or a == keys.space) and w and w.enabled then return w.action end
    elseif (event == "char" or event == "paste") and w and w.kind == "field" and not self.ctrl then insert(w, a)
    end
  end
  return self
end

return M
