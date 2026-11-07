"""Hook that bolts to the rig's aluminium frame to hang the VR headset between riders."""
import cadquery as cq

META = {
    "title": "VR headset hook",
    "category": "Simulator parts",
    "origin": "Designed by Claude",
    "summary": "Bolts to 40 mm aluminium profile with two M8 T-nuts. A wide, rounded saddle holds the headset by its strap without creasing it.",
    "purpose": "Gives the headset a safe home between sessions, off the floor and away from the moving seat.",
    "print": {
        "material": "PETG",
        "printer": "Kobra 3",
        "layer_height": "0.2 mm",
        "walls": "5 walls (2 mm) for strength",
        "infill": "30% gyroid",
        "supports": "None",
        "orientation": "On its side (the 40 mm wide face down), so the arm's layers run the length of the hook and don't snap off.",
        "fill_factor": 0.6,
    },
    "steps": [
        "Drew the side view: a back plate, an arm reaching 75 mm out and a raised lip at the end.",
        "Added a curved brace under the arm to spread the load into the back plate.",
        "Pushed the profile out 40 mm wide to match the profile face.",
        "Rounded every edge the strap touches (3 mm) so it can't dig in, and drilled two 8.5 mm holes 20 mm apart for M8 bolts.",
    ],
    "learning": [
        "Fillets on the inside corner of a bracket make it far stronger: sharp inside corners are where cracks start.",
        "Bolt holes: add about 0.5 mm to the bolt size (8.5 mm for M8) so the bolt slides through.",
        "For brackets, print so the load runs along the layers, never trying to peel them apart.",
    ],
    "assumptions": [
        "Assumes 40 mm aluminium profile and M8 T-nuts. Check what the rig frame uses before printing.",
    ],
}

PARAMS = {
    "width": {"value": 40.0, "unit": "mm", "label": "Hook width"},
    "reach": {"value": 75.0, "unit": "mm", "label": "Arm reach"},
    "plate_h": {"value": 60.0, "unit": "mm", "label": "Back plate height"},
    "thick": {"value": 7.0, "unit": "mm", "label": "Arm and plate thickness"},
    "lip_h": {"value": 22.0, "unit": "mm", "label": "End lip height"},
    "bolt": {"value": 8.5, "unit": "mm", "label": "Bolt hole"},
}


def build(p):
    Wd, L, Hp, t, lh = p["width"], p["reach"], p["plate_h"], p["thick"], p["lip_h"]
    pts = [(0, 0), (L, 0), (L, lh), (L - t, lh), (L - t, t), (t + 18, t),
           (t, t + 22), (t, Hp), (0, Hp)]
    hook = cq.Workplane("XZ").polyline(pts).close().extrude(-Wd)
    hook = hook.edges("|Y").fillet(3.0)
    holes = (cq.Workplane("YZ").pushPoints([(Wd / 2, Hp - 12), (Wd / 2, Hp - 32)])
             .circle(p["bolt"] / 2).extrude(t * 3, both=True))
    hook = hook.cut(holes)
    hook = hook.faces("<Y or >Y").edges().chamfer(0.6)
    return {"hook": hook}
