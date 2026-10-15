#!/usr/bin/env python3
"""Generates SpaceSweep's original app icon (Resources/AppIcon.icns + a 1024px PNG preview).

Design: a deep indigo-to-teal squircle, a bright sweeping arc, and a sparkle.
Requires Pillow. Run from the repository root: python3 scripts/make_icon.py
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersampling
S = SIZE * SS
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def squircle_mask(size, inset, radius_ratio=0.225):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = int((size - 2 * inset) * radius_ratio)
    d.rounded_rectangle([inset, inset, size - inset, size - inset], radius=r, fill=255)
    return mask


def gradient(size, top_left, bottom_right):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(0, size):
            t = (x + y) / (2 * size)
            px[x, y] = lerp(top_left, bottom_right, t)
    return img


def main():
    # Apple's icon grid: ~100px transparent margin at 1024.
    inset = int(100 / 1024 * S)
    base_small = gradient(256, (34, 211, 238), (88, 60, 230))
    base = base_small.resize((S, S), Image.BICUBIC)

    # Deep glow in the lower-right corner.
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([S * 0.35, S * 0.45, S * 1.25, S * 1.35], fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.08))
    violet = Image.new("RGB", (S, S), (126, 58, 242))
    base = Image.composite(violet, base, glow)

    # Soft highlight top-left.
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse([-S * 0.2, -S * 0.35, S * 0.75, S * 0.45], fill=90)
    hl = hl.filter(ImageFilter.GaussianBlur(S * 0.07))
    base = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), base, hl)

    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    art.paste(base, (0, 0), squircle_mask(S, inset))

    cx, cy = S * 0.5, S * 0.53
    radius = S * 0.255
    width = int(S * 0.072)

    # Faint full track.
    track = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(track).ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
                                  outline=(255, 255, 255, 60), width=width)
    art = Image.alpha_composite(art, track)

    # Bright sweep arc with a glow.
    arc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(arc).arc([cx - radius, cy - radius, cx + radius, cy + radius],
                            start=125, end=55, fill=(255, 255, 255, 255), width=width)
    arc_glow = arc.filter(ImageFilter.GaussianBlur(S * 0.02))
    art = Image.alpha_composite(art, arc_glow)
    art = Image.alpha_composite(art, arc)
    # Rounded caps.
    caps = ImageDraw.Draw(art)
    centre_radius = radius - width / 2  # PIL strokes arcs inward from the bounding box
    for angle in (125, 55):
        a = math.radians(angle)
        px, py = cx + centre_radius * math.cos(a), cy + centre_radius * math.sin(a)
        caps.ellipse([px - width / 2, py - width / 2, px + width / 2, py + width / 2], fill=(255, 255, 255, 255))

    # Sparkle (four-point star) at upper right.
    def star(draw, x, y, r, fill):
        k = r * 0.2
        pts = [(x, y - r), (x + k, y - k), (x + r, y), (x + k, y + k), (x, y + r), (x - k, y + k), (x - r, y), (x - k, y - k)]
        draw.polygon(pts, fill=fill)

    sparkle = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sparkle)
    star(sd, cx, cy - S * 0.01, S * 0.13, (255, 255, 255, 255))
    star(sd, cx + S * 0.105, cy - S * 0.115, S * 0.04, (255, 255, 255, 235))
    star(sd, cx, cy + radius - width * 0.2, S * 0.035, (255, 255, 255, 210))
    art = Image.alpha_composite(art, sparkle.filter(ImageFilter.GaussianBlur(S * 0.012)))
    art = Image.alpha_composite(art, sparkle)

    # Subtle inner border.
    border = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    r = int((S - 2 * inset) * 0.225)
    ImageDraw.Draw(border).rounded_rectangle([inset, inset, S - inset, S - inset], radius=r,
                                             outline=(255, 255, 255, 50), width=int(S * 0.004))
    art = Image.alpha_composite(art, border)

    # Drop shadow under the squircle.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sm = squircle_mask(S, inset).filter(ImageFilter.GaussianBlur(S * 0.018))
    shadow.paste((0, 0, 0, 90), (0, int(S * 0.012)), sm)
    final = Image.alpha_composite(shadow, art).resize((SIZE, SIZE), Image.LANCZOS)

    os.makedirs(OUT, exist_ok=True)
    final.save(os.path.join(OUT, "AppIcon-1024.png"))
    final.save(os.path.join(OUT, "AppIcon.icns"),
               sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("Wrote Resources/AppIcon.icns and Resources/AppIcon-1024.png")


if __name__ == "__main__":
    main()
