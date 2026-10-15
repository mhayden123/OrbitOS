"""Render actual Orbit app buffers for visual QA (not an in-game screenshot)."""
from pathlib import Path
import sys
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools"))
from lupa.lua52 import LuaRuntime
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute('package.path=PROJECT_ROOT.."/src/?.lua;"..PROJECT_ROOT.."/tests/?.lua;"..package.path')
frames = lua.execute('''
local desktop=require("orbit.desktop")
local apps=require("orbit.apps")
local terminal=require("terminal")
local keys=require("orbit_tests").keys
local frames={}
local function capture(screen,title)
  local rows={}; for i,r in ipairs(screen.rows) do rows[i]={r.text,r.fg,r.bg} end
  frames[#frames+1]={title=title,rows=rows,width=screen.width,height=screen.height,color=screen.color}
end
local function make(width,height,color)
  local screen=terminal.new(width,height,color)
  local manager
  local config={group="workshop"}
  local options={keys=keys,version=require("orbit.release").version,id=42,boot="preview",now=function() return 0 end,config=config,
    fs={list=function() return {"clock.lua","weather.lua"} end,isDir=function() return false end},
    modemCount=function() return 2 end,load=function() return {group="quarry"} end,save=function() end,saveConfig=function() end,
    title=function(id) local w=manager.find(id); return w and w.title end,windows=function() return manager.windows end,
    cast={streams={},targets=function() return {
      {key="local:monitor_0",name="monitor_0",width=79,height=38},
      {key="7:monitor_0",name="#7 Workshop / monitor_0",width=79,height=38}}
    end}}
  local definitions=apps.definitions(options)
  manager=desktop.new(screen.api,keys,{apps=definitions,subtitle="#42"})
  return screen,manager,definitions
end
local screen,d,defs=make(80,30,true)
d.render(); capture(screen,"APP LIBRARY / 80 x 30")
local program=d.open(defs[2]); program.app.page="path"; program.app.path="/clock.lua"
local network=d.open(defs[3]); network.app.source=program.id
d.geometry(program,3,3,45,20); d.geometry(network,999,999,53,21)
d.render(); capture(screen,"WINDOWS AT SCREEN EDGE / 80 x 30")
local settings=d.open(defs[5]); d.toggleSystem(); d.render(); capture(screen,"ORBIT MENU / SYSTEM CONTROLS")
local pocket,p,apps=make(40,30,true)
local fleet=p.open(apps[1])
fleet.app.event("rednet_message",7,{version=1,group="quarry",kind="status",session="7:boot",state="running",reason="Working",
  label="Granite",owner=42,revision=1,done=1872,total=4096,active=true,mining=true,fuel=6528,jobId="mine"},"turtle-fleet/1")
p.render(); capture(pocket,"TURTLE FLEET / POCKET 40 x 30")
local small,s,sd=make(26,20,true); s.open(sd[4]); s.render(); capture(small,"UPDATES / CLASSIC POCKET")
local basic,b,bd=make(51,19,false); b.open(bd[3]); b.render(); capture(basic,"BASIC COMPUTER / KEYBOARD")
return frames
''')
palette = [f"{int(value):06x}" for value in lua.eval('require("orbit.theme").palette').values()]
font_path = Path("C:/Windows/Fonts/consola.ttf")
font = ImageFont.truetype(str(font_path), 16) if font_path.exists() else ImageFont.load_default(size=16)
cw, ch, pad, gap = 10, 20, 18, 18
panel_w, panel_h = 80*cw+2*pad, 30*ch+60
sheet = Image.new("RGB", (2*panel_w+3*gap, 3*panel_h+4*gap+32), "#141c29")
draw = ImageDraw.Draw(sheet)
version = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))["orbitVersion"]
draw.text((gap,10), f"ORBIT OS {version} | Actual Lua terminal buffers, rendered in simulation", font=font, fill="#dce7f5")
for i, frame in enumerate(frames.values()):
    x, y = gap+(i%2)*(panel_w+gap), 32+gap+(i//2)*(panel_h+gap)
    draw.rounded_rectangle((x,y,x+panel_w,y+panel_h),radius=10,fill="#263145",outline="#506079")
    draw.text((x+pad,y+10),frame["title"],font=font,fill="#dce7f5")
    x += (panel_w-frame["width"]*cw)//2
    for row_i, row in enumerate(frame["rows"].values()):
        for col, char in enumerate(row[1]):
            cx, cy = x+col*cw, y+38+row_i*ch
            active_palette = palette if frame["color"] else {0: "f0f0f0", 7: "4c4c4c", 8: "999999", 15: "111111"}
            draw.rectangle((cx,cy,cx+cw-1,cy+ch-1),fill="#"+active_palette[int(row[3][col],16)])
            draw.text((cx,cy),char,font=font,fill="#"+active_palette[int(row[2][col],16)])
output = ROOT / "docs/orbit-preview.png"
sheet.save(output)
print(output)
