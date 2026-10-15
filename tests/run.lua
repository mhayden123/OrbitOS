local planner = require("fleet.planner")
local motion = require("fleet.motion")
local engine = require("fleet.engine")
local net = require("fleet.net")
local sim = require("simulator")
local count = 0
local function test(name, fn)
  local ok, why = pcall(fn)
  assert(ok, name .. ": " .. tostring(why))
  count = count + 1
  print("PASS " .. name)
end
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function pose(heading, frame) return { x = -8, y = 80, z = 10, heading = heading or 0, frame = frame or "world" } end
local function spec(w, l, d) return { program = "quarry", width = w or 2, length = l or 3, depth = d or 2 } end
local function harness(p)
  local s = sim.new(p or pose())
  local h = { sim = s, now = 0, messages = {}, marks = 0 }
  h.worker = engine.new({
    turtle = s.api, owner = 42, label = "Test", session = "boot-1",
    mining = function() return not h.noPickaxe end,
    now = function() return h.now end,
    sleep = function(seconds)
      h.now = h.now + seconds
      assert(h.now < 100, "Unexpected wait loop")
      assert(h.onSleep, "Unexpected pause: " .. h.worker.reason)
      h.onSleep()
    end,
    locate = function() if h.gps then return h.gps.x, h.gps.y, h.gps.z end end,
    publish = function(status) h.messages[#h.messages + 1] = status end,
    mark = function() h.marks = h.marks + 1 end,
    clearMark = function() h.marks = h.marks - 1 end,
    maintenance = function() return h.updating end,
  })
  local sequence = 0
  function h.command(action, body, sender)
    sequence = sequence + 1
    body = body or {}
    body.kind, body.action, body.session = "command", action, body.session or "boot-1"
    body.request = body.request or "request-" .. sequence
    body.revision, body.jobId = body.revision or h.worker.revision, body.jobId or h.worker.jobId
    return h.worker.handle(sender or 42, body)
  end
  function h.start(job, start, gps)
    return h.command("start", { spec = job or spec(), pose = start or p or pose(), verifyGPS = gps == true })
  end
  return h
end

require("inventory_tests").run(test, equal, harness)
test("worker refuses a new job during an update without moving",function()
  local h=harness(); h.updating=true; local result=h.start()
  assert(not result.ok and result.error:find("update",1,true)); equal(#h.sim.moves,0); equal(h.marks,0)
end)

test("route covers every cell once with adjacent steps: 480 dimension/facing combinations", function()
  for heading = 0, 3 do
    for w = 1, 6 do for l = 1, 5 do for d = 1, 4 do
      local p = pose(heading)
      local plan = assert(planner.create(spec(w, l, d), p))
      local visited, previous = {}, p
      for i = 1, plan.total do
        local cell = planner.target(plan, i)
        assert(planner.contains(plan, cell))
        equal(math.abs(cell.x - previous.x) + math.abs(cell.y - previous.y) + math.abs(cell.z - previous.z), 1)
        assert(not visited[sim.key(cell)], "Cell repeated")
        visited[sim.key(cell)], previous = true, cell
      end
      for x = plan.minX, plan.maxX do for z = plan.minZ, plan.maxZ do for y = plan.floorY + 1, plan.topY do
        assert(visited[sim.key({x=x,y=y,z=z})], "Missed cell")
      end end end
    end end end
  end
end)

test("all four corners and reversed coordinate order use inclusive bounds", function()
  for _, reverse in ipairs({ false, true }) do
    for _, x in ipairs({ -10, -6 }) do for _, z in ipairs({ -20, -17 }) do
      local p = { x = x, z = z, y = 81, heading = 3, frame = "world" }
      local job = { program = "flatten", x1 = reverse and -6 or -10, x2 = reverse and -10 or -6,
        z1 = reverse and -17 or -20, z2 = reverse and -20 or -17, floorY = 64 }
      local plan = assert(planner.create(job, p))
      equal(plan.width, 5); equal(plan.length, 4); equal(plan.depth, 16)
      equal(planner.target(plan, 1).y, 80)
      equal(planner.target(plan, plan.total).y, 65)
      local h = harness(p)
      h.sim.fill(plan, true)
      assert(h.start(job, p).ok)
      h.worker.runPending()
      equal(h.worker.state, "completed")
      equal(#h.sim.moves, plan.fuel)
      equal(sim.key(h.sim.pose), sim.key(p)); equal(h.sim.pose.heading, 3)
    end end
  end
end)

test("full simulated jobs preserve floor and outside blocks and return facing: 80 routes", function()
  for heading = 0, 3 do for w = 1, 5 do for depth = 1, 4 do
    local p, job = pose(heading), spec(w, 3, depth)
    local plan = assert(planner.create(job, p))
    local h = harness(p)
    h.sim.fill(plan)
    for x = plan.minX - 1, plan.maxX + 1 do for z = plan.minZ - 1, plan.maxZ + 1 do
      h.sim.blocks[sim.key({x=x,y=plan.floorY,z=z})] = "minecraft:grass_block"
    end end
    h.sim.blocks[sim.key({x=plan.maxX+1,y=plan.topY,z=plan.maxZ+1})] = "minecraft:diamond_block"
    assert(h.start(job).ok)
    h.worker.runPending()
    equal(h.worker.state, "completed"); equal(h.worker.done, plan.total)
    equal(#h.sim.digs, plan.total); equal(#h.sim.moves, plan.fuel)
    equal(sim.key(h.sim.pose), sim.key(p)); equal(h.sim.pose.heading, heading)
    for _, dug in ipairs(h.sim.digs) do assert(planner.contains(plan, dug)) end
    for key, block in pairs(h.sim.blocks) do assert(block ~= "minecraft:stone", "Missed " .. key) end
    equal(h.marks, 0)
  end end end
end)

test("local mode width is right and length is forward for every heading", function()
  for heading = 0, 3 do
    local plan = assert(planner.create(spec(3, 5, 1), pose(heading, "local")))
    local forward, right = planner.directions[heading], planner.directions[(heading + 1) % 4]
    equal(plan.u.x, right.x); equal(plan.u.z, right.z)
    equal(plan.v.x, forward.x); equal(plan.v.z, forward.z)
  end
end)

test("reject malformed, non-finite, excessive, zero, fractional and off-corner jobs", function()
  for _, job in ipairs({ {}, spec(0), spec(-1), spec(1.5), spec(257), spec(1, 257),
    spec(1, 1, 0), spec(1, 1, 385), spec(256,256,384), spec(0/0), spec(math.huge),
    {program="flatten",x1=0,z1=0,x2=10,z2=10,floorY=64},
    {program="flatten",x1=-8,z1=10,x2=-7,z2=11,floorY=79} }) do
    assert(not planner.create(job, pose()))
  end
  assert(not planner.create(spec(), nil))
  assert(not planner.create("job", pose()))
  local p = pose(); p.heading = 4; assert(not planner.create(spec(), p))
  p = pose(); p.y = math.huge; assert(not planner.create(spec(), p))
  p = pose(0, "local")
  assert(not planner.create({program="flatten",x1=-8,z1=10,x2=-7,z2=11,floorY=64}, p))
end)

test("empty air costs movement fuel but does not dig", function()
  local h = harness()
  assert(h.start().ok); h.worker.runPending()
  equal(h.worker.state, "completed"); equal(#h.sim.digs, 0)
end)

test("only the configured controller can issue commands", function()
  local h = harness()
  equal(h.command("start", {spec=spec(),pose=pose(),verifyGPS=false}, 7), nil)
  equal(h.worker.active, false)
  h.now = 5; h.worker.handle(7, {kind="heartbeat"}); equal(h.worker.lastContact, 0)
end)

test("start retry is idempotent and old revision cannot start a second job", function()
  local h = harness()
  local body = { request="same", spec=spec(), pose=pose(), verifyGPS=false, revision=0 }
  assert(h.command("start", body).ok)
  assert(h.command("start", body).ok)
  equal(h.worker.revision, 1)
  assert(not h.start().ok)
  h.worker.runPending()
  local moves = #h.sim.moves
  assert(h.command("start", body).ok)
  equal(h.worker.active, false)
  assert(not h.command("start", {spec=spec(),pose=pose(),verifyGPS=false,revision=0}).ok)
  h.worker.runPending(); equal(#h.sim.moves, moves)
end)

test("old session, missing GPS choice and incompatible turtle are rejected", function()
  local h = harness()
  assert(not h.command("start", {session="old",spec=spec(),pose=pose(),verifyGPS=false}).ok)
  assert(not h.command("start", {spec=spec(),pose=pose()}).ok)
  h.noPickaxe = true; assert(not h.start().ok)
  equal(h.sim.actions, 0)
end)

test("GPS mismatch and missing hosts fail before physical movement", function()
  for _, found in ipairs({false, true}) do
    local h = harness()
    if found then h.gps = pose(); h.gps.x = 100 end
    assert(h.start(nil, nil, true).ok)
    h.worker.runPending(); equal(h.worker.state, "error"); equal(h.sim.actions, 0)
  end
end)

test("matching GPS permits the job", function()
  local h = harness(); h.gps = pose()
  assert(h.start(nil, nil, true).ok); h.worker.runPending(); equal(h.worker.state, "completed")
end)

test("pause before the first action and resume", function()
  local h = harness()
  assert(h.start().ok); assert(h.command("pause").ok)
  local waited = false
  h.onSleep = function()
    waited = true; equal(h.sim.actions, 0); equal(h.worker.state, "paused")
    assert(h.command("resume").ok)
  end
  h.worker.runPending(); assert(waited); equal(h.worker.state, "completed")
end)

test("pause during a move stops before the next action", function()
  local h = harness()
  assert(h.start().ok)
  h.sim.onAction = function(kind)
    if kind == "move" then h.sim.onAction = nil; assert(h.command("pause").ok) end
  end
  local waited = false
  h.onSleep = function()
    waited = true; equal(#h.sim.moves, 1); assert(h.command("resume").ok)
  end
  h.worker.runPending(); assert(waited); equal(h.worker.state, "completed")
end)

test("lost link pauses; a heartbeat alone does not resume", function()
  local h = harness()
  assert(h.start().ok); h.now = 13
  local waits = 0
  h.onSleep = function()
    equal(h.sim.actions, 0); waits = waits + 1
    h.worker.handle(42, {kind="heartbeat"})
    if waits == 2 then assert(h.command("resume").ok) end
  end
  h.worker.runPending(); equal(waits, 2); equal(h.worker.state, "completed")
end)

test("cancel during movement stops in place; no automatic return", function()
  local h = harness(); assert(h.start().ok)
  h.sim.onAction = function(kind) if kind == "move" then assert(h.command("cancel").ok) end end
  h.worker.runPending(); equal(h.worker.state, "cancelled"); equal(#h.sim.moves, 1)
  equal(h.sim.pose.y, 79); equal(h.worker.active, false)
end)

test("cancel a blocked turtle and reject controls aimed at another job", function()
  local h = harness(); h.sim.fuel = 0; assert(h.start().ok)
  assert(not h.command("resume", {jobId="some-other-job"}).ok)
  h.onSleep = function() assert(h.command("cancel").ok) end
  h.worker.runPending(); equal(h.worker.state, "cancelled"); equal(#h.sim.moves, 0)
end)

test("fuel exhaustion pauses before digging; slot 16 refuels on resume", function()
  local h = harness(); h.sim.fuel = 0
  h.sim.fill(assert(planner.create(spec(), pose())))
  assert(h.start().ok)
  h.onSleep = function()
    equal(h.worker.state, "blocked"); equal(#h.sim.digs, 0); equal(#h.sim.moves, 0)
    h.sim.inventory[16] = 1; assert(h.command("resume").ok)
  end
  h.worker.runPending(); equal(h.worker.state, "completed"); equal(h.sim.inventory[16], 0)
end)

test("unlimited fuel needs no refuelling", function()
  local h = harness(); h.sim.fuel = "unlimited"
  assert(h.start().ok); h.worker.runPending(); equal(h.worker.state, "completed")
end)

test("inventory pauses before a dig and resumes after unloading", function()
  local h = harness()
  for i=1,14 do h.sim.inventory[i]=64 end
  h.sim.fill(assert(planner.create(spec(), pose())))
  assert(h.start().ok)
  h.onSleep = function()
    equal(#h.sim.digs, 0)
    assert(h.worker.reason:find("Inventory",1,true))
    for i=1,15 do h.sim.inventory[i]=0 end
    assert(h.command("resume").ok)
  end
  h.worker.runPending(); equal(h.worker.state, "completed")
end)

test("protected blocks, fluids and bedrock are never removed", function()
  for _, block in ipairs({"computercraft:turtle_normal","computercraft:computer_advanced",
    "minecraft:chest","minecraft:barrel","minecraft:red_shulker_box","minecraft:spawner",
    "minecraft:water","minecraft:lava","minecraft:bubble_column","minecraft:bedrock"}) do
    local h = harness()
    local first = planner.target(assert(planner.create(spec(),pose())),1)
    h.sim.blocks[sim.key(first)] = block
    assert(h.start().ok)
    h.onSleep = function() equal(#h.sim.digs,0); assert(h.command("cancel").ok) end
    h.worker.runPending(); equal(h.sim.blocks[sim.key(first)],block)
  end
end)

test("falling blocks are retried with a finite limit", function()
  local p = pose()
  for _, falling in ipairs({ 3, 100 }) do
    local s = sim.new(p)
    local plan = assert(planner.create(spec(1,1,1),p))
    s.fill(plan); s.falling = falling
    local m = motion.new(s.api, p)
    local ok = m.step(planner.target(plan,1), true, plan)
    equal(ok,falling==3)
    equal(#s.digs,falling==3 and 4 or 16)
    if not ok then equal(sim.key(m.pose),sim.key(p)) end
  end
end)

test("entity obstruction and failed turns do not change tracked position", function()
  local p = pose()
  local s = sim.new(p); s.entity = true
  local plan = assert(planner.create(spec(),p))
  local m = motion.new(s.api,p)
  assert(not m.step(planner.target(plan,1),true,plan)); equal(sim.key(m.pose),sim.key(p))
  s.turnFailure = true; assert(not m.face(1)); equal(m.pose.heading,0)
end)

test("return path blockage pauses without digging", function()
  local h = harness()
  local p = pose(); local plan = assert(planner.create(spec(1,1,1),p))
  h.sim.fill(plan); assert(h.start(spec(1,1,1)).ok)
  h.sim.onAction = function(kind)
    if kind=="move" then h.sim.blocks[sim.key(p)]="minecraft:stone"; h.sim.onAction=nil end
  end
  h.onSleep = function()
    equal(#h.sim.digs,1); assert(h.worker.reason:find("Return path",1,true))
    h.sim.blocks[sim.key(p)]=nil; assert(h.command("resume").ok)
  end
  h.worker.runPending(); equal(h.worker.state,"completed"); equal(#h.sim.digs,1)
end)

test("motion independently refuses outside digging and nonadjacent movement", function()
  local p=pose(); local s=sim.new(p); local m=motion.new(s.api,p)
  local plan=assert(planner.create(spec(),p))
  assert(not m.step({x=p.x,y=p.y+1,z=p.z},true,plan))
  assert(not m.step({x=p.x,y=p.y-2,z=p.z},true,plan))
  equal(s.actions,0)
end)

test("network schema rejects other fleets and versions", function()
  assert(not net.valid(nil,"fleet")); assert(not net.valid("bad","fleet"))
  assert(net.valid(net.packet("fleet","discover"),"fleet"))
  assert(not net.valid(net.packet("other","discover"),"fleet"))
  assert(not net.valid({version=2,group="fleet",kind="discover"},"fleet"))
end)

test("wireless modem discovery handles pocket top slot and ignores wired modems", function()
  local opened={}
  peripheral={getNames=function() return {"top","left","monitor_0"} end,
    hasType=function(side) return side~="monitor_0" end,
    call=function(side,method) equal(method,"isWireless"); return side=="top" end}
  rednet={open=function(side) opened[#opened+1]=side end}
  net.open(); equal(#opened,1); equal(opened[1],"top")
  peripheral.getNames=function() return {} end
  assert(not pcall(net.open))
end)

require("gui_tests").run(test,equal)
require("install_tests").run(test,equal)

test("standalone installer: controller payload installs with no companion files",function()
  require("install_tests").bundle("controller")
end)
test("standalone installer: worker payload installs with no companion files",function()
  require("install_tests").bundle("worker")
end)

test("root installer: both roles install without external modules or companion files",function()
  require("install_tests").bundle("controller","install.lua")
  require("install_tests").bundle("worker","install.lua")
  local root=assert(io.open(PROJECT_ROOT.."/install.lua","r"))
  local release=assert(io.open(PROJECT_ROOT.."/dist/install.lua","r"))
  local rootSource,releaseSource=root:read("*a"),release:read("*a")
  root:close(); release:close()
  equal(rootSource,releaseSource)
end)

test("standalone installer: advanced turtle installs and launches with clicks at 39x13",function()
  require("install_tests").bundle("worker","install.lua",true)
end)

test("release bundles: mouse GUI, discovery, excavation and acknowledgements over Rednet", function()
  require("integration").run(true)
end)

test("release bundles: keyboard-only basic pocket completes the same excavation", function()
  require("integration").run(false)
end)

test("termination escapes the runner and retains the interrupted-job marker", function()
  local h=harness(); assert(h.start().ok)
  h.sim.api.down=function() error("Terminated",0) end
  local ok,why=pcall(h.worker.runPending)
  assert(not ok and why=="Terminated"); equal(h.marks,1)
end)

require("orbit_tests").run(test,equal)
require("update_app_tests").run(test,equal)
require("resolution_tests").run(test,equal)
require("desktop_ui_tests").run(test,equal)
require("programs_tests").run(test,equal)
require("worker_update_tests").run(test,equal)
test("Orbit release: Fleet completes excavation while another app is focused",function()
  require("integration").run(true,true)
end)
test("Orbit release: basic pocket keyboard workflow with background Fleet",function()
  require("integration").run(false,true)
end)
test("Orbit standalone installer: desktop, pocket and turtle screen installation",function()
  require("orbit_tests").installBundle()
end)
test("Orbit receiver release: saved setup, remote display and interactive monitor taps",function()
  require("orbit_tests").receiverBundle()
end)
print(("\n%d test groups passed."):format(count))
