# SmartMotion — project memory

SmartMotion is Sam Jones's UK business around a self-built 6-DOF full-motion flight/driving simulator (Great Dunmow, Essex; currently "A Skysmart MRO Ltd Company"). Priority: paid **experiences** (gift vouchers on sale 30 Nov 2026; first paying riders March 2027). Simulator sales and the custom sim are **parked**. 3D printing is a placeholder awaiting Sam's documents.

This repo is the **single source of truth**: Markdown knowledge base in `docs/`, live status in `data/*.json`, and a read-only dashboard website at `dashboard/index.html`, deployed to Cloudflare Pages from `main` (`.pages.dev`).

## Layout
- `docs/brief.md` — the original kickoff brief (historical; don't edit status here)
- `docs/{business,compliance,operations,product,3d-printing,marketing}/` — topic docs
- `docs/source/` — original PDFs/files, unchanged
- `data/` — `tasks`, `contacts`, `licences`, `documents`, `decisions`, `milestones`, `changelog`, `glossary` (.json)
- `dashboard/index.html` — single file, no build step, fetches `../data/*.json`
- `dashboard/games/` — games that open full-screen over the dashboard (see `docs/games/`)
- `godot/` — the native Windows game (Godot project); `motion/` — SmartMotion Motion, our motion software for the rig; `dashboard/fly/` — the old browser version (kept in the repo, not published)
- `scripts/build-site.mjs` — builds the website into `dist/` (Cloudflare Pages: build command `node scripts/build-site.mjs`, output `dist`); `site/` holds root files (`_headers`, `robots.txt`); `docs/deploy-cloudflare.md` has the setup steps

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
- **Deploying:** pushing to `main` is the deploy; Cloudflare Pages runs `scripts/build-site.mjs`. Before pushing, run it locally and check it prints `Built dist/` (it fails on broken JSON or missing model files). The old private claude.ai copy is retired and no longer updated.
- Validate JSON before committing: `for f in data/*.json; do python3 -m json.tool "$f" >/dev/null || echo "BAD $f"; done`
- Preview locally: `node scripts/build-site.mjs && python3 -m http.server -d dist 8788`, open `http://localhost:8788`.

## Printing & Design (3D models)
- Sam prints on an Anycubic Kobra 3 (250×250×260 mm) and Kobra 3 Max (420×420×500 mm). Deliver STL + STEP for every design. Details: `docs/3d-printing/README.md`.
- New design: create `designs/<slug>/model.py` (copy the pattern of an existing one: `META`, `PARAMS`, `build(p)` returning `{part: cadquery shape}`), then `python3 scripts/build_design.py <slug>`. The build needs `pip install cadquery trimesh matplotlib` and uses Playwright + `scripts/render_preview.js` for the preview picture.
- Change to an existing design: edit `model.py`, then `python3 scripts/build_design.py <slug> --changes "what changed"`. This makes the next version and keeps the old ones.
- Always look at the preview PNG before publishing, and check the build output says every part is watertight and fits a printer.
- Sam's own uploads: put the files in `designs/<slug>/<version>/`, add a `data/designs.json` entry by hand (`origin: "Sam"`), and make a preview with the render script.
- Print feedback: update `status` and add to `print_log` in `data/designs.json`. Write lessons in plain English; the section is also for learning.
- Deploying designs: the site build copies each version's `preview.png`, `view.json`, ZIP, STL and STEP from `designs/`. Commit those outputs with `data/designs.json`; `model.py` and `README.txt` stay in the repo only.

## SmartMotion Flight, browser version (`dashboard/fly/`, no longer published)
- The first version of the game. Since v1.7.1 the website doesn't serve it (the build no longer copies `fly/` or `vendor/`); the Games tile gives the Windows download instead. The code stays in the repo because `flightmodel.js` is the reference for the physics: keep it in step with `flight_model.gd` and run `node scripts/test-flight.mjs` after changing it. Notes: `docs/games/smartmotion-flight.md`.

## SmartMotion Flight, native Windows version (`godot/`)
- Godot 4.6.1 project, same game as `fly/` but on the GPU. Notes: `docs/games/smartmotion-flight-native.md`. Built by `.github/workflows/build-native.yml` into the `native-latest` GitHub release; local build `GODOT=... scripts/build-native.sh`.
- Get Godot in a fresh session: download `Godot_v4.6.1-stable_linux.x86_64.zip` and `Godot_v4.6.1-stable_export_templates.tpz` from `github.com/godotengine/godot-builds/releases/download/4.6.1-stable/` (github.com release downloads work; tuxfamily mirrors don't), unzip the templates into `~/.local/share/godot/export_templates/4.6.1.stable/`. For screenshots install `mesa-vulkan-drivers xvfb` and run `xvfb-run godot --path godot --rendering-driver vulkan -- --q=low --auto --shot=out.png --shot_after=6` (see the options in the doc).
- The native game's world is the real Duxford area (v1.5.0): `terrain.gd` loads real heights and the real runway heading (058, 1,448 m), so it no longer matches the browser version's made-up terrain; keep `flight_model.gd` / `flightmodel.js` in step. World data is made by `scripts/build_world_data.py` into `godot/assets/world/` (licences LIC-10..14; credits must stay on the Controls screen and in `godot/package/README.txt`). Since v1.15.0 an 8 km square round the runway has UK open data (Environment Agency LIDAR, OS OpenMap Local; LIC-15/16, Open Government Licence): `python3 scripts/build_uk_detail.py` makes `detail_h.png`, `detail_photo.jpg`, `detail_mask.png`, `trees.bin` and redoes `height.bin` from `height_copernicus.bin` (downloads to `~/ukdata`; needs network access to environment.data.gov.uk, api.os.uk and omseprd1stdstordownload.blob.core.windows.net); `--normals-only` remakes `detail_n.png`. Since v1.17.0 `python3 scripts/build_urban.py` makes `urban.png` (towns, roads, building density over the 32 km map, OS open data), and vehicles get their real-world surfaces from `scripts/vehicle_look.gd` (ambientCG CC0 textures `assets/textures/veh_*`, made by `scripts/make_vehicle_textures.py`; needs ambientcg.com and acg-download.struffelproductions.com).
- After changing `flight_model.gd` or `terrain.gd` (or `flightmodel.js` / `terrain.js`) run the physics checks: `godot --headless --path godot --script res://tests/test_flight.gd` and `node scripts/test-flight.mjs`.
- Since v1.8.0 the program holds three games picked at the top of the menu: Flight (Duxford), Racing (`race_*.gd`) and Space (`space_*.gd`), sharing `game_mode.gd`; in VR the real menus float on a panel (`vr_panel.gd`). After changing the racing car or circuit run `godot --headless --path godot --script res://tests/test_race.gd`; after changing the menus or VR panel run `godot --headless --path godot -- --test_panel`. The game acts as X-Plane 11 on UDP 49000 so FlyPT Mover's "X-Plane 11 (UDP)" source reads it (`xplane_link.gd`, v1.11.0); after changing it or the telemetry frame run `godot --headless --path godot --script res://tests/test_xplane.gd`. Call the car an "open-wheel racing car", not F1. Since v1.12.0 it is one world: the racing circuit sits on real farmland 2.5 km west of the runway (`RaceTrack.OFFSET`, heights from the real ground) and it and the coaster are built at load and stay parked in the world, so Flight flies over them; only Space has its own world. Test option `--switch_test[=race,flight]` goes between games through the menu. Graphics (v1.13.0): quality `low|medium|high|ultra` ("ultra" = high plus `World.ultra` / `RealScenery.set_extent` extras), `view` near/normal/far, `clouds3d`; `assets/world/roofmask.png` (made by `python3 -I scripts/build_roof_mask.py` after changing `buildings.bin`) lets the ground shader paint over the photo's roofs under the 3D buildings; trees use `shaders/tree.gdshader`. Since v1.16.0 Space has a spaceship that starts on Duxford's runway (`ship_earth_mode.gd`, game key `ship_earth`) and flies up into space (`space_mode.gd`, nine planets, hyperspeed); both extend `ship_mode.gd` and swap through `transfer` in `main.gd`; the cockpit's console buttons are pressed by a VR fingertip (`SpaceShip.touch`); after changing them run `godot --headless --path godot --script res://tests/test_ship.gd`. Since v1.9.0 the first screen asks how the simulator is set up (`stick`, `wheel`, `ride`, `all`; `GameUI.RIG_GAMES` says which games each shows) and there is a fourth game, the roller coaster (`coaster_mode.gd`, in the Duxford world; check with `tests/test_coaster.gd`). "Set up controls" learns a real joystick or wheel (`rig_map` in the settings).
- Controls (v1.19.0): every key and controller button lives in `godot/scripts/keys.gd` (class `Keys`); all input in `main.gd` reads `Keys`, and the Change keys screen, the Controls picture (`keyboard_pic.gd`) and the F1 list are drawn from it. **A new control must be added to `Keys.ACTIONS`**, never read as a fixed key. After changing controls run `godot --headless --path godot --script res://tests/test_keys.gd` and the live test `godot --headless --path godot -- --auto --key_test` (presses real keys while flying; about 10 s; both are part of `scripts/build-native.sh`). Screenshot options: `--ui_shot=<prefix>` (menus, Controls, Change keys, F1 list) and `--shot_look=yaw:pitch,...` (where the cockpit camera looks for each later picture).
- Headless: Godot never sends `RenderingServer.frame_post_draw` without a screen, so anything that waits for it hangs the world load. Guard it with `DisplayServer.get_name() == "headless"` (as in `world.gd`, `race_track.gd`, `space_mode.gd`); the "Parameter t is null" errors printed in headless runs are harmless.
- GDScript gotchas hit so far: lambdas capture variables by value (mutate a Dictionary instead), values read from Dictionaries are untyped (declare `var x: float = ...`), Godot front faces are clockwise.
- Bump `VERSION` for dashboard-visible changes; native releases are built from `main` automatically.
- **Download link** (always the newest build): `https://github.com/jamsconesfku/Smartmotion-Repo/releases/download/native-latest/SmartMotionFlight-Windows.zip`. When Sam asks for the latest download, check the latest `build-native.yml` run has finished successfully and that the `native-latest` release body names the newest commit on `main` that touched `godot/`, then give the link and the steps (they're on the dashboard Games tile and in `godot/package/README.txt`).

## FlyPT Mover profile (`godot/package/SmartMotion-Games.Mover`)
- Made from Sam's own profile (`docs/source/flypt-mover/`, DOC-08) by `scripts/mover/build.py`; never edit the `.Mover` by hand. Notes, the rig's geometry and how it was checked: `docs/games/flypt-mover-profile.md`.
- Before changing filters or limits, replay recorded game data through the model (`scripts/mover/replay.py`, data from the game's `--tel_dump` test option) and report the furthest actuator travel (150 mm is the half stroke). Sam chose to keep his own limits and rig gain (v2, 13 Nov 2026): change only the pose filters unless he asks. It has not been tried in Mover or on the rig: say so.
- The coaster adds extra roll and pitch rate for Mover only (`mover_cue` in its frame, `coaster_mode.gd` `_tel`; v1.19.3) so it moves the rig as much as the aircraft; `scripts/mover/compare.py` compares two recordings.

## SmartMotion Motion (`motion/`, replaces FlyPT Mover)
- Godot 4.6 project, exported as `SmartMotionMotion.exe` into the same Windows ZIP as the game (by `scripts/build-native.sh`, which also runs its checks). Notes and controller protocol: `docs/games/smartmotion-motion.md`.
- Game data in on UDP 4123; seat position out to the Motion4Sim controller in Position mode (36-byte packets, ~500/s) over USB (PowerShell helper `motion/assets/serial_bridge.ps1`, 250,000 baud) or network (UDP 53241, Pro licence); seat position back to the game on UDP 4124 for VR motion compensation (`godot/scripts/motion_comp.gd`).
- After changing `motion/scripts/cueing.gd` or `rig_link.gd` run `godot --headless --path motion --script res://tests/test_cueing.gd`. Motion4Sim's manual writes command numbers in cable order (low byte first): "0600" is command 0x0006.
- Safety: nothing moves the rig unless the operator connects, the controller is online and Motion is ON; pause, crash or lost data fade to the middle. Never raise the default limits without Sam checking the rig's real travel.

## Games
- Each game is one JS file in `dashboard/games/` that exposes `window.<Name>.open({onClose})`, `close()` and `stats()`, injects its own scoped CSS, and draws with canvas/SVG (no libraries).
- Register it in the dashboard: an entry in `VIEWS` with `g:"Games"`, a tile in `renderGames()`, and a `<script src="games/<file>.js">` tag. The site build copies `dashboard/games/` as is.
- Save progress in `localStorage` under an `sm2:` key, wrapped in try/catch.

## Versions
- `VERSION` (repo root) is the dashboard's version, shown under the logo as `v1.1.0 · <commit>` (`version.json` is made by the site build). Bump the **minor** number for a new feature or section, the **patch** number for a fix or design tweak. Data-only updates (tasks, contacts, models) don't need a bump: the commit id shown beside the version already tells each deploy apart.
- The badge beside it shows login status from Cloudflare Access: green "Signed in", red "No login protection" (Access isn't covering the address), grey "Local preview".

## Rules
- The dashboard's name is always **SmartMotion Dashboard** (page title, gallery name, and how to refer to it).
- Branding: SmartMotion logo (`dashboard/assets/`; run `python3 -I scripts/make_icons.py` after a logo change to refresh the phone icons), navy #02022F and orange #FF4C00. Orange is the brand accent; amber is kept only for "waiting"/"due soon" warnings.
- Dashboard wording is plain English for a practical, non-technical reader: say what to do and why, avoid business and tech jargon (or add it to the glossary), keep it professional.
- Keep everything factual; mark assumptions clearly (e.g. P- task due dates are assumed 28 Feb 2027).
- **Never mark a compliance item (ADIPS, insurance, licences, legal) done without Sam's explicit confirmation.**
- Nothing paid runs until ADIPS DOC + insurance. Never charge on consumer-licensed software. Advertise by experience type, not game/aircraft brand names.
- Keep the repo private: it holds contacts and business documents. The website lists contacts and the plan, so it should sit behind Cloudflare Access (see `docs/deploy-cloudflare.md`); never publish `docs/` or `docs/source/`.
