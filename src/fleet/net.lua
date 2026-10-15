local M = { VERSION = 1, PROTOCOL = "turtle-fleet/1", LEASE = 12, STALE = 8 }

function M.open()
  local count = 0
  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.hasType(side, "modem") and peripheral.call(side, "isWireless") then
      rednet.open(side)
      count = count + 1
    end
  end
  assert(count > 0, "Attach a wireless or Ender modem, then run Fleet again.")
end

function M.valid(message, group)
  return type(message) == "table" and message.version == M.VERSION
    and message.group == group and type(message.kind) == "string"
end

function M.packet(group, kind, body)
  local packet = body or {}
  packet.version, packet.group, packet.kind = M.VERSION, group, kind
  return packet
end

function M.send(id, group, kind, body)
  return rednet.send(id, M.packet(group, kind, body), M.PROTOCOL)
end

function M.broadcast(group, kind, body)
  rednet.broadcast(M.packet(group, kind, body), M.PROTOCOL)
end

return M
