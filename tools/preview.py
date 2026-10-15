"""Render actual Lua GUI cell buffers for visual review, without Minecraft."""
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
local fixture=require("gui_fixture")
local frames={}
local function capture(f,title)
  local rows={}
  for i,row in ipairs(f.screen.rows) do rows[i]={text=row.text,fg=row.fg,bg=row.bg} end
  frames[#frames+1]={title=title,rows=rows}
end
local f=fixture.new()
f.status(7,{label="Granite",state="running",active=true,done=1872,total=4096,fuel=6528,jobId="work"})
f.status(12,{label="Basalt",state="paused",active=true,done=288,total=1024,fuel=1184,jobId="other"})
f.status(18,{label="Flint",fuel=2400})
f.now=9
f.status(7,{label="Granite",state="running",active=true,done=1872,total=4096,fuel=6528,jobId="work",
  pose={x=108,y=73,z=211,heading=2,frame="world"}})
f.status(12,{label="Basalt",state="paused",active=true,done=288,total=1024,fuel=1184,jobId="other"})
f.render(); f.focus("turtle:7"); capture(f,"LIVE FLEET")
f.activate("turtle:7"); capture(f,"TURTLE DASHBOARD")
local job=fixture.new()
job.open(); job.activate("quarry"); job.activate("local"); job.activate("next")
job.type("width","16"); job.type("length","16"); job.type("depth","10")
capture(job,"JOB SETUP")
job.activate("next"); job.activate("next"); job.activate("checked")
capture(job,"JOB REVIEW")
local basic=fixture.new(26,20,false)
basic.status(7,{label="Granite",state="running",active=true,done=1872,total=4096,fuel=6528,jobId="work"})
basic.render(); basic.activate("turtle:7"); capture(basic,"BASIC POCKET / KEYBOARD")
return frames
''')

palette = ["f0f0f0", "f2b233", "e57fd8", "99b2f2", "dede6c", "7fcc19", "f2b2cc", "4c4c4c",
           "999999", "4c99b2", "b266e5", "3366cc", "7f664c", "57a64e", "cc4c4c", "111111"]
font_path = Path("C:/Windows/Fonts/consola.ttf")
font = ImageFont.truetype(str(font_path), 18) if font_path.exists() else ImageFont.load_default(size=18)
title_font = ImageFont.truetype(str(font_path), 16) if font_path.exists() else font
cw, ch, pad, gap = 11, 22, 22, 20
panel_w, panel_h = 26*cw + 2*pad, 20*ch + 2*pad + 30
sheet = Image.new("RGB", (3*panel_w+4*gap, 2*panel_h+3*gap+36), "#181e29")
draw = ImageDraw.Draw(sheet)
draw.text((gap, 12), "TURTLE FLEET 0.2  |  actual 26 x 20 terminal buffers (simulated)",font=title_font,fill="#dce7f5")
for index, frame in enumerate(frames.values()):
    x = gap+(index%3)*(panel_w+gap)
    y = 36+gap+(index//3)*(panel_h+gap)
    draw.rounded_rectangle((x,y,x+panel_w,y+panel_h),radius=12,fill="#242e3e",outline="#44516a",width=1)
    draw.text((x+pad,y+12),frame["title"],font=title_font,fill="#dce7f5")
    for row_index, row in enumerate(frame["rows"].values()):
        for col, char in enumerate(row["text"]):
            cx, cy = x+pad+col*cw, y+42+row_index*ch
            draw.rectangle((cx,cy,cx+cw-1,cy+ch-1),fill="#"+palette[int(row["bg"][col],16)])
            draw.text((cx,cy),char,font=font,fill="#"+palette[int(row["fg"][col],16)])
output = ROOT / "docs" / "pocket-gui-preview.png"
output.parent.mkdir(exist_ok=True)
sheet.save(output)
print(output)
