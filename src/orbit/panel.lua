-- Small forms share the Fleet keyboard editor and paginate on short screens.
local gui=require("fleet.gui")
local M={}
function M.new(display,keys)
  local g=gui.new(display,keys)
  local self={gui=g,page=1,screen=nil}
  function self.draw(title,subtitle,items,back)
    if self.screen~=title then self.screen,self.page,g.focus=title,1,nil end
    g.begin(title,subtitle)
    local pages,used={{}},0
    local available=math.max(3,g.height-7)
    for _,item in ipairs(items) do
      local cost=item.field and 3 or 1
      if used+cost>available then pages[#pages+1]={}; used=0 end
      pages[#pages][#pages[#pages]+1]=item; used=used+cost
    end
    self.page=math.min(self.page,#pages); local y=4
    for _,item in ipairs(pages[self.page]) do
      if item.field then
        g.field(item.id,item.label,y,item.value,item.change,{max=item.max or 160,numeric=item.numeric}); y=y+3
      elseif item.text then g.text(2,y,item.text,g.size-2,item.color or "8"); y=y+1
      else
        g.button(item.id,item.label:sub(1,g.size-4),2,y,g.size-2,item.id,{height=1,enabled=item.enabled}); y=y+1
      end
    end
    g.text(2,g.height-3,#pages>1 and ("Page "..self.page.."/"..#pages) or "",g.size-2,"8")
    g.footer(back or "Close",#pages>1 and "More" or nil,"page")
    g.finish()
  end
  function self.event(...)
    local action=g.event(...)
    if action=="page" then self.page=self.page+1; g.focus=nil; self.wrap=true; return end
    return action
  end
  -- At the end, More returns to the first page.
  local draw=self.draw
  self.draw=function(...)
    if self.wrap then
      local _,h=display.getSize(); local items=select(3,...); local count,used=1,0
      for _,v in ipairs(items) do local cost=v.field and 3 or 1; if used+cost>math.max(3,h-7) then count=count+1; used=0 end; used=used+cost end
      if self.page>count then self.page=1 end; self.wrap=false
    end
    draw(...)
  end
  function self.reset() self.page,g.focus=1,nil end
  return self
end
return M
