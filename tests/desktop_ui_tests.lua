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
  test("Orbit UI: system menu is distinct from Apps and preserves exit confirmation",function()
    for _,size in ipairs({{26,13},{26,20},{40,30},{51,19},{80,30}}) do
      for _,color in ipairs({true,false}) do
        local screen=terminal.new(size[1],size[2],color); local exits=0
        local defs=require("orbit.apps").definitions({keys=keys,config={group="orbit"},version="test",id=42,
          quit=function() exits=exits+1 end})
        local d=desktop.new(screen.api,keys,{apps=defs})
        d.render(); local library=d.launcherLayout()
        assert(screen.rows[library.y].text:find("Apps",1,true))
        d.event("mouse_click",1,library.x+library.w-10,library.y); d.render()
        assert(d.systemMenu and not d.launcher)
        local _,items=d.systemLayout(); equal(#items,4); equal(items[1].label,"Settings"); equal(items[4].label,"Exit Orbit...")
        d.event("key",keys.escape); assert(d.launcher and not d.systemMenu)
        d.event("key",keys.f9); d.event("key",keys.enter,true); equal(#d.windows,0)
        d.event("key",keys.enter); d.render()
        equal(#d.windows,1); local settings=d.find(d.focused); equal(settings.kind,"settings"); equal(settings.app.page,"home")
        local background=d.open(definition("Background")); d.render()
        if not background.full then d.event("mouse_click",1,3,1) else d.event("key",keys.f9) end
        assert(d.systemMenu)
        local before=#background.app.events
        d.event("char","x"); d.event("key",keys.f10); equal(#background.app.events,before); equal(#d.windows,2)
        d.event("rednet_message",7,{},"test"); equal(background.app.events[#background.app.events][1],"rednet_message")
        local _,choices=d.systemLayout(); d.event("mouse_click",1,choices[3].x,choices[3].y); d.render()
        equal(d.focused,settings.id); equal(#d.windows,2); equal(settings.app.page,"message"); assert(settings.app.message:find("F9",1,true))
        d.event("key",keys.f9); d.event("key",keys.up); d.event("key",keys.enter); d.render()
        equal(settings.app.page,"quit"); equal(exits,0,"Opening Exit must still ask for confirmation")
        settings.app.event("key",keys.escape); d.render(); equal(settings.app.page,"home"); equal(exits,0)
        d.event("key",keys.f9); d.event("key",keys.down); d.event("key",keys.enter); d.render(); equal(d.find(d.focused).kind,"updates")
        d.event("key",keys.f9); d.event("key",keys.f1); d.render(); assert(d.launcher and not d.systemMenu)
        d.event("key",keys.f9); d.event("mouse_click",1,size[1],size[2]); assert(d.launcher and not d.systemMenu)
        d.stop()
      end
    end
  end)
  test("Orbit UI: shadows leave screen edges and the dock clear after moving and resizing",function()
    for _,color in ipairs({true,false}) do
      for _,size in ipairs({{26,20},{39,13},{51,19},{80,30}}) do
        local screen=terminal.new(size[1],size[2],color); local d=desktop.new(screen.api,keys,{apps={}})
        d.launcher=false; d.render()
        local dock=screen.rows[screen.height]; local dockText,dockBg=dock.text,dock.bg
        d.launcher=true; d.render()
        equal(screen.rows[screen.height].text,dockText); equal(screen.rows[screen.height].bg,dockBg)
        for y=2,screen.height-1 do equal(screen.rows[y].bg:sub(screen.width),"f") end
        if size[1]>=60 then
          local w=d.open(definition("Edges"))
          d.geometry(w,3,3,40,15); d.render()
          equal(screen.rows[w.y+2].bg:sub(w.x+w.w,w.x+w.w),"7","Interior shadow should remain visible")
          for _,bounds in ipairs({{999,999,40,15},{-999,-999,999,999}}) do
            d.geometry(w,table.unpack(bounds)); d.render()
            for y=2,screen.height-1 do equal(screen.rows[y].bg:sub(screen.width),"f") end
            equal(screen.rows[screen.height-1].bg,string.rep("f",screen.width))
          end
          screen.resize(60,22); d.event("term_resize"); d.render()
          equal(screen.rows[screen.height-1].bg,string.rep("f",screen.width))
          for y=2,screen.height-1 do equal(screen.rows[y].bg:sub(screen.width),"f") end
        end
        d.stop()
      end
    end
  end)
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
    assert(not frame.rows[1][1]:find("Panel"),"Floating window title should not be repeated in its content")
    assert(frame.rows[4][1]:find("OK")); d.stop()
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
  test("Orbit UI: generic fields advance through a form with Enter across pages",function()
    for _,height in ipairs({13,20,30}) do
      local screen=terminal.new(26,height,false); local p=panel.new(screen.api,keys)
      local items={{field=true,id="first",label="First",value="",change=function() end},
        {field=true,id="second",label="Second",value="",change=function() end},{id="save",label="Save"}}
      p.draw("Form","",items); equal(p.gui.focus,"first")
      p.event("key",keys.enter); p.draw("Form","",items); equal(p.gui.focus,"second")
      p.event("key",keys.enter); p.draw("Form","",items); equal(p.gui.focus,"save")
      equal(p.event("key",keys.enter),"save")
    end
  end)
  test("Orbit UI: controls have distinct shapes and readable semantic text colors",function()
    local widgets=require("orbit.widgets"); local screen=terminal.new(40,30,true); local g=widgets.new(screen.api,keys)
    g.begin("Contrast","Fields, actions and status")
    g.field("value","Value",4,"Example",function() end)
    g.button("action","Action",2,9,20,"action",{primary=true})
    g.button("off","Unavailable",2,12,20,"off",{enabled=false})
    g.text(2,16,"Warning",20,"4"); g.text(2,17,"Ready",20,"5"); g.finish()
    assert(screen.rows[5].text:find("|",1,true)); assert(screen.rows[6].text:find("---",1,true)); assert(screen.rows[9].text:find("[",1,true)); assert(screen.rows[12].text:find("(",1,true))
    local function luminance(value)
      local r,g,b=math.floor(value/65536)/255,math.floor(value/256)%256/255,value%256/255
      local function linear(c) return c<=0.04045 and c/12.92 or ((c+0.055)/1.055)^2.4 end
      return linear(r)*0.2126+linear(g)*0.7152+linear(b)*0.0722
    end
    for _,row in ipairs(screen.rows) do for i=1,#row.text do if row.text:sub(i,i)~=" " then
      local a=luminance(theme.palette[tonumber(row.fg:sub(i,i),16)+1]); local b=luminance(theme.palette[tonumber(row.bg:sub(i,i),16)+1])
      assert((math.max(a,b)+0.05)/(math.min(a,b)+0.05)>=4.5,"Low contrast text")
    end end end
  end)
end
return M
