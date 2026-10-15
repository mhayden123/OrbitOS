-- Strict terminal: fail on out-of-bounds writes instead of silently clipping them.
local M = {}
M.keys = { up=200, down=208, left=203, right=205, enter=28, numPadEnter=156, tab=15,
  escape=1, space=57, backspace=14, delete=211, home=199, ["end"]=207,
  leftShift=42, rightShift=54, leftCtrl=29, rightCtrl=157, u=22 }

function M.new(width, height, color)
  local self = { width=width or 26, height=height or 20, color=color~=false, x=1, y=1, rows={}, writes=0 }
  local api = {}
  api.getSize=function() return self.width,self.height end
  api.isColor=function() return self.color end
  api.setCursorBlink=function(value) self.blink=value end
  api.setTextColor=function() end
  api.setBackgroundColor=function() end
  api.setCursorPos=function(x,y)
    assert(x>=1 and x<=self.width and y>=1 and y<=self.height,"Cursor out of bounds")
    self.x,self.y=x,y
  end
  api.clear=function()
    for y=1,self.height do self.rows[y]={text=string.rep(" ",self.width),fg=string.rep("0",self.width),bg=string.rep("f",self.width)} end
  end
  api.blit=function(text,fg,bg)
    assert(#text==#fg and #text==#bg,"Mismatched blit lengths")
    assert(self.x+#text-1<=self.width,"Text extends past screen edge")
    assert(not text:find("[\n\r]"),"Scrolling text sent to GUI")
    if not self.color then assert(not (fg..bg):find("[^078f]"),"Non-grayscale color on basic computer") end
    local row=self.rows[self.y]
    for key,value in pairs({text=text,fg=fg,bg=bg}) do row[key]=row[key]:sub(1,self.x-1)..value..row[key]:sub(self.x+#value) end
    self.writes=self.writes+1
  end
  api.clear()
  self.api=api
  function self.text() local lines={}; for y=1,self.height do lines[y]=self.rows[y].text end; return table.concat(lines,"\n") end
  function self.resize(w,h) self.width,self.height=w,h; api.clear() end
  return self
end
return M
