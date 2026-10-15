local M = {}

function M.header(title)
  term.clear()
  term.setCursorPos(1, 1)
  print(title)
  local width = term.getSize()
  print(string.rep("-", width))
end

function M.text(label, default)
  print(label .. (default ~= nil and " [" .. tostring(default) .. "]" or ""))
  write("> ")
  local value = read()
  if value == "" and default ~= nil then return tostring(default) end
  return value
end

function M.number(label, default, low, high)
  while true do
    local value = tonumber(M.text(label, default))
    if value and value == value and value % 1 == 0 and value >= low and value <= high then return value end
    print("Whole number: " .. low .. " to " .. high)
  end
end

function M.wait()
  print("Press Enter to continue.")
  read()
end

function M.load(path)
  if not fs.exists(path) then return nil end
  local file = fs.open(path, "r")
  if not file then return nil end
  local value = textutils.unserialize(file.readAll())
  file.close()
  return value
end

function M.save(path, value)
  local file = assert(fs.open(path, "w"), "Cannot save " .. path)
  file.write(textutils.serialize(value))
  file.close()
end

function M.group(default)
  while true do
    local value = M.text("Fleet name", default or "fleet")
    if value:match("^[%w_-]+$") and #value <= 32 then return value end
    print("Use 1-32 letters, digits, - or _.")
  end
end

return M
