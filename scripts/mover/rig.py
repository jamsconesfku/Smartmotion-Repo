"""MotionXP-PRIME_FLY as set up in Sam's FlyPT Mover profile: inverse kinematics of the linear hexapod.
L1/L2 = long/short spacing of the pivots on the moving platform, L3/L4 on the base (hexagons with alternating sides).
Middle = actuator length pin to pin at mid travel (mm), Range = stroke (mm).
The profile does not say which way round the frames sit or which neighbour each actuator goes to, so every
plausible variant is checked and the worst one is used."""
import numpy as np, itertools, math
L1,L2,L3,L4=1175.0,70.0,700.0,1300.0
MID,RANGE=1250.0,300.0
def hexagon(a,b,phase):
    """6 points on a circle; alternating sides a (between pairs) and b (inside a pair); pairs centred at phase+k*120 deg"""
    R=math.sqrt((a*a+a*b+b*b)/3.0); half=math.asin(b/2/R)
    pts=[]
    for k in range(3):
        c=math.radians(phase)+k*2*math.pi/3
        for s in(-1,1): pts.append((R*math.cos(c+s*half),R*math.sin(c+s*half)))
    return np.array(pts),R
def variants():
    out=[]
    for plat_phase in (90,270,0,180):          # a platform corner at the front, back, right or left
        P,Rp=hexagon(L1,L2,plat_phase)
        # base pivots: taken as pairs L4 apart... the same six points either way; each platform pivot goes to the nearest free base pivot
        B,Rb=hexagon(L3,L4,plat_phase)         # pairs (spacing L4) centred under the platform corners
        B2,_=hexagon(L4,L3,plat_phase+60)      # pairs (spacing L3) centred between them
        for name,BB in (("wide",B),("crossed",B2)):
            # match each platform pivot to nearest base pivot on its own side
            used=set();legs=[]
            for i,p in enumerate(P):
                ang=math.atan2(p[1],p[0]); best=None
                for j,b in enumerate(BB):
                    if j in used: continue
                    d=np.hypot(*(p-b))
                    side=(math.atan2(b[1],b[0])-math.atan2(P[i^1][1],P[i^1][0]))  # prefer away from its twin
                    if best is None or d<best[0]: best=(d,j)
                used.add(best[1]);legs.append((i,best[1]))
            d0=np.hypot(*(P[legs[0][0]]-BB[legs[0][1]]))
            if d0>=MID: continue
            h=math.sqrt(MID*MID-d0*d0)
            out.append((f"corner@{plat_phase} {name}",P,BB,legs,h))
    return out
def rot(yaw,roll,pitch):
    """x right, y forward, z up (mm). pitch + = nose up, roll + = right side down, yaw + = nose right"""
    y,r,p=map(math.radians,(yaw,roll,pitch))
    Rz=np.array([[math.cos(-y),-math.sin(-y),0],[math.sin(-y),math.cos(-y),0],[0,0,1]])
    Rx=np.array([[1,0,0],[0,math.cos(p),-math.sin(p)],[0,math.sin(p),math.cos(p)]])
    Ry=np.array([[math.cos(r),0,math.sin(r)],[0,1,0],[-math.sin(r),0,math.cos(r)]])
    return Rz@Rx@Ry
def lengths(v,pose):
    """pose = sway, surge, heave (mm), yaw, roll, pitch (deg) -> six actuator lengths"""
    _,P,B,legs,h=v
    R=rot(pose[3],pose[4],pose[5]); t=np.array([pose[0],pose[1],pose[2]+h])
    out=[]
    for i,j in legs:
        p=R@np.array([P[i][0],P[i][1],0.0])+t
        out.append(np.linalg.norm(p-np.array([B[j][0],B[j][1],0.0])))
    return np.array(out)
def worst(box,vs=None,samples=0,rng=None):
    """largest |length - middle| over all corners of the box (and random points inside), worst variant"""
    vs=vs or variants(); w=0.0
    pts=[tuple(s*b for s,b in zip(sg,box)) for sg in itertools.product((-1,0,1),repeat=6)]
    for v in vs:
        for p in pts:
            w=max(w,np.abs(lengths(v,p)-MID).max())
    return w
if __name__=="__main__":
    vs=variants()
    for v in vs: print(v[0],"height at mid travel %.0f mm"%v[4],"lengths at rest",np.round(lengths(v,(0,0,0,0,0,0))))
    print("platform pivot circle radius %.0f mm, base %.0f mm"%(hexagon(L1,L2,0)[1],hexagon(L3,L4,0)[1]))
    for nm,box in [("old profile, AIR ranges x rig gain 0.5",(2.5,2.5,2.5,5,15,15)),("old, GROUND ranges x 0.5",(2.5,2.5,75,2.5,7.5,12.5)),
                   ("old, pitch alone 15",(0,0,0,0,0,15)),("old, roll alone 15",(0,0,0,0,15,0)),("old AIR+GROUND summed x0.5",(5,5,77.5,7.5,22.5,27.5))]:
        print("%-42s worst actuator travel from middle %.0f mm (limit %.0f)"%(nm,worst(box,vs),RANGE/2))
