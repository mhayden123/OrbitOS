-- Filesystem work is separated from the installer GUI for failure-path testing.
local M = {}
M.DESTINATION = "/fleet.lua"
M.STARTUP = "/startup/fleet.lua"
M.LAUNCHER = '-- Turtle Fleet startup launcher\nshell.run("/fleet.lua")\n'

local function readFile(fs, path)
  if not fs.exists(path) then return nil end
  if fs.isDir(path) then error(path .. " is a directory.", 0) end
  local handle, why = fs.open(path, "r")
  if not handle then error(why or "Cannot read " .. path, 0) end
  local ok, value = pcall(handle.readAll)
  handle.close()
  if not ok then error(value, 0) end
  return value
end

function M.managedLauncher(source)
  if not source then return false end
  source = source:gsub("\r\n", "\n")
  return source == M.LAUNCHER or source:match('^%s*shell%.run%("/fleet%.lua"%)%s*$') ~= nil
    or source:match("^%s*shell%.run%('/fleet%.lua'%)%s*$") ~= nil
end

local function unused(fs, base)
  if not fs.exists(base) then return base end
  for i = 1, 999 do
    local path = base .. "." .. i
    if not fs.exists(path) then return path end
  end
  error("Too many installer backup files. Move older backups elsewhere.", 0)
end

function M.inspect(fs)
  local ok, result = pcall(function()
    local info = { startupAvailable = true, existing = fs.exists(M.DESTINATION) }
    if fs.exists("/startup") and not fs.isDir("/startup") then
      info.startupAvailable, info.note = false, "An existing /startup file is kept. Use manual launch."
    elseif fs.exists(M.STARTUP) and (fs.isDir(M.STARTUP) or not M.managedLauncher(readFile(fs, M.STARTUP))) then
      info.startupAvailable, info.note = false, "Your custom /startup/fleet.lua is kept. Manage startup there."
    elseif fs.exists("/startup.lua") then
      info.note = "Your /startup.lua is kept. Avoid adding a second Fleet launcher."
    end
    info.managedStartup = info.startupAvailable and fs.exists(M.STARTUP)
    return info
  end)
  if ok then return result end
  return nil, tostring(result)
end

function M.prepare(fs, payloads, role, startup, isTurtle)
  local ok, result = pcall(function()
    if role ~= "controller" and role ~= "worker" then error("Choose Controller or Turtle Worker.", 0) end
    if role == "worker" and not isTurtle then error("The worker can only be installed on a turtle.", 0) end
    local source = payloads[role]
    if type(source) ~= "string" or #source == 0 then error("Installer is missing the selected program.", 0) end
    local compiled, why = load(source, "@fleet.lua", "t", {})
    if not compiled then error("Bundled program is invalid: " .. tostring(why), 0) end
    local info, problem = M.inspect(fs)
    if not info then error(problem, 0) end
    if startup and not info.startupAvailable then error(info.note, 0) end
    if fs.isReadOnly("/") or fs.isReadOnly(M.DESTINATION) then error("Computer storage is read-only.", 0) end
    local original = readFile(fs, M.DESTINATION)
    local oldStartup = fs.exists("/startup") and fs.isDir("/startup") and not fs.isDir(M.STARTUP)
      and readFile(fs, M.STARTUP) or nil
    local changeStartup = startup and oldStartup ~= M.LAUNCHER or not startup and M.managedLauncher(oldStartup)
    if changeStartup and (fs.isReadOnly("/startup") or fs.isReadOnly(M.STARTUP)) then error("Startup storage is read-only.", 0) end
    local free = fs.getFreeSpace("/")
    if type(free) == "number" and free < #source + #M.LAUNCHER + 1024 then error("Not enough free space to install safely.", 0) end
    return { role = role, source = source, original = original, startup = startup,
      oldStartup = oldStartup, changeStartup = changeStartup, info = info,
      backup = original and unused(fs, M.DESTINATION .. ".backup") or nil }
  end)
  if ok then return result end
  return nil, tostring(result)
end

local function writeVerified(fs, path, source)
  local handle, why = fs.open(path, "w")
  if not handle then error(why or "Cannot write " .. path, 0) end
  local ok, problem = pcall(function() handle.write(source); handle.close() end)
  if not ok then pcall(handle.close); error(problem, 0) end
  if readFile(fs, path) ~= source then error("Written file could not be verified: " .. path, 0) end
end

function M.apply(fs, plan)
  local staged, stagedStartup, savedStartup
  local movedOriginal, installed, movedStartup, installedStartup, madeDirectory = false, false, false, false, false
  local ok, why = pcall(function()
    -- The review must still describe the files we are about to change.
    if readFile(fs, M.DESTINATION) ~= plan.original then error("Installed program changed. Review the installation again.", 0) end
    local info, problem = M.inspect(fs)
    if not info then error(problem, 0) end
    if plan.startup and not info.startupAvailable then error(info.note, 0) end
    if plan.changeStartup then
      if fs.exists("/startup") and not fs.isDir("/startup") then error("Startup changed. Review again.", 0) end
      if readFile(fs, M.STARTUP) ~= plan.oldStartup then error("Startup changed. Review again.", 0) end
    end
    if plan.backup and fs.exists(plan.backup) then error("Backup path changed. Review again.", 0) end
    staged = unused(fs, "/.fleet-install.tmp")
    writeVerified(fs, staged, plan.source)
    if plan.changeStartup and plan.startup then
      stagedStartup = unused(fs, "/.fleet-startup.tmp")
      writeVerified(fs, stagedStartup, M.LAUNCHER)
    end
    if plan.backup then fs.move(M.DESTINATION, plan.backup); movedOriginal = true end
    fs.move(staged, M.DESTINATION); staged, installed = nil, true
    if plan.changeStartup then
      if not fs.exists("/startup") then fs.makeDir("/startup"); madeDirectory = true end
      if plan.oldStartup then
        savedStartup = unused(fs, "/.fleet-startup.backup")
        fs.move(M.STARTUP, savedStartup); movedStartup = true
      end
      if plan.startup then
        fs.move(stagedStartup, M.STARTUP); stagedStartup, installedStartup = nil, true
      end
    end
  end)
  local cleanupWarnings = {}
  local function attempt(action, description)
    local success, failure = pcall(action)
    if not success then cleanupWarnings[#cleanupWarnings + 1] = description .. ": " .. tostring(failure) end
  end
  if not ok then
    -- Restore old files if a filesystem operation fails after installation starts.
    if installedStartup then attempt(function() fs.delete(M.STARTUP) end, "Remove new startup launcher") end
    if movedStartup then attempt(function() fs.move(savedStartup, M.STARTUP) end, "Restore startup from " .. savedStartup) end
    if installed then attempt(function() fs.delete(M.DESTINATION) end, "Remove new program") end
    if movedOriginal then attempt(function() fs.move(plan.backup, M.DESTINATION) end, "Restore program from " .. plan.backup) end
    if madeDirectory then
      attempt(function() if #fs.list("/startup") == 0 then fs.delete("/startup") end end, "Remove empty startup directory")
    end
  elseif savedStartup then
    attempt(function() fs.delete(savedStartup) end, "Remove temporary startup backup")
  end
  for _, path in ipairs({ staged or false, stagedStartup or false }) do
    if path and fs.exists(path) then attempt(function() fs.delete(path) end, "Remove staging file " .. path) end
  end
  if not ok then
    return nil, tostring(why) .. (#cleanupWarnings > 0 and (" Recovery needed: " .. table.concat(cleanupWarnings, "; ")) or " Existing files restored.")
  end
  return { role = plan.role, backup = plan.backup, startup = plan.startup, note = plan.info.note,
    warnings = table.concat(cleanupWarnings, "; ") }
end

return M
