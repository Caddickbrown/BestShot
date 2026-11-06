#!/usr/bin/env python3
"""Draws BestShot's app icon: a photo on the light table, framed by the viewfinder's corners.

One drawing, three iOS appearances: the light table, the viewfinder for dark mode,
and a greyscale for tinted (iOS colours it by brightness). The Mac keeps the light one.

Run from apple/: python3 scripts/make-icon.py  (needs Pillow)
"""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path("BestShot/Assets.xcassets/AppIcon.appiconset")
S = 2048  # drawn large, scaled down

# The tokens in BestShot/Utilities/Theme.swift: table, paper, tile, ink, accent, and how heavy the print's shadow is.
LIGHT = dict(table=(239, 235, 225), paper=(251, 250, 246), tile=(221, 216, 204), ink=(20, 20, 20), sun=(200, 38, 29), shadow=70)
DARK = dict(table=(10, 10, 10), paper=(38, 37, 35), tile=(62, 60, 56), ink=(232, 230, 225), sun=(255, 90, 78), shadow=0)
TINTED = dict(table=(0, 0, 0), paper=(58, 58, 58), tile=(96, 96, 96), ink=(236, 236, 236), sun=(255, 255, 255), shadow=0)


def art(colours=LIGHT):
    table, paper, tile, ink, sun = (colours[k] for k in ("table", "paper", "tile", "ink", "sun"))
    im = Image.new("RGB", (S, S), table)
    # The print on the table, with a soft shadow.
    x0, y0, x1, y1 = 500, 560, 1548, 1488
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x0, y0 + 26, x1, y1 + 26), 26, fill=(20, 20, 20, colours["shadow"]))
    im.paste(shadow.filter(ImageFilter.GaussianBlur(34)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(34)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((x0, y0, x1, y1), 26, fill=paper)
    d.rectangle((x0 + 62, y0 + 62, x1 - 62, y1 - 62), fill=tile)
    # The picture: a hill and a sun, the one that's the best shot.
    d.polygon([(x0 + 62, y1 - 62), (x0 + 400, y0 + 400), (x0 + 640, y0 + 610), (x0 + 770, y0 + 500), (x1 - 62, y1 - 62)], fill=ink)
    d.ellipse((x1 - 370, y0 + 150, x1 - 190, y0 + 330), fill=sun)
    # The viewfinder's corners.
    a, b, t, l = 300, S - 300, 74, 300
    for cx, cy, sx, sy in ((a, a, 1, 1), (b, a, -1, 1), (a, b, 1, -1), (b, b, -1, -1)):
        d.rectangle(sorted_box(cx, cy, cx + sx * l, cy + sy * t), fill=ink)
        d.rectangle(sorted_box(cx, cy, cx + sx * t, cy + sy * l), fill=ink)
    return im


def sorted_box(xa, ya, xb, yb):
    return (min(xa, xb), min(ya, yb), max(xa, xb), max(ya, yb))


def mac(im):
    """The Mac's icon sits inside its grid on a rounded square, and keeps its transparency."""
    side, pad = 1648, 200
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side - 1, side - 1), 370, fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (pad, pad + 22), mask)
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    out.paste(im.resize((side, side), Image.LANCZOS), (pad, pad), mask)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    im = art()
    im.resize((1024, 1024), Image.LANCZOS).save(OUT / "icon-1024.png")
    art(DARK).resize((1024, 1024), Image.LANCZOS).save(OUT / "icon-1024-dark.png")
    art(TINTED).resize((1024, 1024), Image.LANCZOS).save(OUT / "icon-1024-tinted.png")
    ios = {"idiom": "universal", "platform": "ios", "size": "1024x1024"}
    images = [
        {"filename": "icon-1024.png", **ios},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "icon-1024-dark.png", **ios},
        {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "icon-1024-tinted.png", **ios},
    ]
    m = mac(im)
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"mac-{px}.png"
            m.resize((px, px), Image.LANCZOS).save(OUT / name)
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    (OUT / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (OUT.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


main()
