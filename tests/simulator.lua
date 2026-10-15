local planner = require("fleet.planner")
local M = {}
function M.key(p) return ("%d:%d:%d"):format(p.x, p.y, p.z) end

function M.new(pose)
  local s = { pose = planner.copyPose(pose), blocks = {}, digs = {}, moves = {}, turns = 0,
    fuel = 100000, selected = 1, inventory = {}, itemNames = {}, itemTags = {}, stackSizes = {},
    transfers = {}, spilled = 0, falling = 0, actions = 0 }
  for i = 1, 16 do s.inventory[i] = 0 end
  local api = {}
  function s.setSlot(slot, count, name, limit, tag)
    s.inventory[slot], s.itemNames[slot] = count, name
    s.stackSizes[slot], s.itemTags[slot] = limit, tag
  end
  local function itemName(slot) return s.itemNames[slot] or "minecraft:cobblestone" end
  local function compatible(a, b)
    return itemName(a) == itemName(b) and s.itemTags[a] == s.itemTags[b]
  end
  local function target(direction)
    local p = planner.copyPose(s.pose)
    if direction == "up" then p.y = p.y + 1
    elseif direction == "down" then p.y = p.y - 1
    else
      local d = planner.directions[p.heading]
      p.x, p.z = p.x + d.x, p.z + d.z
    end
    return p
  end
  local function inspect(direction)
    local name = s.blocks[M.key(target(direction))]
    if name then return true, { name = name } end
    return false, "No block"
  end
  local function dig(direction)
    local p = target(direction)
    local key = M.key(p)
    if not s.blocks[key] then return false, "Nothing to dig" end
    if s.blocks[key] == "minecraft:bedrock" then return false, "Unbreakable block" end
    local drop = s.blocks[key]
    if drop == "minecraft:stone" then drop = "minecraft:cobblestone"
    elseif drop == "minecraft:grass_block" then drop = "minecraft:dirt" end
    s.blocks[key] = nil
    if s.falling > 0 then s.blocks[key], s.falling = "minecraft:gravel", s.falling - 1 end
    s.digs[#s.digs + 1] = p
    s.actions = s.actions + 1
    -- CC inserts drops starting at the selected slot, wrapping through all 16.
    -- An empty slot encountered first wins over a matching stack later on.
    local stored = false
    for offset = 0, 15 do
      local i = (s.selected - 1 + offset) % 16 + 1
      if s.inventory[i] == 0 then
        s.setSlot(i, 1, drop); stored = true; break
      elseif itemName(i) == drop and s.itemTags[i] == nil and api.getItemSpace(i) > 0 then
        s.inventory[i] = s.inventory[i] + 1; stored = true; break
      end
    end
    if not stored then s.spilled = s.spilled + 1 end
    if s.onAction then s.onAction("dig") end
    return true
  end
  local function move(direction)
    local p = target(direction)
    if s.blocks[M.key(p)] or s.entity then return false, "Movement obstructed" end
    if s.fuel ~= "unlimited" then
      if s.fuel < 1 then return false, "Out of fuel" end
      s.fuel = s.fuel - 1
    end
    s.pose.x, s.pose.y, s.pose.z = p.x, p.y, p.z
    s.moves[#s.moves + 1] = p
    s.actions = s.actions + 1
    if s.onAction then s.onAction("move") end
    return true
  end
  for _, dir in ipairs({ "forward", "up", "down" }) do
    api[dir] = function() return move(dir) end
    local suffix = dir == "forward" and "" or dir == "up" and "Up" or "Down"
    api["inspect" .. suffix] = function() return inspect(dir) end
    api["dig" .. suffix] = function() return dig(dir) end
  end
  local function turn(amount)
    if s.turnFailure then return false, "Turn failed" end
    s.pose.heading = (s.pose.heading + amount) % 4
    s.turns, s.actions = s.turns + 1, s.actions + 1
    if s.onAction then s.onAction("turn") end
    return true
  end
  api.turnLeft, api.turnRight = function() return turn(-1) end, function() return turn(1) end
  api.getFuelLevel = function() return s.fuel end
  api.getSelectedSlot = function() return s.selected end
  api.select = function(slot) s.selected = slot; return true end
  api.getItemCount = function(slot) return s.inventory[slot or s.selected] end
  api.getItemSpace = function(slot)
    slot = slot or s.selected
    return s.inventory[slot] == 0 and 64 or (s.stackSizes[slot] or 64) - s.inventory[slot]
  end
  api.compareTo = function(slot)
    if s.inventory[s.selected] == 0 or s.inventory[slot] == 0 then
      return s.inventory[s.selected] == s.inventory[slot]
    end
    return compatible(s.selected, slot)
  end
  api.transferTo = function(slot, count)
    local from = s.selected
    if s.transferFailure then return false, "Transfer failed" end
    if from == slot then return true end
    if s.inventory[from] == 0 then return false, "No items to transfer" end
    if s.inventory[slot] > 0 and not compatible(from, slot) then return false, "Incompatible items" end
    local room = s.inventory[slot] == 0 and (s.stackSizes[from] or 64) or api.getItemSpace(slot)
    local moved = math.min(count or 64, s.inventory[from], room)
    if moved == 0 then return false, "No space for items" end
    if s.inventory[slot] == 0 then
      s.setSlot(slot, 0, itemName(from), s.stackSizes[from], s.itemTags[from])
    end
    s.inventory[from], s.inventory[slot] = s.inventory[from] - moved, s.inventory[slot] + moved
    s.transfers[#s.transfers + 1] = { from = from, to = slot, count = moved }
    s.actions = s.actions + 1
    if s.onAction then s.onAction("transfer") end
    return true
  end
  api.refuel = function()
    if s.selected ~= 16 or s.inventory[16] < 1 or s.badFuel then return false, "No fuel" end
    s.inventory[16], s.fuel = s.inventory[16] - 1, s.fuel + 80
    return true
  end
  api.getEquippedLeft = function() return { name = "minecraft:diamond_pickaxe" } end
  api.getEquippedRight = function() return { name = "computercraft:wireless_modem" } end
  s.api = api
  function s.fill(plan, air)
    for i = 1, plan.total do
      if not air or i % 3 ~= 0 then s.blocks[M.key(planner.target(plan, i))] = "minecraft:stone" end
    end
  end
  return s
end
return M
