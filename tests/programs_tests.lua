local programs=require("orbit.programs")
local desktop=require("orbit.desktop")
local apps=require("orbit.apps")
local surface=require("orbit.surface")
local keys=require("orbit_tests").keys
local M={}
local function setup(width,height,color)
  local screen=surface.new(width,height,color); local current=screen.term; local dir="/"; local calls={}
  local files={["/hello world.lua"]=true,["/bad.lua"]=true,["/wait.lua"]=true,["/folder/demo.lua"]=true,["/orbit.lua"]=true,["/orbit-before-ui.lua"]=true,["/.secret.lua"]=true,["/notes.txt"]=true}
  local folders={["/"]=true,["/folder"]=true}
  local o={keys=keys,term={current=function() return current end,redirect=function(t) current=t end},fs={}}
  local function parent(p) local value=p:match("^(.*)/[^/]+$"); return value=="" and "/" or value end
  function o.fs.list(path)
    assert(folders[path],"Folder missing")
    local result={}; for p in pairs(files) do if parent(p)==path then result[#result+1]=p:match("[^/]+$") end end
    for p in pairs(folders) do if p~="/" and parent(p)==path then result[#result+1]=p:match("[^/]+$") end end
    return result
  end
  o.fs.isDir=function(path) return folders[path] or false end
  o.shell={dir=function() return dir end,setDir=function(value) dir=value end,
    resolveProgram=function(path) if path=="shell" then return "/rom/programs/shell.lua" elseif files[path] then return path end end,
    execute=function(path)
      calls[#calls+1]=path; current.write("Output: "..path)
      if path=="/bad.lua" then return false end
      if path=="/wait.lua" or path=="/rom/programs/shell.lua" then coroutine.yield("timer"); current.write(" resumed") end
      return true
    end}
  local w={title="Programs",full=width<60 or height<22}; local app=programs.new(screen.term,o,w)
  local function action(id)
    for _=1,30 do
      app.render()
      if app.p.gui.find(id) then app.p.gui.focus=id; app.event("key",keys.enter); app.render(); return end
      app.p.gui.focus="next"; app.event("key",keys.enter)
    end
    error("Control missing: "..id)
  end
  return app,screen,o,w,calls,files,folders,action
end
function M.run(test,equal)
  test("Programs: opening browses without running; files, folders and Terminal are distinct",function()
    for _,size in ipairs({{26,13},{26,20},{40,30},{80,30}}) do for _,color in ipairs({true,false}) do
      local app,screen,o,w,calls,files,folders,action=setup(size[1],size[2],color)
      app.render(); equal(#calls,0); equal(app.page,"browse"); equal(app.entries[1].name,"folder"); equal(#app.entries,4)
      action("file:1"); equal(app.directory,"/folder"); action("file:1"); equal(app.page,"review"); equal(#calls,0)
      action("run"); equal(calls[1],"/folder/demo.lua"); assert(app.process.done)
      app.event("key",keys.enter); app.render(); equal(app.page,"browse"); equal(w.title,"Programs")
      action("up"); equal(app.directory,"/")
      action("terminal"); equal(w.title,"Terminal"); equal(calls[2],"/rom/programs/shell.lua"); assert(not app.process.done)
    end end
  end)
  test("Programs: Enter submits a path once, keeps literal spaces and reports failure",function()
    local app,screen,o,w,calls,files,folders,action=setup(26,20,true)
    action("path"); app.p.gui.focus="path"; app.event("paste","/hello world.lua"); app.render()
    app.event("key",keys.enter,true); equal(#calls,0)
    app.event("key",keys.enter); app.render(); equal(calls[1],"/hello world.lua"); assert(app.process.done)
    app.event("key",keys.f8); equal(#calls,2)
    app.event("key",keys.f7); app.render(); equal(app.page,"browse")
    action("path"); app.path="/bad.lua"; app.render(); app.p.gui.focus="path"; app.event("key",keys.enter); app.render()
    equal(app.process.result,false); assert(screen.term.getLine(20):find("Failed",1,true))
    app.event("mouse_click",1,2,20); app.render(); equal(app.page,"browse")
    action("path"); app.path="/missing.lua"; action("run"); equal(app.page,"error"); equal(#calls,3)
    action("back"); equal(app.page,"path"); equal(app.path,"/missing.lua")
  end)
  test("Programs: running output resizes and stop confirmation preserves background events",function()
    local app,screen,o,w,calls,files,folders,action=setup(40,30,true)
    action("path"); app.path="/wait.lua"; action("run"); assert(not app.process.done)
    screen.resize(26,20); app.event("term_resize"); app.render(); equal(app.output.height,18)
    app.event("key",keys.f7); app.render(); equal(app.page,"stop")
    app.event("timer",42); assert(app.process.done)
    action("keep"); equal(app.page,"process")
    app.event("key",keys.f7); equal(app.page,"browse")
    action("terminal"); app.event("mouse_click",1,2,20); app.render(); equal(app.page,"stop")
    action("stop"); equal(app.page,"browse"); assert(not app.process)
  end)
  test("Programs: removed media and managed entry points produce recoverable notices",function()
    local app,screen,o,w,calls,files,folders,action=setup(40,30,true)
    action("file:1"); folders["/folder"]=nil; action("refresh"); assert(app.scanError)
    action("up"); equal(app.directory,"/"); assert(not app.scanError)
    action("path"); app.path="/orbit.lua"; action("run"); equal(app.page,"error"); equal(#calls,0)
    action("back"); equal(app.page,"path"); app.path="/hello world.lua"; files[app.path]=nil; action("run"); equal(app.page,"error"); equal(#calls,0)
  end)
  test("Orbit UI: program reopens the existing app; maximized windows have mouse restore and close",function()
    for _,size in ipairs({{26,20},{80,30}}) do
      local app,screen,o=setup(size[1],size[2],true)
      local defs=apps.definitions(o); local d=desktop.new(screen.term,keys,{apps=defs})
      local w=d.open(defs[2]); d.event("key",keys.f1); local again=d.open(defs[2]); equal(again.id,w.id); equal(#d.windows,1)
      d.event("key",keys.f1); local box=d.launcherLayout(); d.event("mouse_click",1,box.x+10,box.y+1)
      local _,cards=d.launcherLayout(); equal(#cards,1); equal(cards[1].app.windowId,w.id)
      d.event("mouse_click",1,cards[1].x,cards[1].y); assert(not d.launcher); equal(d.focused,w.id)
      d.event("key",keys.f3); d.render(); assert(w.maximized); assert(w.surface.term._orbitWindowTitle==nil)
      d.event("mouse_click",1,size[1]-13,1); d.render(); assert(not w.maximized)
      if w.full then d.event("mouse_click",1,size[1]-8,1) else d.event("mouse_click",1,w.x+1,w.y) end
      equal(#d.windows,0); d.stop()
    end
  end)
  test("Programs: window Close confirms a running program and forced OS shutdown still exits",function()
    local app,screen,o=setup(80,30,true); local defs=apps.definitions(o); local d=desktop.new(screen.term,keys,{apps=defs})
    local w=d.open(defs[2]); w.app.render(); w.app.page="path"; w.app.path="shell"; w.app.p.reset(); w.app.render()
    w.app.p.gui.focus="run"; w.app.event("key",keys.enter); assert(not w.app.process.done)
    d.event("key",keys.f10); equal(#d.windows,1); equal(w.app.page,"stop")
    w.app.render(); w.app.p.gui.focus="keep"; w.app.event("key",keys.enter); equal(w.app.page,"process")
    d.event("key",keys.f10); w.app.render(); w.app.p.gui.focus="stop"; w.app.event("key",keys.enter); d.tick(); equal(#d.windows,0)
    local second=d.open(defs[2]); second.app.page="path"; second.app.path="shell"; second.app.render(); second.app.p.gui.focus="run"; second.app.event("key",keys.enter)
    d.stop(); equal(#d.windows,0)
  end)
end
return M
