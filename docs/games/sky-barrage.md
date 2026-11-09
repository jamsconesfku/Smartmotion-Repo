# Sky Barrage

A SmartMotion arcade game, played from the **Games** section of the SmartMotion Dashboard. It's built to play like an iPhone game: full screen, held upright, drag to aim. It also works with a mouse, and shows in a phone-shaped frame on a laptop.

Original brief: `docs/source/Sky_Barrage_Brief.pdf`.

## How it plugs into the dashboard
- Game code: `dashboard/games/sky-barrage.js` (one file, canvas + inline SVG, no libraries). It adds `window.SkyBarrage` with `open()`, `close()` and `stats()`.
- The dashboard loads it with `<script src="games/sky-barrage.js">`. The site build copies it to the website as is.
- The **Games** menu section (`games` view in `dashboard/index.html`) shows the tile. "Play Sky Barrage" opens the game full-screen over the dashboard, and "Back to dashboard" closes it.
- Deep link: `#sky-barrage` on the dashboard link opens the game straight away.
- Progress is saved in the browser's `localStorage` under `sm2:skybarrage`, the same way the dashboard saves its own settings. It's per device and wrapped in try/catch, so the game still runs if storage is blocked.

## Game summary
- **20 hand-made levels** in the `LEVELS` table: a 7-column grid written as rows of codes (`b12` blimp with 12 HP, `c` crate, `s` storm cloud, `a` armoured airship, `x` bomber, `T` radar tower, `D`/`d` hangar door closed/open, `R` +1 ring, `Z` boss zeppelin, 3 wide).
- **Turn:** drag to aim (10°–170°, dotted path to the first bounce, or 3 bounces with Laser sight). Let go to launch the squadron, one jet every 50 ms. The first jet to land sets the next launch point. Shots speed up after 8 seconds. After each turn the sky moves down one row.
- **Lose:** an enemy reaches the deck, or you run out of turns. **Win:** clear every enemy. Clearing gives 1 star; spare turns give 2 or 3.
- **Enemies:** blimp, cargo crate (drops a medal), storm cloud (chain lightning), armoured airship (half damage), bomber (pushes the enemy below it down), radar tower (solid), hangar doors (open/close each turn), +1 wingman ring, boss zeppelin on levels 10 and 20.
- **Pre-level boosters:** Afterburner, Cluster flares, Stealth (first 3 turns each), +5 Wingmen.
- **In-game power-ups:** Airstrike, Formation (V volley), Thunder, Crosswind, Laser sight.
- **During a shot:** Recall (free) and Undo (5 medals).
- **Medals:** earned from crates and clearing levels. Spent on Undo, +5 turns / Push back (15), extra power-ups (10), boosters (8) and jet colours.

## Branding
Uses the dashboard's navy (#02022F), orange (#FF4C00), Barlow / Barlow Semi Condensed type and rounded corners. Enemy colour tiers are tints of the palette: brand blue for weak, violet for medium, orange for tough.
