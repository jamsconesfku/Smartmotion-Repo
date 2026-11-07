"""Sim button box: a two-part enclosure (body + lid) for push buttons, toggle
switches and rotary encoders, wired to a small USB controller board inside."""
import cadquery as cq

META = {
    "title": "Sim button box",
    "category": "Simulator parts",
    "origin": "Designed by Claude",
    "summary": "Two-part box for 6 push buttons, 2 toggle switches and 2 rotary encoders, with a USB port and slots to bolt it to the rig.",
    "purpose": "Gives riders and the operator real switches for things like engine start, lights and view reset, instead of a keyboard.",
    "print": {
        "material": "PETG (PLA+ is fine indoors)",
        "printer": "Kobra 3",
        "layer_height": "0.2 mm",
        "walls": "4 walls (1.6 mm)",
        "infill": "20% gyroid",
        "supports": "None: print the body open side up and the lid top face down",
        "orientation": "Body: floor on the bed. Lid: flat face on the bed so the panel comes out smooth.",
        "fill_factor": 0.5,
    },
    "steps": [
        "Started from a rounded box and hollowed it with an even 3 mm wall, open at the top.",
        "Added four corner posts with 4.0 mm holes sized for M3 heat-set inserts, so the lid can come off many times without wearing the plastic.",
        "Cut a USB port in the back wall and two slots in the floor for M6 bolts to the rig.",
        "Made the lid with a lip that drops 3 mm inside the walls (0.3 mm gap all round) so it locates itself.",
        "Cut the panel holes: 12 mm buttons, 6.2 mm toggles, 7.2 mm encoders, then countersunk the M3 lid screw holes.",
        "Chamfered the bottom edge 0.8 mm so the first layer squish (elephant foot) doesn't stop the lid fitting.",
    ],
    "learning": [
        "Design clearances: parts that slide together need about 0.2 to 0.3 mm gap per side on an FDM printer. The lid lip uses 0.3 mm.",
        "Heat-set inserts beat screwing into plastic. Hole sizes come from the insert maker; 4.0 mm suits common M3 x 5.7 mm inserts.",
        "Print panels face-down on the bed: the side people see gets the smooth bed finish.",
        "Make hole sizes a parameter. Switches vary, and changing one number is quicker than redrawing.",
    ],
    "assumptions": [
        "Hole sizes assume 12 mm push buttons, MTS-style toggles (6 mm thread) and EC11 encoders (7 mm thread). Measure yours and change the numbers if different.",
        "Mounting slots assume M6 bolts. The box's position on the rig hasn't been decided.",
    ],
}

PARAMS = {
    "width": {"value": 170.0, "unit": "mm", "label": "Box width"},
    "depth": {"value": 100.0, "unit": "mm", "label": "Box depth"},
    "height": {"value": 55.0, "unit": "mm", "label": "Body height"},
    "wall": {"value": 3.0, "unit": "mm", "label": "Wall thickness"},
    "corner": {"value": 8.0, "unit": "mm", "label": "Corner radius"},
    "lid": {"value": 4.0, "unit": "mm", "label": "Lid thickness"},
    "button_hole": {"value": 12.2, "unit": "mm", "label": "Push button hole"},
    "toggle_hole": {"value": 6.3, "unit": "mm", "label": "Toggle switch hole"},
    "encoder_hole": {"value": 7.3, "unit": "mm", "label": "Encoder hole"},
    "insert_hole": {"value": 4.0, "unit": "mm", "label": "Heat-set insert hole (M3)"},
    "fit_gap": {"value": 0.3, "unit": "mm", "label": "Lid lip clearance"},
}


def build(p):
    W, D, H, t, r = p["width"], p["depth"], p["height"], p["wall"], p["corner"]
    boss_r, boss_off = 5.0, t + 4.5
    corners = [(sx * (W / 2 - boss_off), sy * (D / 2 - boss_off)) for sx in (-1, 1) for sy in (-1, 1)]

    # ---- body: rounded box, hollowed, open at the top
    body = (cq.Workplane("XY").box(W, D, H, centered=(True, True, False))
            .edges("|Z").fillet(r)
            .faces(">Z").shell(-t))
    body = body.faces("<Z").edges().chamfer(0.8)
    # corner posts for heat-set inserts
    posts = (cq.Workplane("XY").workplane(offset=t).pushPoints(corners)
             .circle(boss_r).extrude(H - t))
    body = body.union(posts)
    body = (body.faces(">Z").workplane().pushPoints(corners)
            .hole(p["insert_hole"], 8.0))
    # USB port in the back wall
    usb = (cq.Workplane("XZ", origin=(W / 4, D / 2, t + 10)).rect(13.0, 7.5)
           .extrude(-t * 3, both=True).edges("|Y").fillet(1.5))
    body = body.cut(usb)
    # floor slots for M6 bolts
    slots = (cq.Workplane("XY").pushPoints([(-W / 4, 0), (W / 4, 0)])
             .slot2D(26, 6.6, 90).extrude(t * 3, both=True))
    body = body.cut(slots)

    # ---- lid: plate + locating lip, panel holes, countersunk screws
    L, g = p["lid"], p["fit_gap"]
    lid = (cq.Workplane("XY").box(W, D, L, centered=(True, True, False))
           .edges("|Z").fillet(r).faces(">Z").edges().chamfer(0.6))
    iw, idp = W - 2 * t - 2 * g, D - 2 * t - 2 * g
    lip = (cq.Workplane("XY").rect(iw, idp).extrude(-3.0)
           .edges("|Z").fillet(max(0.5, r - t - g))
           .faces("<Z").shell(-1.6))
    lip = lip.cut(cq.Workplane("XY").workplane(offset=-4).pushPoints(corners).circle(boss_r + 1.0).extrude(5))
    lid = lid.union(lip)
    buttons = [(x, y) for x in (-W / 2 + 25, -W / 2 + 52, -W / 2 + 79) for y in (20, -20)]
    toggles = [(W / 2 - 55, 22), (W / 2 - 25, 22)]
    encoders = [(W / 2 - 55, -22), (W / 2 - 25, -22)]
    lid = lid.faces(">Z").workplane().pushPoints(buttons).hole(p["button_hole"])
    lid = lid.faces(">Z").workplane().pushPoints(toggles).hole(p["toggle_hole"])
    lid = lid.faces(">Z").workplane().pushPoints(encoders).hole(p["encoder_hole"])
    lid = lid.faces(">Z").workplane().pushPoints(corners).cskHole(3.4, 6.8, 90)
    return {"body": body, "lid": lid}
