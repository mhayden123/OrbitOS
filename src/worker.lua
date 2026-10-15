local net = require("fleet.net")
local engine = require("fleet.engine")
local ui = require("fleet.ui")
local args = { ... }
assert(turtle, "Run the worker on a turtle.")
net.open()
local configPath, markPath = "/.fleet-worker", "/.fleet-interrupted"
local config = ui.load(configPath)
if type(config) ~= "table" or type(config.group) ~= "string" or type(config.owner) ~= "number" or args[1] == "setup" then
  ui.header("Turtle Fleet setup")
  print("Run the controller first to see its ID.")
  config = { group = ui.group(), owner = ui.number("Controller computer ID", nil, 0, 2147483647) }
  ui.save(configPath, config)
end
if not os.getComputerLabel() then os.setComputerLabel("Fleet turtle " .. os.getComputerID()) end

local function mining()
  for _, get in ipairs({ turtle.getEquippedLeft, turtle.getEquippedRight }) do
    local item = get()
    if item and item.name == "minecraft:diamond_pickaxe" then return true end
  end
  return false
end

local worker
local function announce(status, id)
  status = status or worker.snapshot()
  if id then net.send(id, config.group, "status", status)
  else net.broadcast(config.group, "status", status) end
end

-- A new session invalidates every command sent before a restart.
local session = tostring(os.getComputerID()) .. ":" .. tostring(os.epoch("utc"))
worker = engine.new({
  turtle = turtle, mining = mining, owner = config.owner, label = os.getComputerLabel(),
  now = os.clock, sleep = sleep, session = session, locate = function() return gps.locate(3) end,
  publish = function(status) announce(status) end,
  mark = function(value) ui.save(markPath, value) end,
  clearMark = function() if fs.exists(markPath) then fs.delete(markPath) end end,
})
if fs.exists(markPath) then
  worker.state, worker.reason = "restarted", "Interrupted job discarded. Verify position and submit a new job."
end

local function receiver()
  while true do
    local sender, message = rednet.receive(net.PROTOCOL)
    if net.valid(message, config.group) then
      if message.kind == "discover" then announce(worker.snapshot(), sender)
      else
        local reply = worker.handle(sender, message)
        if reply then net.send(sender, config.group, "ack", reply) end
      end
    end
  end
end

local function runner()
  while true do
    if not worker.runPending() then sleep(0.1) end
  end
end

local function display()
  while true do
    local s = worker.snapshot()
    announce(s)
    ui.header(os.getComputerLabel())
    print("ID " .. os.getComputerID() .. " | " .. config.group)
    print("Controller: " .. config.owner)
    print("State: " .. s.state)
    print("Cells: " .. s.done .. "/" .. s.total)
    print("Blocks dug: " .. s.dug)
    print("Fuel: " .. s.fuel .. " (slot 16)")
    if s.pose then print(("At: %d %d %d"):format(s.pose.x, s.pose.y, s.pose.z)) end
    if not s.mining then print("Equip a diamond pickaxe.") end
    print(s.reason)
    print("Ctrl+T: stop worker")
    sleep(2)
  end
end

-- Termination intentionally propagates. A restart never resumes physical work.
parallel.waitForAny(receiver, runner, display)
