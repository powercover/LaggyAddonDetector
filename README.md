<div align="center">

# Laggy Addon Detector

**Find the addon behind the stutter.**

![Game version](https://img.shields.io/badge/WoW-Retail%2012.1%20(Midnight)-1f6fb2)
![Addon version](https://img.shields.io/badge/version-2.0.0-d9a633)
![Dependencies](https://img.shields.io/badge/dependencies-none-3c9a5f)
![License](https://img.shields.io/badge/license-all%20rights%20reserved-555555)

</div>

Something updated, and now the game hitches. Instead of disabling addons one by one, Laggy Addon
Detector watches every addon live with the game's own addon profiler. It shows which ones are
busy every frame and which ones caused each slow frame, with when and where it happened. It costs
next to nothing while it watches.

## Highlights

- **Slow frames, with the culprit.** Every frame where an addon took longer than your threshold is
  logged in the background: the addon, how long the frame took, the zone or key level, the boss,
  and whether you were in combat. Stutter in a boss fight? Look it up after the fight.
- **Live CPU per addon.** Time per frame now, since reload and during boss fights, plus the peak
  frame. Each addon's share of the frame is worked out the way the game's AddOns list does it.
- **Memory growth, not just size.** A big addon that sits still costs nothing. Memory that grows
  fast makes the garbage collector run more often, and that's what stutters, so growth is what's
  shown and checked.
- **Light by design.** With nothing open it reads one number every two seconds and makes no
  garbage. `/lad perf` shows exactly what it costs.
- **Informative, not decorative.** No severity rainbows. The only colour is a number over one of
  your own thresholds, and that can be turned off.

## The window

`/lad`, or click the minimap button.

- **Summary:** frame rate, all addons' CPU per frame and their share of it, Lua memory and how fast
  it grows, and slow frames since login. Click the slow frame count to open the log.
- **The table:** every addon, sortable by any column. Right-click a header to choose columns:

  | Column | What it is |
  | --- | --- |
  | Now | CPU time per frame, averaged over the last 60 frames |
  | Share | Share of frame time, as the game's AddOns list works it out |
  | Average | CPU time per frame since the last reload |
  | Boss fights | CPU time per frame during boss encounters (off by default) |
  | Last frame | CPU time in the most recent frame (off by default) |
  | Peak | The longest single frame since the last reload, loading screens included |
  | >50 ms | Frames this addon alone took longer than the threshold, since login |
  | Memory | Memory the addon holds, from the last memory scan |
  | Growth | How fast its memory grew between the last two scans |

- **Search**, and **Only problems**: addons over your CPU threshold, those that made slow frames,
  or those whose memory grows fast.
- **Detail pane:** click an addon for all its figures and a histogram of its frames over 1, 5, 10,
  50, 100, 500 and 1000 ms. **Disable after reload** turns it off for this character, so you can
  check whether the stutter goes away without it. Turn it back on the same way.
- **Measure from now:** count slow frames from this moment, for a single pull or key.
- **Slow frame log:** every logged stutter, newest first. Hover one for details, Shift-click to put
  it in chat.
- Shift-click any addon to put its figures in chat. The window can be moved and resized.

## On-screen stats

Off by default. Turn them on in the settings, with `/lad stats`, or by middle-clicking the minimap
button. They show live numbers on screen: frame rate, frame time, latency, addons' CPU, the
busiest addon, Lua memory and slow frames (a new one is briefly tinted). Pick the items, one line
or one per line, size, update rate and background.

To place them, click **Move** in the settings (or type `/lad stats move`), drag them where you want
them, and right-click them to lock them there. Locked, clicks go through them. They hang from an
anchor picked by where you drop them: in the top half of the screen they hang from the top and
grow down; in the bottom half they hang from the bottom and grow up. The left, middle or right
third decides which side the lines line up on. You can also pick one of the six anchors in the
settings, which moves the stats to that edge of the screen.

## Minimap button, addon compartment and data bars

Hover for the UI's cost right now: frame rate, addons' CPU, Lua memory, the five busiest addons and
the latest slow frame.

| Click | Action |
| --- | --- |
| Left-click | Open or close the window |
| Shift + left-click | Report in chat |
| Middle-click | Show or hide the on-screen stats |
| Right-click | Settings |
| Drag | Move the button (unless locked) |

The same popup and clicks are in the minimap's addon compartment, and on data bars (ElvUI, Titan
Panel, ChocolateBar...) when one of them has loaded LibDataBroker. Nothing is bundled for that.

## Chat commands

| Command | Action |
| --- | --- |
| `/lad` | Open or close the window |
| `/lad report` | A summary in chat: busiest addons, slow frames, fast-growing memory |
| `/lad log` | The slow frame log |
| `/lad spikes` | The latest 10 slow frames in chat |
| `/lad mark` | Count slow frames from now (again: back to since login) |
| `/lad stats` | Show or hide the on-screen stats |
| `/lad stats move` | Unlock the on-screen stats to drag them (right-click them, or `/lad stats lock`, to lock) |
| `/lad mem` | Scan memory now |
| `/lad config` | Settings |
| `/lad perf` | What this addon costs |
| `/lad debug` | Debug mode, and the errors the addon caught |
| `/lad reset` | Reset settings (the log is kept) |

`/laggy` works too. The game's **Key Bindings** have a **Laggy Addon Detector** section with
bindings for the window, the on-screen stats, Measure from now and the report. None are bound to
start with.

## Settings

Options → AddOns → Laggy Addon Detector, or right-click the minimap button.

| Section | Options |
| --- | --- |
| Measuring | Window refresh rate, memory scan interval, slow frame threshold (10, 50, 100 or 500 ms), CPU and memory growth thresholds, tinting |
| Slow frame log | Background watch, skip loading screens, a chat line per slow frame, how many to keep, clear |
| Report at login | Say nothing, only problems (default), or always |
| On-screen stats | Show, move, reset position, lock, background, layout, anchor, size, update rate, which items |
| Minimap and data bars | Minimap button, lock it, addon compartment entry, data bar feed |
| Window | Text size, reset size and position |
| Tools | Open, report, scan memory, the addon's own cost, debug mode, reset |

Settings are saved for your whole account.

## What it costs

| Situation | Work |
| --- | --- |
| Nothing open | One profiler read every 2 seconds (the slow frame watch). When a slow frame happened, one pass over the addons to find who made it. No garbage |
| Minimap popup open | The totals and the profiler's own top-5 ranking, once a second |
| On-screen stats on | A few cheap reads per update; the text is set only when it changes |
| Window open | CPU and slow frames for every addon, the sort column, and the other columns for visible rows only. A cell's text is set only when its number changes |
| Memory scan | Only while the window is open, never in combat, at the interval you pick. Each scan is timed, and a slow one makes the next wait longer |

`/lad perf` prints the addon's own CPU, memory, load time and the cost of its last sample and
memory scan.

## How the numbers work

- **CPU** comes from the game's addon profiler (`C_AddOnProfiler`), the same numbers the AddOns
  list shows. It's always on in retail and needs no console settings. It measures only addon code,
  never Blizzard's own interface, and starts over on every reload.
- **Slow frames** are the profiler's per-addon counts of frames over each threshold. The table and
  the summary count from the end of the login loading screen, so start-up work doesn't count as
  lag (it still shows in **Peak**).
- **The culprit of a slow frame** is the addon whose own count went up. When no single addon did,
  several shared the frame, and the log says so. The exact length is known when the addon's peak
  went up with it; otherwise the log shows the threshold it crossed.
- **Memory** comes from the game's per-addon memory count. Counting pauses the game for a moment,
  so it's done sparingly. **Lua memory** in the summary is the whole interface's, read for free.

## Installation

### CurseForge and Wago

Install it with the CurseForge app or the Wago app, or download it from
[CurseForge](https://www.curseforge.com/wow/addons/laggy-addon-detector) or
[Wago](https://addons.wago.io/addons/rN4rWwKD).

### Manual

1. Download `LaggyAddonDetector-<version>.zip` from the
   [latest release](https://github.com/powercover/LaggyAddonDetector/releases/latest) on GitHub.
2. Extract it into `World of Warcraft/_retail_/Interface/AddOns/`, so the `.toc` file ends up at
   `Interface/AddOns/LaggyAddonDetector/LaggyAddonDetector.toc`.
3. Restart the game and make sure **Laggy Addon Detector** is enabled in the AddOns list.

No other addons are required. Settings from 1.x carry over.

## Reporting issues

Open an issue at
[github.com/powercover/LaggyAddonDetector/issues](https://github.com/powercover/LaggyAddonDetector/issues)
with your game version (`/dump GetBuildInfo()`), the output of `/lad debug` and `/lad perf`, and
what you were doing when it happened.

## Development

Plain Lua, no libraries.

| File | Purpose |
| --- | --- |
| `Locales/Locales.lua` | The translation lookup (`ns.L`); language files register with it |
| `Utils.lua` | Error catching, formatting, fonts and flat widgets |
| `Profiler.lua` | The addon list, sampling, the measuring period, filtering and sorting |
| `Memory.lua` | Memory scans, growth and the Lua heap |
| `SpikeWatch.lua` | The background slow frame watch and its log |
| `Window.lua` | The main window: summary, table, detail pane, log |
| `Popup.lua` | Minimap button, popup, addon compartment and data bar feed |
| `Overlay.lua` | On-screen stats |
| `Settings.lua` | The options page |
| `Core.lua` | Saved settings, events, chat commands, key bindings, reports |
| `Bindings.xml` | Key bindings |
| `Icon.tga` | The icon, drawn by `tools/make_icon.py` |

### Tests

The tests run every file in Lua 5.1 (WoW's Lua) against a model of the game's API in
`tests/wow.lua`, and drive a whole session: login, slow frames in and out of combat, a boss fight,
a loading screen, memory scans, the window, popup, on-screen stats, every setting and every chat
command. They need Python 3 and [lupa](https://pypi.org/project/lupa/) (`pip install lupa`).

```sh
python tests/run.py
```

### Releases

Pushing a version tag runs `.github/workflows/release.yml`, which packages the addon with BigWigs'
packager (what goes in: `.pkgmeta`; release notes: `CHANGELOG.md`).

## License

Copyright © 2026 powercover. **All rights reserved.** Free to download and use, but not open
source. See [LICENSE](LICENSE).

World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard
Entertainment, Inc. This addon is not affiliated with or endorsed by Blizzard Entertainment.
