# SmartMotion

Knowledge base and launch dashboard for **SmartMotion** — 6-DOF full-motion flight and driving simulator experiences, Great Dunmow, Essex.

- **Dashboard:** `dashboard/index.html` — tasks, go-live gates, contacts, licences, documents, decisions and recent changes.
- **Knowledge base:** `docs/` (start with [`docs/brief.md`](docs/brief.md)).
- **Data:** `data/*.json` — the dashboard reads these; edit them (or ask Claude Code) to update it.

## Open the dashboard

### On GitHub Pages (any device, including your phone)
1. On GitHub, open the repo → **Settings** → **Pages**.
2. Under **Build and deployment**, set **Source** to *Deploy from a branch*, **Branch** to `main` and folder `/ (root)`. Save.
3. After a minute the site is at `https://jamsconesfku.github.io/Smartmotion-Repo/` (it redirects to the dashboard).

Notes: the branch must be merged into `main` first. GitHub Pages on a **private** repo needs a paid GitHub plan, and a Pages site is publicly visible either way.

### Locally
```bash
python3 -m http.server   # from the repo root
# then open http://localhost:8000/dashboard/
```
Opening `dashboard/index.html` straight from disk won't work, because browsers block it from reading the JSON files.

## Updating
Tell Claude Code what changed ("W1-01 sent today", "booked Rundle for 3 Dec", "here's the business plan PDF"). It updates `data/`, the change log and the docs, then commits. See [`CLAUDE.md`](CLAUDE.md) for conventions.
