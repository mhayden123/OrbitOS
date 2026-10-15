# Orbit OS 0.4.2

Orbit is a desktop environment for CC:Tweaked, built on CraftOS. It includes Turtle Fleet, movable and resizable app windows, a searchable app library, wired and wireless monitor casting, and an Update Center. It runs entirely as in-game Lua. Version 0.4.0 introduces a light interface, blue accents, clearer window controls, a dock, and layouts that use the space available on each device.

## Install

1. Copy **`install-os.lua` from the top level of the project** onto the computer. This one file contains the complete release; do not copy the source folder.
2. Run `install-os`. Choose **Desktop**, optionally enable **Start on boot**, then choose **Install Orbit OS**. On shorter screens, use **More** to reach additional options.
3. Select **Launch Orbit**, or run `orbit` later.
4. Open **Turtle Fleet** from Apps. Existing `/.fleet-controller` settings are reused. Continue using the existing Fleet installer and worker on mining turtles.

You can also copy `orbit.lua` directly and run it without installation. The installer writes `/orbit.lua`, retains numbered backups, and preserves Fleet settings. The optional startup launcher lives at `/startup/orbit.lua`; its temporary files and backups are kept outside the startup directory. Existing custom startup scripts are preserved. If Fleet already starts on boot, automatic Orbit startup is disabled to avoid starting two controllers; launch Orbit manually or adjust your startup configuration.

Use an advanced computer for mouse interaction. Basic computers support keyboard navigation. Desktop and receiver screens support 51×19 computers, 26×20 pockets and 39×13 turtles. **The Fleet controller itself still needs at least 26×19**, so run that app on a computer or pocket. Small displays use full-screen apps. Fleet needs full screen on a standard 51×19 computer; on a larger terminal it can use a floating window with at least 26×19 cells of content.

## Screen resolution

With the optional [Orbit Display companion mod](../companion/README.md), open **Settings → Screen resolution**. Choose Default, Balanced, More space or Custom. The enlarged computer GUI automatically fits the game window, and a 15-second confirmation restores the old size if you cannot use the new layout. Confirmed sizes persist per computer. Desktop and pocket presets are different; mouse and keyboard navigation both work. Install the companion JAR on the client and server and restart Minecraft once. Orbit's Update button updates the Lua interface, while Java companion upgrades require a Minecraft restart.

Live companion testing confirmed 80×30 on an advanced desktop and 40×30 on an advanced wireless pocket, automatic preview rollback, desktop persistence through a game restart, and working Fleet windows at the larger size. See the companion guide for exact version requirements and validation limits.

## Desktop controls

Version 0.4.1 incorporates an independent first-use review: stronger text contrast, outlined fields, bracketed buttons, darker active title bars, a visible Running tab and restore control, and a visual Programs browser. Floating windows show their name once in the title bar; full-screen apps retain their own heading. Enter advances through form fields instead of returning to the first field.

Version 0.4.2 separates the **Orbit** system menu (Settings, Updates, Help and Exit) from the **Apps** library. On compact screens, open Apps and select its Orbit button, or press F9. Exit still asks for confirmation. Window and menu shadows are clipped before reaching the screen edge or dock.

| Control | Action |
| --- | --- |
| Apps button or F1 | Open or hide the searchable app library |
| Orbit button or F9 | Open or hide system controls; Escape dismisses |
| Type in the app library | Filter apps; arrows/Tab select and Enter opens |
| Drag a window title | Move the window |
| Drag its bottom edge | Resize the window |
| Title `Cast` / F6 | Open casting for that app |
| Title `-` | Minimize; app keeps running |
| Title `+` / F3 | Full screen or restore |
| Title `x` / F10 | Close the current app |
| Dock button / F2 | Select or cycle apps; dock arrows reveal more apps |
| F4, then arrows | Move with the keyboard; Enter or Escape finishes |
| F5, then arrows | Resize with the keyboard; Enter or Escape finishes |
| Tab/arrows and Enter | Navigate app buttons and fields |
| More | Cycle through pages on compact forms |
| Settings → Exit Orbit | Confirm exit to CraftOS |
| Ctrl+T | Exit Orbit immediately |

At 60 columns by 22 rows or larger, apps open in floating windows with close, minimize and maximize controls on the left. Smaller screens show one full-screen app with **Apps** in the upper-right corner. Resizing the terminal switches layouts automatically while apps keep running, and restores floating window positions when space permits. Wide menus use two columns; compact menus use a single list and paginate when needed. Basic computers retain keyboard controls and a readable monochrome interface.

Up to eight windows can run at once. Turtle discovery, update transfers and heartbeats continue while Orbit is open, even when Fleet or Updates is closed. Closing Orbit stops those heartbeats; active turtles pause after their connection lease expires. Changing the Fleet group stops queued updates and ends contact with the previous fleet. Fleet's existing start-job review and cancellation confirmation remain in place.

**Programs** opens a visual browser of folders and Lua files. Select a file, then **Run program**. **CraftOS programs** opens the built-in tools; **Terminal** explicitly opens the command line. **Open by path** accepts a program name or path, including spaces, and Enter submits it. Programs supply their own text or graphical interface; Orbit does not turn command-line tools into GUI apps. Use Terminal when you need command arguments.

While a program runs, **Stop** or F7 asks before stopping it. Closing its window uses the same confirmation. Finished programs retain their output with **Programs** (Enter/F7) to return and **Again** (F8) to rerun. Errors retain the typed path so it can be corrected. Reopening Programs resumes its existing window. The app library's **Running** tab lists existing windows on every screen size; F2 also cycles through them. Explicitly maximized windows have a visible **[R]** restore control.

These are cooperative programs sharing the same computer and filesystem, not a security sandbox. Programs that never yield can still stall the computer. Multishell-specific UI programs are not isolated from the host shell. Window positions and running programs are not restored after reboot in this release.

## Cast to a monitor attached directly or by cable

1. Attach a monitor, or connect the computer and monitor using wired modems and networking cable. Enable peripheral sharing on the monitor's wired modem.
2. Open the app you want to display. Press **F6** or click **Cast** in its title bar.
3. In **Displays**, verify the selected app, or use **Choose an app**. Open **Connection help & options** and turn **Monitor taps: On** if you want interaction.
4. Select a monitor. On short windows, use **More** to reach the display list.

The app is mirrored to the monitor and keeps running when its window is hidden. Larger monitors center the app. If an app does not fit, Orbit automatically reduces the monitor text size, choosing the largest scale that fits down to 0.5. If even that cannot fit, the original scale is restored and Orbit explains how large the monitor must be. Successful casts retain the adjusted text size. The same fitting behavior works on wireless receivers running Orbit 0.2.1 or later. **Stop all casts** ends sharing.

Advanced monitor taps map to clicks inside the app. They do not provide keyboard entry or dragging; use the sender computer for text fields. Basic monitors can display apps but do not generate touch events. Monitor capabilities and wired peripheral access follow the [CC:Tweaked monitor API](https://tweaked.cc/peripheral/monitor.html).

## Cast over wireless or a computer network

A wireless display needs a receiving computer connected to its monitor. Both computers need compatible modems and must stay connected and loaded.

1. Install Orbit on the receiver and choose **Display receiver**, or run `orbit receive`.
2. Enter the **sender's computer ID** and matching **display network group** (default `orbit`). Set whether receiver-side monitor taps are allowed.
3. Choose **Start receiver**. This choice is saved, so receiver mode resumes after restart. **Stop receiving** disables it again.
4. On the sender, open **Displays**. The receiver appears as `#ID label / monitor_name`. Select the app and target.

The receiver has a **Monitors: text scale 0.5** button. A receiver may expose several attached or wired monitors; different apps may be cast to different targets. Sender and receiver must both allow taps for remote input. Display streams update at up to four frames per second, refresh unchanged frames periodically, and blank to a disconnected message after eight seconds without contact. Frames are limited to 12,000 cells.

The same display protocol uses wired, wireless, and Ender modems. Wired and wireless connectivity are transports, not an automatic network bridge: the receiver must be reachable through one of the sender's open modems. Reconnection resumes the selected stream while the sender is still running.

The owner ID and group avoid accidental cross-control; they are **not cryptographic authentication**. Rednet permits impersonation and eavesdropping, so use casting on networks with trusted players. See [Rednet's security model](https://tweaked.cc/module/rednet.html).

## One-button OS, app and turtle updates

Open **Apps → Updates → Update everything**. Orbit downloads and verifies both releases, installs the OS and its bundled apps, then sends the worker program to your assigned turtles over the modem. Turtles do not need HTTP access. The default source is built into the program:

```text
https://raw.githubusercontent.com/mhayden123/OrbitOS/main/dist/orbit-release
```

The repository is [mhayden123/OrbitOS](https://github.com/mhayden123/OrbitOS). It must be public for in-game downloads without credentials, and Minecraft's HTTP access must be enabled. No account token is stored on your computers.

**Included apps** lists app versions. Managed apps are Turtle Fleet (controller), Programs, Displays, Updates, and Settings. They are contained in `/orbit.lua`, so a single verified replacement updates them together. Rollback restores the whole previous OS bundle. Separate programs you copy onto the computer keep their own update mechanisms.

**Turtle updates** shows the result for each discovered turtle assigned to this controller. Active jobs, including paused or blocked jobs, wait until completed or cancelled by you. Idle workers receive acknowledged chunks, verify size, SHA-256 and Lua syntax, retain a backup, and restart their program. **Updated** means the new version has reconnected, not just that the transfer finished. Settings and fuel are preserved; updates do not move turtles. Offline turtles must be brought back into range and updated again. Keep Orbit open and chunks loaded until the transfers finish. Closing Updates alone does not stop the transfer. **Stop queued updates** cancels waiting/partial transfers; a worker already installing may finish and restart.

Workers older than 0.3.0 need **one initial upgrade** using the current `install.lua`, choosing **Turtle worker**, then launching it. Those older programs do not contain a receiver for updates. Once upgraded, use the controller's **Update everything** or **Turtle updates → Update turtles**. On the turtle, run the worker (`fleet`), not the Orbit desktop. Its startup should launch only the worker. In-game HTTP installation: `wget run https://raw.githubusercontent.com/mhayden123/OrbitOS/main/install.lua`.

Worker backups use `/.fleet-worker-update.backup` with numbered suffixes. If necessary, stop the worker and copy a retained backup over `/fleet.lua`. OS rollback does not roll back turtles. The owner ID, group and session prevent accidental cross-control but are not cryptographic authentication; use remote updates on trusted Rednet networks.

Settings are preserved. Running apps continue until you close Orbit and run `orbit` again; wait until turtle transfers and jobs are finished before restarting. Repeated updates to the same installed version do not create extra backups. **Update options → Check OS release** lets you review the version, app list and size first. **Update OS + apps only** leaves workers alone.

**Update options → Change update source** saves an override, and **Use OrbitOS GitHub** restores the built-in source. Existing overrides remain in effect across installations. Older Orbit versions can fetch this release using their existing OS updater; restart Orbit to see the new controls.

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
  worker.json
  fleet-worker.lua
```

Copy that directory onto an in-game disk as `/disk/orbit-release`, or into another directory visible to the controller. In **Updates → Update options → Change update source**, enter the directory and save it, then select **Update everything**. Only the controller needs the release files. A local Windows folder is not directly visible to an in-game computer: copy it into the world's ComputerCraft filesystem or transfer it using the server's supported method.

The updater checks the release's SHA-256 checksum and Lua syntax, verifies the staged write, and retains the previous `/orbit.lua` under a numbered backup name. Fleet settings are untouched; Orbit saves update source/history separately from the bundle. **Restore previous OS** restores the previous program after confirmation, retaining another backup of the replaced version. OS updates take effect the next time you close Orbit and run `orbit` again.

## Updates from GitHub

The default repository source is already configured. To use another source, publish all four generated release files together, either in a repository directory or as assets of the same GitHub release. Enter the HTTPS URL of their containing directory under **Change update source**. Supported forms include:

```text
https://raw.githubusercontent.com/OWNER/REPO/main/orbit-release
https://github.com/OWNER/REPO/releases/download/v0.1.1
```

These are templates: replace OWNER, REPO and the version with your own. A `github.com/.../blob/...` directory is normalized to its raw content URL. The manifest URL itself is accepted too. Commit all release files from the same build together; a mismatch is rejected. A release arriving during a check can produce a checksum mismatch; simply retry Update.

Private repositories requiring credentials are not supported. The server must allow HTTPS requests. Checksums detect damaged or mismatched downloads; they do not authenticate a publisher who controls both manifest and file. Choose an update URL you trust.

Updates start only on request. Downgrades through the update source are rejected; use **Update options → Restore previous OS** for the previous installed OS copy. A power interruption during file replacement may require manually restoring the retained backup. Updates across multiple computers are not an atomic transaction: inspect each turtle's result if a connection or disk fails.

## Verification and current limits

All 131 test groups pass. The suite includes real release-bundle installation, desktop window behavior at native and enlarged device sizes, keyboard and mouse control, app isolation, packet validation, owner restrictions, frame ordering, touch mapping, detach/reconnect handling, checksum vectors, HTTP/local update sources, failed writes and rollback. UI checks cover app search, dock overflow, compact/desktop transitions, menu pagination, parent-screen repainting, palette restoration and themed casting. End-to-end simulations run an excavation using Fleet inside the standalone Orbit bundle while another app is focused. A rendered preview uses the actual Lua character/color buffers.

The 0.4.0 interface was also checked in Minecraft on the 40×30 advanced pocket and 80×30 advanced desktop: app search, pocket Settings and Back navigation, live turtle discovery, window dragging, resizing, and dock restoration. Turtle #1 remained idle during these UI checks.

Live validation in Minecraft 26.3: controller #2 downloaded the public GitHub release with **Update everything**, installed the OS/apps, transferred Fleet 0.3.1 to turtle #1, and confirmed its restart from Fleet 0.3.0. The installed OS and worker matched the published SHA-256 hashes, backups were present, and the worker retained its fleet, assigned controller and fuel. Window dragging and resizing were exercised on the actual computer. Mining, failure recovery, and wireless casting retain simulation coverage; this live update test did not exercise every gameplay scenario.

This release does not include a file manager, encrypted networking, automatic app discovery/installation, saved window sessions, or migration of running programs to another computer. Casting mirrors a program that continues executing on the sender. Updates cover Orbit, bundled apps and assigned workers; standalone Fleet controllers still use the Fleet installer.

## Development

```text
python tools/build.py
python tools/test.py
python tools/preview_orbit.py
```

Edit `src/orbit/`, `src/orbit_main.lua`, or `src/orbit_install.lua`, then rebuild. Versions and the built-in update URL are configured in `release.json`. `src/orbit/release.lua` is generated: it includes the versioned app list discovered from `src/orbit/apps.lua`. New bundled app definitions join the same update mechanism. Bump the Orbit version when shipping any bundled app change; the Fleet version identifies the Fleet release separately.

Build outputs include standalone `orbit.lua`, `install-os.lua`, the manifest directory, and `dist/orbit-os.zip`. Build again after regenerating previews to include them in the zip. Run the tests and publish the changed source, bundles, and `dist/orbit-release` files to `mhayden123/OrbitOS` on `main` in the same commit. Editing files on the development PC alone does not publish them to Minecraft; Update sees the most recently published GitHub build.
