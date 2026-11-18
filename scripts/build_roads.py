"""Makes godot/assets/world/roads.bin (v1.23.0): every road in the 32 km map as a centreline with its class, from
Ordnance Survey OpenMap Local (Open Government Licence, LIC-16: the same data the 1 m ground picture uses). The game
lays the nearby roads on the ground as proper road surfaces (real_scenery.gd, shaders/road.gdshader): crisp edges at
any height, continuous through junctions, centre and edge lines where the real roads have them.
Needs: pip install pyshp shapely pyproj; network access to api.os.uk and omseprd1stdstordownload.blob.core.windows.net
(the download goes to ~/ukdata, as for scripts/build_uk_detail.py).
Run: python3 -I scripts/build_roads.py

roads.bin: uint32 count, then per road: uint8 class, uint8 flags (1 = collapsed dual carriageway), uint16 points,
points as int32 x, z in quarter metres (game axes: x east, z south, origin as world.json)."""
import glob, json, os, struct, subprocess, zipfile
import numpy as np
import shapefile
from pyproj import Transformer
from shapely.geometry import LineString, box

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "godot", "assets", "world")
DATA = os.path.expanduser("~/ukdata")
wj = json.load(open(os.path.join(WORLD, "world.json")))
HALF = wj["half"]
LOCAL = f"+proj=tmerc +lat_0={wj['origin_lat']} +lon_0={wj['origin_lon']} +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs"
from_osgb = Transformer.from_crs("EPSG:27700", LOCAL, always_xy=True)
to_osgb = Transformer.from_crs(LOCAL, "EPSG:27700", always_xy=True)
# class ids (shaders/road.gdshader and real_scenery.gd use the same numbers)
CLASSES = {"Motorway": 0, "Primary Road": 1, "A Road": 2, "B Road": 3, "Minor Road": 4, "Local Road": 5,
           "Local Access Road": 6, "Restricted Local Access Road": 7, "Shared Use Carriageway": 8, "Guided Busway Carriageway": 9}
STEP = 6.0     # longest piece between points (metres): the road follows the ground's shape at this spacing


def fetch():
    os.makedirs(DATA, exist_ok=True)
    z = os.path.join(DATA, "oml_tl.zip")
    if not os.path.exists(z):
        subprocess.run(["curl", "-sS", "-L", "--retry", "3", "-o", z,
                        "https://api.os.uk/downloads/v1/products/OpenMapLocal/downloads?area=TL&format=ESRI%C2%AE+Shapefile&redirect"], check=True)
    if not glob.glob(os.path.join(DATA, "oml", "**", "TL_Road.shp"), recursive=True):
        with zipfile.ZipFile(z) as zf:
            zf.extractall(os.path.join(DATA, "oml"), [n for n in zf.namelist() if "TL_Road." in n])
    return glob.glob(os.path.join(DATA, "oml", "**", "TL_Road.shp"), recursive=True)[0]


def main():
    shp = fetch()
    r = shapefile.Reader(shp)
    # the map square in the OS grid (a little bigger, then clipped exactly in game axes)
    xs, ys = zip(*[to_osgb.transform(x, y) for x in (-HALF - 500, HALF + 500) for y in (-HALF - 500, HALF + 500)])
    bb = (min(xs), min(ys), max(xs), max(ys))
    clip = box(-HALF + 20, -HALF + 20, HALF - 20, HALF - 20)
    out = []
    pts_total = 0
    for sr in r.iterShapeRecords(fields=["CLASSIFICA"]):
        b = sr.shape.bbox
        if b[2] < bb[0] or b[0] > bb[2] or b[3] < bb[1] or b[1] > bb[3]:
            continue
        cls_txt = str(sr.record["CLASSIFICA"] or "")
        kind = cls_txt.split(",")[0]
        if kind not in CLASSES:
            continue
        flags = 1 if "Collapsed Dual" in cls_txt else 0
        parts = list(sr.shape.parts) + [len(sr.shape.points)]
        for k in range(len(parts) - 1):
            p = np.array(sr.shape.points[parts[k]:parts[k + 1]])
            if len(p) < 2:
                continue
            ex, ny = from_osgb.transform(p[:, 0], p[:, 1])
            line = LineString(np.stack([ex, -np.asarray(ny)], -1))   # game x, z (north is -z)
            g = line.intersection(clip)
            for ln in ([g] if g.geom_type == "LineString" else list(getattr(g, "geoms", []))):
                if ln.geom_type != "LineString" or ln.length < 2.0:
                    continue
                n = max(int(np.ceil(ln.length / STEP)), 1)
                q = np.array([ln.interpolate(i / n, normalized=True).coords[0] for i in range(n + 1)])
                if len(q) > 65000:
                    continue
                out.append((CLASSES[kind], flags, q))
                pts_total += len(q)
    with open(os.path.join(WORLD, "roads.bin"), "wb") as f:
        f.write(struct.pack("<I", len(out)))
        for c, fl, q in out:
            f.write(struct.pack("<BBH", c, fl, len(q)))
            f.write(np.round(q * 4).astype("<i4").tobytes())
    km = sum(np.linalg.norm(np.diff(q, axis=0), axis=1).sum() for _, _, q in out) / 1000.0
    print(f"roads.bin: {len(out)} roads, {pts_total} points, {km:.0f} km")


if __name__ == "__main__":
    main()
