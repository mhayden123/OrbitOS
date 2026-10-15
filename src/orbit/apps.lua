local panel=require("orbit.panel")
local gui=require("fleet.gui")
local fleetClient=require("fleet.client")
local fleetDashboard=require("fleet.dashboard")
local fleetNet=require("fleet.net")
local surface=require("orbit.surface")
local task=require("orbit.task")
local update=require("orbit.update")
local releaseInfo=require("orbit.release")
local M={}
local function button(id,label,enabled) return {id=id,label=label,enabled=enabled} end
local function note(text) return {text=text} end
local function field(id,label,value,change,numeric) return {id=id,label=label,value=value,change=change,field=true,numeric=numeric} end
function M.definitions(o)
  local function generic(display)
    local app={running=true,p=panel.new(display,o.keys),page="home"}
    function app.notice(text,back) app.message,app.returnPage,app.page=text,back or app.page,"message"; app.p.reset() end
    function app.messageItems()
      local w=display.getSize(); local items={}
      for _,line in ipairs(gui.wrap(app.message,math.min(40,w)-2)) do items[#items+1]=note(line) end
      return items
    end
    function app.back() if app.page=="message" then app.page=app.returnPage; app.p.reset() else app.running=false end end
    return app
  end
  local definitions={}
  definitions[#definitions+1]={id="fleet",title="Turtle Fleet",singleton=true,minW=26,minH=19,create=function(display)
    -- OS opens wired and wireless modems; Fleet continues using its own protocol.
    local cfg=o.load("/.fleet-controller") or {}
    local client=fleetClient.new({group=cfg.group,owner=o.id,now=o.now,boot=o.boot})
    local app=fleetDashboard.new(display,o.keys,{client=client,setup=not cfg.group,
      saveGroup=function(value) o.save("/.fleet-controller",{group=value}) end})
    local event=app.event
    app.event=function(name,a,b,c,...)
      if name=="rednet_message" and c==fleetNet.PROTOCOL then client.receive(a,b) end
      event(name,a,b,c,...)
    end
    app.tick=function() if o.modemCount()>0 then client.tick() end end
    return app
  end}
  definitions[#definitions+1]={id="program",title="Run a program",minW=26,minH=10,create=function(display,w)
    local app=generic(display); app.path="shell"
    function app.render()
      if app.process then
        if app.process.done and not app.reported then
          local _,h=display.getSize(); surface.text(display,1,h,app.process.error or "Program finished. F10 closes."); app.reported=true
        end
        return
      end
      app.p.draw("RUN A PROGRAM","CraftOS applications",{
        field("path","Program path",app.path,function(v) app.path=v end),
        button("run","Run"),note("Use shell for a command prompt."),note("F1 apps / F10 close")})
    end
    function app.event(...)
      if app.process then app.process.event(...); return end
      local a=app.p.event(...)
      if a=="back" then app.running=false
      elseif a=="run" and #app.path>0 then
        display.clear(); display.setCursorPos(1,1); w.title=app.path:match("[^/]+$") or "Program"
        app.process=task.new(function() o.shell.run(app.path) end,display,o.term,o.shell)
      end
    end
    return app
  end}
  definitions[#definitions+1]={id="network",title="Displays & network",singleton=true,minW=26,minH=10,create=function(display)
    local app=generic(display); app.source=o.castSource; app.touch=false
    function app.render()
      if app.page=="message" then app.p.draw("DISPLAY NOTICE","",app.messageItems(),"Back"); return end
      local items={note("Group: "..o.config.group.." | ID "..o.id),note("Open modems: "..o.modemCount()),
        button("source","App: "..(o.title(app.source) or "Choose an app")),
        button("touch",app.touch and "[x] Allow monitor taps" or "[ ] Allow monitor taps"),button("stop","Stop all casts")}
      app.targets=o.cast.targets()
      if #app.targets==0 then items[#items+1]=note("No displays found yet.") end
      for i,t in ipairs(app.targets) do
        local stream=o.cast.streams[t.key]
        items[#items+1]=button("target:"..t.key,t.name.." "..t.width.."x"..t.height)
        if stream then items[#items+1]=note("  "..stream.status) end
      end
      items[#items+1]=note("Remote: run orbit receive there.")
      app.p.draw("DISPLAYS & NETWORK","Choose an app, then a display",items)
    end
    function app.event(...)
      local action=app.p.event(...)
      if action=="back" then app.back()
      elseif action=="source" then
        local windows=o.windows(); local choices={}
        for _,w in ipairs(windows) do if w.kind~="network" then choices[#choices+1]=w.id end end
        local index=0; for i,id in ipairs(choices) do if id==app.source then index=i end end
        app.source=choices[index%math.max(1,#choices)+1]
      elseif action=="touch" then app.touch=not app.touch
      elseif action=="stop" then o.cast.stopAll()
      elseif action and action:match("^target:") then
        local key=action:sub(8)
        for _,target in ipairs(app.targets) do if target.key==key then
          local ok,why=o.cast.start(target,app.source,app.touch)
          if not ok then app.notice(why) end
          break
        end end
      end
    end
    return app
  end}
  definitions[#definitions+1]={id="updates",title="Update Center",singleton=true,minW=26,minH=10,create=function(display)
    local app=generic(display)
    local function savedSource()
      return type(o.config.updateSource)=="string" and #o.config.updateSource>0 and o.config.updateSource or releaseInfo.updateSource
    end
    app.source=savedSource()
    local function work(fn,finish)
      app.page="busy"; app.progress="Checking release..."; app.p.reset(); app.job=task.new(fn,display,o.term)
      app.finish=finish
    end
    local function yielding() local timer=os.startTimer(0); os.pullEvent("timer"); os.cancelTimer(timer) end
    local function currentVersion()
      local installed=update.version(o.config.installedVersion)
      return installed and installed>update.version(o.version) and o.config.installedVersion or o.version
    end
    local function installed(result)
      if result.unchanged then
        app.notice("Already up to date on disk: Orbit "..result.version.." and its bundled apps. "..
          (result.version~=o.version and "Restart Orbit when current work is finished to use this version." or ""),"home")
        return
      end
      o.config.rollback=result.backup; o.config.installedVersion=result.version
      local saved,why=pcall(o.saveConfig)
      app.notice("Updated Orbit "..result.version.." and all bundled apps. Close Orbit and run orbit again when current work is finished. "..
        (result.backup and "Rollback: "..result.backup..". " or "")..
        (saved and "" or "Could not save update history: "..tostring(why)),"home")
    end
    local function install(release)
      if release.unchanged then return {unchanged=true,version=release.manifest.version} end
      app.progress="Installing OS and apps..."
      return {backup=update.apply(o.fs,release,yielding),version=release.manifest.version}
    end
    function app.tick()
      if app.job and app.job.done then
        local job=app.job; app.job=nil
        if job.error then app.notice(job.error,"home") else app.finish(job.result) end
      end
    end
    function app.render()
      local items
      if app.page=="message" then app.p.draw("UPDATE NOTICE","",app.messageItems(),"Back"); return
      elseif app.page=="busy" then items={note(app.progress),note("Other apps keep running.")}
      elseif app.page=="source" then
        items={field("source","Directory or HTTPS release URL",app.source,function(v) app.source=v end),
          button("saveSource","Save source"),button("defaultSource","Use OrbitOS GitHub"),button("cancel","Cancel")}
      elseif app.page=="included" then
        items={note("Orbit OS "..o.version)}
        for _,info in ipairs(releaseInfo.apps) do items[#items+1]=note(info.title.." "..info.version) end
        items[#items+1]=note("These update together.")
        items[#items+1]=note("Other programs keep their own updater.")
        items[#items+1]=note("Turtle workers update on each turtle.")
      elseif app.page=="review" then
        items={note("Running: "..o.version),note("Available: "..app.release.manifest.version),note("Size: "..app.release.manifest.size.." bytes"),
          note("SHA-256 verified."),note("OS and bundled apps update together."),button("install","Install update"),button("cancel","Cancel")}
        for _,info in ipairs(app.release.manifest.apps or {}) do items[#items+1]=note(info.title.." "..info.version) end
      elseif app.page=="rollback" then items={note("Restore the previous OS and apps?"),note("Running apps continue until restart."),button("restore","Restore backup"),button("cancel","Cancel")}
      else items={note("Running Orbit "..o.version),button("update","Update OS + apps"),
          button("included","What's included?"),button("changeSource","Change update source"),button("check","Check without installing"),
          button("rollback","Rollback previous update",o.config.rollback~=nil),note("Restart when your work is finished.")}
      end
      app.p.draw("UPDATE CENTER","OS and bundled apps",items)
    end
    function app.event(...)
      if app.job then app.job.event(...); return end
      local action=app.p.event(...)
      if action=="back" then if app.page=="home" then app.running=false else app.page="home"; app.p.reset() end
      elseif action=="cancel" then app.page="home"; app.p.reset()
      elseif action=="changeSource" then app.source=savedSource(); app.page="source"; app.p.reset()
      elseif action=="included" then app.page="included"; app.p.reset()
      elseif action=="saveSource" or action=="defaultSource" then
        if action=="defaultSource" then app.source=releaseInfo.updateSource end
        if #app.source==0 then app.notice("Enter an in-game folder or an HTTPS release URL.","source")
        else o.config.updateSource=app.source; o.saveConfig(); app.page="home"; app.p.reset() end
      elseif action=="update" then
        work(function() return install(update.check(savedSource(),currentVersion(),o.fs,o.http,o.decode,yielding)) end,installed)
      elseif action=="check" then
        work(function() return update.check(savedSource(),currentVersion(),o.fs,o.http,o.decode,yielding) end,
          function(release) app.release=release; app.page="review"; app.p.reset() end)
      elseif action=="install" then
        work(function() return install(app.release) end,installed)
      elseif action=="rollback" then app.page="rollback"
      elseif action=="restore" then
        work(function() return update.rollback(o.fs,o.config.rollback) end,function(backup)
          o.config.rollback=backup; o.config.installedVersion=nil; o.saveConfig(); app.notice("Previous OS and bundled apps restored. Close Orbit and run orbit to use them.","home")
        end)
      end
    end
    return app
  end}
  definitions[#definitions+1]={id="settings",title="Settings & help",singleton=true,minW=26,minH=10,create=function(display)
    local app=generic(display); app.group=o.config.group
    function app.render()
      if app.page=="message" then app.p.draw("ORBIT HELP","",app.messageItems(),"Back"); return end
      if app.page=="quit" then
        app.p.draw("EXIT ORBIT?","Apps will close",{note("Fleet turtles pause when"),note("their controller link expires."),
          button("exit","Exit to CraftOS"),button("cancel","Keep working")},"Back"); return
      end
      app.p.draw("SETTINGS & HELP","Orbit "..o.version.." / computer #"..o.id,{
        field("group","Display network group",app.group,function(v) app.group=v end),button("save","Save network group"),
        button("help","Window and casting help"),button("quit","Exit Orbit"),note("Fleet keeps its own group settings.")})
    end
    function app.event(...)
      local a=app.p.event(...)
      if a=="back" then if app.page=="quit" then app.page="home" else app.back() end
      elseif a=="save" then
        if app.group:match("^[%w_-]+$") and #app.group<=32 then
          o.cast.stopAll(); o.cast.peers={}; o.config.group=app.group; o.saveConfig(); app.notice("Display network saved.")
        else app.notice("Use 1-32 letters, digits, hyphens or underscores.") end
      elseif a=="help" then app.notice("Drag a title to move a window. Drag its bottom edge to resize. Title controls: C casts, _ minimizes, ^ maximizes, X closes. F1 opens Apps; F2 switches; F3 toggles full screen; F4 moves and F5 resizes using arrows, then Enter; F6 opens casting; F10 closes the current app. Fleet uses full screen when its controls need the space. Wired monitors appear directly. Wireless displays need a receiver computer running orbit receive, with this computer's ID and matching group. Receiver taps require permission on both computers. Programs share the computer's files and use cooperative multitasking.")
      elseif a=="quit" then app.page="quit"
      elseif a=="cancel" then app.page="home"
      elseif a=="exit" then o.quit() end
    end
    return app
  end}
  return definitions
end
return M
