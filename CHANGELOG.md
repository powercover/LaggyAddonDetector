# Laggy Addon Detector 2.0.0

A rewrite, focused on finding stutter and on costing as little as possible itself.

- **Slow frames and who caused them.** The profiler's per-addon counts of frames over 10, 50, 100
  or 500 ms, shown in the table and logged in the background: each stutter with the addon behind
  it, its length, the zone or key level, the boss, and whether you were in combat. The log is kept
  across reloads.
- **A new window.** A summary of frame rate, addons' share of each frame, Lua memory and slow
  frames; a sortable, searchable, resizable table with columns you choose; a detail pane with
  every figure and a slow-frame histogram for one addon; "Disable after reload" to test without
  it.
- **Memory growth instead of memory size.** A big addon that sits still is no longer flagged. What
  stutters is memory that grows fast, so that's what is shown and checked.
- **Measure from now.** Count slow frames for a single pull or key.
- **On-screen stats (off by default).** Frame rate, latency, addons' CPU, Lua memory and slow frames
  on screen, one per line or all on one. Drag them anywhere and lock them: they grow down from a top
  anchor and up from a bottom one.
- **Settings page** in Options → AddOns: thresholds, refresh rates, the log, the login report, the
  on-screen stats, the minimap button, the addon compartment and a data bar feed.
- **Light by design.** With nothing open, the addon reads one number every two seconds and makes
  no garbage. The table reads only what it shows, memory is never scanned in combat, and each
  scan is timed and backs off when slow. `/lad perf` shows what it costs.
- No colours by "severity" any more: the only colour is a number over one of your thresholds, and
  that can be turned off.
- Key bindings, chat commands for everything, and caught errors in `/lad debug`.
- A new icon, and the AddOns list files the addon under **Performance**.
