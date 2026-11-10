# SmartMotion Flight: the native Windows version

The same game as the browser version (`docs/games/smartmotion-flight.md`), rebuilt in the **Godot 4.6** engine so it runs as a normal Windows program on the PC's graphics card. Source: `godot/`. Since v1.5.0 the world is the **real Duxford area** built from free open data (see "Real world" below); aircraft, signs and sky are still made in code, and the only other outside files are the Barlow fonts (SIL Open Font Licence) and CC0 textures from ambientCG.

## Getting it
- Built automatically by GitHub Actions (`.github/workflows/build-native.yml`) whenever `godot/` changes on `main`, and published as the **native-latest** release: https://github.com/jamsconesfku/Smartmotion-Repo/releases/tag/native-latest (the repo is private, so sign in to GitHub first). Download `SmartMotionFlight-Windows.zip`, unzip, run `SmartMotionFlight.exe`. The zip's `README.txt` has the steps.
- Windows shows a "Windows protected your PC" screen because the program isn't code-signed: More info > Run anyway.
- Build locally: `GODOT=/path/to/Godot_v4.6.1 scripts/build-native.sh` (needs the matching export templates).

## What's better than the browser version
Forward+ renderer (Vulkan): real-time soft sun shadows across the whole scene, ambient occlusion, bloom, filmic tone mapping, 4x anti-aliasing, a much sharper 4096-pixel painted ground map, GPU-displaced terrain, instanced houses and trees with distance culling, Barlow brand fonts, and a fallback "compatibility" mode (`Play (compatibility mode).bat`) for older graphics cards.
The flight model is the same physics ported line for line (`godot/scripts/flight_model.gd`), checked by `godot/tests/test_flight.gd` (takeoff, climb, level flight, turns, stalls, landing, stopping), which also runs in the build.

## VR (Meta Quest 3)
OpenXR through **Meta Quest Link** (cable) or Air Link: in the Quest Link app set it as the active OpenXR runtime, start Link, then press "Fly in VR" (or `Play (VR - Meta Quest).bat`). Controls: right stick pitch/roll, right trigger/grip more/less power, left stick power/rudder, left trigger brakes, A flaps, B recentre, X pause, Y restart. The keyboard works in VR too (WASD to fly, Shift/Ctrl power); the game brings its window to the front when VR starts and shows a message if the keyboard isn't reaching it. The desktop window mirrors the view and shows the pause menu. First tested on Sam's Quest 3 on 9 Nov 2026: VR works, but flying was hard to control, which led to the v1.4.0 control changes. Still to tune: seat position, comfort and frame rate.

## The aircraft: Skysmart's Bulldog (v1.6.0)
You now fly **Skysmart's own Scottish Aviation Bulldog**: G-SMAT, ex-RAF XX658 (built 1974, Cambridge University Air Squadron, code 07; Skysmart's since October 2019, flown from Duxford). It replaces the made-up light trainer; the WW2 fighter stays as the second choice. Built in code in `godot/scripts/bulldog.gd`:
- **Shape from the real dimensions**: span 10.06 m, length 7.09 m, height 2.28 m, wing area 12.02 m², tapered wing (1.45 m root to 0.95 m tip chord) with a proper aerofoil and 6° dihedral, boxy side-by-side fuselage, sliding bubble canopy with frames, swept fin, fixed tricycle gear, two-blade 1.88 m Hartzell propeller (black, yellow tips). Ailerons, elevator, rudder and flaps move.
- **Flight model** (`bulldog` in `flight_model.gd` and `flightmodel.js`): 1,000 kg, 200 hp Lycoming IO-360, clean stall about 55 kt, top speed about 130 kt, crisp aerobatic roll. Passes all physics checks.
- **Livery**: RAF light-trainer style (white upper, light grey under, signal-red bands and tips, black anti-glare panel, type D roundels, fin flash, serial XX658, code 07). **Assumption**: we found no clear photo of G-SMAT's current paint; send photos and we'll match it exactly.
- **Cockpit, built for VR**: a 3D panel at real scale with live round gauges (airspeed with the Bulldog's arcs, attitude, altimeter, turn coordinator, heading, vertical speed, g-meter with max/min, RPM, manifold pressure, oil, fuel, CHT, amps, clock), each behind its own bezel and glass so they have depth in the headset; radios, switches, magneto key, annunciators and placards; glare shield and compass; two control sticks that move with your inputs, rudder pedals, throttle/propeller/mixture levers, trim wheel, flap lever and fuel selector; bucket seats, side lining, canopy frames and the propeller arc in front. An instructor sits in the right-hand seat and looks around. The panel is drawn at 1,800 pixels per metre and updates every frame so the needles move smoothly in VR.

## Real world (v1.5.0)
A 32.8 km square centred on the middle of Duxford's hard runway (real heading 058 true, 1,448 m), made by `scripts/build_world_data.py` into `godot/assets/world/` (re-run it to refresh; needs `pip install rasterio pyproj numpy pillow duckdb shapely requests`, about 5 minutes):
- **Ground heights**: Copernicus DEM GLO-30 (`height.bin`, 1024 x 1024, 32 m), smoothed (it is a surface model, so woods and roofs are bumps), the airfield flattened at 33.5 m, the edges faded so the map can repeat.
- **Ground photo**: Copernicus Sentinel-2, 7 July 2023, six passes stitched (`ortho.jpg`, 4096 px, about 8 m a pixel), colour-corrected for a game. Pick another day with `S2_DAY=YYYY-MM-DD`.
- **Land cover**: ESA WorldCover 2021 (`landcover.png`: red trees, green built-up, blue water, alpha grassland). Drives the close-up textures, the shiny river and where trees grow.
- **Buildings**: 129,117 real footprints and heights from Overture Maps (OpenStreetMap and others) (`buildings.bin`), including the real Duxford hangars (the made-up hangars are gone). Houses get pitched roofs; walls are brick, render or metal cladding with windows; roofs take their colour from the satellite photo. Crash checks use the real buildings near the aircraft.
- **Trees**: one tree per 8 m woodland pixel, streamed in 1 km squares: a detailed tree up to 1.3 km, a simple one to 4 km, the photo beyond.
- **Close-up ground**: ambientCG CC0 grass, soil, tarmac and concrete photo textures with normal maps, mixed into the satellite colour within about 2 km so the ground has grain and bumps when low.
- Beyond the real square the old painted countryside carries on to the horizon.
- Licences and the credits we must show: `data/licences.json` LIC-10 to LIC-14; the credits are on the game's Controls screen and in the download's README.

## 3D clouds (v1.5.0)
`shaders/clouds_volumetric.gdshader`: a full-screen raymarch through a cloud layer 950 to 2,300 m up, shaped by a weather map and 3D noise (made in code by Godot's noise generator), lit with sun absorption, dark bases and silver edges towards the sun. Clouds drift with the wind and cast moving shadows on the ground. The scene's depth hides clouds behind hills and buildings. Used on Medium/High with the Forward+ renderer; VR, Low and compatibility mode use the lighter cloud cards.

## Performance (RTX 4060 target)
High: about 1 M triangles of nearby trees, about 2 M of far trees, 16,000 buildings within 7 km, 72 cloud steps a pixel. If it drops below 60 fps, use Medium (fewer trees, shorter range, 44 cloud steps). In VR the 3D clouds, SSAO and SSIL are switched off. Load with `--stats` (after `--`) to log triangles, draw calls and fps every two seconds in the diagnostics log.

## Controls and Easy mode (v1.4.0)
Keyboard: W/S nose down/up, A/D bank to turn (arrow keys also work), Shift/Ctrl power (now 0 to full in about a second, was about three), Q/E rudder, Space brakes, F flaps. In **Easy** mode (the default) the game sets full power when a flight starts on the runway, so the aircraft speeds up by itself and you just hold S at the speed shown to lift off; once airborne it holds the wings level and the height for you.

## Graphics (v1.4.0)
Puffy cumulus clouds (four cloud shapes painted once by `shaders/cloud_paint.gdshader`, drawn by `shaders/cloud.gdshader` with bright tops, grey bases and glowing edges towards the sun), wispy high cloud and a richer sky with a proper sun glow (`shaders/sky.gdshader`), broadleaf and conifer trees with soft shading, plus about 3,200 single trees, hedgerow lines and copses across the farmland, ground detail at three scales and a shiny river, light bouncing between nearby surfaces (SSIL, High quality only, off in VR), soft sun shadows, aerial haze that takes on the sky colour, and 16x texture filtering.

## Motion rig link
Settings > Motion rig > On sends the same JSON frame as the browser version (see `docs/games/smartmotion-flight.md` for the fields) over **UDP** (default `127.0.0.1:4123`, 60 per second), straight from the game, so no bridge program is needed. Point the rig adapter at that port. An adapter for FlyPT Mover / the Motion4Sim controller still needs writing once the rig's input format is confirmed.

## Layout of `godot/`
`scripts/`: `main.gd` (controller, input, cameras, VR), `flight_model.gd`, `terrain.gd`, `world.gd` (sky, ground, Duxford, signs, scenery), `aircraft_model.gd` + `instruments.gd` (aircraft and cockpit), `ui.gd` (menus, HUD), `telemetry.gd`, `synth.gd` (sound), `settings.gd`. `shaders/`: ground painting, ground, sky. `assets/`: logos, fonts. `package/`: files added to the download. `tests/`: physics checks.

Test options (after `--` on the command line): `--auto` (skip the menu), `--aircraft=fighter`, `--mode=gates`, `--start=air`, `--tod=golden`, `--cam=cockpit`, `--q=low|medium|high`, `--vr`, `--telemetry=host:port`, `--shot=file.png --shot_after=6` (save a screenshot and quit).

## Not yet
Higher-resolution aerial photos near the airfield (Sentinel-2 is 10 m), roads as 3D strips, real aircraft models, proper weather, a rig adapter, code signing for the .exe, and testing on the MSI laptop and Quest 3.
