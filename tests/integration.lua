-- Small CraftOS event model: each parallel coroutine receives its own event copy.
-- Loads the release files without access to source modules.
local sim = require("simulator")
local terminal = require("terminal")
local M = {}

function M.run(mouse, orbit)
  local world = { now = 0, machines = {}, queue = {}, timers = {}, timerId = 0, packets = {} }
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k,v in pairs(value) do result[k] = copy(v) end; return result
  end
  function world.push(id, ...)
    world.queue[#world.queue + 1] = { id = id, args = {...} }
  end
  local function machine(id, role, turtleSim)
    local m = { id = id, logs = {}, files = {}, env = {} }
    world.machines[id] = m
    local env = setmetatable(m.env, { __index = _G })
    env._G = env
    env.require = function(name) error("Bundle required external module: " .. name) end
    env.os = {
      getComputerID = function() return id end, getComputerLabel = function() return "Test " .. id end,
      setComputerLabel = function() end, clock = function() return world.now end,
      epoch = function() return 1700000000000 end,
      pullEvent = function(filter)
        local event = {coroutine.yield(filter)}
        if event[1] == "terminate" then error("Terminated", 0) end
        return table.unpack(event)
      end,
      startTimer = function(seconds)
        world.timerId = world.timerId + 1
        world.timers[world.timerId] = { id = id, at = world.now + seconds }
        return world.timerId
      end,
      cancelTimer = function(timer) world.timers[timer] = nil end,
    }
    env.os.pullEventRaw=function(filter) return coroutine.yield(filter) end
    env.sleep = function(seconds)
      local timer = env.os.startTimer(seconds)
      while true do local _, value = env.os.pullEvent("timer"); if value == timer then return end end
    end
    env.print = function(...) local a={...}; for i,v in ipairs(a) do a[i]=tostring(v) end; m.logs[#m.logs+1]=table.concat(a," ") end
    env.write = function(text) m.logs[#m.logs+1]=text end
    env.read = function() local _, line = env.os.pullEvent("line"); return line end
    m.screen=terminal.new(role=="worker" and 39 or 26,role=="worker" and 13 or 20,role=="worker" or mouse)
    if orbit and role=="controller" then
      local current=m.screen.api
      env.term=setmetatable({current=function() return current end,redirect=function(t) local old=current; current=t; return old end},
        {__index=function(_,key) return function(...) return current[key](...) end end})
    else env.term=m.screen.api end
    env.keys=orbit and require("orbit_tests").keys or terminal.keys
    env.colors={black=32768,white=1}
    env.peripheral = { getNames=function() return {role=="worker" and "right" or "top"} end,
      hasType=function(_,kind) return kind=="modem" end, call=function() return true end }
    env.fs = {
      exists = function(path) return m.files[path] ~= nil end,
      delete = function(path) m.files[path]=nil end,
      open = function(path, mode)
        if mode=="r" and m.files[path]==nil then return nil end
        return { readAll=function() return copy(m.files[path]) end,
          write=function(value) m.files[path]=copy(value) end, close=function() end }
      end,
    }
    env.textutils = { serialize=copy, unserialize=copy }
    m.files["/.fleet-"..role] = { group="test", owner=42 }
    local function send(destination, message, protocol)
      world.packets[#world.packets+1] = { sender=id, destination=destination, message=copy(message) }
      if world.machines[destination] then world.push(destination,"rednet_message",id,copy(message),protocol) end
      return true
    end
    env.rednet = {
      open=function() end, send=send,
      broadcast=function(message, protocol)
        for other in pairs(world.machines) do if other~=id then send(other,message,protocol) end end
      end,
      receive=function(protocol)
        while true do
          local _, sender, message, received = env.os.pullEvent("rednet_message")
          if not protocol or received==protocol then return sender,message,received end
        end
      end,
    }
    env.gps = { locate=function() return nil end }
    if turtleSim then
      env.turtle = {}
      for name, fn in pairs(turtleSim.api) do
        if name=="forward" or name=="up" or name=="down" or name=="transferTo" or name:match("^turn") or name:match("^dig") then
          env.turtle[name]=function(...) local result={fn(...)}; env.sleep(0.05); return table.unpack(result) end
        else env.turtle[name]=fn end
      end
    end
    env.parallel = { waitForAny=function(...)
      local children={}
      for _, fn in ipairs({...}) do children[#children+1]={co=coroutine.create(fn)} end
      local event={}
      while true do
        for _, child in ipairs(children) do
          if not child.filter or child.filter==event[1] or event[1]=="terminate" then
            local ok, filter=coroutine.resume(child.co,table.unpack(event))
            assert(ok,filter)
            if coroutine.status(child.co)=="dead" then return end
            child.filter=filter
          end
        end
        event={coroutine.yield()}
      end
    end }
    local filename=orbit and role=="controller" and "orbit.lua" or "fleet-"..role..".lua"
    m.co=coroutine.create(assert(loadfile(PROJECT_ROOT.."/dist/"..filename,"t",env)))
    return m
  end
  function world.step()
    local event = table.remove(world.queue,1)
    if not event then
      local selected, earliest
      for id,timer in pairs(world.timers) do if not earliest or timer.at<earliest then selected,earliest=id,timer.at end end
      assert(selected,"No runnable event")
      local timer=world.timers[selected]; world.timers[selected]=nil; world.now=timer.at
      event={id=timer.id,args={"timer",selected}}
    end
    local m=world.machines[event.id]
    if coroutine.status(m.co)~="dead" then
      local ok, why=coroutine.resume(m.co,table.unpack(event.args)); assert(ok,why)
    end
  end
  function world.untilTrue(condition)
    for _=1,3000 do if condition() then return end; world.step() end
    error("Integration event limit reached")
  end
  local origin={x=0,y=0,z=0,heading=0,frame="local"}
  local turtleSim=sim.new(origin)
  for x=0,2 do for z=-2,0 do for y=-2,-1 do turtleSim.blocks[sim.key({x=x,y=y,z=z})]="minecraft:dirt" end end end
  local controller=machine(42,"controller")
  local worker=machine(7,"worker",turtleSim)
  world.push(42); world.push(7)
  if orbit then world.push(42,"key",terminal.keys.enter) end
  world.untilTrue(function() return controller.screen.text():find("#7 Test 7",1,true) end)
  if mouse then
    local function click(x,y) world.push(42,"mouse_click",1,x,y) end
    click(3,4); click(3,14); click(3,10); click(3,5); click(16,18)
    click(4,5); world.push(42,"paste","3")
    click(4,9); world.push(42,"paste","3")
    click(4,13); world.push(42,"paste","2")
    click(16,18); click(16,18); click(3,14); click(16,18)
  else
    local function key(name) world.push(42,"key",terminal.keys[name]) end
    -- Discovery preserves focus on Setup; Tab past Quit to the newly arrived row.
    key("tab"); key("tab")
    key("enter"); key("enter"); key("tab"); key("enter"); key("enter"); key("tab"); key("enter")
    world.push(42,"paste","3"); key("enter")
    world.push(42,"paste","3"); key("enter")
    world.push(42,"paste","2"); key("enter"); key("enter")
    key("tab"); key("enter"); key("enter"); key("tab"); key("tab"); key("enter")
  end
  if orbit then
    local k=require("orbit_tests").keys
    world.push(42,"key",k.f1); world.push(42,"key",k.down); world.push(42,"key",k.down); world.push(42,"key",k.enter)
    world.untilTrue(function() return controller.screen.text():find("DISPLAYS",1,true) end)
  end
  local function completed()
    for _,packet in ipairs(world.packets) do
      if packet.sender==7 and packet.message.kind=="status" and packet.message.state=="completed" then return true end
    end
  end
  world.untilTrue(completed)
  assert(#turtleSim.digs==18,"Bundled program failed to clear all 18 blocks")
  assert(sim.key(turtleSim.pose)==sim.key(origin) and turtleSim.pose.heading==0,"Bundled worker did not return")
  assert(worker.files["/.fleet-interrupted"]==nil,"Completed job left interrupted marker")
  if orbit then world.push(42,"key",require("orbit_tests").keys.f2) end
  world.untilTrue(function() return controller.screen.text():find("COMPLETED",1,true) end)
  -- Replay a captured start packet after completion; no new physical work may start.
  local moves=#turtleSim.moves
  for _,packet in ipairs(world.packets) do
    if packet.sender==42 and packet.message.action=="start" then
      world.push(7,"rednet_message",42,packet.message,"turtle-fleet/1"); break
    end
  end
  for _=1,30 do world.step() end
  assert(#turtleSim.moves==moves,"Duplicate start ran a second excavation")
end

return M
