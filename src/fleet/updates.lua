-- Bounded, acknowledged transfers. Only the assigned controller may update an idle worker.
local sha=require("orbit.sha256")
local update=require("orbit.update")
local M={PROTOCOL="fleet-update/1",CHUNK=4096,LIMIT=512*1024,TIMEOUT=15}
function M.manifest(m)
  return type(m)=="table" and m.product=="fleet-worker" and m.format==1
    and m.artifact=="fleet-worker.lua" and update.version(m.version)~=nil
    and type(m.size)=="number" and m.size%1==0 and m.size>0 and m.size<=M.LIMIT
    and type(m.sha256)=="string" and #m.sha256==64 and not m.sha256:find("[^0-9a-f]")
end
function M.verify(m,source,yield)
  assert(M.manifest(m),"Invalid turtle release")
  assert(type(source)=="string" and #source==m.size,"Turtle release size mismatch")
  assert(sha.digest(source,yield)==m.sha256,"Turtle release checksum mismatch")
  assert(load(source,"@fleet-worker.lua","t",{}),"Invalid turtle Lua program")
end
function M.fetch(base,fs,http,decode,yield)
  local m=decode(update.fetch(base,"worker.json",fs,http))
  assert(M.manifest(m),"No turtle update in this release")
  local source=update.fetch(base,m.artifact,fs,http); M.verify(m,source,yield)
  return {manifest=m,source=source}
end
function M.receiver(o)
  local self={state="ready"}
  local pending,completed,installing
  function self.busy() return pending~=nil or self.restart==true end
  function self.tick()
    if pending and not installing and o.now()-pending.seen>M.TIMEOUT then pending=nil; self.state="Transfer timed out; retry from controller" end
  end
  function self.status()
    return {protocol=1,version=o.version,state=self.state,received=pending and pending.bytes or 0,total=pending and pending.manifest.size or 0}
  end
  function self.receive(sender,m)
    if sender~=o.owner or type(m)~="table" or m.group~=o.group or m.session~=o.session
      or type(m.transfer)~="string" or #m.transfer>100 or type(m.step)~="number" or m.step%1~=0 then return end
    local reply={group=o.group,session=o.session,transfer=m.transfer,step=m.step,ok=false}
    local function fail(why) reply.error=why; return reply end
    if completed and completed.transfer==m.transfer and m.kind=="commit" then reply.ok=true; reply.installed=true; return reply end
    if m.kind=="begin" then
      if o.active() then return fail("Working: update waits until the job finishes") end
      if pending then
        if pending.id==m.transfer then reply.ok=true; return reply end
        return fail("Another update is in progress")
      end
      if not M.manifest(m.manifest) then return fail("Invalid turtle release") end
      if update.version(m.manifest.version)<=update.version(o.version) then return fail("Already current or newer") end
      pending={id=m.transfer,manifest=m.manifest,chunks={},bytes=0,next=1,seen=o.now()}
      self.state="Receiving update"; reply.ok=true; return reply
    end
    if not pending or pending.id~=m.transfer then return fail("Transfer expired; retry") end
    pending.seen=o.now()
    if m.kind=="abort" then pending=nil; self.state="Update cancelled"; reply.ok=true; return reply end
    if m.kind=="chunk" then
      if type(m.index)~="number" or m.index%1~=0 or type(m.data)~="string" or #m.data==0 or #m.data>M.CHUNK then return fail("Invalid chunk") end
      if m.index<pending.next then
        if pending.chunks[m.index]~=m.data then return fail("Conflicting chunk") end
      elseif m.index~=pending.next then return fail("Missing earlier chunk")
      else
        if pending.bytes+#m.data>pending.manifest.size then return fail("Update exceeds expected size") end
        pending.chunks[m.index]=m.data; pending.bytes=pending.bytes+#m.data; pending.next=pending.next+1
      end
      reply.ok=true; return reply
    end
    if m.kind~="commit" then return fail("Unknown update step") end
    if o.active() then return fail("A job is active; update not installed") end
    self.state="Verifying update"; installing=true
    local ok,why=pcall(function()
      local source=table.concat(pending.chunks); M.verify(pending.manifest,source,o.yield)
      self.state="Installing update"
      self.backup=update.replace(o.fs,o.path,source,"/.fleet-worker-update.backup","/.fleet-worker-update.staging")
    end)
    installing=false
    if not ok then pending=nil; self.state="Update failed"; return fail(tostring(why)) end
    completed={transfer=pending.id}; pending=nil; self.restart=true; self.state="Restarting worker"
    reply.ok=true; reply.installed=true; return reply
  end
  return self
end
return M
