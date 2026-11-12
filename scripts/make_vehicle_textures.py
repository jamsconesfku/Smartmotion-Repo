#!/usr/bin/env python3
"""Make the vehicle surface textures (v1.17.0) in godot/assets/textures/veh_*:
  - from ambientCG (CC0, public domain; https://ambientcg.com): Fabric004 (carbon fibre), Metal009 (brushed),
    Metal038 (scratched steel), Rubber004 (tyres), Leather026 (seats), PaintedMetal004 (gloss changes),
    each as _col, _nrm (OpenGL) and _rgh at 512 x 512
  - veh_panels_nrm.png: aircraft / spaceship panel seams and rivets, drawn here (1024 px = 2.4 m)
Run: python3 scripts/make_vehicle_textures.py   (needs network access to ambientcg.com and
     acg-download.struffelproductions.com; numpy, pillow, requests)
"""
import io, os, zipfile
import numpy as np
import requests
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "textures")
NAMES = {"Fabric004": "carbon", "Metal009": "brushed", "Metal038": "steel", "Rubber004": "rubber",
         "Leather026": "leather", "PaintedMetal004": "chipped"}


def ambientcg():
    for a, n in NAMES.items():
        z = zipfile.ZipFile(io.BytesIO(requests.get(f"https://ambientcg.com/get?file={a}_1K-JPG.zip", timeout=120).content))
        for part, suf in [("Color", "col"), ("NormalGL", "nrm"), ("Roughness", "rgh")]:
            f = [x for x in z.namelist() if x.endswith(part + ".jpg")][0]
            im = Image.open(io.BytesIO(z.read(f))).convert("L" if suf == "rgh" else "RGB").resize((512, 512), Image.LANCZOS)
            im.save(os.path.join(OUT, f"veh_{n}_{suf}.jpg"), quality=90)


def panels():
    n = 1024
    h = np.zeros((n, n), np.float32)
    rows = [0, 384, 640, 1024]
    cols = [[0, 300, 620], [140, 460, 800], [0, 256, 560, 880]]
    yy, xx = np.mgrid[-2:3, -2:3]
    r2 = yy * yy + xx * xx
    dome = np.where(r2 <= 5, 0.55 * (1 - r2 / 6), 0)

    def rivet(cx, cy):
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                k = ((cy + dy) % n, (cx + dx) % n)
                h[k] = max(h[k], dome[dy + 2, dx + 2])
    for ri in range(3):
        y0, y1 = rows[ri], rows[ri + 1]
        for w, d in [(-1, 0.55), (0, 1.0), (1, 0.55)]:
            h[(y0 + w) % n, :] = np.minimum(h[(y0 + w) % n, :], -d)
        for cx in cols[ri]:
            for w, d in [(-1, 0.55), (0, 1.0), (1, 0.55)]:
                h[y0:y1, (cx + w) % n] = np.minimum(h[y0:y1, (cx + w) % n], -d)
        for x in range(6, n, 22):
            for oy in (7, -7):
                rivet(x, y0 + oy)
        for cx in cols[ri]:
            for y in range(y0 + 10, y1 - 6, 22):
                rivet(cx + 7, y)
    dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    v = np.dstack([-dx * 1.6, dy * 1.6, np.ones_like(h)])
    v /= np.linalg.norm(v, axis=2, keepdims=True)
    Image.fromarray(((v * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "veh_panels_nrm.png"))


if __name__ == "__main__":
    ambientcg()
    panels()
    print("done")
