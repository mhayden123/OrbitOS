local panel=require("orbit.panel")
local task=require("orbit.task")
local M={}
local function button(id,label,enabled) return {id=id,label=label,enabled=enabled} end
local function note(text) return {text=text} end
function M.new(display,o)
  local app={running=true,p=panel.new(display,o.keys),page="home",nextPoll=0}
  local api=o.resolutionApi
  local compatible=type(api)=="table" and type(api.getInfo)=="function" and type(api.preview)=="function"
    and type(api.keep)=="function" and type(api.revert)=="function"
  local function finish()
    if app.process and app.process.done then
      if app.process.error then app.message=app.process.error end
      app.process=nil
    end
  end
  local function request(fn)
    if app.process then return end
    app.message=nil
    app.process=task.new(fn,display,o.term,o.shell)
    finish()
  end
  local function refresh()
    local info=api.getInfo()
    assert(type(info)=="table" and info.apiVersion==1,"Update Orbit Display to a compatible version.")
    app.info=info
    if app.token and info.preview~=app.token then
      app.token=nil; app.page="home"; app.message="Previous resolution restored."; app.p.reset()
    end
    app.nextPoll=o.now()+1
  end
  local function preview(w,h)
    if not app.info then return end
    local i=app.info
    w,h=tonumber(w),tonumber(h)
    if not w or not h or w%1~=0 or h%1~=0 or w<i.minWidth or w>i.maxWidth or h<i.minHeight or h>i.maxHeight then
      app.message=("Use %d-%d columns and %d-%d rows."):format(i.minWidth,i.maxWidth,i.minHeight,i.maxHeight); return
    end
    request(function()
      app.token=api.preview(w,h); app.page="preview"; app.p.reset(); refresh()
    end)
  end
  function app.render()
    local i=app.info; local items={}; local busy=app.process~=nil
    if not compatible then
      items={note("Install Orbit Display on the Minecraft client and server, then restart Minecraft."),
        note("Get the companion JAR from the OrbitOS repository. ComputerCraft Lua cannot install Minecraft mods.")}
    elseif not i then
      items={note(app.message or "Reading display settings..."),button("refresh","Try again",not busy)}
    elseif app.token then
      items={note(("%d x %d - keep this size?"):format(i.width,i.height)),
        button("keep","Keep resolution",not busy),button("revert","Revert",not busy),
        note("Restores automatically in "..tostring(i.remaining).."s.")}
    elseif app.page=="custom" then
      items={{id="width",label="Columns",field=true,numeric=true,value=app.width,change=function(v) app.width=v end,max=3},
        {id="height",label="Rows",field=true,numeric=true,value=app.height,change=function(v) app.height=v end,max=2},
        button("preview","Preview size",not busy),note("Text fits the game window automatically.")}
    else
      local pocket=i.kind=="pocket"
      items={note(("Current: %d x %d"):format(i.width,i.height)),
        button("default",("Default (%d x %d)"):format(i.defaultWidth,i.defaultHeight),not busy),
        button("balanced",pocket and "Balanced (40 x 30)" or "Balanced (80 x 30)",not busy),
        button("space",pocket and "More space (52 x 36)" or "More space (100 x 36)",not busy),
        button("custom","Custom size",not busy)}
    end
    if app.message and i then items[#items+1]=note(app.message) end
    app.p.draw("RESOLUTION",busy and "Working..." or "This computer's display",items,"Back")
  end
  function app.event(...)
    if app.process then app.process.event(...); finish() end
    local action=app.p.event(...)
    if action=="back" then
      if app.token then app.close(); app.running=false
      elseif app.page=="custom" then app.page="home"; app.message=nil; app.p.reset()
      else app.close(); app.running=false end
    elseif not app.process and compatible then
      if action=="refresh" then request(refresh)
      elseif action=="keep" and app.token then request(function()
        api.keep(app.token); app.token=nil; app.page="home"; refresh(); app.message="Resolution saved."; app.p.reset()
      end)
      elseif action=="revert" and app.token then request(function()
        api.revert(app.token); app.token=nil; app.page="home"; refresh(); app.p.reset()
      end)
      elseif action=="custom" and app.info then
        app.width,app.height=tostring(app.info.width),tostring(app.info.height); app.page="custom"; app.p.reset()
      elseif action=="preview" then preview(app.width,app.height)
      elseif app.info then
        if action=="default" then preview(app.info.defaultWidth,app.info.defaultHeight)
        elseif action=="balanced" then preview(app.info.kind=="pocket" and 40 or 80,30)
        elseif action=="space" then preview(app.info.kind=="pocket" and 52 or 100,36) end
      end
    end
  end
  function app.tick()
    finish()
    if compatible and not app.process and o.now()>=app.nextPoll and (app.token or not app.info) then request(refresh) end
  end
  function app.close()
    if app.token then
      local token=app.token; app.token=nil
      -- Starting the task submits the main-thread revert. The server timer is the
      -- fallback even if this app closes while preview() is still awaiting its token.
      task.new(function() pcall(api.revert,token) end,display,o.term,o.shell)
    end
  end
  if compatible then request(refresh) end
  return app
end
return M
