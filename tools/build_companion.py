"""Build Orbit Display against an installed, unobfuscated Minecraft 26.3 Fabric instance.

Uses the game's exact dependency jars and bundled JDK; downloads nothing and never
modifies the instance. Supply --instance and --install for other installations.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--instance", type=Path, default=Path.home() / "curseforge/minecraft/Instances/Minecraft")
parser.add_argument("--install", type=Path, default=Path.home() / "curseforge/minecraft/Install")
parser.add_argument("--java-home", type=Path)
args = parser.parse_args()
java_home = args.java_home or args.install / "runtime/java-runtime-epsilon/windows-x64/java-runtime-epsilon"
instance = json.loads((args.instance / "minecraftinstance.json").read_text(encoding="utf-8-sig"))
assert instance["gameVersion"] == "26.3", "This companion targets Minecraft 26.3"
cc = args.instance / "mods/cc-tweaked-26.3-fabric-1.120.3.jar"
with zipfile.ZipFile(cc) as archive:
    assert json.loads(archive.read("fabric.mod.json"))["version"] == "1.120.3"
version = json.loads((args.install / "versions/26.3/26.3.json").read_text(encoding="utf-8-sig"))
loader = json.loads(instance["baseModLoader"]["versionJson"])
classpath = [args.install / "versions/26.3/26.3.jar", cc]
jei = list((args.instance / "mods").glob("jei-26.3-fabric-*.jar"))
assert len(jei) == 1, "Install JEI's 26.3 Fabric JAR to compile the optional JEI integration"
classpath += jei
for library in version["libraries"] + loader["libraries"]:
    artifact = library.get("downloads", {}).get("artifact", {})
    if "path" in artifact:
        path = args.install / "libraries" / artifact["path"]
    else:
        group, name, ver, *classifier = library["name"].split(":")
        suffix = "-" + classifier[0] if classifier else ""
        path = args.install / "libraries" / group.replace(".", "/") / name / ver / f"{name}-{ver}{suffix}.jar"
    if path.exists() and path not in classpath:
        classpath.append(path)
build = ROOT / "companion/build"
classes = build / "classes"
classes.mkdir(parents=True, exist_ok=True)
assert classes.resolve().is_relative_to((ROOT / "companion/build").resolve())
for stale in classes.rglob("*.class"):
    stale.unlink()
# String-named mixin hooks are not checked by javac. Verify them explicitly.
for class_name, member in [
    ("net.minecraft.client.gui.Gui", "void setScreen(net.minecraft.client.gui.screens.Screen)"),
    ("dan200.computercraft.shared.computer.core.ServerComputer", "void tickServer()"),
    ("dan200.computercraft.shared.computer.core.ComputerSystem", "ServerComputer computer;")
]:
    signature = subprocess.check_output([str(java_home / "bin/javap.exe"), "-p", "-classpath",
        ";".join(map(str, classpath)), class_name], text=True)
    assert member in signature, f"Missing mixin target: {class_name} {member}"
sources = sorted((ROOT / "companion/src/main/java").rglob("*.java"))
tests = sorted((ROOT / "companion/src/test/java").rglob("*.java"))
arguments = ["--release", "25", "-encoding", "UTF-8", "-proc:none", "-classpath",
             ";".join(map(str, classpath)), "-d", str(classes)] + list(map(str, sources + tests))
# javac argfiles use forward slashes, including paths with spaces.
argfile = build / "javac.args"
argfile.write_text("\n".join('"' + value.replace("\\", "/") + '"' for value in arguments), encoding="utf-8")
subprocess.run([str(java_home / "bin/javac.exe"), "@" + str(argfile)], check=True)
subprocess.run([str(java_home / "bin/java.exe"), "-ea", "-cp", str(classes), "dev.orbitos.display.DisplayTests"], check=True)
target = ROOT / "dist/orbit-display-0.1.0+mc26.3.jar"
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(classes.rglob("*.class")):
        if path.name.startswith("DisplayTests"):
            continue
        archive.write(path, path.relative_to(classes).as_posix())
    resources = ROOT / "companion/src/main/resources"
    for path in sorted(resources.rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(resources).as_posix())
    archive.write(ROOT / "companion/LICENSE", "LICENSE")
print(f"Built {target.name} ({target.stat().st_size:,} bytes)")
print("SHA-256:", hashlib.sha256(target.read_bytes()).hexdigest())
