SmartMotion Flight  (Windows, version @VERSION@)
=================================================

A flight game around Duxford for the SmartMotion simulator. Runs on your PC's graphics card, no browser.

HOW TO START
  1. Unzip this folder anywhere (not inside the zip).
  2. Double-click  SmartMotionFlight.exe.
     Windows may say "Windows protected your PC" because the game isn't signed.
     Click "More info", then "Run anyway".
  3. Pick an aircraft (Skysmart's Bulldog G-SMAT, or the WW2 fighter) and press Fly.

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
     "Fly in VR (Meta Quest)" (the game restarts itself in VR mode).
  5. Sit upright and press B on the right controller (or V on the keyboard) to recentre.
  You can fly with the keyboard while wearing the headset: click the game window on the laptop once
  BEFORE putting the headset on, and don't click anywhere else afterwards.
  Your hands: move your right controller to the control stick between your knees and the glove takes hold
  of it (it moves as you fly); the left glove takes the throttle in the same way.
  Controls: right stick = pitch and roll, right trigger / grip = more / less power,
  left stick = power and rudder, left trigger = brakes, A = flaps, B = recentre, X = menu, Y = restart.
  The menu appears in the headset: stick up/down to choose, A to select (change aircraft, start
  position, gate race, time of day, Easy/Pro, recentre, leave VR), B or X to carry on.
  If the keyboard does nothing in VR, the game shows a message: click the game window on the laptop once.
  Smooth VR: the menu's "Headset" line shows the frame rate. It should say "smooth". If it says "too slow",
  pick 72 Hz there (or in the Quest Link app: Settings > Graphics preferences > Refresh rate 72 Hz), and
  set Graphics quality to Medium in Settings. Plug the laptop in to mains power: on battery the graphics card slows down.

CONTROLS (keyboard)
  W/S nose down/up, A/D bank to turn (arrow keys also work), Shift/Ctrl power (or keys 1-0), Q/E rudder, Space brakes,
  F flaps, V camera, P or Esc pause, R restart, T telemetry panel, M sound, F11 full screen.
  Gamepads work too (right stick, left stick, triggers).
  Easy mode (the default) sets full power on the runway for you: hold S at take-off speed to lift off.

SEND MOTION DATA TO THE SIMULATOR RIG
  Settings > Motion rig > On. The game sends the flight data 60 times a second as JSON over UDP to the
  address and port shown (default 127.0.0.1 port 4123). Point your rig software or adapter at that port.
  Press T in flight to see the numbers.

MAP DATA AND TEXTURES (credits)
  Contains modified Copernicus Sentinel data 2023.
  Produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH 2014-2018
  provided under COPERNICUS by the European Union and ESA; all rights reserved.
  ESA WorldCover 2021 (c) ESA, CC BY 4.0.
  Buildings and runway (c) OpenStreetMap contributors, Overture Maps Foundation, ODbL
  (the game's buildings file is available under the ODbL on request).
  Ground and building textures: ambientCG (CC0).

Your settings and best times are saved in your Windows user folder (%APPDATA%\Godot\app_userdata\SmartMotion Flight).
