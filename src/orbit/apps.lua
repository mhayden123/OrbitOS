local panel=require("orbit.panel")
local gui=require("fleet.gui")
local fleetClient=require("fleet.client")
local fleetDashboard=require("fleet.dashboard")
local fleetNet=require("fleet.net")
local surface=require("orbit.surface")
local task=require("orbit.task")
local update=require("orbit.update")
local releaseInfo=require("orbit.release")
local workerRelease=require("fleet.updates")
local resolution=require("orbit.resolution")
local widgets=require("orbit.widgets")
local M={}
local descriptions={resolution="Size and readability",network="Wireless connections",help="Shortcuts and controls",
  quit="Return to CraftOS",update="OS, apps and workers",turtles="Versions and progress",included="What's installed",options="More settings",
  source="Pick an open app",custom="Choose columns and rows"}
local function button(id,label,enabled,primary) return {id=id,label=label,enabled=enabled,primary=primary,description=descriptions[id]} end
local function note(text) return {text=text} end
local function field(id,label,value,change,numeric) return {id=id,label=label,value=value,change=change,field=true,numeric=numeric} end
function M.definitions(o)
  local function generic(display)
    local app={running=true,p=panel.new(display,o.keys),page="home"}
    function app.notice(text,back) app.message,app.returnPage,app.page=text,back or app.page,"message"; app.p.reset() end
    function app.messageItems()
      local w=display.getSize(); local items={}
      items[1]=note(app.message)
      return items
    end
    function app.back() if app.page=="message" then app.page=app.returnPage; app.p.reset() else app.running=false end end
    return app
  end
  local definitions={}
  definitions[#definitions+1]={id="fleet",title="Turtle Fleet",description="Jobs and live turtles",width=70,height=25,singleton=true,minW=26,minH=19,create=function(display)
    -- OS opens wired and wireless modems; Fleet continues using its own protocol.
    local cfg=o.load("/.fleet-controller") or {}
    local client=fleetClient.new({group=cfg.group,owner=o.id,now=o.now,boot=o.boot})
    local app=fleetDashboard.new(display,o.keys,{client=client,setup=not cfg.group,widgets=widgets,
      saveGroup=function(value)
        o.save("/.fleet-controller",{group=value})
        if o.fleetUpdates then o.fleetUpdates.setGroup(value) end
      end})
    local event=app.event
    app.event=function(name,a,b,c,...)
      if name=="rednet_message" and c==fleetNet.PROTOCOL then client.receive(a,b) end
      event(name,a,b,c,...)
    end
    app.tick=function() if o.modemCount()>0 then client.tick() end end
    return app
  end}
  definitions[#definitions+1]={id="program",title="Programs",description="Shell and CraftOS apps",minW=26,minH=13,create=function(display,w)
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
        button("run","Run",true,true),note("Use shell for a command prompt.")})
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
  definitions[#definitions+1]={id="network",title="Displays",description="Share a window",singleton=true,minW=26,minH=13,create=function(display)
    local app=generic(display); app.source=o.castSource; app.touch=false
    function app.render()
      if app.page=="message" then app.p.draw("DISPLAY NOTICE","",app.messageItems(),"Back"); return end
      if app.page=="sources" then
        local choices={}
        for _,w in ipairs(o.windows()) do if w.kind~="network" then choices[#choices+1]=button("app:"..w.id,w.title) end end
        if #choices==0 then choices={note("Open an app from Apps first. Then return here to share it on a monitor.")} end
        app.p.draw("CHOOSE AN APP","Share a live view",choices,"Back"); return
      elseif app.page=="options" then
        app.p.draw("DISPLAY OPTIONS","Wired and wireless",{
          button("touch",app.touch and "Monitor taps: On" or "Monitor taps: Off"),button("stop","Stop all casts"),
          note("Network: "..o.config.group.." / computer #"..o.id),note("Connected modems: "..o.modemCount()),
          note("Wired: attach a monitor with networking cable and enable its modem."),
          note("Wireless: on another computer, run orbit receive. Set its sender to "..o.id.." and group to "..o.config.group..".")},"Back"); return
      end
      local ready=o.title(app.source)~=nil
      local items={button("source",ready and ("App: "..o.title(app.source)) or "Choose an app",true,not ready)}
      if not ready then items[#items+1]=note("Choose what to share, then tap a display.") end
      app.targets=o.cast.targets()
      if #app.targets==0 then items[#items+1]=note("No displays found. Open Connection help to connect one.") end
      for i,t in ipairs(app.targets) do
        local stream=o.cast.streams[t.key]
        items[#items+1]=button("target:"..t.key,(stream and "Sharing: " or "Share to ")..t.name,ready)
        if stream then items[#items+1]=note("  "..stream.status) end
      end
      items[#items+1]=button("options","Connection help & options")
      app.p.draw("DISPLAYS","Share an app on a monitor",items)
    end
    function app.event(...)
      local action=app.p.event(...)
      if action=="back" then if app.page=="home" then app.running=false else app.page="home"; app.p.reset() end
      elseif action=="source" then
        app.page="sources"; app.p.reset()
      elseif action=="options" then app.page="options"; app.p.reset()
      elseif action and action:match("^app:") then app.source=tonumber(action:sub(5)); app.page="home"; app.p.reset()
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
  definitions[#definitions+1]={id="updates",title="Updates",description="Keep everything current",singleton=true,minW=26,minH=13,create=function(display)
    local app=generic(display)
    local function savedSource()
      return type(o.config.updateSource)=="string" and #o.config.updateSource>0 and o.config.updateSource or releaseInfo.updateSource
    end
    app.source=savedSource()
    local fleet=o.fleetUpdates
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
      if result.workers and fleet then
        app.summary=(result.unchanged and "OS and apps are current." or "OS and apps installed. Restart Orbit after turtle updates finish.")
        app.page="turtles"; app.p.reset()
      end
      if result.unchanged then
        if result.workers then return end
        app.notice("Already up to date on disk: Orbit "..result.version.." and its bundled apps. "..
          (result.version~=o.version and "Restart Orbit when current work is finished to use this version." or ""),"home")
        return
      end
      if result.workers then
        if result.saveError then app.summary=app.summary.." Could not save update history: "..result.saveError end
        return
      end
      app.notice("Updated Orbit "..result.version.." and all bundled apps. Close Orbit and run orbit again when current work is finished. "..
        (result.backup and "Rollback: "..result.backup..". " or "")..
        (result.saveError and "Could not save update history: "..result.saveError or ""),"home")
    end
    local function install(release)
      if release.unchanged then return {unchanged=true,version=release.manifest.version} end
      app.progress="Installing OS and apps..."
      local result={backup=update.apply(o.fs,release,yielding),version=release.manifest.version}
      -- Persist before another event can close this window or begin worker transfers.
      o.config.rollback=result.backup; o.config.installedVersion=result.version
      local saved,why=pcall(o.saveConfig); if not saved then result.saveError=tostring(why) end
      return result
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
      elseif app.page=="options" then
        items={button("check","Check OS release"),button("osOnly","Update OS + apps only"),button("changeSource","Change update source"),
          button("rollback","Restore previous OS",o.config.rollback~=nil),note("Source: "..(savedSource()==releaseInfo.updateSource and "OrbitOS on GitHub" or savedSource()))}
      elseif app.page=="turtles" then
        items={note(app.summary or "Updates wait for active jobs to finish.")}
        if not fleet or #fleet.rows==0 then
          items[#items+1]=note("No update results yet. Open Turtle Fleet to choose your fleet, then update while turtles are in range.")
        else
          for i,row in ipairs(fleet.rows) do
            items[#items+1]=button("worker:"..i,"#"..row.id.." "..row.state..(row.state=="Sending" and " "..row.progress.."%" or ""))
          end
        end
        items[#items+1]=button("workers","Update turtles",fleet~=nil and not fleet.running,true)
        if fleet and fleet.running then items[#items+1]=button("stopWorkers","Stop queued updates") end
      elseif app.page=="worker" then
        local row=fleet.rows[app.worker]
        items={note(row.label or ("Turtle #"..row.id)),note("Version: "..tostring(row.version)),note(row.state),
          note(row.detail or (row.state=="Setup needed" and "This worker predates remote updates. Install the latest worker once and restart it. Future updates come from here."
          or row.state=="Offline" and "Bring the turtle in range and try Update turtles again." or "Its settings are kept when updating."))}
      elseif app.page=="included" then
        items={note("Orbit OS "..o.version)}
        for _,info in ipairs(releaseInfo.apps) do items[#items+1]=note(info.title.." "..info.version) end
        items[#items+1]=note("These update together.")
        items[#items+1]=note("Other programs keep their own updater.")
        items[#items+1]=note("Assigned turtles update over the modem. They do not need internet access.")
      elseif app.page=="review" then
        items={note("Running: "..o.version),note("Available: "..app.release.manifest.version),note("Size: "..app.release.manifest.size.." bytes"),
          note("SHA-256 verified."),note("OS and bundled apps update together."),button("install","Install update"),button("cancel","Cancel")}
        for _,info in ipairs(app.release.manifest.apps or {}) do items[#items+1]=note(info.title.." "..info.version) end
      elseif app.page=="rollback" then items={note("Restore the previous OS and apps?"),note("Running apps continue until restart."),button("restore","Restore backup"),button("cancel","Cancel")}
      else items={note("Orbit "..o.version),button("update","Update everything",not fleet or not fleet.running,true),
          button("turtles",fleet and fleet.running and "Turtles: updating..." or "Turtle updates"),
          button("included","Included apps"),button("options","Update options")}
      end
      app.p.draw("UPDATES","OS, apps and your turtles",items,app.page=="home" and "Close" or "Back")
    end
    function app.event(...)
      if app.job then app.job.event(...); return end
      local action=app.p.event(...)
      if action=="back" then
        if app.page=="home" then app.running=false else app.page=app.page=="worker" and "turtles" or "home"; app.p.reset() end
      elseif action=="cancel" then app.page="home"; app.p.reset()
      elseif action=="changeSource" then app.source=savedSource(); app.page="source"; app.p.reset()
      elseif action=="included" then app.page="included"; app.p.reset()
      elseif action=="options" or action=="turtles" then app.page=action; app.p.reset()
      elseif action and action:match("^worker:") then app.worker=tonumber(action:sub(8)); app.page="worker"; app.p.reset()
      elseif action=="stopWorkers" then fleet.cancel()
      elseif action=="saveSource" or action=="defaultSource" then
        if action=="defaultSource" then app.source=releaseInfo.updateSource end
        if #app.source==0 then app.notice("Enter an in-game folder or an HTTPS release URL.","source")
        else o.config.updateSource=app.source; o.saveConfig(); app.page="home"; app.p.reset() end
      elseif action=="update" then
        work(function()
          local release=update.check(savedSource(),currentVersion(),o.fs,o.http,o.decode,yielding)
          local workers
          if fleet then app.progress="Downloading turtle update..."; workers=workerRelease.fetch(savedSource(),o.fs,o.http,o.decode,yielding) end
          local result=install(release)
          if workers then fleet.start(workers); result.workers=true end
          return result
        end,installed)
      elseif action=="workers" then
        work(function() fleet.start(workerRelease.fetch(savedSource(),o.fs,o.http,o.decode,yielding)) end,function()
          app.summary=nil; app.page="turtles"; app.p.reset()
        end)
      elseif action=="osOnly" then
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
  definitions[#definitions+1]={id="settings",title="Settings",description="Make Orbit your own",width=62,singleton=true,minW=26,minH=13,create=function(display)
    local app=generic(display); app.group=o.config.group
    function app.render()
      if app.resolution then app.resolution.render(); return end
      if app.page=="message" then app.p.draw("ORBIT HELP","",app.messageItems(),"Back"); return end
      if app.page=="quit" then
        app.p.draw("EXIT ORBIT?","Apps will close",{note("Fleet turtles pause when"),note("their controller link expires."),
          button("exit","Exit to CraftOS"),button("cancel","Keep working")},"Back"); return
      end
      if app.page=="network" then app.p.draw("DISPLAY NETWORK","Used by wireless receivers",{
        field("group","Display network group",app.group,function(v) app.group=v end),button("save","Save network group"),
        note("Fleet keeps its own group settings.")},"Back"); return end
      app.p.draw("SETTINGS","Orbit "..o.version.." / computer #"..o.id,{
        button("resolution","Screen resolution"),button("network","Display network"),button("help","Keyboard & windows"),button("quit","Exit Orbit")})
    end
    function app.event(...)
      if app.resolution then
        app.resolution.event(...)
        if not app.resolution.running then app.resolution=nil; app.p.reset() end
        return
      end
      local a=app.p.event(...)
      if a=="back" then if app.page=="quit" or app.page=="network" then app.page="home"; app.p.reset() else app.back() end
      elseif a=="resolution" then app.resolution=resolution.new(display,o)
      elseif a=="network" then app.page="network"; app.p.reset()
      elseif a=="save" then
        if app.group:match("^[%w_-]+$") and #app.group<=32 then
          o.cast.stopAll(); o.cast.peers={}; o.config.group=app.group; o.saveConfig(); app.notice("Display network saved.")
        else app.notice("Use 1-32 letters, digits, hyphens or underscores.") end
      elseif a=="help" then app.notice("Apps: click Orbit or Apps, or press F1. Type to find an app. F2 switches open apps. On larger screens, drag the title to move a window and its bottom edge to resize. The left controls close (x), minimize (-) and maximize (+). Cast shares the app. Compact screens show one app at a time. F3 toggles full screen; F4 moves and F5 resizes with arrows, then Enter; F6 opens casting; F10 closes. Forms use Tab, arrows and Enter; Ctrl+U clears a field. Other apps and Fleet connections keep running in the background.")
      elseif a=="quit" then app.page="quit"
      elseif a=="cancel" then app.page="home"
      elseif a=="exit" then o.quit() end
    end
    function app.tick() if app.resolution then app.resolution.tick() end end
    function app.close() if app.resolution then app.resolution.close() end end
    return app
  end}
  return definitions
end
return M
