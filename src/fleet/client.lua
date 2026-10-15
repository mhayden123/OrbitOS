local net = require("fleet.net")
local planner = require("fleet.planner")
local M = {}

local function validStatus(m)
  return type(m.session) == "string" and #m.session <= 100 and type(m.state) == "string"
    and type(m.reason) == "string" and type(m.label) == "string"
    and planner.integer(m.owner, 0, 2147483647) and planner.integer(m.revision, 0, 2147483647)
    and planner.integer(m.done, 0, planner.MAX_VOLUME) and planner.integer(m.total, 0, planner.MAX_VOLUME)
    and type(m.active) == "boolean" and type(m.mining) == "boolean"
    and (m.fuel == "unlimited" or planner.integer(m.fuel, 0, 2147483647))
    and (m.jobId == nil or type(m.jobId) == "string") and (m.pose == nil or planner.validPose(m.pose))
end

function M.new(options)
  local self = { peers = {}, group = options.group, owner = options.owner, sequence = 0, heartbeatAt = 0 }
  local now, send, broadcast = options.now, options.send or net.send, options.broadcast or net.broadcast
  function self.fresh(peer) return peer and now() - peer.seen < net.STALE end
  function self.setGroup(group)
    assert(not self.pending, "Cannot change fleet while a command is pending.")
    self.group, self.peers, self.heartbeatAt, self.result = group, {}, 0, nil
  end
  function self.receive(sender, message)
    if not net.valid(message, self.group) then return end
    if message.kind == "status" and validStatus(message) then
      self.peers[sender] = { status = message, seen = now() }
      if self.pending and self.pending.id == sender and self.pending.body.session ~= message.session then
        self.result = { ok = false, error = "Turtle restarted. Review a new job.", action = self.pending.body.action }
        self.pending = nil
      end
    elseif message.kind == "ack" and self.pending and sender == self.pending.id
      and message.request == self.pending.body.request then
      self.result = { ok = message.ok == true, error = type(message.error) == "string" and message.error or "Command accepted.",
        action = self.pending.body.action }
      self.pending = nil
    end
  end
  function self.request(id, body)
    if self.pending then return false, "Another command is waiting for a reply." end
    local peer = self.peers[id]
    if not self.fresh(peer) then return false, "Turtle is offline or out of range." end
    if peer.status.owner ~= self.owner then return false, "This turtle belongs to another controller." end
    if body.session and body.session ~= peer.status.session then return false, "Turtle restarted. Review a new job." end
    self.sequence = self.sequence + 1
    body.request, body.session = options.boot .. ":" .. self.sequence, peer.status.session
    body.revision, body.jobId = body.revision or peer.status.revision, body.jobId or peer.status.jobId
    self.result = nil
    self.pending = { id = id, body = body, attempts = 1, deadline = now() + 2 }
    send(id, self.group, "command", body)
    return true
  end
  function self.tick()
    if not self.group then return end
    if now() >= self.heartbeatAt then
      broadcast(self.group, "discover")
      for id, peer in pairs(self.peers) do
        if peer.status.owner == self.owner then send(id, self.group, "heartbeat") end
      end
      self.heartbeatAt = now() + 2
    end
    local pending = self.pending
    if pending and now() >= pending.deadline then
      if pending.attempts == 3 then
        self.result = { ok = false, action = pending.body.action,
          error = "No acknowledgement. Outcome unknown. Check turtle status before retrying." }
        self.pending = nil
      else
        pending.attempts, pending.deadline = pending.attempts + 1, now() + 2
        send(pending.id, self.group, "command", pending.body)
      end
    end
  end
  return self
end

return M
