# SmartMotion

Knowledge base and launch dashboard for **SmartMotion** — 6-DOF full-motion flight and driving simulator experiences, Great Dunmow, Essex.

- **Dashboard:** `dashboard/index.html` — tasks, go-live gates, contacts, licences, documents, decisions and recent changes.
- **Knowledge base:** `docs/` (start with [`docs/brief.md`](docs/brief.md)).
- **Data:** `data/*.json` — the dashboard reads these; edit them (or ask Claude Code) to update it.

## Open the dashboard

**Private link (use this):** https://claude.ai/artifact/2UtrL6HCXVmKdrYJavCaME
Only you can open it (sign in to claude.ai). Works on any device. Claude Code republishes it whenever the data changes.

GitHub Pages isn't used because the repo is private and Pages on a private repo needs a paid GitHub plan (and would still publish the site openly).

### Locally
```bash
python3 -m http.server   # from the repo root
# then open http://localhost:8000/dashboard/
```
Opening `dashboard/index.html` straight from disk won't work, because browsers block it from reading the JSON files.

## Updating
Tell Claude Code what changed ("W1-01 sent today", "booked Rundle for 3 Dec", "here's the business plan PDF"). It updates `data/`, the change log and the docs, then commits. See [`CLAUDE.md`](CLAUDE.md) for conventions.
