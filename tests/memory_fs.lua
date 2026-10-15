local M = {}
function M.new()
  local self = { files = {}, directories = { ["/"] = true }, free = 2000000, mutations = 0, closed = 0 }
  local fs = {}
  local function check(operation, path, target)
    if self.fail then self.fail(operation, path, target) end
  end
  local function parent(path) return path:match("^(.*)/[^/]+$") == "" and "/" or path:match("^(.*)/[^/]+$") end
  fs.exists = function(path) return self.files[path] ~= nil or self.directories[path] == true end
  fs.isDir = function(path) return self.directories[path] == true end
  fs.isReadOnly = function() return self.readOnly == true end
  fs.getFreeSpace = function() return self.free end
  fs.list = function(path)
    local names = {}
    for file in pairs(self.files) do if parent(file) == path then names[#names + 1] = file end end
    for dir in pairs(self.directories) do if dir ~= "/" and parent(dir) == path then names[#names + 1] = dir end end
    return names
  end
  fs.makeDir = function(path)
    check("mkdir", path)
    assert(not self.files[path], "Cannot replace file with directory")
    self.directories[path], self.mutations = true, self.mutations + 1
  end
  fs.move = function(path, target)
    check("move", path, target)
    assert(self.files[path] ~= nil, "Missing move source: " .. path)
    assert(not fs.exists(target), "Move destination exists: " .. target)
    assert(self.directories[parent(target)], "Missing target directory")
    self.files[target], self.files[path], self.mutations = self.files[path], nil, self.mutations + 1
  end
  fs.delete = function(path)
    check("delete", path)
    assert(not self.directories[path] or #fs.list(path) == 0, "Refusing nonempty directory delete")
    self.files[path], self.directories[path], self.mutations = nil, nil, self.mutations + 1
  end
  fs.open = function(path, mode)
    check("open", path, mode)
    if mode == "r" then
      if self.files[path] == nil then return nil, "Missing file" end
      return { readAll = function() return self.files[path] end, close = function() self.closed = self.closed + 1 end }
    end
    assert(mode == "w")
    assert(self.directories[parent(path)], "Missing write directory")
    self.files[path], self.mutations = "", self.mutations + 1
    return {
      write = function(source)
        self.files[path] = self.corruptWrite and source:sub(1, #source - 1) or source
        check("write", path)
      end,
      close = function() self.closed = self.closed + 1 end,
    }
  end
  self.api = fs
  return self
end
return M
