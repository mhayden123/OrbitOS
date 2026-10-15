local planner = require("fleet.planner")
local motion = require("fleet.motion")
local net = require("fleet.net")
local M = {}

-- Receiver and runner share this state; only the runner calls turtle movement APIs.
function M.new(options)
  local self = {
    state = "idle", phase = "", reason = "", active = false, revision = 0,
    done = 0, total = 0, lastContact = options.now(), session = options.session,
    cache = {}, cacheOrder = {},
  }
  local cancelled = {}

  function self.snapshot()
    return {
      state = self.state, phase = self.phase, reason = self.reason,
      active = self.active, revision = self.revision, session = self.session,
      done = self.done, total = self.total, jobId = self.jobId,
      pose = self.mover and planner.copyPose(self.mover.pose) or nil,
      dug = self.mover and self.mover.dug or 0,
      fuel = options.turtle.getFuelLevel(), mining = options.mining(),
      owner = options.owner, label = options.label,
    }
  end

  local function publish() if options.publish then options.publish(self.snapshot()) end end

  function self.handle(sender, message)
    if sender ~= options.owner then return nil end
    if message.kind == "heartbeat" then
      self.lastContact = options.now()
      return nil
    end
    if message.kind ~= "command" or type(message.request) ~= "string" or #message.request > 100 then return nil end
    if message.session ~= self.session then
      return { request = message.request, ok = false, error = "Turtle restarted. Refresh its status." }
    end
    self.lastContact = options.now()
    if self.cache[message.request] then return self.cache[message.request] end
    local reply = { request = message.request, ok = false }
    local action = message.action
    if action == "start" then
      if options.maintenance and options.maintenance() then reply.error = "Worker update in progress. Try again when it reconnects."
      elseif self.active then reply.error = "Turtle is already working."
      elseif message.revision ~= self.revision then reply.error = "Status changed. Review and submit a fresh job."
      elseif not options.mining() then reply.error = "Equip a diamond pickaxe for mining programs."
      else
        local plan, why = planner.create(message.spec, message.pose)
        if not plan then reply.error = why
        elseif message.verifyGPS ~= true and message.verifyGPS ~= false then reply.error = "GPS choice is missing."
        elseif message.verifyGPS and message.pose.frame ~= "world" then reply.error = "GPS needs world coordinates."
        else
          self.plan, self.verifyGPS = plan, message.verifyGPS
          self.jobId, self.revision = message.request, self.revision + 1
          self.active, self.pending, self.cancel, self.pauseRequested, self.paused = true, true, false, false, false
          self.done, self.total, self.reason, self.state, self.phase = 0, plan.total, "", "starting", "checking"
          self.mover = nil
          reply.ok = true
        end
      end
    elseif not self.active or message.jobId ~= self.jobId then
      reply.error = "No matching active job."
    elseif action == "pause" then
      self.pauseRequested, reply.ok = true, true
    elseif action == "resume" then
      self.pauseRequested, self.paused, reply.ok = false, false, true
    elseif action == "cancel" then
      self.cancel, reply.ok = true, true
    else reply.error = "Unknown command." end
    self.cache[message.request] = reply
    self.cacheOrder[#self.cacheOrder + 1] = message.request
    if #self.cacheOrder > 64 then self.cache[table.remove(self.cacheOrder, 1)] = nil end
    publish()
    return reply
  end

  local function checkpoint()
    if self.cancel then error(cancelled, 0) end
    if options.now() - self.lastContact > net.LEASE then
      self.paused, self.state, self.reason = true, "paused", "Controller link lost. Reconnect, then resume."
    elseif self.pauseRequested then
      self.paused, self.state, self.reason = true, "paused", "Paused by controller."
    end
    while self.paused or self.pauseRequested do
      if self.cancel then error(cancelled, 0) end
      options.sleep(0.1)
    end
    if self.cancel then error(cancelled, 0) end
    -- Never act on a resume received before a renewed contact lease.
    if options.now() - self.lastContact > net.LEASE then return checkpoint() end
    self.state, self.reason = self.phase == "returning" and "returning" or "running", ""
  end

  local function retry(action)
    while true do
      checkpoint()
      local ok, why = action()
      if ok then return end
      self.paused, self.state, self.reason = true, "blocked", why
      publish()
      checkpoint()
    end
  end

  function self.runPending()
    if not self.pending then return false end
    self.pending = false
    local ok, why = pcall(function()
      if options.mark then options.mark({ jobId = self.jobId, program = self.plan.program }) end
      if self.verifyGPS then
        local x, y, z = options.locate()
        if not x then error("GPS unavailable. Check hosts or use a manually verified position.", 0) end
        local p = self.plan.origin
        if math.abs(x - p.x) > 0.1 or math.abs(y - p.y) > 0.1 or math.abs(z - p.z) > 0.1 then
          error("GPS does not match the entered starting position. No movement made.", 0)
        end
      end
      self.mover = motion.new(options.turtle, self.plan.origin, checkpoint)
      self.phase = "clearing"
      for index = 1, self.total do
        local target = planner.target(self.plan, index)
        retry(function() return self.mover.step(target, true, self.plan) end)
        self.done = index
      end
      self.phase = "returning"
      -- Rise in the cleared column, then cross above the volume without digging.
      for _, axis in ipairs({ "y", "x", "z" }) do
        while self.mover.pose[axis] ~= self.plan.origin[axis] do
          local target = planner.copyPose(self.mover.pose)
          target[axis] = target[axis] + (target[axis] < self.plan.origin[axis] and 1 or -1)
          retry(function() return self.mover.step(target, false) end)
        end
      end
      retry(function() return self.mover.face(self.plan.origin.heading) end)
    end)
    if not ok and why == "Terminated" then error(why, 0) end
    self.active, self.paused, self.pauseRequested = false, false, false
    if ok then self.state, self.reason = "completed", "Returned to the starting position."
    elseif why == cancelled then self.state, self.reason = "cancelled", "Stopped in place. Check position before a new job."
    else self.state, self.reason = "error", tostring(why) end
    if options.clearMark then options.clearMark() end
    publish()
    return true
  end

  return self
end

return M
