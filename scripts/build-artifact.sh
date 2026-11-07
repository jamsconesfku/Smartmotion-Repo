#!/usr/bin/env bash
# Builds the private claude.ai copy of the dashboard into build/artifact/.
# Same page as dashboard/index.html, but it reads data/ next to itself.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/artifact
rm -rf "$out" && mkdir -p "$out/data"
cp data/*.json "$out/data/"
cp -r dashboard/assets "$out/assets"
# Print & Design: previews, 3D views and download ZIPs (not the raw STL/STEP; those are inside the ZIPs)
if [ -d designs ]; then
  find designs -path '*/v*/*' \( -name preview.png -o -name view.json \) | while read -r f; do
    mkdir -p "$out/$(dirname "$f")"; cp "$f" "$out/$f"
  done
  # The private page can't host .zip/.stl/.step files, so each ZIP's contents go into a
  # .bundle.json (base64) and the page rebuilds the ZIP in the browser when Sam downloads.
  python3 - "$out" <<'PY'
import base64, glob, json, os, sys, zipfile
out = sys.argv[1]
for z in glob.glob("designs/*/v*/*.zip"):
    with zipfile.ZipFile(z) as zf:
        files = [{"path": n, "b64": base64.b64encode(zf.read(n)).decode()} for n in zf.namelist()]
    dst = os.path.join(out, z[:-4] + ".bundle.json")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    json.dump({"zip": os.path.basename(z), "files": files}, open(dst, "w"), separators=(",", ":"))
PY
fi
python3 - "$out/index.html" <<'PY'
import re, sys
s = open("dashboard/index.html", encoding="utf-8").read()
s = s.replace('const DATA = "../data/";', 'const DATA = "data/";')
s = s.replace('const ROOT = "../";', 'const ROOT = "";')
# Inline the games so the private page needs no extra script files.
def inline(m):
    js = open("dashboard/" + m.group(1), encoding="utf-8").read()
    return "<script>\n" + js + "\n</script>"
s = re.sub(r'<script src="(games/[^"]+\.js)"></script>', inline, s)
# The artifact host adds its own document skeleton.
s = re.sub(r'<!doctype html>\s*<html[^>]*>\s*<head>\s*', '', s, flags=re.I)
s = re.sub(r'<meta charset[^>]*>\s*<meta name="viewport"[^>]*>\s*', '', s)
s = re.sub(r'</head>\s*<body>\s*', '', s)
s = re.sub(r'</body>\s*</html>\s*$', '', s)
# Build the essentials into the page so it still works where the app blocks separate file requests
# (phones showed "tasks.json could not be loaded (403)"): plan data, logos, model preview pictures.
import base64, glob, json, os
inline = {}
for f in glob.glob("data/*.json"):
    inline[f.replace(os.sep, "/")] = json.load(open(f, encoding="utf-8"))
def uri(path):
    return "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()
for f in glob.glob("designs/*/v*/preview.png"):
    inline[f.replace(os.sep, "/")] = uri(f)
s = s.replace('src="assets/logo.png"', 'src="' + uri("dashboard/assets/logo.png") + '"')
s = s.replace('src="assets/logo-dark.png"', 'src="' + uri("dashboard/assets/logo-dark.png") + '"')
blob = json.dumps(inline, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
s = s.replace("<script>\n(function(){", "<script>window.__INLINE=" + blob + ";</script>\n<script>\n(function(){", 1)
open(sys.argv[1], "w", encoding="utf-8").write(s)
PY
python3 - "$out" <<'PY'
import json, os, sys
out = sys.argv[1]
files = {}
for d, _, fs in os.walk(out):
    for f in fs:
        rel = os.path.relpath(os.path.join(d, f), out)
        if rel not in ("index.html", "files.json"):
            files[rel] = os.path.join(out, rel)
json.dump(files, open(os.path.join(out, "files.json"), "w"), indent=1)
PY
echo "Built $out"
