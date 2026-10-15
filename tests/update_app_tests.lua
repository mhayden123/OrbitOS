local apps=require("orbit.apps")
local update=require("orbit.update")
local releaseInfo=require("orbit.release")
local sha=require("orbit.sha256")
local memory=require("memory_fs")
local terminal=require("terminal")
local M={}

function M.run(test,equal)
  local function fixture(width,height,color)
    local screen=terminal.new(width or 26,height or 20,color)
    local f=memory.new(); f.files["/orbit.lua"]="return 'old OS and old apps'"
    f.files["/.fleet-controller"]="keep fleet"; f.files["/my-program.lua"]="keep my program"
    local source="return 'new OS and new apps'"
    local manifest={format=1,product="orbit-os",artifact="orbit.lua",version="0.2.0",size=#source,
      sha256=sha.digest(source),apps={{id="fleet",title="Turtle Fleet",version="0.2.4"}}}
    local current=screen.api
    local h={screen=screen,fs=f,source=source,manifest=manifest,requests={},config={group="orbit"},saves=0}
    local http={get=function(request)
      h.requests[#h.requests+1]=request.url
      coroutine.yield("http_success")
      if h.httpError then return nil,"HTTP 404: release unavailable" end
      local data=request.url:match("manifest%.json$") and "manifest" or h.source
      return {read=function(n) if #data==0 then return nil end; local chunk=data:sub(1,n); data=data:sub(n+1); return chunk end,close=function() end}
    end}
    local opts={keys=terminal.keys,config=h.config,version="0.1.1",fs=f.api,http=http,
      decode=function() return h.manifest end,saveConfig=function() h.saves=h.saves+1 end,
      term={current=function() return current end,redirect=function(t) local old=current; current=t; return old end}}
    function h.open()
      h.app=apps.definitions(opts)[4].create(screen.api)
    end
    local function input(...)
      local old=os
      os=setmetatable({startTimer=function() return 1 end,cancelTimer=function() end,
        pullEvent=function(name) return coroutine.yield(name) end},{__index=old})
      local ok,why=pcall(h.app.event,...); os=old; assert(ok,why)
    end
    function h.press(id,mouse)
      for _=1,12 do
        h.app.render()
        for _,w in ipairs(h.app.p.gui.widgets) do if w.id==id then
          if mouse then input("mouse_click",1,h.app.p.gui.left+w.x-1,w.y)
          else h.app.p.gui.focus=id; input("key",terminal.keys.enter) end
          return
        end end
        h.app.p.gui.focus="next"; input("key",terminal.keys.enter)
      end
      error("Missing update button: "..id)
    end
    function h.finish()
      local old=os
      os=setmetatable({startTimer=function() return 1 end,cancelTimer=function() end,
        pullEvent=function(name) return coroutine.yield(name) end},{__index=old})
      local ok,why=pcall(function()
        for _=1,100 do
          if not h.app.job then return end
          h.app.event("http_success"); h.app.event("timer",1); h.app.tick(); h.app.render()
        end
        error("Update did not finish")
      end)
      os=old; assert(ok,why)
    end
    h.open(); return h
  end

  test("Update Center: one button updates OS and apps at native screen sizes",function()
    for _,size in ipairs({{26,20,false},{39,13,true},{51,19,true}}) do
      local h=fixture(table.unpack(size)); h.press("update",size[3])
      assert(h.app.job and not h.app.job.done,"HTTP download did not yield: "..tostring(h.app.job and h.app.job.error))
      equal(h.fs.files["/orbit.lua"],"return 'old OS and old apps'")
      h.finish(); equal(h.fs.files["/orbit.lua"],h.source)
      equal(h.requests[1],releaseInfo.updateSource.."/manifest.json")
      equal(h.requests[2],releaseInfo.updateSource.."/orbit.lua")
      equal(h.fs.files[h.config.rollback],"return 'old OS and old apps'")
      equal(h.fs.files["/.fleet-controller"],"keep fleet"); equal(h.fs.files["/my-program.lua"],"keep my program")
      assert(h.app.message:find("all bundled apps",1,true)); equal(h.config.installedVersion,"0.2.0")
      -- Already installed but not restarted: no second backup or filesystem writes.
      local writes=h.fs.mutations; h.press("back"); h.press("update"); h.finish()
      equal(h.fs.mutations,writes); assert(h.app.message:find("Already up to date",1,true))
    end
  end)

  test("Update Center: source override persists, GitHub default can be restored",function()
    local h=fixture(); h.press("changeSource"); h.app.source="/disk/custom-release"; h.press("saveSource")
    equal(h.config.updateSource,"/disk/custom-release"); h.open(); equal(h.app.source,"/disk/custom-release")
    h.press("changeSource"); h.press("defaultSource"); equal(h.config.updateSource,releaseInfo.updateSource)
    h.open(); equal(h.app.source,releaseInfo.updateSource); equal(h.saves,2)
  end)

  test("Update Center: download failures and bad checksums never install",function()
    for _,failure in ipairs({"http","hash"}) do
      local h=fixture(); if failure=="http" then h.httpError=true else h.manifest.sha256=string.rep("0",64) end
      h.press("update"); h.finish()
      equal(h.fs.files["/orbit.lua"],"return 'old OS and old apps'"); equal(h.fs.mutations,0)
      equal(h.config.rollback,nil); equal(h.app.page,"message")
    end
  end)

  test("Update Center: check-only, install, rollback and installed-version guard",function()
    local h=fixture(); h.press("check"); h.finish(); equal(h.app.page,"review"); equal(h.fs.mutations,0)
    h.press("install"); h.finish(); equal(h.fs.files["/orbit.lua"],h.source)
    h.manifest.version="0.1.5"; h.press("back"); h.press("update"); h.finish()
    assert(h.app.message:find("Older release",1,true)); equal(h.fs.files["/orbit.lua"],h.source)
    h.press("back"); h.press("rollback"); h.press("restore"); h.finish()
    equal(h.fs.files["/orbit.lua"],"return 'old OS and old apps'")
    equal(h.fs.files[h.config.rollback],h.source); equal(h.config.installedVersion,nil)
  end)

  test("Update manifest: app metadata matches the registry and rejects malformed entries",function()
    local h=fixture(); assert(update.manifest(h.manifest))
    local definitions=apps.definitions({})
    equal(#definitions,#releaseInfo.apps)
    for i,definition in ipairs(definitions) do
      equal(releaseInfo.apps[i].id,definition.id); equal(releaseInfo.apps[i].title,definition.title)
      assert(update.version(releaseInfo.apps[i].version))
    end
    for _,invalid in ipairs({"apps",{{id="../fleet",title="Fleet",version="1.0.0"}},
      {{id="fleet",title="Fleet",version="invalid"}},
      {{id="fleet",title="Fleet",version="1.0.0"},{id="fleet",title="Duplicate",version="1.0.0"}}}) do
      h.manifest.apps=invalid; assert(not update.manifest(h.manifest))
    end
    h.manifest.apps=nil; assert(update.manifest(h.manifest),"Legacy manifests must still work")
  end)
end

return M
