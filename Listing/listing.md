# Laggy Addon Detector on CurseForge and Wago

What goes on each project page. The description is the same Markdown on both:
[description.md](description.md). Nothing in this folder ships with the addon.

| Field | Value |
| --- | --- |
| Name | Laggy Addon Detector |
| CurseForge | [laggy-addon-detector](https://www.curseforge.com/wow/addons/laggy-addon-detector), project ID 1697012 |
| Wago | [rN4rWwKD](https://addons.wago.io/addons/rN4rWwKD) |
| Summary (141 characters) | Finds the addon behind lag and stutter: live CPU per addon, slow frames logged with the culprit, memory growth, and optional on-screen stats. |
| Short summary, if a field is shorter (99 characters) | Find the addon behind the stutter: live CPU per addon, slow frames with the culprit, memory growth. |
| Description | [description.md](description.md), as Markdown |
| Logo | [icon-400.png](icon-400.png) (CurseForge asks for 400 x 400), or [icon-512.png](icon-512.png) |
| License | All Rights Reserved |
| Game | World of Warcraft, Retail only (12.1.0 and 12.1.5, Midnight) |
| Source code | `https://github.com/powercover/LaggyAddonDetector` |
| Issues | `https://github.com/powercover/LaggyAddonDetector/issues` |

## Images

Upload to each project's image gallery, then put its address in description.md in place of the
placeholder.

| Placeholder | Image |
| --- | --- |
| `IMAGE_OVERVIEW` | [overview.png](overview.png) (2560 x 1440): the window, the slow frame log, the minimap popup and the on-screen stats, each part labelled. Other addons appear only as generic stand-ins |

## Regenerating

From the addon folder:

- `python tools/make_icon.py`: `Icon.tga` for the game, and `icon-400.png`, `icon-512.png` here.
- `python tools/make_overview.py`: `overview.png`, after the UI changes.
