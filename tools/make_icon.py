"""Draws the addon's icon: Icon.tga (128x128, for the game), Listing/icon-400.png and
Listing/icon-512.png (for the CurseForge and Wago project pages), and optionally a preview sheet.
Run from the addon folder: python tools/make_icon.py [preview.png]

A round dial in neutral steel: a frame-time line that runs flat and jumps into one sharp spike,
amber at its base and red at its tip. Drawn at 16x and scaled down for clean edges."""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
S = 2048  # drawing size
OUT = 128
C = S / 2


def disc(draw, radius, fill):
    draw.ellipse((C - radius, C - radius, C + radius, C + radius), fill=fill)


def radial(size, inner, outer, radius):
    """A square whose colour runs from `inner` at the centre to `outer` at `radius` and beyond.
    Opaque all over, so scaling it up leaves no see-through fringe where it's masked to a disc."""
    image = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            d = min(1.0, math.hypot(x - size / 2 + 0.5, y - size / 2 + 0.5) / radius)
            t = d ** 1.6
            pixels[x, y] = tuple(round(inner[i] + (outer[i] - inner[i]) * t) for i in range(3)) + (255,)
    return image


def mask(radius):
    image = Image.new("L", (S, S), 0)
    ImageDraw.Draw(image).ellipse((C - radius, C - radius, C + radius, C + radius), fill=255)
    return image


def polyline(draw, points, width, color):
    draw.line(points, fill=color, width=width, joint="curve")
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=color)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def build():
    k = S / 512  # the design is laid out on 512
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)

    # Rim: a dark outer edge, a steel band, a thin highlight, then the dial.
    disc(draw, 256 * k, (14, 16, 20, 255))
    disc(draw, 250 * k, (92, 99, 110, 255))
    disc(draw, 236 * k, (150, 158, 170, 255))
    disc(draw, 231 * k, (58, 64, 74, 255))
    disc(draw, 224 * k, (10, 13, 18, 255))
    small = radial(256, (30, 40, 56), (12, 16, 23), 220 / 512 * 256)
    dial = small.resize((S, S), Image.BICUBIC)
    icon.paste(dial, (0, 0), mask(220 * k))

    # The graph, on its own layer, kept inside the dial.
    graph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = ImageDraw.Draw(graph)
    for y in (180, 256, 332):
        g.line([(40 * k, y * k), (472 * k, y * k)], fill=(44, 58, 78, 255), width=round(6 * k))
    for x in (180, 332):
        g.line([(x * k, 40 * k), (x * k, 472 * k)], fill=(34, 46, 62, 255), width=round(5 * k))

    base = 318
    line = [(30, base), (96, base), (122, base - 22), (148, base + 14), (176, base - 8), (206, base)]
    spike = [(206, base), (246, 104), (288, 404), (318, base - 20), (344, base)]
    tail = [(344, base), (384, base), (408, base - 14), (430, base), (482, base)]
    width = round(30 * k)
    calm = (150, 214, 255, 255)
    scale = lambda points: [(x * k, y * k) for x, y in points]
    polyline(g, scale(line), width, calm)
    polyline(g, scale(tail), width, calm)

    # The spike: amber at the baseline, red at the tip, drawn in short steps so the colour runs.
    amber, red = (255, 182, 59, 255), (255, 72, 56, 255)
    steps = []
    for (x1, y1), (x2, y2) in zip(spike, spike[1:]):
        for i in range(24):
            t1, t2 = i / 24, (i + 1) / 24
            steps.append(((x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1), (x1 + (x2 - x1) * t2, y1 + (y2 - y1) * t2)))
    for (x1, y1), (x2, y2) in steps:
        height = max(0.0, min(1.0, (base - (y1 + y2) / 2) / (base - 104)))
        color = lerp(amber, red, height ** 0.8)
        g.line([(x1 * k, y1 * k), (x2 * k, y2 * k)], fill=color, width=width)
        g.ellipse((x2 * k - width / 2, y2 * k - width / 2, x2 * k + width / 2, y2 * k + width / 2), fill=color)
    # The spike's tip: a bright point.
    tip = (246 * k, 104 * k)
    r = 22 * k
    g.ellipse((tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r), fill=(255, 236, 214, 255))

    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(graph, (0, 0), Image.composite(graph.getchannel("A"), Image.new("L", (S, S), 0), mask(214 * k)))
    icon = Image.alpha_composite(icon, clipped)

    # A soft top highlight on the rim, for a little depth.
    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shine).ellipse((C - 250 * k, C - 250 * k, C + 250 * k, C + 250 * k), outline=(255, 255, 255, 46), width=round(5 * k))
    shine.putalpha(Image.composite(shine.getchannel("A"), Image.new("L", (S, S), 0), Image.linear_gradient("L").rotate(180).resize((S, S))))
    return Image.alpha_composite(icon, shine)


def preview(icon, path):
    """The icon at the sizes the game shows it, on dark and light backgrounds."""
    sizes = [128, 64, 32, 20, 16]
    sheet = Image.new("RGBA", (sum(sizes) + 20 * (len(sizes) + 1), 2 * 128 + 60), (24, 24, 28, 255))
    ImageDraw.Draw(sheet).rectangle((0, 128 + 30, sheet.width, sheet.height), fill=(200, 200, 205, 255))
    x = 20
    for size in sizes:
        small = icon.resize((size, size), Image.LANCZOS)
        for row in (0, 1):
            y = 20 + row * (128 + 30) + (128 - size) // 2
            sheet.alpha_composite(small, (x, y))
        x += size + 20
    sheet.save(path)


if __name__ == "__main__":
    drawing = build()
    icon = drawing.resize((OUT, OUT), Image.LANCZOS)
    icon.save(ROOT / "Icon.tga")
    listing = ROOT / "Listing"
    listing.mkdir(exist_ok=True)
    for size in (400, 512):
        drawing.resize((size, size), Image.LANCZOS).save(listing / f"icon-{size}.png", optimize=True)
    if len(sys.argv) > 1:
        preview(icon, sys.argv[1])
    print("Icon.tga and Listing/icon-400.png, icon-512.png written")
