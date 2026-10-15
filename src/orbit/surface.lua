-- Buffered terminal redirects keep applications from drawing over one another.
local M = {}
local hex = "0123456789abcdef"
local palette = {0xf0f0f0,0xf2b233,0xe57fd8,0x99b2f2,0xdede6c,0x7fcc19,0xf2b2cc,0x4c4c4c,
  0x999999,0x4c99b2,0xb266e5,0x3366cc,0x7f664c,0x57a64e,0xcc4c4c,0x111111}
local function index(color)
  for i=0,15 do if color==2^i then return i+1 end end
  error("Invalid terminal colour",2)
end
function M.new(width,height,color)
  local s={width=width,height=height,color=color~=false,rows={},x=1,y=1,fg="0",bg="f",blink=false,palette={}}
  local t={}
  local function blank() return {string.rep(" ",s.width),string.rep(s.fg,s.width),string.rep(s.bg,s.width)} end
  for i,v in ipairs(palette) do s.palette[i]={math.floor(v/65536)/255,math.floor(v/256)%256/255,v%256/255} end
  function t.getSize() return s.width,s.height end
  function t.isColor() return s.color end
  t.isColour=t.isColor
  function t.setCursorPos(x,y) s.x,s.y=math.floor(x),math.floor(y) end
  function t.getCursorPos() return s.x,s.y end
  function t.setCursorBlink(v) s.blink=v==true end
  function t.getCursorBlink() return s.blink end
  function t.setTextColor(v) s.fg=hex:sub(index(v),index(v)) end
  function t.getTextColor() return 2^tonumber(s.fg,16) end
  function t.setBackgroundColor(v) s.bg=hex:sub(index(v),index(v)) end
  function t.getBackgroundColor() return 2^tonumber(s.bg,16) end
  function t.clear() for y=1,s.height do s.rows[y]=blank() end end
  function t.clearLine() if s.rows[s.y] then s.rows[s.y]=blank() end end
  function t.blit(text,fg,bg)
    assert(type(text)=="string" and #text==#fg and #text==#bg,"Invalid blit lengths")
    assert(not (fg..bg):find("[^0-9a-f]"),"Invalid blit colours")
    local row=s.rows[s.y]
    if row then
      local first,last=math.max(1,2-s.x),math.min(#text,s.width-s.x+1)
      if first<=last then
        local x=s.x+first-1
        for i,value in ipairs({text,fg,bg}) do row[i]=row[i]:sub(1,x-1)..value:sub(first,last)..row[i]:sub(x+last-first+1) end
      end
    end
    s.x=s.x+#text
  end
  function t.write(text) text=tostring(text); t.blit(text,string.rep(s.fg,#text),string.rep(s.bg,#text)) end
  function t.scroll(n)
    n=math.floor(n); local old=s.rows; s.rows={}
    for y=1,s.height do s.rows[y]=old[y+n] or blank() end
  end
  function t.getLine(y) local r=assert(s.rows[y],"Line outside terminal"); return r[1],r[2],r[3] end
  function t.setPaletteColor(c,r,g,b)
    if not g then local v=r; r,g,b=math.floor(v/65536)/255,math.floor(v/256)%256/255,v%256/255 end
    s.palette[index(c)]={r,g,b}
  end
  function t.getPaletteColor(c) return table.unpack(s.palette[index(c)]) end
  t.setTextColour,t.getTextColour=t.setTextColor,t.getTextColor
  t.setBackgroundColour,t.getBackgroundColour=t.setBackgroundColor,t.getBackgroundColor
  t.setPaletteColour,t.getPaletteColour=t.setPaletteColor,t.getPaletteColor
  function s.resize(w,h)
    local old=s.rows; s.width,s.height,s.rows=w,h,{}
    for y=1,h do
      local row=blank()
      if old[y] then for i=1,3 do row[i]=(old[y][i]..row[i]):sub(1,w) end end
      s.rows[y]=row
    end
  end
  function s.frame()
    local rows,colors={},{}
    for y,r in ipairs(s.rows) do rows[y]={r[1],r[2],r[3]} end
    for i,p in ipairs(s.palette) do colors[i]={p[1],p[2],p[3]} end
    return {width=s.width,height=s.height,rows=rows,palette=colors,x=s.x,y=s.y,blink=s.blink}
  end
  s.term=t; t.clear(); return s
end
function M.text(t,x,y,value,fg,bg)
  t.setCursorPos(x,y); t.setTextColor(fg or 1); t.setBackgroundColor(bg or 32768); t.write(value)
end
return M
