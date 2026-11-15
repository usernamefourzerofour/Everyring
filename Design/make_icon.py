"""Draws the Everyring app icon as a 1024x1024 PNG without transparency.

Three concentric rings in Everyring's own palette (not Apple's Activity colours) on a warm light background. Each ring
starts at a different angle: every ring has its own period.

    python3 Design/make_icon.py Everyring/Assets.xcassets/AppIcon.appiconset/icon.png
    python3 Design/make_icon.py EveryringWatch/Assets.xcassets/AppIcon.appiconset/icon.png --watch
"""
import math
import sys

from PIL import Image, ImageDraw

N, SS = 1024, 4
W = N * SS


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


# (start colour, end colour, start angle in degrees from 12 o'clock, fraction of a lap)
RINGS = [
    (hex_rgb("#FF7A45"), hex_rgb("#FFB86B"), 0, 0.80),    # Sunrise
    (hex_rgb("#6B4BEF"), hex_rgb("#A98CFF"), 125, 0.68),  # Violet
    (hex_rgb("#0B7F9E"), hex_rgb("#41C0D2"), 245, 0.74),  # Lagoon
]
BACKGROUND = (hex_rgb("#FFF7EE"), hex_rgb("#FFE2CB"))


def draw(watch=False):
    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    top, bottom = BACKGROUND
    for y in range(W):
        d.line([(0, y), (W, y)], fill=mix(top, bottom, y / (W - 1)))

    scale = 0.84 if watch else 1.0  # the watch masks the icon to a circle
    width = 84 * SS * scale
    gap = 28 * SS * scale
    outer = 356 * SS * scale
    cx = cy = W / 2

    for i, (c0, c1, start, frac) in enumerate(RINGS):
        r = outer - i * (width + gap)
        # Faint track.
        track = Image.new("L", (W, W), 0)
        ImageDraw.Draw(track).ellipse([cx - r - width / 2, cy - r - width / 2, cx + r + width / 2, cy + r + width / 2],
                                      outline=255, width=int(width))
        img.paste(Image.new("RGB", (W, W), c1), (0, 0), track.point(lambda v: v * 0.14))
        # The arc: overlapping discs along the path give a gradient with round caps.
        steps = 1400
        for s in range(steps + 1):
            t = s / steps
            a = math.radians(start + 360 * frac * t)
            x, y = cx + r * math.sin(a), cy - r * math.cos(a)
            d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=mix(c0, c1, t))
    return img.resize((N, N), Image.LANCZOS)


if __name__ == "__main__":
    draw(watch="--watch" in sys.argv).save(sys.argv[1])
