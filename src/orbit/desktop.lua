local surface=require("orbit.surface")
local M={}
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
function M.new(display,keys,options)
  options=options or {}
  local width,height=display.getSize()
  local self={windows={},nextId=0,launcher=true,menu=1,running=true,width=width,height=height,keys=keys}
  local canvas=surface.new(width,height,display.isColor())
  local function find(id) for i,w in ipairs(self.windows) do if w.id==id then return w,i end end end
  self.find=find
  function self.focus(id)
    local w,i=find(id); if not w then return end
    table.remove(self.windows,i); self.windows[#self.windows+1]=w; w.hidden=false; self.focused=id
  end
  local function invoke(w,method,...)
    if not w.app or not w.app[method] then return end
    local ok,why=pcall(w.app[method],...)
    if not ok then w.error=tostring(why); if w.app.close then pcall(w.app.close) end; w.app={} end
  end
  local function resize(w)
    local sw,sh=w.full and self.width or w.w,w.full and self.height or w.h-2
    if w.surface.width~=sw or w.surface.height~=sh then
      w.surface.resize(sw,sh); invoke(w,"event","term_resize")
    end
  end
  function self.open(definition)
    if definition.singleton then for _,w in ipairs(self.windows) do if w.kind==definition.id then self.focus(w.id); self.launcher=false; return w end end end
    if #self.windows>=8 then return nil,"Close a window first (maximum eight)." end
    self.nextId=self.nextId+1
    local w={id=self.nextId,kind=definition.id,title=definition.title,minW=definition.minW or 26,minH=definition.minH or 10,
      x=2+(self.nextId-1)%3,y=2+(self.nextId-1)%2,w=math.min(38,self.width-2),h=math.min(14,self.height-3)}
    w.full=self.width<w.minW+2 or self.height<w.minH+5
    w.w=clamp(w.w,w.minW,self.width); w.h=clamp(w.h,w.minH+2,self.height)
    w.x=clamp(w.x,1,self.width-w.w+1); w.y=clamp(w.y,2,self.height-w.h)
    w.surface=surface.new(w.full and self.width or w.w,w.full and self.height or w.h-2,display.isColor())
    self.windows[#self.windows+1]=w; self.focused=w.id; self.launcher=false
    local ok,app=pcall(definition.create,w.surface.term,w)
    if ok then w.app=app else w.error=tostring(app); w.app={} end
    return w
  end
  function self.close(id)
    local w,i=find(id); if not w then return end
    invoke(w,"close"); if options.closed then options.closed(id) end
    table.remove(self.windows,i); self.focused=self.windows[#self.windows] and self.windows[#self.windows].id
    if not self.focused then self.launcher=true end
  end
  function self.maximize(w)
    if not w then return end
    if w.full and self.width>=w.minW+2 and self.height>=w.minH+5 then w.full=false else w.full=true end
    resize(w)
  end
  function self.geometry(w,x,y,ww,hh)
    if w.full then return end
    w.w=clamp(ww,w.minW,self.width); w.h=clamp(hh,w.minH+2,self.height-2)
    w.x=clamp(x,1,self.width-w.w+1); w.y=clamp(y,2,self.height-w.h)
    resize(w)
  end
  function self.appInput(id,...)
    local w=find(id); if w then invoke(w,"event",...); if w.app.running==false then self.close(id) end end
  end
  function self.tick()
    local copy={table.unpack(self.windows)}
    for _,w in ipairs(copy) do invoke(w,"tick"); if w.app.running==false then self.close(w.id) end end
  end
  function self.event(event,a,b,c,...)
    if event=="term_resize" then
      self.width,self.height=display.getSize(); canvas.resize(self.width,self.height)
      for _,w in ipairs(self.windows) do
        if self.width<w.minW+2 or self.height<w.minH+5 then w.full=true end
        if w.full then resize(w) else self.geometry(w,w.x,w.y,w.w,w.h) end
      end
      return
    end
    local w=find(self.focused)
    if event=="key" and not b then
      if a==keys.f1 then self.launcher=not self.launcher; self.mode=nil; return
      elseif a==keys.f2 then
        local first=self.windows[1]; if first then self.focus(first.id) end; self.launcher=false; return
      elseif a==keys.f3 then self.maximize(w); return
      elseif a==keys.f4 then self.mode="move"; return
      elseif a==keys.f5 then self.mode="size"; return
      elseif a==keys.f6 and w then if options.cast then options.cast(w.id) end; return
      elseif a==keys.f10 and w then self.close(w.id); return end
    end
    if self.mode and w then
      if event=="key" then
        if a==keys.enter or a==keys.escape then self.mode=nil
        else
          local dx=a==keys.left and -1 or a==keys.right and 1 or 0
          local dy=a==keys.up and -1 or a==keys.down and 1 or 0
          self.geometry(w,w.x+(self.mode=="move" and dx or 0),w.y+(self.mode=="move" and dy or 0),
            w.w+(self.mode=="size" and dx or 0),w.h+(self.mode=="size" and dy or 0))
        end
      end
      return
    end
    local input=event=="key" or event=="key_up" or event=="char" or event=="paste" or event:match("^mouse_") or event=="terminate"
    if self.launcher and input then
      local apps=options.apps or {}
      if event=="key" then
        if a==keys.down or a==keys.tab then self.menu=self.menu%#apps+1
        elseif a==keys.up then self.menu=(self.menu-2)%#apps+1
        elseif a==keys.escape then self.launcher=false
        elseif a==keys.enter then self.open(apps[self.menu]) end
      elseif event=="mouse_click" and a==1 and b>=2 and b<=math.min(30,self.width-1) and c>=4 and c<4+#apps then
        self.menu=c-3; self.open(apps[self.menu])
      end
      return
    end
    if event=="mouse_click" and a==1 then
      if w and w.full then
        if c==1 and b>=self.width-5 then self.launcher=true else self.appInput(w.id,event,a,b,c) end
        return
      end
      if c==1 and b<=7 then self.launcher=true; return end
      if c==self.height then
        local slot=math.floor((b-1)/10)+1; local target=self.windows[slot]
        if target then self.focus(target.id) end; return
      end
      for i=#self.windows,1,-1 do
        local hit=self.windows[i]
        if not hit.hidden and b>=hit.x and b<hit.x+hit.w and c>=hit.y and c<hit.y+hit.h then
          self.focus(hit.id); w=hit
          if c==w.y then
            local offset=w.x+w.w-1-b
            if offset==0 then self.close(w.id)
            elseif offset==2 then self.maximize(w)
            elseif offset==4 then w.hidden=true; self.focused=nil; self.launcher=true
            elseif offset==6 then if options.cast then options.cast(w.id) end
            else self.drag={id=w.id,x=b,y=c,wx=w.x,wy=w.y,ww=w.w,wh=w.h,mode="move"} end
          elseif c==w.y+w.h-1 then self.drag={id=w.id,x=b,y=c,wx=w.x,wy=w.y,ww=w.w,wh=w.h,mode="size"}
          else self.appInput(w.id,event,a,b-w.x+1,c-w.y) end
          return
        end
      end
      return
    elseif event=="mouse_drag" and self.drag then
      local d=self.drag; local target=find(d.id)
      if target then self.geometry(target,d.wx+(d.mode=="move" and b-d.x or 0),d.wy+(d.mode=="move" and c-d.y or 0),
        d.ww+(d.mode=="size" and b-d.x or 0),d.wh+(d.mode=="size" and c-d.y or 0)) end
      return
    elseif event=="mouse_up" and self.drag then self.drag=nil; return end
    if input then
      if w then
        if event:match("^mouse_") and not w.full then
          if b<w.x or b>=w.x+w.w or c<=w.y or c>=w.y+w.h-1 then return end
          b,c=b-w.x+1,c-w.y
        end
        self.appInput(w.id,event,a,b,c,...)
      end
    else
      local copy={table.unpack(self.windows)}
      for _,app in ipairs(copy) do self.appInput(app.id,event,a,b,c,...) end
    end
  end
  function self.render()
    local t=canvas.term; t.setBackgroundColor(display.isColor() and 2048 or 32768); t.clear()
    -- Hidden windows still render into their buffers for live monitor casting.
    for _,w in ipairs(self.windows) do
      invoke(w,"render")
      if w.error then w.surface.term.clear(); surface.text(w.surface.term,1,1,"App stopped. F10 closes."); surface.text(w.surface.term,1,3,w.error) end
    end
    surface.text(t,1,1,("[Apps] ORBIT OS  "..(options.subtitle or "")):sub(1,self.width),1,128)
    local function draw(w)
      local x,y=w.full and 1 or w.x,w.full and 1 or w.y+1
      if not w.full then
        local bar=(w.title..string.rep(" ",w.w)):sub(1,w.w-7).."C _ ^ X"
        surface.text(t,w.x,w.y,bar,1,w.id==self.focused and 512 or 128)
      end
      for row=1,w.surface.height do t.setCursorPos(x,y+row-1); t.blit(w.surface.term.getLine(row)) end
      if not w.full then surface.text(t,w.x,w.y+w.h-1,string.rep("-",w.w-1).."/",256,128) end
    end
    local focused=find(self.focused)
    if focused and focused.full then draw(focused); surface.text(t,self.width-5,1," Apps ",1,128)
    else
      for _,w in ipairs(self.windows) do if not w.hidden then draw(w) end end
      for i,w in ipairs(self.windows) do surface.text(t,(i-1)*10+1,self.height,(w.title.."        "):sub(1,9),1,w.id==self.focused and 512 or 128) end
    end
    if self.mode then surface.text(t,1,self.height,"Arrows: "..self.mode.." | Enter: done",1,128) end
    if self.launcher then
      local mw=math.min(30,self.width-2)
      for y=2,math.min(self.height-1,5+#(options.apps or {})) do surface.text(t,2,y,string.rep(" ",mw),1,128) end
      surface.text(t,3,2,"ORBIT / APPS",1,128)
      for i,app in ipairs(options.apps or {}) do surface.text(t,2,3+i,((i==self.menu and "> " or "  ")..app.title..string.rep(" ",mw)):sub(1,mw),1,i==self.menu and 512 or 128) end
      surface.text(t,3,5+#(options.apps or {}),"F1 menu  F2 switch",1,128)
    end
    display.setCursorBlink(false)
    local grayscale=function(value) return (value:gsub("[^078f]","7")) end
    for y=1,self.height do
      local text,fg,bg=t.getLine(y)
      if not display.isColor() then fg,bg=grayscale(fg),grayscale(bg) end
      display.setCursorPos(1,y); display.blit(text,fg,bg)
    end
    if focused and not self.launcher and focused.surface.blink then
      local s=focused.surface
      if s.x>=1 and s.x<=s.width and s.y>=1 and s.y<=s.height then
        display.setCursorPos((focused.full and 0 or focused.x-1)+s.x,(focused.full and 0 or focused.y)+s.y); display.setCursorBlink(true)
      end
    end
  end
  function self.stop() local ids={}; for _,w in ipairs(self.windows) do ids[#ids+1]=w.id end; for _,id in ipairs(ids) do self.close(id) end; self.running=false end
  return self
end
return M
