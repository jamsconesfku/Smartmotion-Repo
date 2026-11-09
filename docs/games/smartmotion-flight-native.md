# SmartMotion Flight: the native Windows version

The same game as the browser version (`docs/games/smartmotion-flight.md`), rebuilt in the **Godot 4.6** engine so it runs as a normal Windows program on the PC's graphics card. Source: `godot/`. Everything is still made in code (no bought or downloaded art; only the Barlow fonts, which are free under the SIL Open Font Licence).

## Getting it
- Built automatically by GitHub Actions (`.github/workflows/build-native.yml`) whenever `godot/` changes on `main`, and published as the **native-latest** release: https://github.com/jamsconesfku/Smartmotion-Repo/releases/tag/native-latest (the repo is private, so sign in to GitHub first). Download `SmartMotionFlight-Windows.zip`, unzip, run `SmartMotionFlight.exe`. The zip's `README.txt` has the steps.
- Windows shows a "Windows protected your PC" screen because the program isn't code-signed: More info > Run anyway.
- Build locally: `GODOT=/path/to/Godot_v4.6.1 scripts/build-native.sh` (needs the matching export templates).

## What's better than the browser version
Forward+ renderer (Vulkan): real-time soft sun shadows across the whole scene, ambient occlusion, bloom, filmic tone mapping, 4x anti-aliasing, a much sharper 4096-pixel painted ground map, GPU-displaced terrain, instanced houses and trees with distance culling, Barlow brand fonts, and a fallback "compatibility" mode (`Play (compatibility mode).bat`) for older graphics cards.
The flight model is the same physics ported line for line (`godot/scripts/flight_model.gd`), checked by `godot/tests/test_flight.gd` (takeoff, climb, level flight, turns, stalls, landing, stopping), which also runs in the build.

## VR (Meta Quest 3)
OpenXR through **Meta Quest Link** (cable) or Air Link: in the Quest Link app set it as the active OpenXR runtime, start Link, then press "Fly in VR" (or `Play (VR - Meta Quest).bat`). Controls: right stick pitch/roll, right trigger/grip more/less power, left stick power/rudder, left trigger brakes, A flaps, B recentre, X pause, Y restart. The keyboard works in VR too (WASD to fly, Shift/Ctrl power); the game brings its window to the front when VR starts and shows a message if the keyboard isn't reaching it. The desktop window mirrors the view and shows the pause menu. First tested on Sam's Quest 3 on 9 Nov 2026: VR works, but flying was hard to control, which led to the v1.4.0 control changes. Still to tune: seat position, comfort and frame rate.

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
Real geography and elevation for Duxford, real aircraft models, proper weather, a rig adapter, code signing for the .exe, and testing on the MSI laptop and Quest 3.
