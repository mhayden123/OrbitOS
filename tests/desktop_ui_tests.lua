local desktop=require("orbit.desktop")
local panel=require("orbit.panel")
local surface=require("orbit.surface")
local theme=require("orbit.theme")
local terminal=require("terminal")
local keys=require("orbit_tests").keys
local M={}
local function definition(title,id)
  return {id=id or title,title=title,description="Useful tools",create=function(t)
    local app={events={},text=""}
    function app.render() surface.text(t,1,1,"Live app") end
    function app.event(...) app.events[#app.events+1]={...} end
    return app
  end}
end
function M.run(test,equal)
  test("Orbit UI: searchable launcher works with keyboard and clicks at all device sizes",function()
    for _,size in ipairs({{26,20},{39,13},{40,30},{51,19},{80,30},{100,36},{160,60}}) do
      for _,color in ipairs({true,false}) do
        local screen=terminal.new(size[1],size[2],color)
        local defs={definition("Turtle Fleet"),definition("Programs"),definition("Displays"),definition("Updates"),definition("Settings")}
        local d=desktop.new(screen.api,keys,{apps=defs})
        d.render(); d.event("paste","settings"); d.render()
        local _,cards=d.launcherLayout(); equal(#cards,1); equal(cards[1].app.title,"Settings")
        d.event("key",keys.enter,true); equal(#d.windows,0)
        d.event("key",keys.enter); equal(d.windows[1].title,"Settings")
        d.event("key",keys.f1); d.event("paste","nothing found"); d.render()
        d.event("key",keys.enter); equal(#d.windows,1); assert(screen.text():find("No matching apps"))
        d.event("key",keys.escape); equal(d.query,""); assert(d.launcher)
        local _,items=d.launcherLayout(); local hit=items[1]
        d.event("mouse_click",1,hit.x,hit.y); equal(#d.windows,2); equal(d.windows[2].title,"Turtle Fleet")
        d.render(); d.stop()
      end
    end
  end)
  test("Orbit UI: compact transitions preserve windows and return to the desktop layout",function()
    local screen=terminal.new(80,30,true); local d=desktop.new(screen.api,keys,{apps={}})
    local a=d.open(definition("One")); local b=d.open(definition("Two"))
    local x,y,ww,hh=b.x,b.y,b.w,b.h
    for _,size in ipairs({{40,30},{26,20},{51,19},{80,30}}) do
      screen.resize(size[1],size[2]); d.render(); equal(d.focused,b.id); equal(#d.windows,2)
      equal(b.full,size[1]<60); assert(not b.error)
    end
    equal(b.x,x); equal(b.y,y); equal(b.w,ww); equal(b.h,hh)
    d.event("key",keys.f3); assert(b.full)
    screen.resize(40,30); d.render(); screen.resize(100,36); d.render(); assert(b.full,"Explicit maximize was lost")
    d.event("key",keys.f3); assert(not b.full)
    d.stop()
  end)
  test("Orbit UI: dock pages expose all eight windows to mouse navigation",function()
    local screen=terminal.new(80,30,true); local d=desktop.new(screen.api,keys,{apps={}})
    for i=1,8 do d.open(definition("Window "..i)) end
    local seen={}
    for _=1,3 do
      local nextPage
      for _,hit in ipairs(d.dockLayout()) do
        if hit.window then seen[hit.window.id]=hit else if hit.label==">" then nextPage=hit end end
      end
      d.event("mouse_click",1,nextPage.x,nextPage.y); d.render()
    end
    for i=1,8 do assert(seen[i],"Window missing from dock") end
    local active=d.find(d.focused); d.event("mouse_click",1,active.x+3,active.y); assert(active.hidden)
    assert(d.launcher,"Minimizing should make app navigation available")
    local found
    for _=1,3 do
      local more
      for _,hit in ipairs(d.dockLayout()) do if hit.window and hit.window.id==active.id then found=hit elseif hit.label==">" then more=hit end end
      if found then break end
      d.event("mouse_click",1,more.x,more.y)
    end
    assert(found); d.event("mouse_click",1,found.x,found.y); equal(d.focused,active.id); assert(not active.hidden); assert(not d.launcher,"A dock click should restore the app immediately")
    d.event("mouse_click",1,active.x+1,active.y); equal(#d.windows,7); d.stop()
  end)
  test("Orbit UI: modal launcher captures input while network events reach background apps",function()
    local screen=terminal.new(80,30,true); local def=definition("One"); local d=desktop.new(screen.api,keys,{apps={def}})
    local w=d.open(def)
    d.event("mouse_click",1,w.x+10,w.y); assert(d.drag)
    d.event("key",keys.f1); assert(not d.drag)
    local before=#w.app.events
    d.event("char","a"); d.event("key",keys.f10); equal(#w.app.events,before); equal(#d.windows,1)
    d.event("rednet_message",12,{kind="status"},"test"); equal(w.app.events[#w.app.events][1],"rednet_message")
    d.event("mouse_click",1,1,2); assert(not d.launcher); equal(#d.windows,1)
    d.stop()
  end)
  test("Orbit UI: responsive cards paginate without overlap and keep editable focus after resize",function()
    for _,size in ipairs({{26,13},{26,20},{40,30},{51,19},{60,17},{80,30}}) do
      for _,color in ipairs({true,false}) do
        local screen=terminal.new(size[1],size[2],color); local p=panel.new(screen.api,keys); local items={}; local seen={}
        for i=1,30 do items[i]={id="item"..i,label="Action "..i,description="More information"} end
        for _=1,35 do
          p.draw("Actions","All your tools",items)
          local cells={}
          for _,w in ipairs(p.gui.widgets) do
            seen[w.id]=true
            for y=w.y,w.y+w.height-1 do for x=w.x,w.x+w.width-1 do
              assert(x>=1 and x<=p.gui.size and y>=1 and y<screen.height,"Control clipped")
              local key=x..":"..y; assert(not cells[key],"Overlapping controls"); cells[key]=true
            end end
          end
          p.gui.focus="next"; p.event("key",keys.enter)
        end
        for i=1,30 do assert(seen["item"..i],"Unreachable control") end
        local value="typed path"; local form={{field=true,id="path",label="Program",value=value,change=function(v) value=v end,max=100}}
        p.draw("Program","",form); p.gui.focus="path"; p.gui.cursors.path=4
        screen.resize(26,20); p.event("term_resize"); p.draw("Program","",form)
        equal(p.gui.focus,"path"); equal(p.gui.cursors.path,4); p.event("char","X"); equal(value,"typeXd path")
      end
    end
  end)
  test("Orbit UI: themed cast surfaces carry their palette and desktop restores the native palette",function()
    local native=surface.new(80,30,true); local before={native.term.getPaletteColor(1)}
    local d=desktop.new(native.term,keys,{apps={}})
    local w=d.open({id="panel",title="Panel",create=function(t) local p=panel.new(t,keys); return {render=function() p.draw("Panel","",{{id="ok",label="OK"}}) end} end})
    d.render(); local frame=w.surface.frame(); local expected=theme.palette[1]
    equal(math.floor(frame.palette[1][1]*255),math.floor(expected/65536))
    assert(frame.rows[1][3]:find("0")); d.stop()
    local after={native.term.getPaletteColor(1)}; for i=1,3 do equal(before[i],after[i]) end
  end)
  test("Orbit UI: returning from a child screen repaints the parent even when its state is unchanged",function()
    local screen=terminal.new(40,30,true); local parent=panel.new(screen.api,keys); local child=panel.new(screen.api,keys)
    local function drawParent() parent.draw("Settings","Your computer",{{id="resolution",label="Screen resolution"}}) end
    drawParent(); local expected=screen.text()
    child.draw("Resolution","Display size",{{id="default",label="Default"}})
    assert(screen.text()~=expected)
    parent.reset(); drawParent(); equal(screen.text(),expected)
  end)
end
return M
