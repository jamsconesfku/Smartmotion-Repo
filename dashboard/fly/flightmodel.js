/* SmartMotion Flight: flight model.
   Pure maths, no graphics, so it runs in the browser and in Node tests (scripts/test-flight.mjs).
   World axes: x east, y up, z south (north is -z), metres. Body axes: x right, y up, z back (nose is -z).
   Angular rates are in body axes: +x nose up, +y yaw left, +z roll left (right wing up). */
(function (root) {
'use strict';
const D2R = Math.PI / 180, G = 9.80665;
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const lerp = (a, b, t) => a + (b - a) * t;
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
// quaternions are [x, y, z, w], body to world
const qmul = (a, b) => [a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1], a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3], a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]];
const qinv = (q) => [-q[0], -q[1], -q[2], q[3]];
function qrot(q, v) {
  const x = q[0], y = q[1], z = q[2], w = q[3];
  const tx = 2 * (y * v[2] - z * v[1]), ty = 2 * (z * v[0] - x * v[2]), tz = 2 * (x * v[1] - y * v[0]);
  return [v[0] + w * tx + (y * tz - z * ty), v[1] + w * ty + (z * tx - x * tz), v[2] + w * tz + (x * ty - y * tx)];
}
const qaxis = (ax, a) => { const s = Math.sin(a / 2); return [ax[0] * s, ax[1] * s, ax[2] * s, Math.cos(a / 2)]; };
function qnorm(q) { const l = Math.hypot(q[0], q[1], q[2], q[3]) || 1; return [q[0] / l, q[1] / l, q[2] / l, q[3] / l]; }
// heading (clockwise from north), pitch (nose up), roll (right wing down); all radians
function qfromHPR(h, p, r) { return qnorm(qmul(qmul(qaxis([0, 1, 0], -h), qaxis([1, 0, 0], p)), qaxis([0, 0, 1], -r))); }

/* ---------- aircraft ---------- */
const SPECS = {
  trainer: {
    key: 'trainer', name: 'Light Trainer', blurb: 'Forgiving four-seat tourer. Slow, stable and easy to land.',
    mass: 1100, S: 16.2, b: 11.0, c: 1.5, I: [1825, 2666, 1285],
    clA: 4.6, cl0: 0.31, aStall: 16 * D2R, aStallN: -14 * D2R, clFlap: 0.42,
    cd0: 0.031, cdFlap: 0.04, k: 0.057,
    cm0: 0.04, cmA: -0.89, cmQ: -14, cmDe: 1.3, deMax: 0.44,
    rollP: -0.47, rollB: 0.09, rollDa: 0.18, daMax: 0.35,
    yawB: -0.07, yawR: -0.11, yawDr: 0.07, drMax: 0.38, yawDa: 0.02, cyB: -0.31,
    power: 119e3, eta: 0.8, tStatic: 2600, propSlip: 220,
    gear: [{ p: [-1.15, -1.05, 0.25], brake: true }, { p: [1.15, -1.05, 0.25], brake: true }, { p: [0, -1.05, -1.5], steer: true }],
    gearK: 50000, gearC: 3500,
    hit: [[0, -0.2, -2.5], [0, 0.6, 5.6], [-5.5, 0.9, -0.3], [5.5, 0.9, -0.3], [0, -0.7, 0.3], [0, 1.0, 0.5]],
    eye: [-0.32, 0.5, -0.15], cruise: 55, cruiseThrottle: 0.62, vr: 26, rpmIdle: 700, rpmMax: 2700,
  },
  // Scottish Aviation Bulldog 120 (Skysmart's G-SMAT, ex-RAF XX658): 10.06 m span, 12.02 m2 wing, 200 hp
  // Lycoming IO-360, about 1,000 kg with two crew. Clean stall about 55 kt, top speed about 130 kt, aerobatic.
  bulldog: {
    key: 'bulldog', name: 'Bulldog', blurb: 'Skysmart\'s ex-RAF Scottish Aviation Bulldog trainer. Crisp, aerobatic and honest.',
    mass: 1000, S: 12.02, b: 10.06, c: 1.2, I: [1450, 2150, 1050],
    clA: 4.8, cl0: 0.25, aStall: 16 * D2R, aStallN: -14 * D2R, clFlap: 0.45,
    cd0: 0.04, cdFlap: 0.045, k: 0.06,
    cm0: 0.035, cmA: -0.85, cmQ: -13, cmDe: 1.25, deMax: 0.44,
    rollP: -0.45, rollB: 0.08, rollDa: 0.21, daMax: 0.38,
    yawB: -0.07, yawR: -0.11, yawDr: 0.075, drMax: 0.38, yawDa: 0.02, cyB: -0.3,
    power: 149e3, eta: 0.7, tStatic: 3300, propSlip: 240,
    gear: [{ p: [-1.03, -1.05, 0.4], brake: true }, { p: [1.03, -1.05, 0.4], brake: true }, { p: [0, -1.05, -1.55], steer: true }],
    gearK: 46000, gearC: 3200,
    hit: [[0, -0.15, -2.4], [0, 0.3, 4.75], [-5.0, 0.08, 0.1], [5.0, 0.08, 0.1], [0, -0.62, 0.3], [0, 0.98, 0.25]],
    eye: [-0.3, 0.68, 0.22], cruise: 55, cruiseThrottle: 0.65, vr: 27, rpmIdle: 700, rpmMax: 2700,
  },
  fighter: {
    key: 'fighter', name: 'WW2 Fighter', blurb: 'Fast single-seat fighter. Powerful and lively: needs a firm hand.',
    mass: 3000, S: 22.5, b: 11.2, c: 2.1, I: [8000, 11000, 4500],
    clA: 4.4, cl0: 0.18, aStall: 15 * D2R, aStallN: -13 * D2R, clFlap: 0.35,
    cd0: 0.0215, cdFlap: 0.04, k: 0.07,
    cm0: 0.03, cmA: -0.8, cmQ: -14, cmDe: 1.1, deMax: 0.44,
    rollP: -0.5, rollB: 0.08, rollDa: 0.2, daMax: 0.38,
    yawB: -0.08, yawR: -0.12, yawDr: 0.07, drMax: 0.36, yawDa: 0.02, cyB: -0.3,
    power: 1100e3, eta: 0.82, tStatic: 11000, propSlip: 330,
    gear: [{ p: [-1.9, -1.45, -0.2], brake: true }, { p: [1.9, -1.45, -0.2], brake: true }, { p: [0, -1.0, 5.1], steer: true }],
    gearK: 136000, gearC: 9500, brakeMu: 0.4, tailDragger: true,
    hit: [[0, -0.1, -3.2], [0, 0.4, 5.9], [-5.6, -0.2, 0], [5.6, -0.2, 0], [0, -0.8, 0.2], [0, -0.95, -3.1]],
    eye: [0, 0.6, -0.9], cruise: 90, cruiseThrottle: 0.5, vr: 40, rpmIdle: 800, rpmMax: 3000,
  },
};

class FlightModel {
  /* env: { height(x,z), paved(x,z)?, colliders?: [{cx,cz,c,s,hu,hv,top}], wind?: [x,y,z] } */
  constructor(specKey, env) {
    this.spec = SPECS[specKey] || SPECS.trainer;
    this.env = env;
    this.events = [];
    this.assist = true;
    this.reset({ x: 0, z: 0, heading: 0 });
  }
  reset(o) {
    const sp = this.spec, h = (o.heading || 0) * D2R;
    this.pos = [o.x || 0, 0, o.z || 0];
    this.vel = [0, 0, 0]; this.w = [0, 0, 0];
    this.acc = 0; this.t = 0;
    this.crashed = false; this.crashReason = '';
    this.surf = { e: 0, a: 0, r: 0 };
    this.engine = o.throttle || 0; this.steer = 0;
    this.gammaInt = 0; this.airborneT = 0; this.groundT = 1; this.contacts = 0;
    this.touchdownDone = true; this.maxSink = 0; this.specForce = [0, G, 0];
    this.flaps = 0; this.wind = this.env.wind || [0, 0, 0];
    this.eLast = 0; this.stallWarn = false; this.stalled = false;
    if (o.airborne != null) {
      const gy = this.env.height(this.pos[0], this.pos[2]);
      this.pos[1] = gy + (o.agl || 500);
      this.q = qfromHPR(h, 0, 0);
      this.vel = mul(qrot(this.q, [0, 0, -1]), o.speed || sp.cruise);
      this.touchdownDone = false; this.airborneT = 5; this.groundT = 0;
    } else {
      const gy = this.env.height(this.pos[0], this.pos[2]);
      const low = Math.min(...sp.gear.map((g) => g.p[1]));
      const tail = sp.gear.find((g) => g.p[2] > 1);
      const pitch = tail ? Math.asin(clamp((tail.p[1] - low) / (tail.p[2] + 0.3), 0, 0.3)) : 0;
      this.q = qfromHPR(h, pitch, 0);
      this.pos[1] = gy - low * Math.cos(pitch) + 0.02;
      this.touchdownDone = true;
      for (let i = 0; i < 240; i++) this._sub(1 / 120, { pitch: 0, roll: 0, yaw: 0, throttle: 0, brake: 1, flaps: 0, trim: 0 });
      this.vel = [0, 0, 0]; this.w = [0, 0, 0]; this.events = []; this.touchdownDone = true; this.airborneT = 0;
    }
    this._instruments();
  }
  step(dt, inp) {
    const H = 1 / 120;
    this.acc += Math.min(dt, 0.1);
    let n = 0;
    while (this.acc >= H && n < 24) { this._sub(H, inp); this.acc -= H; n++; }
    this._instruments();
  }
  consumeEvents() { const e = this.events; this.events = []; return e; }

  euler() {
    const f = qrot(this.q, [0, 0, -1]), u = qrot(this.q, [0, 1, 0]), r = qrot(this.q, [1, 0, 0]);
    let hd = Math.atan2(f[0], -f[2]) / D2R; if (hd < 0) hd += 360;
    return { heading: hd, pitch: Math.asin(clamp(f[1], -1, 1)) / D2R, roll: Math.atan2(-r[1], u[1]) / D2R };
  }

  // lift and drag coefficients for angle of attack a (rad)
  _coef(a, flap) {
    const sp = this.spec, cl0 = sp.cl0 + sp.clFlap * flap;
    const clMax = cl0 + sp.clA * sp.aStall, clMin = cl0 + sp.clA * sp.aStallN;
    let cl = cl0 + sp.clA * a;
    const flat = 1.1 * Math.sin(2 * a);
    if (a > sp.aStall) cl = lerp(clMax, flat, sstep(sp.aStall, sp.aStall + 0.14, a));
    else if (a < sp.aStallN) cl = lerp(clMin, flat, sstep(sp.aStallN, sp.aStallN - 0.14, a));
    const post = Math.max(sstep(sp.aStall, sp.aStall + 0.2, a), sstep(sp.aStallN, sp.aStallN - 0.2, a));
    const cd = sp.cd0 + sp.cdFlap * flap * flap + sp.k * cl * cl + 1.3 * Math.sin(a) * Math.sin(a) * post;
    return { cl, cd };
  }

  // stick inputs -> control surface commands (-1..1)
  _controls(h, inp, V, alpha, beta, gamma, phi, onGround) {
    const sp = this.spec, s = this;
    let e, a, r;
    if (onGround || !this.assist || V < 18) {
      e = inp.pitch + (inp.trim || 0); a = inp.roll; r = inp.yaw;
      this.gammaInt = 0;
    } else {
      // pitch: stick commands flight path angle; roll: stick commands bank angle; rudder is coordinated
      let gT = inp.pitch >= 0 ? inp.pitch * 17 * D2R : inp.pitch * 12 * D2R;
      gT += (inp.trim || 0) * 16 * D2R;   // Easy mode: the trim sets a hands-off climb or descent (full trim: 8 degrees)
      const aLim = 0.88 * sp.aStall;
      if (alpha > aLim) gT = Math.min(gT, gamma - 4 * (alpha - aLim));
      const gErr = gT - gamma;
      this.gammaInt = clamp(this.gammaInt + 0.25 * gErr * h, -0.25, 0.25);
      const qCmd = clamp(2.0 * gErr, -0.5, 0.5);
      const ff = -(sp.cm0 + sp.cmA * alpha) / (sp.cmDe * sp.deMax);
      e = ff + 0.9 * (qCmd - s.w[0]) + this.gammaInt;
      const phiT = inp.roll * 65 * D2R;
      const pCmd = clamp(2.0 * (phiT - phi), -1.5, 1.5);
      a = 0.7 * (pCmd - (-s.w[2]));
      r = 1.4 * beta - 0.5 * (-s.w[1]) + inp.yaw;
    }
    return { e: clamp(e, -1, 1), a: clamp(a, -1, 1), r: clamp(r, -1, 1) };
  }

  _sub(h, inp) {
    const sp = this.spec, env = this.env;
    if (this.crashed) {
      this.vel = mul(this.vel, 1 - 3 * h); this.w = mul(this.w, 1 - 4 * h);
      this.pos = add(this.pos, mul(this.vel, h)); return;
    }
    this.t += h;
    const qi = qinv(this.q);
    const velRel = sub(this.vel, this.wind), V = len(velRel);
    const va = qrot(qi, velRel);
    const rho = 1.225 * Math.exp(-Math.max(this.pos[1], 0) / 8500);
    const qbar = 0.5 * rho * V * V;
    const alpha = V > 1 ? Math.atan2(-va[1], -va[2]) : 0;
    const beta = V > 1 ? Math.asin(clamp(va[0] / V, -1, 1)) : 0;
    const spd = len(this.vel);
    const gamma = spd > 3 ? Math.asin(clamp(this.vel[1] / spd, -1, 1)) : 0;
    const f = qrot(this.q, [0, 0, -1]), u = qrot(this.q, [0, 1, 0]), rr = qrot(this.q, [1, 0, 0]);
    const phi = Math.atan2(-rr[1], u[1]);
    const onGround = this.contacts > 0;

    // controls
    const cmd = this._controls(h, inp, V, alpha, beta, gamma, phi, onGround);
    const rate = 4.5 * h;
    this.surf.e += clamp(cmd.e - this.surf.e, -rate, rate);
    this.surf.a += clamp(cmd.a - this.surf.a, -rate, rate);
    this.surf.r += clamp(cmd.r - this.surf.r, -rate, rate);
    this.flaps += clamp((inp.flaps || 0) - this.flaps, -0.5 * h, 0.5 * h);
    const thr = clamp(inp.throttle, 0, 1);
    this.engine += (thr - this.engine) * (1 - Math.exp(-h / 0.6));

    // thrust
    const Vt = Math.max(V, 14);
    const thrust = Math.min(sp.tStatic, sp.eta * sp.power * this.engine / Vt) * (this.engine > 0.02 ? 1 : 0);

    // aerodynamic forces (body frame)
    const { cl, cd } = this._coef(alpha, this.flaps);
    this.alpha = alpha; this.beta = beta;
    this.stallWarn = alpha > 0.85 * sp.aStall && V > 8; this.stalled = alpha > sp.aStall && V > 8;
    let Fb = [0, 0, 0];
    if (V > 0.5) {
      const vh = mul(va, 1 / V);
      let l = sub([0, 1, 0], mul(vh, vh[1]));
      const ll = len(l); l = ll > 0.05 ? mul(l, 1 / ll) : [0, 1, 0];
      Fb = add(mul(l, qbar * sp.S * cl), mul(vh, -qbar * sp.S * cd));
      Fb[0] += qbar * sp.S * sp.cyB * beta;
    }
    Fb[2] -= thrust;
    const qctl = 0.5 * rho * (V * V + sp.propSlip * this.engine);
    const Vh = Math.max(V, 12);
    const w = this.w;
    const Mx = qbar * sp.S * sp.c * (sp.cm0 + sp.cmA * alpha + sp.cmQ * (w[0] * sp.c / (2 * Vh))) + qctl * sp.S * sp.c * sp.cmDe * this.surf.e * sp.deMax;
    const Mz = qbar * sp.S * sp.b * (sp.rollP * (w[2] * sp.b / (2 * Vh)) + sp.rollB * beta) - qctl * sp.S * sp.b * sp.rollDa * this.surf.a * sp.daMax;
    const My = qbar * sp.S * sp.b * (sp.yawB * beta + sp.yawR * (w[1] * sp.b / (2 * Vh))) - qctl * sp.S * sp.b * sp.yawDr * this.surf.r * sp.drMax + qctl * sp.S * sp.b * sp.yawDa * this.surf.a * sp.daMax;
    let M = [Mx, My, Mz];

    // world force so far
    let Fw = qrot(this.q, Fb);
    const FnoG = Fb.slice();                 // aero + thrust in body axes
    let Gb = [0, 0, 0];                       // ground forces in body axes
    Fw = add(Fw, [0, -sp.mass * G, 0]);

    // landing gear
    const wW = qrot(this.q, this.w);
    let contacts = 0, torW = [0, 0, 0], worstSink = 0, tailNow = false;
    const speedGround = Math.hypot(this.vel[0], this.vel[2]);
    this.steer = (inp.yaw || 0) * 0.5 * (1 - sstep(8, 40, speedGround));
    for (const g of sp.gear) {
      const rW = qrot(this.q, g.p), wp = add(this.pos, rW);
      const gh = env.height(wp[0], wp[2]), d = gh - wp[1];
      if (d <= 0) continue;
      const vw = add(this.vel, cross(wW, rW));
      let N = sp.gearK * d - sp.gearC * vw[1]; if (N < 0) N = 0;
      contacts++; if (-vw[1] > worstSink) worstSink = -vw[1];
      if (g.steer) tailNow = true;
      let fw = [f[0], 0, f[2]]; const fl = Math.hypot(fw[0], fw[2]) || 1; fw = [fw[0] / fl, 0, fw[2] / fl];
      if (g.steer) { const c = Math.cos(this.steer), s = Math.sin(this.steer); fw = [fw[0] * c + fw[2] * s, 0, -fw[0] * s + fw[2] * c]; }
      const lw = [-fw[2], 0, fw[0]];
      const vF = dot(vw, fw), vL = dot(vw, lw);
      const paved = env.paved ? env.paved(wp[0], wp[2]) : true;
      const roll = paved ? 0.018 : 0.06;
      const mu = paved ? 0.85 : 0.6;
      // a tail-dragger only brakes while its tail wheel is down, otherwise braking would tip it onto its nose
      const brake = g.brake ? (inp.brake || 0) * (sp.brakeMu || 0.5) * ((sp.tailDragger && !this.tailDown) ? 0.12 : 1) : 0;
      const Fl = -mu * N * Math.tanh(vL / 0.25);
      const Ff = -(roll + brake) * N * Math.tanh(vF / 0.4);
      const F = [fw[0] * Ff + lw[0] * Fl, N, fw[2] * Ff + lw[2] * Fl];
      Fw = add(Fw, F); torW = add(torW, cross(rW, F));
    }
    this.tailDown = tailNow;
    if (contacts > 0) { this.groundT = 0; this.airborneT = 0; this.contacts = contacts; }
    else { this.contacts = 0; this.airborneT += h; this.groundT += h; }
    if (contacts > 0 && !this.touchdownDone && this.airborneT === 0) {
      // first wheel contact after flight
      const sink = worstSink;
      this.touchdownDone = true;
      this.events.push({ type: 'touchdown', sink, ias: this.ias || 0 });
      if (sink > 7.5) return this._crash('Landed too hard: the gear collapsed');
    }
    if (contacts === 0) this.touchdownDone = false;
    Gb = qrot(qi, sub(Fw, [0, -sp.mass * G, 0]));  // all non-gravity forces in body axes
    this.specForce = mul(Gb, 1 / sp.mass);

    // body strikes and buildings
    for (const hp of sp.hit) {
      const wp = add(this.pos, qrot(this.q, hp));
      if (env.height(wp[0], wp[2]) - wp[1] > 0.12) return this._crash(contacts ? 'The aircraft hit the ground' : 'The aircraft hit the ground');
      if (env.colliders) for (const b of env.colliders) {
        const dx = wp[0] - b.cx, dz = wp[2] - b.cz, uu = dx * b.c + dz * b.s, vv = -dx * b.s + dz * b.c;
        if (Math.abs(uu) < b.hu && Math.abs(vv) < b.hv && wp[1] < b.top) return this._crash('The aircraft hit a building');
      }
    }

    // integrate
    M = add(M, qrot(qi, torW));
    const I = sp.I;
    const Iw = [I[0] * w[0], I[1] * w[1], I[2] * w[2]];
    const gyro = cross(w, Iw);
    this.w = [w[0] + (M[0] - gyro[0]) / I[0] * h, w[1] + (M[1] - gyro[1]) / I[1] * h, w[2] + (M[2] - gyro[2]) / I[2] * h];
    this.vel = add(this.vel, mul(Fw, h / sp.mass));
    this.pos = add(this.pos, mul(this.vel, h));
    const wl = len(this.w);
    if (wl > 1e-6) this.q = qnorm(qmul(this.q, qaxis(mul(this.w, 1 / wl), wl * h)));
    if (!isFinite(this.pos[0] + this.pos[1] + this.pos[2])) this._crash('Simulation error');
  }
  _crash(reason) {
    this.crashed = true; this.crashReason = reason;
    this.events.push({ type: 'crash', reason });
  }
  _instruments() {
    const sp = this.spec, v = sub(this.vel, this.wind), tas = len(v);
    const rho = 1.225 * Math.exp(-Math.max(this.pos[1], 0) / 8500);
    const e = this.euler();
    const gnd = this.env.height(this.pos[0], this.pos[2]);
    const wheelY = -Math.min(...sp.gear.map((g) => g.p[1]));
    this.ias = tas * Math.sqrt(rho / 1.225);
    this.i = {
      ias: this.ias, tas, gs: Math.hypot(this.vel[0], this.vel[2]), altMSL: this.pos[1], altAGL: Math.max(0, this.pos[1] - gnd - wheelY),
      vs: this.vel[1], heading: e.heading, pitch: e.pitch, roll: e.roll, aoa: (this.alpha || 0) / D2R, slip: (this.beta || 0) / D2R,
      g: this.specForce[1] / G, onGround: this.contacts > 0, stallWarn: this.stallWarn, stall: this.stalled,
      throttle: this.engine, rpm: sp.rpmIdle + (sp.rpmMax - sp.rpmIdle) * this.engine, flaps: this.flaps,
    };
  }
}

root.SMFlight = { FlightModel, SPECS, qrot, qfromHPR, D2R, G };
if (typeof module !== 'undefined' && module.exports) module.exports = root.SMFlight;
})(typeof window !== 'undefined' ? window : globalThis);
