local desktop=require("orbit.desktop")
local apps=require("orbit.apps")
local cast=require("orbit.cast")
local receiver=require("orbit.receiver")
local ui=require("fleet.ui")
local release=require("orbit.release")
local fleetUpdates=require("fleet.update_client")
local fleetNet=require("fleet.net")
local transfer=require("fleet.updates")
local VERSION=release.version
local args={...}
local native=term.current()
local width,height=native.getSize()
assert(width>=26 and height>=13,"Orbit needs at least 26 columns and 13 rows.")
local config=ui.load("/.orbit-config") or {}
if type(config)~="table" then config={} end
config.group=type(config.group)=="string" and config.group or "orbit"
local function saveConfig() ui.save("/.orbit-config",config) end
local modemCount=cast.open(peripheral,rednet)
local function monitors() return cast.monitors(peripheral) end
local ok,why=pcall(function()
  if args[1]=="receive" then
    receiver.run({display=native,keys=keys,load=ui.load,save=ui.save,monitors=monitors,rednet=rednet,peripheral=peripheral})
    return
  end
  local manager
  local boot=tostring(os.getComputerID())..":"..tostring(os.epoch("utc"))
  local fleetConfig=ui.load("/.fleet-controller")
  local updating=fleetUpdates.new({group=type(fleetConfig)=="table" and fleetConfig.group or nil,
    owner=os.getComputerID(),now=os.clock,boot=boot,yield=function() sleep(0) end,
    sendUpdate=function(id,message) rednet.send(id,message,transfer.PROTOCOL) end})
  local casting=cast.host({group=function() return config.group end,now=os.clock,boot=boot,monitors=monitors,
    send=rednet.send,broadcast=rednet.broadcast,
    frame=function(id) local w=manager.find(id); return w and w.surface.frame() end,
    input=function(id,x,y) manager.appInput(id,"mouse_click",1,x,y); manager.appInput(id,"mouse_up",1,x,y) end})
  local options={keys=keys,config=config,saveConfig=saveConfig,version=VERSION,id=os.getComputerID(),boot=boot,
    now=os.clock,load=ui.load,save=ui.save,fs=fs,http=http,decode=textutils.unserializeJSON,
    term=term,shell=shell,resolutionApi=orbit_display,cast=casting,fleetUpdates=updating,modemCount=function() return modemCount end,
    windows=function() return manager.windows end,title=function(id) local w=manager.find(id); return w and w.title end,
    quit=function() manager.running=false end}
  local definitions=apps.definitions(options)
  manager=desktop.new(native,keys,{apps=definitions,subtitle="#"..os.getComputerID(),closed=casting.stopAll,
    cast=function(id)
      options.castSource=id
      local w=manager.open(definitions[3]); if w then w.app.source=id end
    end})
  local timer=os.startTimer(0.25)
  local success,problem=pcall(function()
    while manager.running do
      manager.render(); casting.tick()
      local e={os.pullEventRaw()}
      if e[1]=="terminate" then manager.stop(); break end
      if e[1]=="timer" and e[2]==timer then
        if modemCount>0 then updating.tick() end
        manager.tick(); timer=os.startTimer(0.25)
      end
      if e[1]=="peripheral" or e[1]=="peripheral_detach" then modemCount=cast.open(peripheral,rednet) end
      if e[1]=="rednet_message" and e[4]==cast.PROTOCOL then casting.receive(e[2],e[3]) end
      if e[1]=="rednet_message" and (e[4]==fleetNet.PROTOCOL or e[4]==transfer.PROTOCOL) then updating.receive(e[2],e[3],e[4]) end
      if e[1]=="monitor_touch" then casting.touch(e[2],e[3],e[4]) end
      manager.event(table.unpack(e))
    end
  end)
  updating.cancel(); casting.stopAll(); manager.stop(); os.cancelTimer(timer)
  if not success then error(problem,0) end
end)
term.redirect(native); native.setCursorBlink(false); native.setBackgroundColor(colors.black); native.setTextColor(colors.white); native.clear(); native.setCursorPos(1,1)
if not ok then error(why,0) end
print("Orbit closed. Run orbit to return.")
