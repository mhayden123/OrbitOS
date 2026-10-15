-- A visual launcher; the command line is an explicit choice, never the default.
local panel=require("orbit.panel")
local surface=require("orbit.surface")
local task=require("orbit.task")
local theme=require("orbit.theme")
local M={}
local function button(id,label,primary,description) return {id=id,label=label,primary=primary,description=description} end
local function base(path) return path:match("[^/]+$") or path end
local function join(dir,name) return (dir=="/" and "" or dir).."/"..name end
local function managed(name)
  return name=="startup" or name=="startup.lua" or name=="orbit.lua" or name=="fleet.lua" or name=="install.lua" or name=="install-os.lua"
    or name:match("^orbit[%.%-]") or name:match("^fleet[%.%-]") or name:match("^install[%.%-]")
end
function M.new(display,o,w)
  local app={running=true,p=panel.new(display,o.keys),page="browse",directory="/",path="",entries={}}
  local function page(name) app.page=name; app.p.reset() end
  local function scan()
    app.entries={}; app.scanError=nil
    local ok,why=pcall(function()
      for _,name in ipairs(o.fs.list(app.directory)) do
        local path=join(app.directory,name)
        if not name:match("^%.") and not (app.directory=="/" and managed(name)) then
          local folder=o.fs.isDir(path)
          if folder or name:match("%.lua$") or not name:find("%.") then
            if app.directory=="/" and name=="rom" then path,name="/rom/programs","CraftOS programs" end
            app.entries[#app.entries+1]={path=path,name=name,folder=folder}
          end
        end
      end
      table.sort(app.entries,function(a,b) if a.folder~=b.folder then return a.folder end; return a.name:lower()<b.name:lower() end)
    end)
    if not ok then app.scanError="This folder is unavailable. Go up or refresh to try again." end
  end
  local function reset()
    app.process,app.output,app.failure=nil,nil,nil; w.title="Programs"; theme.apply(display); scan(); page("browse")
  end
  local function start(path,title)
    app.path=path
    app.launchPage=(app.page=="path" or app.page=="review") and app.page or "browse"
    local ok,resolved=pcall(function() return o.shell.resolveProgram(path) end)
    if not ok or not resolved then app.failure="Program not found: "..path; page("error"); return end
    if (resolved=="orbit.lua" or resolved=="/orbit.lua" or resolved=="fleet.lua" or resolved=="/fleet.lua") then
      app.failure="Orbit is already running. Open Turtle Fleet or another built-in app from Apps."; page("error"); return
    end
    local width,height=display.getSize()
    app.output=surface.new(width,height-1-(w.full and 1 or 0),display.isColor()); app.failure=nil
    w.title=title or base(resolved); app.title=w.title
    app.process=task.new(function() return o.shell.execute(resolved) end,app.output.term,o.term,o.shell)
    page("process")
  end
  scan()
  function app.render()
    if app.page=="process" then
      local width,height=display.getSize(); local t=app.output.term
      local header=w.full and 1 or 0
      if app.output.width~=width or app.output.height~=height-1-header then app.output.resize(width,height-1-header); app.process.event("term_resize") end
      if header==1 then
        surface.text(display,1,1,string.rep(" ",width),1,32768)
        surface.text(display,2,1,theme.fit(app.title,width-2-(display._orbitHeaderReserve or 0)),1,32768)
      end
      for y=1,app.output.height do display.setCursorPos(1,y+header); display.blit(t.getLine(y)) end
      local done=app.process.done; local failed=done and (app.process.error or app.process.result==false)
      local action=done and "[Programs] [Again]" or "[Stop]"
      surface.text(display,1,height,string.rep(" ",width),32768,256)
      surface.text(display,1,height,action,1,display.isColor() and 2048 or 32768)
      local statusX=done and 19 or 9
      surface.text(display,statusX,height,theme.fit(done and (failed and "Failed" or "Done") or "F7: stop",width-statusX),failed and (display.isColor() and 16384 or 32768) or 32768,256)
      if done then
        display.setCursorBlink(false)
        if app.process.error then surface.text(display,1,height-1,theme.fit(app.process.error,width),1,display.isColor() and 16384 or 32768) end
      else
        local x,y=t.getCursorPos()
        if x>=1 and x<=width and y>=1 and y<=height-1-header then display.setCursorPos(x,y+header); display.setCursorBlink(t.getCursorBlink()) end
      end
      return
    elseif app.page=="stop" then
      app.p.draw("Stop program?",app.title,{{text="Unsaved work can be lost."},button("keep","Keep running",true),button("stop","Stop program")},"Keep running"); return
    elseif app.page=="error" then
      app.p.draw("Cannot open program","Choose a different file",{{text=app.failure}},"Back"); return
    elseif app.page=="path" or app.page=="review" then
      local items
      if app.page=="path" then
        items={{field=true,id="path",label="Program name or path",value=app.path,max=160,enter="run",change=function(v) app.path=v end},button("run","Open program",true),{text="Programs may have text or graphical interfaces."}}
      else items={{text=app.path},button("run","Run program",true),{text="This runs a Lua file. Its interface is provided by that program."}} end
      app.p.draw(app.page=="path" and "Open by path" or "Open program",app.page=="review" and base(app.path) or "Advanced",items,"Back"); return
    end
    local items={}
    if app.directory~="/" then items[#items+1]=button("up","Up one folder") end
    if app.scanError then items[#items+1]={text=app.scanError}
    elseif #app.entries==0 then items[#items+1]={text="No Lua programs here. Copy a .lua file here to see it in this list."}
    else for i,entry in ipairs(app.entries) do items[#items+1]=button("file:"..i,(entry.folder and "/ " or "")..entry.name,false,entry.folder and "Open folder" or "Lua program") end end
    items[#items+1]=button("terminal","Terminal",false,"CraftOS command line")
    items[#items+1]=button("path","Open by path",false,"Choose a program name")
    items[#items+1]=button("refresh","Refresh files")
    app.p.draw("Programs",app.directory=="/" and "Files on this computer" or app.directory,items)
  end
  function app.event(event,a,b,c,...)
    if app.page=="process" then
      local width,height=display.getSize()
      local header=w.full and 1 or 0
      if app.process.done and ((event=="mouse_click" and a==1 and c==height and b>=12 and b<=18) or (event=="key" and a==o.keys.f8 and not b)) then
        start(app.path,app.title); return
      elseif (event=="mouse_click" and a==1 and c==height and b<=(app.process.done and 10 or 6)) or (event=="key" and a==o.keys.f7 and not b) then
        if app.process.done then reset() else page("stop") end; return
      elseif app.process.done then
        if event=="key" and (a==o.keys.enter or a==o.keys.numPadEnter) and not b then reset() end
        return
      elseif event=="term_resize" then app.output.resize(width,height-1-header)
      elseif event:match("^mouse_") then
        if c<=header or c>=height then return end
        c=c-header
      end
      app.process.event(event,a,b,c,...); return
    end
    if app.page=="stop" and app.process and not (event=="key" or event=="key_up" or event=="char" or event=="paste" or event:match("^mouse_")) then app.process.event(event,a,b,c,...) end
    local submit=app.page=="path" and app.p.gui.focus=="path" and event=="key" and (a==o.keys.enter or a==o.keys.numPadEnter) and not b
    local action=app.p.event(event,a,b,c,...)
    if submit then action="run" end
    if action=="back" then
      if app.page=="browse" then app.running=false
      elseif app.page=="stop" then app.closing=false; page("process")
      elseif app.page=="error" then page(app.launchPage or "browse")
      else scan(); page("browse") end
    elseif action=="terminal" then start("shell","Terminal")
    elseif action=="path" then app.path=""; page("path")
    elseif action=="run" then start(app.path)
    elseif action=="up" then app.directory=app.directory:match("^(.*)/[^/]+$"); if app.directory=="" then app.directory="/" end; scan(); page("browse")
    elseif action=="refresh" then scan(); app.p.reset()
    elseif action=="keep" then app.closing=false; page("process")
    elseif action=="stop" then local closing=app.closing; reset(); if closing then app.running=false end
    elseif action and action:match("^file:") then
      local entry=app.entries[tonumber(action:sub(6))]
      if entry.folder then app.directory=entry.path; scan(); page("browse")
      else app.path=entry.path; page("review") end
    end
  end
  function app.requestClose()
    if app.process and not app.process.done then app.closing=true; page("stop"); return false end
    return true
  end
  return app
end
return M
