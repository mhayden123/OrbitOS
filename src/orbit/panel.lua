-- Small forms share the Fleet keyboard editor and paginate on short screens.
local gui=require("fleet.gui")
local widgets=require("orbit.widgets")
local M={}
function M.new(display,keys)
  local g=widgets.new(display,keys)
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
      else add(item,item.field and 3 or (item.description and g.height>=19 and 3 or 2)) end
    end
    return pages
  end
  function self.draw(title,subtitle,items,back)
    if self.screen~=title then self.screen,self.page,g.focus=title,1,nil end
    g.begin(title,subtitle)
    local grid=g.size>=54 and g.height>=17 and #items>1
    for _,item in ipairs(items) do if item.text or item.field then grid=false end end
    local pages
    if grid then
      pages={{}}; local capacity=math.max(2,math.floor((g.height-7)/3)*2)
      for i,item in ipairs(items) do local page=math.floor((i-1)/capacity)+1; pages[page]=pages[page] or {}; table.insert(pages[page],item) end
    else pages=paginate(items) end
    if g.focus and g.focus~="next" and g.focus~="back" then
      for page,entries in ipairs(pages) do for _,item in ipairs(entries) do if item.id==g.focus then self.page=page end end end
    end
    if self.wrap and self.page>#pages then self.page=1 end; self.wrap=false
    self.page=math.min(self.page,#pages); local y=4
    for index,item in ipairs(pages[self.page]) do
      if item.field then
        local enter=item.enter
        if not enter then
          local found=false
          for _,candidate in ipairs(items) do
            if found and candidate.id and candidate.enabled~=false then enter=candidate.id; break end
            if candidate==item then found=true end
          end
        end
        enter=enter or "back"
        g.field(item.id,item.label,y,item.value,item.change,{max=item.max or 160,numeric=item.numeric,enter=enter}); y=y+3
      elseif item.text then g.text(2,y,item.text,g.size-2,item.color or "8"); y=y+1
      else
        local detail=item.description and g.height>=19
        local h=detail and 2 or 1
        local x,w=2,g.size-2
        if grid then
          w=math.floor((g.size-5)/2); x=2+(index-1)%2*(w+2); y=4+math.floor((index-1)/2)*3; h=2
        end
        g.button(item.id,item.label,x,y,w,item.id,{height=h,enabled=item.enabled,primary=item.primary,sub=detail and item.description or nil})
        if not grid then y=y+h+1 end
      end
    end
    g.text(2,g.height-3,#pages>1 and ("Page "..self.page.."/"..#pages) or "",g.size-2,"8")
    g.footer(back or "Close",#pages>1 and "More" or nil,"page")
    g.finish()
  end
  function self.event(...)
    local event,direction=...
    if event=="mouse_scroll" then
      if direction>0 then self.page=self.page+1; self.wrap=true else self.page=math.max(1,self.page-1) end
      g.focus=nil; return
    end
    local action=g.event(...)
    if action=="page" then self.page=self.page+1; g.focus=nil; self.wrap=true; return end
    return action
  end
  function self.reset() self.page,g.focus=1,nil; g.previous={} end
  return self
end
return M
