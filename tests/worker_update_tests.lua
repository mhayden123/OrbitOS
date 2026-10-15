local transport=require("fleet.updates")
local client=require("fleet.update_client")
local sha=require("orbit.sha256")
local memory=require("memory_fs")
local net=require("fleet.net")
local M={}
function M.run(test,equal)
  local source="--"..string.rep("payload",1500).."\nreturn 'new worker'"
  local manifest={product="fleet-worker",format=1,artifact="fleet-worker.lua",version="0.3.0",size=#source,sha256=sha.digest(source)}
  local function fixture()
    local f=memory.new(); f.files["/fleet.lua"]="return 'old worker'"; f.files["/.fleet-worker"]="saved owner and group"
    local h={fs=f,now=0,active=false,step=0}
    h.worker=transport.receiver({owner=2,group="fleet",session="old",version="0.2.9",fs=f.api,path="/fleet.lua",
      active=function() return h.active end,now=function() return h.now end,yield=function() if h.yield then h.yield() end end})
    function h.message(kind,extra)
      h.step=h.step+1; local m=extra or {}; m.kind=kind; m.group="fleet"; m.session="old"; m.transfer="test"; m.step=h.step; return m
    end
    function h.send(kind,extra) return h.worker.receive(2,h.message(kind,extra)) end
    function h.chunks(value)
      value=value or source
      for i=1,#value,transport.CHUNK do assert(h.send("chunk",{index=math.floor((i-1)/transport.CHUNK)+1,data=value:sub(i,i+transport.CHUNK-1)}).ok) end
    end
    return h
  end
  test("Worker updates: owner, fleet, session and busy-job guards",function()
    local h=fixture(); local m=h.message("begin",{manifest=manifest})
    equal(h.worker.receive(99,m),nil); m.group="wrong"; equal(h.worker.receive(2,m),nil)
    m.group="fleet"; m.session="stale"; equal(h.worker.receive(2,m),nil)
    h.active=true; assert(not h.send("begin",{manifest=manifest}).ok); assert(not h.worker.busy())
    equal(h.fs.mutations,0)
  end)
  test("Worker updates: ordered chunks, duplicate delivery and verified replacement",function()
    local h=fixture(); assert(h.send("begin",{manifest=manifest}).ok); assert(h.worker.busy())
    assert(not h.send("chunk",{index=2,data="x"}).ok)
    local first=source:sub(1,transport.CHUNK)
    assert(h.send("chunk",{index=1,data=first}).ok); assert(h.send("chunk",{index=1,data=first}).ok)
    assert(not h.send("chunk",{index=1,data="different"}).ok)
    h.chunks(); equal(h.fs.mutations,0)
    local result=h.send("commit"); assert(result.ok and result.installed and h.worker.restart)
    equal(h.fs.files["/fleet.lua"],source); equal(h.fs.files[h.worker.backup],"return 'old worker'")
    equal(h.fs.files["/.fleet-worker"],"saved owner and group")
    local writes=h.fs.mutations; assert(h.send("commit").ok); equal(writes,h.fs.mutations)
  end)
  test("Worker updates: corrupt, incomplete and invalid Lua never replace installed worker",function()
    for _,kind in ipairs({"hash","missing","syntax"}) do
      local h=fixture(); local m={}; for k,v in pairs(manifest) do m[k]=v end
      local content=source
      if kind=="hash" then m.sha256=string.rep("0",64)
      elseif kind=="syntax" then content="invalid !!!"; m.size=#content; m.sha256=sha.digest(content) end
      assert(h.send("begin",{manifest=m}).ok); if kind~="missing" then h.chunks(content) end
      assert(not h.send("commit").ok); equal(h.fs.files["/fleet.lua"],"return 'old worker'")
      equal(h.fs.mutations,0); assert(not h.worker.busy())
    end
  end)
  test("Worker updates: failed disk move restores old program",function()
    local h=fixture(); h.send("begin",{manifest=manifest}); h.chunks()
    h.fs.fail=function(op,path) if op=="move" and path:find("staging",1,true) then error("disk failure") end end
    assert(not h.send("commit").ok); equal(h.fs.files["/fleet.lua"],"return 'old worker'"); assert(not h.worker.restart)
  end)
  test("Worker updates: timeout, cancellation and slow verification release the lock correctly",function()
    local h=fixture(); h.send("begin",{manifest=manifest}); h.now=16; h.worker.tick(); assert(not h.worker.busy())
    h.send("begin",{manifest=manifest}); assert(h.send("abort").ok); assert(not h.worker.busy())
    h.send("begin",{manifest=manifest}); h.chunks()
    h.yield=function() h.now=h.now+20; h.worker.tick(); assert(h.worker.busy()) end
    assert(h.send("commit").ok)
  end)
  local function network()
    local h=fixture(); h.queue={}
    h.controller=client.new({owner=2,group="fleet",boot="controller",now=function() return h.now end,
      send=function() end,broadcast=function() end,sendUpdate=function(id,m) h.queue[#h.queue+1]={id,m} end})
    function h.status(id,active,version,session)
      h.controller.receive(id,{version=1,group="fleet",kind="status",session=session or "old",owner=2,
        label="Turtle "..id,state="idle",reason="",revision=0,done=0,total=0,active=active,mining=true,fuel=100,
        update=version and {protocol=1,version=version} or nil},net.PROTOCOL)
    end
    function h.pump(drop)
      for _=1,50 do
        local item=table.remove(h.queue,1); if not item then break end
        local reply=h.worker.receive(2,item[2])
        if reply and not (drop and drop(item[2],reply)) then h.controller.receive(item[1],reply,transport.PROTOCOL) end
      end
    end
    h.release={manifest=manifest,source=source}; return h
  end
  test("Controller updates: queues busy jobs, reports legacy/current/offline separately",function()
    local h=network(); h.status(1,true,"0.2.9"); h.status(3,false,nil); h.status(4,false,"0.3.0")
    h.status(5,false,"0.2.9"); h.controller.client.peers[5].seen=-20
    h.controller.start(h.release); equal(#h.queue,0); assert(h.controller.running)
    equal(h.controller.rows[1].state,"Waiting"); equal(h.controller.rows[2].state,"Setup needed")
    equal(h.controller.rows[3].state,"Up to date"); equal(h.controller.rows[4].state,"Offline")
    h.status(1,false,"0.2.9"); h.controller.tick(); h.pump()
    equal(h.controller.rows[1].state,"Restarting")
    h.status(1,false,"0.3.0","new"); h.controller.tick()
    equal(h.controller.rows[1].state,"Updated"); assert(not h.controller.running)
  end)
  test("Controller updates: lost acknowledgements retry safely and require new worker status",function()
    local h=network(); h.status(1,false,"0.2.9"); h.controller.start(h.release)
    local dropped=false
    h.pump(function(m) if m.kind=="chunk" and not dropped then dropped=true; return true end end)
    h.now=3; h.controller.tick(); h.pump(function(m) return m.kind=="commit" end)
    equal(h.fs.files["/fleet.lua"],source); assert(h.controller.rows[1].state~="Updated")
    h.status(1,false,"0.3.0","new"); h.controller.tick(); equal(h.controller.rows[1].state,"Updated")
  end)
  test("Controller updates: cancellation aborts partial transfer without touching worker",function()
    local h=network(); h.status(1,false,"0.2.9"); h.controller.start(h.release)
    local begin=table.remove(h.queue,1); h.worker.receive(2,begin[2]); assert(h.worker.busy())
    h.controller.cancel(); h.pump(); assert(not h.worker.busy()); equal(h.fs.mutations,0)
    assert(not h.controller.running)
  end)
end
return M
