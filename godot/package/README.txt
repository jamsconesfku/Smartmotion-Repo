SmartMotion Flight  (Windows, version @VERSION@)
=================================================

Four games for the SmartMotion simulator in one program: Flight (around the real Duxford), Racing (an
open-wheel racing car on a 4 km circuit), Space (a space fighter battle) and a Roller coaster beside Duxford.
Runs on your PC's graphics card, no browser.

HOW TO START
  1. Unzip this folder anywhere (not inside the zip).
  2. Double-click  SmartMotionFlight.exe.
     Windows may say "Windows protected your PC" because the game isn't signed.
     Click "More info", then "Run anyway".
  3. The first screen asks how the simulator is set up today: Flight stick (Flight and Space games),
     Steering wheel (Racing), Hands-free ride (Roller coaster) or Laptop or gamepad (every game).
     The menu then shows the games for that set-up ("Change setup" to pick again).
  4. With a joystick or wheel fitted, press "Set up controls" once: press Set beside each control and move it
     as asked (the game remembers it).
  5. Choose the options and press Fly / Race / Launch / Ride.
     (Racing, Space and the Coaster take a few seconds to build the first time you pick them.)

GRAPHICS SETTINGS (Settings on the menu)
  Graphics quality: Fast, Balanced, Best (the default) or Ultra. Ultra draws buildings and trees further,
  more trees, sharper shadows further out and reflections in water and windows: use it if Best runs
  smoothly; on battery or in VR, Best is the safe choice. View distance: Near (fastest), Normal or Far.
  3D clouds: On or Off (Off is the quickest way to win back speed on the screen; VR never uses them).
  Quality and view distance change the next time you start the game.

USE YOUR GAMING GRAPHICS CARD
  The menu shows which graphics card the game is using ("Graphics: ..."). On a laptop with two
  graphics chips it should say NVIDIA or AMD, not Intel. If it doesn't:
  Windows Settings > System > Display > Graphics > Add the .exe > Options > High performance.

IF THE GAME WON'T START OR LOOKS WRONG
  Try "Play (compatibility mode).bat". It uses a simpler graphics mode that works on older graphics cards.

VR ON A META QUEST 3
  1. Install the Meta Quest Link app on the PC and connect the headset (USB cable or Air Link).
  2. In the Quest Link app: Settings > General > "Set Meta Quest Link as active OpenXR runtime".
  3. Put the headset on and start Quest Link (you'll see the Link home).
  4. Double-click "Play (VR - Meta Quest).bat" (best), or run SmartMotionFlight.exe and press
     "Play in VR (Meta Quest)" (the game restarts itself in VR mode).
  5. Sit upright and press B on the right controller (or V on the keyboard) to recentre.
  You can fly with the keyboard while wearing the headset: click the game window on the laptop once
  BEFORE putting the headset on, and don't click anywhere else afterwards.
  Your hands: move your right controller to the control stick between your knees and the glove takes hold
  of it (it moves as you fly); the left glove takes the throttle in the same way.
  Controls: right stick = pitch and roll, right trigger / grip = more / less power,
  left stick = power and rudder, left trigger = brakes, A = flaps, B = recentre, X = menu, Y = restart.
  THE MENU IN VR: the game's own menu floats in front of you in the headset (the main menu, pause menu and
  results). Point at it with either controller (an orange beam) and pull the trigger (index finger) to click: it clicks the moment the
  trigger goes down, with a short buzz in the controller; stick up/down
  scrolls. Or push the stick up/down to move between buttons and press A. X opens the menu while playing and
  carries on; Y restarts. You can switch between Flight, Racing and Space without taking the headset off.
  The pause menu also has "Recentre my view", the headset refresh rate and "Leave VR".
  Racing in VR: right trigger = accelerate, left trigger = brake, either stick = steer. Your gloves take
  the steering wheel when you bring the controllers to it.
  Space in VR: right stick = pitch and roll, left stick = speed and yaw, right trigger = fire, left trigger
  = boost. The gloves take the flight stick (right) and throttle (left).
  If the keyboard does nothing in VR, the game shows a message: click the game window on the laptop once.
  Smooth VR: the pause menu's "Headset" button shows the frame rate. It should say "smooth". If it says "too slow",
  pick 72 Hz there (or in the Quest Link app: Settings > Graphics preferences > Refresh rate 72 Hz), and
  set Graphics quality to Medium in Settings. Plug the laptop in to mains power: on battery the graphics card slows down.

CONTROLS (keyboard)
  FLIGHT
  W/S nose down/up, A/D bank to turn (arrow keys also work), Shift/Ctrl power (or keys 1-0), Q/E rudder, Space brakes,
  F flaps, V camera, P or Esc pause, R restart, T telemetry panel, M sound, F11 full screen.
  Gamepads work too (right stick, left stick, triggers).
  Easy mode (the default) sets full power on the runway for you: hold S at take-off speed to lift off.
  ONE WORLD: the racing circuit (2.5 km west of the runway) and the roller coaster (just south-east of the
  runway) are in the Duxford world. Fly over them in Flight; they're parked there when you're not using them.
  IF THE GAME CRASHES: start it again and press "Copy diagnostics" on the menu, then paste it to Claude.
  It includes the log of the run that crashed.

  RACING
  W or Up = accelerate, S or Down (or Space) = brake (hold when stopped to reverse), A/D or Left/Right = steer,
  V camera (chase, cockpit, TV), R restart. Gamepad: left stick steer, right trigger accelerate, left trigger brake.
  Race: 3 laps against 7 computer cars from a standing start: when the five red lights go out, go.
  Time trial: drive on your own and set your fastest lap (it is saved). Easy mode adds traction control,
  anti-lock brakes and stability control; Pro has none.
  COASTER
  No controls: just ride. V changes the view (your seat, behind the train, orbit). R rides again.
  SPACE
  W/S nose down/up, A/D roll, Q/E yaw, Shift/Ctrl speed, Space or left mouse button fire, Tab boost.
  Gamepad: right stick pitch and roll, left stick speed and yaw, right trigger fire, left trigger boost.
  Shoot down the waves of red drones. Your shield recharges a few seconds after a hit; the hull doesn't.
  Watch out for asteroids and the station. Easy mode helps you aim and rolls you upright when you let go.

MOVE THE SIMULATOR WITH THE GAME (SmartMotion Motion, replaces FlyPT Mover)
  SmartMotionMotion.exe is in this folder. It reads the game's motion data (Flight, Racing and Space) and drives the
  Motion4Sim controller over its USB cable (or the network cable, if the controller has the Pro licence).
  One-off set-up:
    1. In the Motion4Sim Dashboard, enter the rig's measurements on the Rig tab (copy them from the
       MotionXP-PRIME_FLY rig in FlyPT Mover: same layout). Check them on the Dashboard's Test tab in
       Position mode, then close the Dashboard and FlyPT Mover (only one program can use the USB port).
    2. In SmartMotion Motion: Settings > Safety limits, set the limits to fit the rig's real travel.
    3. Nobody on the rig, Strength 20 %: Test movement > "Wave each axis in turn". Check each axis goes
       the way the screen says; tick "Flip" in Settings > Directions for any that don't.
  Every session:
    1. Start SmartMotionFlight.exe. Settings > Motion rig > On (127.0.0.1, port 4123).
    2. Start SmartMotionMotion.exe. Pick "USB cable", press Find, then Connect.
    3. Start rig (homing), then Online (the rig rises to the middle).
    4. Rider belted in, operator at the red stop button: Motion ON. The motion fades in.
       Pause or a crash in the game fades it out and the seat returns to the middle by itself.
    5. After the ride: Park. Rider off only when the rig has stopped.
  Space = emergency stop on screen. The hardware stop button on the controller always works.
  In VR the game cancels the rig's movement out of the headset view (it reads the seat position
  SmartMotion Motion sends back on port 4124), so the cockpit stays still around you.
  Your settings are saved in %APPDATA%\Godot\app_userdata\SmartMotion Motion.
  Other software can still read the game's data: it is JSON over UDP, 60 a second (press T to see the numbers).

USE FLYPT MOVER WITH THE GAME (its 3D picture, or to drive the rig)
  The game talks to FlyPT Mover the way X-Plane 11 does, so Mover's ready-made "X-Plane 11 (UDP)" source
  reads it. No plug-in or extra program needed. It works for Flight, Racing, Space and the Coaster.
    1. Start SmartMotionFlight.exe (Settings > FlyPT Mover is On already). The first time, Windows may ask
       whether to allow the game on networks: tick Private networks and click Allow (Mover needs it).
    2. In FlyPT Mover, use the "SOURCE :: XPLANE 11 (UDP)" source (leave its address as 127.0.0.1 and
       port 49000, X-Plane's normal settings) and switch it on.
       Start the game first, then tick Connect in Mover's X-Plane source window (Mover asks only once, when
       it connects). After that the game remembers Mover: restarting the game, or switching to VR, carries
       on without reconnecting. Only if Mover itself was closed or reconnected do you need Connect again.
    3. Fly. The 3D rig picture in Mover moves with the game. Press T in the game: the panel shows
       "FlyPT Mover connected" once Mover is asking for data.
  COCKPIT LIGHT: the Bulldog's warning-light row has a MOVER light (the fighter shows it on the engine dial):
    dark "OFF" = the link is off in Settings; amber "WAITING" = the game is ready but Mover hasn't asked
    for data; green "LINKED" = Mover is reading the game.
  If it stays amber: Mover may be listening for X-Plane's "DATA" rows instead of asking. Open the X-Plane
    source window (small square, top right of its tile), note the port it shows, and type that number in
    the game: Settings > FlyPT Mover > "DATA rows to port". If that port is 49000, first change
    "Answer on port" to 49010 so the game doesn't take 49000 itself. Then stop and start the source in Mover.
  WHICH MOVER POSE EACH GAME USES: Mover splits the X-Plane source into AIR and GROUND by whether the
    vehicle is on the ground. Flying, Space and the Coaster ride are "air" (the AIR pose). Racing, and an
    aircraft on the runway, are "ground" (the GROUND pose), so Mover switches to it by itself as soon as
    the car game starts. To make the car move the rig: open the GROUND pose (top-right square of its tile),
    tick "SOURCE :: XPLANE 11 (UDP) GROUND" on the right, and set it like AIR: Sway = Lateral acceleration,
    Surge = Longitudinal acceleration, Heave = Vertical acceleration (kerb and gravel rumble come through
    here), Yaw = Yaw speed; tick "Mix sway in roll" and "Mix surge in pitch" so cornering and braking
    tilt the seat. Start with small Out gains and raise them bit by bit. The engine speed is sent as RPM.
    The racing car pulls about 1 g accelerating and over 2 g braking and cornering (10-25 m/s2), so set
    the Range for Sway and Surge to about 20-25 (the flying profile's 5 fills up straight away).
  If a direction is the wrong way round in Mover, flip it in Mover's settings for that axis.
  Mover listens to the game; use FlyPT Mover OR SmartMotion Motion to drive the rig, not both at once.
  The game also sends X-Plane "DATA" rows to 127.0.0.1 port 49001, for Mover set-ups that expect those.
  If X-Plane itself is running on the same PC it holds port 49000; close it first.

MAP DATA AND TEXTURES (credits)
  Contains modified Copernicus Sentinel data 2023.
  Produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH 2014-2018
  provided under COPERNICUS by the European Union and ESA; all rights reserved.
  ESA WorldCover 2021 (c) ESA, CC BY 4.0.
  Buildings and runway (c) OpenStreetMap contributors, Overture Maps Foundation, ODbL
  (the game's buildings file is available under the ODbL on request).
  Ground and building textures: ambientCG (CC0).

Your settings and best times are saved in your Windows user folder (%APPDATA%\Godot\app_userdata\SmartMotion Flight).
