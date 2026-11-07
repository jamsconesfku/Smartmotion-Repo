/* Sky Barrage: a SmartMotion arcade game.
   Opens full-screen over the SmartMotion Dashboard (window.SkyBarrage.open()).
   Everything is drawn with canvas and inline SVG; no outside libraries. */
(function () {
'use strict';

/* ================= Constants ================= */
const COLS = 7, LAST_ROW = 10, DECK = 11, LAUNCH_Y = 11.55, FIELD_H = 12.35;
const R = 0.11, SPEED = 15, GAP = 0.06, CR = 0.2, STEP = 0.07;
const SAVE_KEY = 'sm2:skybarrage';
const PAL = {
  navy: '#02022f', deep: '#05063a', sky: '#11166a', haze: '#2a3192',
  orange: '#ff4c00', ember: '#ff8a52', cream: '#fff3ea', white: '#ffffff',
  steel: '#9aa0cc', steelD: '#4a4f86', gold: '#ffc23d', green: '#4cc283', red: '#ff5a4f'
};
/* Enemy toughness tiers: tints of the dashboard palette (brand blue, violet, orange). */
const TIER = ['#4f63e8', '#9a7be0', '#ff7a33'];
const FONT = '"Barlow Semi Condensed", "Arial Narrow", system-ui, sans-serif';

/* ================= Levels =================
   Each level: name, jets (squadron size), turns, rows (top to bottom, 7 cells each).
   Cell codes: . empty | b blimp | c cargo crate | s storm cloud | a armoured airship
   x bomber | T radar tower | D hangar door (closed) | d hangar door (open) | R +1 ring
   Z boss zeppelin (3 wide: follow it with two dots). Number = hit points. */
const LEVELS = [
  { name: 'First Sortie', jets: 10, turns: 12, rows: [
    'b3 b3 b3 b3 b3 b3 b3',
    '. b4 b4 b4 b4 b4 .',
    '. . b5 b5 b5 . .'] },
  { name: 'Checkerboard', jets: 10, turns: 12, rows: [
    'b6 . b6 . b6 . b6',
    'b5 b5 . b5 . b5 b5',
    '. b4 b4 b4 b4 b4 .',
    'b3 . b3 . b3 . b3'] },
  { name: 'Cargo Run', jets: 12, turns: 13, rows: [
    'c8 b5 b5 c8 b5 b5 c8',
    'b6 . b6 . b6 . b6',
    '. c6 . c6 . c6 .',
    'b4 b4 b4 . b4 b4 b4'] },
  { name: 'Radar Pillars', jets: 14, turns: 13, rows: [
    'b8 T b8 b8 b8 T b8',
    'b8 T b9 c10 b9 T b8',
    'b7 T b7 . b7 T b7',
    'b6 . b6 . b6 . b6',
    'b5 b5 . . . b5 b5'] },
  { name: 'Storm Front', jets: 16, turns: 13, rows: [
    's6 b9 s6 b9 s6 b9 s6',
    'b10 s5 b10 s5 b10 s5 b10',
    '. b8 . c12 . b8 .',
    's4 . s4 . s4 . s4'] },
  { name: 'Ring Road', jets: 14, turns: 14, rows: [
    'b12 b12 b12 b12 b12 b12 b12',
    'b10 . R . R . b10',
    'b10 b10 . c14 . b10 b10',
    '. . R . R . .',
    'b8 b8 b8 . b8 b8 b8'] },
  { name: 'Hangar Doors', jets: 18, turns: 14, rows: [
    'b14 b14 D b14 D b14 b14',
    'T b12 b12 b12 b12 b12 T',
    'b12 . d . d . b12',
    'T s8 . . . s8 T',
    'b10 b10 b10 R b10 b10 b10'] },
  { name: 'Bomber Alley', jets: 20, turns: 14, rows: [
    'x12 . x12 . x12 . x12',
    'b14 b14 b14 b14 b14 b14 b14',
    '. c16 . s10 . c16 .',
    'b12 . b12 . b12 . b12',
    'R . . . . . R'] },
  { name: 'The Channel', jets: 22, turns: 15, rows: [
    'b16 T b18 b18 b18 T b16',
    'b16 T s12 c20 s12 T b16',
    'b15 T b15 . b15 T b15',
    'b14 D . . . D b14',
    'b12 T x14 . x14 T b12',
    'b10 . . R . . b10'] },
  { name: 'Zeppelin I', jets: 24, turns: 15, rows: [
    'b16 b16 Z200 . . b16 b16',
    's10 b14 b14 c20 b14 b14 s10',
    '. T . R . T .',
    'b12 b12 . . . b12 b12'] },
  { name: 'Iron Hulls', jets: 26, turns: 15, rows: [
    'a20 b18 a20 b18 a20 b18 a20',
    'b18 . b18 c24 b18 . b18',
    'T a16 T . T a16 T',
    'b14 . . R . . b14',
    's10 s10 . . . s10 s10'] },
  { name: 'Gap Run', jets: 28, turns: 16, rows: [
    'b24 b24 b24 T b24 b24 b24',
    'b22 . b22 T b22 . b22',
    'c26 . . T . . c26',
    'b20 b20 . D . b20 b20',
    'x18 . . . . . x18',
    'b16 b16 b16 R b16 b16 b16'] },
  { name: 'Thunderhead', jets: 30, turns: 16, rows: [
    's14 s14 s14 s14 s14 s14 s14',
    'a24 . a24 . a24 . a24',
    'b24 b24 . c30 . b24 b24',
    '. D . T . D .',
    'b20 . b20 . b20 . b20',
    'R . . . . . R'] },
  { name: 'Canyon', jets: 32, turns: 16, rows: [
    'b30 b30 T . T b30 b30',
    'b28 b28 T R T b28 b28',
    'b26 c30 T . T c30 b26',
    'b24 b24 D . D b24 b24',
    'x22 . . . . . x22',
    'b20 s16 . . . s16 b20'] },
  { name: 'Steel Sky', jets: 34, turns: 16, rows: [
    'a30 a30 a30 a30 a30 a30 a30',
    '. T . T . T .',
    'b28 x26 b28 x26 b28 x26 b28',
    's18 . s18 R s18 . s18',
    'b24 b24 . . . b24 b24',
    'c30 . . . . . c30'] },
  { name: 'Shutter Bay', jets: 36, turns: 17, rows: [
    'b36 T b36 b36 b36 T b36',
    'b34 d b34 c40 b34 d b34',
    'b32 T s20 . s20 T b32',
    'b30 D . R . D b30',
    'a28 T a28 . a28 T a28',
    'b24 . . . . . b24'] },
  { name: 'Bomber Wave', jets: 38, turns: 17, rows: [
    'x30 x30 x30 x30 x30 x30 x30',
    'b34 . . T . . b34',
    'b34 c36 . T . c36 b34',
    's22 s22 R T R s22 s22',
    'b30 b30 b30 . b30 b30 b30',
    'a28 . a28 . a28 . a28'] },
  { name: 'Fortress', jets: 40, turns: 18, rows: [
    'b40 b40 b40 b40 b40 b40 b40',
    'T T D . D T T',
    'b36 b36 b36 c44 b36 b36 b36',
    's24 . s24 . s24 . s24',
    'a32 a32 . R . a32 a32',
    'x30 . T . T . x30',
    'b26 b26 . . . b26 b26'] },
  { name: 'Gauntlet', jets: 44, turns: 18, rows: [
    'a40 s26 a40 s26 a40 s26 a40',
    'b40 T b40 T b40 T b40',
    'c46 . x36 R x36 . c46',
    'b36 D b36 . b36 D b36',
    's24 . s24 T s24 . s24',
    'b32 b32 . . . b32 b32',
    'R . . . . . R'] },
  { name: 'Zeppelin II', jets: 48, turns: 18, rows: [
    'a36 a36 Z600 . . a36 a36',
    'b38 T b38 c44 b38 T b38',
    's26 . s26 R s26 . s26',
    'x34 D . . . D x34',
    'b30 b30 b30 . b30 b30 b30'] },
];
const CODE = { b: 'blimp', c: 'crate', s: 'storm', a: 'armour', x: 'bomber', T: 'tower', D: 'door', d: 'door', R: 'ring', Z: 'boss' };

const INFO = {
  aim: { name: 'Drag to aim', tip: 'Drag anywhere to aim your squadron, then let go to launch. Drag below the deck line to cancel.' },
  blimp: { name: 'Blimps', tip: 'The number is how many hits it takes. Colour shows how tough it is: blue, then violet, then orange.' },
  crate: { name: 'Cargo Crates', tip: 'Tough boxes. Every crate you destroy drops a medal.' },
  storm: { name: 'Storm Clouds', tip: 'Destroy one and lightning strikes the enemies right next to it.' },
  armour: { name: 'Armoured Airships', tip: 'Plated hulls: they only take half damage from each hit.' },
  bomber: { name: 'Bombers', tip: 'If a bomber survives your turn, it pushes the enemy below it down an extra row.' },
  tower: { name: 'Radar Towers', tip: 'Solid steel. They can’t be destroyed, and your jets bounce off them.' },
  door: { name: 'Hangar Doors', tip: 'They open and close every turn! Closed doors block your jets.' },
  ring: { name: '+1 Wingman Ring', tip: 'Fly a jet through it to add a wingman for the rest of the level.' },
  boss: { name: 'Boss Zeppelin', tip: 'Three cells wide, with its own health bar. Bring it down to win.' },
};
const TIP_ORDER = ['blimp', 'crate', 'storm', 'armour', 'bomber', 'tower', 'door', 'ring', 'boss'];

/* ================= Icons (inline SVG) ================= */
const svg = (p, extra = '') => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${p}</svg>`;
const ICONS = {
  airstrike: svg('<circle cx="12" cy="12" r="7"/><path d="M12 2v5M12 17v5M2 12h5M17 12h5"/><circle cx="12" cy="12" r="1.5" fill="currentColor"/>'),
  split: svg('<path d="M12 21L6 5M12 21l6-16M6 5l-1.2 4.2M6 5l3.6 2.4M18 5l1.2 4.2M18 5l-3.6 2.4"/>'),
  storm: svg('<path d="M7 16a4 4 0 01-.5-8 5.5 5.5 0 0110.6-1A3.5 3.5 0 0117.5 14"/><path d="M13 11l-3 5h4l-3 5"/>'),
  wind: svg('<path d="M3 8h11a3 3 0 10-3-3M3 12h15a3 3 0 11-3 3M3 16h7"/>'),
  laser: svg('<path d="M4 20l3-3M9 15l2-2M13 11l2-2" /><circle cx="18" cy="6" r="3"/><path d="M18 1v2M18 9v2M13 6h2M21 6h2"/>'),
  fire: svg('<path d="M12 22c4 0 7-3 7-7 0-4-3-6-4-10-2 2-3 4-3 6-1-1-2-2-2-4-3 3-5 5-5 8 0 4 3 7 7 7z"/>'),
  cluster: svg('<path d="M12 3v5M12 16v5M3 12h5M16 12h5M5.6 5.6l3.2 3.2M15.2 15.2l3.2 3.2M18.4 5.6l-3.2 3.2M8.8 15.2l-3.2 3.2"/>'),
  stealth: svg('<path d="M12 2l2 6 7 4v2l-7-2-.5 5 2.5 2v1.5L12 19l-4 1.5V19l2.5-2-.5-5-7 2v-2l7-4z" stroke-dasharray="3 2"/>'),
  wingmen: svg('<path d="M8 3l1.3 4.2L13.5 9.5v1.3L9.3 9.7l-.5 3.3 1.6 1.3v1.1L8 14.6l-2.4.8v-1.1l1.6-1.3-.5-3.3-4.2 1.1V9.5l4.2-2.3z"/><path d="M18 12v8M14 16h8"/>'),
  help: svg('<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 114 2c-1 .6-1.5 1.1-1.5 2.2"/><path d="M12 17v.01"/>'),
  skins: svg('<path d="M12 3a9 9 0 100 18c1.2 0 1.6-.9 1.2-1.8-.5-1 .2-2.2 1.3-2.2H17a4 4 0 004-4c0-5.5-4-10-9-10z"/><circle cx="7.5" cy="11" r="1.2" fill="currentColor"/><circle cx="11" cy="7" r="1.2" fill="currentColor"/><circle cx="15.5" cy="8" r="1.2" fill="currentColor"/>'),
  pause: svg('<path d="M9 5v14M15 5v14" stroke-width="3"/>'),
  back: svg('<path d="M15 5l-7 7 7 7" stroke-width="2.6"/>'),
  close: svg('<path d="M6 6l12 12M18 6L6 18" stroke-width="2.6"/>'),
  recall: svg('<path d="M12 4v12M6 11l6 6 6-6"/><path d="M4 21h16"/>'),
  undo: svg('<path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 010 12h-3"/>'),
  sound: svg('<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M16.5 8.5a5 5 0 010 7M19 6a8.5 8.5 0 010 12"/>'),
  mute: svg('<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M17 9l5 6M22 9l-5 6"/>'),
  lock: svg('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 018 0v3"/>'),
};
const JET_PATH = 'M12 1.5l2.1 6.6 7.4 4.1v2.2l-7.4-2.1-.6 4.9 2.6 2.1v1.9L12 20.1l-4.1 1.1v-1.9l2.6-2.1-.6-4.9-7.4 2.1v-2.2l7.4-4.1z';
const jetSvg = (color) => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${JET_PATH}" fill="${color}"/></svg>`;
const MEDAL = '<svg class="sb-medal" viewBox="0 0 20 20" aria-hidden="true"><path d="M5.5 1h3.2l1.3 5.2-3 1.1zM14.5 1h-3.2L10 6.2l3 1.1z" fill="#ff4c00"/><circle cx="10" cy="12.5" r="5.8" fill="#ffc23d"/><path d="M10 9.4l1 2 2.2.3-1.6 1.5.4 2.2-2-1.1-2 1.1.4-2.2-1.6-1.5 2.2-.3z" fill="#a8700a"/></svg>';
const STAR = (cls = '') => `<svg class="sb-star ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.2l2.9 6.4 7 .7-5.3 4.7 1.6 6.9L12 17.3 5.8 20.9l1.6-6.9L2.1 9.3l7-.7z"/></svg>`;

const PU = [
  { k: 'airstrike', name: 'Airstrike', desc: 'Tap one enemy to destroy it.' },
  { k: 'split', name: 'Formation', desc: 'Your next volley flies in a V of two angles.' },
  { k: 'storm', name: 'Thunder', desc: 'Lightning hits every enemy in a random row for half its health.' },
  { k: 'wind', name: 'Crosswind', desc: 'Blows every enemy one column to the right.' },
  { k: 'laser', name: 'Laser sight', desc: 'Your aim line shows 3 bounces for the rest of the level.' },
];
const BO = [
  { k: 'fire', name: 'Afterburner', desc: 'First 3 turns: jets burn straight through enemies.' },
  { k: 'cluster', name: 'Cluster flares', desc: 'First 3 turns: every jet splits into 3 on its first hit.' },
  { k: 'stealth', name: 'Stealth', desc: 'First 3 turns: every jet slips through one tower or door.' },
  { k: 'wingmen', name: '+5 Wingmen', desc: 'Five extra jets for the whole level.' },
];
const SKINS = [
  { id: 'flare', name: 'Flare Orange', color: '#ff4c00', cost: 0 },
  { id: 'ace', name: 'Ace White', color: '#f4f2ff', cost: 25 },
  { id: 'night', name: 'Night Blue', color: '#5b6cff', cost: 25 },
  { id: 'ember', name: 'Ember', color: '#ff9a62', cost: 40 },
  { id: 'violet', name: 'Violet', color: '#b9a7e0', cost: 40 },
  { id: 'gold', name: 'Squadron Gold', color: '#ffc23d', cost: 60 },
];
const PRICE = { pu: 10, bo: 8, undo: 5, cont: 15 };

/* ================= Save data ================= */
const DEF_SAVE = () => ({ v: 1, unlocked: 1, stars: {}, best: {}, medals: 25,
  pu: { airstrike: 3, split: 3, storm: 3, wind: 3, laser: 3 },
  bo: { fire: 2, cluster: 2, stealth: 2, wingmen: 2 },
  skin: 'flare', owned: ['flare'], seen: [], sound: true });
function loadSave() {
  try {
    const s = JSON.parse(localStorage.getItem(SAVE_KEY));
    if (s && s.v === 1) { const d = DEF_SAVE(); return Object.assign(d, s, { pu: Object.assign(d.pu, s.pu), bo: Object.assign(d.bo, s.bo) }); }
  } catch (e) { /* storage blocked: play without saving */ }
  return DEF_SAVE();
}
let save = loadSave();
function store() { try { localStorage.setItem(SAVE_KEY, JSON.stringify(save)); } catch (e) { /* ignore */ } }

/* ================= Sound (tiny synth, starts after first tap) ================= */
const Sound = {
  ctx: null, last: {},
  init() {
    if (!this.ctx) { try { this.ctx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { this.ctx = null; } }
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
  },
  play(kind) {
    if (!save.sound || !this.ctx || this.ctx.state !== 'running') return;
    const now = this.ctx.currentTime, gap = { hit: 0.035, launch: 0.05, pop: 0.04 }[kind] || 0;
    if (gap && this.last[kind] && now - this.last[kind] < gap) return;
    this.last[kind] = now;
    const S = { hit: ['square', 900, 700, 0.04, 0.02], pop: ['triangle', 520, 140, 0.16, 0.06], launch: ['sine', 280, 520, 0.06, 0.015],
      star: ['triangle', 660, 1320, 0.3, 0.08], tap: ['sine', 640, 640, 0.05, 0.04], zap: ['sawtooth', 240, 60, 0.3, 0.05],
      ring: ['sine', 700, 1500, 0.18, 0.06], fail: ['triangle', 320, 90, 0.6, 0.08], boom: ['sawtooth', 160, 36, 0.45, 0.09],
      wind: ['sine', 200, 420, 0.4, 0.04], coin: ['square', 1200, 1800, 0.1, 0.03] }[kind];
    if (!S) return;
    try {
      const o = this.ctx.createOscillator(), g = this.ctx.createGain();
      o.type = S[0]; o.connect(g); g.connect(this.ctx.destination);
      o.frequency.setValueAtTime(S[1], now); o.frequency.exponentialRampToValueAtTime(S[2], now + S[3]);
      g.gain.setValueAtTime(S[4], now); g.gain.exponentialRampToValueAtTime(0.0001, now + S[3]);
      o.start(now); o.stop(now + S[3] + 0.02);
    } catch (e) { /* ignore */ }
  }
};
const buzz = (ms) => { try { if (navigator.vibrate) navigator.vibrate(ms); } catch (e) { /* ignore */ } };

/* ================= Helpers ================= */
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const rgbCache = {};
function rgb(hex) {
  if (rgbCache[hex]) return rgbCache[hex];
  const n = parseInt(hex.slice(1), 16);
  return (rgbCache[hex] = [(n >> 16) & 255, (n >> 8) & 255, n & 255]);
}
function mix(a, b, t, alpha = 1) {
  const A = rgb(a), B = rgb(b);
  const c = A.map((v, i) => Math.round(v + (B[i] - v) * t));
  return alpha < 1 ? `rgba(${c[0]},${c[1]},${c[2]},${alpha})` : '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
}
function rr(ctx, x, y, w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath(); ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
const isEnemy = (c) => c.type !== 'tower' && c.type !== 'door' && c.type !== 'ring';
const esc = (s) => String(s).replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
let uid = 0;

function parseLevel(n) {
  const def = LEVELS[n - 1], rows = def.rows;
  const bottom = rows.length <= 3 ? 3 : rows.length <= 4 ? 4 : 5;
  const cells = [];
  rows.forEach((line, i) => {
    const row = bottom - (rows.length - 1 - i);
    line.trim().split(/\s+/).forEach((tok, col) => {
      if (tok === '.') return;
      const type = CODE[tok[0]], hp = parseInt(tok.slice(1), 10) || 0;
      cells.push({ id: ++uid, type, col, row, w: type === 'boss' ? 3 : 1, hp, maxHp: hp,
        open: tok[0] === 'd', openA: tok[0] === 'd' ? 1 : 0, flash: 0, xA: 0, yA: 0, dead: false, stamp: 0 });
    });
  });
  return cells;
}
function maxRefOf(cells) { return Math.max(1, ...cells.filter((c) => isEnemy(c) && c.type !== 'boss').map((c) => c.maxHp)); }

/* ================= Drawing: enemies, blocks, jets ================= */
function tierColor(c, maxRef) {
  if (c.type === 'boss') return PAL.orange;
  const r = c.maxHp / maxRef, t = r <= 0.4 ? 0 : r <= 0.75 ? 1 : 2;
  return c.type === 'armour' ? mix(TIER[t], PAL.steel, 0.45) : TIER[t];
}
function hpText(ctx, c, x, y, s, size = 0.36) {
  const v = Math.ceil(c.hp - 1e-6);
  ctx.font = `italic 800 ${Math.round(s * size)}px ${FONT}`;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.lineWidth = Math.max(2, s * 0.07); ctx.strokeStyle = 'rgba(2,2,47,.75)'; ctx.lineJoin = 'round';
  ctx.strokeText(v, x, y); ctx.fillStyle = '#fff'; ctx.fillText(v, x, y);
}
function drawCell(ctx, c, x, y, w, h, s, maxRef, time) {
  const t = c.type;
  if (t === 'tower') return drawTower(ctx, x, y, w, h, s, time);
  if (t === 'door') return drawDoor(ctx, c, x, y, w, h, s);
  if (t === 'ring') return drawRing(ctx, x, y, w, h, s, time);
  const base = tierColor(c, maxRef);
  const dr = c.maxHp ? 1 - c.hp / c.maxHp : 0;
  const fill = mix(base, '#ffffff', 0.06 + 0.34 * dr);
  const dark = mix(base, PAL.navy, 0.45);
  // glow: brighter as it gets damaged
  ctx.save(); ctx.globalAlpha = 0.14 + 0.5 * dr; ctx.fillStyle = base;
  rr(ctx, x - s * 0.05, y - s * 0.05, w + s * 0.1, h + s * 0.1, s * 0.3); ctx.fill(); ctx.restore();

  const g = ctx.createLinearGradient(0, y, 0, y + h); g.addColorStop(0, fill); g.addColorStop(1, mix(base, PAL.navy, 0.22));
  if (t === 'blimp' || t === 'armour') {
    const by = y + h * 0.14, bh = h * 0.64;
    ctx.fillStyle = dark; // fins
    ctx.beginPath(); ctx.moveTo(x + w * 0.16, by + bh * 0.3); ctx.lineTo(x, by - h * 0.04); ctx.lineTo(x + w * 0.1, by - h * 0.04); ctx.lineTo(x + w * 0.3, by + bh * 0.25); ctx.fill();
    ctx.beginPath(); ctx.moveTo(x + w * 0.16, by + bh * 0.7); ctx.lineTo(x, by + bh + h * 0.04); ctx.lineTo(x + w * 0.1, by + bh + h * 0.04); ctx.lineTo(x + w * 0.3, by + bh * 0.75); ctx.fill();
    ctx.fillStyle = g; rr(ctx, x + w * 0.06, by, w * 0.92, bh, bh / 2); ctx.fill();
    ctx.fillStyle = dark; rr(ctx, x + w / 2 - w * 0.13, by + bh - 1, w * 0.26, h * 0.13, s * 0.04); ctx.fill();
    if (t === 'armour') {
      ctx.strokeStyle = mix(base, PAL.navy, 0.55); ctx.lineWidth = Math.max(1, s * 0.03);
      for (let i = 1; i < 4; i++) { const px = x + w * 0.06 + (w * 0.92) * i / 4; ctx.beginPath(); ctx.moveTo(px, by + 2); ctx.lineTo(px, by + bh - 2); ctx.stroke(); }
      ctx.lineWidth = Math.max(1.5, s * 0.05); ctx.strokeStyle = PAL.steel; rr(ctx, x + w * 0.06, by, w * 0.92, bh, bh / 2); ctx.stroke();
    }
    ctx.fillStyle = 'rgba(255,255,255,.35)'; rr(ctx, x + w * 0.22, by + bh * 0.14, w * 0.5, bh * 0.16, bh * 0.08); ctx.fill();
    hpText(ctx, c, x + w * 0.54, by + bh / 2, s);
  } else if (t === 'crate') {
    ctx.fillStyle = g; rr(ctx, x + w * 0.06, y + h * 0.06, w * 0.88, h * 0.88, s * 0.08); ctx.fill();
    ctx.strokeStyle = mix(base, '#ffffff', 0.45); ctx.lineWidth = s * 0.07;
    ctx.beginPath(); ctx.moveTo(x + w * 0.5, y + h * 0.08); ctx.lineTo(x + w * 0.5, y + h * 0.92);
    ctx.moveTo(x + w * 0.08, y + h * 0.5); ctx.lineTo(x + w * 0.92, y + h * 0.5); ctx.stroke();
    ctx.fillStyle = dark; rr(ctx, x + w * 0.22, y + h * 0.32, w * 0.56, h * 0.36, s * 0.08); ctx.fill();
    hpText(ctx, c, x + w / 2, y + h / 2, s, 0.32);
  } else if (t === 'storm') {
    const cf = mix(base, PAL.steel, 0.3), cg = ctx.createLinearGradient(0, y, 0, y + h);
    cg.addColorStop(0, mix(cf, '#ffffff', 0.15 + 0.3 * dr)); cg.addColorStop(1, mix(cf, PAL.navy, 0.3));
    ctx.fillStyle = cg; ctx.beginPath();
    ctx.arc(x + w * 0.3, y + h * 0.56, s * 0.22, 0, 7); ctx.arc(x + w * 0.52, y + h * 0.4, s * 0.27, 0, 7);
    ctx.arc(x + w * 0.74, y + h * 0.56, s * 0.2, 0, 7); ctx.fill();
    rr(ctx, x + w * 0.12, y + h * 0.52, w * 0.76, h * 0.3, h * 0.15); ctx.fill();
    ctx.fillStyle = PAL.gold; ctx.beginPath();
    ctx.moveTo(x + w * 0.66, y + h * 0.66); ctx.lineTo(x + w * 0.56, y + h * 0.86); ctx.lineTo(x + w * 0.64, y + h * 0.86);
    ctx.lineTo(x + w * 0.58, y + h * 1.0); ctx.lineTo(x + w * 0.76, y + h * 0.78); ctx.lineTo(x + w * 0.68, y + h * 0.78); ctx.lineTo(x + w * 0.74, y + h * 0.66); ctx.fill();
    hpText(ctx, c, x + w * 0.48, y + h * 0.56, s, 0.34);
  } else if (t === 'bomber') {
    ctx.fillStyle = g;
    ctx.beginPath(); // swept wings, nose pointing at the deck
    ctx.moveTo(x + w * 0.5, y + h * 0.3); ctx.lineTo(x + w * 0.98, y + h * 0.5); ctx.lineTo(x + w * 0.98, y + h * 0.62);
    ctx.lineTo(x + w * 0.5, y + h * 0.54); ctx.lineTo(x + w * 0.02, y + h * 0.62); ctx.lineTo(x + w * 0.02, y + h * 0.5); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(x + w * 0.5, y + h * 0.02); ctx.lineTo(x + w * 0.72, y + h * 0.14); ctx.lineTo(x + w * 0.28, y + h * 0.14); ctx.fill();
    rr(ctx, x + w * 0.38, y + h * 0.04, w * 0.24, h * 0.92, w * 0.12); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,.55)'; rr(ctx, x + w * 0.44, y + h * 0.7, w * 0.12, h * 0.14, w * 0.06); ctx.fill();
    hpText(ctx, c, x + w / 2, y + h * 0.44, s, 0.32);
  } else if (t === 'boss') {
    const by = y + h * 0.08, bh = h * 0.78;
    ctx.fillStyle = PAL.deep;
    ctx.beginPath(); ctx.moveTo(x + s * 0.3, by + bh * 0.3); ctx.lineTo(x, by - h * 0.06); ctx.lineTo(x + s * 0.2, by - h * 0.06); ctx.lineTo(x + s * 0.55, by + bh * 0.25); ctx.fill();
    ctx.beginPath(); ctx.moveTo(x + s * 0.3, by + bh * 0.7); ctx.lineTo(x, by + bh + h * 0.06); ctx.lineTo(x + s * 0.2, by + bh + h * 0.06); ctx.lineTo(x + s * 0.55, by + bh * 0.75); ctx.fill();
    const bg = ctx.createLinearGradient(0, by, 0, by + bh);
    bg.addColorStop(0, mix(PAL.orange, '#ffffff', 0.25 + 0.3 * dr)); bg.addColorStop(1, mix(PAL.orange, PAL.navy, 0.35));
    ctx.fillStyle = bg; rr(ctx, x + s * 0.12, by, w - s * 0.14, bh, bh / 2); ctx.fill();
    ctx.fillStyle = 'rgba(2,2,47,.35)';
    for (let i = 1; i < 6; i++) { const px = x + s * 0.12 + (w - s * 0.14) * i / 6; ctx.fillRect(px - 1, by + 3, 2, bh - 6); }
    ctx.fillStyle = PAL.navy; rr(ctx, x + w / 2 - s * 0.45, by + bh - 2, s * 0.9, h * 0.16, s * 0.06); ctx.fill();
    ctx.fillStyle = PAL.gold; for (let i = 0; i < 4; i++) ctx.fillRect(x + w / 2 - s * 0.36 + i * s * 0.22, by + bh + h * 0.03, s * 0.1, h * 0.06);
    ctx.fillStyle = 'rgba(255,255,255,.35)'; rr(ctx, x + s * 0.5, by + bh * 0.13, w * 0.5, bh * 0.13, bh * 0.07); ctx.fill();
    hpText(ctx, c, x + w * 0.55, by + bh / 2, s, 0.5);
  }
  if (c.flash > 0) {
    ctx.save(); ctx.globalAlpha = Math.min(0.7, c.flash * 6); ctx.fillStyle = '#fff';
    rr(ctx, x, y + h * 0.08, w, h * 0.84, s * 0.25); ctx.fill(); ctx.restore();
  }
}
function drawTower(ctx, x, y, w, h, s, time) {
  const g = ctx.createLinearGradient(x, 0, x + w, 0);
  g.addColorStop(0, PAL.steelD); g.addColorStop(0.45, PAL.steel); g.addColorStop(1, PAL.steelD);
  ctx.fillStyle = g; rr(ctx, x + w * 0.2, y - s * GAP, w * 0.6, h + s * GAP * 2, s * 0.06); ctx.fill();
  ctx.strokeStyle = 'rgba(2,2,47,.45)'; ctx.lineWidth = Math.max(1, s * 0.03);
  ctx.beginPath();
  for (let i = 0; i < 3; i++) { const yy = y + h * (0.2 + i * 0.3); ctx.moveTo(x + w * 0.22, yy); ctx.lineTo(x + w * 0.78, yy + h * 0.15); ctx.moveTo(x + w * 0.78, yy); ctx.lineTo(x + w * 0.22, yy + h * 0.15); }
  ctx.stroke();
  ctx.fillStyle = PAL.orange; ctx.fillRect(x + w * 0.2, y + h * 0.02, w * 0.6, h * 0.08);
  ctx.fillStyle = `rgba(255,90,79,${0.4 + 0.6 * Math.abs(Math.sin(time * 3 + x))})`;
  ctx.beginPath(); ctx.arc(x + w / 2, y + h * 0.06, s * 0.06, 0, 7); ctx.fill();
}
function drawDoor(ctx, c, x, y, w, h, s) {
  const o = c.openA;
  ctx.strokeStyle = 'rgba(154,160,204,.7)'; ctx.lineWidth = Math.max(1.5, s * 0.04);
  ctx.setLineDash(o > 0.95 ? [s * 0.1, s * 0.08] : []); rr(ctx, x, y, w, h, s * 0.06); ctx.stroke(); ctx.setLineDash([]);
  const pw = (w / 2) * (1 - o);
  if (pw > 0.5) {
    const g = ctx.createLinearGradient(0, y, 0, y + h); g.addColorStop(0, PAL.steel); g.addColorStop(1, PAL.steelD);
    ctx.fillStyle = g; ctx.fillRect(x + 1, y + 1, pw, h - 2); ctx.fillRect(x + w - 1 - pw, y + 1, pw, h - 2);
    ctx.fillStyle = PAL.orange;
    ctx.fillRect(x + pw - s * 0.05, y + 1, s * 0.05, h - 2); ctx.fillRect(x + w - pw, y + 1, s * 0.05, h - 2);
    ctx.strokeStyle = 'rgba(2,2,47,.35)'; ctx.lineWidth = 1; ctx.beginPath();
    for (let i = 1; i < 4; i++) { const yy = y + h * i / 4; ctx.moveTo(x + 2, yy); ctx.lineTo(x + pw - 2, yy); ctx.moveTo(x + w - pw + 2, yy); ctx.lineTo(x + w - 2, yy); }
    ctx.stroke();
  }
}
function drawRing(ctx, x, y, w, h, s, time) {
  const cx = x + w / 2, cy = y + h / 2, r = s * 0.3 * (1 + 0.06 * Math.sin(time * 5));
  ctx.save(); ctx.globalAlpha = 0.25; ctx.fillStyle = PAL.orange; ctx.beginPath(); ctx.arc(cx, cy, r * 1.35, 0, 7); ctx.fill(); ctx.restore();
  ctx.strokeStyle = PAL.orange; ctx.lineWidth = s * 0.08; ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.stroke();
  ctx.strokeStyle = PAL.gold; ctx.lineWidth = s * 0.03; ctx.setLineDash([s * 0.08, s * 0.1]); ctx.lineDashOffset = -time * s;
  ctx.beginPath(); ctx.arc(cx, cy, r * 0.72, 0, 7); ctx.stroke(); ctx.setLineDash([]);
  ctx.font = `italic 800 ${Math.round(s * 0.26)}px ${FONT}`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillStyle = '#fff'; ctx.fillText('+1', cx, cy + 1);
}
function drawJet(ctx, x, y, ang, size, color) {
  const u = size / 10;
  ctx.save(); ctx.translate(x, y); ctx.rotate(ang);
  ctx.fillStyle = color; ctx.beginPath();
  ctx.moveTo(5 * u, 0); ctx.lineTo(1.2 * u, -0.9 * u); ctx.lineTo(-1 * u, -4 * u); ctx.lineTo(-2.4 * u, -4 * u); ctx.lineTo(-1.4 * u, -1 * u);
  ctx.lineTo(-3.4 * u, -1 * u); ctx.lineTo(-4.4 * u, -2.2 * u); ctx.lineTo(-5 * u, -2.2 * u); ctx.lineTo(-4.4 * u, 0);
  ctx.lineTo(-5 * u, 2.2 * u); ctx.lineTo(-4.4 * u, 2.2 * u); ctx.lineTo(-3.4 * u, 1 * u); ctx.lineTo(-1.4 * u, 1 * u);
  ctx.lineTo(-2.4 * u, 4 * u); ctx.lineTo(-1 * u, 4 * u); ctx.lineTo(1.2 * u, 0.9 * u); ctx.closePath(); ctx.fill();
  ctx.fillStyle = 'rgba(2,2,47,.55)'; ctx.beginPath(); ctx.ellipse(1.8 * u, 0, 1.3 * u, 0.5 * u, 0, 0, 7); ctx.fill();
  ctx.restore();
}

/* ================= DOM: build once ================= */
let root, phone, canvas, ctx, hud, el = {};
let built = false, running = false, raf = 0, lastTs = 0, onCloseCb = null;
let W = 0, H = 0, dpr = 1, S = 40, OX = 0, OY = 0, bgCanvas = null;
let mode = 'title', time = 0;

const CSS = `
#sb-root{position:fixed;inset:0;z-index:1000;display:flex;justify-content:center;align-items:center;background:#01011c;font-family:"Barlow",system-ui,-apple-system,sans-serif;color:#fff;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;touch-action:none;overscroll-behavior:none;-webkit-touch-callout:none}
#sb-root *{box-sizing:border-box}
:where(#sb-root button){font:inherit;color:inherit}
#sb-root button{cursor:pointer;touch-action:manipulation;-webkit-tap-highlight-color:transparent}
#sb-root button:focus-visible{outline:3px solid #ff4c00;outline-offset:2px}
.sb-phone{position:relative;width:100%;height:100%;max-width:460px;overflow:hidden;background:#02022f;isolation:isolate}
@media (min-width:640px){#sb-root{padding:20px;background:radial-gradient(circle at 50% 25%,#151a62,#01011c 70%)}.sb-phone{height:100%;max-height:900px;border-radius:40px;box-shadow:0 0 0 10px #0b0d33,0 0 0 11px #2b307a,0 30px 90px rgba(0,0,0,.65)}}
.sb-canvas{position:absolute;inset:0;width:100%;height:100%;display:block}
.sb-hud{position:absolute;inset:0;display:flex;flex-direction:column;pointer-events:none}
.sb-top{pointer-events:auto;display:grid;grid-template-columns:auto auto 1fr auto auto;align-items:center;gap:8px;padding:calc(env(safe-area-inset-top,0px) + 10px) 12px 6px}
.sb-field{flex:1}
.sb-bottom{pointer-events:auto;padding:6px 10px calc(env(safe-area-inset-bottom,0px) + 10px);min-height:calc(env(safe-area-inset-bottom,0px) + 88px)}
.sb-ib{width:40px;height:40px;border-radius:50%;display:grid;place-items:center;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.16);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px);transition:transform .12s}
.sb-ib:active{transform:scale(.9)}
.sb-ib svg{width:20px;height:20px}
.sb-scorebox{text-align:center;line-height:1;min-width:0}
.sb-lvl{font-size:11px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:#ff8a52}
.sb-score{font:italic 800 28px/1.05 "Barlow Semi Condensed","Arial Narrow",sans-serif;font-variant-numeric:tabular-nums;margin-top:2px}
.sb-bar{position:relative;height:8px;border-radius:99px;background:rgba(255,255,255,.14);margin:6px auto 0;width:min(170px,100%)}
.sb-bar i{position:absolute;left:0;top:0;bottom:0;border-radius:99px;background:linear-gradient(90deg,#ff8a52,#ff4c00);width:0;transition:width .25s}
.sb-bar .sb-star{position:absolute;top:50%;width:18px;height:18px;transform:translate(-50%,-50%);fill:#2a2f72;stroke:#02022f;stroke-width:1.5;transition:fill .2s,transform .3s cubic-bezier(.3,1.8,.5,1)}
.sb-bar .sb-star.on{fill:#ffc23d;transform:translate(-50%,-50%) scale(1.2)}
.sb-turns{font:italic 800 15px "Barlow Semi Condensed",sans-serif;padding:6px 10px;border-radius:99px;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.16);white-space:nowrap}
.sb-turns.low{background:#ff4c00;border-color:#ff4c00}
.sb-tray{display:grid;grid-template-columns:repeat(5,1fr);gap:7px}
.sb-pu{position:relative;display:flex;flex-direction:column;align-items:center;gap:3px;padding:9px 2px 7px;border-radius:16px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);transition:transform .12s,background .15s}
.sb-pu:active{transform:scale(.93)}
.sb-pu svg{width:24px;height:24px}
.sb-pu span{font-size:11px;font-weight:600;letter-spacing:.02em;white-space:nowrap}
.sb-pu b{position:absolute;top:-6px;right:-3px;min-width:26px;padding:1px 6px;border-radius:99px;background:#ff4c00;font:italic 800 12px/1.3 "Barlow Semi Condensed",sans-serif;box-shadow:0 2px 6px rgba(0,0,0,.35)}
.sb-pu b.zero{background:#2a2f72}
.sb-pu.on{background:rgba(255,76,0,.25);border-color:#ff4c00}
.sb-pu.dim{opacity:.45}
.sb-shot{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.sb-btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;min-height:54px;padding:0 22px;border-radius:16px;border:0;background:linear-gradient(#ff6a24,#ff4c00);color:#fff;font:italic 800 21px "Barlow Semi Condensed","Arial Narrow",sans-serif;letter-spacing:.03em;text-transform:uppercase;box-shadow:0 4px 0 #a83200,0 10px 24px rgba(255,76,0,.35);transition:transform .1s,box-shadow .1s;width:100%}
.sb-btn:active{transform:translateY(3px);box-shadow:0 1px 0 #a83200,0 4px 12px rgba(255,76,0,.3)}
.sb-btn svg{width:22px;height:22px}
.sb-btn.sec{background:rgba(255,255,255,.1);box-shadow:inset 0 0 0 1px rgba(255,255,255,.2)}
.sb-btn.sec:active{transform:scale(.97)}
.sb-btn.ghost{background:none;box-shadow:none;min-height:44px;font-size:17px;color:#b9bce0}
.sb-btn.big{min-height:62px;font-size:26px}
.sb-btn[disabled]{opacity:.45}
.sb-medal{width:18px;height:18px;flex:none;vertical-align:-3px}
.sb-screen{position:absolute;inset:0;display:flex;flex-direction:column;padding:calc(env(safe-area-inset-top,0px) + 14px) 20px calc(env(safe-area-inset-bottom,0px) + 18px);animation:sbIn .4s cubic-bezier(.2,.9,.3,1.1)}
@keyframes sbIn{from{opacity:0;transform:scale(.96)}to{opacity:1;transform:none}}
.sb-title{justify-content:space-between;text-align:center}
.sb-title .logo{width:150px;margin:6px auto 0;display:block}
.sb-name{font:italic 800 clamp(54px,17vw,76px)/.86 "Barlow Semi Condensed","Arial Narrow",sans-serif;letter-spacing:-.01em;margin:0;text-shadow:0 6px 30px rgba(255,76,0,.25)}
.sb-name span{display:block;color:#ff4c00}
.sb-tag{color:#b9bce0;font-size:16px;margin:12px auto 0;max-width:30ch}
.sb-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:0 0 16px}
.sb-stats div{background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);border-radius:16px;padding:10px 6px;-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px)}
.sb-stats b{display:flex;align-items:center;justify-content:center;gap:4px;font:italic 800 24px "Barlow Semi Condensed",sans-serif}
.sb-stats span{font-size:12px;color:#b9bce0}
.sb-col{display:grid;gap:10px}
.sb-head{display:flex;align-items:center;gap:10px;margin-bottom:8px}
.sb-head h2{font:italic 800 30px "Barlow Semi Condensed",sans-serif;margin:0;flex:1}
.sb-pill{display:inline-flex;align-items:center;gap:6px;padding:6px 12px;border-radius:99px;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.16);font:italic 800 17px "Barlow Semi Condensed",sans-serif}
.sb-mapscroll{flex:1;overflow-y:auto;touch-action:pan-y;-webkit-overflow-scrolling:touch;margin:0 -20px;padding:10px 20px 30px;mask-image:linear-gradient(transparent,#000 4%,#000 94%,transparent)}
.sb-path{display:flex;flex-direction:column;align-items:center;gap:0}
.sb-node{position:relative;width:76px;height:76px;border-radius:50%;border:0;display:grid;place-items:center;background:radial-gradient(circle at 35% 30%,#ff8a52,#ff4c00 65%);box-shadow:0 5px 0 #a83200,0 10px 24px rgba(255,76,0,.35);font:italic 800 30px "Barlow Semi Condensed",sans-serif;transition:transform .12s}
.sb-node:active{transform:scale(.92)}
.sb-node.done{background:radial-gradient(circle at 35% 30%,#4a56c9,#1b2170 70%);box-shadow:0 5px 0 #0a0d45,0 8px 18px rgba(0,0,0,.35)}
.sb-node.locked{background:#14185a;box-shadow:0 5px 0 #0a0d45;color:#5a5f9a}
.sb-node.locked svg{width:24px;height:24px}
.sb-node.boss{width:92px;height:92px}
.sb-node.boss::after{content:"BOSS";position:absolute;top:-10px;left:50%;transform:translateX(-50%);font:italic 800 12px "Barlow Semi Condensed",sans-serif;background:#ffc23d;color:#02022f;padding:1px 8px;border-radius:99px;letter-spacing:.06em}
.sb-node.current{animation:sbPulse 1.6s ease-in-out infinite}
@keyframes sbPulse{0%,100%{box-shadow:0 5px 0 #a83200,0 0 0 0 rgba(255,76,0,.55)}50%{box-shadow:0 5px 0 #a83200,0 0 0 14px rgba(255,76,0,0)}}
.sb-nstars{position:absolute;bottom:-14px;left:50%;transform:translateX(-50%);display:flex;gap:1px}
.sb-nstars .sb-star{width:18px;height:18px;fill:#2a2f72;stroke:#02022f;stroke-width:1.5}
.sb-nstars .sb-star.on{fill:#ffc23d}
.sb-dots{width:6px;height:36px;background:radial-gradient(circle,rgba(255,255,255,.35) 2px,transparent 2.5px) 0 0/6px 12px repeat-y}
.sb-wrap{position:absolute;inset:0;z-index:5;display:flex;align-items:flex-end;background:rgba(1,1,20,.55);-webkit-backdrop-filter:blur(3px);backdrop-filter:blur(3px);opacity:0;transition:opacity .25s}
.sb-wrap.on{opacity:1}
.sb-wrap.center{align-items:center;padding:20px}
.sb-sheet{width:100%;max-height:90%;overflow-y:auto;touch-action:pan-y;background:linear-gradient(180deg,#171c78,#0a0c45);border-top:1px solid rgba(255,255,255,.18);border-radius:30px 30px 0 0;padding:8px 20px calc(env(safe-area-inset-bottom,0px) + 20px);transform:translateY(100%);transition:transform .38s cubic-bezier(.2,.9,.25,1.08)}
.sb-wrap.on .sb-sheet{transform:none}
.sb-wrap.center .sb-sheet{border-radius:30px;border:1px solid rgba(255,255,255,.18);padding:22px 20px 18px;transform:scale(.8);opacity:0;transition:transform .4s cubic-bezier(.3,1.5,.5,1),opacity .2s;text-align:center}
.sb-wrap.center.on .sb-sheet{transform:none;opacity:1}
.sb-grab{width:40px;height:5px;border-radius:99px;background:rgba(255,255,255,.3);margin:0 auto 12px}
.sb-sh{display:flex;align-items:flex-start;gap:10px;margin-bottom:12px}
.sb-sh div{flex:1}
.sb-eyebrow{font-size:12px;font-weight:600;letter-spacing:.12em;text-transform:uppercase;color:#ff8a52}
.sb-sheet h3{font:italic 800 30px/1.05 "Barlow Semi Condensed",sans-serif;margin:2px 0 0}
.sb-sheet p{color:#c9cbea;margin:6px 0 0;font-size:15px;line-height:1.45}
.sb-mini{display:block;width:100%;border-radius:18px;background:rgba(2,2,47,.6);border:1px solid rgba(255,255,255,.12)}
.sb-meta{display:flex;justify-content:center;gap:14px;margin:10px 0 14px;font-size:14px;color:#c9cbea}
.sb-meta b{color:#fff;font:italic 800 17px "Barlow Semi Condensed",sans-serif}
.sb-boost{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:8px 0 6px}
.sb-bslot{position:relative;aspect-ratio:1;border-radius:18px;background:rgba(255,255,255,.08);border:2px solid rgba(255,255,255,.14);display:grid;place-items:center;transition:transform .12s,border-color .15s,background .15s}
.sb-bslot:active{transform:scale(.92)}
.sb-bslot svg{width:30px;height:30px}
.sb-bslot.sel{border-color:#ff4c00;background:rgba(255,76,0,.22)}
.sb-bslot.sel::before{content:"\\2713";position:absolute;top:-8px;left:-6px;width:22px;height:22px;border-radius:50%;background:#4cc283;display:grid;place-items:center;font-size:13px;font-weight:800}
.sb-bslot b{position:absolute;bottom:-7px;right:-4px;padding:0 7px;border-radius:99px;background:#ff4c00;font:italic 800 13px/1.4 "Barlow Semi Condensed",sans-serif}
.sb-bslot b.zero{background:#2a2f72}
.sb-bdesc{min-height:40px;font-size:14px;color:#c9cbea;text-align:center;margin:8px 0 14px}
.sb-bdesc b{color:#fff}
.sb-bigstars{display:flex;justify-content:center;align-items:flex-end;gap:6px;margin:-6px 0 8px}
.sb-bigstars .sb-star{width:64px;height:64px;fill:#2a2f72;stroke:#02022f;stroke-width:1}
.sb-bigstars .sb-star:nth-child(2){width:84px;height:84px}
.sb-bigstars .sb-star.on{fill:#ffc23d;animation:sbStar .55s cubic-bezier(.3,1.8,.5,1) both}
@keyframes sbStar{from{transform:scale(0) rotate(-40deg)}to{transform:none}}
.sb-big{font:italic 800 46px/1 "Barlow Semi Condensed",sans-serif;font-variant-numeric:tabular-nums;margin:10px 0 2px}
.sb-earn{display:flex;justify-content:center;gap:10px;margin:8px 0 16px;flex-wrap:wrap}
.sb-list{display:grid;gap:8px;margin:12px 0}
.sb-li{display:grid;grid-template-columns:48px 1fr;gap:12px;align-items:center;padding:8px 10px;border-radius:16px;background:rgba(255,255,255,.06)}
.sb-li canvas{width:48px;height:48px}
.sb-li b{display:block;font:italic 800 18px "Barlow Semi Condensed",sans-serif}
.sb-li span{font-size:14px;color:#c9cbea}
.sb-skins{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:12px 0 4px}
.sb-skin{border-radius:18px;padding:12px 6px 10px;background:rgba(255,255,255,.07);border:2px solid rgba(255,255,255,.12);display:grid;justify-items:center;gap:4px}
.sb-skin svg{width:44px;height:44px;filter:drop-shadow(0 4px 8px rgba(0,0,0,.4))}
.sb-skin b{font-size:13px;font-weight:600}
.sb-skin span{font-size:12px;color:#c9cbea;display:flex;align-items:center;gap:3px}
.sb-skin.eq{border-color:#ff4c00;background:rgba(255,76,0,.18)}
.sb-tip{position:absolute;inset:0;z-index:6;display:flex;align-items:center;justify-content:center;padding:24px;background:rgba(1,1,20,.62);animation:sbFade .25s}
@keyframes sbFade{from{opacity:0}}
.sb-tipcard{width:100%;max-width:340px;background:#fff3ea;color:#02022f;border-radius:26px;padding:20px 20px 16px;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.5);animation:sbPop .45s cubic-bezier(.3,1.6,.5,1)}
@keyframes sbPop{from{transform:scale(.6);opacity:0}}
.sb-tipcard canvas{width:84px;height:84px;display:block;margin:0 auto 6px}
.sb-tipcard .sb-eyebrow{color:#c23a00}
.sb-tipcard h3{font:italic 800 28px/1.05 "Barlow Semi Condensed",sans-serif;margin:2px 0 6px}
.sb-tipcard p{margin:0 0 14px;font-size:16px;line-height:1.4;color:#2a2c55}
.sb-tipcard small{font-size:13px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;color:#c23a00;animation:sbBlink 1.4s ease-in-out infinite}
@keyframes sbBlink{50%{opacity:.35}}
.sb-toast{position:absolute;left:50%;top:calc(env(safe-area-inset-top,0px) + 74px);z-index:7;transform:translate(-50%,-20px);opacity:0;padding:9px 16px;border-radius:99px;background:#fff3ea;color:#02022f;font-weight:600;font-size:14px;box-shadow:0 8px 24px rgba(0,0,0,.4);transition:opacity .2s,transform .3s cubic-bezier(.3,1.6,.5,1);pointer-events:none;white-space:nowrap;max-width:90%;overflow:hidden;text-overflow:ellipsis}
.sb-toast.on{opacity:1;transform:translate(-50%,0)}
.sb-banner{position:absolute;left:50%;top:calc(env(safe-area-inset-top,0px) + 74px);transform:translateX(-50%);z-index:4;padding:8px 14px;border-radius:99px;background:#ff4c00;font-weight:700;font-size:14px;pointer-events:none;white-space:nowrap;animation:sbBlink 1.2s ease-in-out infinite}
.sb-row{display:flex;gap:10px}
.sb-row>*{flex:1}
.sb-sm{font-size:13px;color:#9a9dcc;text-align:center;margin-top:10px}
@media (prefers-reduced-motion:reduce){.sb-screen,.sb-tipcard,.sb-node.current,.sb-bigstars .sb-star.on{animation:none}}
`;

function h(html) { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; }

function build() {
  if (built) return;
  built = true;
  const st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
  root = h(`<div id="sb-root" hidden role="application" aria-label="Sky Barrage game">
    <div class="sb-phone">
      <canvas class="sb-canvas"></canvas>
      <div class="sb-hud" hidden>
        <div class="sb-top">
          <button class="sb-ib" data-act="help" aria-label="How to play">${ICONS.help}</button>
          <button class="sb-ib" data-act="skins" aria-label="Jet colours">${ICONS.skins}</button>
          <div class="sb-scorebox"><div class="sb-lvl" id="sb-lvl">Level 1</div><div class="sb-score" id="sb-score">0</div>
            <div class="sb-bar" id="sb-bar"><i></i>${STAR()}${STAR()}${STAR()}</div></div>
          <div class="sb-turns" id="sb-turns">12 turns</div>
          <button class="sb-ib" data-act="pause" aria-label="Pause">${ICONS.pause}</button>
        </div>
        <div class="sb-field"></div>
        <div class="sb-bottom">
          <div class="sb-tray" id="sb-tray">${PU.map((p) => `<button class="sb-pu" data-act="pu" data-k="${p.k}" aria-label="${p.name}">${ICONS[p.k]}<span>${p.name}</span><b>x0</b></button>`).join('')}</div>
          <div class="sb-shot" id="sb-shot" hidden>
            <button class="sb-btn sec" data-act="recall">${ICONS.recall}Recall<small style="font-size:13px;opacity:.8;font-style:normal">free</small></button>
            <button class="sb-btn sec" data-act="undo">${ICONS.undo}Undo <span style="display:inline-flex;align-items:center;gap:3px;font-size:17px">${MEDAL}${PRICE.undo}</span></button>
          </div>
        </div>
      </div>
      <div id="sb-screens"></div>
      <div class="sb-toast" id="sb-toast"></div>
    </div>
  </div>`);
  document.body.appendChild(root);
  phone = root.querySelector('.sb-phone');
  canvas = root.querySelector('canvas'); ctx = canvas.getContext('2d');
  hud = root.querySelector('.sb-hud');
  el = { lvl: root.querySelector('#sb-lvl'), score: root.querySelector('#sb-score'), bar: root.querySelector('#sb-bar'),
    turns: root.querySelector('#sb-turns'), tray: root.querySelector('#sb-tray'), shot: root.querySelector('#sb-shot'),
    screens: root.querySelector('#sb-screens'), toast: root.querySelector('#sb-toast'), top: root.querySelector('.sb-top'), bottom: root.querySelector('.sb-bottom') };

  root.addEventListener('click', onClick);
  canvas.addEventListener('pointerdown', onDown);
  canvas.addEventListener('pointermove', onMove);
  canvas.addEventListener('pointerup', onUp);
  canvas.addEventListener('pointercancel', onUp);
  root.addEventListener('contextmenu', (e) => e.preventDefault());
  root.addEventListener('pointerdown', () => Sound.init(), true);
  if (window.ResizeObserver) new ResizeObserver(() => layout()).observe(phone);
  window.addEventListener('resize', layout);
  document.addEventListener('visibilitychange', () => { if (document.hidden && running && mode === 'game' && G && G.state !== 'done' && !G.paused) openPause(); });
  document.addEventListener('keydown', (e) => {
    if (!running) return;
    if (e.key === 'Escape') { if (sheetOpen) closeSheet(); else if (mode === 'game') openPause(); else if (mode === 'map') showTitle(); else close(); }
  });
}

/* ================= Layout & background ================= */
function layout() {
  if (!running) return;
  const r = phone.getBoundingClientRect();
  W = r.width; H = r.height; dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
  let top = 0, bot = 0;
  if (mode === 'game') { top = el.top.getBoundingClientRect().bottom - r.top; bot = r.bottom - el.bottom.getBoundingClientRect().top; }
  const aw = W - 14, ah = H - top - bot - 8;
  S = Math.max(10, Math.min(aw / COLS, ah / FIELD_H));
  OX = (W - S * COLS) / 2; OY = top + 4 + Math.max(0, (ah - S * FIELD_H) / 2);
  bgCanvas = document.createElement('canvas'); bgCanvas.width = Math.max(1, Math.round(W)); bgCanvas.height = Math.max(1, Math.round(H));
  const b = bgCanvas.getContext('2d'), g = b.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, '#02022f'); g.addColorStop(0.55, '#0d1260'); g.addColorStop(1, '#1d2385');
  b.fillStyle = g; b.fillRect(0, 0, W, H);
  const sun = b.createRadialGradient(W * 0.85, 0, 0, W * 0.85, 0, Math.min(W, 460) * 0.55);
  sun.addColorStop(0, 'rgba(255,76,0,.16)'); sun.addColorStop(1, 'rgba(255,76,0,0)'); b.fillStyle = sun; b.fillRect(0, 0, W, H);
  b.fillStyle = 'rgba(255,255,255,.5)';
  for (let i = 0; i < 40; i++) { const x = (i * 97.3) % W, y = (i * 53.7) % (H * 0.5); b.globalAlpha = 0.15 + (i % 5) * 0.08; b.fillRect(x, y, 1.4, 1.4); }
  b.globalAlpha = 1;
}
const clouds = Array.from({ length: 9 }, (_, i) => ({ x: (i * 0.37) % 1, y: 0.08 + (i * 0.113) % 0.8, s: 0.6 + (i % 4) * 0.3, v: 0.006 + (i % 3) * 0.004 }));
function drawSky(dt) {
  ctx.drawImage(bgCanvas, 0, 0, W, H);
  ctx.fillStyle = 'rgba(185,188,224,.045)';
  for (const c of clouds) {
    c.x += c.v * dt; if (c.x > 1.3) c.x = -0.3;
    const x = c.x * W, y = c.y * H, s = c.s * Math.min(W, 460) * 0.06;
    ctx.beginPath();
    ctx.moveTo(x - s * 0.4, y + s * 0.5);
    ctx.arc(x, y + s * 0.1, s * 0.6, Math.PI * 0.6, Math.PI * 1.5);
    ctx.arc(x + s * 1.0, y - s * 0.35, s * 0.85, Math.PI * 1.05, Math.PI * 1.95);
    ctx.arc(x + s * 2.1, y + s * 0.1, s * 0.6, Math.PI * 1.5, Math.PI * 0.4);
    ctx.closePath(); ctx.fill();
  }
}

/* ================= Pools ================= */
const JMAX = 520, PMAX = 1000, TMAX = 80;
const jets = Array.from({ length: JMAX }, () => ({ active: false }));
const parts = Array.from({ length: PMAX }, () => ({ life: 0 }));
const texts = Array.from({ length: TMAX }, () => ({ life: 0 }));
let jPtr = 0, pPtr = 0, tPtr = 0;
function getJet() { for (let i = 0; i < JMAX; i++) { const k = (jPtr + i) % JMAX; if (!jets[k].active) { jPtr = k + 1; jets[k].active = true; return jets[k]; } } return null; }
function spark(x, y, vx, vy, life, size, color) {
  const p = parts[pPtr]; pPtr = (pPtr + 1) % PMAX;
  p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.max = life; p.size = size; p.color = color;
}
function burst(x, y, n, colors, force = 4) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, v = force * (0.3 + Math.random());
    spark(x, y, Math.cos(a) * v, Math.sin(a) * v - 1, 0.45 + Math.random() * 0.5, 0.05 + Math.random() * 0.08, colors[i % colors.length]);
  }
}
function floatText(x, y, text, color = '#fff', size = 0.34) {
  const t = texts[tPtr]; tPtr = (tPtr + 1) % TMAX;
  t.x = x; t.y = y; t.text = text; t.color = color; t.size = size; t.life = 0.9; t.max = 0.9;
}

/* ================= Game state ================= */
let G = null;
let occ = new Array((LAST_ROW + 1) * COLS).fill(null);
let stamp = 0;
function rebuildOcc() {
  occ.fill(null);
  for (const c of G.cells) {
    if (c.dead || c.row < 0 || c.row > LAST_ROW) continue;
    for (let k = 0; k < c.w; k++) occ[c.row * COLS + c.col + k] = c;
  }
}
const enemiesLeft = () => G.cells.some((c) => !c.dead && isEnemy(c));
function cellAt(r, c) { return G.cells.find((x) => !x.dead && x.row === r && c >= x.col && c < x.col + x.w); }

function startLevel(n, picks) {
  const cells = parseLevel(n), def = LEVELS[n - 1];
  const enemies = cells.filter(isEnemy);
  const base = enemies.reduce((s, c) => s + c.maxHp * 10 + (c.type === 'boss' ? 500 : 50), 0);
  G = { n, def, cells, maxRef: maxRefOf(cells), turnsLeft: def.turns, baseJets: def.jets, bonus: 0, launchX: COLS / 2,
    firstX: null, score: 0, shown: 0, medalsEarned: 0, laser: false, splitArmed: false, volleySplit: false,
    bo: { fire: 0, cluster: 0, stealth: 0 }, state: 'aim', aim: 90, aimOk: false, aiming: false, guide: null,
    toLaunch: 0, launchT: 0, launched: 0, shotTime: 0, shiftT: 0, clearT: 0, shake: 0, chain: [], bolts: [],
    stars: [base, base + 100 * Math.ceil(def.turns * 0.15), base + 100 * Math.ceil(def.turns * 0.35)],
    paused: false, tip: false, snap: null, wind: 0, extraTurns: 0 };
  for (const k of picks) {
    if (save.bo[k] <= 0) continue;
    save.bo[k]--;
    if (k === 'wingmen') G.bonus += 5; else G.bo[k] = 3;
  }
  store();
  for (const j of jets) j.active = false;
  for (const p of parts) p.life = 0;
  for (const t of texts) t.life = 0;
  rebuildOcc();
  setMode('game');
  refreshHud(true);
  setTimeout(checkTips, 350);
}

/* ================= Physics ================= */
function fixAngle(j) {
  const sp = Math.hypot(j.vx, j.vy), minVy = sp * 0.14;
  if (Math.abs(j.vy) < minVy) {
    j.vy = (j.vy >= 0 ? 1 : -1) * minVy;
    j.vx = (j.vx >= 0 ? 1 : -1) * Math.sqrt(Math.max(0, sp * sp - j.vy * j.vy));
  }
}
function collide(j, c) {
  const x0 = c.col + GAP, y0 = c.row + GAP, x1 = c.col + c.w - GAP, y1 = c.row + 1 - GAP;
  const qx = clamp(j.x, x0 + CR, x1 - CR), qy = clamp(j.y, y0 + CR, y1 - CR);
  const dx = j.x - qx, dy = j.y - qy, d2 = dx * dx + dy * dy, rad = CR + R;
  if (d2 >= rad * rad) { if (j.skip === c) j.skip = null; return; }
  if (c.type === 'ring') { collectRing(c); return; }
  if (c.type === 'door' && c.open) return;
  if (j.skip === c) return;
  const enemy = isEnemy(c);
  if (!enemy && j.stealth) { j.stealth = false; j.skip = c; spark(j.x, j.y, 0, 0, 0.3, 0.12, '#b9bce0'); return; }
  if (enemy && j.fire) { hitCell(c, j); j.skip = c; return; }
  let nx, ny; const d = Math.sqrt(d2);
  if (d > 1e-6) { nx = dx / d; ny = dy / d; } else {
    const sp = Math.hypot(j.vx, j.vy) || 1; nx = -j.vx / sp; ny = -j.vy / sp;
  }
  j.x = qx + nx * rad; j.y = qy + ny * rad;
  const vn = j.vx * nx + j.vy * ny;
  if (vn < 0) { j.vx -= 2 * vn * nx; j.vy -= 2 * vn * ny; }
  fixAngle(j);
  if (enemy) { hitCell(c, j); if (j.cluster) clusterSplit(j); }
}
function clusterSplit(j) {
  j.cluster = false;
  const sp = Math.hypot(j.vx, j.vy), a = Math.atan2(j.vy, j.vx);
  for (const d of [-0.5, 0.5]) {
    const n = getJet(); if (!n) break;
    Object.assign(n, { x: j.x, y: j.y, vx: Math.cos(a + d) * sp, vy: Math.sin(a + d) * sp, temp: true, fire: j.fire, cluster: false, stealth: false, ret: false, skip: null, age: 0 });
    fixAngle(n);
  }
  burst(j.x, j.y, 6, [PAL.gold, '#fff'], 3);
}
function stepJet(j, dt) {
  j.x += j.vx * dt; j.y += j.vy * dt; j.age += dt;
  if (j.x < R) { j.x = R; if (j.vx < 0) { j.vx = -j.vx; fixAngle(j); } }
  else if (j.x > COLS - R) { j.x = COLS - R; if (j.vx > 0) { j.vx = -j.vx; fixAngle(j); } }
  if (j.y < R) { j.y = R; if (j.vy < 0) { j.vy = -j.vy; fixAngle(j); } }
  if (j.age > 22 && j.vy < 0) j.vy = Math.abs(j.vy); // rescue a jet that never comes home
  if (j.y < DECK + 0.3) {
    const c0 = Math.floor(j.x) - 1, r0 = Math.floor(j.y) - 1;
    stamp++;
    for (let r = r0; r <= r0 + 2; r++) {
      if (r < 0 || r > LAST_ROW) continue;
      for (let c = c0; c <= c0 + 2; c++) {
        if (c < 0 || c >= COLS) continue;
        const cell = occ[r * COLS + c];
        if (!cell || cell.dead || cell.stamp === stamp) continue;
        cell.stamp = stamp; collide(j, cell);
      }
    }
  }
  if (j.vy > 0 && j.y >= LAUNCH_Y) land(j);
}
function land(j) {
  if (j.temp) { j.active = false; return; }
  if (G.firstX === null) G.firstX = clamp(j.x, 0.4, COLS - 0.4);
  j.ret = true; j.y = LAUNCH_Y;
}
function spawnJet() {
  const j = getJet(); if (!j) return;
  let a = G.aim;
  if (G.volleySplit) a += (G.launched % 2 ? -10 : 10);
  a = clamp(a, 10, 170) * Math.PI / 180;
  Object.assign(j, { x: G.launchX, y: LAUNCH_Y, vx: Math.cos(a) * SPEED, vy: -Math.sin(a) * SPEED, temp: false, ret: false, skip: null, age: 0,
    fire: G.bo.fire > 0, cluster: G.bo.cluster > 0, stealth: G.bo.stealth > 0 });
  G.launched++;
  Sound.play('launch');
}
function hitCell(c, j) {
  damage(c, c.type === 'armour' ? 0.5 : 1);
  Sound.play('hit');
  if (j && Math.random() < 0.35) spark(j.x, j.y, (Math.random() - 0.5) * 2, (Math.random() - 0.5) * 2, 0.25, 0.05, '#fff');
}
function damage(c, amt) {
  if (c.dead || !isEnemy(c)) return;
  const real = Math.min(c.hp, amt);
  c.hp -= amt; c.flash = 0.12; G.score += Math.round(real * 10);
  if (c.hp <= 1e-6) destroy(c);
}
function destroy(c) {
  c.dead = true;
  for (let k = 0; k < c.w; k++) { const i = c.row * COLS + c.col + k; if (c.row >= 0 && c.row <= LAST_ROW && occ[i] === c) occ[i] = null; }
  const cx = c.col + c.w / 2, cy = c.row + 0.5, colHex = tierColor(c, G.maxRef);
  const boss = c.type === 'boss';
  burst(cx, cy, boss ? 90 : 20, [colHex, '#ffffff', PAL.ember, PAL.gold], boss ? 7 : 4);
  const pts = boss ? 500 : 50; G.score += pts;
  floatText(cx, cy - 0.2, '+' + (pts + Math.round(c.maxHp * 10)), boss ? PAL.gold : '#fff', boss ? 0.6 : 0.34);
  G.shake = Math.max(G.shake, boss ? 0.9 : 0.16);
  Sound.play(boss ? 'boom' : 'pop'); buzz(boss ? 60 : 8);
  if (c.type === 'crate') { G.medalsEarned++; floatText(cx, cy + 0.25, '+1 medal', PAL.gold, 0.28); Sound.play('coin'); }
  if (c.type === 'storm') G.chain.push({ c, t: 0.09 });
  if (!enemiesLeft() && G.clearT <= 0) G.clearT = 0.7;
}
function stormChain(c) {
  const n = [[c.row - 1, c.col], [c.row + 1, c.col], [c.row, c.col - 1], [c.row, c.col + 1]];
  for (const [r, col] of n) {
    const t = cellAt(r, col);
    if (t && isEnemy(t)) { G.bolts.push({ x1: c.col + 0.5, y1: c.row + 0.5, x2: col + 0.5, y2: r + 0.5, t: 0.35 }); damage(t, 1); }
  }
  Sound.play('zap');
}
function collectRing(c) {
  c.dead = true; rebuildOcc();
  G.bonus++; floatText(c.col + 0.5, c.row + 0.4, '+1 jet', PAL.gold, 0.32);
  burst(c.col + 0.5, c.row + 0.5, 14, [PAL.orange, PAL.gold, '#fff'], 3);
  Sound.play('ring'); buzz(10);
}
function recallAll() {
  for (const j of jets) {
    if (!j.active) continue;
    if (j.temp) { j.active = false; continue; }
    if (!j.ret) { if (G.firstX === null) G.firstX = G.launchX; j.ret = true; j.y = LAUNCH_Y; }
  }
  G.toLaunch = 0;
}

/* ================= Turn flow ================= */
function fire() {
  G.snap = { cells: G.cells.filter((c) => !c.dead).map((c) => Object.assign({}, c, { flash: 0, xA: 0, yA: 0 })),
    score: G.score, launchX: G.launchX, bonus: G.bonus, medalsEarned: G.medalsEarned, bo: Object.assign({}, G.bo), split: G.splitArmed };
  G.volleySplit = G.splitArmed;
  if (G.splitArmed) { save.pu.split--; store(); G.splitArmed = false; }
  G.state = 'firing'; G.toLaunch = G.baseJets + G.bonus; G.launchT = 0; G.launched = 0; G.shotTime = 0; G.firstX = null; G.guide = null;
  refreshHud();
}
function endTurn() {
  G.launchX = G.firstX === null ? G.launchX : G.firstX; G.firstX = null; G.volleySplit = false;
  for (const k of ['fire', 'cluster', 'stealth']) if (G.bo[k] > 0) G.bo[k]--;
  G.turnsLeft--;
  if (!enemiesLeft()) return win();
  if (G.turnsLeft <= 0) return fail('turns');
  const bombers = G.cells.filter((c) => !c.dead && c.type === 'bomber');
  for (const c of G.cells) { if (c.dead) continue; c.row++; c.yA = -1; if (c.type === 'door') c.open = !c.open; }
  for (const b of bombers) {
    const below = cellAt(b.row + 1, b.col);
    if (below && isEnemy(below) && below.type !== 'boss' && !cellAt(below.row + 1, below.col)) {
      below.row++; below.yA = -2; G.bolts.push({ x1: b.col + 0.5, y1: b.row + 0.7, x2: b.col + 0.5, y2: below.row + 0.3, t: 0.3, push: true });
    }
  }
  G.cells = G.cells.filter((c) => !c.dead && !(c.row > LAST_ROW && !isEnemy(c)));
  rebuildOcc();
  G.state = 'shift'; G.shiftT = 0;
  refreshHud();
}
function afterShift() {
  if (G.cells.some((c) => !c.dead && isEnemy(c) && c.row > LAST_ROW)) return fail('deck');
  G.state = 'aim'; refreshHud(); checkTips();
}
function win() {
  G.state = 'done';
  const turnBonus = G.turnsLeft * 100;
  G.score += turnBonus;
  const stars = G.score >= G.stars[2] ? 3 : G.score >= G.stars[1] ? 2 : 1;
  const medals = 4 + stars * 2 + G.medalsEarned;
  const n = G.n;
  save.stars[n] = Math.max(save.stars[n] || 0, stars);
  save.best[n] = Math.max(save.best[n] || 0, G.score);
  save.unlocked = Math.max(save.unlocked, Math.min(LEVELS.length, n + 1));
  save.medals += medals;
  store();
  for (let i = 0; i < 4; i++) setTimeout(() => burst(1 + Math.random() * 5, 2 + Math.random() * 5, 30, [PAL.orange, PAL.gold, '#fff', '#9a7be0'], 6), i * 180);
  setTimeout(() => showComplete(stars, turnBonus, medals), 900);
}
function fail(reason) {
  G.state = 'done';
  Sound.play('fail'); buzz(80);
  setTimeout(() => showFailed(reason), 500);
}
function continueLevel(reason) {
  if (save.medals < PRICE.cont) return toast('Not enough medals');
  save.medals -= PRICE.cont; store();
  if (reason === 'turns') G.turnsLeft += 5;
  else { for (const c of G.cells) { c.row -= 3; c.yA = 3; } G.cells = G.cells.filter((c) => c.row > -12); G.turnsLeft = Math.max(G.turnsLeft, 3); }
  rebuildOcc(); closeSheet(); G.state = 'aim'; refreshHud(true);
}
function undoShot() {
  if (G.state !== 'firing' || !G.snap) return;
  if (save.medals < PRICE.undo) return toast('Not enough medals');
  save.medals -= PRICE.undo;
  if (G.snap.split && G.volleySplit) save.pu.split++;
  store();
  for (const j of jets) j.active = false;
  const s = G.snap;
  G.cells = s.cells.map((c) => Object.assign({}, c)); G.score = s.score; G.launchX = s.launchX; G.bonus = s.bonus;
  G.medalsEarned = s.medalsEarned; G.bo = s.bo; G.splitArmed = s.split; G.volleySplit = false;
  G.toLaunch = 0; G.firstX = null; G.clearT = 0; G.chain = []; G.state = 'aim'; G.snap = null;
  rebuildOcc(); refreshHud(true); toast('Shot undone');
}

/* ================= Power-ups ================= */
function usePU(k) {
  if (!G) return;
  if (G.state === 'target' && k === 'airstrike') { G.state = 'aim'; refreshHud(); return; }
  if (G.state !== 'aim' && G.state !== 'target') return toast('Wait for your squadron to land');
  if (k === 'split' && G.splitArmed) { G.splitArmed = false; refreshHud(); return; }
  if (save.pu[k] <= 0) return offerBuy('pu', k);
  if (G.state === 'target') G.state = 'aim';
  Sound.play('tap');
  if (k === 'airstrike') { G.state = 'target'; }
  else if (k === 'split') { G.splitArmed = true; toast('Next volley flies in a V'); }
  else if (k === 'storm') { save.pu.storm--; thunder(); }
  else if (k === 'wind') { save.pu.wind--; crosswind(); }
  else if (k === 'laser') { if (G.laser) return toast('Laser sight is already on'); save.pu.laser--; G.laser = true; toast('Laser sight on: 3 bounces'); }
  store(); refreshHud();
}
function airstrike(c) {
  const cx = c.col + c.w / 2, cy = c.row + 0.5;
  G.bolts.push({ x1: cx, y1: -1, x2: cx, y2: cy, t: 0.3, strike: true });
  Sound.play('boom'); buzz(30);
  if (c.type === 'boss') damage(c, Math.ceil(c.maxHp * 0.2)); else damage(c, c.hp);
  burst(cx, cy, 30, [PAL.orange, PAL.gold, '#fff'], 6);
  G.shake = Math.max(G.shake, 0.4);
}
function thunder() {
  const rows = [...new Set(G.cells.filter((c) => !c.dead && isEnemy(c) && c.row >= 0 && c.row <= LAST_ROW).map((c) => c.row))];
  if (!rows.length) return;
  const r = rows[Math.floor(Math.random() * rows.length)];
  G.bolts.push({ x1: 0, y1: r + 0.5, x2: COLS, y2: r + 0.5, t: 0.5, big: true });
  for (const c of G.cells.filter((x) => !x.dead && isEnemy(x) && x.row === r)) {
    const amt = c.type === 'boss' ? Math.min(Math.ceil(c.hp * 0.5), Math.ceil(c.maxHp * 0.25)) : Math.ceil(c.hp * 0.5);
    damage(c, amt);
  }
  Sound.play('zap'); buzz(25); G.shake = Math.max(G.shake, 0.3);
}
function crosswind() {
  const rows = {};
  for (const c of G.cells) { if (!c.dead) (rows[c.row] = rows[c.row] || []).push(c); }
  for (const list of Object.values(rows)) {
    const boss = list.find((c) => c.type === 'boss');
    const free = [...Array(COLS).keys()].filter((k) => !boss || k < boss.col || k >= boss.col + 3);
    for (const c of list) {
      if (c.type === 'boss') continue;
      const i = free.indexOf(c.col); if (i < 0) continue;
      const nc = free[(i + 1) % free.length];
      c.xA = nc > c.col ? c.col - nc : -0.9; c.col = nc;
    }
  }
  rebuildOcc(); G.wind = 0.8; Sound.play('wind');
}
function offerBuy(kind, k) {
  const item = (kind === 'pu' ? PU : BO).find((x) => x.k === k), price = PRICE[kind];
  openSheet(`<div class="sb-grab"></div>
    <div class="sb-sh"><div><div class="sb-eyebrow">Out of stock</div><h3>${esc(item.name)}</h3><p>${esc(item.desc)}</p></div></div>
    <div class="sb-meta">You have <b style="display:inline-flex;align-items:center;gap:4px">${MEDAL}${save.medals}</b></div>
    <div class="sb-col"><button class="sb-btn" data-act="buy" data-kind="${kind}" data-k="${k}" ${save.medals < price ? 'disabled' : ''}>Buy 1 &middot; ${MEDAL} ${price}</button>
    <button class="sb-btn ghost" data-act="close">Not now</button></div>`, { pauseGame: true });
}

/* ================= Tooltips ================= */
function checkTips() {
  if (!G || G.state !== 'aim' || sheetOpen) return;
  const want = [];
  if (!save.seen.includes('aim')) want.push('aim');
  const visible = new Set(G.cells.filter((c) => !c.dead && c.row >= 0 && c.row <= LAST_ROW).map((c) => c.type));
  for (const t of TIP_ORDER) if (visible.has(t) && !save.seen.includes(t)) want.push(t);
  if (!want.length) return;
  const t = want[0]; save.seen.push(t); store();
  G.tip = true;
  const tip = h(`<div class="sb-tip" data-act="tipdone"><div class="sb-tipcard">
    <canvas width="168" height="168"></canvas>
    <div class="sb-eyebrow">${t === 'aim' ? 'How to fly' : 'New in the sky'}</div><h3>${esc(INFO[t].name)}</h3><p>${esc(INFO[t].tip)}</p><small>Tap to continue</small></div></div>`);
  el.screens.appendChild(tip);
  drawIcon(tip.querySelector('canvas'), t);
}
function drawIcon(cv, type) {
  const c2 = cv.getContext('2d'), s = cv.width / 1.6;
  c2.clearRect(0, 0, cv.width, cv.height);
  if (type === 'aim') {
    c2.fillStyle = PAL.orange;
    for (let i = 0; i < 6; i++) { c2.globalAlpha = 1 - i * 0.14; c2.beginPath(); c2.arc(cv.width * 0.3 + i * cv.width * 0.09, cv.height * 0.78 - i * cv.height * 0.11, cv.width * 0.025, 0, 7); c2.fill(); }
    c2.globalAlpha = 1; drawJet(c2, cv.width * 0.24, cv.height * 0.82, -Math.PI / 4, cv.width * 0.34, PAL.navy);
    return;
  }
  const w = type === 'boss' ? 3 : 1;
  const cell = { type, col: 0, row: 0, w, hp: type === 'boss' ? 300 : 12, maxHp: type === 'boss' ? 300 : 12, open: false, openA: 0, flash: 0 };
  const cs = type === 'boss' ? cv.width / 3.2 : s;
  const x = (cv.width - cs * w) / 2, y = (cv.height - cs) / 2;
  drawCell(c2, cell, x + cs * GAP, y + cs * GAP, cs * w - cs * GAP * 2, cs - cs * GAP * 2, cs, type === 'crate' || type === 'armour' ? 14 : 30, 0);
}

/* ================= Input ================= */
function toField(e) {
  const r = canvas.getBoundingClientRect();
  return { x: (e.clientX - r.left - OX) / S, y: (e.clientY - r.top - OY) / S };
}
function aimAt(p) {
  if (p.y > DECK - 0.15) { G.aimOk = false; G.guide = null; return; }
  let a = Math.atan2(LAUNCH_Y - p.y, p.x - G.launchX) * 180 / Math.PI;
  if (a < 0) a = a < -90 ? 180 : 0;
  G.aim = clamp(a, 10, 170); G.aimOk = true;
  G.guide = trace(G.aim, G.laser ? 3 : 1);
}
function onDown(e) {
  if (mode !== 'game' || !G || G.paused || G.tip || sheetOpen) return;
  const p = toField(e);
  if (G.state === 'target') {
    const c = (p.y >= 0 && p.y < LAST_ROW + 1) ? occ[Math.floor(p.y) * COLS + clamp(Math.floor(p.x), 0, COLS - 1)] : null;
    if (c && isEnemy(c)) { save.pu.airstrike--; store(); airstrike(c); G.state = 'aim'; refreshHud(); }
    else toast('Tap an enemy to strike it');
    return;
  }
  if (G.state !== 'aim') return;
  G.aiming = true;
  try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
  aimAt(p);
}
function onMove(e) { if (G && G.aiming) aimAt(toField(e)); }
function onUp(e) {
  if (!G || !G.aiming) return;
  G.aiming = false;
  if (e.type === 'pointerup' && G.aimOk && G.state === 'aim') fire();
  G.guide = null;
}
function trace(angle, maxB) {
  const pts = [];
  let x = G.launchX, y = LAUNCH_Y, b = 0, dist = 0, next = 0.32;
  const a = angle * Math.PI / 180; let dx = Math.cos(a), dy = -Math.sin(a);
  const st = 0.04;
  for (let i = 0; i < 1500; i++) {
    x += dx * st; y += dy * st; dist += st;
    let hit = false;
    if (x < R) { x = R; dx = Math.abs(dx); hit = true; } else if (x > COLS - R) { x = COLS - R; dx = -Math.abs(dx); hit = true; }
    if (y < R) { y = R; dy = Math.abs(dy); hit = true; }
    if (!hit && y < DECK) {
      const c0 = Math.floor(x) - 1, r0 = Math.floor(y) - 1;
      outer: for (let r = r0; r <= r0 + 2; r++) {
        if (r < 0 || r > LAST_ROW) continue;
        for (let cc = c0; cc <= c0 + 2; cc++) {
          if (cc < 0 || cc >= COLS) continue;
          const c = occ[r * COLS + cc];
          if (!c || c.dead || c.type === 'ring' || (c.type === 'door' && c.open)) continue;
          const x0 = c.col + GAP, y0 = c.row + GAP, x1 = c.col + c.w - GAP, y1 = c.row + 1 - GAP;
          const qx = clamp(x, x0 + CR, x1 - CR), qy = clamp(y, y0 + CR, y1 - CR);
          const ddx = x - qx, ddy = y - qy, d = Math.hypot(ddx, ddy);
          if (d < CR + R) {
            const nx = d > 1e-6 ? ddx / d : -dx, ny = d > 1e-6 ? ddy / d : -dy;
            x = qx + nx * (CR + R); y = qy + ny * (CR + R);
            const vn = dx * nx + dy * ny; if (vn < 0) { dx -= 2 * vn * nx; dy -= 2 * vn * ny; }
            hit = true; break outer;
          }
        }
      }
    }
    if (dist >= next) { pts.push(x, y); next += 0.32; }
    if (hit) { b++; if (b >= maxB) break; }
    if (y >= LAUNCH_Y && dy > 0) break;
  }
  return { pts, ex: x, ey: y };
}

/* ================= Update ================= */
function update(dt) {
  time += dt;
  for (const p of parts) if (p.life > 0) { p.life -= dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 9 * dt; p.vx *= 0.98; }
  for (const t of texts) if (t.life > 0) { t.life -= dt; t.y -= dt * 0.9; }
  if (mode !== 'game' || !G) return;
  for (const c of G.cells) {
    if (c.flash > 0) c.flash -= dt;
    if (c.xA) { c.xA += (0 - c.xA) * Math.min(1, dt * 12); if (Math.abs(c.xA) < 0.005) c.xA = 0; }
    if (c.yA) { c.yA += (0 - c.yA) * Math.min(1, dt * 11); if (Math.abs(c.yA) < 0.005) c.yA = 0; }
    if (c.type === 'door') { const t = c.open ? 1 : 0; c.openA += (t - c.openA) * Math.min(1, dt * 9); }
  }
  for (const b of G.bolts) b.t -= dt;
  G.bolts = G.bolts.filter((b) => b.t > 0);
  if (G.shake > 0) G.shake = Math.max(0, G.shake - dt * 2.5);
  if (G.wind > 0) G.wind -= dt;
  if (G.paused || G.tip) return;
  if (G.chain.length) {
    for (const ch of G.chain) ch.t -= dt;
    const due = G.chain.filter((ch) => ch.t <= 0); G.chain = G.chain.filter((ch) => ch.t > 0);
    due.forEach((ch) => stormChain(ch.c));
  }
  if (G.clearT > 0) {
    G.clearT -= dt;
    if (G.clearT <= 0) {
      if (G.state === 'firing') G.turnsLeft--; // the shot that cleared the sky uses a turn
      recallAll(); win(); return;
    }
  }
  if (G.state === 'firing') {
    const f = G.shotTime > 8 ? 1 + Math.min(1.6, (G.shotTime - 8) / 4) : 1;
    G.shotTime += dt;
    const edt = dt * f;
    if (G.toLaunch > 0) {
      G.launchT -= edt;
      while (G.toLaunch > 0 && G.launchT <= 0) { spawnJet(); G.toLaunch--; G.launchT += 0.05; }
    }
    const steps = Math.max(1, Math.ceil(SPEED * edt / STEP)), sdt = edt / steps;
    for (let s = 0; s < steps; s++) {
      for (let i = 0; i < JMAX; i++) { const j = jets[i]; if (j.active && !j.ret) stepJet(j, sdt); }
    }
    let flying = 0;
    for (const j of jets) {
      if (!j.active) continue;
      if (j.ret) {
        const tx = G.firstX === null ? G.launchX : G.firstX, d = tx - j.x;
        j.x += Math.sign(d) * Math.min(Math.abs(d), edt * 16);
        if (Math.abs(d) < 0.05) j.active = false;
      } else {
        flying++;
        if (j.fire && Math.random() < 0.3) spark(j.x, j.y, (Math.random() - 0.5), (Math.random() - 0.5), 0.25, 0.07, Math.random() < 0.5 ? PAL.orange : PAL.gold);
      }
    }
    if (G.toLaunch === 0 && flying === 0 && G.clearT <= 0) {
      for (const j of jets) j.active = false;
      endTurn();
    }
  } else {
    for (const j of jets) {
      if (!j.active) continue;
      const d = G.launchX - j.x; j.x += Math.sign(d) * Math.min(Math.abs(d), dt * 16);
      if (Math.abs(d) < 0.05) j.active = false;
    }
  }
  if (G.state === 'shift') { G.shiftT += dt; if (G.shiftT >= 0.32) afterShift(); }
}

/* ================= Render ================= */
const X = (x) => OX + x * S, Y = (y) => OY + y * S;
function render(dt) {
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  drawSky(dt);
  if (mode === 'game' && G) drawGame();
  else drawAttract();
}
function drawAttract() {
  const n = 7;
  for (let k = 0; k < 2; k++) {
    const t = ((time * 0.09 + k * 0.5) % 1.3) - 0.15;
    for (let i = 0; i < n; i++) {
      const off = Math.abs(i - 3);
      const x = t * (W + 200) - 100 - off * 18, y = H * (0.62 + k * 0.12) - t * H * 0.35 + off * 14 - (k ? 0 : 0);
      ctx.strokeStyle = 'rgba(255,255,255,.12)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - 70, y + 70 * 0.35 * H / (W + 200)); ctx.stroke();
      drawJet(ctx, x, y, -Math.atan2(H * 0.35, W + 200), 26, i === 3 ? PAL.orange : 'rgba(185,188,224,.55)');
    }
  }
}
function drawGame() {
  const sx = G.shake > 0 ? (Math.random() - 0.5) * G.shake * S * 0.35 : 0, sy = G.shake > 0 ? (Math.random() - 0.5) * G.shake * S * 0.35 : 0;
  ctx.save(); ctx.translate(sx, sy);
  // field panel
  ctx.fillStyle = 'rgba(255,255,255,.035)'; rr(ctx, X(0) - 5, Y(0) - 5, S * COLS + 10, S * DECK + 10, 16); ctx.fill();
  ctx.fillStyle = 'rgba(255,255,255,.06)';
  for (let r = 1; r < DECK; r++) for (let c = 1; c < COLS; c++) ctx.fillRect(X(c) - 1, Y(r) - 1, 2, 2);
  // wind streaks
  if (G.wind > 0) {
    ctx.strokeStyle = `rgba(255,255,255,${0.25 * G.wind})`; ctx.lineWidth = 2;
    for (let i = 0; i < 10; i++) { const y = Y((i * 1.13) % DECK), x = X(((time * 9 + i * 1.7) % (COLS + 2)) - 1); ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + S * 0.9, y); ctx.stroke(); }
  }
  drawDeck();
  // cells (clipped to the field so new rows slide in from the top edge)
  ctx.save(); ctx.beginPath(); ctx.rect(X(0) - 8, Y(0) - 2, S * COLS + 16, S * DECK + 2); ctx.clip();
  const g = GAP * S;
  for (const c of G.cells) {
    if (c.dead) continue;
    const ry = c.row + c.yA; if (ry < -1.05 || ry > DECK + 0.5) continue;
    drawCell(ctx, c, X(c.col + c.xA) + g, Y(ry) + g, c.w * S - 2 * g, S - 2 * g, S, G.maxRef, time);
    if (c.type === 'boss') {
      const bw = c.w * S - 2 * g, bx = X(c.col + c.xA) + g, by = Y(ry) - S * 0.02;
      ctx.fillStyle = 'rgba(2,2,47,.8)'; rr(ctx, bx, by - S * 0.12, bw, S * 0.12, S * 0.06); ctx.fill();
      ctx.fillStyle = PAL.gold; rr(ctx, bx + 2, by - S * 0.12 + 2, Math.max(0, (bw - 4) * c.hp / c.maxHp), S * 0.12 - 4, S * 0.05); ctx.fill();
    }
  }
  ctx.restore();
  // aim guide
  if (G.guide && G.state === 'aim') {
    const p = G.guide.pts;
    for (let i = 0; i < p.length; i += 2) {
      ctx.globalAlpha = Math.max(0.2, 1 - i / (p.length + 6));
      ctx.fillStyle = i % 4 ? '#fff' : PAL.ember;
      ctx.beginPath(); ctx.arc(X(p[i]), Y(p[i + 1]), S * 0.05, 0, 7); ctx.fill();
    }
    ctx.globalAlpha = 0.85; ctx.strokeStyle = '#fff'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(X(G.guide.ex), Y(G.guide.ey), R * S * 1.2, 0, 7); ctx.stroke(); ctx.globalAlpha = 1;
  }
  // contrails
  const skin = (SKINS.find((s) => s.id === save.skin) || SKINS[0]).color;
  ctx.lineCap = 'round';
  ctx.strokeStyle = 'rgba(255,255,255,.22)'; ctx.lineWidth = S * 0.05; ctx.beginPath();
  for (const j of jets) {
    if (!j.active || j.ret) continue;
    const sp = Math.hypot(j.vx, j.vy) || 1;
    ctx.moveTo(X(j.x - j.vx / sp * 0.55), Y(j.y - j.vy / sp * 0.55)); ctx.lineTo(X(j.x), Y(j.y));
  }
  ctx.stroke();
  for (const j of jets) {
    if (!j.active) continue;
    const ang = j.ret ? (j.x < (G.firstX ?? G.launchX) ? 0 : Math.PI) : Math.atan2(j.vy, j.vx);
    drawJet(ctx, X(j.x), Y(j.y), ang, S * 0.42, j.temp ? PAL.gold : j.fire ? PAL.ember : skin);
  }
  // bolts
  for (const b of G.bolts) {
    ctx.globalAlpha = Math.min(1, b.t * 4);
    ctx.strokeStyle = b.push ? PAL.red : b.strike ? '#fff' : PAL.gold; ctx.lineWidth = b.big ? S * 0.09 : S * 0.05;
    ctx.beginPath(); ctx.moveTo(X(b.x1), Y(b.y1));
    const segs = b.strike ? 1 : 6;
    for (let i = 1; i <= segs; i++) {
      const t = i / segs, jx = i < segs ? (Math.random() - 0.5) * 0.25 : 0, jy = i < segs ? (Math.random() - 0.5) * 0.25 : 0;
      ctx.lineTo(X(b.x1 + (b.x2 - b.x1) * t + jx), Y(b.y1 + (b.y2 - b.y1) * t + jy));
    }
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  // particles
  for (const p of parts) {
    if (p.life <= 0) continue;
    ctx.globalAlpha = Math.min(1, p.life / p.max * 1.5); ctx.fillStyle = p.color;
    const s = p.size * S; ctx.fillRect(X(p.x) - s / 2, Y(p.y) - s / 2, s, s);
  }
  ctx.globalAlpha = 1;
  // floating score
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  for (const t of texts) {
    if (t.life <= 0) continue;
    ctx.globalAlpha = Math.min(1, t.life / t.max * 2);
    ctx.font = `italic 800 ${Math.round(S * t.size)}px ${FONT}`;
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(2,2,47,.8)'; ctx.strokeText(t.text, X(t.x), Y(t.y)); ctx.fillStyle = t.color; ctx.fillText(t.text, X(t.x), Y(t.y));
  }
  ctx.globalAlpha = 1;
  // target mode hint
  if (G.state === 'target') {
    ctx.fillStyle = 'rgba(255,76,0,.08)'; ctx.fillRect(X(0), Y(0), S * COLS, S * DECK);
  }
  ctx.restore();
}
function drawDeck() {
  const y0 = Y(DECK), y1 = Y(FIELD_H);
  const g = ctx.createLinearGradient(0, y0, 0, y1); g.addColorStop(0, '#141a72'); g.addColorStop(1, '#05063a');
  ctx.fillStyle = g; rr(ctx, X(0) - 5, y0, S * COLS + 10, y1 - y0 + 4, 12); ctx.fill();
  const danger = G.cells.some((c) => !c.dead && isEnemy(c) && c.row >= LAST_ROW);
  ctx.fillStyle = danger ? `rgba(255,90,79,${0.5 + 0.5 * Math.abs(Math.sin(time * 6))})` : PAL.orange;
  ctx.fillRect(X(0), y0 - 1.5, S * COLS, 3);
  ctx.strokeStyle = 'rgba(255,255,255,.16)'; ctx.lineWidth = 2; ctx.setLineDash([S * 0.22, S * 0.18]);
  ctx.beginPath(); ctx.moveTo(X(0.2), Y(LAUNCH_Y)); ctx.lineTo(X(COLS - 0.2), Y(LAUNCH_Y)); ctx.stroke(); ctx.setLineDash([]);
  const lx = G.launchX;
  ctx.fillStyle = 'rgba(255,255,255,.12)'; rr(ctx, X(lx) - S * 0.42, Y(LAUNCH_Y) - S * 0.07, S * 0.84, S * 0.14, S * 0.07); ctx.fill();
  const skin = (SKINS.find((s) => s.id === save.skin) || SKINS[0]).color;
  if (G.state !== 'firing') {
    const a = G.aiming && G.aimOk ? -G.aim * Math.PI / 180 : -Math.PI / 2;
    drawJet(ctx, X(lx), Y(LAUNCH_Y), a, S * 0.62, skin);
  }
  const label = G.state === 'firing' ? (G.toLaunch > 0 ? `${G.toLaunch}` : '') : `${G.baseJets}+${G.bonus}`;
  if (label) {
    ctx.font = `italic 800 ${Math.round(S * 0.3)}px ${FONT}`; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    const tw = ctx.measureText(label).width, iw = S * 0.32, total = iw + 4 + tw;
    const cx = clamp(X(lx) - total / 2, X(0.05), X(COLS - 0.05) - total), cy = Y(LAUNCH_Y + 0.45);
    drawJet(ctx, cx + iw / 2, cy, -Math.PI / 2, iw, PAL.ember);
    ctx.fillStyle = '#fff'; ctx.fillText(label, cx + iw + 4, cy + 1);
  }
  if (G.state === 'aim' && !G.aiming && G.n <= 2) {
    ctx.globalAlpha = 0.5 + 0.4 * Math.sin(time * 3);
    ctx.font = `600 ${Math.round(S * 0.28)}px "Barlow", system-ui, sans-serif`; ctx.textAlign = 'center'; ctx.fillStyle = '#fff';
    ctx.fillText('Drag up to aim, let go to launch', X(COLS / 2), Y(DECK - 0.45)); ctx.globalAlpha = 1;
  }
}

/* ================= HUD ================= */
let lastHud = {};
function refreshHud(force) {
  if (!G) return;
  el.lvl.textContent = `Level ${G.n} · ${G.def.name}`;
  el.turns.textContent = `${G.turnsLeft} turn${G.turnsLeft === 1 ? '' : 's'}`;
  el.turns.classList.toggle('low', G.turnsLeft <= 3);
  const firing = G.state === 'firing';
  el.tray.hidden = firing; el.shot.hidden = !firing;
  el.tray.querySelectorAll('.sb-pu').forEach((b) => {
    const k = b.dataset.k, n = save.pu[k];
    const badge = b.querySelector('b'); badge.textContent = n > 0 ? 'x' + n : '+'; badge.classList.toggle('zero', n <= 0);
    const on = (k === 'airstrike' && G.state === 'target') || (k === 'split' && G.splitArmed) || (k === 'laser' && G.laser);
    b.classList.toggle('on', on); b.classList.toggle('dim', G.state !== 'aim' && G.state !== 'target');
  });
  const bar = el.bar, stars = bar.querySelectorAll('.sb-star');
  [60, 80, 100].forEach((v, i) => { stars[i].style.left = v + '%'; });
  const banner = el.screens.querySelector('.sb-banner');
  if (G.state === 'target' && !banner) el.screens.appendChild(h('<div class="sb-banner">Airstrike: tap an enemy</div>'));
  if (G.state !== 'target' && banner) banner.remove();
  if (force) { G.shown = G.score; lastHud = {}; }
}
function hudTick() {
  if (mode !== 'game' || !G) return;
  if (G.shown !== G.score) G.shown += Math.ceil((G.score - G.shown) * 0.25) || (G.score > G.shown ? 1 : -1);
  if (Math.abs(G.shown - G.score) < 2) G.shown = G.score;
  if (lastHud.s !== G.shown) { el.score.textContent = G.shown.toLocaleString('en-GB'); lastHud.s = G.shown; }
  const [s1, s2, s3] = G.stars, v = G.shown;
  const pct = v <= s1 ? v / s1 * 60 : v <= s2 ? 60 + (v - s1) / (s2 - s1) * 20 : Math.min(100, 80 + (v - s2) / (s3 - s2) * 20);
  if (lastHud.p !== Math.round(pct)) {
    lastHud.p = Math.round(pct);
    el.bar.querySelector('i').style.width = pct + '%';
    el.bar.querySelectorAll('.sb-star').forEach((s, i) => {
      const on = G.shown >= G.stars[i];
      if (on && !s.classList.contains('on')) Sound.play('star');
      s.classList.toggle('on', on);
    });
  }
}

/* ================= Screens & sheets ================= */
let sheetOpen = false, sheetOpts = {};
function setMode(m) {
  mode = m;
  hud.hidden = m !== 'game';
  el.screens.innerHTML = '';
  closeSheet(true);
  requestAnimationFrame(layout);
}
function totalStars() { return Object.values(save.stars).reduce((a, b) => a + b, 0); }
function cleared() { return Object.keys(save.stars).length; }
function showTitle() {
  setMode('title'); G = null;
  el.screens.innerHTML = `<div class="sb-screen sb-title">
    <div><img class="logo" src="assets/logo-dark.png" alt="SmartMotion"><h1 class="sb-name">Sky<span>Barrage</span></h1>
      <p class="sb-tag">Launch your squadron off the carrier deck and clear the skies.</p></div>
    <div><div class="sb-stats"><div><b>${cleared()}/${LEVELS.length}</b><span>Levels cleared</span></div>
      <div><b>${STAR('on').replace('sb-star on', 'sb-star on" style="width:20px;height:20px;fill:#ffc23d')}${totalStars()}</b><span>Stars</span></div>
      <div><b>${MEDAL}${save.medals}</b><span>Medals</span></div></div>
    <div class="sb-col"><button class="sb-btn big" data-act="map">Play</button>
      <div class="sb-row"><button class="sb-btn sec" data-act="skins">${ICONS.skins}Jets</button><button class="sb-btn sec" data-act="help">${ICONS.help}How to</button></div>
      <button class="sb-btn ghost" data-act="exit">${ICONS.back}Back to dashboard</button></div></div>
  </div>`;
}
function showMap() {
  setMode('map'); G = null;
  let nodes = '';
  for (let n = LEVELS.length; n >= 1; n--) {
    const locked = n > save.unlocked, st = save.stars[n] || 0, cur = n === save.unlocked && !st;
    const off = [0, 70, 0, -70][n % 4];
    nodes += `<button class="sb-node ${locked ? 'locked' : st ? 'done' : ''} ${cur ? 'current' : ''} ${n % 10 === 0 ? 'boss' : ''}" style="transform:translateX(${off}px)" data-act="preview" data-n="${n}" aria-label="Level ${n}${locked ? ', locked' : ''}">
      ${locked ? ICONS.lock : n}${!locked ? `<span class="sb-nstars">${[1, 2, 3].map((i) => STAR(i <= st ? 'on' : '')).join('')}</span>` : ''}</button>`;
    if (n > 1) nodes += `<div class="sb-dots" style="transform:translateX(${([0, 70, 0, -70][n % 4] + [0, 70, 0, -70][(n - 1) % 4]) / 2}px)"></div>`;
  }
  el.screens.innerHTML = `<div class="sb-screen">
    <div class="sb-head"><button class="sb-ib" data-act="title" aria-label="Back">${ICONS.back}</button><h2>Levels</h2><span class="sb-pill">${MEDAL}${save.medals}</span></div>
    <div class="sb-mapscroll"><div class="sb-path">${nodes}</div></div></div>`;
  const cur = el.screens.querySelector('.sb-node.current') || el.screens.querySelector(`.sb-node[data-n="${save.unlocked}"]`);
  if (cur) setTimeout(() => cur.scrollIntoView({ block: 'center' }), 30);
}
let picks = new Set();
function openPreview(n) {
  if (n > save.unlocked) { toast('Clear the level before it to unlock this one'); return; }
  picks = new Set();
  const def = LEVELS[n - 1], st = save.stars[n] || 0;
  openSheet(`<div class="sb-grab"></div>
    <div class="sb-sh"><div><div class="sb-eyebrow">Level ${n}${n % 10 === 0 ? ' · Boss' : ''}</div><h3>${esc(def.name)}</h3></div>
      <button class="sb-ib" data-act="close" aria-label="Close">${ICONS.close}</button></div>
    <canvas class="sb-mini" id="sb-mini"></canvas>
    <div class="sb-meta"><span><b>${def.turns}</b> turns</span><span><b>${def.jets}</b> jets</span><span style="display:flex;gap:1px">${[1, 2, 3].map((i) => STAR(i <= st ? 'on' : '').replace('class="sb-star', 'style="width:18px;height:18px;fill:' + (i <= st ? '#ffc23d' : '#2a2f72') + '" class="sb-star')).join('')}</span></div>
    <div class="sb-eyebrow" style="text-align:center">Boosters</div>
    <div class="sb-boost">${BO.map((b) => `<button class="sb-bslot" data-act="booster" data-k="${b.k}" aria-label="${b.name}">${ICONS[b.k]}<b class="${save.bo[b.k] ? '' : 'zero'}">${save.bo[b.k] ? 'x' + save.bo[b.k] : '+'}</b></button>`).join('')}</div>
    <div class="sb-bdesc" id="sb-bdesc">Tap a booster to take it into the level.</div>
    <button class="sb-btn big" data-act="play" data-n="${n}">Play</button>`, {});
  const cv = root.querySelector('#sb-mini'); drawMini(cv, n);
}
function drawMini(cv, n) {
  const cells = parseLevel(n), rows = LEVELS[n - 1].rows.length;
  const minRow = Math.min(...cells.map((c) => c.row));
  const wcss = cv.clientWidth || 300, cs = wcss / COLS, hcss = cs * (rows + 0.4);
  const r2 = Math.min(2, window.devicePixelRatio || 1);
  cv.width = wcss * r2; cv.height = hcss * r2; cv.style.height = hcss + 'px';
  const c2 = cv.getContext('2d'); c2.setTransform(r2, 0, 0, r2, 0, 0);
  const ref = maxRefOf(cells), g = cs * GAP;
  for (const c of cells) drawCell(c2, c, c.col * cs + g, (c.row - minRow + 0.2) * cs + g, c.w * cs - 2 * g, cs - 2 * g, cs, ref, 0);
}
function showComplete(stars, turnBonus, medals) {
  const n = G.n, last = n >= LEVELS.length;
  openSheet(`<div class="sb-bigstars">${[1, 2, 3].map((i) => STAR(i <= stars ? 'on' : '').replace('<svg', `<svg style="animation-delay:${0.15 + i * 0.25}s"`)).join('')}</div>
    <div class="sb-eyebrow">Level ${n} cleared</div><h3>${esc(G.def.name)}</h3>
    <div class="sb-big" id="sb-countup">0</div>
    <div class="sb-earn"><span class="sb-pill">${MEDAL}+${medals}</span>${turnBonus ? `<span class="sb-pill">Turns left +${turnBonus}</span>` : ''}</div>
    <div class="sb-col">${last ? '<p>You’ve cleared every level. Go back for 3 stars!</p>' : `<button class="sb-btn big" data-act="next">Next level</button>`}
      <div class="sb-row"><button class="sb-btn sec" data-act="retry">Replay</button><button class="sb-btn sec" data-act="map">Levels</button></div></div>`, { center: true });
  for (let i = 1; i <= stars; i++) setTimeout(() => { Sound.play('star'); buzz(15); }, (0.15 + i * 0.25) * 1000 + 200);
  const target = G.score, t0 = performance.now(), out = root.querySelector('#sb-countup');
  const tick = (now) => { const p = Math.min(1, (now - t0) / 900); out.textContent = Math.round(target * (1 - Math.pow(1 - p, 3))).toLocaleString('en-GB'); if (p < 1 && sheetOpen) requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
}
function showFailed(reason) {
  const deck = reason === 'deck';
  openSheet(`<div class="sb-eyebrow">Level ${G.n}</div><h3>${deck ? 'They reached the deck!' : 'Out of turns'}</h3>
    <p>${deck ? 'An enemy got all the way down to your carrier.' : 'The sky isn’t clear yet.'}</p>
    <div class="sb-col" style="margin-top:16px">
      <button class="sb-btn big" data-act="continue" data-r="${reason}" ${save.medals < PRICE.cont ? 'disabled' : ''}>${deck ? 'Push back' : '+5 turns'} &middot; ${MEDAL} ${PRICE.cont}</button>
      <button class="sb-btn sec" data-act="retry">Retry</button>
      <button class="sb-btn ghost" data-act="map">Levels</button></div>
    <div class="sb-sm">You have ${save.medals} medals</div>`, { center: true });
}
function openPause() {
  if (!G || G.state === 'done') return;
  openSheet(`<div class="sb-grab"></div>
    <div class="sb-sh"><div><div class="sb-eyebrow">Paused</div><h3>Level ${G.n}</h3></div><span class="sb-pill">${MEDAL}${save.medals}</span></div>
    <div class="sb-col"><button class="sb-btn big" data-act="close">Resume</button>
    <div class="sb-row"><button class="sb-btn sec" data-act="retry">Restart</button><button class="sb-btn sec" data-act="map">Levels</button></div>
    <button class="sb-btn sec" data-act="sound">${save.sound ? ICONS.sound + 'Sound on' : ICONS.mute + 'Sound off'}</button>
    <button class="sb-btn ghost" data-act="exit">${ICONS.back}Back to dashboard</button></div>`, { pauseGame: true });
}
function openHelp() {
  const types = ['blimp', 'crate', 'storm', 'armour', 'bomber', 'tower', 'door', 'ring', 'boss'];
  openSheet(`<div class="sb-grab"></div>
    <div class="sb-sh"><div><div class="sb-eyebrow">How to play</div><h3>Sky Barrage</h3></div><button class="sb-ib" data-act="close" aria-label="Close">${ICONS.close}</button></div>
    <p>Drag anywhere to aim, let go to launch. Every hit takes 1 off an enemy. After each turn the sky moves down a row: don’t let anything reach your deck, and clear it before your turns run out.</p>
    <p>The first jet to land sets where you launch from next. <b>Recall</b> brings everyone home for free; <b>Undo</b> takes back the shot for ${PRICE.undo} medals.</p>
    <div class="sb-list">${types.map((t) => `<div class="sb-li"><canvas width="96" height="96" data-type="${t}"></canvas><div><b>${esc(INFO[t].name)}</b><span>${esc(INFO[t].tip)}</span></div></div>`).join('')}
    ${PU.map((p) => `<div class="sb-li"><div style="width:48px;height:48px;display:grid;place-items:center;border-radius:14px;background:rgba(255,76,0,.2)">${ICONS[p.k].replace('<svg', '<svg width="26" height="26"')}</div><div><b>${esc(p.name)}</b><span>${esc(p.desc)}</span></div></div>`).join('')}</div>`, { pauseGame: true });
  root.querySelectorAll('.sb-li canvas').forEach((cv) => drawIcon(cv, cv.dataset.type));
}
function openSkins() {
  openSheet(`<div class="sb-grab"></div>
    <div class="sb-sh"><div><div class="sb-eyebrow">Hangar</div><h3>Jet colours</h3></div><span class="sb-pill">${MEDAL}${save.medals}</span></div>
    <div class="sb-skins">${SKINS.map((s) => {
      const own = save.owned.includes(s.id), eq = save.skin === s.id;
      return `<button class="sb-skin ${eq ? 'eq' : ''}" data-act="skin" data-id="${s.id}">${jetSvg(s.color)}<b>${esc(s.name)}</b><span>${eq ? 'Flying' : own ? 'Tap to fly' : MEDAL + s.cost}</span></button>`;
    }).join('')}</div>
    <button class="sb-btn sec" data-act="close" style="margin-top:10px">Done</button>`, { pauseGame: true });
}
function openSheet(html, opts) {
  closeSheet(true);
  sheetOpts = opts || {};
  if (sheetOpts.pauseGame && G) G.paused = true;
  const wrap = h(`<div class="sb-wrap ${sheetOpts.center ? 'center' : ''}" data-act="${sheetOpts.center ? '' : 'backdrop'}"><div class="sb-sheet" role="dialog">${html}</div></div>`);
  el.screens.appendChild(wrap); sheetOpen = true;
  requestAnimationFrame(() => wrap.classList.add('on'));
}
function closeSheet(instant) {
  const wrap = el.screens && el.screens.querySelector('.sb-wrap');
  if (G && sheetOpts.pauseGame) G.paused = false;
  sheetOpen = false; sheetOpts = {};
  if (!wrap) return;
  if (instant) { wrap.remove(); return; }
  wrap.classList.remove('on'); setTimeout(() => wrap.remove(), 300);
  if (G && G.state === 'aim') setTimeout(checkTips, 320);
}
let toastT = 0;
function toast(msg) {
  el.toast.textContent = msg; el.toast.classList.add('on');
  clearTimeout(toastT); toastT = setTimeout(() => el.toast.classList.remove('on'), 1600);
}

/* ================= Clicks ================= */
function onClick(e) {
  const t = e.target.closest('[data-act]'); if (!t) return;
  const act = t.dataset.act;
  if (!act || (act === 'backdrop' && e.target !== t)) return;
  if (act !== 'tipdone') Sound.play('tap');
  switch (act) {
    case 'title': showTitle(); break;
    case 'map': closeSheet(true); showMap(); break;
    case 'exit': close(); break;
    case 'preview': openPreview(+t.dataset.n); break;
    case 'booster': {
      const k = t.dataset.k, b = BO.find((x) => x.k === k);
      if (save.bo[k] <= 0) { buyItem('bo', k, () => { openPreview(+root.querySelector('[data-act="play"]').dataset.n); }); return; }
      if (picks.has(k)) picks.delete(k); else picks.add(k);
      t.classList.toggle('sel', picks.has(k));
      root.querySelector('#sb-bdesc').innerHTML = `<b>${esc(b.name)}</b>: ${esc(b.desc)}`;
      break;
    }
    case 'play': { const n = +t.dataset.n; closeSheet(true); startLevel(n, [...picks]); break; }
    case 'close': case 'backdrop': closeSheet(); break;
    case 'pause': openPause(); break;
    case 'help': openHelp(); break;
    case 'skins': openSkins(); break;
    case 'skin': {
      const s = SKINS.find((x) => x.id === t.dataset.id);
      if (!save.owned.includes(s.id)) {
        if (save.medals < s.cost) { toast('Not enough medals'); return; }
        save.medals -= s.cost; save.owned.push(s.id); Sound.play('coin');
      }
      save.skin = s.id; store(); openSkins(); break;
    }
    case 'sound': save.sound = !save.sound; store(); Sound.init(); openPause(); break;
    case 'pu': usePU(t.dataset.k); break;
    case 'buy': buyItem(t.dataset.kind, t.dataset.k); break;
    case 'recall': if (G && G.state === 'firing') { recallAll(); buzz(10); } break;
    case 'undo': undoShot(); break;
    case 'retry': { const n = G.n; closeSheet(true); startLevel(n, []); break; }
    case 'next': { const n = Math.min(LEVELS.length, G.n + 1); closeSheet(true); showMap(); setTimeout(() => openPreview(n), 250); break; }
    case 'continue': continueLevel(t.dataset.r); break;
    case 'tipdone': t.remove(); if (G) { G.tip = false; setTimeout(checkTips, 200); } break;
  }
}
function buyItem(kind, k, after) {
  const price = PRICE[kind];
  if (save.medals < price) { toast('Not enough medals'); return; }
  save.medals -= price; save[kind][k]++; store(); Sound.play('coin');
  toast('Bought 1. ' + save.medals + ' medals left');
  if (after) after(); else { closeSheet(); refreshHud(); }
}

/* ================= Loop ================= */
function frame(ts) {
  if (!running) return;
  const dt = Math.min(1 / 30, Math.max(0, (ts - (lastTs || ts)) / 1000)); lastTs = ts;
  update(dt); render(dt); hudTick();
  raf = requestAnimationFrame(frame);
}

/* ================= Public API ================= */
function open(opts) {
  build();
  onCloseCb = opts && opts.onClose;
  save = loadSave();
  root.hidden = false; running = true; lastTs = 0;
  document.documentElement.style.overflow = 'hidden';
  layout();
  if (document.fonts && document.fonts.load) document.fonts.load(`italic 800 20px ${FONT}`).catch(() => {});
  if (opts && opts.level) startLevel(opts.level, []); else showTitle();
  cancelAnimationFrame(raf); raf = requestAnimationFrame(frame);
}
function close() {
  if (!built) return;
  running = false; cancelAnimationFrame(raf);
  root.hidden = true; document.documentElement.style.overflow = '';
  G = null; closeSheet(true);
  if (onCloseCb) onCloseCb();
}
function stats() {
  const s = loadSave();
  return { unlocked: s.unlocked, levels: LEVELS.length, cleared: Object.keys(s.stars).length,
    stars: Object.values(s.stars).reduce((a, b) => a + b, 0), maxStars: LEVELS.length * 3, medals: s.medals };
}
window.SkyBarrage = { open, close, stats, _debug: () => ({ G, jets, save, S, OX, OY, mode }) };
})();
