"""A model of the parts of FlyPT Mover 3.5 that Sam's profile uses, to replay recorded game data through a profile.
Filters as documented on flyptmover.com (Mover 3.5 > Basics > Filters): EMALP = exponential moving average over N
samples (one sample = the calculation time, 2 ms in this profile), EMAHP = VALUE - EMALP, LOGISTIC(v;range;speed)
approaches +-range without reaching it, CROP/MINCROP/MAXCROP clamp, GAIN multiplies.
Not documented exactly: the EMA's weight for N samples (2/(N+1) is the textbook one; 1/N is also tried) and LOGISTIC's
curve (range*tanh(speed*v/range) matches the one worked example on the forum: LOGISTIC(20;10;1) = 9.64)."""
import numpy as np, math, csv, xml.etree.ElementTree as ET
DT=0.002
ALPHA_MODE="2/(N+1)"
def _alpha(n):
    n=max(float(n),1.0)
    return 2.0/(n+1.0) if ALPHA_MODE=="2/(N+1)" else 1.0/n
def emalp(x,n):
    a=_alpha(n)
    if a>=1.0: return x.copy()
    y=np.empty_like(x); acc=float(x[0]); b=1.0-a
    for i,v in enumerate(x.tolist()):
        acc=b*acc+a*v; y[i]=acc
    return y
def parse(expr):
    expr=expr.replace(" ","")
    pos=0
    def node():
        nonlocal pos
        j=pos
        while pos<len(expr) and expr[pos] not in "(;)": pos+=1
        tok=expr[j:pos]
        if pos<len(expr) and expr[pos]=="(":
            pos+=1; args=[node()]
            while expr[pos]==";": pos+=1; args.append(node())
            assert expr[pos]==")",expr; pos+=1
            return (tok.upper(),args)
        return tok
    n=node(); assert pos==len(expr),(expr,pos); return n
def run(n,x):
    if isinstance(n,str):
        return x if n.upper()=="VALUE" else float(n)
    f,a=n; v=run(a[0],x)
    p=[run(q,x) for q in a[1:]]
    if f=="EMALP": return emalp(v,p[0])
    if f=="EMAHP": return v-emalp(v,p[0])
    if f=="GAIN": return v*p[0]
    if f=="CROP": return np.clip(v,p[0],p[1])
    if f=="MINCROP": return np.maximum(v,p[0])
    if f=="MAXCROP": return np.minimum(v,p[0])
    if f=="LOGISTIC": return p[0]*np.tanh(p[1]*v/p[0])
    if f=="ABS": return np.abs(v)
    if f=="LDYNLP": return v
    raise ValueError(f)
def filt(expr,x): return run(parse(expr),x)

DOF=["Sway","Surge","Heave","Yaw","Roll","Pitch"]
VALUE_OF={"Pitch speed (º/s)":"Q","Roll speed (º/s)":"P","Yaw speed (º/s)":"R","Vertical acceleration (m/s²)":"vert","Longitudinal acceleration (m/s²)":"long","Lateral acceleration (m/s²)":"lat"}
def load_profile(path):
    r=ET.parse(path).getroot(); mods={}
    for ch in r:
        c=ch.find("CONTROLS")
        if c is None: continue
        d={}
        for e in c:
            d[e.tag]=[i.text for i in e] if len(e) else (e.text or "")
        mods[ch.findtext("Name")]=d
    return mods
def pose(m,src):
    """src: dict of arrays for this pose's inputs (already summed over the sources ticked). Returns dof -> array"""
    out={}
    for d in DOF:
        p="pnl"+d+"."
        x=src[VALUE_OF[m[p+"ddl"+d+"Value"]]]*float(m[p+"nud"+d+"InGain"])
        y=filt(m[p+"afc"+d+"Filter.txtFilterText"],x)*float(m[p+"nud"+d+"OutGain"])
        if d=="Pitch" and m["pnlPitch.chkMixSurgeInPitch"]=="True":
            y=y+filt(m["pnlPitch.afcSurgeInPitchFilter.txtFilterText"],src["long"])*float(m["pnlPitch.nudSurgeInPitchOutGain"])
        if d=="Roll" and m["pnlRoll.chkMixSwayInRoll"]=="True":
            y=y+filt(m["pnlRoll.afcSwayInRollFilter.txtFilterText"],src["lat"])*float(m["pnlRoll.nudSwayInRollOutGain"])
        rg=float(m[p+"nud"+d+"Range"])
        out[d]=np.clip(y,-rg,rg)
    return out
def rotm(pitch,roll,hdg):
    p,r,h=map(math.radians,(pitch,roll,hdg))
    Ry=np.array([[math.cos(-h),0,math.sin(-h)],[0,1,0],[-math.sin(-h),0,math.cos(-h)]])
    Rx=np.array([[1,0,0],[0,math.cos(p),-math.sin(p)],[0,math.sin(p),math.cos(p)]])
    Rz=np.array([[math.cos(-r),-math.sin(-r),0],[math.sin(-r),math.cos(-r),0],[0,0,1]])
    return Ry@Rx@Rz
def load_tel(path,hz=60,blend=0.5):
    """game frames (60 a second) -> what Mover's source holds at 500 samples a second (each value held until the next
    packet), split into AIR and GROUND shares"""
    rows=list(csv.DictReader(open(path)))
    G=9.81; n=len(rows)
    k={c:np.array([float(r[c]) for r in rows]) for c in rows[0]}
    lon=np.zeros(n);lat=np.zeros(n);ver=np.zeros(n)
    for i in range(n):
        R=rotm(k["theta"][i],k["phi"][i],k["psi"][i])
        a=np.array([k["g_side"][i],k["g_nrml"][i],k["g_axil"][i]])*G+R.T@np.array([0,-G,0])   # movement, gravity taken out, seat axes
        lat[i]=a[0];ver[i]=a[1];lon[i]=-a[2]
    step=max(1,round(60/hz))
    idx=(np.arange(int(n/60/DT))*DT*60).astype(int); idx=(idx//step)*step
    s={"P":k["P"][idx],"Q":k["Q"][idx],"R":k["R"][idx],"long":lon[idx],"lat":lat[idx],"vert":ver[idx]}
    og=k["on_ground"][idx]
    if blend>0:
        m=int(blend/DT); wg=np.convolve(np.concatenate([np.full(m,og[0]),og]),np.ones(m)/m,"valid")[:len(og)]
    else: wg=og
    air={c:v*(1-wg) for c,v in s.items()}; gnd={c:v*wg for c,v in s.items()}
    return {"AIR":air,"GROUND":gnd},wg
def rig_pose(mods,parts,rigname="MotionXP-PRIME_FLY"):
    """Sum the poses ticked in the rig, with the sources ticked in each pose; rig gain, then the rig's limits."""
    rg=mods[rigname]; tot={d:0.0 for d in DOF}
    for pn in rg["TVInputSelection"]:
        m=mods[pn]; src=None
        for it in m["TVInputSelection"]:
            if "XPLANE" not in it: continue
            part=parts["AIR" if it.strip().endswith("AIR") else "GROUND"]
            src=part if src is None else {c:src[c]+part[c] for c in part}
        if src is None: continue
        po=pose(m,src)
        for d in DOF: tot[d]=tot[d]+po[d]
    g=float(rg["NUDGain"])
    return np.stack([np.clip(tot[d]*g,-float(rg["NUD"+d+"Limit"]),float(rg["NUD"+d+"Limit"])) for d in DOF],1)
