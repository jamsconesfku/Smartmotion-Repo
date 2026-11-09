/* SmartMotion Flight: the game (controls, cameras, HUD, gate run, sound, telemetry, VR). */
(function () {
'use strict';
const THREE = window.THREE, F = window.SMFlight, T = window.SMTerrain, A = window.SMAircraft, W = window.SMWorld;
const $ = (id) => document.getElementById(id);
const KT = 1.94384, FT = 3.28084, FPM = 196.85, D2R = Math.PI / 180;
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const store = { get(k, d) { try { const v = localStorage.getItem('sm2:flight:' + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } }, set(k, v) { try { localStorage.setItem('sm2:flight:' + k, JSON.stringify(v)); } catch (e) { /* ignore */ } } };
const qs = new URLSearchParams(location.search);
const S = Object.assign({ aircraft: 'trainer', start: 'runway', mode: 'free', assist: 'true', tod: 'day', wind: 'calm', invert: false, sound: true, quality: '', tel: false, telUrl: 'ws://localhost:8765' }, store.get('settings', {}));
for (const k of ['aircraft', 'start', 'mode', 'assist', 'tod', 'wind']) if (qs.get(k)) S[k] = qs.get(k);
S.assist = String(S.assist);
const saveS = () => store.set('settings', S);
const isTouch = matchMedia('(pointer: coarse)').matches || qs.get('touch') === '1';
if (isTouch) document.body.classList.add('touch');
const quality = qs.get('q') || S.quality || (isTouch ? 'medium' : 'medium');

let renderer, scene, camera, rig, world, fm, plane, cockpit;
let state = 'loading', paused = false, camMode = 'chase', last = 0, hudT = 0, panelT = 0;
const inp = { pitch: 0, roll: 0, yaw: 0, throttle: 0, brake: 0, flaps: 0, trim: 0 };
let flapsIdx = 0, throttle = 0, trim = 0;
const gate = { next: 0, t: 0, done: false, active: false };
const look = { yaw: 0, pitch: 0 }, orbit = { yaw: 0.6, pitch: 0.25, dist: 16 };
const camS = { q: new THREE.Quaternion(), pos: new THREE.Vector3(), init: false };
const tmp = { v: new THREE.Vector3(), q: new THREE.Quaternion(), e: new THREE.Euler(0, 0, 0, 'YXZ') };
let landing = null;

/* ================= helpers ================= */
function toast(t, ms) { const el = $('toast'); el.textContent = t; el.classList.add('on'); clearTimeout(toast.t); toast.t = setTimeout(() => el.classList.remove('on'), ms || 2200); }
function setMsg(t, warn) { const el = $('msg'); if (!t) { el.hidden = true; return; } el.hidden = false; el.textContent = t; el.className = warn ? 'warn' : ''; }
function fatal(msg) { $('loadmsg').textContent = msg; $('loadmsg').style.color = '#ff8a52'; $('loadbar').style.width = '100%'; }
const fmtTime = (s) => Math.floor(s / 60) + ':' + (s % 60).toFixed(1).padStart(4, '0');

/* ================= input ================= */
const keys = new Set(), kb = { pitch: 0, roll: 0, yaw: 0 }, pad = { pitch: 0, roll: 0, yaw: 0, brake: 0, tr: 0 }, touch = { pitch: 0, roll: 0, yaw: 0, brake: 0 }, vrIn = { pitch: 0, roll: 0, yaw: 0, brake: 0, tr: 0 };
let touchThrottle = null; const edge = {};
const pressed = (id, v) => { const was = edge[id]; edge[id] = v; return v && !was; };
const dz = (v) => Math.abs(v) < 0.12 ? 0 : (v - Math.sign(v) * 0.12) / 0.88;
function approach(cur, tgt, rate, dt) { return cur + clamp(tgt - cur, -rate * dt, rate * dt); }
function cycleFlaps() { flapsIdx = (flapsIdx + 1) % 3; toast('Flaps ' + ['up', 'half', 'full'][flapsIdx]); }
function cycleCamera() {
  if (state !== 'fly' && state !== 'ended') return;
  camMode = camMode === 'chase' ? 'cockpit' : camMode === 'cockpit' ? 'orbit' : 'chase'; applyView(); camS.init = false; toast({ chase: 'Chase view', cockpit: 'Cockpit view', orbit: 'Orbit view (drag to turn)' }[camMode]);
}
function applyView() { const cp = camMode === 'cockpit' || (renderer && renderer.xr.isPresenting); if (plane) plane.userData.setView(cp); if (cockpit) cockpit.visible = cp; $('adi').style.visibility = cp ? 'hidden' : ''; }
window.addEventListener('keydown', (e) => {
  if (e.target && e.target.tagName === 'INPUT') return;
  keys.add(e.code);
  if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'PageUp', 'PageDown'].includes(e.code)) e.preventDefault();
  if (e.repeat) return;
  if (Snd.ctx === null) Snd.init();
  if (e.code === 'KeyF') cycleFlaps(); else if (e.code === 'KeyV' || e.code === 'KeyC') cycleCamera();
  else if (e.code === 'KeyP' || e.code === 'Escape') { if (!$('help').hidden) backToMenuOrPause('help'); else if (!$('settings').hidden) backToMenuOrPause('settings'); else togglePause(); }
  else if (e.code === 'KeyR' && state !== 'menu') startFlight(); else if (e.code === 'KeyT') toggleTel(); else if (e.code === 'KeyM') { S.sound = !S.sound; saveS(); toast(S.sound ? 'Sound on' : 'Sound off'); }
  else if (e.code === 'Home') throttle = 1; else if (e.code === 'End') throttle = 0;
  else if (/^Digit[0-9]$/.test(e.code)) throttle = e.code === 'Digit0' ? 1 : (+e.code[5]) / 10;
  else if (e.code === 'BracketLeft') trim = clamp(trim - 0.03, -0.5, 0.5); else if (e.code === 'BracketRight') trim = clamp(trim + 0.03, -0.5, 0.5);
});
window.addEventListener('keyup', (e) => keys.delete(e.code));
window.addEventListener('pointerdown', () => { if (Snd.ctx === null) Snd.init(); else Snd.gesture = true; });
window.addEventListener('blur', () => { keys.clear(); if (state === 'fly' && !renderer.xr.isPresenting) pause(true); });
function readInput(dt) {
  const k = (c) => keys.has(c) ? 1 : 0;
  const tp = (k('ArrowUp') || k('KeyW')) * -1 + (k('ArrowDown') || k('KeyS')), tr = (k('ArrowRight') || k('KeyD')) - (k('ArrowLeft') || k('KeyA')), ty = k('KeyE') - k('KeyQ');
  kb.pitch = approach(kb.pitch, tp, tp ? 2.6 : 4, dt); kb.roll = approach(kb.roll, tr, tr ? 3 : 4.5, dt); kb.yaw = approach(kb.yaw, ty, ty ? 4 : 6, dt);
  // gamepad
  pad.pitch = pad.roll = pad.yaw = pad.brake = pad.tr = 0;
  const gps = navigator.getGamepads ? navigator.getGamepads() : [];
  for (const gp of gps) {
    if (!gp || !gp.connected) continue;
    pad.roll = dz(gp.axes[2] || 0); pad.pitch = dz(gp.axes[3] || 0); pad.yaw = dz(gp.axes[0] || 0); pad.tr = -dz(gp.axes[1] || 0);
    const b = (i) => gp.buttons[i] ? gp.buttons[i].value : 0;
    pad.brake = b(6); if (b(4)) pad.yaw = -1; if (b(5)) pad.yaw = 1; pad.tr += b(12) - b(13);
    if (pressed('pA', b(0) > 0.5)) cycleFlaps(); if (pressed('pB', b(1) > 0.5)) cycleCamera(); if (pressed('pS', b(9) > 0.5)) togglePause();
    break;
  }
  if (renderer.xr.isPresenting) readVR(dt); else { vrIn.pitch = vrIn.roll = vrIn.yaw = vrIn.brake = vrIn.tr = 0; }
  const inv = S.invert ? -1 : 1;
  inp.pitch = clamp(kb.pitch + (pad.pitch + touch.pitch + vrIn.pitch) * inv, -1, 1);
  inp.roll = clamp(kb.roll + pad.roll + touch.roll + vrIn.roll, -1, 1);
  inp.yaw = clamp(kb.yaw + pad.yaw + touch.yaw + vrIn.yaw, -1, 1);
  const trAx = pad.tr + vrIn.tr + (k('ShiftLeft') || k('ShiftRight') || k('PageUp') || k('KeyX')) - (k('ControlLeft') || k('ControlRight') || k('PageDown') || k('KeyZ'));
  if (touchThrottle !== null) throttle = touchThrottle; else throttle = clamp(throttle + trAx * 0.35 * dt, 0, 1);
  inp.throttle = throttle; inp.brake = Math.max(k('Space') || k('KeyB'), pad.brake, touch.brake, vrIn.brake); inp.flaps = flapsIdx / 2; inp.trim = trim;
}

/* ================= sound ================= */
const Snd = {
  ctx: null,
  gesture: false,
  init() {
    this.gesture = true;
    try { this.ctx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { this.ctx = false; return; }
    const c = this.ctx, mk = (type, f) => { const o = c.createOscillator(); o.type = type; o.frequency.value = f; o.start(); return o; };
    this.master = c.createGain(); this.master.gain.value = 0; this.master.connect(c.destination);
    this.lp = c.createBiquadFilter(); this.lp.type = 'lowpass'; this.lp.frequency.value = 900; this.lp.connect(this.master);
    this.o1 = mk('sawtooth', 40); this.o2 = mk('square', 80); this.g1 = c.createGain(); this.g2 = c.createGain(); this.g1.gain.value = 0.5; this.g2.gain.value = 0.18;
    this.o1.connect(this.g1).connect(this.lp); this.o2.connect(this.g2).connect(this.lp);
    const buf = c.createBuffer(1, c.sampleRate * 2, c.sampleRate), d = buf.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    this.nz = c.createBufferSource(); this.nz.buffer = buf; this.nz.loop = true; this.bp = c.createBiquadFilter(); this.bp.type = 'bandpass'; this.bp.frequency.value = 700; this.wg = c.createGain(); this.wg.gain.value = 0;
    this.nz.connect(this.bp).connect(this.wg).connect(c.destination); this.nz.start();
    this.horn = mk('square', 1250); this.hg = c.createGain(); this.hg.gain.value = 0; this.horn.connect(this.hg).connect(c.destination);
  },
  update(i, thr, on) {
    if (!this.ctx) return; const c = this.ctx, t = c.currentTime;
    if (c.state === 'suspended' && this.gesture) c.resume();
    const vol = on && S.sound ? 1 : 0;
    this.master.gain.setTargetAtTime(0.16 * vol * (0.35 + 0.65 * thr), t, 0.1);
    const f = 22 + thr * 46; this.o1.frequency.setTargetAtTime(f, t, 0.08); this.o2.frequency.setTargetAtTime(f * 2.02, t, 0.08); this.lp.frequency.setTargetAtTime(500 + thr * 900, t, 0.1);
    this.wg.gain.setTargetAtTime(vol * Math.pow(clamp(i.ias / 90, 0, 1.3), 2) * 0.22, t, 0.15); this.bp.frequency.setTargetAtTime(400 + i.ias * 9, t, 0.15);
    this.hg.gain.setTargetAtTime(vol * (i.stallWarn && !i.onGround && Math.floor(t * 6) % 2 ? 0.05 : 0), t, 0.02);
  },
};

/* ================= telemetry (for the motion rig) ================= */
const Tel = {
  ws: null, status: 'off', nextSend: 0, retry: null, frame: null,
  make(t) {
    const i = fm.i, sp = fm.spec, g = F.G, lat0 = 52.0908, lon0 = 0.1317;
    const lat = lat0 - fm.pos[2] / 111320, lon = lon0 + fm.pos[0] / (111320 * Math.cos(lat0 * D2R));
    const vb = F.qrot([-fm.q[0], -fm.q[1], -fm.q[2], fm.q[3]], fm.vel);
    return {
      v: 1, t: +t.toFixed(3), aircraft: sp.key, paused, crashed: fm.crashed,
      pos: { x: +fm.pos[0].toFixed(2), y: +fm.pos[1].toFixed(2), z: +fm.pos[2].toFixed(2) },
      geo: { lat: +lat.toFixed(6), lon: +lon.toFixed(6), alt_m: +fm.pos[1].toFixed(1) },
      att: { pitch_deg: +i.pitch.toFixed(2), roll_deg: +i.roll.toFixed(2), heading_deg: +i.heading.toFixed(2) },
      rate: { roll_dps: +(-fm.w[2] / D2R).toFixed(2), pitch_dps: +(fm.w[0] / D2R).toFixed(2), yaw_dps: +(-fm.w[1] / D2R).toFixed(2) },
      vel_body: { surge: +(-vb[2]).toFixed(2), sway: +vb[0].toFixed(2), heave: +vb[1].toFixed(2) },
      g_felt: { surge: +(-fm.specForce[2] / g).toFixed(3), sway: +(fm.specForce[0] / g).toFixed(3), heave: +(fm.specForce[1] / g).toFixed(3) },
      ias_kt: +(i.ias * KT).toFixed(1), tas_kt: +(i.tas * KT).toFixed(1), gs_kt: +(i.gs * KT).toFixed(1), alt_ft: +(i.altMSL * FT).toFixed(0), agl_ft: +(i.altAGL * FT).toFixed(0), vs_fpm: +(i.vs * FPM).toFixed(0),
      aoa_deg: +i.aoa.toFixed(2), slip_deg: +i.slip.toFixed(2), throttle: +i.throttle.toFixed(3), rpm: Math.round(i.rpm), flaps: +i.flaps.toFixed(2), on_ground: i.onGround, stall: i.stall,
      controls: { pitch: +inp.pitch.toFixed(3), roll: +inp.roll.toFixed(3), yaw: +inp.yaw.toFixed(3) },
    };
  },
  push(t, now) {
    this.frame = this.make(t); window.SmartMotionTelemetry = this.frame;
    if (this.ws && this.ws.readyState === 1 && now >= this.nextSend) { this.nextSend = now + 1 / 60 - 0.002; if (this.ws.bufferedAmount < 65536) this.ws.send(JSON.stringify(this.frame)); }
  },
  connect(url) {
    this.disconnect(); if (!url) return; this.status = 'connecting'; this.url = url;
    try { this.ws = new WebSocket(url); } catch (e) { this.status = 'error: ' + e.message; return; }
    this.ws.onopen = () => { this.status = 'connected'; }; this.ws.onerror = () => { this.status = 'cannot reach ' + url; };
    this.ws.onclose = () => { if (this.status === 'connected') this.status = 'closed'; if (S.tel) this.retry = setTimeout(() => this.connect(url), 3000); };
  },
  disconnect() { clearTimeout(this.retry); if (this.ws) { this.ws.onclose = null; try { this.ws.close(); } catch (e) { /* ignore */ } } this.ws = null; this.status = 'off'; },
};
function toggleTel() { const el = $('tel'); el.hidden = !el.hidden; }
function telPanel() {
  const el = $('tel'); if (el.hidden || !Tel.frame) return; const f = Tel.frame, st = Tel.status;
  el.innerHTML = `<div class="st"><span class="dot ${st === 'connected' ? 'ok' : (S.tel ? 'bad' : '')}"></span>${S.tel ? 'Rig link: ' + st : 'Rig link off (Settings)'}</div>` +
    `<b>pitch</b> ${f.att.pitch_deg.toFixed(1)}°  <b>roll</b> ${f.att.roll_deg.toFixed(1)}°<br><b>yaw rate</b> ${f.rate.yaw_dps.toFixed(1)}°/s<br>` +
    `<b>surge</b> ${f.g_felt.surge.toFixed(2)}g <b>sway</b> ${f.g_felt.sway.toFixed(2)}g<br><b>heave</b> ${f.g_felt.heave.toFixed(2)}g <b>aoa</b> ${f.aoa_deg.toFixed(1)}°<br><b>IAS</b> ${f.ias_kt} kt <b>VS</b> ${f.vs_fpm}`;
}

/* ================= flight set-up ================= */
function startPose() {
  const sp = F.SPECS[S.aircraft], rw = T.RW;
  if (S.mode === 'gates') {
    const [x, z] = T.fromRunway(-500, 0), g = T.GATES[0], hd = (Math.atan2(g[0] - x, -(g[1] - z)) / D2R + 360) % 360;
    return { x, z, heading: hd, airborne: true, agl: 140, speed: sp.cruise, throttle: sp.cruiseThrottle };
  }
  if (S.start === 'air') { const [x, z] = T.fromRunway(-1300, 0); return { x, z, heading: 62, airborne: true, agl: 380, speed: sp.cruise, throttle: sp.cruiseThrottle }; }
  const [x, z] = T.fromRunway(-rw.len / 2 + 70, 0); return { x, z, heading: 62 };
}
function mountPlane() {
  if (plane) scene.remove(plane);
  plane = A.build(S.aircraft, world.assets); cockpit = A.buildCockpit(S.aircraft); plane.add(cockpit);
  scene.add(plane); applyView();
}
function placePlane(dt) {
  plane.position.set(fm.pos[0], fm.pos[1], fm.pos[2]); plane.quaternion.set(fm.q[0], fm.q[1], fm.q[2], fm.q[3]);
  plane.userData.update(fm.surf, fm.engine, dt, fm.i ? fm.i.ias : 0);
}
function showcase() {
  state = 'menu'; paused = false; world.env.wind = [0, 0, 0];
  fm = new F.FlightModel(S.aircraft, world.env); const [x, z] = T.fromRunway(-T.RW.len / 2 + 70, 0); fm.reset({ x, z, heading: 62 });
  mountPlane(); camMode = 'chase'; applyView(); placePlane(0); world.setGates(false, 0);
}
function startFlight() {
  Snd.ctx === null && Snd.init();
  world.env.wind = S.wind === 'breezy' ? [-3.5, 0, 2] : [0, 0, 0];
  world.setTimeOfDay(S.tod);
  fm = new F.FlightModel(S.aircraft, world.env); fm.assist = S.assist === 'true'; fm.reset(startPose());
  mountPlane(); if (camMode !== 'cockpit') camMode = 'chase'; applyView(); camS.init = false;
  throttle = startPose().throttle || 0; flapsIdx = 0; trim = 0; kb.pitch = kb.roll = kb.yaw = 0; landing = null;
  gate.next = 0; gate.t = 0; gate.done = false; gate.active = S.mode === 'gates'; world.setGates(gate.active, 0);
  $('gateBox').hidden = !gate.active; $('tAssist').textContent = fm.assist ? 'Easy' : 'Pro'; $('tAssist').classList.toggle('on', fm.assist);
  state = 'fly'; paused = false; closeSheets(); $('menu').hidden = true; $('end').hidden = true; $('hud').hidden = false; $('touch').hidden = !isTouch; setMsg('');
  last = performance.now() / 1000;
  if (fm.i.onGround) toast('Full power, then pull back at about ' + Math.round(fm.spec.vr * 1.12 * KT) + ' knots', 4500); else if (gate.active) toast('Fly through the orange gates as fast as you can', 4000);
}
function toMenu() { closeSheets(); $('hud').hidden = true; $('touch').hidden = true; $('end').hidden = true; $('menu').hidden = false; showcase(); }
function endFlight(title, label, text, big) {
  state = 'ended'; $('endLab').textContent = label; $('endH').textContent = title; $('endP').textContent = text || ''; const b = $('endBig'); b.hidden = !big; b.textContent = big || '';
  setTimeout(() => { if (state === 'ended') $('end').hidden = false; }, 900);
}

/* ================= pause and sheets ================= */
const SHEETS = ['pause', 'help', 'settings'];
const anySheet = () => SHEETS.some((id) => !$(id).hidden);
function closeSheets() { SHEETS.forEach((id) => { $(id).hidden = true; }); }
function pause(on) { if (state !== 'fly') return; paused = on; $('pause').hidden = !on; }
function togglePause() { if (state === 'fly') pause(!paused); }
function openSheet(id, from) { $(id).hidden = false; if (from) $(from).hidden = true; }
function backToMenuOrPause(id) { $(id).hidden = true; if (state === 'fly' && paused) $('pause').hidden = false; }

/* ================= cameras ================= */
function updateCamera(dt) {
  const P = plane.position, Q = plane.quaternion, sp = fm.spec;
  if (renderer.xr.isPresenting) return updateVRRig();
  camera.near = camMode === 'cockpit' ? 0.1 : 0.6; camera.far = 40000;
  let focus = 0;
  if (state === 'menu') {
    orbit.yaw += dt * 0.12; const d = sp.key === 'fighter' ? 19 : 16, h = 4.5;
    camera.position.set(P.x + Math.sin(orbit.yaw) * d, P.y + h, P.z + Math.cos(orbit.yaw) * d); camera.up.set(0, 1, 0); camera.lookAt(P.x, P.y + 1.2, P.z);
    if (innerWidth > 900) { camera.setViewOffset(innerWidth, innerHeight, -innerWidth * 0.16, 0, innerWidth, innerHeight); } else camera.clearViewOffset();
    camera.updateProjectionMatrix(); return;
  }
  if (camera.view && camera.view.enabled) { camera.clearViewOffset(); }
  if (camMode === 'cockpit') {
    const e = tmp.v.set(...sp.eye).applyQuaternion(Q); camera.position.copy(P).add(e);
    tmp.e.set(look.pitch, look.yaw, 0); tmp.q.setFromEuler(tmp.e); camera.quaternion.copy(Q).multiply(tmp.q); camera.up.set(0, 1, 0);
  } else if (camMode === 'orbit') {
    const d = orbit.dist * (sp.key === 'fighter' ? 1.2 : 1);
    camera.position.set(P.x + Math.sin(orbit.yaw) * Math.cos(orbit.pitch) * d, P.y + Math.sin(orbit.pitch) * d, P.z + Math.cos(orbit.yaw) * Math.cos(orbit.pitch) * d);
    camera.up.set(0, 1, 0); camera.lookAt(P);
  } else {
    if (!camS.init) { camS.q.copy(Q); camS.init = true; camS.pos.copy(P); }
    camS.q.slerp(Q, 1 - Math.exp(-dt * 3.5));
    const off = tmp.v.set(0, sp.key === 'fighter' ? 3.2 : 2.7, sp.key === 'fighter' ? 14 : 11.5).applyQuaternion(camS.q);
    camera.position.copy(P).add(off);
    const gy = world.heightAt(camera.position.x, camera.position.z) + 2; if (camera.position.y < gy) camera.position.y = gy;
    const up = tmp.q.copy(camS.q); camera.up.set(0, 1, 0).lerp(tmp.v.set(0, 1, 0).applyQuaternion(up), 0.3).normalize();
    camera.lookAt(tmp.v.set(0, 0.9, -7).applyQuaternion(Q).add(P));
  }
  // keep the eye above the ground
  const gy = world.heightAt(camera.position.x, camera.position.z) + 0.6; if (camera.position.y < gy) camera.position.y = gy;
  focus = 0;
}
// drag to look around (cockpit) or orbit
let dragging = null;
function bindDrag() {
  const c = $('gl');
  c.addEventListener('pointerdown', (e) => { if (state === 'loading') return; dragging = { x: e.clientX, y: e.clientY }; Snd.ctx === null && Snd.init(); try { c.setPointerCapture(e.pointerId); } catch (er) { /* ignore */ } });
  c.addEventListener('pointermove', (e) => {
    if (!dragging) return; const dx = e.clientX - dragging.x, dy = e.clientY - dragging.y; dragging = { x: e.clientX, y: e.clientY };
    if (camMode === 'cockpit') { look.yaw = clamp(look.yaw - dx * 0.006, -2.2, 2.2); look.pitch = clamp(look.pitch - dy * 0.006, -1, 1); }
    else if (camMode === 'orbit' || state === 'menu') { orbit.yaw -= dx * 0.006; orbit.pitch = clamp(orbit.pitch + dy * 0.005, -0.2, 1.3); }
  });
  const up = () => { dragging = null; };
  c.addEventListener('pointerup', up); c.addEventListener('pointercancel', up);
  c.addEventListener('dblclick', () => { look.yaw = look.pitch = 0; });
  c.addEventListener('wheel', (e) => { orbit.dist = clamp(orbit.dist * (1 + e.deltaY * 0.001), 8, 60); e.preventDefault(); }, { passive: false });
}

/* ================= touch controls ================= */
function bindTouch() {
  const stick = $('stick'), knob = $('stickKnob');
  const setStick = (e) => { const r = stick.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2; let x = (e.clientX - cx) / (r.width / 2), y = (e.clientY - cy) / (r.height / 2); const l = Math.hypot(x, y); if (l > 1) { x /= l; y /= l; } touch.roll = x; touch.pitch = y; knob.style.transform = `translate(${x * 44}px,${y * 44}px)`; };
  stick.addEventListener('pointerdown', (e) => { stick.setPointerCapture(e.pointerId); setStick(e); e.stopPropagation(); });
  stick.addEventListener('pointermove', (e) => { if (stick.hasPointerCapture(e.pointerId)) setStick(e); });
  const rel = (e) => { touch.roll = 0; touch.pitch = 0; knob.style.transform = ''; };
  stick.addEventListener('pointerup', rel); stick.addEventListener('pointercancel', rel);
  const ts = $('thrS'), fill = $('thrFill');
  const setThr = (e) => { const r = ts.getBoundingClientRect(); touchThrottle = clamp(1 - (e.clientY - r.top) / r.height, 0, 1); };
  ts.addEventListener('pointerdown', (e) => { ts.setPointerCapture(e.pointerId); setThr(e); }); ts.addEventListener('pointermove', (e) => { if (ts.hasPointerCapture(e.pointerId)) setThr(e); });
  const hold = (id, key, val) => { const b = $(id); const on = (e) => { b.setPointerCapture(e.pointerId); touch[key] = val; b.classList.add('on'); }, off = () => { touch[key] = 0; b.classList.remove('on'); }; b.addEventListener('pointerdown', on); b.addEventListener('pointerup', off); b.addEventListener('pointercancel', off); };
  hold('tbL', 'yaw', -1); hold('tbR', 'yaw', 1); hold('tbBrake', 'brake', 1);
  $('tbFlaps').addEventListener('click', cycleFlaps);
  window.addEventListener('keydown', () => { touchThrottle = null; });
  setInterval(() => { fill.style.height = Math.round(throttle * 182) + 'px'; }, 100);
}

/* ================= HUD ================= */
let adiCtx = null;
function drawADI(pitch, roll) {
  const c = $('adi'); if (!adiCtx) adiCtx = c.getContext('2d'); const g = adiCtx, W = c.width, R = W / 2 - 4;
  g.clearRect(0, 0, W, W); g.save(); g.translate(W / 2, W / 2); g.beginPath(); g.arc(0, 0, R, 0, 7); g.clip();
  g.rotate(-roll * D2R); const py = pitch * (R / 30);
  g.fillStyle = '#3a78c2'; g.fillRect(-R * 2, -R * 2 + py, R * 4, R * 2); g.fillStyle = '#7a5a32'; g.fillRect(-R * 2, py, R * 4, R * 2);
  g.strokeStyle = '#fff'; g.lineWidth = 3; g.beginPath(); g.moveTo(-R, py); g.lineTo(R, py); g.stroke();
  for (const p of [-20, -10, 10, 20]) { const y = py - p * (R / 30), w = Math.abs(p) === 10 ? R * 0.3 : R * 0.5; g.beginPath(); g.moveTo(-w, y); g.lineTo(w, y); g.stroke(); }
  g.restore(); g.strokeStyle = '#ff4c00'; g.lineWidth = 6; g.beginPath(); g.moveTo(W / 2 - R * 0.6, W / 2); g.lineTo(W / 2 - R * 0.2, W / 2); g.lineTo(W / 2, W / 2 + R * 0.14); g.lineTo(W / 2 + R * 0.2, W / 2); g.lineTo(W / 2 + R * 0.6, W / 2); g.stroke();
}
function updateHud() {
  const i = fm.i;
  $('spd').textContent = Math.round(i.ias * KT); $('hdgN').textContent = String(Math.round(i.heading) % 360).padStart(3, '0') + '°';
  const agl = i.altAGL * FT; $('alt').textContent = Math.round(i.altMSL * FT); $('vs').textContent = (Math.round(i.vs * FPM / 10) * 10);
  $('thr').style.width = Math.round(throttle * 100) + '%';
  $('tFlaps').textContent = 'Flaps ' + Math.round(i.flaps * 100) + '%'; $('tFlaps').classList.toggle('on', i.flaps > 0.05); $('tBrake').classList.toggle('on', inp.brake > 0.1);
  drawADI(i.pitch, i.roll);
  if (gate.active) {
    const g = world.gates[Math.min(gate.next, world.gates.length - 1)];
    $('gateN').textContent = gate.done ? 'Finished' : 'Gate ' + (gate.next + 1) + '/' + world.gates.length; $('gateT').textContent = fmtTime(gate.t) + (gate.done ? '' : '  ·  ' + Math.round(Math.hypot(g.x - fm.pos[0], g.z - fm.pos[2])) + ' m');
    const brg = Math.atan2(g.x - fm.pos[0], -(g.z - fm.pos[2])) / D2R, rel = brg - i.heading; $('arrow').style.transform = `rotate(${rel}deg)`;
  }
  // messages
  let m = '', warn = false;
  if (fm.crashed) m = ''; else if (i.stallWarn && !i.onGround) { m = 'STALL'; warn = true; }
  else if (!i.onGround && i.altAGL < 70 && i.vs < -7) { m = 'PULL UP'; warn = true; }
  else if (i.onGround && i.ias > fm.spec.vr * 1.08 && i.ias < fm.spec.vr * 1.5 && fm.engine > 0.8) m = 'ROTATE';
  setMsg(m, warn);
}

/* ================= main loop ================= */
function tick(ts) {
  const now = ts / 1000; let dt = Math.min(0.05, Math.max(0, now - (last || now))); last = now;
  if (state === 'loading') return;
  if (state === 'fly' || state === 'ended') {
    if (!paused) {
      if (state === 'fly') readInput(dt); else { inp.throttle = 0; inp.brake = 1; }
      const px = fm.pos[0], py = fm.pos[1], pz = fm.pos[2];
      fm.step(dt, inp);
      for (const ev of fm.consumeEvents()) handleEvent(ev);
      if (gate.active && !gate.done && state === 'fly') { gate.t += dt; checkGate(px, py, pz); }
      Tel.push(now, now);
    }
  }
  placePlane(paused ? 0 : dt);
  updateCamera(dt);
  world.update(dt, plane.position);
  if (state === 'fly' && now - hudT > 0.08) { hudT = now; updateHud(); }
  if (state === 'fly' && now - panelT > 0.07 && (camMode === 'cockpit' || renderer.xr.isPresenting)) { panelT = now; const i = fm.i; A.drawPanel(cockpit, { ias: i.ias * KT, vmax: fm.spec.key === 'fighter' ? 400 : 200, alt: i.altMSL * FT, vs: i.vs * FPM, heading: i.heading, pitch: i.pitch, roll: i.roll, throttle, rpm: i.rpm, rpmMax: fm.spec.rpmMax, flaps: i.flaps, stall: i.stall });
    const y = cockpit.userData.yoke; y.rotation.z = -inp.roll * 0.5; y.rotation.x = inp.pitch * 0.18; }
  if (now - panelT > 0.5) { telPanel(); }
  Snd.update(fm.i, fm.engine, state === 'fly' && !paused);
  renderer.render(scene, camera);
}
function handleEvent(ev) {
  if (ev.type === 'touchdown') {
    const fpm = Math.round(ev.sink * FPM); const r = fpm < 120 ? 'Smooth' : fpm < 300 ? 'Good' : fpm < 500 ? 'Firm' : 'Hard';
    toast(`Touchdown: ${fpm} ft/min (${r})`, 3500); landing = { fpm, r };
  } else if (ev.type === 'crash') {
    endFlight('Crashed', 'Flight over', ev.reason + '. Take another go: gentle with the controls, and keep your speed up on approach.');
  }
}
function checkGate(px, py, pz) {
  const g = world.gates[gate.next], nx = g.nx, nz = g.nz;
  const d0 = (px - g.x) * nx + (pz - g.z) * nz, d1 = (fm.pos[0] - g.x) * nx + (fm.pos[2] - g.z) * nz;
  if (d0 < 0 && d1 >= 0) {
    const t = d0 / (d0 - d1), x = px + (fm.pos[0] - px) * t, y = py + (fm.pos[1] - py) * t, z = pz + (fm.pos[2] - pz) * t;
    if (Math.hypot(x - g.x, y - g.y, z - g.z) < g.r * 0.96) {
      gate.next++; Snd.ctx && 0;
      if (gate.next >= world.gates.length) { gate.done = true; const best = store.get('best:' + S.aircraft, 0); const nb = !best || gate.t < best; if (nb) store.set('best:' + S.aircraft, gate.t); world.setGates(true, gate.next);
        endFlight('Course complete', 'Gate run', nb ? 'New best time for this aircraft!' : 'Best: ' + fmtTime(best), fmtTime(gate.t)); }
      else { world.setGates(true, gate.next); toast('Gate ' + gate.next + '  ' + fmtTime(gate.t), 1500); }
    } else toast('Missed the gate: turn back and fly through the ring', 2500);
  }
}

/* ================= VR (WebXR) ================= */
const vr = { supported: false, headRef: null, frames: 0 };
async function checkVR() {
  const note = $('vrNote');
  if (!navigator.xr) { note.textContent = 'VR: open this page in the Meta Quest Browser, or in Chrome/Edge on a PC with a headset connected (Quest Link).'; return; }
  try { vr.supported = await navigator.xr.isSessionSupported('immersive-vr'); } catch (e) { vr.supported = false; }
  $('vrBtn').hidden = !vr.supported; $('hudVr').hidden = !vr.supported;
  note.textContent = vr.supported ? 'VR is ready. Tap Enter VR, then put the headset on.' : 'VR isn\'t available in this browser. Use the Meta Quest Browser, or Chrome/Edge on a PC with the headset connected. iPhone browsers don\'t support WebXR.';
}
async function enterVR() {
  if (!vr.supported) return;
  if (state === 'menu') startFlight();
  try {
    const session = await navigator.xr.requestSession('immersive-vr', { optionalFeatures: ['local-floor', 'bounded-floor'] });
    session.addEventListener('end', onVrEnd);
    await renderer.xr.setSession(session);
    vr.headRef = null; vr.frames = 0; camMode = 'cockpit'; applyView(); camera.near = 0.1; toast('VR: sit upright and press B to recentre', 4000);
  } catch (e) { toast('Could not start VR: ' + (e && e.message ? e.message : e), 5000); }
}
function onVrEnd() { rig.position.set(0, 0, 0); rig.quaternion.identity(); camS.init = false; camMode = 'chase'; applyView(); }
function headPos() {
  const cams = renderer.xr.getCamera ? renderer.xr.getCamera(camera).cameras : null, v = new THREE.Vector3();
  if (cams && cams.length) { for (const c of cams) v.add(new THREE.Vector3().setFromMatrixPosition(c.matrix)); v.multiplyScalar(1 / cams.length); }
  return v;
}
function updateVRRig() {
  if (!vr.headRef && ++vr.frames > 8) vr.headRef = headPos();
  const ref = vr.headRef || headPos(), off = new THREE.Vector3(...fm.spec.eye).sub(ref).applyQuaternion(plane.quaternion);
  rig.quaternion.copy(plane.quaternion); rig.position.copy(plane.position).add(off);
}
function readVR(dt) {
  vrIn.pitch = vrIn.roll = vrIn.yaw = vrIn.brake = vrIn.tr = 0;
  const session = renderer.xr.getSession(); if (!session) return;
  for (const src of session.inputSources) {
    const gp = src.gamepad; if (!gp) continue; const ax = gp.axes, b = (i) => gp.buttons[i] ? gp.buttons[i].value : 0;
    const sx = dz(ax.length >= 4 ? ax[2] : ax[0] || 0), sy = dz(ax.length >= 4 ? ax[3] : ax[1] || 0);
    if (src.handedness === 'right') { vrIn.roll = sx; vrIn.pitch = sy; if (pressed('vA', b(4) > 0.5)) cycleFlaps(); if (pressed('vB', b(5) > 0.5)) { vr.headRef = headPos(); toast('View recentred'); } }
    else { vrIn.yaw = sx; vrIn.tr = -sy; vrIn.brake = b(0); if (pressed('vX', b(4) > 0.5)) togglePause(); if (pressed('vY', b(5) > 0.5)) toast('Hold X to pause'); }
  }
}

/* ================= menu wiring ================= */
function paintMenu() {
  document.querySelectorAll('#planes .plane').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.v === S.aircraft)));
  document.querySelectorAll('#menu .seg').forEach((seg) => { const k = seg.dataset.key; if (k) seg.querySelectorAll('button').forEach((b) => b.setAttribute('aria-pressed', String(String(S[k]) === b.dataset.v))); });
  $('swSound').setAttribute('aria-pressed', String(S.sound)); $('swInvert').setAttribute('aria-pressed', String(S.invert)); $('swTel').setAttribute('aria-pressed', String(S.tel));
  document.querySelectorAll('#quality button').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.v === quality))); $('telUrl').value = S.telUrl;
}
function wire() {
  $('planes').addEventListener('click', (e) => { const b = e.target.closest('.plane'); if (!b) return; S.aircraft = b.dataset.v; saveS(); paintMenu(); showcase(); });
  document.querySelectorAll('#menu .seg').forEach((seg) => seg.addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b || !seg.dataset.key) return; S[seg.dataset.key] = b.dataset.v; saveS(); paintMenu(); if (seg.dataset.key === 'tod') world.setTimeOfDay(S.tod); }));
  $('fly').addEventListener('click', startFlight); $('vrBtn').addEventListener('click', enterVR); $('hudVr').addEventListener('click', enterVR);
  $('helpBtn').addEventListener('click', () => openSheet('help')); $('setBtn').addEventListener('click', () => openSheet('settings'));
  $('helpBtn2').addEventListener('click', () => openSheet('help', 'pause')); $('setBtn2').addEventListener('click', () => openSheet('settings', 'pause'));
  $('helpClose').addEventListener('click', () => backToMenuOrPause('help')); $('setClose').addEventListener('click', () => backToMenuOrPause('settings'));
  $('pauseBtn').addEventListener('click', togglePause); $('camBtn').addEventListener('click', cycleCamera); $('resume').addEventListener('click', () => pause(false));
  $('restart').addEventListener('click', startFlight); $('toMenu').addEventListener('click', toMenu); $('again').addEventListener('click', startFlight); $('endMenu').addEventListener('click', toMenu);
  $('swSound').addEventListener('click', () => { S.sound = !S.sound; saveS(); paintMenu(); }); $('swInvert').addEventListener('click', () => { S.invert = !S.invert; saveS(); paintMenu(); });
  $('swTel').addEventListener('click', () => { S.tel = !S.tel; saveS(); paintMenu(); S.tel ? Tel.connect(S.telUrl) : Tel.disconnect(); });
  $('telUrl').addEventListener('change', (e) => { S.telUrl = e.target.value.trim(); saveS(); if (S.tel) Tel.connect(S.telUrl); });
  document.querySelectorAll('#quality button').forEach((b) => b.addEventListener('click', () => { S.quality = b.dataset.v; saveS(); location.reload(); }));
  setInterval(() => { $('telSt').textContent = S.tel ? 'Status: ' + Tel.status : 'Off'; }, 500);
  window.addEventListener('resize', resize);
  bindDrag(); bindTouch();
}
function resize() {
  if (!renderer) return; const w = innerWidth, h = innerHeight;
  if (!renderer.xr.isPresenting) renderer.setSize(w, h, false);
  camera.aspect = w / h; camera.updateProjectionMatrix();
}

/* ================= start-up ================= */
async function init() {
  try {
    renderer = new THREE.WebGLRenderer({ canvas: $('gl'), antialias: !isTouch && quality !== 'low', powerPreference: 'high-performance' });
  } catch (e) { return fatal('This browser can\'t show 3D graphics. Try Chrome, Edge, Safari or the Meta Quest Browser.'); }
  renderer.setPixelRatio(quality === 'low' ? 1 : Math.min(window.devicePixelRatio || 1, isTouch ? 1.75 : 2));
  renderer.xr.enabled = true; try { renderer.xr.setReferenceSpaceType('local-floor'); renderer.xr.setFoveation(1); } catch (e) { /* older runtimes */ }
  scene = new THREE.Scene(); camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.6, 40000); rig = new THREE.Group(); rig.add(camera); scene.add(rig);
  resize();
  world = new W.World(scene, renderer, { quality, tod: S.tod });
  try {
    await world.init((p, msg) => { $('loadbar').style.width = Math.round(p * 100) + '%'; $('loadmsg').textContent = msg + '…'; });
  } catch (e) { console.error(e); return fatal('Something went wrong while building the world: ' + e.message); }
  wire(); paintMenu(); showcase(); checkVR();
  if (S.tel) Tel.connect(S.telUrl); if (qs.get('telemetry')) { S.tel = true; S.telUrl = qs.get('telemetry'); Tel.connect(S.telUrl); paintMenu(); }
  $('loading').hidden = true; renderer.setAnimationLoop(tick);
  if (qs.get('auto') === '1') startFlight(); else $('menu').hidden = false;
  window.SMFlightDebug = { get fm() { return fm; }, get world() { return world; }, get renderer() { return renderer; }, get state() { return state; }, S, inp, startFlight, toMenu, Tel };
}
init();
})();
