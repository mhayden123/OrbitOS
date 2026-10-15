local planner = require("fleet.planner")
local M = {}

function M.protected(name)
  return name:match("^computercraft:") or name:find("chest", 1, true)
    or name:find("shulker_box", 1, true) or name == "minecraft:barrel"
    or name == "minecraft:spawner" or name == "minecraft:trial_spawner"
end

function M.new(api, pose, checkpoint, changed)
  local self = { pose = planner.copyPose(pose), dug = 0 }
  checkpoint, changed = checkpoint or function() end, changed or function() end

  function self.face(heading)
    while self.pose.heading ~= heading do
      checkpoint()
      local left = (heading - self.pose.heading) % 4 == 3
      local ok, why = (left and api.turnLeft or api.turnRight)()
      if not ok then return false, why or "Cannot turn." end
      self.pose.heading = (self.pose.heading + (left and -1 or 1)) % 4
      changed()
    end
    return true
  end

  local function fuel()
    local level = api.getFuelLevel()
    if level == "unlimited" or level > 0 then return true end
    local selected = api.getSelectedSlot()
    api.select(16)
    local ok = api.refuel(1)
    api.select(selected)
    return ok, "Out of fuel. Put fuel in slot 16, then resume."
  end

  local function emptyCargoSlots()
    local empty = 0
    for slot = 1, 15 do
      if api.getItemCount(slot) == 0 then empty = empty + 1 end
    end
    return empty
  end

  local function compactCargo()
    -- Merge only compatible cargo stacks. Native transfers enforce item/component
    -- compatibility and stack limits; fuel slot 16 is never a source or target.
    for target = 1, 14 do
      if api.getItemCount(target) > 0 and api.getItemSpace(target) > 0 then
        for source = target + 1, 15 do
          checkpoint()
          if api.getItemCount(source) > 0 then
            api.select(source)
            if api.compareTo(target) then
              checkpoint()
              api.transferTo(target)
            end
          end
          if api.getItemSpace(target) == 0 then break end
        end
      end
    end
  end

  local function space()
    if emptyCargoSlots() < 2 then compactCargo() end
    if emptyCargoSlots() < 2 then return false, "Inventory nearly full. Empty cargo slots, then resume." end
    -- Drops search from the selected slot. Always start at 1 so partial stacks
    -- get used before later empty slots, instead of spreading one item per slot.
    api.select(1)
    return true
  end

  function self.step(target, mayDig, plan)
    local p = self.pose
    local dx, dy, dz = target.x - p.x, target.y - p.y, target.z - p.z
    if math.abs(dx) + math.abs(dy) + math.abs(dz) ~= 1 then
      return false, "Route error: target must be adjacent."
    end
    if mayDig and (not plan or not planner.contains(plan, target)) then
      return false, "Route error: digging outside the selected volume."
    end
    local move, inspect, dig
    if dy ~= 0 then
      move = dy > 0 and api.up or api.down
      inspect = dy > 0 and api.inspectUp or api.inspectDown
      dig = dy > 0 and api.digUp or api.digDown
    else
      local heading = dx == 1 and 1 or dx == -1 and 3 or dz == 1 and 2 or 0
      local ok, why = self.face(heading)
      if not ok then return false, why end
      move, inspect, dig = api.forward, api.inspect, api.dig
    end
    for _ = 1, 16 do
      checkpoint()
      local ok, why = fuel()
      if not ok then return false, why end
      local exists, block = inspect()
      if exists then
        if block.name == "minecraft:water" or block.name == "minecraft:lava"
          or block.name == "minecraft:bubble_column" then
          return false, "Fluid encountered: " .. block.name .. ". Drain it before resuming."
        end
        if not mayDig then return false, "Return path blocked. Clear it, then resume." end
        if M.protected(block.name) then return false, "Protected block: " .. block.name end
        ok, why = space()
        if not ok then return false, why end
        checkpoint()
        ok, why = dig()
        if not ok then return false, "Cannot dig: " .. (why or block.name) end
        self.dug = self.dug + 1
        changed()
      end
      checkpoint()
      ok, why = move()
      if ok then
        p.x, p.y, p.z = target.x, target.y, target.z
        changed()
        return true
      end
      -- A falling block may have replaced the dug block. Never attack entities.
      local solid = inspect()
      if not solid then return false, "Movement blocked by entity or world boundary: " .. (why or "unknown") end
    end
    return false, "Repeated falling blocks. Stabilize the area, then resume."
  end
  return self
end

return M
