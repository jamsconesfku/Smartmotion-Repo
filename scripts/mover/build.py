"""Makes SmartMotion's FlyPT Mover profile from Sam's own profile: same modules, same rig measurements and output,
new pose filters and limits. Only the text of existing settings is changed, so Mover loads it as it loads the original.
usage: python3 scripts/mover/build.py docs/source/flypt-mover/smart_motion_game.Mover godot/package/SmartMotion-Games.Mover "13 Nov 2026"
Check a change with scripts/mover/replay.py before giving it to anyone (see docs/games/flypt-mover-profile.md)."""
import sys, re
src,dst=sys.argv[1],sys.argv[2]
raw=open(src,"rb").read().decode("utf-8-sig")

# v2 (Sam, 13 Nov 2026: "keep the limits as before but make the internal pose profiles work better"):
# the pose ranges, the rig's limits and the rig gain (0.5) are left exactly as in Sam's profile. Only the pose
# filters, gains and mixes change. The seat moves half of what a pose says (rig gain 0.5), so a soft limit of 16
# here is 8 degrees at the seat. The soft limits (LOGISTIC) are set so that in normal use the actuators stay
# inside their 300 mm stroke, but the hard limits no longer guarantee it (see docs/games/flypt-mover-profile.md).
AIR={
 "pnlPitch.afcPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-60;60);0.6);110);110);110);14;1)",
 "pnlPitch.afcSurgeInPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-25;25);0.55);120);120);120);6;1)",
 "pnlPitch.chkMixSurgeInPitch":"True","pnlPitch.nudSurgeInPitchOutGain":"1",
 "pnlRoll.afcRollFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-90;90);0.4);110);110);110);18;1)",
 "pnlRoll.chkMixSwayInRoll":"False",
 "pnlYaw.afcYawFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMAHP(GAIN(CROP(VALUE;-60;60);0.35);600);100);100);8;1)",
 "pnlHeave.afcHeaveFilter.txtFilterText":"LOGISTIC(EMAHP(EMALP(EMALP(GAIN(CROP(VALUE;-25;25);0.5);110);110);500);4.5;1)",
 "pnlHeave.nudHeaveOutGain":"1",
 "pnlSurge.nudSurgeOutGain":"0","pnlSway.nudSwayOutGain":"0",
}
GROUND={
 "pnlPitch.afcPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-40;40);0.5);110);110);110);5;1)",
 "pnlPitch.afcSurgeInPitchFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-30;30);0.9);135);135);135);16;1)",
 "pnlPitch.chkMixSurgeInPitch":"True","pnlPitch.nudSurgeInPitchOutGain":"1",
 "pnlRoll.afcRollFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-40;40);0.3);110);110);110);3;1)",
 "pnlRoll.afcSwayInRollFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMALP(GAIN(CROP(VALUE;-30;30);0.7);135);135);135);11.5;1)",
 "pnlRoll.chkMixSwayInRoll":"True","pnlRoll.nudSwayInRollOutGain":"1",
 "pnlYaw.afcYawFilter.txtFilterText":"LOGISTIC(EMALP(EMALP(EMAHP(GAIN(CROP(VALUE;-60;60);0.25);500);120);120);4.5;1)",
 "pnlHeave.afcHeaveFilter.txtFilterText":"LOGISTIC(EMAHP(EMALP(EMALP(GAIN(CROP(VALUE;-15;15);6);100);100);400);50;1)",
 "pnlHeave.nudHeaveOutGain":"1",
 "pnlSurge.nudSurgeOutGain":"0","pnlSway.nudSwayOutGain":"0",
}
RIG={}

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
raw=raw.replace("<ShareDescription></ShareDescription>","<ShareDescription>For SmartMotion Flight v1.19+ through the X-Plane 11 (UDP) source. Sam's limits and rig gain, with smooth pose filters for every game. Made %s.</ShareDescription>"%sys.argv[3],1)
open(dst,"wb").write(b"\xef\xbb\xbf"+raw.encode("utf-8"))
print("written",dst)
