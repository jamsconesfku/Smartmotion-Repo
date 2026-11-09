#!/usr/bin/env python3
"""Make the phone home-screen icons from the dark-mode logo (navy tile, logo centred).
Run only when the logo changes:  python3 -I scripts/make_icons.py"""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent.parent / "dashboard" / "assets"
logo = Image.open(root / "logo-dark.png").convert("RGBA")

def tile(size, frac):
    bg = Image.new("RGBA", (size, size), (2, 2, 47, 255))   # brand navy, fully opaque (iOS needs no transparency)
    w = round(size * frac); h = round(w * logo.height / logo.width)
    bg.alpha_composite(logo.resize((w, h), Image.LANCZOS), ((size - w) // 2, (size - h) // 2))
    return bg.convert("RGB")

tile(180, 0.80).save(root / "apple-touch-icon.png", optimize=True)
tile(192, 0.80).save(root / "icon-192.png", optimize=True)
tile(512, 0.80).save(root / "icon-512.png", optimize=True)
tile(512, 0.58).save(root / "icon-maskable-512.png", optimize=True)   # extra margin: Android crops this one into a circle
print("icons written to", root)
