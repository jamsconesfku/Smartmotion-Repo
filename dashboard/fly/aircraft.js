/* SmartMotion Flight: aircraft models, cockpit and instrument panel (three.js, no outside art).
   Body axes: x right, y up, z back (nose is -z), origin at the centre of gravity. */
(function (root) {
'use strict';
const THREE = root.THREE;
const WHITE = [0.95, 0.96, 0.98], NAVY = [0.012, 0.012, 0.18], ORANGE = [1, 0.3, 0], GREY = [0.74, 0.76, 0.86];
const lam = (color, o) => new THREE.MeshLambertMaterial(Object.assign({ color }, o || {}));

function paint(geom, fn) {
  const n = geom.attributes.normal, p = geom.attributes.position, c = new Float32Array(n.count * 3);
  for (let i = 0; i < n.count; i++) {
    const col = fn(n.getX(i), n.getY(i), n.getZ(i), p.getX(i), p.getY(i), p.getZ(i));
    c[i * 3] = col[0]; c[i * 3 + 1] = col[1]; c[i * 3 + 2] = col[2];
  }
  geom.setAttribute('color', new THREE.BufferAttribute(c, 3));
  return geom;
}
function fuselage(profile, segs) {
  const pts = profile.map((p) => new THREE.Vector2(p[1], p[0]));
  const g = new THREE.LatheGeometry(pts, segs || 16);
  g.rotateX(Math.PI / 2);
  return g;
}
const radiusAt = (profile, z) => {
  for (let i = 0; i < profile.length - 1; i++) {
    const a = profile[i], b = profile[i + 1];
    if (z >= a[0] && z <= b[0]) return a[1] + (b[1] - a[1]) * (z - a[0]) / (b[0] - a[0]);
  }
  return 0.1;
};
// one wing (right side): x spanwise, forward distances for leading and trailing edge at root and tip
function wingGeom(span, rootLE, rootChord, tipLE, tipChord, thick) {
  const sh = new THREE.Shape();
  sh.moveTo(0, rootLE); sh.lineTo(span, tipLE); sh.lineTo(span, tipLE - tipChord); sh.lineTo(0, rootLE - rootChord); sh.closePath();
  const g = new THREE.ExtrudeGeometry(sh, { depth: thick, bevelEnabled: false });
  g.translate(0, 0, -thick / 2);
  g.rotateX(-Math.PI / 2);                      // shape y (forward) -> -z, thickness -> y
  g.computeVertexNormals();
  return g;
}
function finGeom(height, rootLE, rootTE, tipLE, tipTE, thick) {       // forward distances from the tail reference point
  const sh = new THREE.Shape();
  sh.moveTo(rootLE, 0); sh.lineTo(tipLE, height); sh.lineTo(tipTE, height); sh.lineTo(rootTE, 0); sh.closePath();
  const g = new THREE.ExtrudeGeometry(sh, { depth: thick, bevelEnabled: false });
  g.translate(0, 0, -thick / 2);
  g.rotateY(Math.PI / 2);                        // shape x (forward) -> -z, thickness -> x
  g.computeVertexNormals();
  return g;
}
function box(w, h, d, mat) { return new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); }

let decalTex = null;
function logoMaterial(img) {
  if (!decalTex && img) { decalTex = new THREE.Texture(img); decalTex.needsUpdate = true; decalTex.anisotropy = 4; }
  return new THREE.MeshBasicMaterial({ map: decalTex, transparent: true, side: THREE.DoubleSide, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
}

function build(key, assets) {
  const root = new THREE.Group();
  const fus = new THREE.Group();                 // fuselage parts (hidden in the cockpit view)
  const outer = new THREE.Group();               // wings, tail and gear (always visible)
  root.add(fus, outer);
  const vcMat = lam(0xffffff, { vertexColors: true, side: THREE.DoubleSide });
  const glass = lam(0x9cc6ea, { transparent: true, opacity: 0.42, side: THREE.DoubleSide });
  const navyM = lam(0x02022f), orangeM = lam(0xff4c00), whiteM = lam(0xf2f4fa), darkM = lam(0x23252e), greyM = lam(0x6b6f80);
  const sp = root.userData;
  let profile, wingY, wing, tailZ, eye;
  const surf = { aileronL: null, aileronR: null, elevator: null, rudder: null };

  if (key === 'trainer') {
    profile = [[-2.4, 0], [-2.35, 0.18], [-2.1, 0.36], [-1.6, 0.5], [-0.9, 0.62], [0.2, 0.66], [1.4, 0.55], [2.8, 0.4], [4.4, 0.26], [5.9, 0.12]];
    const g = paint(fuselage(profile, 18), (nx, ny) => ny > 0.3 ? WHITE : ny < -0.5 ? NAVY : Math.abs(ny) < 0.18 ? ORANGE : (ny < 0 ? NAVY : WHITE));
    fus.add(new THREE.Mesh(g, vcMat));
    const canopy = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 10), glass); canopy.scale.set(0.52, 0.4, 1.3); canopy.position.set(0, 0.6, -0.25); fus.add(canopy);
    const cowl = new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.46, 0.5, 16), orangeM); cowl.rotation.x = Math.PI / 2; cowl.position.set(0, 0, -2.2); fus.add(cowl);
    // wing: high wing
    const wg = paint(wingGeom(5.5, 1.0, 1.7, 0.85, 1.2, 0.14), (nx, ny) => ny > 0.5 ? WHITE : GREY);
    for (const s of [1, -1]) { const m = new THREE.Mesh(wg, vcMat); m.position.y = 0.97; if (s < 0) m.scale.x = -1; outer.add(m); }
    for (const s of [1, -1]) {                                         // struts
      const st = box(0.07, 1.25, 0.07, whiteM); st.position.set(s * 1.9, 0.35, 0.05); st.rotation.z = s * -0.62; outer.add(st);
      const tip = box(0.6, 0.16, 0.5, orangeM); tip.position.set(s * 5.55, 0.97, 0.45); outer.add(tip);
    }
    for (const s of [1, -1]) {                                         // ailerons
      const g2 = new THREE.Group(); g2.position.set(s * 4.1, 0.97, 0.05); const a = box(2.1, 0.05, 0.36, navyM); a.position.z = 0.18; g2.add(a); outer.add(g2);
      surf[s > 0 ? 'aileronR' : 'aileronL'] = g2;
    }
    // tail
    const sg = paint(wingGeom(1.8, -4.7, 0.75, -4.95, 0.55, 0.07), (nx, ny) => WHITE);
    for (const s of [1, -1]) { const m = new THREE.Mesh(sg, vcMat); m.position.set(0, 0.2, 0); if (s < 0) m.scale.x = -1; outer.add(m); }
    const el = new THREE.Group(); el.position.set(0, 0.2, 5.45); const eb = box(3.5, 0.05, 0.5, navyM); eb.position.z = 0.25; el.add(eb); outer.add(el); surf.elevator = el;
    const fg = finGeom(1.35, -4.6, -5.45, -5.0, -5.45, 0.08); const fin = new THREE.Mesh(paint(fg, (nx, ny, nz, x, y) => y > 1.1 ? ORANGE : WHITE), vcMat); fin.position.set(0, 0.2, 0); outer.add(fin);
    const rd = new THREE.Group(); rd.position.set(0, 0.2, 5.45); const rb = box(0.05, 1.3, 0.45, navyM); rb.position.set(0, 0.65, 0.22); rd.add(rb); outer.add(rd); surf.rudder = rd;
    // gear
    sp.wheels = [];
    for (const [gx, gy, gz, r] of [[-1.15, -1.05, 0.25, 0.28], [1.15, -1.05, 0.25, 0.28], [0, -1.05, -1.5, 0.24]]) {
      const w = new THREE.Mesh(new THREE.CylinderGeometry(r, r, 0.16, 16), darkM); w.rotation.z = Math.PI / 2; w.position.set(gx, gy + r + 0.08, gz); outer.add(w); sp.wheels.push(w);
      const leg = box(0.08, 0.7, 0.08, greyM); leg.position.set(gx * 0.85, gy + r + 0.4, gz); outer.add(leg);
      if (gx) { const pant = new THREE.Mesh(new THREE.SphereGeometry(1, 10, 8), whiteM); pant.scale.set(0.12, 0.34, 0.55); pant.position.set(gx + Math.sign(gx) * 0.12, gy + r + 0.08, gz); outer.add(pant); }
    }
    // propeller
    const prop = new THREE.Group(); prop.position.set(0, 0, -2.5);
    prop.add(new THREE.Mesh(new THREE.ConeGeometry(0.2, 0.45, 12).rotateX(-Math.PI / 2).translate(0, 0, -0.18), orangeM));
    sp.blades = [];
    for (let i = 0; i < 2; i++) { const b = box(0.13, 1.95, 0.03, darkM); b.rotation.z = i * Math.PI / 2 + Math.PI / 2 * 0; prop.add(b); sp.blades.push(b); }
    const disc = new THREE.Mesh(new THREE.CircleGeometry(0.98, 28), new THREE.MeshBasicMaterial({ color: 0x20222c, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false })); prop.add(disc); sp.disc = disc;
    outer.add(prop); sp.prop = prop;
    eye = [-0.32, 0.5, -0.15];
    // livery decals
    if (assets.logo) {
      const lm = logoMaterial(assets.logo);
      for (const s of [1, -1]) {
        const z = 2.3, y = 0.2, r = radiusAt(profile, z), x = Math.sqrt(Math.max(r * r - y * y, 0.01)) + 0.015;
        const d = new THREE.Mesh(new THREE.PlaneGeometry(1.7, 0.68), lm); d.position.set(s * x, y, z); d.rotation.y = s * Math.PI / 2; fus.add(d);
      }
    }
  } else {
    profile = [[-3.0, 0], [-2.95, 0.22], [-2.5, 0.42], [-1.6, 0.55], [-0.4, 0.62], [0.8, 0.55], [2.2, 0.42], [3.8, 0.28], [5.5, 0.14], [5.95, 0.08]];
    const g = paint(fuselage(profile, 18), (nx, ny) => ny > 0.35 ? NAVY : ny < -0.3 ? WHITE : (Math.abs(ny) < 0.12 ? ORANGE : (ny > 0 ? NAVY : WHITE)));
    fus.add(new THREE.Mesh(g, vcMat));
    const canopy = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 10), glass); canopy.scale.set(0.4, 0.34, 1.05); canopy.position.set(0, 0.55, 0.1); fus.add(canopy);
    const wg = paint(wingGeom(5.6, 1.4, 3.0, 0.2, 1.0, 0.2), (nx, ny) => ny > 0.5 ? NAVY : WHITE);
    for (const s of [1, -1]) { const m = new THREE.Mesh(wg, vcMat); m.position.y = -0.4; if (s < 0) m.scale.x = -1; outer.add(m); }
    for (const s of [1, -1]) {
      const tip = box(0.5, 0.18, 0.9, orangeM); tip.position.set(s * 5.5, -0.4, 0.2); outer.add(tip);
      const g2 = new THREE.Group(); g2.position.set(s * 4.2, -0.4, 0.5); const a = box(2.0, 0.05, 0.5, orangeM); a.position.z = 0.25; g2.add(a); outer.add(g2);
      surf[s > 0 ? 'aileronR' : 'aileronL'] = g2;
    }
    const sg = paint(wingGeom(2.0, -4.6, 0.8, -5.0, 0.55, 0.07), () => NAVY);
    for (const s of [1, -1]) { const m = new THREE.Mesh(sg, vcMat); m.position.set(0, 0.2, 0); if (s < 0) m.scale.x = -1; outer.add(m); }
    const el = new THREE.Group(); el.position.set(0, 0.2, 5.4); const eb = box(4.0, 0.05, 0.55, orangeM); eb.position.z = 0.28; el.add(eb); outer.add(el); surf.elevator = el;
    const fg = finGeom(1.6, -4.4, -5.4, -5.1, -5.4, 0.08); const fin2 = new THREE.Mesh(paint(fg, () => WHITE), vcMat); fin2.position.set(0, 0.2, 0); outer.add(fin2);
    const rd = new THREE.Group(); rd.position.set(0, 0.2, 5.4); const rb = box(0.05, 1.5, 0.55, navyM); rb.position.set(0, 0.75, 0.28); rd.add(rb); outer.add(rd); surf.rudder = rd;
    sp.wheels = [];
    for (const [gx, gy, gz, r] of [[-1.9, -1.45, -0.2, 0.36], [1.9, -1.45, -0.2, 0.36], [0, -1.0, 5.1, 0.14]]) {
      const w = new THREE.Mesh(new THREE.CylinderGeometry(r, r, r * 0.55, 14), darkM); w.rotation.z = Math.PI / 2; w.position.set(gx, gy + r + 0.1, gz); outer.add(w); sp.wheels.push(w);
      if (gz < 1) { const leg = box(0.1, 0.85, 0.12, greyM); leg.position.set(gx * 0.94, gy + r + 0.55, gz); outer.add(leg); }
    }
    const prop = new THREE.Group(); prop.position.set(0, 0, -3.2);
    prop.add(new THREE.Mesh(new THREE.ConeGeometry(0.3, 0.75, 14).rotateX(-Math.PI / 2).translate(0, 0, -0.3), orangeM));
    sp.blades = [];
    for (let i = 0; i < 3; i++) { const b = box(0.2, 1.75, 0.035, darkM); b.geometry.translate(0, 0.875, 0); b.rotation.z = i * Math.PI * 2 / 3; prop.add(b); sp.blades.push(b); }
    const disc = new THREE.Mesh(new THREE.CircleGeometry(1.75, 30), new THREE.MeshBasicMaterial({ color: 0x20222c, transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false })); prop.add(disc); sp.disc = disc;
    outer.add(prop); sp.prop = prop;
    eye = [0, 0.6, -0.9];
    if (assets.logo) {
      const lm = logoMaterial(assets.logo);
      for (const s of [1, -1]) { const d = new THREE.Mesh(new THREE.PlaneGeometry(1.0, 0.4), lm); d.position.set(s * 0.06, 0.95, 5.0); d.rotation.y = s * Math.PI / 2; outer.add(d); }
    }
  }
  sp.surf = surf; sp.fus = fus; sp.outer = outer; sp.eye = eye;
  // pilot (visible from outside)
  const pilot = new THREE.Mesh(new THREE.SphereGeometry(0.13, 10, 8), lam(0xd9a98c)); pilot.position.set(eye[0], eye[1] + 0.12, eye[2] + 0.1);
  const helmet = new THREE.Mesh(new THREE.SphereGeometry(0.145, 10, 8, 0, Math.PI * 2, 0, Math.PI * 0.62), orangeM); helmet.position.copy(pilot.position); helmet.position.y += 0.015;
  fus.add(pilot, helmet); sp.pilot = [pilot, helmet];
  root.traverse((o) => { if (o.isMesh) o.matrixAutoUpdate = true; });

  // control surfaces, propeller and wheels follow the flight model
  sp.update = function (surfDef, engine, dt, ias) {
    const k = 0.5;
    surf.aileronR.rotation.x = -k * surfDef.a; surf.aileronL.rotation.x = k * surfDef.a;
    surf.elevator.rotation.x = -k * surfDef.e; surf.rudder.rotation.y = k * surfDef.r;
    const spin = (8 + engine * 95) * dt;
    sp.prop.rotation.z += spin;
    const blur = Math.min(1, Math.max(0, (engine - 0.2) / 0.5));
    sp.disc.material.opacity = 0.17 * blur;
    sp.blades.forEach((b) => { b.visible = blur < 0.8; });
    for (const w of sp.wheels) w.rotation.x += ias * dt * 3;
  };
  sp.setView = function (cockpit) {
    fus.visible = !cockpit; sp.pilot.forEach((p) => { p.visible = !cockpit; }); sp.disc.visible = !cockpit;
  };
  return root;
}

/* ---------- cockpit ---------- */
function buildCockpit(key) {
  const g = new THREE.Group();
  const dark = lam(0x14151c), mid = lam(0x2a2c38), orangeM = lam(0xff4c00);
  const fighter = key === 'fighter';
  const eye = fighter ? [0, 0.6, -0.9] : [-0.32, 0.5, -0.15];
  const pw = fighter ? 0.7 : 1.1, ph = fighter ? 0.44 : 0.42;
  const canvas = document.createElement('canvas'); canvas.width = 1024; canvas.height = Math.round(1024 * ph / pw);
  const tex = new THREE.CanvasTexture(canvas); tex.anisotropy = 4;
  const panel = new THREE.Mesh(new THREE.PlaneGeometry(pw, ph), new THREE.MeshBasicMaterial({ map: tex }));
  panel.position.set(eye[0] + (fighter ? 0 : 0.32), eye[1] - 0.36, eye[2] - 0.74); panel.rotation.x = -0.4;
  g.add(panel);
  const cx = panel.position.x;
  const shield = new THREE.Mesh(new THREE.BoxGeometry(pw + 0.3, 0.06, 0.42), dark); shield.position.set(cx, eye[1] - 0.1, eye[2] - 0.8); shield.rotation.x = -0.1; g.add(shield);
  const cowl = new THREE.Mesh(new THREE.BoxGeometry(pw + 0.5, 0.35, 0.8), dark); cowl.position.set(cx, eye[1] - 0.62, eye[2] - 1.05); g.add(cowl);
  // yoke / stick
  const yoke = new THREE.Group(); yoke.position.set(eye[0], eye[1] - 0.46, eye[2] - 0.42);
  if (fighter) { const st = new THREE.Mesh(new THREE.CylinderGeometry(0.014, 0.018, 0.34, 8), mid); st.position.y = 0.15; yoke.add(st); const grip = new THREE.Mesh(new THREE.SphereGeometry(0.04, 8, 6), orangeM); grip.position.y = 0.33; yoke.add(grip); }
  else { const col = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.02, 0.3, 8), mid); col.rotation.x = Math.PI / 2; col.position.z = 0.12; yoke.add(col);
    const rim = new THREE.Mesh(new THREE.TorusGeometry(0.15, 0.015, 6, 20, Math.PI * 1.2), dark); rim.rotation.z = Math.PI * 0.9; rim.position.set(0, 0.07, 0.3); yoke.add(rim); }
  g.add(yoke);
  if (fighter) {                                                       // gun sight ring
    const sight = new THREE.Mesh(new THREE.TorusGeometry(0.05, 0.004, 6, 24), orangeM); sight.position.set(0, eye[1] + 0.12, eye[2] - 0.7); g.add(sight);
    const glass = new THREE.Mesh(new THREE.PlaneGeometry(0.14, 0.12), new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.1 })); glass.position.set(0, eye[1] + 0.12, eye[2] - 0.7); g.add(glass);
  }
  g.userData = { canvas, ctx: canvas.getContext('2d'), tex, yoke, eye, fighter };
  return g;
}

/* ---------- instrument panel drawing ---------- */
function drawPanel(cock, d) {
  const { ctx, canvas, tex } = cock.userData, W = canvas.width, H = canvas.height;
  ctx.fillStyle = '#16171f'; ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = '#ff4c00'; ctx.fillRect(0, 0, W, 8);
  const cols = 3, cw = W / cols, ch = H / 2, r = Math.min(cw, ch) * 0.47;
  const dial = (i, j, draw) => { const cx = cw * (i + 0.5), cy = ch * (j + 0.5); ctx.save(); ctx.translate(cx, cy);
    ctx.fillStyle = '#05060b'; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill(); ctx.strokeStyle = '#4a4d5e'; ctx.lineWidth = 5; ctx.stroke();
    ctx.save(); ctx.beginPath(); ctx.arc(0, 0, r - 4, 0, 7); ctx.clip(); draw(); ctx.restore(); ctx.restore(); };
  const ang = (v, a0, a1, v0, v1) => (a0 + (a1 - a0) * (Math.min(Math.max(v, v0), v1) - v0) / (v1 - v0)) * Math.PI / 180;
  const needle = (a, len, w, col) => { ctx.save(); ctx.rotate(a); ctx.strokeStyle = col; ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(-len * 0.15, 0); ctx.lineTo(len, 0); ctx.stroke(); ctx.restore(); };
  const ticks = (n, a0, a1, len, w, lab, every, font) => { for (let k = 0; k <= n; k++) { const a = (a0 + (a1 - a0) * k / n) * Math.PI / 180; ctx.strokeStyle = '#d5d8e6'; ctx.lineWidth = w; ctx.beginPath(); ctx.moveTo(Math.cos(a) * (r - 8), Math.sin(a) * (r - 8)); ctx.lineTo(Math.cos(a) * (r - 8 - len), Math.sin(a) * (r - 8 - len)); ctx.stroke();
    if (lab && k % every === 0) { ctx.fillStyle = '#e9ebf5'; ctx.font = (font || 21) + 'px sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(lab(k), Math.cos(a) * (r - 38), Math.sin(a) * (r - 38)); } } };
  const label = (t) => { ctx.fillStyle = '#9ea2b8'; ctx.font = '22px sans-serif'; ctx.textAlign = 'center'; ctx.fillText(t, 0, r * 0.62); };
  // airspeed
  dial(0, 0, () => { const vmax = d.vmax || 200; ticks(vmax / 10, 135, 405, 12, 3, (k) => k * 10, vmax / 50, 21); label('KNOTS'); needle(ang(d.ias, 135, 405, 0, vmax), r - 14, 6, '#ff4c00'); });
  // attitude
  dial(1, 0, () => { ctx.save(); ctx.rotate(-d.roll * Math.PI / 180); const py = d.pitch * (r / 28);
    ctx.fillStyle = '#3d7fc4'; ctx.fillRect(-r, -r * 2 + py, r * 2, r * 2); ctx.fillStyle = '#7a5a32'; ctx.fillRect(-r, py, r * 2, r * 2);
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(-r, py); ctx.lineTo(r, py); ctx.stroke();
    ctx.lineWidth = 3; for (const p of [-20, -10, 10, 20]) { const y = py - p * (r / 28), w = Math.abs(p) === 10 ? r * 0.3 : r * 0.45; ctx.beginPath(); ctx.moveTo(-w, y); ctx.lineTo(w, y); ctx.stroke(); }
    ctx.restore(); ctx.strokeStyle = '#ffb000'; ctx.lineWidth = 7; ctx.beginPath(); ctx.moveTo(-r * 0.55, 0); ctx.lineTo(-r * 0.15, 0); ctx.lineTo(0, r * 0.12); ctx.lineTo(r * 0.15, 0); ctx.lineTo(r * 0.55, 0); ctx.stroke(); });
  // altimeter
  dial(2, 0, () => { ticks(10, -90, 270, 12, 3, (k) => k % 10, 1); const ft = d.alt; needle(ang(ft % 1000, -90, 270, 0, 1000), r - 14, 6, '#ffffff'); needle(ang(ft % 10000, -90, 270, 0, 10000), r * 0.6, 8, '#ff4c00'); label('FEET'); });
  // heading
  dial(0, 1, () => { ctx.save(); ctx.rotate(-d.heading * Math.PI / 180); ctx.fillStyle = '#e9ebf5'; ctx.font = '30px sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    for (let k = 0; k < 36; k++) { const a = k * 10 * Math.PI / 180 - Math.PI / 2; ctx.strokeStyle = '#d5d8e6'; ctx.lineWidth = k % 3 ? 2 : 4; ctx.beginPath(); ctx.moveTo(Math.cos(a) * (r - 8), Math.sin(a) * (r - 8)); ctx.lineTo(Math.cos(a) * (r - (k % 3 ? 18 : 28)), Math.sin(a) * (r - (k % 3 ? 18 : 28))); ctx.stroke();
      if (k % 3 === 0) { const t = k === 0 ? 'N' : k === 9 ? 'E' : k === 18 ? 'S' : k === 27 ? 'W' : String(k); ctx.save(); ctx.translate(Math.cos(a) * (r - 54), Math.sin(a) * (r - 54)); ctx.rotate(a + Math.PI / 2); ctx.fillText(t, 0, 0); ctx.restore(); } }
    ctx.restore(); ctx.fillStyle = '#ff4c00'; ctx.beginPath(); ctx.moveTo(0, -r + 6); ctx.lineTo(-10, -r + 28); ctx.lineTo(10, -r + 28); ctx.fill(); ctx.strokeStyle = '#fff'; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(0, -18); ctx.lineTo(0, 18); ctx.moveTo(-16, 4); ctx.lineTo(16, 4); ctx.stroke(); });
  // vertical speed
  dial(1, 1, () => { ticks(12, 90, 450, 12, 3, null, 1); ctx.fillStyle = '#e9ebf5'; ctx.font = '24px sans-serif'; ctx.textAlign = 'center'; ctx.fillText('UP', 0, -r * 0.45); ctx.fillText('DN', 0, r * 0.55);
    needle(ang(Math.max(-2000, Math.min(2000, d.vs)), 180 - 160, 180 + 160 + 20, -2000, 2000) + 0, r - 14, 6, '#ff4c00'); label('V/S x100'); });
  // engine and controls
  dial(2, 1, () => { ticks(8, 135, 405, 12, 3, (k) => k, 1, 24); needle(ang(d.rpm, 135, 405, 0, d.rpmMax || 3000), r - 14, 6, '#ffffff');
    ctx.fillStyle = '#e9ebf5'; ctx.font = '26px sans-serif'; ctx.textAlign = 'center'; ctx.fillText('THR ' + Math.round(d.throttle * 100) + '%', 0, r * 0.35); ctx.fillText('FLAPS ' + Math.round(d.flaps * 100) + '%', 0, r * 0.62);
    if (d.stall) { ctx.fillStyle = '#ff3b30'; ctx.font = 'bold 34px sans-serif'; ctx.fillText('STALL', 0, -r * 0.35); } label(''); });
  tex.needsUpdate = true;
}

root.SMAircraft = { build, buildCockpit, drawPanel };
})(window);
