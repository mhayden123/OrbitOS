local gui = require("fleet.gui")
local core = require("fleet.install_core")
local M = {}

function M.new(display, keys, options)
  local g = gui.new(display, keys)
  local fs, payloads = options.fs, options.payloads
  local self = { gui = g, page = options.role and "options" or "role", role = options.role or
    (options.isTurtle and "worker" or "controller"), startup = options.startup ~= false, running = true }
  local function go(page)
    self.page, g.focus = page, nil
    if page == "role" then g.focus = self.role end
  end
  local function message(title, text, back)
    self.messageTitle, self.messageText, self.messagePage, self.messageBack = title, text, 1, back
    go("message")
  end
  local function inspect()
    local info, why = core.inspect(fs)
    if not info then message("INSTALLER ERROR", why, "role"); return end
    self.info = info
    if not info.startupAvailable then self.startup = false end
  end
  inspect()
  if self.page == "role" then g.focus = self.role end

  function self.render()
    local width, height = display.getSize()
    local compact = height < 19
    self.tooSmall = width < 26 or height < 13
    if self.tooSmall then
      g.begin("FLEET INSTALLER", "Display too small")
      g.paragraph(4, "Use at least 26 columns and 13 rows. Esc exits.", math.max(1, height - 6)); g.finish(); return
    end
    local name = self.role == "worker" and "Turtle Worker" or "Controller"
    if self.page == "role" then
      g.begin("FLEET INSTALLER", "Choose what to install")
      g.button("controller", "Controller", 2, compact and 4 or 5, g.size - 2, "controller", { height = compact and 2 or 3,
        sub = options.isTurtle and "Control a turtle fleet" or "Recommended here" })
      g.button("worker", "Turtle Worker", 2, compact and 7 or 10, g.size - 2, "worker", { height = compact and 2 or 3, enabled = options.isTurtle,
        sub = options.isTurtle and "Recommended here" or "Requires a turtle" })
      g.paragraph(compact and 9 or 15, "Both programs included.", 1, "8")
      g.footer("Quit")
    elseif self.page == "options" then
      g.begin("INSTALL OPTIONS", name)
      g.paragraph(4, self.role == "worker" and "Needs a pickaxe and a wireless modem to work." or
        "Use a wireless modem to discover your turtles.", 3)
      g.button("startup", self.startup and "[x] Start on boot" or "[ ] Start on boot", 2, compact and 7 or 8, g.size - 2,
        "startup", { height = compact and 1 or 2, enabled = self.info and self.info.startupAvailable })
      if compact then
        g.button("setupDetails", self.info and self.info.note and "Startup notice" or "Setup details",
          2, 9, g.size - 2, "setupDetails", { height = 1 })
      else
        g.paragraph(12, self.info and self.info.note or "Fleet settings are kept. An existing program will be backed up.", 5, "8")
      end
      g.footer("Back", "Next")
    elseif self.page == "review" then
      g.begin("READY TO INSTALL", name)
      g.text(3, 4, "Program: /fleet.lua", g.size - 4)
      g.text(3, compact and 5 or 6, self.startup and "Startup: enabled" or "Startup: manual", g.size - 4, "5")
      if compact then
        g.paragraph(7, self.plan.backup and "Existing program will be backed up." or "A new program will be installed.", 2)
        g.paragraph(9, "Settings and other programs kept.", 2, "8")
      else
        g.paragraph(8, self.plan.backup and "An existing /fleet.lua will be backed up before replacing it." or
          "A new /fleet.lua will be installed.", 4)
        g.paragraph(13, "Existing fleet settings and other programs stay in place.", 3, "8")
      end
      g.footer("Back", "Install", "install")
    elseif self.page == "installing" then
      g.begin("INSTALLING", name)
      g.paragraph(5, "Writing and verifying the selected program...", 4)
    elseif self.page == "done" then
      g.begin("INSTALL COMPLETE", name)
      g.text(3, 4, "Run: fleet", g.size - 4, "5")
      g.text(3, compact and 5 or 6, self.result.startup and "Starts on boot." or "Launch manually.", g.size - 4)
      g.paragraph(compact and 7 or 8, compact and "Launch to set up your fleet." or
        "Launch now to configure the fleet name and connect your turtles.", compact and 2 or 4)
      g.button("details", "Install details", 2, compact and 9 or 13, g.size - 2, "details", { height = compact and 1 or 2 })
      g.footer("Done", "Launch", "launch")
    elseif self.page == "message" then
      g.begin(self.messageTitle, "Turtle Fleet installer")
      local lines = gui.wrap(self.messageText, g.size - 4)
      local per = height - 8
      local pages = math.max(1, math.ceil(#lines / per))
      self.messagePage = math.min(self.messagePage, pages)
      for i = (self.messagePage - 1) * per + 1, math.min(#lines, self.messagePage * per) do
        g.text(3, 4 + (i - 1) % per, lines[i], g.size - 4)
      end
      g.text(3, height - 4, "Page " .. self.messagePage .. "/" .. pages, g.size - 4, "8")
      g.footer("Back", self.messagePage < pages and "More" or nil, "more")
    end
    g.finish()
  end

  function self.event(event, a, b, c)
    if event == "term_resize" then g.previous = {} end
    if self.tooSmall then if event == "key" and a == keys.escape then self.running = false end; return end
    local action = g.event(event, a, b, c)
    if action == "back" then
      if self.page == "role" or self.page == "done" then self.running = false
      elseif self.page == "options" then go("role")
      elseif self.page == "review" then go("options"); inspect()
      elseif self.page == "message" then go(self.messageBack) end
    elseif action == "controller" or action == "worker" then self.role = action; go("options"); inspect()
    elseif action == "startup" then self.startup = not self.startup
    elseif action == "setupDetails" then
      message("SETUP DETAILS", ((self.info and self.info.note) or "") ..
        " Fleet settings are kept. An existing /fleet.lua will be backed up. Start on boot adds the Fleet startup launcher; otherwise run fleet manually.", "options")
    elseif action == "next" then
      local plan, why = core.prepare(fs, payloads, self.role, self.startup, options.isTurtle)
      if plan then self.plan = plan; go("review") else message("CANNOT INSTALL", why, "options") end
    elseif action == "install" then
      go("installing"); self.render()
      local result, why = core.apply(fs, self.plan)
      if result then self.result = result; go("done") else message("INSTALL FAILED", why, "options") end
    elseif action == "details" then
      local r = self.result
      message("INSTALL DETAILS", "Installed " .. r.role .. " at /fleet.lua. " ..
        (r.backup and "Previous program: " .. r.backup .. ". " or "") ..
        (r.startup and "Startup launcher: /startup/fleet.lua. " or "Run fleet to start manually. ") ..
        (r.note or "") .. " " .. r.warnings, "done")
    elseif action == "more" then self.messagePage = self.messagePage + 1
    elseif action == "launch" then self.launch, self.running = true, false end
  end
  return self
end

return M
