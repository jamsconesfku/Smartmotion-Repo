"""Replays recorded game data through a FlyPT Mover profile (mover.py) and the rig (rig.py), and reports how far and
how hard the actuators would move.
usage: python3 scripts/mover/replay.py scripts/mover <profile.Mover> <folder with flight.csv race.csv coaster.csv ship.csv> [--both]
Record the data with the game: godot --headless --fixed-fps 60 --path godot -- --auto --stunt --game=race --autopilot
  --tel_dump=race.csv --quit_after=150   (flight: --game=flight; coaster: --game=coaster; ship: --game=space --space_start=earth)"""
import sys; sys.path.insert(0,sys.argv[1])
import numpy as np, rig, mover
prof=sys.argv[2]; teldir=sys.argv[3]
mods=mover.load_profile(prof)
v=rig.variants()[0]
half=rig.RANGE/2
print("profile:",prof.split("/")[-1])
for mode in (["2/(N+1)","1/N"] if "--both" in sys.argv else ["2/(N+1)"]):
  mover.ALPHA_MODE=mode
  for hz,blend in ([(60,0.5),(20,0.0)] if "--both" in sys.argv else [(60,0.5)]):
    print(f" EMA weight {mode}, game data {hz} a second, air/ground change {'gradual' if blend else 'instant'}")
    for game in ["flight","race","coaster","ship"]:
        parts,wg=mover.load_tel(f"{teldir}/{game}.csv",hz,blend)
        P=mover.rig_pose(mods,parts)
        step=5   # every 10 ms
        L=np.array([rig.lengths(v,p) for p in P[::step]])-rig.MID
        dt=mover.DT*step
        vel=np.diff(L,axis=0)/dt; acc=np.diff(vel,axis=0)/dt
        over=(np.abs(L).max(1)>half).mean()*100
        print(f"  {game:8s} pose max: sway {abs(P[:,0]).max():5.1f} surge {abs(P[:,1]).max():5.1f} heave {abs(P[:,2]).max():5.1f} mm, yaw {abs(P[:,3]).max():4.1f} roll {abs(P[:,4]).max():4.1f} pitch {abs(P[:,5]).max():4.1f} deg"
              f" | actuator: furthest from middle {np.abs(L).max():4.0f} mm (stroke allows {half:.0f}), beyond the stroke {over:4.1f}% of the time,"
              f" top speed {np.abs(vel).max():5.0f} mm/s, hardest jolt {np.abs(acc).max()/9810:5.2f} g, typical jolt {np.percentile(np.abs(acc),99)/9810:5.2f} g")
