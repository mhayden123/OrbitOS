-- Orbit styling with Fleet's retained focus and keyboard editor.
local gui=require("fleet.gui")
local theme=require("orbit.theme")
local M={}
function M.new(display,keys,options)
  options=options or {}
  local g=gui.new(display,keys)
  theme.apply(display)
  local text=g.text
  function g.text(x,y,value,width,color,bg)
    color=color=="8" and "7" or color or "f"
    if not g.color and not color:match("^[078f]$") then color="7" end
    text(x,y,value,width,color,bg)
  end
  function g.begin(title,subtitle)
    g.width,g.height=display.getSize(); g.color=display.isColor()
    g.size=math.min(options.maxWidth or 68,g.width); g.left=math.floor((g.width-g.size)/2)+1
    g.rows,g.widgets={},{}
    for y=1,g.height do g.rows[y]={text=string.rep(" ",g.width),fg=string.rep("f",g.width),bg=string.rep("0",g.width)} end
    g.text(2,1,theme.fit(theme.title(title),g.size-8),g.size-8,"f")
    g.text(2,2,theme.fit(subtitle,g.size-2),g.size-2,"7")
    g.text(2,g.height,g.width>=40 and "Tab to navigate  Enter to choose" or "Tab / Arrows  Enter",g.size-2,"7")
  end
  function g.finish()
    local focused=g.find(g.focus)
    if not focused or not focused.enabled then g.moveFocus(1) end
    g.cursor=nil
    for _,w in ipairs(g.widgets) do
      local selected=g.focus==w.id
      local bg,fg="8","f"
      if not w.enabled then bg,fg="0","7"
      elseif selected then bg,fg=g.color and "b" or "f","0"
      elseif w.primary then bg,fg=g.color and "b" or "7","0"
      elseif w.danger then bg,fg=g.color and "e" or "7","0" end
      g.fill(w.x,w.y,w.width,w.height,bg)
      if w.kind=="field" then
        local cursor=math.min(g.cursors[w.id] or #w.value,#w.value); g.cursors[w.id]=cursor
        local offset=math.max(0,cursor-(w.width-3))
        text(w.x,w.y,selected and ">" or " ",1,fg,bg)
        text(w.x+1,w.y,w.value:sub(offset+1),w.width-2,fg,bg)
        if selected then g.cursor={x=g.left+w.x+cursor-offset,y=w.y} end
      else
        text(w.x,w.y,selected and ">" or " ",1,fg,bg)
        text(w.x+1,w.y,theme.fit(w.label,w.width-2),w.width-2,fg,bg)
        if w.sub and w.height>1 then text(w.x+1,w.y+1,theme.fit(w.sub,w.width-2),w.width-2,fg,bg) end
      end
    end
    display.setCursorBlink(false)
    for y,row in ipairs(g.rows) do
      local signature=row.text..row.fg..row.bg
      if g.previous[y]~=signature then display.setCursorPos(1,y); display.blit(row.text,row.fg,row.bg); g.previous[y]=signature end
    end
    for y=g.height+1,#g.previous do g.previous[y]=nil end
    if g.cursor then display.setCursorPos(g.cursor.x,g.cursor.y); display.setCursorBlink(true) end
  end
  return g
end
return M
