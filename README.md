# Laggy Addon Detector

Bored of hunting which addon is causing lag spikes every time something got updated?

You reload, the game stutters, and now you are disabling addons one by one hoping to find the culprit. **Laggy Addon Detector** does that work for you. It watches CPU and memory in real time, flags the addons that are actually draining resources, and shows you the results the moment you log in or reload.

## What it does

- Scans all loaded addons live, not just once
- Prints a short chat report after each login or `/reload`
- Colors addon names by load:
  - **Red** — heavy, likely causing hitching
  - **Yellow** — average
  - **Green** — lightweight and fine
- Minimap button tints itself to the worst current load
- Mouseover the minimap button to see only the red, resource-draining addons
- Click it for a full sortable table of every loaded addon

## How to use

1. Log in (or `/reload`).
2. Hover the clock icon on the minimap. Any addon draining CPU or memory shows up in red.
3. Click the icon to open the usage table.
4. Click a column header to sort by **name**, **CPU**, **peak**, **memory**, or overall **load**.
5. Drag the minimap button if you want it somewhere else.

Slash commands:

| Command | Action |
| --- | --- |
| `/lad` or `/laggy` | Toggle the usage table |
| `/lad report` | Print a chat summary right now |

There is also a **Chat report** button in the top-left of the table.

## How to read the numbers

CPU is milliseconds per frame. Memory is KB/MB.

- Green: under **0.40 ms** CPU and under **10 MB**
- Yellow: under **1.50 ms** CPU and under **40 MB**
- Red: **1.50 ms+** CPU or **40 MB+** memory

The table updates about once a second. Memory sampling pauses in combat so the detector itself does not hitch you.

On retail, CPU tracking uses Blizzard's always-on addon profiler. No extra console CVars needed.

## Requirements

- World of Warcraft **12.1.0** and **12.1.5**
- Author: **powercover**
