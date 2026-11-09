/* SmartMotion Flight: terrain height and the layout of the Duxford area.
   An impression of the area, not a survey: the runway, hangars, M11, river, villages and woods are placed
   to feel right from the air. World axes: x east, y up, z south (north is -z), metres, origin at the airfield centre. */
(function (root) {
'use strict';
const D2R = Math.PI / 180;
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const sstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

/* ----- runway 06/24: 062 degrees true, 1,503 m ----- */
const hdg = 62 * D2R;
const RW = { heading: hdg, dir: [Math.sin(hdg), -Math.cos(hdg)], len: 1503, width: 46, elev: 38 };
RW.perp = [-RW.dir[1], RW.dir[0]];                 // points to the right when facing along the runway (to the south-east)
const toRunway = (x, z) => [x * RW.dir[0] + z * RW.dir[1], x * RW.perp[0] + z * RW.perp[1]];
const fromRunway = (u, v) => [RW.dir[0] * u + RW.perp[0] * v, RW.dir[1] * u + RW.perp[1] * v];

/* ----- noise ----- */
function ihash(x, y, s) {
  let h = (Math.imul(x | 0, 0x27d4eb2d) ^ Math.imul(y | 0, 0x165667b1) ^ Math.imul(s | 0, 0x9e3779b1)) | 0;
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b); h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}
function vnoise(x, z, period, seed) {                // periodic value noise, x and z in lattice units
  const x0 = Math.floor(x), z0 = Math.floor(z), fx = x - x0, fz = z - z0;
  const u = fx * fx * fx * (fx * (fx * 6 - 15) + 10), v = fz * fz * fz * (fz * (fz * 6 - 15) + 10);
  const i0 = ((x0 % period) + period) % period, j0 = ((z0 % period) + period) % period, i1 = (i0 + 1) % period, j1 = (j0 + 1) % period;
  const a = ihash(i0, j0, seed), b = ihash(i1, j0, seed), c = ihash(i0, j1, seed), d = ihash(i1, j1, seed);
  return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
const SIZE = 512, CELL = 64, LEN = SIZE * CELL;     // heightmap: 512 x 512 cells of 64 m = 32.8 km, repeats beyond that
function fbm(x, z) {
  let s = 0, a = 1, tot = 0;
  for (let o = 0; o < 6; o++) {
    const wl = 8192 / (1 << o);
    s += a * vnoise(x / wl, z / wl, LEN / wl, 11 + o); tot += a; a *= 0.5;
  }
  return s / tot;
}
function distToSegment(px, pz, ax, az, bx, bz) {
  const dx = bx - ax, dz = bz - az, t = clamp(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz || 1), 0, 1);
  return Math.hypot(px - (ax + dx * t), pz - (az + dz * t));
}
function rawHeight(x, z) {
  const hills = (fbm(x, z) - 0.5) * 80 + 48;
  const [u, v] = toRunway(x, z);
  const du = Math.max(Math.abs(u) - RW.len / 2, 0), d = Math.hypot(du, v);   // distance to the runway strip
  return RW.elev + (hills - RW.elev) * sstep(480, 1100, d);
}
class HeightMap {
  constructor() {
    this.data = new Float32Array(SIZE * SIZE);
    for (let j = 0; j < SIZE; j++) for (let i = 0; i < SIZE; i++) this.data[j * SIZE + i] = rawHeight((i - SIZE / 2) * CELL, (j - SIZE / 2) * CELL);
  }
  height(x, z) {                                      // bilinear, repeats beyond the map edge
    const gx = x / CELL + SIZE / 2, gz = z / CELL + SIZE / 2;
    const i0 = Math.floor(gx), j0 = Math.floor(gz), fx = gx - i0, fz = gz - j0;
    const a = ((i0 % SIZE) + SIZE) % SIZE, b = (a + 1) % SIZE, c = ((j0 % SIZE) + SIZE) % SIZE, d = (c + 1) % SIZE, D = this.data;
    const h00 = D[c * SIZE + a], h10 = D[c * SIZE + b], h01 = D[d * SIZE + a], h11 = D[d * SIZE + b];
    return h00 + (h10 - h00) * fx + (h01 - h00) * fz + (h00 - h10 - h01 + h11) * fx * fz;
  }
}

/* ----- the airfield (runway frame: u along 062, v to the right/south-east) ----- */
const BUILDINGS = [
  { kind: 'hangar', u: -345, v: -240, du: 84, dv: 56, h: 17 },
  { kind: 'hangar', u: -245, v: -240, du: 84, dv: 56, h: 17 },
  { kind: 'hangar', u: -145, v: -240, du: 84, dv: 56, h: 17 },
  { kind: 'hangar', u: -45, v: -240, du: 84, dv: 56, h: 17 },
  { kind: 'bighangar', u: 130, v: -250, du: 130, dv: 76, h: 22 },
  { kind: 'tower', u: 40, v: -168, du: 9, dv: 9, h: 15 },
];
const colliders = BUILDINGS.map((b) => {
  const [x, z] = fromRunway(b.u, b.v);
  // box frame: u axis = runway direction, v axis = perpendicular; c and s are the direction's x and z
  return { cx: x, cz: z, c: RW.dir[0], s: RW.dir[1], hu: b.du / 2 + 2, hv: b.dv / 2 + 2, top: RW.elev + b.h };
});
function paved(x, z) {
  const [u, v] = toRunway(x, z), au = Math.abs(u), av = Math.abs(v);
  if (au < RW.len / 2 + 15 && av < 26) return true;                       // runway
  if (au < 700 && Math.abs(v + 75) < 10) return true;                      // taxiway
  if (v < -23 && v > -75 && [-600, -250, 100, 450].some((u0) => Math.abs(u - u0) < 10)) return true;
  if (u > -400 && u < 220 && v < -90 && v > -215) return true;             // apron
  return false;
}

/* ----- the countryside ----- */
const ROADS = [
  { name: 'M11', w: 30, pts: [[1000, -9000], [2000, -4800], [3100, 0], [4000, 4600], [5200, 9000]] },
  { name: 'A505', w: 13, pts: [[-8000, -900], [-3000, -1150], [1000, -1450], [3100, -1700], [6500, -2400]] },
  { name: 'B1383', w: 9, pts: [[-1200, 5000], [-300, 2500], [300, 900], [1400, 480], [3100, 450]] },
  { name: 'lane', w: 7, pts: [[1500, 2400], [1450, 1300], [1400, 500]] },
  { name: 'lane', w: 7, pts: [[1500, 2400], [2300, 2900], [3600, 4000]] },
  { name: 'lane', w: 7, pts: [[-700, 1900], [-300, 2500]] },
  { name: 'lane', w: 7, pts: [[-1200, 5000], [-2500, 6500], [-4000, 7200]] },
  { name: 'lane', w: 7, pts: [[1400, 480], [1000, -400], [900, -1480]] },
  { name: 'lane', w: 7, pts: [[-2200, -2600], [-1500, -1500], [-300, -1250]] },
  { name: 'lane', w: 7, pts: [[2300, 2900], [3100, 2200]] },
];
const RIVER = { w: 16, pts: [[-2500, -9500], [-1700, -6800], [-1100, -4900], [-400, -2700], [600, -900], [1100, 700], [900, 2200], [600, 3200], [1500, 6000], [3000, 9500]] };
const VILLAGES = [
  { name: 'Duxford', x: 1400, z: 520, r: 430 }, { name: 'Whittlesford', x: 1550, z: 2450, r: 390 },
  { name: 'Pampisford', x: -700, z: 1950, r: 330 }, { name: 'Sawston', x: -2300, z: -2600, r: 620 },
  { name: 'Hinxton', x: 900, z: -1500, r: 280 }, { name: 'Ickleton', x: 2300, z: 2950, r: 300 },
  { name: 'Great Chesterford', x: 3600, z: 4000, r: 460 }, { name: 'Shelford', x: -1200, z: 5000, r: 520 },
  { name: 'Town', x: -2500, z: -13500, r: 3000 }, { name: 'Market town', x: 9500, z: 9500, r: 1500 },
];
const WOODS = [
  [-1800, 600, 380], [900, -2300, 300], [2400, 1500, 260], [-300, 2800, 340], [3600, -3000, 420], [-3200, -400, 450],
  [4800, 1200, 300], [-4500, 2800, 380], [200, 5200, 420], [2000, -5200, 360], [-1100, -4200, 300], [5600, -600, 320],
  [-2200, 4300, 300], [3300, 3800, 280], [-4000, -4500, 500], [6000, 5000, 420], [-6200, 800, 520], [7400, -5000, 480],
];
// low-level course: gates around the area, height above ground in metres
const GATES = [
  [1300, -1700, 130], [2800, -3500, 120], [4200, -2100, 110], [4700, 0, 100], [3700, 2300, 110], [2100, 3500, 120],
  [200, 3000, 120], [-1600, 1700, 110], [-2300, -500, 120], [-1000, -1900, 130], [200, -700, 90],
];
// Smartmotion signs (runway frame); face = angle in degrees the sign faces, measured like a heading from the runway direction
const SIGNS = [
  { u: -560, v: 105, w: 34, h: 11, face: -90, post: 8 },
  { u: 420, v: -120, w: 34, h: 11, face: 90, post: 8 },
  { u: 760, v: 180, w: 26, h: 8.5, face: 180, post: 7 },
];

root.SMTerrain = { RW, toRunway, fromRunway, HeightMap, rawHeight, BUILDINGS, colliders, paved, ROADS, RIVER, VILLAGES, WOODS, GATES, SIGNS, ihash, vnoise, LEN, SIZE, CELL, distToSegment };
if (typeof module !== 'undefined' && module.exports) module.exports = root.SMTerrain;
})(typeof window !== 'undefined' ? window : globalThis);
