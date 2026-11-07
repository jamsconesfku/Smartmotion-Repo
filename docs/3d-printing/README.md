# 3D printing and design

Sam designs and prints parts for the simulator and personal projects on an **Anycubic Kobra 3** (250 × 250 × 260 mm) and a **Kobra 3 Max** (420 × 420 × 500 mm). Claude designs models to order, and everything lives in the **Print & Design** workspace of the SmartMotion Dashboard (switch at the top of the menu, or add `#print-design` to the dashboard link).

## How it works
1. Sam asks for a design in a Claude Code chat (what it's for, measurements, material), or uploads his own STL/STEP files.
2. Claude writes the design as parametric CadQuery code in `designs/<slug>/model.py` and builds it with `scripts/build_design.py <slug>`.
3. The build makes STL (print) + STEP (edit) files, a preview picture, a 3D view, a size check against both printers, a filament estimate and a download ZIP. It also adds or updates the entry in `data/designs.json`.
4. Sam prints it and reports back. The status and print log are updated, and changes become a new version (v2, v3…). Old versions are kept.

## Files
- `designs/<slug>/model.py`: current source. `META` holds the title, category, print settings, design steps, lessons and assumptions. `PARAMS` holds the measurements that can be changed. `build(p)` returns the parts.
- `designs/<slug>/<version>/`: frozen output for each version (STL, STEP, preview.png, view.json, ZIP, model.py, README.txt).
- `data/designs.json`: the library the dashboard reads. Status is one of `idea`, `designing`, `ready_to_print`, `printed`, `needs_changes`, `archived`, plus `notes` and `print_log` entries (`{date, version, note}`).

## Library
| ID | Model | Notes |
|---|---|---|
| PD-001 | Sim button box | 6 buttons, 2 toggles, 2 encoders, USB, M3 heat-set inserts |
| PD-002 | VR headset hook | Bolts to 40 mm profile with M8 T-nuts |
| PD-003 | Extrusion cable clip | Snaps into an 8 mm slot, holds a 10 mm cable bundle |

The starter models assume standard parts (40-series profile, 12 mm buttons, M8 T-nuts). Each lists its assumptions to check before printing.
