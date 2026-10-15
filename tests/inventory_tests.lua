local planner = require("fleet.planner")
local sim = require("simulator")
local M = {}

function M.run(test, equal, harness)
  local function prepare(h, width, length)
    local job = { program = "quarry", width = width or 1, length = length or 1, depth = 1 }
    local plan = assert(planner.create(job, h.sim.pose))
    for i = 1, plan.total do h.sim.blocks[sim.key(planner.target(plan, i))] = "minecraft:dirt" end
    assert(h.start(job).ok)
    return plan
  end

  test("inventory simulation respects selected slot, wraps and matches dropped items", function()
    local h = harness(); local s = h.sim
    local plan = prepare(h)
    local key = sim.key(planner.target(plan, 1))
    s.api.select(5); assert(s.api.digDown()); equal(s.inventory[5], 1); equal(s.inventory[1], 0)
    s.blocks[key] = "minecraft:grass_block"
    assert(s.api.digDown()); equal(s.inventory[5], 2); equal(s.itemNames[5], "minecraft:dirt")
    s.blocks[key] = "minecraft:stone"
    assert(s.api.digDown()); equal(s.inventory[6], 1); equal(s.itemNames[6], "minecraft:cobblestone")
    s.setSlot(16, 64, "minecraft:coal"); s.api.select(16)
    s.blocks[key] = "minecraft:dirt"
    assert(s.api.digDown()); equal(s.inventory[1], 1); equal(s.inventory[5], 2)
  end)

  test("525 dirt blocks stack into nine cargo slots without blocking or spilling", function()
    local h = harness(); prepare(h, 21, 25)
    h.sim.setSlot(16, 48, "minecraft:coal")
    h.worker.runPending()
    equal(h.worker.state, "completed"); equal(h.worker.done, 525)
    for i = 1, 8 do equal(h.sim.inventory[i], 64) end
    equal(h.sim.inventory[9], 13)
    for i = 10, 15 do equal(h.sim.inventory[i], 0) end
    equal(h.sim.inventory[16], 48); equal(h.sim.spilled, 0)
  end)

  test("fourteen scattered dirt items consolidate before declaring cargo full", function()
    local h = harness(); prepare(h)
    for i = 1, 14 do h.sim.setSlot(i, 1, "minecraft:dirt") end
    -- Matching item in the fuel slot must still be excluded from consolidation.
    h.sim.setSlot(16, 48, "minecraft:dirt")
    h.worker.runPending(); equal(h.worker.state, "completed")
    equal(h.sim.inventory[1], 15); equal(h.sim.inventory[16], 48)
    for i = 2, 15 do equal(h.sim.inventory[i], 0) end
    for _, move in ipairs(h.sim.transfers) do assert(move.from < 16 and move.to < 16) end
  end)

  test("consolidation respects item variants and smaller stack limits", function()
    local h = harness(); prepare(h)
    h.sim.setSlot(1, 15, "minecraft:ender_pearl", 16)
    h.sim.setSlot(2, 3, "minecraft:ender_pearl", 16)
    h.sim.setSlot(3, 1, "minecraft:dirt", 64, "variant-a")
    h.sim.setSlot(4, 1, "minecraft:dirt", 64, "variant-b")
    h.sim.setSlot(5, 1, "minecraft:diamond_pickaxe", 1)
    h.sim.setSlot(6, 1, "minecraft:diamond_pickaxe", 1)
    for i = 7, 14 do h.sim.setSlot(i, 1, "minecraft:dirt") end
    h.worker.runPending(); equal(h.worker.state, "completed")
    equal(h.sim.inventory[1], 16); equal(h.sim.inventory[2], 2)
    for i = 3, 6 do equal(h.sim.inventory[i], 1) end
    equal(h.sim.itemTags[3], "variant-a"); equal(h.sim.itemTags[4], "variant-b")
    equal(h.sim.inventory[7], 9); equal(h.sim.spilled, 0)
  end)

  test("failed consolidation blocks without digging and retries on resume", function()
    local h = harness(); prepare(h)
    for i = 1, 14 do h.sim.setSlot(i, 1, "minecraft:dirt") end
    h.sim.transferFailure = true
    local waited = false
    h.onSleep = function()
      waited = true; equal(h.worker.state, "blocked"); equal(#h.sim.digs, 0)
      assert(h.worker.reason:find("Inventory", 1, true))
      h.sim.transferFailure = false; assert(h.command("resume").ok)
    end
    h.worker.runPending(); assert(waited); equal(h.worker.state, "completed")
    equal(h.sim.inventory[1], 15)
  end)

  test("cancel during cargo consolidation stops before further transfers or digs", function()
    local h = harness(); prepare(h)
    for i = 1, 14 do h.sim.setSlot(i, 1, "minecraft:dirt") end
    h.sim.onAction = function(kind) if kind == "transfer" then assert(h.command("cancel").ok) end end
    h.worker.runPending(); equal(h.worker.state, "cancelled")
    equal(#h.sim.transfers, 1); equal(#h.sim.digs, 0); equal(#h.sim.moves, 0)
  end)
end

return M
