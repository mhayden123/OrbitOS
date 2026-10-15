local gui = require("fleet.gui")
local planner = require("fleet.planner")
local M = {}

function M.new(display, keys, options)
  local g, client = gui.new(display, keys), options.client
  local self = { gui = g, page = options.setup and "setup" or "home", history = {}, running = true,
    listPage = 1, infoPage = 1, group = client.group or "fleet", draft = {}, checked = false }
  local function go(page, reset)
    if reset then self.history = {} else self.history[#self.history + 1] = self.page end
    self.page, self.error, g.focus = page, nil, nil
    if page == "home" and self.selected then g.focus = "turtle:" .. self.selected end
    if page == "review2" then self.checked = false end
  end
  local function back()
    local previous = table.remove(self.history)
    if previous then
      self.page, self.error, g.focus = previous, nil, nil
      if previous == "home" and self.selected then g.focus = "turtle:" .. self.selected end
    elseif self.page ~= "home" and client.group then go("home", true) end
  end
  local function peer() return client.peers[self.selected] end
  local function writable()
    local p = peer()
    return client.fresh(p) and p.status.owner == client.owner
  end
  local function notice(title, text)
    self.infoTitle, self.infoText, self.infoPage = title, text, 1
    go("info")
  end
  local function command(body)
    local ok, why = client.request(self.selected, body)
    if ok then go("pending") else notice("Cannot send", why) end
  end
  local function field(id, label, index, nextId)
    g.field(id, label, 4 + (index - 1) * 4, self.draft[id] or "", function(value)
      self.draft[id], self.error, self.checked = value, nil, false
    end, { numeric = true, max = 10, enter = nextId })
  end
  local function numbers(definitions)
    for _, item in ipairs(definitions) do
      local value = tonumber(self.draft[item[1]])
      if not planner.integer(value, item[2], item[3]) then
        self.error = item[4] .. ": " .. item[2] .. " to " .. item[3]
        g.focus = item[1]
        return false
      end
    end
    return true
  end
  local function makePlan()
    local d = self.draft
    local pose = { x = 0, y = 0, z = 0, heading = 0, frame = "local" }
    if d.world then pose = { x = tonumber(d.x), y = tonumber(d.y), z = tonumber(d.z), heading = d.heading, frame = "world" } end
    local spec = { program = d.program, width = tonumber(d.width), length = tonumber(d.length), depth = tonumber(d.depth),
      x1 = tonumber(d.x1), z1 = tonumber(d.z1), x2 = tonumber(d.x2), z2 = tonumber(d.z2), floorY = tonumber(d.floorY) }
    local plan, why = planner.create(spec, pose)
    if not plan then self.error = why; return end
    self.plan, self.spec, self.pose = plan, spec, pose
    go("review1")
  end
  local function nextPage()
    if self.page == "placement" then go(self.draft.world and "origin" or "dimensions")
    elseif self.page == "origin" then
      if numbers({{"x",-30000000,30000000,"X"},{"y",-30000,30000,"Y"},{"z",-30000000,30000000,"Z"}}) then go("facing") end
    elseif self.page == "facing" and self.draft.heading ~= nil then
      if self.draft.program == "flatten" then
        self.draft.x1, self.draft.z1 = self.draft.x1 or self.draft.x, self.draft.z1 or self.draft.z
        go("corner1")
      else go("dimensions") end
    elseif self.page == "dimensions" then
      if numbers({{"width",1,256,"Width"},{"length",1,256,"Length"},{"depth",1,384,"Depth"}}) then makePlan() end
    elseif self.page == "corner1" then
      if numbers({{"x1",-30000000,30000000,"X"},{"z1",-30000000,30000000,"Z"}}) then go("corner2") end
    elseif self.page == "corner2" then
      if numbers({{"x2",-30000000,30000000,"X"},{"z2",-30000000,30000000,"Z"},{"floorY",-30000,30000,"Floor"}}) then makePlan() end
    elseif self.page == "review1" then go("review2") end
  end

  function self.render()
    local width, height = display.getSize()
    self.tooSmall = width < 26 or height < 19
    if self.tooSmall then
      g.begin("TURTLE FLEET", "Display too small")
      g.paragraph(4, "Use a display at least 26 columns by 19 rows.", math.max(1, height - 7))
      g.finish(); return
    end
    local p, d = peer(), self.draft
    local half = math.floor((math.min(40, width) - 5) / 2)
    local function pair(y, id, label, action, id2, label2, action2, enabled, enabled2, buttonHeight)
      g.button(id,label,2,y,half,action,{enabled=enabled,height=buttonHeight})
      g.button(id2,label2,half+4,y,g.size-half-4,action2,{enabled=enabled2,height=buttonHeight})
    end
    if self.page == "setup" then
      g.begin("CONNECT A FLEET", "Controller #" .. client.owner)
      g.field("group", "Fleet name", 4, self.group, function(value) self.group, self.error = value, nil end,
        { max = 32, enter = "next" })
      g.paragraph(9, "Use this name on every turtle. Assign them to controller #" .. client.owner .. ".", 4)
      if client.group then g.paragraph(14,"Changing fleet pauses active turtles after the link timeout.",3,"4") end
      g.footer(client.group and "Back" or "Quit", "Save", "save")
    elseif self.page == "home" then
      g.begin("TURTLE FLEET", "Control #" .. client.owner .. " | " .. client.group)
      local ids = {}; for id in pairs(client.peers) do ids[#ids+1] = id end; table.sort(ids)
      self.perPage = math.max(1, math.floor((height - 8) / 3))
      self.pages = math.max(1, math.ceil(#ids / self.perPage))
      self.listPage = math.min(self.listPage, self.pages)
      local focused = g.focus and tonumber(g.focus:match("^turtle:(%d+)$"))
      if focused then for index,id in ipairs(ids) do if id == focused then self.listPage=math.floor((index-1)/self.perPage)+1 end end end
      g.text(2,3,"LIVE " .. #ids .. "   page " .. self.listPage .. "/" .. self.pages,g.size-2,"8")
      local first = (self.listPage-1)*self.perPage+1
      for index=first,math.min(#ids,first+self.perPage-1) do
        local id, entry = ids[index], client.peers[ids[index]]
        local s = entry.status
        local status = client.fresh(entry) and s.state or "OFFLINE"
        local sub = s.owner ~= client.owner and (status .. " owner #" .. s.owner) or (status .. " fuel " .. s.fuel)
        g.button("turtle:"..id,"#"..id.." "..s.label,2,4+(index-first)*3,g.size-2,"open:"..id,{sub=sub})
      end
      if #ids == 0 then
        g.paragraph(6,"Looking for turtles...",2)
        g.paragraph(10,"Use the same fleet name and a wireless modem on each turtle.",4,"8")
      end
      pair(height-5,"prev","< Page","prev","more","Page >","more",self.listPage>1,self.listPage<self.pages)
      pair(height-2,"setup","Setup","setup","quit","Quit","quit")
    elseif self.page == "detail" and p then
      local s = p.status
      local status = client.fresh(p) and s.state:upper() or "OFFLINE"
      g.begin("TURTLE #"..self.selected,s.label)
      local percent = s.total>0 and math.floor(100*s.done/s.total) or 0
      g.text(3,4,status .. "  " .. percent .. "%",g.size-4,client.fresh(p) and "5" or "4")
      g.progress(5,s.done,s.total)
      g.text(3,6,"Cells "..s.done.."/"..s.total,g.size-4)
      g.text(3,7,"Fuel  "..s.fuel,g.size-4)
      if s.pose then
        g.text(3,9,"X "..s.pose.x.."  Y "..s.pose.y,g.size-4)
        g.text(3,10,"Z "..s.pose.z.."  "..s.pose.frame,g.size-4)
        g.text(3,11,"Facing "..planner.directions[s.pose.heading].name,g.size-4,"8")
      else g.text(3,9,"No position recorded",g.size-4,"8") end
      local reason = s.owner ~= client.owner and ("Assigned to controller #"..s.owner) or s.reason
      local activity = s.phase == "returning" and "Returning to start." or s.active and "Clearing selected area." or "Ready for instructions."
      g.paragraph(12,reason~="" and reason or activity,height >= 20 and 2 or 1,"8")
      pair(height-6,"new","New job","new","details","Details","details",writable() and not s.active and s.mining,true,1)
      local paused = s.state == "paused" or s.state == "blocked"
      pair(height-4,"control",paused and "Resume" or "Pause",paused and "resume" or "pause",
        "cancel","Cancel","cancel",writable() and s.active,writable() and s.active,1)
      g.footer("Back")
    elseif self.page == "program" then
      g.begin("NEW JOB", "Turtle #" .. self.selected .. " / program")
      g.button("flatten","Flatten by corners",2,5,g.size-2,"flatten",{height=3,sub="X/Z corners + floor Y"})
      g.button("quarry","Clear a volume",2,10,g.size-2,"quarry",{height=3,sub="Width x length x depth"})
      g.paragraph(15,"Mining pickaxe required.",1,"8")
      g.footer("Back")
    elseif self.page == "mode" then
      g.begin("POSITION MODE","Clear a volume")
      g.button("local","Relative to turtle",2,5,g.size-2,"local",{height=3,sub="No coordinates needed"})
      g.button("world","World coordinates",2,10,g.size-2,"world",{height=3,sub="Optional GPS check"})
      g.footer("Back")
    elseif self.page == "placement" then
      g.begin("PLACE THE TURTLE",d.world and "World coordinates" or "Relative coordinates")
      g.paragraph(4,"Start at a corner, one block ABOVE the highest terrain to remove.",4)
      g.text(3,9,"T . . .  <- start plane",g.size-4,"3")
      g.text(3,10,"# # # #  <- first layer",g.size-4)
      g.text(3,11,"= = = =  <- kept floor",g.size-4,"5")
      g.paragraph(13,d.program=="quarry" and "Width goes RIGHT. Length goes FORWARD. Leave the start plane clear." or
        "Start above ANY corner. Leave the start plane clear for the return trip.",4,"8")
      g.footer("Back","Next")
    elseif self.page == "origin" then
      g.begin("TURTLE POSITION","Turtle block coordinates")
      field("x","Starting X",1,"y"); field("y","Starting Y",2,"z"); field("z","Starting Z",3)
      g.footer("Back","Next")
    elseif self.page == "facing" then
      g.begin("FACING & GPS","Select the turtle direction")
      for heading=0,3 do
        local selected=d.heading==heading and "[x] " or "[ ] "
        local label=({"N -Z","E +X","S +Z","W -X"})[heading+1]
        local x=heading%2==0 and 2 or half+4
        g.button("heading:"..heading,selected..label,x,5+math.floor(heading/2)*3,
          heading%2==0 and half or g.size-half-4,"heading:"..heading)
      end
      g.button("gps",(d.verifyGPS and "[x] " or "[ ] ").."Check GPS",2,12,g.size-2,"gps")
      g.paragraph(15,"GPS: position only.",1,"8")
      g.footer("Back","Next","next",d.heading~=nil)
    elseif self.page == "dimensions" then
      g.begin("CLEAR A VOLUME","Includes starting column")
      field("width","Width RIGHT (1-256)",1,"length")
      field("length","Length FORWARD (1-256)",2,"depth")
      field("depth","Depth BELOW (1-384)",3)
      g.footer("Back","Review","next")
    elseif self.page == "corner1" then
      g.begin("AREA / CORNER 1","Inclusive X/Z rectangle")
      field("x1","First corner X",1,"z1"); field("z1","First corner Z",2)
      g.paragraph(13,"The turtle must be above one of the four corners.",3,"8")
      g.footer("Back","Next")
    elseif self.page == "corner2" then
      g.begin("AREA / CORNER 2","Opposite corner + floor")
      field("x2","Opposite corner X",1,"z2"); field("z2","Opposite corner Z",2,"floorY")
      field("floorY","Floor Y to KEEP",3)
      g.footer("Back","Review","next")
    elseif self.page == "review1" then
      local plan, pose=self.plan,self.pose
      g.begin("REVIEW / FOOTPRINT","1 of 2 | Turtle #"..self.selected)
      g.text(3,4,"Coordinates: "..pose.frame,g.size-4,"3")
      g.text(3,6,"X "..plan.minX..".."..plan.maxX,g.size-4)
      g.text(3,7,"Z "..plan.minZ..".."..plan.maxZ,g.size-4)
      g.text(3,9,"Start X "..pose.x,g.size-4)
      g.text(3,10,"Start Y "..pose.y,g.size-4)
      g.text(3,11,"Start Z "..pose.z,g.size-4)
      g.text(3,13,pose.frame=="local" and "Facing: as placed" or "Facing: "..planner.directions[pose.heading].name,g.size-4)
      g.text(3,15,plan.width.." wide x "..plan.length.." long",g.size-4,"8")
      g.footer("Back","Next")
    elseif self.page == "review2" then
      local plan=self.plan
      g.begin("REVIEW / EXCAVATION","2 of 2 | Turtle #"..self.selected)
      g.text(3,4,"Clear Y "..plan.topY..".."..(plan.floorY+1),g.size-4)
      g.text(3,5,"KEEP floor Y "..plan.floorY,g.size-4,"5")
      g.text(3,7,"Layers "..plan.depth,g.size-4)
      g.text(3,8,"Cells "..plan.total,g.size-4)
      g.text(3,9,"Travel fuel "..plan.fuel,g.size-4)
      g.paragraph(11,"Cuts only. Returns home.",2,"8")
      g.button("checked",(self.checked and "[x] " or "[ ] ").."Placement checked",2,14,g.size-2,"checked")
      g.footer("Back","Start job","start",self.checked and writable(),true)
    elseif self.page == "cancel" then
      g.begin("CANCEL THIS JOB?","Turtle #"..self.selected)
      g.paragraph(5,"The turtle will stop in place. It will NOT return home.",4,"4")
      g.paragraph(11,"Pause instead if you want to resume this job later.",4,"8")
      g.footer("Back","Cancel job","confirmCancel",writable(),true)
    elseif self.page == "quit" then
      g.begin("CLOSE CONTROLLER?",client.group or "Turtle Fleet")
      g.paragraph(5,"Active turtles pause after 12 seconds without contact.",4,"4")
      g.paragraph(11,"Reopen this controller and choose Resume to continue.",4,"8")
      g.footer("Back","Quit","confirmQuit")
    elseif self.page == "pending" then
      g.begin("SENDING COMMAND","Turtle #"..self.selected)
      g.paragraph(5,"Waiting for the turtle to acknowledge the command.",4)
      g.paragraph(11,"Discovery and connection heartbeats are still active.",4,"8")
      g.text(3,16,"Attempt "..(client.pending and client.pending.attempts or 1).." of 3",g.size-4,"3")
    elseif self.page == "info" then
      g.begin(self.infoTitle,"Turtle #"..(self.selected or "-"))
      local lines=gui.wrap(self.infoText,g.size-4)
      local per=height-8
      local pages=math.max(1,math.ceil(#lines/per))
      self.infoPage=math.min(self.infoPage,pages)
      for i=(self.infoPage-1)*per+1,math.min(#lines,self.infoPage*per) do g.text(3,4+(i-1)%per,lines[i],g.size-4) end
      g.text(3,height-4,"Page "..self.infoPage.."/"..pages,g.size-4,"8")
      g.footer("Back",self.infoPage<pages and "More" or nil,"infoMore")
    else go("home",true); return self.render() end
    if self.error then
      local errorText=self.error; self.error=nil
      notice("CHECK INPUT",errorText)
      return self.render()
    end
    g.finish()
  end

  function self.event(event,a,b,c)
    if event=="term_resize" then g.previous={} end
    if client.result then
      local result=client.result; client.result=nil
      go("detail",true)
      if not result.ok then notice("COMMAND RESULT",result.error) end
      return
    end
    if self.tooSmall then
      if event=="key" and a==keys.escape then self.running=false end
      return
    end
    if self.page=="pending" then return end
    local action=g.event(event,a,b,c)
    if event=="mouse_scroll" and self.page=="home" and display.isColor() then action=a>0 and "more" or "prev" end
    if not action then return end
    if action=="back" then
      if self.page=="home" or (self.page=="setup" and not client.group) then go("quit") else back() end
    elseif action=="setup" then self.group=client.group; go("setup")
    elseif action=="save" then
      if not self.group:match("^[%w_-]+$") or #self.group>32 then self.error="Use 1-32 letters, digits, - or _."
      else options.saveGroup(self.group); client.setGroup(self.group); go("home",true) end
    elseif action=="quit" then go("quit")
    elseif action=="confirmQuit" then self.running=false
    elseif action=="prev" or action=="more" then
      self.listPage=math.max(1,math.min(self.pages,self.listPage+(action=="more" and 1 or -1))); g.focus=nil
    elseif action:match("^open:") then self.selected=tonumber(action:sub(6)); go("detail")
    elseif action=="new" and writable() then
      local s=peer().status
      if s.active or not s.mining then return end
      self.revision,self.session=s.revision,s.session
      self.draft,self.checked,self.plan={},false,nil
      g.cursors={}; go("program")
    elseif action=="details" then
      local s=peer().status
      local position=s.pose and (" Position: X "..s.pose.x..", Y "..s.pose.y..", Z "..s.pose.z.." ("..s.pose.frame..").") or ""
      notice("TURTLE DETAILS",s.label..". "..s.state..". "..s.reason..position.." Owner #"..s.owner..". "..
        (s.mining and "Mining pickaxe equipped." or "Equip a diamond pickaxe to enable jobs."))
    elseif action=="flatten" or action=="quarry" then
      self.draft.program=action
      if action=="flatten" then self.draft.world=true; go("placement") else go("mode") end
    elseif action=="world" or action=="local" then self.draft.world=action=="world"; go("placement")
    elseif action:match("^heading:") then self.draft.heading=tonumber(action:sub(9))
    elseif action=="gps" then self.draft.verifyGPS=not self.draft.verifyGPS
    elseif action=="next" then nextPage()
    elseif action=="checked" then self.checked=not self.checked
    elseif action=="start" and self.checked then
      local p=peer()
      if not writable() or p.status.session~=self.session or p.status.revision~=self.revision or p.status.active then
        notice("TURTLE CHANGED","Turtle changed or went offline. Go back to the turtle dashboard and review a new job.")
      else command({action="start",spec=self.spec,pose=self.pose,verifyGPS=self.draft.verifyGPS==true,
        session=self.session,revision=self.revision}) end
    elseif action=="pause" or action=="resume" then command({action=action,jobId=peer().status.jobId})
    elseif action=="cancel" then self.cancelJob=peer().status.jobId; go("cancel")
    elseif action=="confirmCancel" then command({action="cancel",jobId=self.cancelJob})
    elseif action=="infoMore" then self.infoPage=self.infoPage+1 end
  end
  return self
end

return M
