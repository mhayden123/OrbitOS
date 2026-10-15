"""Run Lua 5.2 simulations (no Minecraft installation required)."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / ".tools"))
try:
    from lupa.lua52 import LuaRuntime
except ImportError:
    raise SystemExit("Install test dependencies: python -m pip install --target .tools -r requirements-dev.txt")

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute('package.path = PROJECT_ROOT .. "/src/?.lua;" .. PROJECT_ROOT .. "/tests/?.lua;" .. package.path')
# Compile every source and generated program in the same Lua version as CraftOS syntax.
compile_lua = lua.eval('function(path) local f, why = loadfile(path); assert(f, why) end')
paths = sorted((ROOT / "src").rglob("*.lua")) + sorted((ROOT / "dist").glob("*.lua")) + [ROOT / "install.lua"]
for path in paths:
    compile_lua(path.as_posix())
print(f"Compiled {len(paths)} Lua files.", flush=True)
lua.execute((ROOT / "tests" / "run.lua").read_text(encoding="utf-8"))
