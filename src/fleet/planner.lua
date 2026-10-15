-- All geometry is independent of Minecraft, and uses inclusive block coordinates.
local M = {}
M.MAX_EDGE, M.MAX_DEPTH, M.MAX_VOLUME = 256, 384, 2000000
M.directions = {
  [0] = { x = 0, z = -1, name = "north" },
  [1] = { x = 1, z = 0, name = "east" },
  [2] = { x = 0, z = 1, name = "south" },
  [3] = { x = -1, z = 0, name = "west" },
}
M.programs = {
  { id = "flatten", name = "Flatten by corners", needsWorld = true },
  { id = "quarry", name = "Clear width/length/depth", needsWorld = false },
}

function M.integer(n, low, high)
  return type(n) == "number" and n == n and n % 1 == 0 and n >= low and n <= high
end

function M.validPose(p)
  return type(p) == "table" and M.integer(p.x, -30000000, 30000000)
    and M.integer(p.z, -30000000, 30000000) and M.integer(p.y, -30000, 30000)
    and M.integer(p.heading, 0, 3) and (p.frame == "world" or p.frame == "local")
end

function M.copyPose(p)
  return { x = p.x, y = p.y, z = p.z, heading = p.heading, frame = p.frame }
end

function M.create(spec, pose)
  if type(spec) ~= "table" or not M.validPose(pose) then
    return nil, "Invalid job or starting position."
  end
  local p = { origin = M.copyPose(pose), program = spec.program }
  if spec.program == "flatten" then
    if pose.frame ~= "world" then return nil, "Corners require world coordinates." end
    for _, key in ipairs({ "x1", "z1", "x2", "z2" }) do
      if not M.integer(spec[key], -30000000, 30000000) then
        return nil, "Corner coordinates must be whole numbers."
      end
    end
    if not M.integer(spec.floorY, -30000, 30000) then return nil, "Invalid floor Y." end
    if (pose.x ~= spec.x1 and pose.x ~= spec.x2)
      or (pose.z ~= spec.z1 and pose.z ~= spec.z2) then
      return nil, "Place the turtle above a corner of this rectangle."
    end
    local otherX = pose.x == spec.x1 and spec.x2 or spec.x1
    local otherZ = pose.z == spec.z1 and spec.z2 or spec.z1
    p.width, p.length = math.abs(otherX - pose.x) + 1, math.abs(otherZ - pose.z) + 1
    p.u = { x = otherX >= pose.x and 1 or -1, z = 0 }
    p.v = { x = 0, z = otherZ >= pose.z and 1 or -1 }
    p.depth = pose.y - 1 - spec.floorY
  elseif spec.program == "quarry" then
    p.width, p.length, p.depth = spec.width, spec.length, spec.depth
    p.u, p.v = M.directions[(pose.heading + 1) % 4], M.directions[pose.heading]
  else
    return nil, "Unknown program."
  end
  if not M.integer(p.width, 1, M.MAX_EDGE) or not M.integer(p.length, 1, M.MAX_EDGE) then
    return nil, "Width and length must be 1-256 blocks (corners are inclusive)."
  end
  if not M.integer(p.depth, 1, M.MAX_DEPTH) then
    return nil, "Remove 1-384 layers; floor Y must be at least 2 below the turtle."
  end
  p.area, p.total = p.width * p.length, p.width * p.length * p.depth
  if p.total > M.MAX_VOLUME then return nil, "Job exceeds 2,000,000 blocks." end
  p.topY, p.floorY = pose.y - 1, pose.y - p.depth - 1
  local farX = pose.x + p.u.x * (p.width - 1) + p.v.x * (p.length - 1)
  local farZ = pose.z + p.u.z * (p.width - 1) + p.v.z * (p.length - 1)
  if not M.integer(farX, -30000000, 30000000) or not M.integer(farZ, -30000000, 30000000)
    or not M.integer(p.floorY, -30000, 30000) then return nil, "Area is outside coordinate limits." end
  p.minX, p.maxX = math.min(pose.x, farX), math.max(pose.x, farX)
  p.minZ, p.maxZ = math.min(pose.z, farZ), math.max(pose.z, farZ)
  local last = M.target(p, p.total)
  p.fuel = p.total + math.abs(last.x - pose.x) + math.abs(last.z - pose.z) + p.depth
  return p
end

-- Adjacent serpentine layers run in opposite directions. No path table is allocated.
function M.target(p, index)
  assert(M.integer(index, 1, p.total), "Invalid route index")
  local layer = math.floor((index - 1) / p.area)
  local cell = (index - 1) % p.area
  if layer % 2 == 1 then cell = p.area - 1 - cell end
  local row, column = math.floor(cell / p.width), cell % p.width
  if row % 2 == 1 then column = p.width - 1 - column end
  return {
    x = p.origin.x + p.u.x * column + p.v.x * row,
    z = p.origin.z + p.u.z * column + p.v.z * row,
    y = p.topY - layer,
  }
end

function M.contains(p, target)
  return target.x >= p.minX and target.x <= p.maxX and target.z >= p.minZ
    and target.z <= p.maxZ and target.y > p.floorY and target.y <= p.topY
end

return M
