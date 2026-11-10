# Rig specification

| Item | Detail |
|---|---|
| Platform | Single-seat 6-DOF motion platform: pitch, roll, yaw, surge, heave, sway |
| Actuators | 7 electric actuators: 6 for motion, plus 1 driving seat-belt tensioners that simulate g-force. No hydraulics. |
| Motion controller | Motion4Sim servo driver controller (upgraded to the newest generation in Oct 2026) |
| Motion software | FlyPT Mover (telemetry to motion; profiles per game; free for non-commercial use). For our own games it is replaced by our own **SmartMotion Motion** (v1.9.0, not yet tested on the rig), which drives the controller in Position mode: `docs/games/smartmotion-motion.md` |
| Display | VR headset or screens, plus a spectator screen |
| Controls | Force-feedback joystick and throttle (flight) or steering wheel and pedals (driving); the rig converts between modes |
| Restraint | 5-point harness |
| Power | Single-phase electric; portable for events |

## To confirm and record
Needed for the ADIPS design review and the operations manual (W2-04, DEC-03):

| Item | Value |
|---|---|
| Rated rider load | _TBC_ |
| Rider height / age limits | _TBC_ |
| Footprint and exclusion zone | _TBC_ |
| E-stop design and behaviour | _TBC_ |
| Transport weight and size | _TBC_ |
| PC specification | _TBC_ |
| Headset model | _TBC_ |

## Custom simulator idea (parked, F-02)
A SmartMotion-owned flight experience on FlightGear, with a UDP telemetry bridge into FlyPT Mover, one-click experience presets and an operator panel. Later option: Unity or Unreal sim using the JSBSim flight model and OpenXR. Four phases: prove VR and motion work → aircraft and scenery → experience presets → trial runs and paperwork.
