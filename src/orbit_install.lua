-- Build embeds Orbit and its manifest; use install-os.lua from the project root.
local payload=require("orbit.payload")
local update=require("orbit.update")
local panel=require("orbit.panel")
local gui=require("fleet.gui")
local ui=require("fleet.ui")
local restorePalette=require("orbit.theme").preserve(term)
local p=panel.new(term,keys)
local boot,receiver=false,false
local result,message,backup
local function managedStartup(source)
  return source=='-- Orbit OS startup launcher\nshell.run("/orbit.lua")\n' or
    source=='-- Orbit OS startup launcher\nshell.run("/orbit.lua", "receive")\n'
end
local function startup()
  return '-- Orbit OS startup launcher\nshell.run("/orbit.lua"'..(receiver and ', "receive"' or '')..')\n'
end
local function startupAvailable()
  if fs.exists("/startup") and not fs.isDir("/startup") then return false,"Existing /startup file: use manual launch." end
  if fs.exists("/startup/fleet.lua") then return false,"Fleet starts on boot already. Use manual launch or manage startup files." end
  if fs.exists("/startup/orbit.lua") then
    if fs.isDir("/startup/orbit.lua") then return false,"Startup path is a directory." end
    local old=update.read(fs,"/startup/orbit.lua",8192)
    if not managedStartup(old) then return false,"Custom Orbit startup script is preserved." end
  end
  return true
end
local ok,why=pcall(function()
  while true do
    local items={}
    if message then
      local width=term.getSize()
      for _,line in ipairs(gui.wrap(message,math.min(40,width)-2)) do items[#items+1]={text=line} end
      if result then items[#items+1]={id="launch",label="Launch Orbit"} end
      p.draw(result and "ORBIT INSTALLED" or "INSTALL NOTICE","",items,"Done")
    else
      local allowed,note=startupAvailable(); if not allowed then boot=false end
      items={{text="Orbit OS "..payload.manifest.version},{text="Install to /orbit.lua"},
        {id="role",label=receiver and "Role: Display receiver" or "Role: Desktop"},
        {id="boot",label=boot and "[x] Start on boot" or "[ ] Start on boot",enabled=allowed},
        {id="install",label="Install Orbit OS"},{text="Existing OS gets a backup."}}
      if note then for _,line in ipairs(gui.wrap(note,math.min(40,term.getSize())-2)) do items[#items+1]={text=line} end end
      p.draw("INSTALL ORBIT OS","Desktop, Fleet and casting",items,"Quit")
    end
    local a=p.event(os.pullEvent())
    if a=="back" then break
    elseif a=="role" then receiver=not receiver
    elseif a=="boot" then boot=not boot
    elseif a=="install" then
      local installed,problem=pcall(function()
        backup=update.apply(fs,payload)
        if boot then
          assert(startupAvailable()); if not fs.exists("/startup") then fs.makeDir("/startup") end
          update.replace(fs,"/startup/orbit.lua",startup(),"/.orbit-startup.backup","/.orbit-startup.staging")
        elseif fs.exists("/startup/orbit.lua") and not fs.isDir("/startup/orbit.lua") and managedStartup(update.read(fs,"/startup/orbit.lua",8192)) then
          update.retire(fs,"/startup/orbit.lua","/.orbit-startup.backup")
        end
      end)
      if installed then
        result=true; message="Installed /orbit.lua. "..(boot and "Starts on boot. " or "Run orbit"..(receiver and " receive" or "").." to launch. ")..
          (backup and "Previous OS: "..backup..". " or "").."Fleet settings are preserved."
        local config=ui.load("/.orbit-config") or {}; if type(config)~="table" then config={} end
        if backup then config.rollback=backup; ui.save("/.orbit-config",config) end
      else message="Installation needs attention: "..tostring(problem)..". If /orbit.lua was written, run it manually. Settings were kept." end
      p.reset()
    elseif a=="launch" then
      term.clear(); term.setCursorPos(1,1)
      if receiver then shell.run("/orbit.lua","receive") else shell.run("/orbit.lua") end
      break
    end
  end
end)
restorePalette(); term.setCursorBlink(false); term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
if not ok then error(why,0) end
print(result and "Orbit installed. Run orbit to launch." or "Installer closed.")
