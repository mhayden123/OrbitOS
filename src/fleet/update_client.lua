local transport=require("fleet.updates")
local fleet=require("fleet.client")
local version=require("orbit.update").version
local M={}
function M.new(o)
  local client=fleet.new(o)
  local self={rows={},client=client,running=false,sequence=0}
  local current,release
  local send=o.sendUpdate
  local function finish(state,detail)
    current.row.state,current.row.detail=state,detail; current=nil
  end
  local function request(kind,extra)
    local m=extra or {}; current.step=current.step+1
    m.kind,m.group,m.session,m.transfer,m.step=kind,client.group,current.session,current.id,current.step
    current.message,current.attempts,current.deadline=m,1,o.now()+2
    send(current.row.id,m)
  end
  local function nextChunk()
    local start=(current.index-1)*transport.CHUNK+1
    if start>#release.source then current.row.state="Installing"; request("commit")
    else request("chunk",{index=current.index,data=release.source:sub(start,start+transport.CHUNK-1)}) end
  end
  function self.setGroup(group)
    self.cancel(); client.setGroup(group)
  end
  function self.start(value)
    assert(not self.running,"Turtle updates are already running")
    transport.verify(value.manifest,value.source,o.yield)
    release=value; self.rows={}; self.running=true
    local ids={}; for id,p in pairs(client.peers) do if p.status.owner==o.owner then ids[#ids+1]=id end end; table.sort(ids)
    for _,id in ipairs(ids) do
      local p=client.peers[id]; local u=p.status.update
      local row={id=id,label=p.status.label,version=type(u)=="table" and u.version or "Legacy",state="Waiting",progress=0}
      if not client.fresh(p) then row.state="Offline"
      elseif type(u)~="table" or u.protocol~=1 or not version(u.version) then row.state="Setup needed"
      elseif version(u.version)>=version(release.manifest.version) then row.state="Up to date" end
      self.rows[#self.rows+1]=row
    end
    self.tick()
  end
  function self.receive(sender,m,protocol)
    if protocol~="fleet-update/1" then
      client.receive(sender,m)
      local p=client.peers[sender]
      if current and current.row.id==sender and p and type(p.status.update)=="table"
        and p.status.update.version==release.manifest.version and p.status.session~=current.session then
        current.row.version=p.status.update.version
        finish("Updated","Worker reconnected")
      end
      return
    end
    if not current or not current.message or type(m)~="table" or sender~=current.row.id or m.group~=client.group
      or m.transfer~=current.id or m.session~=current.session or m.step~=current.step then return end
    if not m.ok then finish("Failed",tostring(m.error or "Update rejected")); return end
    if current.message.kind=="begin" then current.index=1; current.row.state="Sending"; nextChunk()
    elseif current.message.kind=="chunk" then
      current.row.progress=math.min(100,math.floor(current.index*transport.CHUNK/#release.source*100))
      current.index=current.index+1; nextChunk()
    elseif m.installed then
      current.row.state="Restarting"; current.message=nil; current.deadline=o.now()+15
    end
  end
  function self.tick()
    client.tick()
    if not self.running then return end
    if current then
      if o.now()>=current.deadline then
        if current.message and current.attempts<4 then
          current.attempts=current.attempts+1; current.deadline=o.now()+2; send(current.row.id,current.message)
        else finish("Check connection","No confirmation; refresh or retry") end
      end
      if current then return end
    end
    local waiting=false
    for _,row in ipairs(self.rows) do if row.state=="Waiting" then
      local p=client.peers[row.id]
      if not client.fresh(p) then row.state="Offline"
      elseif p.status.active then waiting=true; row.detail="Will update after the job"
      else
        self.sequence=self.sequence+1
        current={row=row,session=p.status.session,id=o.boot..":update:"..self.sequence,step=0}
        row.state,row.detail="Connecting",nil; request("begin",{manifest=release.manifest}); return
      end
    end end
    self.running=waiting
  end
  function self.cancel()
    if current and current.message and current.message.kind~="commit" then
      send(current.row.id,{kind="abort",group=client.group,session=current.session,transfer=current.id,step=current.step+1})
    end
    for _,row in ipairs(self.rows) do if row.state=="Waiting" then row.state="Cancelled" end end
    if current then finish("Stopped","Check worker status before retrying") end
    self.running=false
  end
  return self
end
return M
