#!/usr/bin/env python3
"""Build godot/assets/world/urban.png (v1.17.0): where the towns, buildings and roads are, over the whole
32,768 m world square, one pixel per 8 m (the same grid as landcover.png). From Ordnance Survey open data
(Open Government Licence v3.0, credit only):
  R  built-up area: OS Open Built Up Areas (towns and villages), feathered at the edge
  G  road surface: OS OpenMap Local roads at their real widths (the fraction of the 8 m pixel that is road)
  B  how built up: OS OpenMap Local building outlines, the share of the ground under roofs within about 40 m
  A  main road: 1 for A roads and motorways, so they get a darker, fresher tarmac
The ground shader uses it so towns look built up (streets, pavements, roofs and gardens, not open grass
fields), no 3D grass grows in them, and roads are drawn sharper than the 10 m satellite photo.
Needs: the OS downloads from build_uk_detail.py (~/ukdata/oml) and OS Open Built Up Areas (fetched here).
Run:   python3 scripts/build_urban.py   (a minute or two)
"""
import glob, json, os, subprocess, warnings, zipfile
import numpy as np
import fiona
from PIL import Image
from pyproj import Transformer
from rasterio import features
from rasterio.transform import from_origin
from scipy import ndimage
from shapely.geometry import shape
from shapely.ops import transform as sh_transform

warnings.filterwarnings("ignore", category=DeprecationWarning)
HERE = os.path.dirname(os.path.abspath(__file__))
WORLD = os.path.join(HERE, "..", "godot", "assets", "world")
DATA = os.path.expanduser("~/ukdata")
HALF, PX, SS = 16384.0, 4096, 4          # 8 m pixels, drawn at 2 m and averaged
wj = json.load(open(os.path.join(WORLD, "world.json")))
LOCAL = f"+proj=tmerc +lat_0={wj['origin_lat']} +lon_0={wj['origin_lon']} +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
to_osgb = Transformer.from_crs(LOCAL, "EPSG:27700", always_xy=True)
to_local = Transformer.from_crs("EPSG:27700", LOCAL, always_xy=True)
ROAD_W = {"Motorway": 24.0, "Primary Road": 11.0, "A Road": 9.5, "B Road": 7.5, "Minor Road": 6.0, "Local Road": 5.5,
          "Local Access Road": 4.0, "Restricted Local Access Road": 3.5, "Shared Use Carriageway": 4.0}


def fetch():
    g = glob.glob(os.path.join(DATA, "bua", "**", "*.gpkg"), recursive=True)
    if g:
        return g[0]
    z = os.path.join(DATA, "bua.zip")
    subprocess.run(["curl", "-sS", "-L", "-o", z, "https://api.os.uk/downloads/v1/products/BuiltUpAreas/downloads?area=GB&format=GeoPackage&redirect"], check=True)
    with zipfile.ZipFile(z) as zf:
        zf.extractall(os.path.join(DATA, "bua"))
    return glob.glob(os.path.join(DATA, "bua", "**", "*.gpkg"), recursive=True)[0]


def loc(g):
    return sh_transform(lambda x, y, z=None: to_local.transform(x, y), g)


def oml(name, bbox):
    f = glob.glob(os.path.join(DATA, "oml", "**", f"TL_{name}.shp"), recursive=True)[0]
    with fiona.open(f) as s:
        for r in s.filter(bbox=bbox):
            yield shape(r["geometry"]), r["properties"]


def raster(shapes_, n):
    if not shapes_:
        return np.zeros((n, n), np.uint8)
    return features.rasterize(shapes_, out_shape=(n, n), transform=from_origin(-HALF, HALF, 2 * HALF / n, 2 * HALF / n),
                              fill=0, dtype=np.uint8)


def down(a):
    return a.reshape(PX, SS, PX, SS).sum(axis=(1, 3), dtype=np.uint16).astype(np.float32) / (SS * SS)


def main():
    xs, ys = [], []
    for x in (-HALF - 200, HALF + 200):
        for y in (-HALF - 200, HALF + 200):
            e, n = to_osgb.transform(x, y)
            xs.append(e); ys.append(n)
    bbox = (min(xs), min(ys), max(xs), max(ys))
    gp = fetch()
    with fiona.open(gp, layer="os_open_built_up_areas") as s:
        bua = [(loc(shape(r["geometry"])), 1) for r in s.filter(bbox=bbox)]
    print("built-up areas:", len(bua))
    built = raster(bua, PX).astype(np.float32)
    built = ndimage.gaussian_filter(built, 1.5)          # a soft 10-20 m edge

    rd, main_rd = [], []
    for g, p in oml("Road", bbox):
        c = str(p.get("CLASSIFICA") or "")
        w = ROAD_W.get(c.split(",")[0], 4.0) * (1.8 if "Collapsed Dual" in c else 1.0)
        geom = loc(g).buffer(w / 2.0, cap_style=1)
        rd.append((geom, 1))
        if c.startswith(("A Road", "Motorway", "Primary Road")):
            main_rd.append((geom, 1))
    print("roads:", len(rd))
    road = down(raster(rd, PX * SS))
    mainr = ndimage.maximum_filter(down(raster(main_rd, PX * SS)), size=2)

    bl = [(loc(g), 1) for g, _ in oml("Building", bbox)]
    print("buildings:", len(bl))
    cover = down(raster(bl, PX * SS))
    dens = ndimage.gaussian_filter(cover, 2.5)           # share of the ground under roofs, about 40 m round
    dens = np.clip(dens / 0.35, 0, 1)                    # 35 % roofs = a town centre

    img = np.dstack([built, road, dens, (mainr > 0.2).astype(np.float32)])
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(WORLD, "urban.png"), optimize=True)
    print("urban.png: built-up %.1f%% of the map, roads %.1f%%" % (100 * (built > 0.5).mean(), 100 * road.mean()))
    cr = "Contains OS data © Crown copyright and database right 2026 (OS OpenMap Local, Open Government Licence v3.0)"
    cr2 = "Contains OS data © Crown copyright and database right 2026 (OS Open Built Up Areas, Open Government Licence v3.0)"
    if cr2 not in wj["credits"]:
        wj["credits"].append(cr2)
    json.dump(wj, open(os.path.join(WORLD, "world.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
