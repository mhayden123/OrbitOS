-- Development entry point. Copy the generated root install.lua into Minecraft.
local bundled, payloads = pcall(function() return require("fleet.payloads") end)
if not bundled then
  error("This is installer source. Copy install.lua from the project root or dist/ into your computer, then run install. Both programs are embedded in that file.", 0)
end
local installer = require("fleet.installer")
local args = { ... }
local role = args[1]
if role == "turtle" then role = "worker" end
if role == "auto" then role = turtle and "worker" or "controller" end
assert(not role or role == "controller" or role == "worker", "Usage: install [auto|controller|worker] [startup|manual]")
assert(not args[2] or args[2] == "startup" or args[2] == "manual", "Choose startup or manual.")
local app = installer.new(term, keys, { fs = fs, payloads = payloads, isTurtle = turtle ~= nil,
  role = role, startup = args[2] ~= "manual" })
local ok, why = pcall(function()
  while app.running do
    app.render()
    app.event(os.pullEvent())
  end
end)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok then error(why, 0) end
if app.launch then shell.run("/fleet.lua")
elseif app.result then print("Fleet installed. Run: fleet")
else print("Installer closed.") end
