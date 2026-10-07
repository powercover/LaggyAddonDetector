"""Draws Listing/overview.png (2560 x 1440): a schematic of the addon with callouts saying what each
part shows. Other addons appear only as generic stand-ins (Nameplates, Auras...), never by name.
Run from the addon folder: python tools/make_overview.py

Everything is laid out in 2560 x 1440 coordinates and drawn at twice that, then scaled down."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
W, H, K = 2560, 1440, 2
FONTS = "C:/Windows/Fonts/"

BG = (13, 15, 19)
BODY = (16, 16, 20)
BAND = (24, 24, 28)
CELL = (30, 30, 34)
LINE = (62, 62, 70)
TEXT = (235, 235, 237)
DIM = (160, 160, 170)
FAINT = (112, 112, 122)
WARN = (255, 194, 71)
GOLD = (255, 209, 0)
CALM = (150, 214, 255)
BAR = (120, 120, 132)
STRIPE = (19, 19, 23)
SELECT = (40, 40, 46)

_fonts = {}


def font(size, weight="regular"):
    key = (size, weight)
    if key not in _fonts:
        name = {"regular": "segoeui.ttf", "semi": "seguisb.ttf", "bold": "segoeuib.ttf"}[weight]
        _fonts[key] = ImageFont.truetype(FONTS + name, size * K)
    return _fonts[key]


def s(*values):
    return [round(v * K) for v in values]


class Canvas:
    def __init__(self):
        self.image = Image.new("RGB", (W * K, H * K), BG)
        self.draw = ImageDraw.Draw(self.image)

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=1, radius=0):
        if radius:
            self.draw.rounded_rectangle(s(x0, y0, x1, y1), radius * K, fill=fill, outline=outline, width=width * K)
        else:
            self.draw.rectangle(s(x0, y0, x1, y1), fill=fill, outline=outline, width=width * K)

    def line(self, points, color, width=1):
        self.draw.line([tuple(s(x, y)) for x, y in points], fill=color, width=round(width * K))

    def text(self, x, y, value, size, color=TEXT, weight="regular", anchor="la"):
        self.draw.text(tuple(s(x, y)), value, font=font(size, weight), fill=color, anchor=anchor)

    def width(self, value, size, weight="regular"):
        return self.draw.textlength(value, font=font(size, weight)) / K

    def circle(self, x, y, r, fill=None, outline=None, width=1):
        self.draw.ellipse(s(x - r, y - r, x + r, y + r), fill=fill, outline=outline, width=width * K)

    def paste(self, image, x, y):
        self.image.paste(image, tuple(s(x, y)), image)

    def wrap(self, value, size, width, weight="regular"):
        lines, current = [], ""
        for word in value.split():
            trial = (current + " " + word).strip()
            if self.width(trial, size, weight) <= width:
                current = trial
            else:
                lines.append(current)
                current = word
        if current:
            lines.append(current)
        return lines


c = Canvas()

# --- callouts -----------------------------------------------------------------------------------


def badge(x, y, number, r=15):
    c.circle(x, y, r, fill=CALM)
    c.text(x, y + 1, str(number), 17, (12, 24, 36), "bold", "mm")


def outline(x0, y0, x1, y1):
    """A thin ring around the values a callout is about."""
    c.rect(x0, y0, x1, y1, outline=CALM, width=2, radius=5)


def callout(number, box, title, body, target, side=None, mark=None):
    """A tooltip-style box with a numbered badge, joined by a leader line to `target`. The far badge
    goes at `mark` (a margin next to the part), or at the leader's end."""
    x0, y0, x1, y1 = box
    tx, ty = target
    # The leader leaves the box from the side facing the target.
    if side is None:
        side = "right" if tx > x1 else ("left" if tx < x0 else ("bottom" if ty > y1 else "top"))
    sx, sy = {
        "right": (x1, min(max(ty, y0 + 24), y1 - 24)),
        "left": (x0, min(max(ty, y0 + 24), y1 - 24)),
        "bottom": (min(max(tx, x0 + 24), x1 - 24), y1),
        "top": (min(max(tx, x0 + 24), x1 - 24), y0),
    }[side]
    c.line([(sx, sy), (tx, ty)], (96, 140, 170), 2)
    c.circle(sx, sy, 4, fill=CALM)
    c.rect(x0, y0, x1, y1, fill=(18, 20, 26), outline=(70, 78, 92), width=1, radius=6)
    badge(x0 + 26, y0 + 28, number)
    c.text(x0 + 50, y0 + 15, title, 21, GOLD, "semi")
    y = y0 + 50
    for line in c.wrap(body, 17, x1 - x0 - 36):
        c.text(x0 + 18, y, line, 17, (214, 216, 222))
        y += 25
    badge(*(mark or target), number, 13)


# --- title --------------------------------------------------------------------------------------

icon = Image.open(ROOT / "Listing" / "icon-512.png").convert("RGBA").resize((92 * K, 92 * K), Image.LANCZOS)
c.paste(icon, 48, 34)
c.text(156, 36, "Laggy Addon Detector", 50, TEXT, "semi")
c.text(158, 100, "What each part shows. Find the addon behind the stutter; it costs next to nothing while it watches.", 23, DIM)

# --- the main window ----------------------------------------------------------------------------

X0, Y0, X1, Y1 = 560, 176, 1800, 976
c.rect(X0 - 6, Y0 - 6, X1 + 6, Y1 + 6, fill=(8, 9, 11))
c.rect(X0, Y0, X1, Y1, fill=BODY, outline=LINE)
c.rect(X0 + 1, Y0 + 1, X1 - 1, Y0 + 50, fill=BAND)
c.line([(X0, Y0 + 51), (X1, Y0 + 51)], LINE)
c.paste(icon.resize((30 * K, 30 * K), Image.LANCZOS), X0 + 16, Y0 + 11)
c.text(X0 + 56, Y0 + 13, "Laggy Addon Detector", 21, TEXT, "semi")
tab_x = X0 + 56 + c.width("Laggy Addon Detector", 21, "semi") + 34
c.text(tab_x, Y0 + 15, "Addons", 18, TEXT)
c.rect(tab_x - 4, Y0 + 46, tab_x + c.width("Addons", 18) + 4, Y0 + 49, fill=TEXT)
c.text(tab_x + c.width("Addons", 18) + 30, Y0 + 15, "Slow frame log", 18, DIM)
c.rect(X1 - 150, Y0 + 12, X1 - 52, Y0 + 40, fill=CELL, outline=LINE)
c.text(X1 - 101, Y0 + 26, "Settings", 16, TEXT, anchor="mm")
c.line([(X1 - 34, Y0 + 17), (X1 - 18, Y0 + 33)], DIM, 2)
c.line([(X1 - 34, Y0 + 33), (X1 - 18, Y0 + 17)], DIM, 2)

# Summary strip.
PAD = 16
SY0, SY1 = Y0 + 64, Y0 + 162
cell_w = (X1 - X0 - PAD * 2 - 36) / 4
summary = [
    ("Frame rate", "118 fps", "8.5 ms a frame", TEXT),
    ("Addons' CPU a frame", "1.42 ms", "17% of each frame", TEXT),
    ("Lua memory", "312 MB", "+420 KB/s growth", TEXT),
    ("Frames over 50 ms", "7", "since login, last: Nameplates", WARN),
]
for i, (label, value, sub, color) in enumerate(summary):
    cx = X0 + PAD + i * (cell_w + 12)
    c.rect(cx, SY0, cx + cell_w, SY1, fill=BAND)
    c.text(cx + 14, SY0 + 10, label, 16, DIM)
    c.text(cx + 14, SY0 + 32, value, 30, color, "semi")
    c.text(cx + 14, SY0 + 72, sub, 16, DIM)

# Toolbar.
TY0, TY1 = SY1 + 14, SY1 + 52
c.rect(X0 + PAD, TY0, X0 + PAD + 270, TY1, fill=CELL, outline=LINE)
c.circle(X0 + PAD + 18, TY0 + 18, 7, outline=DIM, width=2)
c.line([(X0 + PAD + 23, TY0 + 23), (X0 + PAD + 29, TY0 + 29)], DIM, 2)
c.text(X0 + PAD + 40, TY0 + 8, "Search addons", 16, FAINT)
cbx = X0 + PAD + 290
c.rect(cbx, TY0 + 10, cbx + 18, TY0 + 28, fill=CELL, outline=LINE)
c.text(cbx + 28, TY0 + 8, "Only problems", 16, TEXT)
bx = X1 - PAD
for label in ("Report", "Scan memory", "Measure from now"):
    w = c.width(label, 16) + 28
    c.rect(bx - w, TY0, bx, TY1, fill=CELL, outline=LINE)
    c.text(bx - w / 2, TY0 + 19, label, 16, TEXT, anchor="mm")
    bx -= w + 10

# Table.
HY0 = TY1 + 12
ROW = 33
cols = [("Addon", None), ("Now", 100), ("Share", 124), ("Average", 104), ("Peak", 96), (">50 ms", 92), ("Memory", 112), ("Growth", 124)]
list_x0, list_x1 = X0 + PAD, X1 - PAD - 12
fixed = sum(w for _, w in cols if w)
name_w = list_x1 - list_x0 - fixed
xs, x = [], list_x0
for label, w in cols:
    width = w or name_w
    xs.append((x, width))
    x += width
c.rect(list_x0, HY0, list_x1, HY0 + ROW, fill=BAND)
for (label, _), (cx, cw) in zip(cols, xs):
    color = TEXT if label == "Now" else DIM
    if label == "Addon":
        c.text(cx + 8, HY0 + 7, label, 16, color)
    else:
        c.text(cx + cw - 8, HY0 + 7, label, 16, color, anchor="ra")
# The sort chevron on Now.
nx, nw = xs[1]
chev = nx + nw - 8 - c.width("Now", 16) - 14
c.line([(chev - 5, HY0 + 14), (chev, HY0 + 20), (chev + 5, HY0 + 14)], TEXT, 2)

rows = [
    # name, now, share, avg, peak, slow, memory, growth, warn flags
    ("Nameplates", "1.21 ms", 14, "0.98 ms", "112 ms", "3", "38.4 MB", "+210 KB/s", {"now", "slow"}),
    ("Auras", "0.33 ms", 4.0, "0.29 ms", "64.0 ms", "2", "61.2 MB", "+340 KB/s", {"slow", "growth"}),
    ("Damage meter", "0.18 ms", 2.1, "0.15 ms", "71.0 ms", "1", "24.8 MB", "+60 KB/s", {"slow"}),
    ("Boss timers", "0.09 ms", 1.1, "0.06 ms", "22.0 ms", "0", "11.3 MB", "+12 KB/s", set()),
    ("Bags", "0.05 ms", 0.6, "0.04 ms", "18.0 ms", "0", "9.6 MB", "+4 KB/s", set()),
    ("Unit frames", "0.04 ms", 0.5, "0.05 ms", "14.0 ms", "0", "7.1 MB", "+3 KB/s", set()),
    ("Collections database", "0.01 ms", 0.1, "0.02 ms", "9.00 ms", "0", "182 MB", "0 KB/s", set()),
    ("Laggy Addon Detector", "0.01 ms", 0.1, "0.01 ms", "3.10 ms", "0", "1.2 MB", "+1 KB/s", set()),
]
row_y = {}
for i, (name, now, share, avg, peak, slow, mem, growth, warn) in enumerate(rows):
    ry = HY0 + ROW + i * ROW
    row_y[name] = ry
    if i == 0:
        c.rect(list_x0, ry, list_x1, ry + ROW, fill=SELECT)
    elif i % 2 == 1:
        c.rect(list_x0, ry, list_x1, ry + ROW, fill=STRIPE)
    values = [name, now, None, avg, peak, slow, mem, growth]
    keys = ["name", "now", "share", "avg", "peak", "slow", "memory", "growth"]
    for key, value, (cx, cw) in zip(keys, values, xs):
        if key == "name":
            c.text(cx + 8, ry + 6, value, 17, TEXT)
            continue
        if key == "share":
            text = f"{share:.0f}%" if share >= 10 else f"{share:.1f}%"
            c.text(cx + cw - 8, ry + 6, text, 17, FAINT if share < 0.5 else TEXT, anchor="ra")
            bar_w = (cw - 16) * share / 100 * 3
            c.rect(cx + 8, ry + ROW - 6, cx + 8 + max(2, bar_w), ry + ROW - 4, fill=BAR)
            continue
        color = WARN if key in warn else (FAINT if value in ("0", "0 KB/s") or value.startswith("0.0") else TEXT)
        c.text(cx + cw - 8, ry + 6, value, 17, color, anchor="ra")
rows_bottom = HY0 + ROW + len(rows) * ROW
# Scroll bar.
c.rect(list_x1 + 6, HY0 + ROW, list_x1 + 12, rows_bottom, fill=CELL)
c.rect(list_x1 + 6, HY0 + ROW, list_x1 + 12, HY0 + ROW + 120, fill=LINE)

# Detail pane for the selected addon.
DY0, DY1 = rows_bottom + 10, Y1 - 38
c.rect(X0 + 1, DY0, X1 - 1, DY1, fill=BAND)
c.line([(X0, DY0), (X1, DY0)], LINE)
c.line([(X1 - 30, DY0 + 12), (X1 - 18, DY0 + 24)], DIM, 2)
c.line([(X1 - 30, DY0 + 24), (X1 - 18, DY0 + 12)], DIM, 2)
c.text(X0 + 20, DY0 + 14, "Nameplates", 21, TEXT, "semi")
c.text(X0 + 20, DY0 + 44, "version 2.4 · folder Nameplates", 15, FAINT)
pairs = [("CPU now", "1.21 ms"), ("Share of frame", "14%"), ("Average since reload", "0.98 ms"), ("Average in boss fights", "1.57 ms"),
         ("Last frame", "1.10 ms"), ("Peak frame", "112 ms"), ("Memory", "38.4 MB"), ("Growth", "+210 KB/s")]
half = 270
for i, (label, value) in enumerate(pairs):
    px = X0 + 20 + (i % 2) * (half + 30)
    py = DY0 + 76 + (i // 2) * 27
    c.text(px, py, label, 15, DIM)
    c.text(px + half, py, value, 16, TEXT, anchor="ra")
hx = X0 + 640
c.text(hx, DY0 + 14, "Frames this addon made slow, since login", 15, DIM)
hist = [(">1 ms", 812), (">5 ms", 96), (">10 ms", 31), (">50 ms", 3), (">100 ms", 1), (">500 ms", 0), (">1000 ms", 0)]
import math
for i, (label, value) in enumerate(hist):
    hy = DY0 + 40 + i * 21
    c.text(hx + 70, hy, label, 14, DIM, anchor="ra")
    c.rect(hx + 80, hy + 4, hx + 320, hy + 15, fill=CELL)
    if value:
        c.rect(hx + 80, hy + 4, hx + 80 + 240 * math.log10(value + 1) / math.log10(813), hy + 15, fill=BAR)
    c.text(hx + 370, hy, str(value), 14, TEXT if value else FAINT, anchor="ra")
for i, label in enumerate(("Disable after reload", "Put in chat")):
    by = DY0 + 44 + i * 42
    c.rect(hx + 400, by, X1 - 22, by + 30, fill=CELL, outline=LINE)
    c.text((hx + 400 + X1 - 22) / 2, by + 15, label, 15, TEXT, anchor="mm")

# Footer.
c.text(X0 + 26, Y1 - 29, "CPU every 1 s  ·  memory every 10 s (last scan 14 ms, 6s ago)  ·  42 addons  ·  this addon 0.01 ms", 15, FAINT)

# --- the slow frame log -------------------------------------------------------------------------

LX0, LY0, LX1 = 560, 1040, 1440
log_rows = [
    ("21:04:13", "Nameplates", "112 ms", "Raid (Mythic)", "Boss: final boss"),
    ("21:02:51", "Auras", "over 100 ms", "Raid (Mythic)", "In combat"),
    ("20:58:30", "Several addons together", "over 50 ms", "Capital city", "Out of combat"),
    ("20:41:07", "Damage meter", "71 ms", "Dungeon +12", "In combat"),
]
LY1 = LY0 + 50 + 36 + len(log_rows) * 34 + 14
c.rect(LX0 - 6, LY0 - 6, LX1 + 6, LY1 + 6, fill=(8, 9, 11))
c.rect(LX0, LY0, LX1, LY1, fill=BODY, outline=LINE)
c.rect(LX0 + 1, LY0 + 1, LX1 - 1, LY0 + 44, fill=BAND)
c.text(LX0 + 26, LY0 + 11, "Slow frame log", 19, TEXT, "semi")
c.text(LX0 + 26 + c.width("Slow frame log", 19, "semi") + 20, LY0 + 13, "Watching for frames over 50 ms. 4 logged.", 16, DIM)
lcols = [("Time", 110), ("Addon", 250), ("Frame", 130), ("Where", 190), ("State", 170)]
lx = LX0 + 16
c.rect(LX0 + 12, LY0 + 54, LX1 - 12, LY0 + 86, fill=BAND)
positions = []
for label, w in lcols:
    positions.append((lx, w))
    if label == "Frame":
        c.text(lx + w - 10, LY0 + 60, label, 15, DIM, anchor="ra")
    else:
        c.text(lx + 6, LY0 + 60, label, 15, DIM)
    lx += w
for i, row in enumerate(log_rows):
    ry = LY0 + 86 + i * 34
    if i % 2 == 1:
        c.rect(LX0 + 12, ry, LX1 - 12, ry + 34, fill=STRIPE)
    for j, (value, (px, w)) in enumerate(zip(row, positions)):
        color = FAINT if value == "Several addons together" else TEXT
        if j == 2:
            c.text(px + w - 10, ry + 7, value, 16, color, anchor="ra")
        else:
            c.text(px + 6, ry + 7, value, 16, color)

# --- on-screen stats ----------------------------------------------------------------------------

OX0, OY0, OX1, OY1 = 1880, 176, 2510, 336
c.rect(OX0, OY0, OX1, OY1, fill=(26, 34, 30), outline=(44, 54, 50), radius=8)
c.text(OX1 - 16, OY1 - 30, "your screen", 15, (88, 104, 96), anchor="ra")
stats = [("118 fps", TEXT), ("Latency 24 / 31 ms", TEXT), ("Addons 1.42 ms (17%)", TEXT), ("Slow frames 7 (Nameplates)", WARN)]
sw = max(c.width(t, 19, "semi") for t, _ in stats) + 24
STATS_BOTTOM = OY0 + 16 + len(stats) * 28 + 12
c.rect(OX0 + 18, OY0 + 16, OX0 + 18 + sw, STATS_BOTTOM, fill=(6, 8, 8))
for i, (value, color) in enumerate(stats):
    tx, ty = OX0 + 30, OY0 + 22 + i * 28
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        c.text(tx + dx * 0.8, ty + dy * 0.8, value, 19, (0, 0, 0), "semi")
    c.text(tx, ty, value, 19, color, "semi")

# --- minimap popup ------------------------------------------------------------------------------

PX0, PY0, PX1 = 1880, 830, 2330
LH = 22
popup = [
    ("Laggy Addon Detector", GOLD, "118 fps"),
    ("Addons: 1.42 ms a frame, 17% of frame time", TEXT, None),
    ("Lua memory: 312 MB, +420 KB/s", TEXT, None),
    ("", TEXT, None),
    ("Busiest right now", GOLD, None),
    ("Nameplates", TEXT, "1.21 ms"),
    ("Auras", TEXT, "0.33 ms"),
    ("Damage meter", TEXT, "0.18 ms"),
    ("Boss timers", TEXT, "0.09 ms"),
    ("Bags", TEXT, "0.05 ms"),
    ("", TEXT, None),
    ("Frames over 50 ms, since login", TEXT, "7"),
    ("Latest: Nameplates, 112 ms, 21:04:13", DIM, None),
    ("", TEXT, None),
    ("Click: window · Right-click: settings", FAINT, None),
    ("Shift-click: report · Middle-click: on-screen stats", FAINT, None),
]
PY1 = PY0 + 16 + len(popup) * LH + 10
c.rect(PX0, PY0, PX1, PY1, fill=(8, 10, 22), outline=(96, 100, 120), radius=4)
for i, (left, color, right) in enumerate(popup):
    py = PY0 + 12 + i * LH
    if not left:
        continue
    c.text(PX0 + 14, py, left, 16 if color != GOLD else 17, color, "semi" if color == GOLD else "regular")
    if right:
        rcolor = WARN if right in ("1.21 ms", "7") else TEXT
        c.text(PX1 - 14, py, right, 16, rcolor, anchor="ra")
# The minimap button it belongs to.
mini = icon.resize((52 * K, 52 * K), Image.LANCZOS)
c.circle(2440, 900, 60, fill=(30, 38, 34), outline=(60, 70, 64), width=2)
c.paste(mini, 2440 - 26 + 30, 900 - 26 - 30)
c.text(2440, 980, "minimap", 15, (88, 104, 96), anchor="mm")

# --- callouts -----------------------------------------------------------------------------------

LEFT = (40, 500)
callout(1, (LEFT[0], 176, LEFT[1], 320), "The summary",
        "Frame rate, all addons' CPU per frame and their share of it, total Lua memory and how fast it grows, and slow frames since login.",
        (X0, SY0 + 49))
callout(2, (LEFT[0], 336, LEFT[1], 480), "Search and tools",
        "Find an addon, show only problems, measure from now for a single pull or key, scan memory, report in chat.",
        (X0, (TY0 + TY1) / 2))
callout(3, (LEFT[0], 496, LEFT[1], 668), "Every addon, sortable",
        "CPU now and its share of the frame, average since reload, peak frame, slow frames, memory and growth. Right-click the header to pick columns.",
        (X0, row_y["Boss timers"] + 16))
callout(5, (LEFT[0], 684, LEFT[1], 850), "One addon in full",
        "Click a row: every figure, a histogram of its frames from over 1 ms to over 1 s, and Disable after reload to test without it.",
        (X0, DY0 + 70))
callout(6, (LEFT[0], 866, LEFT[1], 1000), "What it costs",
        "How often it samples and what the addon itself costs. Memory is never scanned in combat.",
        (X0, Y1 - 20))
callout(7, (LEFT[0], 1016, LEFT[1], 1190), "The slow frame log",
        "Every stutter, caught in the background: the addon behind it, how long it took, where, and whether it was a boss fight. Kept across reloads.",
        (LX0, LY0 + 22))

# Right of the window: the values themselves, ringed.
gx, gw = xs[7]
ay = row_y["Auras"]
outline(gx + 14, ay + 3, gx + gw - 2, ay + ROW - 3)
callout(4, (1860, 468, 2510, 588), "Amber = over your line",
        "The only colour the addon uses: a number over one of your thresholds (busy CPU, slow frames, fast growth). It can be turned off.",
        (gx + gw - 2, ay + ROW / 2), mark=(X1, ay + ROW / 2))
mx, _ = xs[6]
cy = row_y["Collections database"]
outline(mx + 30, cy + 3, gx + gw - 2, cy + ROW - 3)
callout(8, (1860, 604, 2510, 724), "Size isn't lag, growth is",
        "182 MB that sits still costs nothing. Memory that grows fast makes the garbage collector run, and that stutters.",
        (gx + gw - 2, cy + ROW / 2), mark=(X1, cy + ROW / 2))

callout(9, (OX0, OY1 + 10, OX1, OY1 + 120), "On-screen stats (optional)",
        "Drag anywhere, right-click to lock. They grow down from the top, up from the bottom.",
        (OX0 + 18 + sw / 2, STATS_BOTTOM + 14), side="top")
callout(10, (PX0, PY1 + 16, OX1, PY1 + 146), "The minimap popup",
        "Hover the button: the busiest addons right now and the latest slow frame. The same in the addon compartment and on data bars.",
        (PX0 + 225, PY1 + 2), side="top")

c.text(LX0, LY1 + 50, "No libraries · no class or spec theming · free on CurseForge and Wago", 18, FAINT)

out = c.image.resize((W, H), Image.LANCZOS)
(ROOT / "Listing").mkdir(exist_ok=True)
out.save(ROOT / "Listing" / "overview.png", optimize=True)
print("Listing/overview.png written")
