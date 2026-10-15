local surface=require("orbit.surface")
local desktop=require("orbit.desktop")
local cast=require("orbit.cast")
local update=require("orbit.update")
local sha=require("orbit.sha256")
local task=require("orbit.task")
local panel=require("orbit.panel")
local terminal=require("terminal")
local memory=require("memory_fs")
local M={}
local keys={}; for k,v in pairs(terminal.keys) do keys[k]=v end
for i=1,10 do keys["f"..i]=58+i end
M.keys=keys
local function release(source,version)
  return {source=source,manifest={format=1,product="orbit-os",artifact="orbit.lua",version=version or "0.1.0",size=#source,sha256=sha.digest(source)}}
end
local function monitor(w,h,color)
  local t=terminal.new(w,h,color)
  t.api.write=function(value) t.api.blit(value,string.rep("0",#value),string.rep("f",#value)) end
  return {name="monitor_0",width=w,height=h,color=color~=false,term=t.api},t
end
local function runtime(screen)
  local current=screen
  return {current=function() return current end,redirect=function(t) local old=current; current=t; return old end}
end
function M.run(test,equal)
  test("Orbit surface: clipping, scrolling, colours and resizing preserve terminal semantics",function()
    local s=surface.new(8,4,true); local t=s.term
    t.setCursorPos(-1,1); t.write("abcdef"); equal(t.getLine(1),"cdef    ")
    t.setCursorPos(7,2); t.blit("abcdef","012345","fedcba"); equal(t.getLine(2),"      ab")
    t.scroll(1); equal(t.getLine(1),"      ab")
    s.resize(5,2); equal(t.getLine(1),"     "); equal(s.frame().width,5)
    t.setPaletteColor(2,0x123456); local r,g,b=t.getPaletteColor(2); assert(r>0 and b>g)
    assert(not pcall(t.blit,"x","qq","0"))
  end)
  test("Orbit desktop: move, resize, focus, minimize, restore and close",function()
    local screen=terminal.new(51,19,true)
    local events={}; local renders=0
    local definition={id="demo",title="Demo",create=function(display)
      return {render=function() renders=renders+1; surface.text(display,1,1,"Hello") end,
        event=function(...) events[#events+1]={...} end}
    end}
    local d=desktop.new(screen.api,keys,{apps={definition}}); local a=d.open(definition); local b=d.open(definition)
    d.event("mouse_click",1,b.x+1,b.y); d.event("mouse_drag",1,b.x+5,b.y+1); d.event("mouse_up",1,1,1)
    equal(b.x,7); equal(b.y,4)
    local oldWidth=b.w; d.event("mouse_click",1,b.x+b.w-1,b.y+b.h-1)
    d.event("mouse_drag",1,b.x+b.w-4,b.y+b.h-2); d.event("mouse_up",1,1,1)
    equal(b.w,oldWidth-3)
    d.event("mouse_click",1,b.x+2,b.y+2); local e=events[#events]; equal(e[3],3); equal(e[4],2)
    d.event("key",keys.f2); equal(d.focused,a.id)
    d.event("key",keys.f3); assert(a.full); d.render()
    assert(renders>=2,"Background window did not render")
    d.event("mouse_click",1,50,1); assert(d.launcher)
    d.launcher=false; d.event("key",keys.f3); assert(not a.full)
    d.event("mouse_click",1,a.x+a.w-5,a.y); assert(a.hidden and d.launcher)
    d.focus(a.id); assert(not a.hidden)
    d.event("key",keys.f10); equal(#d.windows,1)
  end)
  test("Orbit desktop: basic keyboard geometry, real device sizes and background events",function()
    for _,size in ipairs({{51,19},{26,20},{39,13},{80,30}}) do
      local screen=terminal.new(size[1],size[2],false); local events={}; local ticks=0
      local def={id="demo",title="Demo",create=function(t) return {render=function() surface.text(t,1,1,"Demo") end,
        tick=function() ticks=ticks+1 end,event=function(...) events[#events+1]={...} end} end}
      local d=desktop.new(screen.api,keys,{apps={def}}); local a=d.open(def); local b=d.open(def)
      d.event("key",keys.f4); d.event("key",keys.left); d.event("key",keys.enter)
      d.event("key",keys.f5); d.event("key",keys.left); d.event("key",keys.enter)
      d.tick(); equal(ticks,2)
      d.event("modem_message","left",10,11,"payload",6); equal(events[#events][5],"payload"); equal(events[#events][6],6)
      d.render(); assert(a.surface.width>=26 and b.surface.height>=10)
      screen.resize(26,20); d.event("term_resize"); d.render(); assert(a.full and b.full)
      d.stop(); equal(#d.windows,0)
    end
  end)
  test("Orbit panel: all controls fit short forms and page through keyboard fields",function()
    for _,size in ipairs({{26,10},{26,20},{39,13},{38,12}}) do
      local screen=terminal.new(size[1],size[2],false); local p=panel.new(screen.api,keys); local value=""
      local items={{field=true,id="value",label="Value",value=value,change=function(v) value=v end}}
      for i=1,10 do items[#items+1]={id=tostring(i),label="Button "..i} end
      local seen={}
      for _=1,15 do
        p.draw("Form","Test",items)
        for _,w in ipairs(p.gui.widgets) do
          assert(w.y+w.height-1<screen.height and w.x+w.width-1<=screen.width); seen[w.id]=true
        end
        p.gui.focus="next"; p.event("key",keys.enter)
      end
      for i=1,10 do assert(seen[tostring(i)],"Paged control never visible") end
    end
  end)
  test("Orbit tasks: terminal redirects, event filters and app failures are isolated",function()
    local a=surface.new(26,10,true); local b=surface.new(26,10,true); local termApi=runtime(b.term)
    local process=task.new(function()
      surface.text(termApi.current(),1,1,"First")
      local event=coroutine.yield("timer"); equal(event,"timer")
      surface.text(termApi.current(),1,2,"Second")
      error("App error")
    end,a.term,termApi)
    equal(termApi.current(),b.term); process.event("key",1); assert(not process.done)
    process.event("timer",3); assert(process.done and process.error:find("App error")); equal(termApi.current(),b.term)
    assert(a.term.getLine(2):find("Second")); assert(not b.term.getLine(1):find("First"))
  end)
  test("Orbit SHA-256: standard vectors and block padding",function()
    equal(sha.digest(""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    equal(sha.digest("abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    equal(sha.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  end)
  test("Orbit update: local manifests, checksums, backups and rollback preserve settings",function()
    local f=memory.new(); f.directories["/disk"]=true; f.directories["/disk/orbit-release"]=true
    local r=release("return 'new'","0.2.0"); f.files["/disk/orbit-release/manifest.json"]="manifest"
    f.files["/disk/orbit-release/orbit.lua"]=r.source; f.files["/orbit.lua"]="return 'old'"; f.files["/.fleet-controller"]="settings"
    local ready=update.check("/disk/orbit-release","0.1.0",f.api,nil,function() return r.manifest end)
    local backup=update.apply(f.api,ready)
    equal(f.files[backup],"return 'old'"); equal(f.files["/orbit.lua"],r.source); equal(f.files["/.fleet-controller"],"settings")
    local newer=update.rollback(f.api,backup); equal(f.files["/orbit.lua"],"return 'old'"); equal(f.files[newer],r.source)
    r.source="return 'tampered'"; assert(not pcall(update.apply,f.api,r)); equal(f.files["/orbit.lua"],"return 'old'")
  end)
  test("Orbit update: malformed releases and failed writes never replace the current OS",function()
    for _,kind in ipairs({"size","hash","path","version","lua","full","readonly","write","move"}) do
      local f=memory.new(); f.files["/orbit.lua"]="return 'old'"; local r=release("return 'new'")
      if kind=="size" then r.manifest.size=0 elseif kind=="hash" then r.manifest.sha256=string.rep("0",64)
      elseif kind=="path" then r.manifest.artifact="../startup.lua" elseif kind=="version" then r.manifest.version="nan"
      elseif kind=="lua" then r=release("not a Lua program !") elseif kind=="full" then f.free=0
      elseif kind=="readonly" then f.readOnly=true
      else f.fail=function(op,path) if op==kind and path:find("staging",1,true) then error("Injected failure") end end end
      assert(not pcall(update.apply,f.api,r),"Accepted invalid update: "..kind)
      equal(f.files["/orbit.lua"],"return 'old'")
    end
  end)
  test("Orbit update: GitHub raw URL normalization and bounded HTTP reads",function()
    local requested,closed={},0
    local http={get=function(req)
      requested[#requested+1]=req.url
      local content="payload"
      return {read=function(n) if #content==0 then return nil end; local s=content:sub(1,n); content=content:sub(n+1); return s end,
        close=function() closed=closed+1 end}
    end}
    equal(update.fetch("https://github.com/user/repo/blob/main/release/manifest.json","orbit.lua",{},http),"payload")
    equal(requested[1],"https://raw.githubusercontent.com/user/repo/main/release/orbit.lua"); equal(closed,1)
    http.get=function() return {read=function() return string.rep("x",17000) end,close=function() closed=closed+1 end} end
    assert(not pcall(update.fetch,"https://example.invalid/release","manifest.json",{},http)); equal(closed,2)
    assert(not pcall(update.fetch,"http://example.invalid","orbit.lua",{},http))
  end)
  test("Orbit startup: staging and backups stay outside the startup directory",function()
    local f=memory.new(); f.directories["/startup"]=true; f.files["/startup/orbit.lua"]="old launcher"
    local backup=update.replace(f.api,"/startup/orbit.lua","new launcher","/.orbit-startup.backup","/.orbit-startup.staging")
    equal(backup,"/.orbit-startup.backup"); equal(f.files[backup],"old launcher")
    equal(#f.api.list("/startup"),1)
    update.retire(f.api,"/startup/orbit.lua","/.orbit-startup.backup")
    equal(#f.api.list("/startup"),0); equal(f.files["/.orbit-startup.backup.1"],"new launcher")
  end)
  test("Orbit casting: wired and wireless modems open; malformed frames and small monitors fail",function()
    local opened={}
    local p={getNames=function() return {"left","right","monitor_0"} end,hasType=function(n,t) return n~="monitor_0" end}
    equal(cast.open(p,{open=function(n) opened[n]=true end}),2); assert(opened.left and opened.right)
    local f=surface.new(26,19,true).frame(); local m=monitor(20,10,true)
    assert(not cast.paint(m.term,f)); f.rows[1][2]="bad"; assert(not cast.validFrame(f))
    assert(not cast.validFrame({width=255,height=255,rows={}}))
  end)
  test("Orbit casting: discovery, owned receiver, ordered frames, taps and disconnect lease",function()
    local now=0; local queue={}; local tapped={}; local m,screen=monitor(40,22,true)
    local src=surface.new(26,19,true); surface.text(src.term,1,1,"Live app")
    local host,receiver
    host=cast.host({group=function() return "test" end,now=function() return now end,boot="host",monitors=function() return {} end,
      frame=function(id) if id==5 then return src.frame() end end,input=function(...) tapped[#tapped+1]={...} end,
      send=function(id,msg) queue[#queue+1]={to=id,from=42,msg=msg} end,
      broadcast=function(msg) queue[#queue+1]={to=7,from=42,msg=msg} end})
    receiver=cast.receiver({group=function() return "test" end,owner=function() return 42 end,touch=function() return true end,
      label="Workshop",now=function() return now end,monitors=function() return {m} end,
      send=function(id,msg) queue[#queue+1]={to=id,from=7,msg=msg} end})
    local function deliver()
      for _=1,100 do local p=table.remove(queue,1); if not p then return end
        if p.to==42 then host.receive(p.from,p.msg) else receiver.receive(p.from,p.msg) end
      end; error("Packet loop")
    end
    host.tick(); deliver(); local targets=host.targets(); equal(#targets,1)
    assert(host.start(targets[1],5,true)); now=2; host.tick(); deliver(); host.tick(); deliver()
    assert(screen.text():find("Live app",1,true)); local s=receiver.streams.monitor_0; assert(s)
    receiver.event("monitor_touch","monitor_0",s.placement.x,s.placement.y); deliver(); equal(tapped[1][1],5)
    equal(tapped[1][2],1); equal(tapped[1][3],1)
    local seq=s.seq
    receiver.receive(99,{version=1,group="test",kind="stop",stream=s.token,monitor="monitor_0"}); assert(receiver.streams.monitor_0)
    receiver.receive(42,{version=1,group="test",kind="frame",stream=s.token,monitor="monitor_0",seq=seq-1,frame=src.frame()}); equal(s.seq,seq)
    receiver.event("monitor_resize","monitor_0"); assert(not s.placement)
    now=11; receiver.tick(); assert(not receiver.streams.monitor_0); assert(screen.text():find("disconnected"))
  end)
  test("Orbit casting: local monitor maps taps and detachment does not stop the desktop",function()
    local now=1; local tapped=0; local m,screen=monitor(40,22,false); local connected=true
    local s=surface.new(26,19,true); surface.text(s.term,1,1,"Fleet",32,2048)
    local host=cast.host({group=function() return "test" end,now=function() return now end,boot="host",send=function() end,broadcast=function() end,
      monitors=function() return connected and {m} or {} end,frame=function() return s.frame() end,input=function() tapped=tapped+1 end})
    local target=host.targets()[1]; assert(host.start(target,1,true)); host.tick()
    local p=host.streams[target.key].placement; host.touch(m.name,p.x,p.y); equal(tapped,1)
    host.touch(m.name,1,1); equal(tapped,1)
    connected=false; now=4; host.tick(); equal(host.streams[target.key].status,"Monitor detached")
    connected=true; now=7; host.tick(); equal(host.streams[target.key].status,"Live")
    host.stopAll(); assert(screen.text():find("Cast stopped")); equal(next(host.streams),nil)
  end)
  test("Orbit casting: auto-fit uses the largest readable scale and restores it if no fit is possible",function()
    local screen=terminal.new(40,20,true); local t=screen.api; local scale=1; local changes=0
    t.getTextScale=function() return scale end
    t.setTextScale=function(value) scale=value; changes=changes+1; screen.resize(math.floor(40/value),math.floor(20/value)) end
    local src=surface.new(51,19,true)
    assert(cast.paint(t,src.frame())); equal(scale,0.5); equal(changes,1)
    assert(cast.paint(t,src.frame())); equal(changes,1)
    t.setTextScale(1); local huge=surface.new(100,30,true)
    assert(not cast.paint(t,huge.frame())); equal(scale,1)
    t.setTextScale=function() error("Monitor detached") end
    assert(not cast.paint(t,src.frame()))
  end)
end

-- Exercise the actual standalone installer without source modules or companion files.
function M.installBundle()
  for _,size in ipairs({{51,19},{26,20},{39,13}}) do
    local f=memory.new(); local screen=terminal.new(size[1],size[2],true)
    local phase=1
    local env=setmetatable({fs=f.api,term=screen.api,keys=keys,colors={black=32768,white=1},
      require=function(name) error("External installer dependency: "..name) end,print=function() end,
      os={pullEvent=function()
        if phase==1 then
          for y,row in ipairs(screen.rows) do local x=row.text:find("Install Orbit OS",1,true)
            if x then phase=2; return "mouse_click",1,x,y end
          end
          -- Short forms page to the install action.
          for y,row in ipairs(screen.rows) do local x=row.text:find("More",1,true); if x then return "mouse_click",1,x,y end end
          error("No install button")
        end
        return "key",keys.escape
      end}}, {__index=_G})
    assert(loadfile(PROJECT_ROOT.."/install-os.lua","t",env))()
    local expected=assert(io.open(PROJECT_ROOT.."/orbit.lua","r")); local source=expected:read("*a"); expected:close()
    assert(f.files["/orbit.lua"]==source,"Standalone OS installer did not install the release")
  end
end
function M.receiverBundle()
  local computer=terminal.new(51,19,true); local m,screen=monitor(40,22,true)
  local frame=surface.new(26,19,true); surface.text(frame.term,1,1,"Wireless Fleet")
  local packets={}; local f=memory.new(); f.files["/.orbit-receiver"]="saved receiver settings"
  local function packet(kind,body) body=body or {}; body.version=1; body.group="orbit"; body.kind=kind; return body end
  local events={
    {"rednet_message",42,packet("discover"),cast.PROTOCOL},
    {"rednet_message",42,packet("start",{stream="sender:1",monitor=m.name,touch=true}),cast.PROTOCOL},
    {"rednet_message",42,packet("frame",{stream="sender:1",monitor=m.name,seq=1,frame=frame.frame()}),cast.PROTOCOL},
    {"monitor_touch",m.name,8,2}, {"terminate"}}
  local step=0
  local termApi=runtime(computer.api)
  local env=setmetatable({fs=f.api,term=termApi,keys=keys,colors={black=32768,white=1},
    require=function(name) error("External receiver dependency: "..name) end,print=function() end,
    textutils={unserialize=function() return {owner="42",group="orbit",active=true,touch=true} end},
    peripheral={getNames=function() return {"left",m.name} end,
      hasType=function(name,kind) return name=="left" and kind=="modem" or name==m.name and kind=="monitor" end,
      wrap=function() return m.term end},
    rednet={open=function() end,send=function(id,message) packets[#packets+1]={id=id,message=message} end},
    os={getComputerID=function() return 7 end,getComputerLabel=function() return "Receiver" end,clock=function() return 0 end,
      startTimer=function() return 1 end,cancelTimer=function() end,pullEventRaw=function()
        step=step+1
        if step==4 then assert(screen.text():find("Wireless Fleet",1,true),"Actual receiver bundle did not render frame") end
        local event=assert(table.remove(events,1),"Receiver stalled"); return table.unpack(event)
      end}}, {__index=_G})
  assert(loadfile(PROJECT_ROOT.."/orbit.lua","t",env))("receive")
  local touch
  for _,p in ipairs(packets) do if p.message.kind=="touch" then touch=p; break end end
  assert(touch and touch.id==42 and touch.message.x==1 and touch.message.y==1,"Actual receiver did not return touch coordinates")
end
return M
