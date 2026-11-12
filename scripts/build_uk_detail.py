#!/usr/bin/env python3
"""Build the high-detail inset for SmartMotion Flight (v1.15.0) from free UK open data (Open Government Licence).

An 8,192 m square centred on the middle of Duxford's hard runway (same local grid as build_world_data.py):
  - detail_h.png     4096 x 4096, 2 m: ground height from the Environment Agency's 1 m LIDAR Composite DTM,
                     16-bit in two 8-bit channels (R high byte, G low byte; metres = value / 100 - 100)
  - detail_photo.jpg 8192 x 8192, 1 m: the ground picture. Colour from the Sentinel-2 photo (ortho.jpg), with the
                     real tree crowns (EA LIDAR vegetation heights, shaded by the sun), OS OpenMap Local roads,
                     water and building outlines drawn sharp, and field texture from the EA LIDAR intensity
  - detail_mask.png  4096 x 4096, 2 m: R tree canopy, G road, B water, A building (for the ground shader)
  - trees.bin        every tree the LIDAR sees in the square (peaks of the vegetation heights): x, z, height, crown
Also rewrites height.bin (the 32 km square, 32 m cells) with the LIDAR ground wherever the LIDAR covers it.

Data (downloaded by fetch_uk_detail() below into ~/ukdata; all Open Government Licence v3, credit only):
  Environment Agency LIDAR Composite DTM 2022 1 m, National LIDAR Programme VOM and intensity 1 m
  Ordnance Survey OpenMap Local (TL square)
Needs: pip install rasterio pyproj numpy pillow scipy fiona shapely requests
Run:   python3 scripts/build_uk_detail.py   (downloads about 1.6 GB the first time; then a few minutes)
"""
import glob, json, math, os, struct, subprocess, sys, zipfile
import numpy as np
import rasterio
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from rasterio import features
from pyproj import Transformer
from PIL import Image
from scipy import ndimage
import fiona
from shapely.geometry import shape, mapping, box
import warnings
from shapely.ops import transform as sh_transform
warnings.filterwarnings("ignore", category=DeprecationWarning)

HERE = os.path.dirname(os.path.abspath(__file__))
WORLD = os.path.join(HERE, "..", "godot", "assets", "world")
DATA = os.path.expanduser("~/ukdata")
HALF = 16384.0                 # the whole world square (build_world_data.py)
ZH = 4096.0                    # half the detail square
NP, NH = 8192, 4096            # photo pixels (1 m), height / mask pixels (2 m)
wj = json.load(open(os.path.join(WORLD, "world.json")))
LOCAL = f"+proj=tmerc +lat_0={wj['origin_lat']} +lon_0={wj['origin_lon']} +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
to_osgb = Transformer.from_crs(LOCAL, "EPSG:27700", always_xy=True)
to_ll = Transformer.from_crs(LOCAL, "EPSG:4326", always_xy=True)
SURVEY = "https://environment.data.gov.uk/backend/catalog/api/tiles/collections/survey/search"


def fetch_uk_detail():
    import requests
    os.makedirs(DATA, exist_ok=True)
    H = ZH + 300
    ring = [list(to_ll.transform(x, y)) for x, y in [(-H, -H), (H, -H), (H, H), (-H, H), (-H, -H)]]
    res = requests.post(SURVEY, data=json.dumps({"type": "Polygon", "coordinates": [ring]}),
                        headers={"Content-Type": "application/geo+json"}, timeout=120).json()["results"]
    want = {}
    for x in res:
        p, y, r, t = x["product"]["id"], x["year"]["id"], x["resolution"]["id"], x["tile"]["id"]
        if r != "1":
            continue
        if p == "lidar_composite_dtm" or (p in ("national_lidar_programme_vom", "national_lidar_programme_intensity")
                                          and ((p, t) not in want or y > want[(p, t)][0])):
            want[(p, t)] = (y, x["uri"])
    for (p, t), (y, u) in sorted(want.items()):
        z = os.path.join(DATA, "raw", p, f"{t}_{y}.zip")
        if not os.path.exists(z):
            os.makedirs(os.path.dirname(z), exist_ok=True)
            subprocess.run(["curl", "-sS", "-L", "--retry", "3", "-o", z, u], check=True)
        out = os.path.join(DATA, "tif", p)
        os.makedirs(out, exist_ok=True)
        with zipfile.ZipFile(z) as zf:
            for n in zf.namelist():
                if n.endswith(".tif") and "_HS_" not in n and not os.path.exists(os.path.join(out, os.path.basename(n))):
                    zf.extract(n, out)
    oml = os.path.join(DATA, "oml_tl.zip")
    if not os.path.exists(oml):
        subprocess.run(["curl", "-sS", "-L", "-o", oml, "https://api.os.uk/downloads/v1/products/OpenMapLocal/downloads?area=TL&format=ESRI%C2%AE+Shapefile&redirect"], check=True)
    if not glob.glob(os.path.join(DATA, "oml", "**", "TL_Road.shp"), recursive=True):
        with zipfile.ZipFile(oml) as zf:
            zf.extractall(os.path.join(DATA, "oml"))


def grid(n, half, centred=False):
    c = 2 * half / n
    o = c / 2 if centred else 0.0
    return from_origin(-half - o, half + o, c, c)


def warp(files, n, half, resampling, centred=False):
    dst = np.full((n, n), np.nan, np.float32)
    for f in files:
        with rasterio.open(f) as src:
            tmp = np.full((n, n), np.nan, np.float32)
            reproject(rasterio.band(src, 1), tmp, dst_transform=grid(n, half, centred), dst_crs=LOCAL, resampling=resampling,
                      src_nodata=src.nodata, dst_nodata=np.nan)
            m = np.isnan(dst) & ~np.isnan(tmp)
            dst[m] = tmp[m]
    return dst


def fill_nan(a):
    m = np.isnan(a)
    if not m.any():
        return a
    idx = ndimage.distance_transform_edt(m, return_distances=False, return_indices=True)
    return a[tuple(idx)]


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def tifs(p):
    return sorted(glob.glob(os.path.join(DATA, "tif", p, "*.tif")))


def shapes(name, bounds_osgb):
    f = glob.glob(os.path.join(DATA, "oml", "**", f"TL_{name}.shp"), recursive=True)[0]
    with fiona.open(f) as s:
        for r in s.filter(bbox=bounds_osgb):
            yield shape(r["geometry"]), r["properties"]


_inv = Transformer.from_crs("EPSG:27700", LOCAL, always_xy=True)


def to_local_geom(g):
    return sh_transform(lambda x, y, z=None: _inv.transform(x, y), g)


def raster(geoms, n, half, all_touched=False):
    if not geoms:
        return np.zeros((n, n), np.float32)
    r = features.rasterize(geoms, out_shape=(n, n), transform=grid(n, half), fill=0, all_touched=all_touched, dtype=np.uint8, merge_alg=features.MergeAlg.replace)
    return r.astype(np.float32) / (255.0 if r.max() > 1 else 1.0)


def dashes(line, on, gap):
    """Pieces of a line: `on` metres of paint every `on + gap` metres."""
    from shapely.ops import substring
    out = []
    geoms = getattr(line, "geoms", [line])
    for ln in geoms:
        L = ln.length
        d = gap * 0.5
        while d < L:
            out.append(substring(ln, d, min(d + on, L)))
            d += on + gap
    return out


def grade_runway(h2):
    """The runway is level at the game's runway height (Terrain.RW_ELEV, as in earlier versions): the real one
    falls about 4 m from the 06 end, and the ground rises 5 m just before it, which made landings float a long
    way. Level 25 m either side and 60 m past each end, blended into the real LIDAR ground over the next 40-80 m."""
    hd = math.radians(wj["runway_heading"])
    d = np.array([math.sin(hd), -math.cos(hd)])
    pp = np.array([math.cos(hd), math.sin(hd)])
    L = wj["runway_len"]
    n = h2.shape[0]
    c = (np.arange(n) * 2.0 - ZH)
    X, Z = np.meshgrid(c, c)
    U = X * d[0] + Z * d[1]
    V = X * pp[0] + Z * pp[1]
    us = np.arange(-L / 2 - 700, L / 2 + 201, 2.0)
    prof = []
    for u in us:
        x, z = d * u
        i, j = int(round((x + ZH) / 2)), int(round((z + ZH) / 2))
        prof.append(np.median(h2[j - 6:j + 7, i - 6:i + 7]))
    prof = np.full(len(prof), 33.5)   # Terrain.RW_ELEV
    hp = np.interp(U, us, prof)
    # past the 06 end (where landings come in) the approach is level for 350 m as on earlier maps; past the
    # 24 end only 60 m, so the real M11 cutting just beyond it stays as it is
    past = np.where(U < 0, -U - L / 2, U - L / 2)
    w = np.where(U < 0, 1 - sstep(350.0, 600.0, past), 1 - sstep(60.0, 140.0, past))
    w *= 1 - sstep(np.where((U < 0) & (past > 0), 90.0, 48.0), np.where((U < 0) & (past > 0), 160.0, 88.0), np.abs(V))
    print("runway levelled at 33.5 m (the LIDAR has it %.1f m at the 06 end, %.1f m at the 24 end)" % (h2[int(round((d[1] * -L / 2 + ZH) / 2)), int(round((d[0] * -L / 2 + ZH) / 2))], h2[int(round((d[1] * L / 2 + ZH) / 2)), int(round((d[0] * L / 2 + ZH) / 2))]))
    return h2 * (1 - w) + hp * w


def write_normals(h2):
    """detail_n.png (v1.17.0): the ground's slope every 2 m, so the ground shader reads one filtered texture
    for its shading instead of about 20 height lookups a pixel (much quicker in VR, where every pixel is drawn
    twice). R, G = the normal's x and z (east, south) as 0.5 + n / 2; with mipmaps it smooths itself far away."""
    gz, gx = np.gradient(h2.astype(np.float64), 2.0)       # rows run south (game +z), columns east (+x)
    n = np.dstack([-gx, np.ones_like(gx), -gz])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    rg = np.dstack([n[..., 0] * 0.5 + 0.5, n[..., 2] * 0.5 + 0.5, np.zeros_like(gx)])
    Image.fromarray((np.clip(rg, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(WORLD, "detail_n.png"), optimize=True)
    print("detail_n.png: ground slopes for the shader")


def normals_only():
    a = np.asarray(Image.open(os.path.join(WORLD, "detail_h.png"))).astype(np.int32)
    write_normals((a[..., 0] * 256 + a[..., 1]) / 100.0 - 100.0)


def main():
    fetch_uk_detail()
    xs, ys = [], []
    for x in (-ZH - 400, ZH + 400):
        for y in (-ZH - 400, ZH + 400):
            e, n = to_osgb.transform(x, y)
            xs.append(e); ys.append(n)
    bounds = (min(xs), min(ys), max(xs), max(ys))
    print("detail square in OS grid:", [round(v) for v in bounds])

    # ------------------------------------------------------------ heights
    dtm = tifs("lidar_composite_dtm")
    print("LIDAR DTM tiles:", len(dtm))
    h2 = warp(dtm, NH, ZH, Resampling.average, centred=True)
    print("detail heights: %.1f to %.1f m, %.2f%% missing" % (np.nanmin(h2), np.nanmax(h2), 100 * np.isnan(h2).mean()))
    h2 = fill_nan(h2)
    h2 = grade_runway(h2)
    v = np.clip(np.round((h2 + 100.0) * 100.0), 0, 65535).astype(np.uint16)
    rg = np.dstack([(v >> 8).astype(np.uint8), (v & 255).astype(np.uint8), np.zeros_like(v, np.uint8)])
    Image.fromarray(rg, "RGB").save(os.path.join(WORLD, "detail_h.png"), optimize=True)
    write_normals(h2)

    # the 32 km map: LIDAR ground where it exists (averaged into the 32 m cells), Copernicus elsewhere, blended
    old = np.frombuffer(open(os.path.join(WORLD, "height.bin"), "rb").read(), "<u2").reshape(1024, 1024).astype(np.float32) / 100.0 - 100.0
    if not os.path.exists(os.path.join(WORLD, "height_copernicus.bin")):
        open(os.path.join(WORLD, "height_copernicus.bin"), "wb").write(open(os.path.join(WORLD, "height.bin"), "rb").read())
    old = np.frombuffer(open(os.path.join(WORLD, "height_copernicus.bin"), "rb").read(), "<u2").reshape(1024, 1024).astype(np.float32) / 100.0 - 100.0
    lid = warp(dtm, 1024, HALF, Resampling.average, centred=True)
    have = ~np.isnan(lid)
    # blend from Copernicus at the edge of the LIDAR cover to LIDAR 640 m inside it (no step at the edge)
    dist = ndimage.distance_transform_edt(have) * 32.0
    w = sstep(0.0, 640.0, dist)
    new = np.where(have, old + (np.nan_to_num(lid) - old) * w, old)
    print("height.bin: LIDAR covers %.0f%% of the 32 km map (mean change %.2f m)" % (100 * have.mean(), float(np.mean((new - old)[have]))))
    hv = np.clip(np.round((new + 100.0) * 100.0), 0, 65535).astype("<u2")
    open(os.path.join(WORLD, "height.bin"), "wb").write(hv.tobytes())

    # ------------------------------------------------------------ vegetation, intensity
    vom = warp(tifs("national_lidar_programme_vom"), NP, ZH, Resampling.bilinear)
    vom = np.nan_to_num(vom, nan=0.0)
    vom[(vom < 0) | (vom > 40)] = 0
    inten = fill_nan(warp(tifs("national_lidar_programme_intensity"), NP, ZH, Resampling.bilinear))
    li = np.log(np.clip(inten, 1.0, None)).astype(np.float32)
    del inten
    print("vegetation: %.1f%% of the square above 2 m" % (100 * (vom > 2).mean()))

    # ------------------------------------------------------------ OS OpenMap Local
    road_w = {"Motorway": 24.0, "Primary Road": 11.0, "A Road": 9.5, "B Road": 7.5, "Minor Road": 6.0, "Local Road": 5.5,
              "Local Access Road": 4.0, "Restricted Local Access Road": 3.5, "Shared Use Carriageway": 4.0}
    rd, marks, edge = [], [], []
    for g, p in shapes("Road", bounds):
        c = str(p.get("CLASSIFICA") or "")
        wdt = road_w.get(c.split(",")[0], 4.0)
        if "Collapsed Dual" in c:
            wdt *= 1.8
        # value: how dark the surface is (main roads fresh black tarmac, lanes and tracks paler and worn)
        tone = 255 if wdt >= 7.0 else (190 if wdt >= 5.0 else 120)
        lg = to_local_geom(g)
        rd.append((lg.buffer(wdt / 2.0, cap_style=1), tone))
        # road markings (v1.17.0), drawn 1 m wide and faint so at 1 m a pixel they read as the real thin lines:
        # dashed white centre lines on A, B and minor roads, solid edge lines on A roads and motorways
        kind = c.split(",")[0]
        if kind in ("A Road", "B Road", "Minor Road", "Primary Road") and "Collapsed Dual" not in c:
            marks.extend(dashes(lg, 4.0 if kind != "Minor Road" else 2.0, 5.0 if kind != "Minor Road" else 7.0))
        if kind in ("A Road", "Primary Road", "Motorway"):
            for side in (-1, 1):
                try:
                    edge.append(lg.parallel_offset(side * (wdt / 2.0 - 0.6), "left", join_style=2))
                except Exception:
                    pass
        if kind == "Motorway" or "Collapsed Dual" in c:
            for off in (-wdt / 4.0, wdt / 4.0):
                try:
                    marks.extend(dashes(lg.parallel_offset(off, "left", join_style=2), 2.0, 7.0))
                except Exception:
                    pass
    wa = [(to_local_geom(g), 1) for g, _ in shapes("SurfaceWater_Area", bounds)]
    wa += [(to_local_geom(g).buffer(1.6), 1) for g, _ in shapes("SurfaceWater_Line", bounds)]
    bl = [(to_local_geom(g), 1) for g, _ in shapes("Building", bounds)]
    print("OS OpenMap Local: %d roads, %d water, %d buildings" % (len(rd), len(wa), len(bl)))
    road = raster(rd, NP, ZH)
    mk = raster([(m.buffer(0.5, cap_style=2), 1) for m in marks + edge if not m.is_empty], NP, ZH)
    print("road markings: %d dashes, %d edge lines" % (len(marks), len(edge)))
    water = raster(wa, NP, ZH)
    bldg = raster(bl, NP, ZH)

    # ------------------------------------------------------------ the photo (in strips, to fit in memory)
    ortho = np.asarray(Image.open(os.path.join(WORLD, "ortho.jpg")).convert("RGB"))
    px = ortho.shape[0] / (2 * HALF)
    a, b = int((HALF - ZH) * px), int((HALF + ZH) * px)
    base_img = Image.fromarray(ortho[a:b, a:b]).resize((NP, NP), Image.BICUBIC)
    del ortho
    rng = np.random.default_rng(5)
    tint = ndimage.gaussian_filter(rng.random((NP // 8, NP // 8)), 1.5)
    tint = (np.asarray(Image.fromarray(((tint - tint.min()) / (np.ptp(tint) + 1e-6) * 255).astype(np.uint8)).resize((NP, NP), Image.BILINEAR)) / 255.0).astype(np.float32)
    sun = np.array([-0.45, -0.55, 0.70], np.float32)  # towards the sun (south-west): x east, y north, z up
    tar = np.array([0.030, 0.031, 0.034], np.float32)
    wcol = np.array([0.010, 0.020, 0.018], np.float32)
    roof = np.array([0.06, 0.055, 0.055], np.float32)
    out = np.zeros((NP, NP, 3), np.uint8)
    S, M = 1024, 24
    for r0 in range(0, NP, S):
        a0, a1 = max(r0 - M, 0), min(r0 + S + M, NP)
        sl = slice(a0, a1)
        k0, k1 = r0 - a0, r0 - a0 + min(S, NP - r0)
        base = np.asarray(base_img.crop((0, a0, NP, a1))).astype(np.float32) / 255.0
        lin = base ** 2.2
        v = vom[sl]
        canopy = ndimage.gaussian_filter(sstep(1.5, 3.5, v), 0.7).astype(np.float32)
        rs, ws, bs = road[sl], water[sl], bldg[sl]
        # field texture from the LIDAR intensity: only the fine detail (a few metres), as a gentle brightness change
        hp = np.clip((li[sl] - ndimage.gaussian_filter(li[sl], 5.0)) * 0.55, -0.22, 0.22)
        open_ground = (1 - canopy) * (1 - rs) * (1 - ws) * (1 - bs)
        lin *= np.exp(hp * open_ground)[..., None]
        # tree crowns from above: lit from the sun side, dark on the far side
        sh = ndimage.gaussian_filter(v, 0.8)
        gy, gx = np.gradient(sh)
        nz = np.full_like(gx, 1.2)
        ln = np.sqrt(gx * gx + gy * gy + nz * nz)
        lit = np.clip((-gx * sun[0] + gy * sun[1] + nz * sun[2]) / ln, 0.0, 1.0)
        t = tint[sl]
        leaf = np.dstack([0.040 + 0.03 * t, 0.075 + 0.035 * t, 0.025 + 0.01 * t])
        # keep some of the photo's own tree colour (seasons, conifers, copper beech), lit like a crown
        leaf = leaf * 0.6 + ndimage.gaussian_filter(lin, (3, 3, 0)) * 0.4
        crown = leaf * (0.5 + 1.0 * lit)[..., None]
        lin = lin * (1 - canopy[..., None]) + crown * canopy[..., None]
        # tarmac over the photo: dark fresh tarmac on main roads, a worn mix with the ground on lanes and tracks
        cov = ndimage.gaussian_filter((rs > 0).astype(np.float32), 0.6)[..., None]
        tone = ndimage.maximum_filter(rs, size=3)[..., None]
        road_col = lin * 0.75 * (1 - tone) + tar * (0.9 + 0.2 * t[..., None]) * tone
        lin = lin * (1 - cov) + road_col * cov
        lin = lin * (1 - mk[sl][..., None] * 0.32) + np.float32(0.55) * mk[sl][..., None] * 0.32   # the white lines
        rs = (rs > 0).astype(np.float32)
        water_s = ndimage.gaussian_filter(ws, 0.7)
        lin = lin * (1 - water_s[..., None]) + wcol * water_s[..., None]
        # roofs: darker and greyer than the photo's smudge, keeping its variation (the 3D buildings stand on top)
        lin = lin * (1 - bs[..., None] * 0.6) + (roof + lin * 0.4) * bs[..., None] * 0.6
        out[r0:r0 + (k1 - k0)] = (np.clip(lin[k0:k1], 0, 1) ** (1 / 2.2) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(out, "RGB").save(os.path.join(WORLD, "detail_photo.jpg"), quality=88, optimize=True)
    del out, li, base_img, tint
    canopy = sstep(1.5, 3.5, vom).astype(np.float32)

    def half_res(m):
        return m.reshape(NH, 2, NH, 2).mean(axis=(1, 3))
    mask = np.dstack([half_res(canopy), half_res((road > 0).astype(np.float32)), half_res(water), half_res(bldg)])
    Image.fromarray((np.clip(mask, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(WORLD, "detail_mask.png"), optimize=True)

    # ------------------------------------------------------------ trees: the peaks of the vegetation heights
    vs = ndimage.gaussian_filter(vom, 1.2)
    peak = (vs == ndimage.maximum_filter(vs, size=7)) & (vs > 3.0) & (road <= 0) & (bldg < 0.5) & (water < 0.5)
    yy, xx = np.nonzero(peak)
    hts = vom[yy, xx]
    # crown size: the width of the canopy around the peak (half the height, 2-9 m radius)
    cr = np.clip(hts * 0.32 + 1.2, 2.0, 9.0)
    wx = -ZH + (xx + 0.5) * (2 * ZH / NP)
    wz = -ZH + (yy + 0.5) * (2 * ZH / NP)
    order = np.lexsort((wx, wz))
    rec = np.zeros(len(order), dtype=[("x", "<i2"), ("z", "<i2"), ("h", "u1"), ("r", "u1")])
    rec["x"] = np.round(wx[order] * 4)
    rec["z"] = np.round(wz[order] * 4)
    rec["h"] = np.clip(np.round(hts[order] * 5), 0, 255)
    rec["r"] = np.clip(np.round(cr[order] * 20), 0, 255)
    with open(os.path.join(WORLD, "trees.bin"), "wb") as f:
        f.write(struct.pack("<I", len(rec)))
        f.write(rec.tobytes())
    print("trees.bin: %d trees (%.0f per km2), median height %.1f m" % (len(rec), len(rec) / ((2 * ZH / 1000) ** 2), float(np.median(hts))))

    wj["detail"] = {"half": ZH, "photo_px": NP, "height_px": NH, "height_encoding": "detail_h.png R*256+G, metres = value / 100 - 100, sample i at -half + i*2",
                    "trees": "trees.bin: uint32 count, then per tree int16 x*4, int16 z*4, uint8 height*5, uint8 crown radius*20"}
    cr_list = wj["credits"]
    for c in ["Contains Environment Agency information © Environment Agency and/or database right 2026 (LIDAR, Open Government Licence v3.0)",
              "Contains OS data © Crown copyright and database right 2026 (OS OpenMap Local, Open Government Licence v3.0)"]:
        if c not in cr_list:
            cr_list.append(c)
    json.dump(wj, open(os.path.join(WORLD, "world.json"), "w"), indent=1)
    print("done")


if __name__ == "__main__":
    if "--normals-only" in sys.argv:
        normals_only()
    else:
        main()
