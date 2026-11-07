# SmartMotion — project memory

SmartMotion is Sam Jones's UK business around a self-built 6-DOF full-motion flight/driving simulator (Great Dunmow, Essex; currently "A Skysmart MRO Ltd Company"). Priority: paid **experiences** (gift vouchers on sale 30 Nov 2026; first paying riders March 2027). Simulator sales and the custom sim are **parked**. 3D printing is a placeholder awaiting Sam's documents.

This repo is the **single source of truth**: Markdown knowledge base in `docs/`, live status in `data/*.json`, and a read-only dashboard at `dashboard/index.html` (GitHub Pages).

## Layout
- `docs/brief.md` — the original kickoff brief (historical; don't edit status here)
- `docs/{business,compliance,operations,product,3d-printing,marketing}/` — topic docs
- `docs/source/` — original PDFs/files, unchanged
- `data/` — `tasks`, `contacts`, `licences`, `documents`, `decisions`, `milestones`, `changelog`, `glossary` (.json)
- `dashboard/index.html` — single file, no build step, fetches `../data/*.json`
- `dashboard/games/` — games that open full-screen over the dashboard (see `docs/games/`)
- `scripts/build-artifact.sh` — builds the private claude.ai copy of the dashboard into `build/artifact/`

## Data conventions
- Every record has `id`, `status`, `updated` (YYYY-MM-DD). Dates are ISO.
- Task `status`: `todo` | `in_progress` | `waiting` | `done` | `parked`.
- Task `area`: Admin, Finance, Legal, Insurance, Safety, Software, Engineering, Operations, Sales, Website, Marketing, Events, Launch, 3D Printing, Product Sales.
- Task IDs: `D-` done before repo, `W1-`..`W4-` November weeks, `P-` before first rider, `F-` parked/future. New tasks: next free number in the right prefix.
- Every open task has a `why`: one or two plain-English sentences on why it matters, written for someone hands-on but not business- or tech-minded. Add one to every new task.
- `data/glossary.json` holds plain explanations of jargon (`term`, `meaning`). The dashboard underlines those terms wherever they appear; add new jargon there.
- Gates (`type: "gate"`) also have a plain `why`.
- `depends_on` lists task IDs; `links` may hold URLs, repo paths (`docs/...`) or IDs (`DEC-..`, task IDs).
- Decisions: `DEC-nn` open questions, `DEC-Pn` agreed working principles. Set `status: "decided"` and fill `decision` when Sam decides.
- Milestones: `type: "date"` (countdowns) and `type: "gate"`. A gate shows as met when **all** its `tasks` are `done` (computed by the dashboard).
- Contacts `status`: `not_contacted` | `contacted` | `replied` | `quoted` | `engaged` | `declined` | `n/a`.
- Licences `status`: `to_buy` | `to_request` | `requested` | `to_confirm` | `optional` | `available` | `bought` | `signed` | `not_usable`.
- Documents `status`: `awaiting_upload` | `draft` | `in_repo`.

## Workflow
- **Git:** Sam wants every change committed and pushed straight to `main` (no feature branches or pull requests).
- **Sam reports progress:** update the record(s) (status, notes, `updated`), add an entry at the end of `data/changelog.json` (`{date, summary, ids}`), commit with a clear message, push.
- **Sam uploads a document:** put the original in `docs/source/`, summarise it into the right topic doc, add any new tasks/contacts/decisions to `data/`, update `data/documents.json`, log it.
- **Republish the dashboard after any change to `data/` or `dashboard/`:** run `scripts/build-artifact.sh`, then publish `build/artifact/index.html` with the Artifact tool, `url` = https://claude.ai/artifact/2UtrL6HCXVmKdrYJavCaME, and `files` mapping each `data/<name>.json` to `build/artifact/data/<name>.json` (plus `assets/logo.png` and `assets/logo-dark.png` when the logo changes). (`build/` is gitignored.) The repo is private, so GitHub Pages isn't available.
- Validate JSON before committing: `for f in data/*.json; do python3 -m json.tool "$f" >/dev/null || echo "BAD $f"; done`
- Preview locally: `python3 -m http.server` in the repo root, open `http://localhost:8000/dashboard/`.

## Printing & Design (3D models)
- Sam prints on an Anycubic Kobra 3 (250×250×260 mm) and Kobra 3 Max (420×420×500 mm). Deliver STL + STEP for every design. Details: `docs/3d-printing/README.md`.
- New design: create `designs/<slug>/model.py` (copy the pattern of an existing one: `META`, `PARAMS`, `build(p)` returning `{part: cadquery shape}`), then `python3 scripts/build_design.py <slug>`. The build needs `pip install cadquery trimesh matplotlib` and uses Playwright + `scripts/render_preview.js` for the preview picture.
- Change to an existing design: edit `model.py`, then `python3 scripts/build_design.py <slug> --changes "what changed"`. This makes the next version and keeps the old ones.
- Always look at the preview PNG before publishing, and check the build output says every part is watertight and fits a printer.
- Sam's own uploads: put the files in `designs/<slug>/<version>/`, add a `data/designs.json` entry by hand (`origin: "Sam"`), and make a preview with the render script.
- Print feedback: update `status` and add to `print_log` in `data/designs.json`. Write lessons in plain English; the section is also for learning.
- Republishing: the build script copies `designs/**/{preview.png,view.json,*.zip}` into `build/artifact/` and lists them in `build/artifact/files.json`. Pass all of them in `files` when publishing (with `capabilities: {downloads: true}` kept).

## Games
- Each game is one JS file in `dashboard/games/` that exposes `window.<Name>.open({onClose})`, `close()` and `stats()`, injects its own scoped CSS, and draws with canvas/SVG (no libraries).
- Register it in the dashboard: an entry in `VIEWS` with `g:"Games"`, a tile in `renderGames()`, and a `<script src="games/<file>.js">` tag. The build script inlines `games/*.js` into the private page automatically.
- Save progress in `localStorage` under an `sm2:` key, wrapped in try/catch.

## Rules
- The dashboard's name is always **SmartMotion Dashboard** (page title, gallery name, and how to refer to it).
- Branding: SmartMotion logo (`dashboard/assets/`), navy #02022F and orange #FF4C00. Orange is the brand accent; amber is kept only for "waiting"/"due soon" warnings.
- Dashboard wording is plain English for a practical, non-technical reader: say what to do and why, avoid business and tech jargon (or add it to the glossary), keep it professional.
- Keep everything factual; mark assumptions clearly (e.g. P- task due dates are assumed 28 Feb 2027).
- **Never mark a compliance item (ADIPS, insurance, licences, legal) done without Sam's explicit confirmation.**
- Nothing paid runs until ADIPS DOC + insurance. Never charge on consumer-licensed software. Advertise by experience type, not game/aircraft brand names.
- Keep the repo private: it holds contacts and business documents.
