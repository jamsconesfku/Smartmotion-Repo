#!/usr/bin/env node
// Builds the SmartMotion Dashboard website into dist/ (what Cloudflare Pages serves).
//   Cloudflare Pages settings:  build command  node scripts/build-site.mjs   output directory  dist
//   Local check:                node scripts/build-site.mjs && python3 -m http.server -d dist 8788
// No dependencies. Only the folders listed below reach the internet: nothing from docs/ (business plan,
// PDFs) or the design source code is published.
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dist = join(root, "dist");
const fail = (msg) => { console.error("BUILD FAILED: " + msg); process.exit(1); };

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });

// 1. The page. In the repo it sits one folder below data/, on the site it sits beside it.
let html = readFileSync(join(root, "dashboard", "index.html"), "utf8");
for (const [from, to] of [['const DATA = "../data/";', 'const DATA = "data/";'], ['const ROOT = "../";', 'const ROOT = "";']]) {
  if (!html.includes(from)) fail(`dashboard/index.html no longer contains: ${from}`);
  html = html.replace(from, to);
}
writeFileSync(join(dist, "index.html"), html);
for (const d of ["assets", "games"]) cpSync(join(root, "dashboard", d), join(dist, d), { recursive: true });
cpSync(join(root, "dashboard", "manifest.webmanifest"), join(dist, "manifest.webmanifest"));
cpSync(join(root, "site"), dist, { recursive: true });            // _headers, robots.txt

// 2. The plan data. A broken file would give a blank site, so stop the deploy instead.
cpSync(join(root, "data"), join(dist, "data"), { recursive: true });
for (const f of readdirSync(join(dist, "data"))) {
  try { JSON.parse(readFileSync(join(dist, "data", f), "utf8")); } catch (e) { fail(`data/${f} is not valid JSON (${e.message})`); }
}

// 3. 3D models: preview, 3D view, ZIP, STL, STEP for every version.
const keep = (name) => name === "preview.png" || name === "view.json" || [".zip", ".stl", ".step"].includes(extname(name));
const designsDir = join(root, "designs");
if (existsSync(designsDir)) {
  for (const slug of readdirSync(designsDir)) {
    const sdir = join(designsDir, slug);
    if (!statSync(sdir).isDirectory()) continue;
    for (const ver of readdirSync(sdir)) {
      const vdir = join(sdir, ver);
      if (!statSync(vdir).isDirectory()) continue;
      for (const f of readdirSync(vdir)) {
        if (!keep(f)) continue;
        mkdirSync(join(dist, "designs", slug, ver), { recursive: true });
        cpSync(join(vdir, f), join(dist, "designs", slug, ver, f));
      }
    }
  }
}

// 4. Every file the library points at must exist, or a model page would have broken downloads.
const designs = JSON.parse(readFileSync(join(dist, "data", "designs.json"), "utf8"));
let files = 0;
for (const d of designs) for (const v of d.versions) {
  const need = [v.preview, v.view, v.zip, ...v.parts.flatMap((p) => [p.stl, p.step])];
  for (const f of need) { files++; if (!existsSync(join(dist, f))) fail(`${d.id} ${v.v} refers to ${f} but it is missing`); }
}

const size = (dir) => readdirSync(dir, { withFileTypes: true }).reduce((n, e) => n + (e.isDirectory() ? size(join(dir, e.name)) : statSync(join(dir, e.name)).size), 0);
console.log(`Built dist/ (${(size(dist) / 1048576).toFixed(1)} MB): ${designs.length} models, ${files} model files checked.`);
