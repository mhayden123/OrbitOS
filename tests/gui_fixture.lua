local terminal=require("terminal")
local clientModule=require("fleet.client")
local dashboard=require("fleet.dashboard")
local M={}
function M.new(width,height,color,setup)
  local f={now=0,sent={},broadcasts={},keys=terminal.keys}
  f.screen=terminal.new(width,height,color)
  f.client=clientModule.new({group=not setup and "quarry" or nil,owner=42,boot="controller-boot",now=function() return f.now end,
    send=function(id,group,kind,body) f.sent[#f.sent+1]={id=id,group=group,kind=kind,body=body} end,
    broadcast=function(group,kind) f.broadcasts[#f.broadcasts+1]={group=group,kind=kind} end})
  f.app=dashboard.new(f.screen.api,terminal.keys,{client=f.client,setup=setup,saveGroup=function(value) f.saved=value end})
  function f.status(id,changes)
    local s={version=1,group="quarry",kind="status",session="worker-boot",revision=0,state="idle",reason="",label="Digger "..id,
      owner=42,done=0,total=0,active=false,mining=true,fuel=2400}
    for key,value in pairs(changes or {}) do s[key]=value end
    f.client.receive(id,s)
    return s
  end
  function f.render()
    f.app.render()
    local widgets=f.app.gui.widgets
    for i,a in ipairs(widgets) do
      assert(a.x>=1 and a.y>=1 and a.x+a.width-1<=f.app.gui.size and a.y+a.height-1<=f.screen.height,"Widget outside viewport")
      if a.label then assert(#a.label<=a.width-2,"Clipped button label: "..a.label) end
      for j=i+1,#widgets do local b=widgets[j]
        assert(a.x+a.width<=b.x or b.x+b.width<=a.x or a.y+a.height<=b.y or b.y+b.height<=a.y,"Overlapping widgets: "..a.id.." / "..b.id)
      end
    end
  end
  function f.event(...) f.app.event(...); f.render() end
  function f.focus(id)
    for _=1,#f.app.gui.widgets+1 do
      if f.app.gui.focus==id then return end
      f.event("key",f.keys.tab)
    end
    error("Cannot focus "..id.." on "..f.app.page)
  end
  function f.activate(id)
    f.focus(id); f.event("key",f.keys.enter)
  end
  function f.click(id)
    local w=assert(f.app.gui.find(id),"Missing widget "..id)
    f.event("mouse_click",1,f.app.gui.left+w.x,w.y)
  end
  function f.type(id,value)
    f.focus(id)
    f.event("key",f.keys.leftCtrl); f.event("key",f.keys.u); f.event("key_up",f.keys.leftCtrl)
    f.event("paste",value)
  end
  function f.open()
    f.status(7); f.render(); f.activate("turtle:7"); f.activate("new")
  end
  function f.localJob()
    f.open(); f.activate("quarry"); f.activate("local"); f.activate("next")
    f.type("width","3"); f.type("length","3"); f.type("depth","2")
    f.activate("next"); f.activate("next")
  end
  f.render()
  return f
end
return M
