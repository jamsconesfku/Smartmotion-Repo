#!/usr/bin/env bash
# Builds the private claude.ai copy of the dashboard into build/artifact/.
# Same page as dashboard/index.html, but it reads data/ next to itself.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/artifact
rm -rf "$out" && mkdir -p "$out/data"
cp data/*.json "$out/data/"
python3 - "$out/index.html" <<'PY'
import re, sys
s = open("dashboard/index.html", encoding="utf-8").read()
s = s.replace('const DATA = "../data/";', 'const DATA = "data/";')
# The artifact host adds its own document skeleton.
s = re.sub(r'<!doctype html>\s*<html[^>]*>\s*<head>\s*', '', s, flags=re.I)
s = re.sub(r'<meta charset[^>]*>\s*<meta name="viewport"[^>]*>\s*', '', s)
s = re.sub(r'</head>\s*<body>\s*', '', s)
s = re.sub(r'</body>\s*</html>\s*$', '', s)
open(sys.argv[1], "w", encoding="utf-8").write(s)
PY
echo "Built $out"
