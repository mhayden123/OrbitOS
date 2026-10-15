# Orbit Display

A Fabric companion for **Minecraft 26.3 and CC:Tweaked 1.120.3**. It adds per-computer resolution controls to Orbit OS 0.3.0 and a computer screen which automatically fits into Minecraft's viewport. Both standard and advanced computers and pocket computers are supported. Turtle inventory screens retain their native size.

## Install

1. Put [`orbit-display-0.1.0+mc26.3.jar`](../dist/orbit-display-0.1.0+mc26.3.jar) in the Minecraft instance's `mods` directory. For multiplayer, install it on the server and on every client using these computers.
2. Restart Minecraft/the server. This is required for a new Java mod.
3. Update Orbit OS, then open **Apps → Settings → Screen resolution**.
4. Pick Default, Balanced, More space, or Custom. Select **Keep resolution** within 15 seconds. Otherwise the server restores the previous size, including when the Lua program is closed or crashes.

Balanced is 80×30 on desktops and 40×30 on pockets. More space is 100×36 or 52×36 respectively. Custom sizes allow 26–160 columns and 13–60 rows. Larger grids make text physically smaller. The client fits the entire computer GUI into the game window and translates clicks, dragging and scrolling into the same logical coordinates. Minecraft's global GUI scale is not modified.

Confirmed sizes are saved per computer ID in the world's `computercraft/orbit-display/<id>.txt`. Moving a computer or restarting the world retains its size. These files do not contain programs or inventory data. To recover manually, stop the world/server and remove the affected ID's display settings file; the computer uses CC:Tweaked's configured default next time.

Orbit's Lua updater handles the OS and apps. It cannot replace a loaded Java mod or write outside the computer's sandbox. Future companion JAR upgrades require a Minecraft/server restart. The companion intentionally pins CC:Tweaked 1.120.3 because it uses internal terminal and screen interfaces; a newer CC:Tweaked release must be checked before widening this dependency.

## Lua API

Each supported computer receives an `orbit_display` API. It only controls that computer; no remote IDs, filesystem paths or code execution are accepted.

```lua
local info = orbit_display.getInfo()
-- info: apiVersion, version, kind, width/height, defaultWidth/defaultHeight,
-- minWidth/maxWidth, minHeight/maxHeight, previewSeconds, remaining, preview?
local token = orbit_display.preview(80, 30)
orbit_display.keep(token) -- save, or orbit_display.revert(token) to undo
```

These functions run on Minecraft's server thread and can yield. Orbit runs them in a separate coroutine so Fleet/network events continue. A resize raises `term_resize` and `orbit_display_changed`. The server owns preview timing, validates dimensions and preview tokens, and writes only after confirmation. A failed save leaves the timeout active.

## Build and test

Minecraft 26.3 is unobfuscated. `tools/build_companion.py` compiles against the exact installed game, CC:Tweaked, Fabric Loader and libraries using its Java 25 JDK. It performs no downloads and makes no changes to the Minecraft instance. No third-party classes are bundled into the output JAR.

```text
python tools/build_companion.py --instance "path/to/instance" --install "path/to/Minecraft/install"
python tools/build.py
python tools/test.py
```

The build instance must have CurseForge's `minecraftinstance.json` and JEI's 26.3 Fabric JAR to compile the optional JEI integration; JEI is optional at runtime. `--java-home` can select another JDK 25. Java tests cover timeout, confirmation, rollback, shutdown, stale tokens, failed saving, bounds and screen/input transforms. Lua tests cover presets, custom sizes, mouse/keyboard controls, asynchronous API events, companion absence and desktop resizing.

Live validation used Minecraft 26.3, Fabric Loader 0.19.5, CC:Tweaked 1.120.3 and JEI 31.12.0.66. An advanced desktop changed from 51×19 to 80×30, reverted automatically after an unconfirmed preview, then retained its confirmed size through a full game restart. Fleet discovery, mouse clicks, window dragging/resizing and hiding JEI's overlapping item panel were verified at the larger size. An advanced wireless pocket changed from 26×20 to 40×30 and saved its independent setting. Basic computers and dedicated multiplayer servers have not yet been exercised live; keyboard and grayscale layouts have automated coverage.

Source references: [CC:Tweaked API](https://tweaked.cc/mc-1.21.x/javadoc/), [Fabric project setup](https://docs.fabricmc.net/develop/getting-started/creating-a-project). The installed 26.3/1.120.3 JAR signatures were used for compatibility rather than assuming older source branches match.
