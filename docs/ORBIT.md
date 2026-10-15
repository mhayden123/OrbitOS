# Orbit OS 0.1.1

Orbit is a desktop environment for CC:Tweaked, built on CraftOS. It includes Turtle Fleet, movable and resizable app windows, a program launcher, wired and wireless monitor casting, and an Update Center. It runs entirely as in-game Lua.

## Install

1. Copy **`install-os.lua` from the top level of the project** onto the computer. This one file contains the complete release; do not copy the source folder.
2. Run `install-os`. Choose **Desktop**, optionally enable **Start on boot**, then choose **Install Orbit OS**. On shorter screens, use **More** to reach additional options.
3. Select **Launch Orbit**, or run `orbit` later.
4. Open **Turtle Fleet** from Apps. Existing `/.fleet-controller` settings are reused. Continue using the existing Fleet installer and worker on mining turtles.

You can also copy `orbit.lua` directly and run it without installation. The installer writes `/orbit.lua`, retains numbered backups, and preserves Fleet settings. The optional startup launcher lives at `/startup/orbit.lua`; its temporary files and backups are kept outside the startup directory. Existing custom startup scripts are preserved. If Fleet already starts on boot, automatic Orbit startup is disabled to avoid starting two controllers; launch Orbit manually or adjust your startup configuration.

Use an advanced computer for mouse interaction. Basic computers support keyboard navigation. Desktop and receiver screens support 51×19 computers, 26×20 pockets and 39×13 turtles. **The Fleet controller itself still needs at least 26×19**, so run that app on a computer or pocket. Small displays use full-screen apps. Fleet needs full screen on a standard 51×19 computer; on a larger terminal it can use a floating window with at least 26×19 cells of content.

## Desktop controls

| Control | Action |
| --- | --- |
| Apps button or F1 | Open or hide the app launcher |
| Drag a window title | Move the window |
| Drag its bottom edge | Resize the window |
| Title `C` / F6 | Open casting for that app |
| Title `_` | Minimize; app keeps running |
| Title `^` / F3 | Full screen or restore |
| Title `X` / F10 | Close the current app |
| Taskbar button / F2 | Select or cycle apps |
| F4, then arrows | Move with the keyboard; Enter or Escape finishes |
| F5, then arrows | Resize with the keyboard; Enter or Escape finishes |
| Tab/arrows and Enter | Navigate app buttons and fields |
| More | Cycle through pages on compact forms |
| Settings → Exit Orbit | Confirm exit to CraftOS |
| Ctrl+T | Exit Orbit immediately |

Up to eight windows can run at once. Turtle discovery and heartbeats continue when Fleet is behind another app. Closing Fleet or Orbit stops those heartbeats; active turtles pause after their connection lease expires. Fleet's existing start-job review and cancellation confirmation remain in place.

**Run a program** launches a CraftOS program in its own terminal window. Enter a program path, or use the default `shell` for a command prompt where you can enter arguments. These are cooperative programs sharing the same computer and filesystem, not a security sandbox. Programs that never yield can still stall the computer. Multishell-specific UI programs are not isolated from the host shell. Window positions and running programs are not restored after reboot in this release.

## Cast to a monitor attached directly or by cable

1. Attach a monitor, or connect the computer and monitor using wired modems and networking cable. Enable peripheral sharing on the monitor's wired modem.
2. Open the app you want to display. Press **F6** or click **C** in its title bar.
3. In **Displays & network**, verify the selected app. Enable **Allow monitor taps** if you want interaction.
4. Select a monitor. On short windows, use **More** to reach the display list.

The app is mirrored to the monitor and keeps running when its window is hidden. Larger monitors center the app; smaller monitors are rejected with a size explanation instead of clipping controls. Enlarge the monitor or reduce its text scale. For a directly accessible monitor you can set its scale in CraftOS with `lua`, followed by `peripheral.wrap("monitor_0").setTextScale(0.5)` using its actual peripheral name. **Stop all casts** ends sharing.

Advanced monitor taps map to clicks inside the app. They do not provide keyboard entry or dragging; use the sender computer for text fields. Basic monitors can display apps but do not generate touch events. Monitor capabilities and wired peripheral access follow the [CC:Tweaked monitor API](https://tweaked.cc/peripheral/monitor.html).

## Cast over wireless or a computer network

A wireless display needs a receiving computer connected to its monitor. Both computers need compatible modems and must stay connected and loaded.

1. Install Orbit on the receiver and choose **Display receiver**, or run `orbit receive`.
2. Enter the **sender's computer ID** and matching **display network group** (default `orbit`). Set whether receiver-side monitor taps are allowed.
3. Choose **Start receiver**. This choice is saved, so receiver mode resumes after restart. **Stop receiving** disables it again.
4. On the sender, open **Displays & network**. The receiver appears as `#ID label / monitor_name`. Select the app and target.

The receiver has a **Monitors: text scale 0.5** button. A receiver may expose several attached or wired monitors; different apps may be cast to different targets. Sender and receiver must both allow taps for remote input. Display streams update at up to four frames per second, refresh unchanged frames periodically, and blank to a disconnected message after eight seconds without contact. Frames are limited to 12,000 cells.

The same display protocol uses wired, wireless, and Ender modems. Wired and wireless connectivity are transports, not an automatic network bridge: the receiver must be reachable through one of the sender's open modems. Reconnection resumes the selected stream while the sender is still running.

The owner ID and group avoid accidental cross-control; they are **not cryptographic authentication**. Rednet permits impersonation and eavesdropping, so use casting on networks with trusted players. See [Rednet's security model](https://tweaked.cc/module/rednet.html).

## One-button OS and app updates

Open **Apps → Update Center → Update OS + apps**. Orbit downloads and verifies the configured release, then installs the OS and every bundled app together. The default source is built into the program:

```text
https://raw.githubusercontent.com/mhayden123/OrbitOS/main/dist/orbit-release
```

The repository is [mhayden123/OrbitOS](https://github.com/mhayden123/OrbitOS). It must be public for in-game downloads without credentials, and Minecraft's HTTP access must be enabled. No account token is stored on your computers.

**What's included?** lists app versions. Managed apps are Turtle Fleet (controller), Run a program, Displays & network, Update Center, and Settings & help. They are contained in `/orbit.lua`, so a single verified replacement updates them together. Rollback restores the whole previous bundle. Separate programs you copy onto the computer keep their own update mechanisms, and turtle workers are installed separately on each turtle with the Fleet installer.

Settings are preserved. Running apps continue until you close Orbit and run `orbit` again; the updater does not restart a working Fleet controller. Repeated Update clicks against the same installed file report that it is already up to date without creating extra backups. **Check without installing** lets you review the version, app list and size first.

**Change update source** saves an override, and **Use OrbitOS GitHub** restores the built-in source. Existing overrides remain in effect across installations. For a computer still on 0.1.0, install the new `install-os.lua` once, or enter the default source above in the old updater and install 0.1.1.

For a fresh install with HTTP enabled, run:

```text
wget run https://raw.githubusercontent.com/mhayden123/OrbitOS/main/install-os.lua
```

## Updates from a local directory

Every build creates `dist/orbit-release/` containing exactly:

```text
orbit-release/
  manifest.json
  orbit.lua
```

Copy that directory onto an in-game disk as `/disk/orbit-release`, or into another directory visible to the computer. In **Update Center → Change update source**, enter the directory and save it, then select **Update OS + apps**. A local Windows folder is not directly visible to an in-game computer: copy it into the world's ComputerCraft filesystem or transfer it using the server's supported method.

The updater checks the release's SHA-256 checksum and Lua syntax, verifies the staged write, and retains the previous `/orbit.lua` under a numbered backup name. Fleet settings are untouched; Orbit saves update source/history separately from the bundle. **Rollback previous update** restores the previous program after confirmation, retaining another backup of the replaced version. Updates take effect the next time you close Orbit and run `orbit` again.

## Updates from GitHub

The default repository source is already configured. To use another source, publish the generated `manifest.json` and `orbit.lua` together, either in a repository directory or as assets of the same GitHub release. Enter the HTTPS URL of their containing directory under **Change update source**. Supported forms include:

```text
https://raw.githubusercontent.com/OWNER/REPO/main/orbit-release
https://github.com/OWNER/REPO/releases/download/v0.1.1
```

These are templates: replace OWNER, REPO and the version with your own. A `github.com/.../blob/...` directory is normalized to its raw content URL. The manifest URL itself is accepted too. Commit both files from the same build together; a mismatch is rejected. A release arriving during a check can produce a checksum mismatch; simply retry Update.

Private repositories requiring credentials are not supported. The server must allow HTTPS requests. Checksums detect damaged or mismatched downloads; they do not authenticate a publisher who controls both manifest and file. Choose an update URL you trust.

Updates start only when you click **Update OS + apps**, or choose **Check without installing** and then **Install update**. Downgrades through the update source are rejected; use Rollback for the previous installed copy. A power interruption during file replacement may require manually restoring the retained backup.

## Verification and current limits

The test suite includes real release-bundle installation, desktop window behavior at native device sizes, keyboard and mouse control, app isolation, packet validation, owner restrictions, frame ordering, touch mapping, detach/reconnect handling, checksum vectors, HTTP/local update sources, failed writes and rollback. End-to-end simulations run an excavation using Fleet inside the standalone Orbit bundle while another app is focused. A rendered preview uses the actual Lua character/color buffers.

This is a first usable release, **not yet integration-tested inside Minecraft**. It does not include a file manager, encrypted networking, automatic app discovery/installation, saved window sessions, or migration of running programs to another computer. Casting mirrors a program that continues executing on the sender. The updater updates Orbit and the bundled Fleet controller; standalone turtle workers continue to use the Fleet installer.

## Development

```text
python tools/build.py
python tools/test.py
python tools/preview_orbit.py
```

Edit `src/orbit/`, `src/orbit_main.lua`, or `src/orbit_install.lua`, then rebuild. Versions and the built-in update URL are configured in `release.json`. `src/orbit/release.lua` is generated: it includes the versioned app list discovered from `src/orbit/apps.lua`. New bundled app definitions join the same update mechanism. Bump the Orbit version when shipping any bundled app change; the Fleet version identifies the Fleet release separately.

Build outputs include standalone `orbit.lua`, `install-os.lua`, the manifest directory, and `dist/orbit-os.zip`. Build again after regenerating previews to include them in the zip. Run the tests and publish the changed source, bundles, and `dist/orbit-release` files to `mhayden123/OrbitOS` on `main` in the same commit. Editing files on the development PC alone does not publish them to Minecraft; Update sees the most recently published GitHub build.
