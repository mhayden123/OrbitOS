-- Small forms share the Fleet keyboard editor and paginate on short screens.
local gui=require("fleet.gui")
local M={}
function M.new(display,keys)
  local g=gui.new(display,keys)
  local self={gui=g,page=1,screen=nil}
  local function paginate(items)
    local pages,used={{}},0
    local available=math.max(3,g.height-7)
    local function add(item,cost)
      if used+cost>available then pages[#pages+1]={}; used=0 end
      pages[#pages][#pages[#pages]+1]=item; used=used+cost
    end
    for _,item in ipairs(items) do
      if item.text then
        for _,line in ipairs(gui.wrap(item.text,g.size-2)) do add({text=line,color=item.color},1) end
      else add(item,item.field and 3 or 1) end
    end
    return pages
  end
  function self.draw(title,subtitle,items,back)
    if self.screen~=title then self.screen,self.page,g.focus=title,1,nil end
    g.begin(title,subtitle)
    local pages=paginate(items)
    if self.wrap and self.page>#pages then self.page=1 end; self.wrap=false
    self.page=math.min(self.page,#pages); local y=4
    for _,item in ipairs(pages[self.page]) do
      if item.field then
        g.field(item.id,item.label,y,item.value,item.change,{max=item.max or 160,numeric=item.numeric}); y=y+3
      elseif item.text then g.text(2,y,item.text,g.size-2,item.color or "8"); y=y+1
      else
        g.button(item.id,item.label:sub(1,g.size-4),2,y,g.size-2,item.id,{height=1,enabled=item.enabled,primary=item.primary}); y=y+1
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
  function self.reset() self.page,g.focus=1,nil end
  return self
end
return M
