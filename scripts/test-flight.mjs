// Flight model checks. Run: node scripts/test-flight.mjs
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const F = require("../dashboard/fly/flightmodel.js");
const T = require("../dashboard/fly/terrain.js");
const hm = new T.HeightMap();
const env = { height: (x, z) => hm.height(x, z), paved: T.paved, colliders: T.colliders, wind: [0, 0, 0] };
const KT = 1.94384, FT = 3.28084;
let fails = 0;
const check = (name, ok, info = "") => { console.log((ok ? "PASS " : "FAIL ") + name + (info ? "  " + info : "")); if (!ok) fails++; };
const fmt = (n, d = 1) => Number(n).toFixed(d);
function run(fm, secs, inpFn, onTick) { const dt = 1 / 60; for (let t = 0; t < secs && !fm.crashed; t += dt) { fm.step(dt, inpFn(t, fm)); if (onTick) onTick(t, fm); } }
const start = (key, o) => { const fm = new F.FlightModel(key, env); const [x, z] = T.fromRunway(o.u ?? -700, o.v ?? 0); fm.reset({ x, z, heading: 62, ...o }); return fm; };

console.log("terrain: runway height", fmt(hm.height(0, 0)), "m; 3 km away", fmt(hm.height(3000, 1000)), "m");
check("runway is flat", Math.abs(hm.height(300, -150) - 38) < 0.01 && Math.abs(hm.height(-300, 120) - 38) < 0.01);

for (const key of ["trainer", "fighter"]) {
  console.log("\n=== " + key + " ===");
  // sitting still
  let fm = start(key, {});
  run(fm, 5, () => ({ pitch: 0, roll: 0, yaw: 0, throttle: 0, brake: 1, flaps: 0 }));
  check("rests on its wheels", !fm.crashed && Math.hypot(...fm.vel) < 0.2, `speed ${fmt(Math.hypot(...fm.vel), 3)} pitch ${fmt(fm.euler().pitch)} AGL ${fmt(fm.i.altAGL, 2)}`);

  // takeoff
  fm = start(key, {});
  const vr = fm.spec.vr * 1.12;
  let liftoff = null, d0 = fm.pos.slice();
  run(fm, 70, (t, m) => ({ pitch: m.i.ias > vr ? 0.35 : (key === "fighter" && m.i.ias > 20 ? -0.1 : 0), roll: 0, yaw: 0, throttle: 1, brake: 0, flaps: 0 }), (t, m) => { if (!liftoff && !m.i.onGround && m.i.ias > 15) liftoff = { t, d: Math.hypot(m.pos[0] - d0[0], m.pos[2] - d0[2]), ias: m.i.ias }; });
  check("takes off", !!liftoff && !fm.crashed, liftoff ? `liftoff after ${fmt(liftoff.d, 0)} m at ${fmt(liftoff.ias * KT, 0)} kt` : "never left the ground");
  check("climbs away", fm.i.altAGL > 120 && !fm.crashed, `${fmt(fm.i.altAGL * FT, 0)} ft after 70 s, ${fmt(fm.i.ias * KT, 0)} kt, vs ${fmt(fm.i.vs * 196.85, 0)} fpm`);
  check("stays on runway heading", Math.abs(((fm.i.heading - 62 + 540) % 360) - 180) < 8, `heading ${fmt(fm.i.heading, 1)}`);

  // level flight, hands off, assist on
  fm = start(key, { airborne: true, agl: 600, speed: fm.spec.cruise, heading: 62 });
  const h0 = fm.pos[1];
  run(fm, 60, () => ({ pitch: 0, roll: 0, yaw: 0, throttle: fm.spec.cruiseThrottle, flaps: 0 }));
  check("holds altitude hands off (assist)", !fm.crashed && Math.abs(fm.pos[1] - h0) < 40, `altitude change ${fmt(fm.pos[1] - h0)} m, speed ${fmt(fm.i.ias * KT, 0)} kt`);
  // pro mode level flight should at least stay well behaved for 30 s
  fm = start(key, { airborne: true, agl: 800, speed: fm.spec.cruise, heading: 62 }); fm.assist = false;
  let maxRoll = 0; run(fm, 30, () => ({ pitch: 0, roll: 0, yaw: 0, throttle: fm.spec.cruiseThrottle }), (t, m) => { maxRoll = Math.max(maxRoll, Math.abs(m.i.roll)); });
  check("pro mode hands off: no wild divergence", !fm.crashed && maxRoll < 25 && Math.abs(fm.i.pitch) < 25, `max roll ${fmt(maxRoll)}, pitch ${fmt(fm.i.pitch)}, speed ${fmt(fm.i.ias * KT, 0)} kt`);

  // turn
  fm = start(key, { airborne: true, agl: 800, speed: fm.spec.cruise, heading: 0 });
  let bank = 0, h10 = 0, h20 = 0;
  run(fm, 25, (t) => ({ pitch: 0, roll: t > 2 ? 0.5 : 0, yaw: 0, throttle: fm.spec.cruiseThrottle }), (t, m) => { if (t > 10) bank = m.i.roll; if (t <= 10) h10 = m.i.heading; if (t <= 20) h20 = m.i.heading; });
  const turnRate = ((h20 - h10 + 540) % 360 - 180) / 10;
  const expect = (F.G * Math.tan(32.5 * F.D2R) / fm.i.tas) / F.D2R;
  check("half stick gives a steady banked turn", Math.abs(bank - 32.5) < 6 && Math.abs(turnRate - expect) < 1.8, `bank ${fmt(bank)}, turn ${fmt(turnRate)}°/s (expected ${fmt(expect)}), altitude ${fmt(fm.i.altAGL, 0)} m AGL`);

  // roll rate (pro mode, full aileron)
  fm = start(key, { airborne: true, agl: 1500, speed: fm.spec.cruise, heading: 0 }); fm.assist = false;
  let peak = 0; run(fm, 3, () => ({ pitch: 0, roll: 1, yaw: 0, throttle: fm.spec.cruiseThrottle }), (t, m) => { peak = Math.max(peak, -m.w[2] / F.D2R); });
  check("roll rate is sensible", peak > 35 && peak < 140, `peak ${fmt(peak, 0)}°/s`);

  // stall (pro mode, power off, stick back)
  fm = start(key, { airborne: true, agl: 1500, speed: fm.spec.cruise * 0.8, heading: 0 }); fm.assist = false;
  let stalled = null; run(fm, 40, (t) => ({ pitch: 0.55 + (t > 5 ? 0.45 : 0), roll: 0, yaw: 0, throttle: 0 }), (t, m) => { if (!stalled && m.i.stall) stalled = { t, ias: m.i.ias }; });
  check("stalls when pulled back with no power", !!stalled && !fm.crashed, stalled ? `stall at ${fmt(stalled.ias * KT, 0)} kt after ${fmt(stalled.t, 1)} s` : "never stalled");
  run(fm, 22, (t) => ({ pitch: t < 3 ? -0.4 : 0.15, roll: 0, yaw: 0, throttle: 1 }));
  check("recovers with stick forward and power", !fm.crashed && !fm.i.stall, `ias ${fmt(fm.i.ias * KT, 0)} kt, AGL ${fmt(fm.i.altAGL, 0)} m`);

  // landing flown by a script: 3 degree glide in assist mode (stick -0.25 = -3 degrees), flare near the ground
  const [lx, lz] = T.fromRunway(-2900, 0);
  fm = start(key, { x: lx, z: lz, airborne: true, agl: 150, speed: fm.spec.vr * 1.5, heading: 62 });
  let td = null; const vApp = fm.spec.vr * 1.4;
  run(fm, 160, (t, m) => {
    const [u, v] = T.toRunway(m.pos[0], m.pos[2]), agl = m.i.altAGL;
    let pitch, thr;
    if (m.i.onGround) { pitch = 0.05; thr = 0; }
    else if (agl > 10) { pitch = -0.25; thr = clampn(0.3 + (vApp - m.i.ias) * 0.06, 0, 1); }
    else { pitch = clampn(-0.05 + (-m.i.vs - 0.6) * 0.15, -0.2, 0.3); thr = 0; }
    return { pitch, roll: clampn(-v * 0.003 - Math.sin((m.i.heading - 62) * F.D2R) * 1.2, -0.3, 0.3), yaw: 0, throttle: thr, brake: m.i.onGround && m.i.ias < 40 ? 1 : 0, flaps: 0.5 };
  }, (t, m) => { if (!td && m.i.onGround) td = { t, sink: -m.i.vs, ias: m.i.ias, u: T.toRunway(m.pos[0], m.pos[2])[0] }; });
  check("lands without crashing", !fm.crashed && !!td, td ? `touchdown at u=${fmt(td.u, 0)} m, ${fmt(td.ias * KT, 0)} kt, sink ${fmt(td.sink * 196.85, 0)} fpm` : `no touchdown; crashed=${fm.crashed} ${fm.crashReason}; AGL ${fmt(fm.i.altAGL, 0)} ias ${fmt(fm.i.ias * KT, 0)}`);
  check("comes to a stop", !fm.crashed && fm.i.gs < 3, `ground speed ${fmt(fm.i.gs * KT, 0)} kt, ${fmt(T.toRunway(fm.pos[0], fm.pos[2])[0], 0)} m along, ${fmt(T.toRunway(fm.pos[0], fm.pos[2])[1], 0)} m off centre`);
}
function clampn(v, a, b) { return v < a ? a : v > b ? b : v; }
console.log(fails ? `\n${fails} check(s) failed` : "\nAll checks passed");
process.exit(fails ? 1 : 0);
