# FlyPT Mover profile for the SmartMotion games

`godot/package/SmartMotion-Games.Mover` (shipped in the Windows ZIP) is a FlyPT Mover 3.5.3 profile for the MotionXP-PRIME_FLY rig that works with all four games through Mover's "X-Plane 11 (UDP)" source. Sam, 13 Nov 2026: "make a whole mover profile like this one but where each vehicle works smoothly and doesn't over extend any actuator. At the moment the actuators jump up and down and are not smooth." His own profile is kept unchanged as `docs/source/flypt-mover/smart_motion_game.Mover` (DOC-08); the new one is made from it by `scripts/mover/build.py`, which only changes the text of existing settings.

FlyPT Mover is free for non-commercial use only (LIC-06): use this for testing, and SmartMotion Motion for paid rides.

## What was wrong with the old profile
Found by replaying 150 s of each game's real data through a model of Mover (below):
- **Heave slammed between its limits.** The GROUND pose multiplied vertical acceleration by 100 into a 150 mm range, so anything over about 1.5 m/s² (0.15 g) drove heave to the limit: in flight it reached ±75 mm again and again. This is the "jumping up and down".
- **The GROUND pose moved in the air too.** It was ticked for the X-Plane source's AIR values as well as GROUND, so it always got the full signal and added its movement on top of the AIR pose.
- **The racing car saturated the tilt.** Braking/cornering tilt was sized for an aircraft taxiing: it clipped everything over 0.2 to 0.3 g, and the car pulls 1 to 3 g, so the seat banged from one limit to the other.
- **The limits didn't fit the rig.** With rig gain 0.5 the poses could still ask for 15° of pitch and roll and 75 mm of heave together. The rig's own numbers (below) allow about 14° of pitch or roll **on its own**; together they need up to 266 mm of actuator travel from the middle, and only 150 mm exists. In the flight replay an actuator was past the end of its travel 67% of the time.
- Most filters were first-order, so a sudden change in the game came out as a sudden change of speed at the actuators.

## The rig, from the profile's numbers (`scripts/mover/rig.py`)
L1 1175 / L2 70 (pivot spacing on the moving frame: a triangle of close pairs, on a 699 mm circle), L3 700 / L4 1300 (base: on a 1,015 mm circle, which matches the MotionXP Prime's 1.9 x 2.2 m footprint), actuator 1,250 mm at mid travel, 300 mm stroke. That puts the moving frame 1,085 mm above the base at mid travel. Cost in actuator travel: about 10.7 mm per degree of pitch, 9.8 per degree of roll, 6.5 per degree of yaw, 0.9 mm per mm of heave, 0.5 per mm of sway or surge. **Assumption:** L1/L2 are the moving frame and L3/L4 the base (as in other hexapod software that uses the same four numbers); FlyPT's site has no page for this. Which way round the frame faces doesn't change the result.

## The new settings
- **Limits (pose ranges and rig limits), rig gain 1:** pitch 7°, roll 6.5°, yaw 3°, heave 22 mm, sway and surge 5 mm. With all six at their limits together the worst actuator is 142 mm from the middle (150 available). Raising the rig gain or any limit brings the over-reach back.
- **Every channel:** crop the input to a sensible size, gain, two or three low-pass filters one after another (EMALP 100 to 120 samples at Mover's 2 ms calculation time), then LOGISTIC as a soft limit below the hard range. Yaw and heave also have a high-pass (EMAHP) so they drift back to the middle.
- **AIR** (flying, spaceship, coaster): pitch, roll and yaw from the turn rates; a little pitch from speeding up and slowing down (surge in pitch on); heave from vertical acceleration; sway in roll off (in a banked turn it would fight the roll).
- **GROUND** (racing car, aircraft on the runway): pitch from longitudinal and roll from lateral acceleration, sized for 1 to 3 g; small rate cues for the aircraft rotating; yaw rate with washout; heave for bumps. Listens to the GROUND values only.
- Not changed: the rig's measurements, the M4S serial output, the belt, wind and motion-compensation modules, the sources. Sway and surge (sliding the seat) stay off, as in Sam's profile, because their directions were never tested.

## Checked by replay (`scripts/mover/replay.py`)
| Game | Old: furthest from middle | Old: past the stroke | Old: hardest jolt | New: furthest | New: past the stroke | New: hardest jolt |
|---|---|---|---|---|---|---|
| Flight (take-off, steep turns, pull-ups) | 241 mm | 67% of the time | 0.92 g | 65 mm | never | 0.12 g |
| Racing (computer driver, flat out) | 99 mm | never | 0.61 g | 50 mm | never | 0.21 g |
| Coaster | 220 mm | 6% | 1.49 g | 68 mm | never | 0.14 g |
| Spaceship (autopilot to space) | 171 mm | 0.6% | 1.45 g | 66 mm | never | 0.24 g |

"Jolt" is the acceleration of an actuator's length. The new figures hold under each way the model could be wrong that we could think of: either textbook weight for the moving average, game data arriving 60 or only 20 times a second, and an instant or gradual change between AIR and GROUND.

**Not tested in FlyPT Mover or on the rig** (neither is available on the build machine). The model follows flyptmover.com's descriptions of the filters; two details are not documented there and are assumed: the exact weight of EMALP for N samples, and LOGISTIC's curve (range x tanh, which matches the one worked example on the xsimulator forum). The directions of the tilts are kept as in Sam's profile; if one is the wrong way round, put a minus on that out gain.

## Changing it
1. Record the games: `godot --headless --fixed-fps 60 --path godot -- --auto --stunt --game=flight --tel_dump=flight.csv --quit_after=150` (also `--game=race --autopilot`, `--game=coaster`, `--game=space --space_start=earth`; `--stunt` flies a set routine and presses the spaceship's autopilot).
2. Edit the filters or `LIMIT` in `scripts/mover/build.py`, run it (usage at the top of the file), then `python3 scripts/mover/replay.py scripts/mover godot/package/SmartMotion-Games.Mover <folder with the four csv files> --both`.
3. Any new limits must keep `rig.worst(limits)` under 150 mm.
