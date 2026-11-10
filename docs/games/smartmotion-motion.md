# SmartMotion Motion (replaces FlyPT Mover)

Our own motion program: it moves the simulator with SmartMotion Flight, in all three games (Flight, Racing and Space). It is in the same Windows download as the game (`SmartMotionMotion.exe`, built from `motion/`, a Godot 4.6 project). Everything is SmartMotion-owned code. FlyPT Mover's own window says it is free for non-commercial use only, so paid rides need motion software we're allowed to use (LIC-06).

**Status (10 Nov 2026, v1.9.0):** built and checked on screen (dry run) and by the automatic checks. **Not yet tried on the real rig or controller** (task P-10).

## How it fits together

```
SmartMotion Flight --(flight data, UDP 4123, 60/s)--> SmartMotion Motion --(seat position, ~500/s, USB or network)--> Motion4Sim controller --> 7 actuators
        ^                                                    |
        +------(seat position back, UDP 4124, 100/s: VR motion compensation)
```

- **The game** sends its flight data (Settings > Motion rig > On, `127.0.0.1:4123`). Fields: `docs/games/smartmotion-flight.md`.
- **SmartMotion Motion** works out where the seat should be (motion cueing) and sends it to the controller about every 2 ms, which is the rate the controller wants.
- **The Motion4Sim controller** runs in **Position mode**. We send the seat position (sway, surge and heave in mm; yaw, roll and pitch in degrees, plus the seat belt), and the controller works out each actuator's length from the rig measurements stored on it. It also owns homing, end stops and the hardware emergency stop. Today FlyPT Mover does the actuator maths itself and sends actuator positions ("Direct mode", the `<255><255><Axis1a>…<Belt>000<10><13>` string in Sam's Mover setup). With Position mode, our program doesn't need the rig's geometry.

## One-off set-up (Sam)
1. **Rig measurements into the controller.** In the Motion4Sim Dashboard, on the Rig tab, enter the measurements of the rig (Sam's Mover setup calls it *MotionXP-PRIME_FLY*; the controller also has a built-in *MXP Prime* rig type). The Dashboard uses the same layout as FlyPT Mover, so the numbers can be copied across. Check them in the Dashboard's 3D view and on its Test tab **in Position mode**, then close the Dashboard (only one program can use the USB port).
2. **Safety limits** in SmartMotion Motion (Settings > Safety limits): set the most movement and turn to fit inside the rig's real travel. The defaults are cautious (±60 mm, ±10°, 300 mm/s, 40°/s).
3. **Directions:** nobody on the rig, Strength 20 %, Test movement > *Wave each axis in turn*. Each axis goes + first: sway right, surge forward, heave up, yaw nose right, roll right side down, pitch nose up. Tick *Flip* (Settings > Directions) for any axis that goes the wrong way.

## Every session
Game: Motion rig On. SmartMotion Motion: USB cable, Find, Connect. Then **Start rig** (homing), **Online** (rises to the middle), rider in, **Motion ON** (fades in over 2 s). After the ride: **Park** (fades out, then sends "offline", so the rig goes down). Space or the on-screen button = emergency stop; the hardware button wired to the controller always works.

## What the motion does (cueing)
The same method as FlyPT Mover and Motion4Sim's own Motionsystem (docs.motion4sim.com, *Motion flow* and *How the platform should move*):

| Channel | Input from the game | Treatment |
|---|---|---|
| Sway, surge, heave | `g_felt` (what the pilot feels; heave minus 1 g) × gain (mm per m/s²) | wash-out (high-pass, 4 s) then two smoothing stages (0.2 s): the start of each push, then a slow drift back to the middle |
| Yaw, roll, pitch | `rate.*_dps` × gain (° per °/s) | wash-out then one smoothing stage: a short twitch as a rotation starts |
| Pitch tilt | `asin(g_felt.surge)` | slow lean (max 3°/s, below what the inner ear notices as rotation), up to 8°: pushed into the seat back on take-off, into the belts when braking |
| Roll tilt | `asin(−g_felt.sway)` | same, for sideways forces (skids, turning on the ground) |
| Seat belt | braking + going light in the seat (`1 − heave`) | tension 0..1 → 0..0xFFFFFFFF on actuator 7 (off by default) |
| Runway rumble | on the ground, by ground speed | 0.4 mm shake |

Then a guard per axis: soft limit (passes 80 % of the limit unchanged, then eases towards it), top speed, top acceleration (it slows down in time not to overshoot). Pause, crash or no data for 0.3 s fades the motion out over 2 s, and the seat glides back to the middle. All settings have plain-English help on the Settings page and are saved in `%APPDATA%\Godot\app_userdata\SmartMotion Motion\motion.cfg`.

In a flight sim, using what the pilot *feels* (specific force) rather than the aircraft's acceleration is what makes this right: in a steady climb the pilot is pushed slightly back into the seat, so the seat tilts nose-up by the climb angle; in a well-flown turn the push is straight down into the seat, so the seat doesn't lean.

## Controller protocol (from docs.motion4sim.com, firmware 5.4x)
- **Position packet, 36 bytes:** `252 252`, then sway, surge, heave (mm), yaw, roll, pitch (degrees) as 32-bit floats, belt and wind as 32-bit whole numbers (0 = off, 0xFFFFFFFF = full), then `10 13`. Low byte first.
- **Commands, 8 bytes:** `249 249`, command (2 bytes), value (2 bytes), `10 13`, low byte first. The manual writes commands as they go down the cable: "0600" is command 6. Used: status `0000` (answer = state number, e.g. 18 = online and moving, 31/32 = emergency), firmware `0200`, emergency `0500` (1 on / 0 off), online `0600` (0 online / 1 offline), start `8000` (homing, instead of pressing the controller's knob).
- **USB:** COM port, 250,000 baud, 8N1 (the same as Sam's Mover setup). Godot can't open COM ports on Windows, so a small helper (`motion/assets/serial_bridge.ps1`, run by Windows PowerShell, which every Windows PC has) passes the bytes to the port and back. Status is read every 0.25 s.
- **Network cable:** UDP to the controller's address, port 53241. Needs the controller's **Pro** licence; Basic controllers ignore network data. Answers go only to the Dashboard's PC, so over the network we only send (no status). Don't use Wi-Fi: it stutters.
- **To confirm on the real controller** (P-10): float byte order (low byte first expected), the sign of each axis, the belt range, the firmware version, and whether the controller switches to Position mode by itself when it sees `252 252` packets.

## VR motion compensation
When the rig tilts, the headset tilts with it, and without a correction the cockpit would swing around the rider's head. SmartMotion Motion sends the seat position it is giving the rig back to the game (`127.0.0.1:4124`, JSON, 100/s, `live` true only when the rig is really following). The game (`godot/scripts/motion_comp.gd`) moves the VR origin by the opposite of that movement, turning about the rig's centre of rotation. That point is assumed to be 0.6 m below the rider's eyes when they recentre (`MotionComp.PIVOT_BELOW_EYE`): adjust it to the centre of rotation set on the Motion4Sim Dashboard once the rig is measured. In Dry run nothing is cancelled, because the rig isn't moving.

## Code (`motion/`)
`scripts/cueing.gd` (the motion maths, fixed 500 steps a second), `rig_link.gd` (packets, USB helper, network), `motion_engine.gd` (the loop, on its own thread: game in, cueing, controller out, pose back to the game), `rig_view.gd` (3D picture, illustration only), `config.gd` (saved settings and the Settings page text), `main.gd` (operator screen). `tests/test_cueing.gd`: 40 checks (directions, limits, tilt speed, fades, belt, exact bytes of every packet and command). Run `godot --headless --path motion --script res://tests/test_cueing.gd`; the native build runs it too and stops on a failure. Screenshot: `xvfb-run godot --path motion --rendering-driver vulkan -- --shot=out.png --shot_after=4` (options: `--motion` switch motion on, `--wave` test wave, `--page=settings|test|help`).

## Later
- Other games: read DCS, MSFS and X-Plane data the way Mover's sources do (each sends its own format), and separate air/ground settings like Mover's AIR/GROUND poses.
- Wind fans (Mover has Left/Right wind outputs; the position packet has one wind value).
- Gentle / Medium / Strong presets (W2-06).
