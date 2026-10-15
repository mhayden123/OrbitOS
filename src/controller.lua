local net = require("fleet.net")
local ui = require("fleet.ui")
local clientModule = require("fleet.client")
local dashboard = require("fleet.dashboard")
local args = { ... }
net.open()
local path = "/.fleet-controller"
local config = ui.load(path)
local group = type(config)=="table" and type(config.group)=="string" and config.group or nil
local client = clientModule.new({ group=group, owner=os.getComputerID(), now=os.clock,
  boot=tostring(os.getComputerID())..":"..tostring(os.epoch("utc")) })
local app = dashboard.new(term,keys,{ client=client, setup=not group or args[1]=="setup",
  saveGroup=function(value) ui.save(path,{group=value}) end })

-- One event loop keeps editing, discovery, heartbeats and retries responsive together.
local timer=os.startTimer(0.25)
local ok,why=pcall(function()
  client.tick()
  app.render()
  while app.running do
    local event={os.pullEvent()}
    if event[1]=="rednet_message" and event[4]==net.PROTOCOL then client.receive(event[2],event[3]) end
    if event[1]=="timer" and event[2]==timer then client.tick(); timer=os.startTimer(0.25) end
    app.event(table.unpack(event))
    if app.running then app.render() end
  end
end)
os.cancelTimer(timer)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
if not ok then error(why,0) end
print("Controller closed. Active turtles pause after their connection lease expires.")
