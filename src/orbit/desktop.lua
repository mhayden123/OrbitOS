local surface=require("orbit.surface")
local theme=require("orbit.theme")
local M={}
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function inside(x,y,r) return x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
function M.new(display,keys,options)
  options=options or {}
  local width,height=display.getSize()
  local self={windows={},nextId=0,launcher=true,menu=1,query="",running=true,width=width,height=height,keys=keys}
  local restorePalette=theme.apply(display)
  local canvas=surface.new(width,height,display.isColor())
  local function compact() return self.width<60 or self.height<22 end
  local function find(id) for i,w in ipairs(self.windows) do if w.id==id then return w,i end end end
  self.find=find
  function self.focus(id)
    local w,i=find(id); if not w then return end
    table.remove(self.windows,i); self.windows[#self.windows+1]=w; w.hidden=false; self.focused=id; self.dockPage=nil
  end
  local function invoke(w,method,...)
    if not w.app or not w.app[method] then return end
    local ok,why=pcall(w.app[method],...)
    if not ok then w.error=tostring(why); if w.app.close then pcall(w.app.close) end; w.app={} end
  end
  local function resize(w)
    w.full=w.maximized or compact() or self.width<w.minW+4 or self.height<w.minH+4
    w.surface.term._orbitHeaderReserve=w.full and (w.maximized and 15 or 10) or 0
    local sw,sh=w.full and self.width or w.w-2,w.full and self.height or w.h-2
    if w.surface.width~=sw or w.surface.height~=sh then w.surface.resize(sw,sh); invoke(w,"event","term_resize") end
  end
  function self.geometry(w,x,y,ww,hh)
    if w.full then return end
    w.w=clamp(ww,w.minW+2,self.width-2); w.h=clamp(hh,w.minH+2,self.height-3)
    w.x=clamp(x,1,self.width-w.w); w.y=clamp(y,2,self.height-w.h-1)
    resize(w)
  end
  function self.open(definition)
    if not definition then return end
    if definition.windowId then self.focus(definition.windowId); self.launcher=false; return find(definition.windowId) end
    if definition.singleton then for _,w in ipairs(self.windows) do if w.kind==definition.id then self.focus(w.id); self.launcher=false; return w end end end
    if #self.windows>=8 then self.notice="8 windows: close one."; return end
    self.nextId=self.nextId+1
    local w={id=self.nextId,kind=definition.id,title=definition.title,minW=definition.minW or 26,minH=definition.minH or 10,
      x=3+(self.nextId-1)%3*3,y=3+(self.nextId-1)%3,w=math.min(definition.width or 58,self.width-6),h=math.min(definition.height or 23,self.height-5)}
    w.w=math.max(w.minW+2,w.w); w.h=math.max(w.minH+2,w.h)
    w.surface=surface.new(1,1,display.isColor()); resize(w)
    if not w.full then self.geometry(w,w.x,w.y,w.w,w.h) end
    self.windows[#self.windows+1]=w; self.focused=w.id; self.launcher=false; self.notice=nil; self.dockPage=nil
    local ok,app=pcall(definition.create,w.surface.term,w)
    if ok then w.app=app else w.error=tostring(app); w.app={} end
    return w
  end
  function self.close(id,force)
    local w,i=find(id); if not w then return end
    if not force and w.app and w.app.requestClose then
      local ok,allowed=pcall(w.app.requestClose)
      if ok and allowed==false then self.focus(id); self.launcher=false; return end
    end
    invoke(w,"close"); if options.closed then options.closed(id) end
    table.remove(self.windows,i); self.focused=nil
    for j=#self.windows,1,-1 do if not self.windows[j].hidden then self.focused=self.windows[j].id; break end end
    if not self.focused then self.launcher=true end
  end
  function self.maximize(w) if w then w.maximized=not w.maximized; resize(w) end end
  function self.appInput(id,...)
    local w=find(id); if w then invoke(w,"event",...); if w.app.running==false then self.close(id) end end
  end
  function self.tick()
    for _,w in ipairs({table.unpack(self.windows)}) do invoke(w,"tick"); if w.app.running==false then self.close(w.id) end end
  end
  local function launcherLayout()
    local mw=math.min(66,self.width-2); local cols=self.width>=60 and 2 or 1
    local mh=math.min(self.height-2,23)
    local box={x=math.floor((self.width-mw)/2)+1,y=math.floor((self.height-mh)/2)+1,w=mw,h=mh}
    local matches={}
    local choices=options.apps or {}
    if self.showRunning then choices={}; for _,w in ipairs(self.windows) do choices[#choices+1]={windowId=w.id,title=w.title,description="Return to this window"} end end
    for _,app in ipairs(choices) do
      if (app.title.." "..(app.description or "")):lower():find(self.query:lower(),1,true) then matches[#matches+1]=app end
    end
    local stride=mh>=22 and 3 or mh>=18 and 2 or 1
    local capacity=math.max(cols,math.floor((mh-7)/stride)*cols)
    self.menu=clamp(self.menu,1,math.max(1,#matches))
    local first=math.floor((self.menu-1)/capacity)*capacity+1
    local cw=math.floor((mw-4-(cols-1)*2)/cols); local cards={}
    for i=first,math.min(#matches,first+capacity-1) do
      local n=i-first
      cards[#cards+1]={x=box.x+2+n%cols*(cw+2),y=box.y+5+math.floor(n/cols)*stride,w=cw,h=stride==3 and 2 or 1,index=i,app=matches[i]}
    end
    return box,cards,matches,cols
  end
  self.launcherLayout=launcherLayout
  local function dockLayout()
    local ordered={table.unpack(self.windows)}; table.sort(ordered,function(a,b) return a.id<b.id end)
    local slots=math.max(1,math.floor((self.width-16)/12)); local current=1
    for i,w in ipairs(ordered) do if w.id==self.focused then current=i end end
    local pages=math.max(1,math.ceil(#ordered/slots))
    local page=clamp(self.dockPage or math.floor((current-1)/slots)+1,1,pages)
    local first=(page-1)*slots+1
    local result={{x=2,y=self.height,w=7,h=1,apps=true}}
    for i=first,math.min(#ordered,first+slots-1) do result[#result+1]={x=10+(i-first)*12,y=self.height,w=11,h=1,window=ordered[i]} end
    if pages>1 then
      result[#result+1]={x=self.width-5,y=self.height,w=2,h=1,page=(page-2)%pages+1,label="<"}
      result[#result+1]={x=self.width-2,y=self.height,w=2,h=1,page=page%pages+1,label=">"}
    end
    return result
  end
  self.dockLayout=dockLayout
  function self.event(event,a,b,c,...)
    if event=="term_resize" then
      self.width,self.height=display.getSize(); canvas.resize(self.width,self.height); self.drag=nil; self.mode=nil
      for _,w in ipairs(self.windows) do resize(w); if not w.full then self.geometry(w,w.x,w.y,w.w,w.h) end end
      return
    end
    local w=find(self.focused)
    if event=="key" and not b then
      if a==keys.f1 then self.launcher=not self.launcher; self.mode=nil; self.drag=nil; self.query=""; self.menu=1; return
      elseif a==keys.f2 then local first=self.windows[1]; if first then self.focus(first.id); self.launcher=false end; return
      elseif not self.launcher then
        if a==keys.f3 then self.maximize(w); return
        elseif a==keys.f4 then self.mode=w and not w.full and "move" or nil; return
        elseif a==keys.f5 then self.mode=w and not w.full and "size" or nil; return
        elseif a==keys.f6 and w then if options.cast then options.cast(w.id) end; return
        elseif a==keys.f10 and w then self.close(w.id); return end
      end
    end
    if self.mode and w then
      if event=="key" then
        if a==keys.enter or a==keys.escape then self.mode=nil
        else
          local dx=a==keys.left and -1 or a==keys.right and 1 or 0; local dy=a==keys.up and -1 or a==keys.down and 1 or 0
          self.geometry(w,w.x+(self.mode=="move" and dx or 0),w.y+(self.mode=="move" and dy or 0),w.w+(self.mode=="size" and dx or 0),w.h+(self.mode=="size" and dy or 0))
        end
      end
      return
    end
    -- The dock stays visible outside the app library, so its controls remain active.
    if event=="mouse_click" and a==1 and c==self.height and not (w and w.full and not w.hidden) then
      for _,hit in ipairs(dockLayout()) do if inside(b,c,hit) then
        if hit.apps then self.launcher=not self.launcher; self.query=""; self.menu=1
        elseif hit.page then self.dockPage=hit.page
        else self.focus(hit.window.id); self.launcher=false end
        return
      end end
      return
    end
    local input=event=="key" or event=="key_up" or event=="char" or event=="paste" or event:match("^mouse_") or event=="terminate"
    if self.launcher and input then
      local box,cards,matches,cols=launcherLayout()
      if event=="key" then
        if a==keys.escape then if #self.query>0 then self.query=""; self.menu=1 else self.launcher=false end
        elseif a==keys.backspace then self.query=self.query:sub(1,-2); self.menu=1
        elseif a==keys.enter and not b then self.open(matches[self.menu])
        elseif #matches>0 then
          local delta=(a==keys.down and cols or a==keys.up and -cols or a==keys.tab and 1 or a==keys.right and 1 or a==keys.left and -1 or 0)
          self.menu=(self.menu-1+delta)%#matches+1
        end
      elseif event=="char" or event=="paste" then self.query=(self.query..tostring(a):gsub("[%z\1-\31\127-\255]","")):sub(1,32); self.menu=1
      elseif event=="mouse_scroll" then self.menu=clamp(self.menu+a,1,math.max(1,#matches))
      elseif event=="mouse_click" and a==1 then
        if c==box.y+1 then
          if b>=box.x+2 and b<=box.x+7 then self.showRunning=false; self.query=""; self.menu=1; return
          elseif b>=box.x+9 and b<=box.x+19 then self.showRunning=true; self.query=""; self.menu=1; return end
        end
        for _,card in ipairs(cards) do if inside(b,c,card) then self.menu=card.index; self.open(card.app); return end end
        if c==box.y and b==box.x+box.w-2 then self.launcher=false
        elseif not inside(b,c,box) then self.launcher=false end
      end
      return
    end
    if event=="mouse_click" and a==1 then
      if c==1 and (b<=7 and not (w and w.full) or b>=self.width-5 and w and w.full) then self.launcher=true; self.query=""; self.menu=1; return end
      if c==1 and w and w.full then
        if b>=self.width-9 and b<=self.width-7 then self.close(w.id); return end
        if w.maximized and b>=self.width-14 and b<=self.width-12 then self.maximize(w); return end
      end
      if w and w.full then self.appInput(w.id,event,a,b,c); return end
      for i=#self.windows,1,-1 do
        local hit=self.windows[i]
        if not hit.hidden and inside(b,c,hit) then
          self.focus(hit.id); w=hit
          if c==w.y then
            local offset=b-w.x
            if offset<=2 then self.close(w.id)
            elseif offset<=5 then w.hidden=true; self.focused=nil; self.launcher=true
            elseif offset<=8 then self.maximize(w)
            elseif offset>=w.w-7 then if options.cast then options.cast(w.id) end
            else self.drag={id=w.id,x=b,y=c,wx=w.x,wy=w.y,ww=w.w,wh=w.h,mode="move"} end
          elseif c==w.y+w.h-1 then self.drag={id=w.id,x=b,y=c,wx=w.x,wy=w.y,ww=w.w,wh=w.h,mode="size"}
          elseif b>w.x and b<w.x+w.w-1 then self.appInput(w.id,event,a,b-w.x,c-w.y) end
          return
        end
      end
      return
    elseif event=="mouse_drag" and self.drag then
      local d=self.drag; local target=find(d.id)
      if target then self.geometry(target,d.wx+(d.mode=="move" and b-d.x or 0),d.wy+(d.mode=="move" and c-d.y or 0),d.ww+(d.mode=="size" and b-d.x or 0),d.wh+(d.mode=="size" and c-d.y or 0)) end
      return
    elseif event=="mouse_up" and self.drag then self.drag=nil; return end
    if input then
      if w and not w.hidden then
        if event:match("^mouse_") and not w.full then
          if b<=w.x or b>=w.x+w.w-1 or c<=w.y or c>=w.y+w.h-1 then return end
          b,c=b-w.x,c-w.y
        end
        self.appInput(w.id,event,a,b,c,...)
      end
    else for _,app in ipairs({table.unpack(self.windows)}) do self.appInput(app.id,event,a,b,c,...) end end
  end
  function self.render()
    local actualWidth,actualHeight=display.getSize()
    if actualWidth~=self.width or actualHeight~=self.height then self.event("term_resize") end
    local t=canvas.term; t.setBackgroundColor(32768); t.clear()
    local function text(x,y,value,fg,bg) surface.text(t,x,y,value,2^tonumber(fg or "f",16),2^tonumber(bg or "0",16)) end
    local function fill(x,y,w,h,bg) for row=y,y+h-1 do text(x,row,string.rep(" ",math.max(0,w)),"f",bg) end end
    for _,w in ipairs(self.windows) do
      w.surface.term._orbitWindowTitle=not w.full and w.title or nil
      invoke(w,"render")
      if w.error then w.surface.term.clear(); surface.text(w.surface.term,2,2,"This app stopped."); surface.text(w.surface.term,2,4,w.error); surface.text(w.surface.term,2,6,"F10 closes the window.") end
    end
    fill(1,1,self.width,1,"8"); text(2,1,"Orbit", "f","8")
    text(10,1,"Workspace", "7","8"); text(self.width-#(options.subtitle or "")-1,1,options.subtitle or "","7","8")
    text(math.max(2,math.floor((self.width-8)/2)),math.floor(self.height/2),"O R B I T","8","f")
    local function draw(w)
      local x,y=w.full and 1 or w.x+1,w.full and 1 or w.y+1
      if not w.full then
        local bar=w.id==self.focused and "f" or "7"
        fill(w.x+1,w.y+1,w.w,w.h,"7"); fill(w.x,w.y,w.w,w.h,"8"); fill(w.x,w.y,w.w,1,bar)
        text(w.x,w.y,"[x]", "0","e"); text(w.x+3,w.y,"[-]","0","7"); text(w.x+6,w.y,"[+]","0","d")
        text(w.x+10,w.y,theme.fit(w.title,w.w-18),"0",bar)
        text(w.x+w.w-7,w.y,"[Cast]","0",bar); text(w.x+w.w-2,w.y+w.h-1,"/","f","8")
      end
      for row=1,w.surface.height do t.setCursorPos(x,y+row-1); t.blit(w.surface.term.getLine(row)) end
    end
    local focused=find(self.focused)
    if focused and focused.full and not focused.hidden then
      draw(focused)
      if focused.maximized then text(self.width-14,1,"[R]","0","7") end
      text(self.width-9,1,"[x]","0","e"); text(self.width-5,1,"[Apps]","0","b")
    else
      for _,w in ipairs(self.windows) do if not w.hidden then draw(w) end end
      fill(1,self.height,self.width,1,"8")
      for _,hit in ipairs(dockLayout()) do
        local label=hit.apps and " Apps " or hit.label or theme.fit(hit.window.title,hit.w-2)
        local active=hit.window and hit.window.id==self.focused
        fill(hit.x,hit.y,hit.w,1,active and "b" or "8"); text(hit.x,hit.y," "..label,active and "0" or "f",active and "b" or "8")
      end
    end
    if self.mode then fill(1,self.height,self.width,1,"8"); text(2,self.height,"Arrows to "..self.mode.."   Enter to finish","f","8") end
    if self.launcher then
      local box,cards,matches=launcherLayout()
      fill(box.x+1,box.y+1,box.w,box.h,"7"); fill(box.x,box.y,box.w,box.h,"0")
      text(box.x+2,box.y,"Orbit", "f","0"); text(box.x+box.w-2,box.y,"x","7","0")
      text(box.x+2,box.y+1,"[Apps]",self.showRunning and "f" or "0",self.showRunning and "8" or "b")
      text(box.x+9,box.y+1,"[Running:"..#self.windows.."]",self.showRunning and "0" or "f",self.showRunning and "b" or "8")
      if self.notice then text(box.x+2,box.y+2,theme.fit(self.notice,box.w-4),"e","0") end
      fill(box.x+2,box.y+3,box.w-4,1,"8"); text(box.x+2,box.y+3,"["..theme.fit(#self.query>0 and self.query or "Type here...",box.w-6),"f","8"); text(box.x+box.w-3,box.y+3,"]","f","8")
      for _,card in ipairs(cards) do
        local selected=card.index==self.menu; local bg=selected and "b" or "9"; local fg=selected and "0" or "f"
        if not display.isColor() then bg=selected and "f" or "8" end
        fill(card.x,card.y,card.w,card.h,bg)
        text(card.x,card.y,(selected and "> " or "  ")..theme.fit(card.app.title,card.w-3),fg,bg)
        local detail=card.app.description or "Open app"
        if card.app.singleton then for _,open in ipairs(self.windows) do if open.kind==card.app.id then detail="Open: "..open.title end end end
        if card.h>1 then text(card.x+2,card.y+1,theme.fit(detail,card.w-3),selected and "0" or "7",bg) end
      end
      if #matches==0 then text(box.x+2,box.y+5,self.showRunning and #self.windows==0 and "No open windows." or "No matching apps.","7","0") end
      text(box.x+2,box.y+box.h-1,theme.fit("Enter:open F2:switch",box.w-4),"7","0")
    end
    display.setCursorBlink(false)
    local grayscale=function(value) return (value:gsub("[^078f]","7")) end
    for y=1,self.height do
      local line,fg,bg=t.getLine(y); if not display.isColor() then fg,bg=grayscale(fg),grayscale(bg) end
      display.setCursorPos(1,y); display.blit(line,fg,bg)
    end
    if focused and not focused.hidden and not self.launcher and focused.surface.blink then
      local s=focused.surface
      if s.x>=1 and s.x<=s.width and s.y>=1 and s.y<=s.height then display.setCursorPos((focused.full and 0 or focused.x)+s.x,(focused.full and 0 or focused.y)+s.y); display.setCursorBlink(true) end
    end
    if self.launcher then
      local box=launcherLayout()
      display.setCursorPos(box.x+3+math.min(#self.query,box.w-7),box.y+3); display.setCursorBlink(true)
    end
  end
  function self.stop()
    local ids={}; for _,w in ipairs(self.windows) do ids[#ids+1]=w.id end
    for _,id in ipairs(ids) do self.close(id,true) end
    restorePalette(); self.running=false
  end
  return self
end
return M
