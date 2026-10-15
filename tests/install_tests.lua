local core = require("fleet.install_core")
local installer = require("fleet.installer")
local memory = require("memory_fs")
local terminal = require("terminal")
local M = {}
local payloads = { controller = '-- controller\nreturn "controller"\n', worker = '-- worker\nreturn "worker"\n' }
local function prepare(f, role, startup, isTurtle)
  return assert(core.prepare(f.api, payloads, role or "controller", startup ~= false, isTurtle))
end
local function noTemps(f)
  for path in pairs(f.files) do assert(not path:match("^/%.fleet%-"), "Leftover temporary file: " .. path) end
end

local function fixture(isTurtle, color, role, width, height)
  local f = memory.new()
  f.screen = terminal.new(width or (isTurtle and 39 or 26),height or (isTurtle and 13 or 20),color)
  f.app = installer.new(f.screen.api, terminal.keys, {fs=f.api,payloads=payloads,isTurtle=isTurtle,role=role})
  function f.render()
    f.app.render()
    local occupied = {}
    for _,w in ipairs(f.app.gui.widgets) do
      assert(w.x>=1 and w.y>=1 and w.x+w.width-1<=f.app.gui.size and w.y+w.height-1<f.screen.height,
        "Installer control outside display: "..w.id)
      if w.label then assert(#w.label<=w.width-2,"Clipped installer button: "..w.label) end
      for y=w.y,w.y+w.height-1 do for x=w.x,w.x+w.width-1 do
        local cell=x..":"..y
        assert(not occupied[cell],"Overlapping installer control: "..w.id)
        occupied[cell]=true
      end end
    end
  end
  function f.event(...) f.app.event(...); f.render() end
  function f.activate(id)
    for _=1,#f.app.gui.widgets+1 do
      if f.app.gui.focus==id then f.event("key",terminal.keys.enter); return end
      f.event("key",terminal.keys.tab)
    end
    error("Cannot focus "..id)
  end
  function f.click(id)
    local w=assert(f.app.gui.find(id))
    f.event("mouse_click",1,f.app.gui.left+w.x,w.y)
  end
  f.render()
  return f
end

function M.run(test,equal)
  test("installer source: missing generated payload gives ready-to-copy file instructions",function()
    local requested = {}
    local env=setmetatable({require=function(name)
      requested[#requested+1]=name
      error("module '"..name.."' not found")
    end}, {__index=_G})
    local ok,why=pcall(assert(loadfile(PROJECT_ROOT.."/src/installer_main.lua","t",env)))
    assert(not ok and why:find("Copy install.lua from the project root or dist/",1,true))
    equal(#requested,1); equal(requested[1],"fleet.payloads")
  end)
  test("installer: fresh controller installs from embedded payload with startup",function()
    local f=memory.new(); local result=assert(core.apply(f.api,prepare(f)))
    equal(f.files["/fleet.lua"],payloads.controller); equal(f.files[core.STARTUP],core.LAUNCHER)
    equal(result.backup,nil); equal(result.startup,true); noTemps(f)
  end)
  test("installer: worker requires a turtle and invalid payload never writes",function()
    local f=memory.new()
    assert(not core.prepare(f.api,payloads,"worker",true,false))
    assert(not core.prepare(f.api,{controller="not valid lua !!!"},"controller",true,false))
    equal(f.mutations,0)
    assert(core.apply(f.api,prepare(f,"worker",false,true)))
    equal(f.files["/fleet.lua"],payloads.worker); assert(not f.api.exists("/startup"))
  end)
  test("installer: updates use unique backups and keep settings and other programs",function()
    local f=memory.new(); f.files["/fleet.lua"]="old"; f.files["/fleet.lua.backup"]="older"
    f.files["/.fleet-worker"]="settings"; f.files["/startup.lua"]="custom startup"; f.files["/other.lua"]="other"
    local result=assert(core.apply(f.api,prepare(f)))
    equal(result.backup,"/fleet.lua.backup.1"); equal(f.files[result.backup],"old")
    equal(f.files["/fleet.lua.backup"],"older"); equal(f.files["/.fleet-worker"],"settings")
    equal(f.files["/startup.lua"],"custom startup"); equal(f.files["/other.lua"],"other")
  end)
  test("installer: manual launch removes only a recognized Fleet launcher",function()
    local f=memory.new(); f.directories["/startup"]=true
    f.files[core.STARTUP]='shell.run("/fleet.lua")\n'; f.files["/startup/other.lua"]="custom"
    assert(core.apply(f.api,prepare(f,"controller",false)))
    equal(f.files[core.STARTUP],nil); equal(f.files["/startup/other.lua"],"custom"); noTemps(f)
    f.files[core.STARTUP]="user custom startup"
    assert(core.apply(f.api,prepare(f,"controller",false)))
    equal(f.files[core.STARTUP],"user custom startup")
  end)
  test("installer: custom startup files are preserved and cannot be overwritten",function()
    for _,kind in ipairs({"legacy","custom","directory"}) do
      local f=memory.new()
      if kind=="legacy" then f.files["/startup"]="user startup"
      else f.directories["/startup"]=true
        if kind=="custom" then f.files[core.STARTUP]="custom" else f.directories[core.STARTUP]=true end
      end
      assert(not core.prepare(f.api,payloads,"controller",true,false)); equal(f.mutations,0)
      assert(core.apply(f.api,prepare(f,"controller",false)))
      assert(f.api.exists(kind=="legacy" and "/startup" or core.STARTUP))
    end
  end)
  test("installer: disk space, read-only storage and destination directories fail before writes",function()
    for _,kind in ipairs({"full","readonly","directory"}) do
      local f=memory.new()
      if kind=="full" then f.free=1 elseif kind=="readonly" then f.readOnly=true else f.directories["/fleet.lua"]=true end
      assert(not core.prepare(f.api,payloads,"controller",true,false)); equal(f.mutations,0)
    end
  end)
  test("installer: changed files invalidate a reviewed installation",function()
    local f=memory.new(); f.files["/fleet.lua"]="old"
    local plan=prepare(f); f.files["/fleet.lua"]="changed"
    assert(not core.apply(f.api,plan)); equal(f.files["/fleet.lua"],"changed"); equal(f.mutations,0)
  end)
  test("installer: corrupt or failed staging writes leave the installed program intact",function()
    for _,kind in ipairs({"corrupt","write","open"}) do
      local f=memory.new(); f.files["/fleet.lua"]="old"
      local plan=prepare(f)
      if kind=="corrupt" then f.corruptWrite=true else
        f.fail=function(op,path,mode) if op==kind and path:find("install.tmp",1,true) then error("simulated staging failure") end end
      end
      assert(not core.apply(f.api,plan)); equal(f.files["/fleet.lua"],"old"); noTemps(f)
    end
  end)
  test("installer: program replacement failure restores the backup",function()
    local f=memory.new(); f.files["/fleet.lua"]="old"
    local plan=prepare(f)
    f.fail=function(op,path,target) if op=="move" and path:find("install.tmp",1,true) then error("simulated rename failure") end end
    assert(not core.apply(f.api,plan)); equal(f.files["/fleet.lua"],"old")
    equal(f.files[plan.backup],nil); noTemps(f)
  end)
  test("installer: failed startup installation restores both existing files",function()
    local f=memory.new(); f.files["/fleet.lua"]="old"; f.directories["/startup"]=true
    f.files[core.STARTUP]='shell.run("/fleet.lua")\n'
    local plan=prepare(f)
    f.fail=function(op,path,target) if op=="move" and path:find("startup.tmp",1,true) then error("simulated startup failure") end end
    assert(not core.apply(f.api,plan)); equal(f.files["/fleet.lua"],"old")
    equal(f.files[core.STARTUP],'shell.run("/fleet.lua")\n'); noTemps(f)
  end)
  test("installer: recovery failures report the backup location without deleting it",function()
    local f=memory.new(); f.files["/fleet.lua"]="old"; local plan=prepare(f)
    f.fail=function(op,path,target) if op=="move" and target=="/fleet.lua" then error("blocked rename") end end
    local result,why=core.apply(f.api,plan)
    assert(not result and why:find("Recovery needed",1,true) and why:find(plan.backup,1,true))
    equal(f.files[plan.backup],"old")
  end)
  test("installer GUI: recommends controller, supports clicks, and cancels without writes",function()
    local f=fixture(false,true); equal(f.app.gui.focus,"controller")
    assert(not f.app.gui.find("worker").enabled)
    f.click("controller"); f.click("next"); equal(f.app.page,"review"); equal(f.mutations,0)
    f.click("back"); f.click("back"); f.click("back"); equal(f.app.running,false); equal(f.mutations,0)
  end)
  test("installer GUI: basic turtle can install and launch using only the keyboard",function()
    local f=fixture(true,false); equal(f.app.gui.focus,"worker")
    f.activate("worker"); f.activate("startup"); f.activate("next"); f.activate("next")
    equal(f.app.page,"done"); equal(f.files["/fleet.lua"],payloads.worker)
    equal(f.files[core.STARTUP],nil)
    f.activate("next"); equal(f.app.launch,true)
  end)
  test("installer GUI: existing legacy startup defaults to manual with visible explanation",function()
    local f=fixture(false,true); f.files["/startup"]="keep me"
    f.click("controller"); equal(f.app.startup,false)
    assert(not f.app.gui.find("startup").enabled)
    assert(f.screen.text():find("/startup",1,true))
    f.click("next"); f.click("next"); equal(f.app.page,"done"); equal(f.files["/startup"],"keep me")
  end)
  test("installer GUI: complete mouse and keyboard flows fit real device dimensions",function()
    for _,size in ipairs({{39,13},{26,20},{51,19},{26,19},{26,13},{39,18}}) do
      for _,isTurtle in ipairs({true,false}) do for _,mouse in ipairs({true,false}) do
        local f=fixture(isTurtle,mouse,nil,size[1],size[2])
        assert(not f.app.tooSmall,"Supported device rejected: "..size[1].."x"..size[2])
        local action=mouse and f.click or f.activate
        local role=isTurtle and "worker" or "controller"
        action(role); equal(f.app.page,"options")
        action("next"); equal(f.app.page,"review"); equal(f.mutations,0)
        assert(f.screen.text():find("Program: /fleet.lua",1,true))
        action("back"); action("next"); action("next")
        equal(f.app.page,"done"); equal(f.files["/fleet.lua"],payloads[role])
        assert(f.screen.text():find("Run: fleet",1,true))
        action("details"); equal(f.app.page,"message")
        for _=1,10 do if not f.app.gui.find("next") then break end; action("next") end
        assert(not f.app.gui.find("next"),"Install details did not reach last page")
        action("back"); action("next"); equal(f.app.launch,true)
      end end
    end
  end)
  test("installer GUI: compact startup conflicts and failure reasons remain readable",function()
    for _,mouse in ipairs({false,true}) do
      local f=fixture(true,mouse); local action=mouse and f.click or f.activate
      f.directories["/startup"]=true; f.files[core.STARTUP]="custom startup"
      action("worker"); equal(f.app.startup,false)
      assert(not f.app.gui.find("startup").enabled)
      action("setupDetails"); equal(f.app.page,"message")
      assert(f.screen.text():find("/startup/fleet.lua",1,true))
      action("back"); equal(f.app.page,"options")
      f.free=0; action("next"); equal(f.app.page,"message"); equal(f.mutations,0)
      assert(f.screen.text():find("Not enough free space",1,true))
      action("back"); f.free=2000000; action("next")
      f.fail=function(op) if op=="write" then error(string.rep("Deliberately long disk error. ",20)) end end
      action("next"); equal(f.app.page,"message")
      assert(f.app.gui.find("next"),"Long error should be paginated")
      action("next"); equal(f.app.messagePage,2)
      action("back"); equal(f.app.page,"options")
    end
  end)
  test("installer GUI: resizing retains the reviewed choice and disables hidden actions",function()
    local f=fixture(true,false)
    f.activate("worker"); f.activate("startup"); f.activate("next")
    equal(f.app.page,"review"); equal(f.app.startup,false)
    f.screen.resize(26,20); f.event("term_resize"); equal(f.app.page,"review")
    f.screen.resize(39,12); f.event("term_resize")
    assert(f.app.tooSmall); equal(#f.app.gui.widgets,0)
    f.event("key",terminal.keys.enter); equal(f.mutations,0)
    f.screen.resize(39,13); f.event("term_resize"); assert(not f.app.tooSmall)
    equal(f.app.role,"worker"); equal(f.app.startup,false)
    f.activate("next"); equal(f.app.page,"done"); equal(f.files[core.STARTUP],nil)
  end)
end

function M.bundle(role, path, mouse)
  local isTurtle=role=="worker"
  local f=memory.new(); local screen=terminal.new(isTurtle and 39 or 26,isTurtle and 13 or 20,mouse or not isTurtle)
  local events={{"key",terminal.keys.enter}}
  for _=1,isTurtle and 3 or 2 do events[#events+1]={"key",terminal.keys.tab} end
  for _,key in ipairs({"enter","tab","enter","tab","tab","enter"}) do events[#events+1]={"key",terminal.keys[key]} end
  local clicks={isTurtle and "Turtle Worker" or "Controller","Next","Install","Launch"}
  local launched
  local env=setmetatable({fs=f.api,term=screen.api,keys=terminal.keys,
    turtle=role=="worker" and {} or nil,colors={black=32768,white=1},
    require=function(name) error("External dependency: "..name) end,
    shell={run=function(path) launched=path end},print=function() end,
    os={pullEvent=function()
      if mouse then
        local label=table.remove(clicks,1); assert(label,"Installer stalled")
        for y=screen.height,1,-1 do
          local x=screen.rows[y].text:find(label,1,true)
          if x then return "mouse_click",1,x,y end
        end
        error("Missing installer button: "..label)
      end
      local event=table.remove(events,1); assert(event,"Installer stalled"); return table.unpack(event)
    end}}, {__index=_G})
  assert(loadfile(PROJECT_ROOT.."/"..(path or "dist/install.lua"),"t",env))()
  local expected=assert(io.open(PROJECT_ROOT.."/dist/fleet-"..role..".lua","r"))
  local source=expected:read("*a"); expected:close()
  assert(f.files["/fleet.lua"]==source,"Embedded payload differs from release file")
  assert(launched=="/fleet.lua","Launch button did not start Fleet")
  assert(f.files[core.STARTUP]==core.LAUNCHER)
end
return M
