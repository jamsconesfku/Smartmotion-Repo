# SmartMotion

Knowledge base and the **SmartMotion Dashboard** for SmartMotion — 6-DOF full-motion flight and driving simulator experiences, Great Dunmow, Essex.

- **Dashboard:** `dashboard/index.html` — tasks, go-live gates, contacts, licences, documents, decisions and recent changes.
- **Knowledge base:** `docs/` (start with [`docs/brief.md`](docs/brief.md)).
- **Data:** `data/*.json` — the dashboard reads these; edit them (or ask Claude Code) to update it.

## Open the SmartMotion Dashboard

It's a website hosted on Cloudflare Pages: **https://smartmotion-dashboard.pages.dev** (once set up; steps in [`docs/deploy-cloudflare.md`](docs/deploy-cloudflare.md)). Every push to `main` redeploys it automatically.

### Locally
```bash
node scripts/build-site.mjs && python3 -m http.server -d dist 8788
# then open http://localhost:8788
```
You can also run `python3 -m http.server` in the repo root and open `/dashboard/`.

## Updating
Tell Claude Code what changed ("W1-01 sent today", "booked Rundle for 3 Dec", "here's the business plan PDF"). It updates `data/`, the change log and the docs, then commits. See [`CLAUDE.md`](CLAUDE.md) for conventions.
