local sha=require("orbit.sha256")
local M={LIMIT=2*1024*1024,TARGET="/orbit.lua"}
function M.version(v)
  if type(v)~="string" then return end
  local a,b,c=v:match("^(%d+)%.(%d+)%.(%d+)$")
  if a and #a<5 and #b<5 and #c<5 then return tonumber(a)*100000000+tonumber(b)*10000+tonumber(c) end
end
function M.manifest(m)
  local valid=type(m)=="table" and m.format==1 and m.product=="orbit-os" and M.version(m.version)~=nil
    and m.artifact=="orbit.lua" and type(m.size)=="number" and m.size%1==0 and m.size>0 and m.size<=M.LIMIT
    and type(m.sha256)=="string" and #m.sha256==64 and not m.sha256:find("[^0-9a-f]")
  if not valid then return false end
  -- Older manifests did not list the apps already contained in orbit.lua.
  if m.apps==nil then return true end
  if type(m.apps)~="table" or #m.apps>32 then return false end
  local seen,count={},0
  for index,app in pairs(m.apps) do
    count=count+1
    if type(index)~="number" or index%1~=0 or index<1 or index>#m.apps or type(app)~="table"
      or type(app.id)~="string" or #app.id>32 or not app.id:match("^[%w_-]+$") or seen[app.id]
      or type(app.title)~="string" or #app.title<1 or #app.title>48 or app.title:find("[%c]")
      or not M.version(app.version) then return false end
    seen[app.id]=true
  end
  return count==#m.apps
end
function M.verify(m,source,yield)
  assert(M.manifest(m),"Invalid Orbit release manifest")
  assert(type(source)=="string" and #source==m.size,"Release size does not match manifest")
  assert(sha.digest(source,yield)==m.sha256,"Release checksum does not match; nothing installed")
  assert(load(source,"@orbit.lua","t",{}),"Release is not valid Lua")
  return true
end
function M.read(fs,path,limit)
  if fs.getSize then assert(fs.getSize(path)<=limit,"File exceeds size limit") end
  local f=assert(fs.open(path,"r"),"Cannot read "..path)
  local ok,value=pcall(f.readAll); f.close(); assert(ok,value)
  assert(type(value)=="string" and #value<=limit,"File exceeds size limit"); return value
end
function M.fetch(base,name,fs,http)
  base=base:gsub("/manifest%.json$",""):gsub("/+$","")
  if base:match("^https://") then
    assert(http and http.get,"HTTP is disabled on this computer")
    base=base:gsub("^https://github.com/([^/]+/[^/]+)/blob/","https://raw.githubusercontent.com/%1/")
    local f,why,failed=http.get({url=base.."/"..name,binary=true,timeout=15})
    if not f then if failed then failed.close() end; error(why or "Download failed",0) end
    local limit=name=="manifest.json" and 16384 or M.LIMIT
    local ok,value=pcall(function()
      local parts,total={},0
      while true do local chunk=f.read(math.min(8192,limit-total+1)); if not chunk then break end; total=total+#chunk; assert(total<=limit,"Download exceeds size limit"); parts[#parts+1]=chunk end
      return table.concat(parts)
    end)
    f.close(); assert(ok,value); return value
  end
  assert(not base:find("://",1,true),"Use an HTTPS release URL or an in-game directory")
  return M.read(fs,base.."/"..name,name=="manifest.json" and 16384 or M.LIMIT)
end
function M.check(base,current,fs,http,decode,yield)
  assert(type(base)=="string" and #base>0,"Choose an update directory or HTTPS URL")
  local manifest=decode(M.fetch(base,"manifest.json",fs,http))
  assert(M.manifest(manifest),"This directory does not contain an Orbit release")
  assert(M.version(manifest.version)>=assert(M.version(current)),"Older release; use Rollback for the previous installation")
  local source=M.fetch(base,manifest.artifact,fs,http); M.verify(manifest,source,yield)
  local same=fs.exists(M.TARGET) and not fs.isDir(M.TARGET) and M.read(fs,M.TARGET,M.LIMIT)==source
  return {manifest=manifest,source=source,base=base,unchanged=same}
end
local function unused(fs,path)
  if not fs.exists(path) then return path end
  for i=1,999 do if not fs.exists(path.."."..i) then return path.."."..i end end
  error("Move older backups off this computer",0)
end
function M.replace(fs,path,source,backupBase,stageBase)
  assert(not fs.isReadOnly(path),"Installation storage is read-only")
  assert(not fs.exists(path) or not fs.isDir(path),"Destination is a directory")
  local free=fs.getFreeSpace(path)
  assert(type(free)~="number" or free>=#source+1024,"Not enough space for a verified update")
  local backup=fs.exists(path) and unused(fs,backupBase or path..".backup") or nil
  local stage=unused(fs,stageBase or path..".staging")
  local moved=false
  local ok,why=pcall(function()
    local h=assert(fs.open(stage,"w"),"Cannot stage update")
    local written,problem=pcall(h.write,source); h.close(); assert(written,problem)
    assert(M.read(fs,stage,M.LIMIT)==source,"Staged update could not be verified")
    if backup then fs.move(path,backup); moved=true end
    fs.move(stage,path)
  end)
  if not ok then
    if moved then
      local restored,problem=pcall(fs.move,backup,path)
      if not restored then why=tostring(why).." Restore manually from "..backup..": "..tostring(problem) end
    end
    if fs.exists(stage) then pcall(fs.delete,stage) end
    error(why,0)
  end
  return backup
end
function M.retire(fs,path,backupBase)
  if not fs.exists(path) then return end
  local backup=unused(fs,backupBase); fs.move(path,backup); return backup
end
function M.apply(fs,release,yield)
  M.verify(release.manifest,release.source,yield)
  return M.replace(fs,M.TARGET,release.source)
end
function M.rollback(fs,path)
  assert(type(path)=="string" and path:match("^/orbit%.lua%.backup%.?%d*$"),"No managed rollback copy")
  local source=M.read(fs,path,M.LIMIT); assert(load(source,"@orbit.lua","t",{}),"Rollback copy is invalid")
  return M.replace(fs,M.TARGET,source)
end
return M
