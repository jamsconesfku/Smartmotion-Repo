# SmartMotion Flight

A browser flight game set around Duxford, built to replace Microsoft Flight Simulator for SmartMotion's own experiences (MSFS has no commercial licence). Everything is SmartMotion-owned code: no third-party flight software, aircraft or scenery. **No longer published (v1.7.1):** the website now offers only the Windows version (`docs/games/smartmotion-flight-native.md`); the browser code stays in the repo as the physics reference.

## What's in v1
- **Two aircraft:** Light Trainer (forgiving) and WW2 Fighter (fast, lively), both with a cockpit, working instruments and animated controls.
- **Duxford area:** runway 06/24 (1,503 m), hangars, tower, apron with parked aircraft, windsock, villages (Duxford, Whittlesford, Sawston and others), the M11, A505, the river, woods and fields. An impression of the area, not a survey (see "Not yet" below).
- **SmartMotion everywhere:** billboards by the runway and beside the M11, big logos on the hangar roofs and the grass, distance boards, a SmartMotion blimp, SmartMotion livery on both aircraft.
- **Modes:** free flight (start on the runway or in the air) and a Gate run through 11 gates with a timer and best time.
- **Controls:** keyboard, gamepad, touch (phone), and VR controllers. **Easy** mode keeps the aircraft stable; **Pro** mode is direct control.
- **Day and golden hour**, calm or breezy.

## VR on the Meta Quest 3
1. Put the game online (Cloudflare Pages). WebXR needs `https`, which the `.pages.dev` address has.
2. In the **Meta Quest Browser**, open the dashboard (sign in with Cloudflare Access as normal), go to Games → Fly Duxford, press **Enter VR**.
3. Or on a PC: Chrome/Edge with the headset connected through **Quest Link** or Air Link, same steps.
4. Sit upright and press **B** to recentre the view.
- Right stick: pitch and roll. Left stick: up/down power, left/right rudder. Left trigger: brakes. A: flaps. B: recentre. X: pause.
- iPhone browsers don't support WebXR. On a phone the game plays as a normal touch game.
- v1 VR has been checked only up to requesting the headset session (no Quest was available while building). Expect to adjust seat position, scale and comfort.

## Telemetry for the motion rig
Settings → **Send flight data** streams one JSON frame about 60 times a second over WebSocket (default `ws://localhost:8765`). The same frame is always available in the page as `window.SmartMotionTelemetry`.

Run the receiver on the PC that drives the rig: `node tools/telemetry-bridge.mjs [--port 8765] [--udp 127.0.0.1:4123] [--log]`. It shows a live readout and can forward each frame as UDP JSON to a rig program (for example a small adapter feeding FlyPT Mover). The adapter isn't written yet because it depends on how the rig software is set up.

Frame fields (units in the name): `att.pitch_deg/roll_deg/heading_deg`, `rate.roll_dps/pitch_dps/yaw_dps` (body rates), `g_felt.surge/sway/heave` (what the pilot feels, in g, 1.0 heave = level flight), `vel_body`, `ias_kt`, `alt_ft`, `agl_ft`, `vs_fpm`, `aoa_deg`, `throttle`, `on_ground`, `stall`, `controls`, plus `geo.lat/lon` and `pos` (metres from the airfield centre).

Note: a browser page on `https://` can only open a `ws://localhost` connection (localhost is allowed). To reach a rig PC elsewhere on the network, the bridge needs to be reached as `wss://` or the page opened on that PC.

## How it's built
`dashboard/fly/`: `flightmodel.js` (physics, no graphics), `terrain.js` (heights and the Duxford layout), `aircraft.js`, `world.js`, `game.js`, `index.html`. Three.js is in `dashboard/vendor/`. `node scripts/test-flight.mjs` checks the physics: takeoff, climb, level flight, turn rate, roll rate, stall and recovery, landing and stopping for both aircraft.

## Not yet / to decide
- **Real geography:** the layout is hand-placed. Real elevation and map data (Ordnance Survey, OpenStreetMap, Environment Agency LIDAR) could replace it. Needs a licence check for paid use.
- **Licensing for paid rides:** the code and art are all ours, so there is no game-company licence to buy. Still confirm with the insurer and ADIPS how a self-built simulator experience is treated, and keep the "no paid rides until the ADIPS DOC" rule.
- Better graphics (real aircraft models, buildings, trees, water), more aircraft, instrument flying, weather and ATC.
- Motion cueing for the rig (washout filters) once the rig adapter exists.
