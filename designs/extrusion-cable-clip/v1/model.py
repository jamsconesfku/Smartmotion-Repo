"""Snap-in cable clip for 40-series aluminium profile with an 8 mm slot."""
import cadquery as cq

META = {
    "title": "Extrusion cable clip",
    "category": "Simulator parts",
    "origin": "Designed by Claude",
    "summary": "Pushes into the 8 mm slot of 40-series aluminium profile and holds a cable bundle up to 10 mm across. No screws needed.",
    "purpose": "Keeps actuator, USB and power cables tidy and away from moving parts of the motion rig.",
    "print": {
        "material": "PETG (flexes without snapping)",
        "printer": "Kobra 3",
        "layer_height": "0.2 mm",
        "walls": "3 walls",
        "infill": "100% (it's small)",
        "supports": "None",
        "orientation": "On its side (the flat 10 mm face on the bed), so the springy legs bend along the layers, not across them.",
        "fill_factor": 1.0,
    },
    "steps": [
        "Drew the clip as a flat side profile, then pushed it out 10 mm thick.",
        "Made a split stem 7.6 mm wide (0.3 mm smaller than the slot each side) with a 1.8 mm gap so the legs can squeeze together.",
        "Added small barbs that spring out behind the slot lip to hold it in.",
        "Added a C-shaped cradle on top with a 6 mm opening; cables push in and stay put.",
    ],
    "learning": [
        "Print orientation decides strength. Layers stick to each other less well than plastic along a layer, so parts that flex should bend along the layers.",
        "Snap fits work best in PETG or nylon. PLA is stiff and tends to crack.",
        "Small parts print better at 100% infill; there's no room for infill pattern anyway.",
    ],
    "assumptions": [
        "Assumes 40-series profile with an 8 mm slot (common B-type). Measure the slot opening on the rig; if it's 10 mm, change the slot width.",
    ],
}

PARAMS = {
    "slot": {"value": 8.0, "unit": "mm", "label": "Profile slot opening"},
    "lip": {"value": 4.3, "unit": "mm", "label": "Slot lip thickness"},
    "cable": {"value": 10.0, "unit": "mm", "label": "Cable bundle size"},
    "thickness": {"value": 10.0, "unit": "mm", "label": "Clip thickness"},
}


def build(p):
    s, lip, cab, T = p["slot"], p["lip"], p["cable"], p["thickness"]
    stem = s - 0.4          # clearance in the slot
    gap = 1.8               # split between the legs
    leg = (stem - gap) / 2
    plate = cq.Workplane("YZ").center(0, 1.2).rect(s + 10, 2.4).extrude(T)
    legs = cq.Workplane("YZ")
    for side in (-1, 1):
        yc = side * (gap / 2 + leg / 2)
        legs = legs.union(cq.Workplane("YZ").center(yc, -(lip + 2.6) / 2).rect(leg, lip + 2.6).extrude(T))
        barb = (cq.Workplane("YZ").polyline([
            (side * (stem / 2 - 0.2), -lip - 0.3), (side * (stem / 2 + 0.9), -lip - 0.3),
            (side * (stem / 2 - 0.2), -lip - 2.6)]).close().extrude(T))
        legs = legs.union(barb)
    rin, rout = cab / 2, cab / 2 + 2.2
    cz = 2.4 + rout - 0.8
    ring = cq.Workplane("YZ").center(0, cz).circle(rout).circle(rin).extrude(T)
    mouth = cq.Workplane("YZ").center(0, cz + rout).rect(cab * 0.6, rout * 1.4).extrude(T)
    ring = ring.cut(mouth)
    clip = plate.union(legs).union(ring)
    # soften the long edges you touch; skip any edge too small to round
    try:
        clip = clip.edges("|X").fillet(0.3)
    except Exception:
        clip = clip.faces("<X or >X").edges().chamfer(0.3)
    return {"clip": clip}
