-- One protocol works over every open wired, wireless, or Ender modem.
local M={PROTOCOL="orbit-display/1",MAX_CELLS=12000}
local function integer(n,lo,hi) return type(n)=="number" and n==math.floor(n) and n>=lo and n<=hi end
local function short(s,n) return type(s)=="string" and #s<=n end
function M.open(peripheral,rednet)
  local count=0
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,"modem") then local ok=pcall(rednet.open,name); if ok then count=count+1 end end
  end
  return count
end
function M.monitors(peripheral)
  local result={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,"monitor") then
      local ok,monitor=pcall(peripheral.wrap,name)
      if ok and monitor then
        local success,w,h=pcall(monitor.getSize)
        if success then result[#result+1]={name=name,width=w,height=h,color=monitor.isColor(),term=monitor} end
      end
    end
  end
  table.sort(result,function(a,b) return a.name<b.name end); return result
end
function M.validFrame(f)
  if type(f)~="table" or not integer(f.width,1,255) or not integer(f.height,1,255)
    or f.width*f.height>M.MAX_CELLS or type(f.rows)~="table" or #f.rows~=f.height then return false end
  for _,r in ipairs(f.rows) do
    if type(r)~="table" then return false end
    for i=1,3 do if type(r[i])~="string" or #r[i]~=f.width then return false end end
    if (r[2]..r[3]):find("[^0-9a-f]") then return false end
  end
  if f.palette~=nil then
    if type(f.palette)~="table" or #f.palette~=16 then return false end
    for _,p in ipairs(f.palette) do
      if type(p)~="table" then return false end
      for i=1,3 do if type(p[i])~="number" or p[i]~=p[i] or p[i]<0 or p[i]>1 then return false end end
    end
  end
  return true
end
local function fit(monitor,width,height)
  local w,h=monitor.getSize()
  if w>=width and h>=height then return w,h end
  if monitor.getTextScale and monitor.setTextScale then
    local original=monitor.getTextScale()
    local ok,fw,fh=pcall(function()
      for scale=original-0.5,0.5,-0.5 do
        monitor.setTextScale(scale); w,h=monitor.getSize()
        if w>=width and h>=height then return w,h end
      end
    end)
    if ok and fw then return fw,fh end
    pcall(monitor.setTextScale,original)
  end
  return nil,"Enlarge this monitor to fit "..width.."x"..height.." cells."
end
function M.paint(monitor,frame)
  if not M.validFrame(frame) then return nil,"Invalid display frame" end
  local w,h=fit(monitor,frame.width,frame.height)
  if not w then return nil,h end
  local x,y=math.floor((w-frame.width)/2)+1,math.floor((h-frame.height)/2)+1
  monitor.setCursorBlink(false); monitor.setBackgroundColor(32768); monitor.clear()
  if frame.palette and monitor.setPaletteColor then for i,p in ipairs(frame.palette) do monitor.setPaletteColor(2^(i-1),p[1],p[2],p[3]) end end
  for row,r in ipairs(frame.rows) do
    monitor.setCursorPos(x,y+row-1)
    local fg,bg=r[2],r[3]
    if not monitor.isColor() then fg,bg=fg:gsub("[^078f]","0"),bg:gsub("[^078f]","7") end
    monitor.blit(r[1],fg,bg)
  end
  return {x=x,y=y,width=frame.width,height=frame.height}
end
local function packet(group,kind,body) body=body or {}; body.version=1; body.group=group; body.kind=kind; return body end
local function valid(m,group) return type(m)=="table" and m.version==1 and m.group==group and short(m.kind,32) end
function M.host(o)
  local self={peers={},streams={},next=0,nextDiscover=0}
  local function send(id,kind,body) o.send(id,packet(o.group(),kind,body),M.PROTOCOL) end
  function self.targets()
    local out={}
    for _,m in ipairs(o.monitors()) do out[#out+1]={key="local:"..m.name,name=m.name,width=m.width,height=m.height,monitor=m.name} end
    for id,p in pairs(self.peers) do
      if o.now()-p.seen<8 then for _,m in ipairs(p.monitors) do
        out[#out+1]={key=id..":"..m.name,name="#"..id.." "..p.label.." / "..m.name,width=m.width,height=m.height,id=id,monitor=m.name}
      end end
    end
    table.sort(out,function(a,b) return a.key<b.key end); return out
  end
  function self.stop(key)
    local s=self.streams[key]; if not s then return end
    if s.target.id then send(s.target.id,"stop",{stream=s.token,monitor=s.target.monitor}) end
    if not s.target.id then for _,m in ipairs(o.monitors()) do if m.name==s.target.monitor then
      pcall(function() m.term.setBackgroundColor(32768); m.term.setTextColor(1); m.term.clear(); m.term.setCursorPos(1,1); m.term.write("Cast stopped") end)
    end end end
    self.streams[key]=nil
  end
  function self.stopAll(source)
    local keys={}; for k,s in pairs(self.streams) do if not source or s.source==source then keys[#keys+1]=k end end
    for _,k in ipairs(keys) do self.stop(k) end
  end
  function self.start(target,source,touch)
    local frame=o.frame(source); if not frame then return nil,"Open an app first." end
    if not M.validFrame(frame) then return nil,"App is too large to cast (12,000 cell limit)." end
    if not target.id then
      local found=false
      for _,m in ipairs(o.monitors()) do if m.name==target.monitor then
        found=true
        local w,h=fit(m.term,frame.width,frame.height); if not w then return nil,h end
        target.width,target.height=w,h
      end end
      if not found then return nil,"Monitor disconnected. Check its cable." end
    end
    self.stop(target.key); self.next=self.next+1
    self.streams[target.key]={target=target,source=source,touch=touch,token=o.boot..":"..self.next,seq=0,
      status=target.id and "Connecting" or "Live",sent=0,seen=o.now(),ready=not target.id}
    return true
  end
  function self.receive(id,m)
    if not valid(m,o.group()) then return end
    if m.kind=="advert" and short(m.label,48) and type(m.monitors)=="table" and #m.monitors<=16 then
      local monitors={}
      for _,d in ipairs(m.monitors) do
        if type(d)~="table" or not short(d.name,128) or not integer(d.width,1,255) or not integer(d.height,1,255) then return end
        monitors[#monitors+1]={name=d.name,width=d.width,height=d.height}
      end
      local count=0; for _ in pairs(self.peers) do count=count+1 end
      if self.peers[id] or count<64 then self.peers[id]={label=m.label,monitors=monitors,seen=o.now()} end
    else
      for _,s in pairs(self.streams) do if id==s.target.id and m.stream==s.token then
        if m.kind=="ack" then s.ready=m.ok==true; s.status=s.ready and "Live" or tostring(m.error):sub(1,120); s.seen=o.now()
        elseif m.kind=="touch" and s.ready and s.touch and m.seq==s.seq and integer(m.x,1,s.width or 0) and integer(m.y,1,s.height or 0) then
          o.input(s.source,m.x,m.y)
        end
      end end
    end
  end
  function self.touch(name,x,y)
    for _,s in pairs(self.streams) do
      local p=s.placement
      if not s.target.id and s.target.monitor==name and s.touch and p and x>=p.x and x<p.x+p.width and y>=p.y and y<p.y+p.height then o.input(s.source,x-p.x+1,y-p.y+1) end
    end
  end
  function self.tick()
    if o.now()>=self.nextDiscover then
      o.broadcast(packet(o.group(),"discover"),M.PROTOCOL); self.nextDiscover=o.now()+3
      for id,p in pairs(self.peers) do if o.now()-p.seen>15 then self.peers[id]=nil end end
    end
    local remove={}
    for key,s in pairs(self.streams) do
      local f=o.frame(s.source)
      if not f then remove[#remove+1]=key
      elseif not M.validFrame(f) then s.status="App exceeds cast size limit"
      else
        if s.target.id and o.now()-s.sent>=2 then
          send(s.target.id,"start",{stream=s.token,monitor=s.target.monitor,touch=s.touch}); s.sent=o.now()
          if o.now()-s.seen>8 then s.status="Receiver offline"; s.ready=false end
        end
        local signature={tostring(f.width),tostring(f.height)}
        for _,r in ipairs(f.rows) do signature[#signature+1]=r[1]..r[2]..r[3] end
        if f.palette then for _,p in ipairs(f.palette) do signature[#signature+1]=table.concat(p,",") end end
        signature=table.concat(signature,"|")
        if s.ready and o.now()-(s.frameAt or -10)>=0.25 and (s.signature~=signature or o.now()-(s.frameAt or -10)>=2) then
          s.seq=s.seq+1; s.width,s.height=f.width,f.height
          if s.target.id then send(s.target.id,"frame",{stream=s.token,monitor=s.target.monitor,seq=s.seq,frame=f})
          else
            local found=false
            for _,m in ipairs(o.monitors()) do if m.name==s.target.monitor then
              found=true; local ok,place,why=pcall(M.paint,m.term,f)
              s.placement=ok and place or nil; s.status=s.placement and "Live" or tostring(why or place)
            end end
            if not found then s.placement=nil; s.status="Monitor detached" end
          end
          s.signature,s.frameAt=signature,o.now()
        end
      end
    end
    for _,key in ipairs(remove) do self.stop(key) end
  end
  return self
end
function M.receiver(o)
  local self={streams={}}
  local function send(kind,body) o.send(o.owner(),packet(o.group(),kind,body),M.PROTOCOL) end
  local function monitor(name) for _,m in ipairs(o.monitors()) do if m.name==name then return m.term end end end
  local function stop(name)
    if self.streams[name] then
      local t=monitor(name)
      if t then pcall(function() t.setBackgroundColor(32768); t.setTextColor(1); t.clear(); t.setCursorPos(1,1); t.write("Cast disconnected") end) end
      self.streams[name]=nil
    end
  end
  function self.stopAll() local names={}; for name in pairs(self.streams) do names[#names+1]=name end; for _,name in ipairs(names) do stop(name) end end
  function self.receive(id,m)
    if id~=o.owner() or not valid(m,o.group()) then return end
    if m.kind=="discover" then
      local list={}; for _,d in ipairs(o.monitors()) do if #list<16 then list[#list+1]={name=d.name,width=d.width,height=d.height} end end
      send("advert",{label=o.label,monitors=list}); return
    end
    if not short(m.stream,100) or not short(m.monitor,128) then return end
    local t=monitor(m.monitor); if not t then return end
    local s=self.streams[m.monitor]
    if m.kind=="start" then
      if not s or s.token~=m.stream then s={token=m.stream,seq=0}; self.streams[m.monitor]=s end
      s.seen=o.now(); s.touch=m.touch==true and o.touch()
      send("ack",{stream=s.token,ok=true})
    elseif s and s.token==m.stream then
      if m.kind=="stop" then stop(m.monitor)
      elseif m.kind=="frame" and integer(m.seq,1,2147483647) and m.seq>s.seq and M.validFrame(m.frame) then
        local ok,place,why=pcall(M.paint,t,m.frame)
        s.placement=ok and place or nil
        if s.placement then s.seq,s.seen=m.seq,o.now()
        else send("ack",{stream=s.token,ok=false,error=tostring(why or place)}) end
      end
    end
  end
  function self.tick() local old={}; for name,s in pairs(self.streams) do if o.now()-s.seen>8 or not monitor(name) then old[#old+1]=name end end; for _,n in ipairs(old) do stop(n) end end
  function self.event(event,name,x,y)
    local s=self.streams[name]
    if event=="monitor_touch" and s and s.touch and s.placement then
      local p=s.placement
      if x>=p.x and x<p.x+p.width and y>=p.y and y<p.y+p.height then send("touch",{stream=s.token,seq=s.seq,x=x-p.x+1,y=y-p.y+1}) end
    elseif event=="monitor_resize" and s then s.placement=nil end
  end
  return self
end
return M
