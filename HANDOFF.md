# Handoff: SmartMotion Flight v1.19.0 (paused 12 Nov 2026)

Work in progress on branch `claude/gracious-fermi-a5v0uc`. **Not on `main` yet**, so no Windows build has been made from it. Delete this file once the work is finished and pushed to `main`.

## What Sam asked for
Trim up/down while flying; remove the buildings from the end of the runway; always stay in the pilot's seat (never fall out when looking around); nothing blocking the view or passing through other parts; a key-binding setting where everything (trim included) can be changed; a help section in the menu with a simple picture of all the controls; an option to show what the buttons do while playing; every visible part of the aircraft realistic and lined up ("as close to Flight Sim 2024 as possible").

## Done and checked
- **Trim**: hold `]` / `[` (Num 1 / Num 7), `\` or Num 5 = middle; gamepad D-pad up/down; VR left grip + left stick. Now works in Easy mode (`flight_model.gd`, `flightmodel.js`). New trim checks in `godot/tests/test_flight.gd` and `scripts/test-flight.mjs` pass.
- **Runway**: 4 stray buildings removed from `buildings.bin`, `roofmask.png` remade, filter added to `scripts/build_world_data.py`.
- **Key bindings**: `godot/scripts/keys.gd` (class `Keys`), Change keys screen in `ui.gd`, all input in `main.gd` reads `Keys`. `godot/tests/test_keys.gd` passes (21 checks).
- **Controls screen**: keyboard picture (`godot/scripts/keyboard_pic.gd`), tabs per game, gamepad and VR cards. Checked by screenshot (`-- --ui_shot=<prefix>` now also saves controls, keys and overlay pictures).
- **Controls while playing**: F1 / Settings toggle, list at the left of the HUD; VR card in the cockpit (not tested in a headset).
- **VR seat limit**: `_keep_in_seat`, `_auto_recentre` in `main.gd` (not tested in a headset: none on the build machine).
- **Bulldog cockpit fit** (`bulldog.gd`): boxier fuselage (`SE_N` 3.6), fuller canopy (`CAN_N` 3.0), panel at 95% cut to the cabin, new glare shield, firewall and rear wall, seats/pedals/instructor moved inside, round propeller disc. Checked by screenshots from 6 cockpit directions and 2 outside views: nothing pokes through.
- All existing checks pass: `test_flight`, `test_race`, `test_ship`, `test_coaster`, `test_xplane`, `-- --test_panel`.
- Docs written: v1.19.0 section in `docs/games/smartmotion-flight-native.md`, `godot/package/README.txt`, `data/changelog.json`; `VERSION` and `APP_VERSION` are 1.19.0.

## Still to do
1. **Run the live key test** and fix anything it finds: `godot --headless --path godot -- --auto --key_test` (`_key_test` in `main.gd`: presses real keys while flying and checks trim, a changed key, F1 list, pause/Esc). It was written but **had not finished running** when work paused (the headless world load was still going after about 5 minutes; it may just be slow, or may need the timing looked at). If it can't be made to run headless, try under `xvfb-run` with `--rendering-driver vulkan`.
2. Run `scripts/build-native.sh` checks if Godot export templates are available, and `node scripts/build-site.mjs` (must print `Built dist/`).
3. Add to `CLAUDE.md` (native game section): the `Keys` class, `tests/test_keys.gd`, `--key_test`, `--shot_look`, and that new controls must be added to `Keys.ACTIONS`.
4. Delete `HANDOFF.md`, commit, push to `main` (Sam's rule: every change goes straight to `main`; that push starts the Windows build). Then check the `build-native.yml` run finishes and give Sam the download link.
5. Tell Sam plainly: VR seat limit and VR help card are untested in a headset; and matching a commercial simulator's cockpit detail needs a hand-made 3D model, not more code.

## Handy on this kind of machine (no graphics card)
- Godot 4.6.1: download from `github.com/godotengine/godot-builds/releases/download/4.6.1-stable/`; run `godot --headless --path godot --import` once (several minutes the first time, and again after adding a `class_name`).
- Screenshots: `apt-get update && apt-get install -y mesa-vulkan-drivers xvfb`, then
  `xvfb-run -a -s "-screen 0 1024x640x24" godot --path godot --rendering-driver vulkan -- --q=low --view=near --auto --cam=cockpit --clouds=off --grass=off --shot=a.png --shot_after=0.4 --shot_frames=3 --shots=b.png@0.1,c.png@0.1 --shot_look=75:-12,0:-50 --shot_cam=cockpit,cockpit`
  (about 7 s a frame; keep `--shot_after` small because the timer only advances 0.13 s a frame).
