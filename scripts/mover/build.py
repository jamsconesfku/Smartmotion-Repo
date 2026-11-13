"""Makes SmartMotion's FlyPT Mover profile from Sam's own profile: same modules, same rig measurements and output,
new pose filters and limits. Only the text of existing settings is changed, so Mover loads it as it loads the original.
usage: python3 scripts/mover/build.py docs/source/flypt-mover/smart_motion_game.Mover godot/package/SmartMotion-Games.Mover "13 Nov 2026"
Check a change with scripts/mover/replay.py before giving it to anyone (see docs/games/flypt-mover-profile.md)."""
import sys, re
src,dst=sys.argv[1],sys.argv[2]
raw=open(src,"rb").read().decode("utf-8-sig")

# the most the seat may move, all six at once, with every actuator still inside its 300 mm stroke (see rig.py)
LIMIT={"Sway":5,"Surge":5,"Heave":22,"Yaw":3,"Roll":6.5,"Pitch":7}

AIR={
 "pnlPitch.afcPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-60;60);0.2);110);110);110);4.4;1)",
 "pnlPitch.afcSurgeInPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-25;25);0.22);120);120);120);2.6;1)",
 "pnlPitch.chkMixSurgeInPitch":"True","pnlPitch.nudSurgeInPitchOutGain":"1",
 "pnlRoll.afcRollFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-90;90);0.12);110);110);110);6;1)",
 "pnlRoll.chkMixSwayInRoll":"False",
 "pnlYaw.afcYawFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMAHP(GAIN(CROP(VALUE;-60;60);0.12);600);100);100);2.7;1)",
 "pnlHeave.afcHeaveFilter.txtFilterText":"LOGISTIC(EMAHP(EMALP(EMALP(GAIN(CROP(VALUE;-25;25);1.8);110);110);500);20;1)",
 "pnlHeave.nudHeaveOutGain":"1",
 "pnlSurge.nudSurgeOutGain":"0","pnlSway.nudSwayOutGain":"0",
}
GROUND={
 "pnlPitch.afcPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-40;40);0.2);110);110);110);2;1)",
 "pnlPitch.afcSurgeInPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-30;30);0.3);110);110);110);5;1)",
 "pnlPitch.chkMixSurgeInPitch":"True","pnlPitch.nudSurgeInPitchOutGain":"1",
 "pnlRoll.afcRollFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-40;40);0.12);110);110);110);2;1)",
 "pnlRoll.afcSwayInRollFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-30;30);0.28);110);110);110);4.5;1)",
 "pnlRoll.chkMixSwayInRoll":"True","pnlRoll.nudSwayInRollOutGain":"1",
 "pnlYaw.afcYawFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMAHP(GAIN(CROP(VALUE;-60;60);0.1);500);120);120);2.7;1)",
 "pnlHeave.afcHeaveFilter.txtFilterText":"LOGISTIC(EMAHP(EMALP(EMALP(GAIN(CROP(VALUE;-15;15);2.5);100);100);400);20;1)",
 "pnlHeave.nudHeaveOutGain":"1",
 "pnlSurge.nudSurgeOutGain":"0","pnlSway.nudSwayOutGain":"0",
}
for d,v in LIMIT.items():
    for P in (AIR,GROUND): P["pnl%s.nud%sRange"%(d,d)]=str(v)
RIG={"NUDGain":"1","CHKAutoGain":"False"}
for d,v in LIMIT.items(): RIG["NUD%sLimit"%d]=str(v)

def block(name,tag):
    m=re.search(r"<%s>\s*<Type>[^<]*</Type>\s*<Name>%s</Name>.*?</%s>"%(tag,re.escape(name),tag),raw,re.S)
    assert m,name; return m
def patch(name,tag,changes,extra=None):
    global raw
    m=block(name,tag); b=m.group(0)
    for k,v in changes.items():
        pat=r"(<%s>)[^<]*(</%s>)"%(re.escape(k),re.escape(k))
        assert len(re.findall(pat,b))==1,(name,k)
        b=re.sub(pat,lambda mm:mm.group(1)+v+mm.group(2),b)
    if extra: b=extra(b)
    raw=raw[:m.start()]+b+raw[m.end():]
patch("AIR","POSE",AIR)
def ground_inputs(b):
    # the GROUND pose listened to the game's AIR values as well as its GROUND values, so it moved in the air too
    line=re.search(r"[ \t]*<item>SOURCE :: XPLANE 11 \(UDP\) AIR</item>\r?\n",b); assert line
    return b[:line.start()]+b[line.end():]
patch("GROUND","POSE",GROUND,ground_inputs)
patch("MotionXP-PRIME_FLY","RIG",RIG)
raw=raw.replace("<ShareName></ShareName>","<ShareName>SmartMotion games (Flight, Racing, Space, Coaster)</ShareName>",1)
raw=raw.replace("<ShareDescription></ShareDescription>","<ShareDescription>For SmartMotion Flight v1.19+ through the X-Plane 11 (UDP) source. Smooth filters and limits that keep every actuator inside its 300 mm stroke. Made %s.</ShareDescription>"%sys.argv[3],1)
open(dst,"wb").write(b"\xef\xbb\xbf"+raw.encode("utf-8"))
print("written",dst)
