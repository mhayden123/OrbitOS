local M={palette={0xf5f7fb,0xe5a34b,0xc58bc8,0xa4bddb,0xeac87a,0x79b88a,0xe5b4c4,0x4b586c,
  0xdce3ed,0xe4edfc,0x9c8dcb,0x3978d4,0x9b7c69,0x418a68,0xcc5f63,0x1d293d}}
function M.preserve(t)
  if not t.isColor() or not t.setPaletteColor then return function() end end
  local previous={}
  for i in ipairs(M.palette) do
    if t.getPaletteColor then previous[i]={t.getPaletteColor(2^(i-1))} end
  end
  return function() for i,value in ipairs(previous) do t.setPaletteColor(2^(i-1),table.unpack(value)) end end
end
function M.apply(t)
  local restore=M.preserve(t)
  if t.isColor() and t.setPaletteColor then for i,value in ipairs(M.palette) do t.setPaletteColor(2^(i-1),value) end end
  return restore
end
function M.fit(text,width)
  text=tostring(text or ""):gsub("[%z\1-\31\127-\255]"," ")
  if #text<=width then return text end
  return width>3 and text:sub(1,width-3).."..." or text:sub(1,math.max(0,width))
end
function M.title(text) return (text:lower():gsub("%f[%a]%a",string.upper)) end
return M
