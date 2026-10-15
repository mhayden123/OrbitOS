"""Render the installer at actual pocket and turtle sizes, without Minecraft."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools"))
from lupa.lua52 import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute('package.path = PROJECT_ROOT .. "/src/?.lua;" .. PROJECT_ROOT .. "/tests/?.lua;" .. package.path')
frames = lua.execute('''
local terminal = require("terminal")
local memory = require("memory_fs")
local installer = require("fleet.installer")
local frames, turtles = {}, {}
local function capture(app, screen, title, target)
  app.render()
  local rows = {}
  for i, row in ipairs(screen.rows) do rows[i] = {text=row.text, fg=row.fg, bg=row.bg} end
  target = target or frames
  target[#target+1] = {title=title, rows=rows, width=screen.width, height=screen.height}
end
local function make(isTurtle, color)
  local screen = terminal.new(isTurtle and 39 or 26, isTurtle and 13 or 20, color)
  local disk = memory.new()
  local app = installer.new(screen.api, terminal.keys, {
    fs=disk.api, payloads={controller="return true", worker="return true"}, isTurtle=isTurtle
  })
  return app, screen
end
local app, screen = make(false, true)
capture(app, screen, "ON A POCKET COMPUTER")
app.event("key", terminal.keys.enter)
capture(app, screen, "STARTUP OPTIONS")
app.event("key", terminal.keys.tab)
app.event("key", terminal.keys.tab)
app.event("key", terminal.keys.enter)
capture(app, screen, "REVIEW BEFORE INSTALLING")
app.event("key", terminal.keys.tab)
app.event("key", terminal.keys.enter)
capture(app, screen, "READY TO LAUNCH")
local turtle, turtleScreen = make(true, true)
capture(turtle, turtleScreen, "ON A TURTLE")
capture(turtle, turtleScreen, "CHOOSE ROLE / 39 x 13", turtles)
turtle.event("key", terminal.keys.enter)
capture(turtle, turtleScreen, "STARTUP OPTIONS", turtles)
for i=1,3 do turtle.event("key", terminal.keys.tab) end
turtle.event("key", terminal.keys.enter)
capture(turtle, turtleScreen, "REVIEW BEFORE INSTALLING", turtles)
turtle.event("key", terminal.keys.tab)
turtle.event("key", terminal.keys.enter)
capture(turtle, turtleScreen, "READY TO LAUNCH", turtles)
local basic, basicScreen = make(false, false)
capture(basic, basicScreen, "BASIC POCKET / KEYBOARD")
return {main=frames, turtles=turtles}
''')

palette = ["f0f0f0", "f2b233", "e57fd8", "99b2f2", "dede6c", "7fcc19", "f2b2cc", "4c4c4c",
           "999999", "4c99b2", "b266e5", "3366cc", "7f664c", "57a64e", "cc4c4c", "111111"]
font_path = Path("C:/Windows/Fonts/consola.ttf")
font = ImageFont.truetype(str(font_path), 18) if font_path.exists() else ImageFont.load_default(size=18)
title_font = ImageFont.truetype(str(font_path), 16) if font_path.exists() else font
cw, ch, pad, gap = 11, 22, 22, 20
def render(frames, columns, name, title):
    frames = list(frames.values())
    panel_w = max(frame["width"] for frame in frames)*cw + 2*pad
    panel_h = max(frame["height"] for frame in frames)*ch + 2*pad + 30
    rows = (len(frames)+columns-1)//columns
    sheet = Image.new("RGB", (columns*panel_w+(columns+1)*gap, rows*panel_h+(rows+1)*gap+36), "#181e29")
    draw = ImageDraw.Draw(sheet)
    draw.text((gap, 12), title, font=title_font, fill="#dce7f5")
    for index, frame in enumerate(frames):
        x = gap+(index % columns)*(panel_w+gap)
        y = 36+gap+(index // columns)*(panel_h+gap)
        actual_w, actual_h = frame["width"]*cw+2*pad, frame["height"]*ch+2*pad+30
        x += (panel_w-actual_w)//2
        draw.rounded_rectangle((x, y, x+actual_w, y+actual_h), radius=12,
                               fill="#242e3e", outline="#44516a", width=1)
        draw.text((x+pad, y+12), frame["title"], font=title_font, fill="#dce7f5")
        for row_index, row in enumerate(frame["rows"].values()):
            for col, char in enumerate(row["text"]):
                cx, cy = x+pad+col*cw, y+42+row_index*ch
                draw.rectangle((cx, cy, cx+cw-1, cy+ch-1), fill="#"+palette[int(row["bg"][col], 16)])
                draw.text((cx, cy), char, font=font, fill="#"+palette[int(row["fg"][col], 16)])
    output = ROOT / "docs" / name
    output.parent.mkdir(exist_ok=True)
    sheet.save(output)
    print(output)

render(frames["main"], 3, "installer-preview.png",
       "TURTLE FLEET INSTALLER | 26 x 20 pocket / 39 x 13 turtle buffers (simulated)")
render(frames["turtles"], 2, "turtle-installer-preview.png",
       "TURTLE FLEET 0.2.4 | actual 39 x 13 turtle buffers (simulated)")
