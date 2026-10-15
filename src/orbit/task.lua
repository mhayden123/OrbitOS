-- Cooperative programs keep their own terminal redirect between event resumes.
local M={}
function M.new(fn,display,terminal,shellApi)
  local self={redirect=display,co=coroutine.create(fn),directory=shellApi and shellApi.dir()}
  function self.resume(...)
    if self.done then return end
    local old=terminal.current(); local dir=shellApi and shellApi.dir()
    terminal.redirect(self.redirect)
    if shellApi then shellApi.setDir(self.directory) end
    local ok,value=coroutine.resume(self.co,...)
    self.redirect=terminal.current(); terminal.redirect(old)
    if shellApi then self.directory=shellApi.dir(); shellApi.setDir(dir) end
    if not ok then self.error,self.done=tostring(value),true
    elseif coroutine.status(self.co)=="dead" then self.done=true; self.result=value
    else self.filter=value end
  end
  function self.event(event,...)
    if not self.filter or self.filter==event or event=="terminate" then self.resume(event,...) end
  end
  self.resume(); return self
end
return M
