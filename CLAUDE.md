# SmartMotion — project memory

SmartMotion is Sam Jones's UK business around a self-built 6-DOF full-motion flight/driving simulator (Great Dunmow, Essex; currently "A Skysmart MRO Ltd Company"). Priority: paid **experiences** (gift vouchers on sale 30 Nov 2026; first paying riders March 2027). Simulator sales and the custom sim are **parked**. 3D printing is a placeholder awaiting Sam's documents.

This repo is the **single source of truth**: Markdown knowledge base in `docs/`, live status in `data/*.json`, and a read-only dashboard at `dashboard/index.html` (GitHub Pages).

## Layout
- `docs/brief.md` — the original kickoff brief (historical; don't edit status here)
- `docs/{business,compliance,operations,product,3d-printing,marketing}/` — topic docs
- `docs/source/` — original PDFs/files, unchanged
- `data/` — `tasks`, `contacts`, `licences`, `documents`, `decisions`, `milestones`, `changelog` (.json)
- `dashboard/index.html` — single file, no build step, fetches `../data/*.json`

## Data conventions
- Every record has `id`, `status`, `updated` (YYYY-MM-DD). Dates are ISO.
- Task `status`: `todo` | `in_progress` | `waiting` | `done` | `parked`.
- Task `area`: Admin, Finance, Legal, Insurance, Safety, Software, Engineering, Operations, Sales, Website, Marketing, Events, Launch, 3D Printing, Product Sales.
- Task IDs: `D-` done before repo, `W1-`..`W4-` November weeks, `P-` before first rider, `F-` parked/future. New tasks: next free number in the right prefix.
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
- Validate JSON before committing: `for f in data/*.json; do python3 -m json.tool "$f" >/dev/null || echo "BAD $f"; done`
- Preview locally: `python3 -m http.server` in the repo root, open `http://localhost:8000/dashboard/`.

## Rules
- Keep everything factual; mark assumptions clearly (e.g. P- task due dates are assumed 28 Feb 2027).
- **Never mark a compliance item (ADIPS, insurance, licences, legal) done without Sam's explicit confirmation.**
- Nothing paid runs until ADIPS DOC + insurance. Never charge on consumer-licensed software. Advertise by experience type, not game/aircraft brand names.
- The GitHub Pages site is public if enabled on a public repo: don't put anything private (personal phone numbers, quotes, prices paid) in `data/` without Sam's OK.
