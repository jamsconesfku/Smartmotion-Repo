#!/usr/bin/env python3
"""Build one Printing & Design model for the SmartMotion Dashboard.

Usage:
  python3 scripts/build_design.py <slug> [--version v2] [--changes "What changed"]

Reads designs/<slug>/model.py (META, PARAMS, build(p) -> {part_name: cadquery shape}),
then writes designs/<slug>/<version>/:
  <slug>-<version>-<part>.stl / .step   print + editable CAD files
  view.json                             light mesh for the dashboard's 3D viewer
  preview.png                           picture for the library card
  <slug>-<version>.zip                  everything Sam downloads (STL, STEP, source, notes)
  model.py                              frozen copy of the source for this version
and adds or updates the entry in data/designs.json (keeping status, notes and print log).
"""
import argparse, datetime, importlib.util, json, shutil, subprocess, sys, zipfile
from pathlib import Path

import cadquery as cq
import numpy as np
import trimesh
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

ROOT = Path(__file__).resolve().parent.parent
PRINTERS = {"kobra3": ("Anycubic Kobra 3", (250, 250, 260)), "kobra3max": ("Anycubic Kobra 3 Max", (420, 420, 500))}
DENSITY = {"PLA": 1.24, "PLA+": 1.24, "PETG": 1.27, "ABS": 1.04, "ASA": 1.07, "TPU": 1.21}
ORANGE = np.array([1.0, 0.30, 0.0])


def load_model(slug):
    path = ROOT / "designs" / slug / "model.py"
    spec = importlib.util.spec_from_file_location(f"design_{slug.replace('-', '_')}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, path


def fits(dims):
    x, y, z = dims
    out = {}
    for key, (_, (bx, by, bz)) in PRINTERS.items():
        out[key] = z <= bz and ((x <= bx and y <= by) or (y <= bx and x <= by))
    return out


def render_preview(meshes, out_png):
    fig = plt.figure(figsize=(8, 6), dpi=110)
    ax = fig.add_subplot(111, projection="3d")
    light = np.array([-0.35, -0.55, 0.76]); light /= np.linalg.norm(light)
    offset, allpts = 0.0, []
    for m in meshes:
        m = m.copy()
        lo, hi = m.bounds
        m.apply_translation([offset - lo[0], -(lo[1] + hi[1]) / 2, -lo[2]])
        offset += (hi[0] - lo[0]) + 15
        tris = m.triangles
        shade = 0.38 + 0.62 * np.clip(m.face_normals @ light, 0, 1)
        cols = np.clip(ORANGE[None, :] * shade[:, None] + (shade[:, None] ** 6) * 0.35, 0, 1)
        ax.add_collection3d(Poly3DCollection(tris, facecolors=cols, edgecolors="none", linewidths=0))
        allpts.append(m.vertices)
    pts = np.vstack(allpts)
    lo, hi = pts.min(0), pts.max(0); mid = (lo + hi) / 2; span = (hi - lo).max() / 2
    ax.set_xlim(mid[0] - span, mid[0] + span); ax.set_ylim(mid[1] - span, mid[1] + span); ax.set_zlim(mid[2] - span, mid[2] + span)
    ax.set_box_aspect((1, 1, 1)); ax.view_init(elev=28, azim=-55); ax.set_axis_off()
    fig.patch.set_alpha(0); ax.patch.set_alpha(0)
    plt.subplots_adjust(0, 0, 1, 1)
    fig.savefig(out_png, transparent=True, bbox_inches="tight", pad_inches=0.05)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("slug")
    ap.add_argument("--version")
    ap.add_argument("--changes", default="")
    a = ap.parse_args()

    mod, src = load_model(a.slug)
    meta, params = mod.META, mod.PARAMS
    p = {k: v["value"] for k, v in params.items()}
    parts = mod.build(p)

    reg_path = ROOT / "data" / "designs.json"
    reg = json.loads(reg_path.read_text()) if reg_path.exists() else []
    entry = next((e for e in reg if e["slug"] == a.slug), None)
    version = a.version or (f"v{len(entry['versions']) + 1}" if entry else "v1")
    outdir = ROOT / "designs" / a.slug / version
    if outdir.exists():
        shutil.rmtree(outdir)
    outdir.mkdir(parents=True)
    shutil.copy(src, outdir / "model.py")

    material = meta["print"].get("material", "PLA").split()[0]
    dens = DENSITY.get(material, 1.24)
    part_info, view, meshes = [], {"parts": []}, []
    for name, shape in parts.items():
        base = f"{a.slug}-{version}-{name}"
        stl, step = outdir / f"{base}.stl", outdir / f"{base}.step"
        cq.exporters.export(shape, str(stl), tolerance=0.02, angularTolerance=0.08)
        cq.exporters.export(shape, str(step))
        m = trimesh.load(stl, force="mesh")
        m.export(stl)  # rewrite as binary STL (much smaller than CadQuery's text STL)
        lo, hi = m.bounds
        dims = [round(float(v), 1) for v in (hi - lo)]
        vol = float(shape.val().Volume()) / 1000.0  # cm3
        part_info.append({
            "name": name, "stl": f"designs/{a.slug}/{version}/{base}.stl", "step": f"designs/{a.slug}/{version}/{base}.step",
            "dims_mm": dims, "volume_cm3": round(vol, 1), "solid_g": round(vol * dens, 1),
            "est_g": round(vol * dens * meta["print"].get("fill_factor", 0.45), 0),
            "triangles": int(len(m.faces)), "watertight": bool(m.is_watertight), "fits": fits(dims)})
        # light mesh for the browser viewer
        tmp = outdir / f"_{name}_view.stl"
        cq.exporters.export(shape, str(tmp), tolerance=0.25, angularTolerance=0.35)
        vm = trimesh.load(tmp, force="mesh"); tmp.unlink()
        view["parts"].append({"name": name, "positions": np.round(vm.triangles.reshape(-1), 3).tolist()})
        meshes.append(m)
    (outdir / "view.json").write_text(json.dumps(view, separators=(",", ":")))
    # preview picture: three.js in headless Chromium (same look as the dashboard viewer);
    # falls back to a simple matplotlib render if that isn't available
    tmpj = outdir / "_preview_mesh.json"
    tmpj.write_text(json.dumps({"parts": [{"name": q["name"], "positions": np.round(m.triangles.reshape(-1), 3).tolist()}
                                          for q, m in zip(part_info, meshes)]}))
    try:
        subprocess.run(["node", str(ROOT / "scripts" / "render_preview.js"), str(tmpj), str(outdir / "preview.png")],
                       check=True, cwd=str(ROOT), timeout=180)
    except Exception as err:
        print("three.js preview failed, using matplotlib:", err)
        render_preview(meshes, outdir / "preview.png")
    tmpj.unlink()

    today = datetime.date.today().isoformat()
    readme = [f"{meta['title']} ({version})", "=" * 40, meta["summary"], "",
              "Print settings", *[f"  {k.replace('_', ' ')}: {v}" for k, v in meta["print"].items() if k != "fill_factor"], "",
              "Parts", *[f"  {q['name']}: {q['dims_mm'][0]} x {q['dims_mm'][1]} x {q['dims_mm'][2]} mm, about {int(q['est_g'])} g" for q in part_info], "",
              "Measurements you can change (ask Claude, or edit model.py)",
              *[f"  {v['label']}: {v['value']} {v.get('unit', '')}".rstrip() for v in params.values()], "",
              "Before printing", *[f"  - {x}" for x in meta.get("assumptions", [])], "",
              "Files: .stl to slice and print, .step to open and edit in Fusion 360 / Onshape / FreeCAD, model.py is the source.",
              f"Built {today} for the SmartMotion Dashboard."]
    (outdir / "README.txt").write_text("\n".join(readme) + "\n")
    zpath = outdir / f"{a.slug}-{version}.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(outdir.iterdir()):
            if f.suffix in (".stl", ".step") or f.name in ("model.py", "README.txt"):
                z.write(f, f"{a.slug}-{version}/{f.name}")

    vrec = {"v": version, "date": today, "changes": a.changes or ("First version" if version == "v1" else ""),
            "parts": part_info, "zip": f"designs/{a.slug}/{version}/{a.slug}-{version}.zip",
            "preview": f"designs/{a.slug}/{version}/preview.png", "view": f"designs/{a.slug}/{version}/view.json",
            "source": f"designs/{a.slug}/{version}/model.py"}
    shared = {k: meta[k] for k in ("title", "category", "summary", "purpose", "print", "steps", "learning", "assumptions", "origin") if k in meta}
    shared["params"] = [{"key": k, **v} for k, v in params.items()]
    if entry is None:
        n = max([int(e["id"].split("-")[1]) for e in reg] or [0]) + 1
        entry = {"id": f"PD-{n:03d}", "slug": a.slug, "status": meta.get("status", "ready_to_print"),
                 "notes": "", "print_log": [], "versions": []}
        reg.append(entry)
    entry.update(shared)
    entry["versions"] = [v for v in entry["versions"] if v["v"] != version] + [vrec]
    entry["current"] = version
    entry["updated"] = today
    reg_path.write_text(json.dumps(reg, ensure_ascii=False, indent=2) + "\n")

    for q in part_info:
        fit = ", ".join(PRINTERS[k][0] for k, ok in q["fits"].items() if ok) or "NO printer (too big)"
        print(f"{q['name']}: {q['dims_mm']} mm, ~{int(q['est_g'])} g, {q['triangles']} triangles, "
              f"{'watertight' if q['watertight'] else 'NOT WATERTIGHT'}, fits: {fit}")
    print(f"Built {entry['id']} {a.slug} {version} -> {outdir.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
