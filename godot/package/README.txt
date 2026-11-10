SmartMotion Flight  (Windows, version @VERSION@)
=================================================

Three games for the SmartMotion simulator in one program: Flight (around the real Duxford), Racing (an
open-wheel racing car on a 4 km circuit) and Space (a space fighter battle). Choose at the top of the menu.
Runs on your PC's graphics card, no browser.

HOW TO START
  1. Unzip this folder anywhere (not inside the zip).
  2. Double-click  SmartMotionFlight.exe.
     Windows may say "Windows protected your PC" because the game isn't signed.
     Click "More info", then "Run anyway".
  3. Pick Flight, Racing or Space at the top of the menu, choose the options and press Fly / Race / Launch.
     (Racing and Space take a few seconds to build the first time you pick them.)

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
  results). Point at it with either controller (an orange beam) and pull the trigger to click; stick up/down
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
  RACING
  W or Up = accelerate, S or Down (or Space) = brake (hold when stopped to reverse), A/D or Left/Right = steer,
  V camera (chase, cockpit, TV), R restart. Gamepad: left stick steer, right trigger accelerate, left trigger brake.
  Race: 3 laps against 7 computer cars from a standing start: when the five red lights go out, go.
  Time trial: drive on your own and set your fastest lap (it is saved). Easy mode adds traction control,
  anti-lock brakes and stability control; Pro has none.
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

MAP DATA AND TEXTURES (credits)
  Contains modified Copernicus Sentinel data 2023.
  Produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH 2014-2018
  provided under COPERNICUS by the European Union and ESA; all rights reserved.
  ESA WorldCover 2021 (c) ESA, CC BY 4.0.
  Buildings and runway (c) OpenStreetMap contributors, Overture Maps Foundation, ODbL
  (the game's buildings file is available under the ODbL on request).
  Ground and building textures: ambientCG (CC0).

Your settings and best times are saved in your Windows user folder (%APPDATA%\Godot\app_userdata\SmartMotion Flight).
