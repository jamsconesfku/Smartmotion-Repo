#!/usr/bin/env python3
"""Build the real-world data for the native SmartMotion Flight game (godot/assets/world/).

A 32,768 m square centred on the middle of Duxford's hard runway, from free open data:
  - elevation: Copernicus DEM GLO-30 (AWS open data)             -> height.bin  (1024x1024 int16, cm above -100 m)
  - ground photo: Copernicus Sentinel-2 L2A, one clear summer day -> ortho.jpg   (4096x4096, about 8 m a pixel)
  - land cover: ESA WorldCover 2021 (10 m)                        -> landcover.png (RGBA: trees, built-up, water, grass)
  - buildings: Overture Maps (OpenStreetMap and others)            -> buildings.bin
  - runway position/heading from Overture (OpenStreetMap)          -> world.json
Needs: pip install rasterio pyproj numpy pillow duckdb requests
Run:   python3 scripts/build_world_data.py   (takes a few minutes; downloads only the parts it needs)
"""
import json, math, os, struct, sys
import numpy as np
import rasterio
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from pyproj import Transformer
from PIL import Image
import requests

OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "world")
HALF = 16384.0
RUNWAY = ((0.1225235, 52.0870817), (0.1404524, 52.0939728))   # Overture/OSM hard runway centreline ends (06 -> 24)
GRASS = ((0.1242068, 52.0892948), (0.1350651, 52.0934957))
OVERTURE = "s3://overturemaps-us-west-2/release/2026-10-21.0"

os.makedirs(OUT, exist_ok=True)
lon0 = (RUNWAY[0][0] + RUNWAY[1][0]) / 2
lat0 = (RUNWAY[0][1] + RUNWAY[1][1]) / 2
LOCAL = f"+proj=tmerc +lat_0={lat0} +lon_0={lon0} +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
to_local = Transformer.from_crs("EPSG:4326", LOCAL, always_xy=True)
to_ll = Transformer.from_crs(LOCAL, "EPSG:4326", always_xy=True)


def grid(n, centred=False):
    # north-up raster covering the square; row 0 is the north edge (game z = -HALF).
    # centred=True puts sample i exactly at -HALF + i*cell (how the game reads heights), not at the pixel middle
    c = 2 * HALF / n
    o = c / 2 if centred else 0.0
    return from_origin(-HALF - o, HALF + o, c, c)


def bbox_ll(pad=0.0):
    xs, ys = [], []
    for x in (-HALF - pad, HALF + pad):
        for y in (-HALF - pad, HALF + pad):
            lo, la = to_ll.transform(x, y)
            xs.append(lo); ys.append(la)
    return min(xs), min(ys), max(xs), max(ys)


def warp(srcs, n, resampling, dtype=np.float32, band=1, nodata=None, centred=False):
    dst = np.full((n, n), np.nan if dtype == np.float32 else 0, dtype=dtype)
    for url in srcs:
        with rasterio.open(url) as src:
            tmp = np.full((n, n), np.nan if dtype == np.float32 else 0, dtype=dtype)
            reproject(rasterio.band(src, band), tmp, dst_transform=grid(n, centred), dst_crs=LOCAL, resampling=resampling,
                      src_nodata=nodata if nodata is not None else src.nodata, dst_nodata=np.nan if dtype == np.float32 else 0)
            m = ~np.isnan(tmp) if dtype == np.float32 else tmp != 0
            if dtype == np.float32:
                m &= np.isnan(dst)
            else:
                m &= dst == 0
            dst[m] = tmp[m]
    return dst


def blur(a, sigma):
    r = int(sigma * 3)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    a = np.apply_along_axis(lambda v: np.convolve(np.pad(v, r, mode="edge"), k, "valid"), 0, a)
    return np.apply_along_axis(lambda v: np.convolve(np.pad(v, r, mode="edge"), k, "valid"), 1, a)


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ runway
ax, ay = to_local.transform(*RUNWAY[0])
bx, by = to_local.transform(*RUNWAY[1])
rw_len = math.hypot(bx - ax, by - ay)
rw_heading = math.degrees(math.atan2(bx - ax, by - ay)) % 360
gx0, gy0 = to_local.transform(*GRASS[0]); gx1, gy1 = to_local.transform(*GRASS[1])
print(f"runway {rw_len:.0f} m, true heading {rw_heading:.2f}, centre {lat0:.6f},{lon0:.6f}")
hd = math.radians(rw_heading)
rdir = np.array([math.sin(hd), -math.cos(hd)])      # game (x, z)
rperp = np.array([math.cos(hd), math.sin(hd)])


def runway_uv(x, z):
    return x * rdir[0] + z * rdir[1], x * rperp[0] + z * rperp[1]


# ------------------------------------------------------------------ elevation
N_H = 1024
lo_min, la_min, lo_max, la_max = bbox_ll(2000)
tiles = []
for la in range(math.floor(la_min), math.floor(la_max) + 1):
    for lo in range(math.floor(lo_min), math.floor(lo_max) + 1):
        ns = f"N{la:02d}" if la >= 0 else f"S{-la:02d}"
        ew = f"E{lo:03d}" if lo >= 0 else f"W{-lo:03d}"
        name = f"Copernicus_DSM_COG_10_{ns}_00_{ew}_00_DEM"
        tiles.append(f"https://copernicus-dem-30m.s3.amazonaws.com/{name}/{name}.tif")
print("DEM tiles", tiles)
h = warp(tiles, N_H, Resampling.bilinear, centred=True)
h = np.where(np.isnan(h), np.nanmean(h), h)
# the DEM is a surface model (it includes woods and roofs): smooth it so the ground isn't lumpy under trees
h = blur(h, 2.2)
cs = 2 * HALF / N_H
ii, jj = np.meshgrid(np.arange(N_H), np.arange(N_H))
X = -HALF + ii * cs
Z = -HALF + jj * cs
U, V = runway_uv(X, Z)
on_rw = (np.abs(U) < rw_len / 2) & (np.abs(V) < 30)
rw_elev = float(np.median(h[on_rw]))
# airfield: flat at the runway level, blending back into the real ground
du = np.maximum(np.abs(U) - rw_len / 2, 0)
dv = np.maximum(np.abs(V + 40) - 220, 0)
d = np.hypot(du, dv)
h = rw_elev + (h - rw_elev) * sstep(60, 500, d)
# the map repeats beyond the square: fade the edge to one height so there is no seam
r = np.maximum(np.abs(X), np.abs(Z))
h = h + (rw_elev + 8.0 - h) * sstep(HALF - 2500, HALF - 300, r)
print(f"runway elevation {rw_elev:.1f} m, terrain {h.min():.0f}..{h.max():.0f} m")
# game row j is z = -HALF + j*cs (north at the top): matches the raster rows
hc = np.clip(np.round((h + 100.0) * 100.0), 0, 65535).astype("<u2")
hc.tofile(os.path.join(OUT, "height.bin"))

ONLY = os.environ.get("ONLY", "")
if ONLY == "height":
    sys.exit(0)
# ------------------------------------------------------------------ land cover (ESA WorldCover)
N_I = 4096
wc = []
for la in range(math.floor(la_min / 3) * 3, math.floor(la_max / 3) * 3 + 1, 3):
    for lo in range(math.floor(lo_min / 3) * 3, math.floor(lo_max / 3) * 3 + 1, 3):
        ns = f"N{la:02d}" if la >= 0 else f"S{-la:02d}"
        ew = f"E{lo:03d}" if lo >= 0 else f"W{-lo:03d}"
        wc.append(f"https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{ns}{ew}_Map.tif")
print("WorldCover tiles", wc)
lc = warp(wc, N_I, Resampling.nearest, dtype=np.uint8, nodata=0)
tree = (lc == 10) | (lc == 20)
built = lc == 50
water = (lc == 80) | (lc == 90)
grass = lc == 30
rgba = np.stack([tree, built, water, grass], -1).astype(np.uint8) * 255
Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "landcover.png"), optimize=True)
print("land cover: trees %.1f%%, built %.1f%%, water %.2f%%" % (tree.mean() * 100, built.mean() * 100, water.mean() * 100))

# ------------------------------------------------------------------ Sentinel-2 ground photo
bb = bbox_ll(0)
poly = {"type": "Polygon", "coordinates": [[[bb[0], bb[1]], [bb[2], bb[1]], [bb[2], bb[3]], [bb[0], bb[3]], [bb[0], bb[1]]]]}
items = []
for yr in (2025, 2024, 2023):
    q = {"collections": ["sentinel-2-l2a"], "intersects": poly, "datetime": f"{yr}-05-15T00:00:00Z/{yr}-08-31T23:59:59Z",
         "query": {"eo:cloud_cover": {"lt": 3}}, "limit": 100}
    items += requests.post("https://earth-search.aws.element84.com/v1/search", json=q, timeout=60).json()["features"]
by_day = {}
for it in items:
    by_day.setdefault(it["properties"]["datetime"][:10], []).append(it)
choice = os.environ.get("S2_DAY")
days = sorted(by_day, key=lambda k: max(i["properties"]["eo:cloud_cover"] for i in by_day[k]))
print("clear days:", [(k, len(by_day[k]), round(max(i['properties']['eo:cloud_cover'] for i in by_day[k]), 2)) for k in days[:12]])
day = choice or days[0]
sel = by_day[day]
print("using", day, [i["id"] for i in sel])


def band(name):
    out = np.full((N_I, N_I), np.nan, np.float32)
    for it in sel:
        a = it["assets"][name]
        off = 0.0
        p = it["properties"]
        if float(p.get("s2:processing_baseline", "0") or 0) >= 4.0 and not p.get("earthsearch:boa_offset_applied", False):
            off = -1000.0
        with rasterio.open(a["href"]) as src:
            tmp = np.full((N_I, N_I), np.nan, np.float32)
            reproject(rasterio.band(src, 1), tmp, dst_transform=grid(N_I), dst_crs=LOCAL, resampling=Resampling.cubic, src_nodata=0, dst_nodata=np.nan)
        m = np.isnan(out) & ~np.isnan(tmp)
        out[m] = (tmp[m] + off) / 10000.0
    return np.nan_to_num(out, nan=0.05)


R, G, B = band("red"), band("green"), band("blue")
# true colour for a game: lift the shadows, lose the blue haze, keep fields natural
rgb = np.stack([R, G, B], -1)
rgb = rgb - np.array([0.012, 0.018, 0.035])                  # haze
rgb = np.clip(rgb, 0, None) * np.array([3.1, 3.05, 3.2])
rgb = rgb / (1 + rgb * 0.35)                                  # soft shoulder for bright roofs and chalk
lum = (rgb * [0.3, 0.59, 0.11]).sum(-1, keepdims=True)
rgb = lum + (rgb - lum) * 1.18                                # a touch more colour
rgb = np.clip(rgb, 0, 1) ** (1 / 1.5)
img = (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)
Image.fromarray(img, "RGB").save(os.path.join(OUT, "ortho.jpg"), quality=90, optimize=True)

# ------------------------------------------------------------------ buildings (Overture Maps)
import duckdb
for k in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"):
    os.environ.pop(k, None)
con = duckdb.connect()
con.execute("INSTALL spatial; LOAD spatial; INSTALL httpfs; LOAD httpfs;")
con.execute("CREATE SECRET (TYPE s3, KEY_ID '', SECRET '', REGION 'us-west-2');")
rows = con.execute(f"""
  SELECT ST_AsWKB(geometry), height, num_floors, class, roof_shape, subtype
  FROM read_parquet('{OVERTURE}/theme=buildings/type=building/*', hive_partitioning=1)
  WHERE bbox.xmin > {bb[0]} AND bbox.xmax < {bb[2]} AND bbox.ymin > {bb[1]} AND bbox.ymax < {bb[3]}""").fetchall()
print("buildings:", len(rows))
from shapely import wkb
from shapely.geometry import Polygon
recs = []
for g, height, floors, cls, roof, sub in rows:
    geom = wkb.loads(bytes(g))
    polys = [geom] if geom.geom_type == "Polygon" else list(getattr(geom, "geoms", []))
    for p in polys:
        if p.geom_type != "Polygon":
            continue
        xs, ys = to_local.transform(*np.array(p.exterior.coords).T)
        pts = np.stack([xs, -ys], -1)                          # game x, z
        if np.abs(pts).max() > HALF - 50:
            continue
        lp = Polygon(pts).simplify(0.6)
        if lp.is_empty or lp.area < 12 or lp.geom_type != "Polygon":
            continue
        c = np.array(lp.exterior.coords)[:-1]
        if len(c) < 3 or len(c) > 60:
            continue
        # v1.19.0: nothing stands on the runway. The map data has four "buildings" on the centreline (parked
        # aircraft or map mistakes); keep the strip and 300 m beyond each end clear
        cu, cv = runway_uv(c[:, 0].mean(), c[:, 1].mean())
        if abs(cu) < rw_len / 2 + 300 and abs(cv) < 60:
            continue
        if height is None or not (2 < height < 120):
            height = (floors * 3.0 + 1.0) if floors else None
        a = lp.area
        kind = 0                                                # 0 house, 1 big low (barn/hangar/shed), 2 other
        if height is None:
            height = 7.5 if a < 250 else (9.0 if a < 2000 else 11.0)
        if a > 600 and height < 16:
            kind = 1
        elif a > 300 or height > 12:
            kind = 2
        recs.append((c, float(height), kind))
with open(os.path.join(OUT, "buildings.bin"), "wb") as f:
    f.write(struct.pack("<I", len(recs)))
    for c, height, kind in recs:
        f.write(struct.pack("<BBH", len(c), kind, int(height * 10)))
        f.write(np.round(c * 4).astype("<i4").tobytes())       # quarter metres
print("kept buildings:", len(recs))

meta = {
    "origin_lat": lat0, "origin_lon": lon0, "half": HALF, "height_size": N_H, "height_cell": cs,
    "height_encoding": "uint16 little-endian, metres = value / 100 - 100, row 0 = north edge",
    "runway_heading": round(rw_heading, 3), "runway_len": round(rw_len, 1), "runway_elev": round(rw_elev, 2),
    "grass_runway": [[round(gx0, 1), round(-gy0, 1)], [round(gx1, 1), round(-gy1, 1)]],
    "sentinel2_day": day, "sentinel2_items": [i["id"] for i in sel],
    "credits": [
        f"Contains modified Copernicus Sentinel data {day[:4]}",
        "Produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
        "ESA WorldCover 2021 (c) ESA, CC BY 4.0",
        "Buildings and runway: Overture Maps Foundation, including (c) OpenStreetMap contributors (ODbL)",
    ],
}
json.dump(meta, open(os.path.join(OUT, "world.json"), "w"), indent=1)
print("done:", OUT)
