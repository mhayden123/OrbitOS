local panel=require("orbit.panel")
local cast=require("orbit.cast")
local M={}
function M.run(o)
  local config=o.load("/.orbit-receiver") or {group="orbit",owner="",touch=false}
  if type(config)~="table" then config={group="orbit",owner="",touch=false} end
  config.group=type(config.group)=="string" and config.group or "orbit"
  config.owner=tostring(config.owner or "")
  local p=panel.new(o.display,o.keys)
  local owner=tonumber(config.owner)
  local active=config.active==true and owner~=nil and owner>=0 and owner%1==0 and config.group:match("^[%w_-]+$")~=nil
  local message=active and "Waiting for a cast..." or "Configure the sender, then start."
  local receiver=cast.receiver({owner=function() return tonumber(config.owner) end,group=function() return config.group end,
    touch=function() return config.touch end,monitors=o.monitors,send=o.rednet.send,now=os.clock,label=(os.getComputerLabel() or "Display receiver"):sub(1,48)})
  local timer=os.startTimer(0.25)
  local function draw()
    local items={}
    if active then
      items={{text="Sender #"..config.owner.." / "..config.group},{text=message},
        {id="stop",label="Stop receiving"},{id="scale",label="Monitors: text scale 0.5"}}
      for _,m in ipairs(o.monitors()) do items[#items+1]={text=m.name.." "..m.width.."x"..m.height..(receiver.streams[m.name] and " Live" or " Ready")} end
    else
      items={{id="owner",label="Sender computer ID",field=true,numeric=true,value=config.owner,change=function(v) config.owner=v end},
        {id="group",label="Display network group",field=true,value=config.group,change=function(v) config.group=v end},
        {id="touch",label=config.touch and "[x] Allow monitor taps" or "[ ] Allow monitor taps"},
        {id="start",label="Start receiver"},{text=message}}
    end
    p.draw("ORBIT DISPLAY RECEIVER","Computer #"..os.getComputerID(),items,"Exit")
  end
  local ok,why=pcall(function()
    while true do
      draw(); local e={os.pullEventRaw()}
      if e[1]=="terminate" then break end
      if e[1]=="timer" and e[2]==timer then receiver.tick(); timer=os.startTimer(0.25) end
      if e[1]=="peripheral" then cast.open(o.peripheral,o.rednet) end
      if active then
        if e[1]=="rednet_message" and e[4]==cast.PROTOCOL then receiver.receive(e[2],e[3]) end
        receiver.event(table.unpack(e))
      end
      local a=p.event(table.unpack(e))
      if a=="back" then break
      elseif a=="touch" then config.touch=not config.touch
      elseif a=="stop" then receiver.stopAll(); active=false; config.active=false; o.save("/.orbit-receiver",config); p.reset()
      elseif a=="scale" then
        for _,m in ipairs(o.monitors()) do pcall(m.term.setTextScale,0.5) end
      elseif a=="start" then
        local owner=tonumber(config.owner)
        if owner and owner>=0 and owner%1==0 and owner<=2147483647 and config.group:match("^[%w_-]+$") and #config.group<=32 then
          config.active=true; o.save("/.orbit-receiver",config); active=true; message="Waiting for a cast..."; p.reset()
        else message="Enter a valid ID and group." end
      end
    end
  end)
  receiver.stopAll(); os.cancelTimer(timer); if not ok then error(why,0) end
end
return M
