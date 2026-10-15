local resolution=require("orbit.resolution")
local desktop=require("orbit.desktop")
local surface=require("orbit.surface")
local terminal=require("terminal")
local M={}
function M.run(test,equal)
  local function fixture(w,h,color,async)
    local screen=terminal.new(w,h,color); local current=screen.api
    local hnd={screen=screen,time=0,calls={},saved={w,h}}
    local info={apiVersion=1,kind=w==26 and "pocket" or "computer",width=w,height=h,defaultWidth=w,defaultHeight=h,
      minWidth=26,maxWidth=160,minHeight=13,maxHeight=60,remaining=0}
    local function response() if async then coroutine.yield("task_complete") end end
    local function size(a,b) info.width,info.height=a,b end
    local api={getInfo=function() response(); local copy={}; for k,v in pairs(info) do copy[k]=v end; return copy end,
      preview=function(a,b)
        hnd.calls[#hnd.calls+1]={a,b}; info.preview="token"; info.remaining=15; size(a,b); response(); return "token"
      end,
      keep=function(token) equal(token,info.preview); response(); if hnd.fail then error("Disk full") end
        hnd.saved={info.width,info.height}; info.preview=nil; return true end,
      revert=function(token) equal(token,info.preview); info.preview=nil; size(table.unpack(hnd.saved)); response(); return true end}
    local opts={resolutionApi=api,keys=terminal.keys,now=function() return hnd.time end,
      term={current=function() return current end,redirect=function(t) local old=current; current=t; return old end}}
    hnd.app=resolution.new(screen.api,opts); hnd.info=info
    function hnd.pump() for _=1,8 do if hnd.app.process then hnd.app.event("task_complete") end end end
    function hnd.press(id,mouse)
      for _=1,12 do
        hnd.app.render()
        for _,widget in ipairs(hnd.app.p.gui.widgets) do if widget.id==id then
          if mouse then hnd.app.event("mouse_click",1,hnd.app.p.gui.left+widget.x-1,widget.y)
          else hnd.app.p.gui.focus=id; hnd.app.event("key",terminal.keys.enter) end
          return
        end end
        hnd.app.p.gui.focus="next"; hnd.app.event("key",terminal.keys.enter)
      end
      error("Missing resolution control: "..id)
    end
    return hnd,opts
  end
  test("Resolution: mouse and keyboard presets, keep, default and custom sizes at native device sizes",function()
    for _,case in ipairs({{26,20,false},{51,19,true},{38,13,true},{80,30,true}}) do
      local h=fixture(table.unpack(case)); h.press("balanced",case[3]); equal(h.calls[1][1],case[1]==26 and 40 or 80)
      h.app.render(); h.press("keep",case[3]); equal(h.saved[2],30); assert(not h.app.token)
      h.press("default"); h.press("revert"); equal(h.info.height,30)
      h.press("custom"); h.app.width="74"; h.app.height="28"; h.press("preview"); h.press("keep")
      equal(h.saved[1],74); equal(h.saved[2],28)
    end
  end)
  test("Resolution: invalid dimensions, save failures, expiry and closing previews recover",function()
    local h=fixture(26,20,false)
    h.press("custom"); h.app.width="500"; h.app.height="20"; h.press("preview"); equal(#h.calls,0)
    h.app.width="40.5"; h.press("preview"); equal(#h.calls,0)
    h.app.width="40"; h.press("preview"); h.fail=true; h.press("keep"); assert(h.app.token and h.app.message:find("Disk full"))
    h.info.preview=nil; h.info.width,h.info.height=26,20; h.time=16; h.app.tick()
    assert(not h.app.token); equal(h.app.page,"home"); assert(h.app.message:find("restored"))
    h.press("space"); h.app.close(); equal(h.info.preview,nil); equal(h.info.width,26)
  end)
  test("Resolution: asynchronous API work yields without swallowing background OS events",function()
    local h=fixture(51,19,true,true); assert(h.app.process)
    h.app.event("rednet_message",5,{},"fleet"); assert(h.app.process)
    h.pump(); h.press("balanced",true); assert(h.app.process and not h.app.token)
    h.pump(); equal(h.app.token,"token"); h.press("keep"); h.pump(); equal(h.saved[1],80)
    h.app.render(); assert(h.screen.text():find("Resolution saved"))
  end)
  test("Resolution: missing or incompatible companion displays installation guidance",function()
    local h,o=fixture(26,20,false); o.resolutionApi=nil; local app=resolution.new(h.screen.api,o)
    app.render(); assert(h.screen.text():find("Install Orbit Display"))
    o.resolutionApi={getInfo=function() return {apiVersion=2} end,preview=function() end,keep=function() end,revert=function() end}
    app=resolution.new(h.screen.api,o); assert(app.message:find("compatible")); app.render()
  end)
  test("Resolution: desktop resizes before drawing and preserves apps when the resize event is missed",function()
    local screen=terminal.new(80,30,true); local events=0
    local def={id="demo",title="Demo",create=function(t) return {render=function() surface.text(t,1,1,"Alive") end,
      event=function(event) if event=="term_resize" then events=events+1 end end} end}
    local manager=desktop.new(screen.api,terminal.keys,{apps={def}}); local app=manager.open(def)
    screen.resize(26,20); manager.render(); assert(app.full); equal(manager.width,26); assert(events>0)
    screen.resize(100,36); manager.render(); equal(manager.height,36); equal(#manager.windows,1)
  end)
end
return M
