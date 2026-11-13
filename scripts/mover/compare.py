"""How much does each game move the seat through a Mover profile? Prints the biggest and the typical (RMS) lean.
usage: python3 scripts/mover/compare.py scripts/mover <profile.Mover> <folder with the csv recordings> [names...]"""
import sys; sys.path.insert(0,sys.argv[1])
import numpy as np, rig, mover
mods=mover.load_profile(sys.argv[2]); v=rig.variants()[0]
for game in (sys.argv[4:] or ["flight","coaster"]):
    parts,wg=mover.load_tel(f"{sys.argv[3]}/{game}.csv")
    air=wg<0.5
    P=mover.rig_pose(mods,parts)[air]
    L=np.array([rig.lengths(v,p) for p in P[::5]])-rig.MID
    acc=np.diff(L,2,axis=0)/(0.01**2)
    print(f"{game:10s} in the air {air.mean()*100:3.0f}% | roll: most {abs(P[:,4]).max():4.1f} typical {P[:,4].std():4.1f} | pitch: most {abs(P[:,5]).max():4.1f} typical {P[:,5].std():4.1f} | yaw: most {abs(P[:,3]).max():4.1f} typical {P[:,3].std():4.1f} deg"
          f" | actuator furthest {np.abs(L).max():4.0f} mm, typical {L.std():4.0f} mm, hardest jolt {np.abs(acc).max()/9810:4.2f} g")
