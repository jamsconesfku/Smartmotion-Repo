#!/usr/bin/env python3
"""Make godot/assets/world/roofmask.png from buildings.bin: where the real buildings stand, one pixel per
8 m over the 32,768 m square (the same grid as landcover.png), widened by one pixel. The ground shader uses it
to paint over the blurry roofs in the satellite photo near the 3D buildings, so a roof isn't seen twice
(once as the building and once as a grey smudge on the ground beside it).
Run: python3 -I scripts/build_roof_mask.py   (a few seconds; needs numpy and pillow)
"""
import os, struct
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
WORLD = os.path.join(HERE, "..", "godot", "assets", "world")
HALF, PX = 16384.0, 4096
M = PX / (2 * HALF)            # pixels per metre
SS = 2                         # draw at twice the size, then shrink: soft edges

data = open(os.path.join(WORLD, "buildings.bin"), "rb").read()
n = struct.unpack_from("<I", data, 0)[0]
o = 4
img = Image.new("L", (PX * SS, PX * SS), 0)
d = ImageDraw.Draw(img)
for _ in range(n):
    nv, kind, h = struct.unpack_from("<BBH", data, o)
    o += 4
    xs = struct.unpack_from("<%di" % (2 * nv), data, o)
    o += 8 * nv
    pts = [((xs[2 * i] / 4.0 + HALF) * M * SS, (xs[2 * i + 1] / 4.0 + HALF) * M * SS) for i in range(nv)]
    d.polygon(pts, fill=255)
img = img.filter(ImageFilter.MaxFilter(3)).resize((PX, PX), Image.BILINEAR).filter(ImageFilter.MaxFilter(3))
img.save(os.path.join(WORLD, "roofmask.png"), optimize=True)
print("roofmask.png: %d buildings, %d x %d" % (n, PX, PX))
