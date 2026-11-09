/* SmartMotion Flight: the world (three.js).
   Sky, terrain, the Duxford airfield with SmartMotion signs, villages, woods, clouds, a blimp and the gate course.
   The ground colour is painted once on the GPU into two big textures (fields, hedges, roads, river, villages, runway). */
(function (root) {
'use strict';
const THREE = root.THREE, T = root.SMTerrain, D2R = Math.PI / 180;
const FONT = '"Barlow Semi Condensed","Arial Narrow",system-ui,sans-serif';
function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const loadImg = (url) => new Promise((res) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = url; });
const lam = (c, o) => new THREE.MeshLambertMaterial(Object.assign({ color: c }, o || {}));

const TOD = {
  day: { el: 46, az: 205, sun: [1, 0.96, 0.88], top: [0.14, 0.36, 0.78], hor: [0.74, 0.84, 0.95], hemiSky: 0xbfd6f2, hemiGnd: 0x61704f, hemiI: 0.9, sunI: 0.95, amb: [0.52, 0.55, 0.62], fog: 0.000048 },
  golden: { el: 9, az: 252, sun: [1, 0.62, 0.32], top: [0.12, 0.2, 0.5], hor: [0.97, 0.74, 0.56], hemiSky: 0xf1bf9c, hemiGnd: 0x4d4439, hemiI: 0.7, sunI: 1.0, amb: [0.4, 0.38, 0.45], fog: 0.00007 },
};
const sunDir = (t) => new THREE.Vector3(Math.sin(t.az * D2R) * Math.cos(t.el * D2R), Math.sin(t.el * D2R), -Math.cos(t.az * D2R) * Math.cos(t.el * D2R));

/* ---------- ground painting shader (runs once per map) ---------- */
const BAKE_FRAG = `
precision highp float;
varying vec2 vUv;
uniform vec2 uCenter; uniform float uSize; uniform float uRoadMul; uniform float uDetail;
uniform vec4 uRoad[28]; uniform float uRoadW[28]; uniform vec4 uRiver[12]; uniform vec3 uVill[10]; uniform vec3 uWood[18]; uniform vec4 uRw;
float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
vec2 h22(vec2 p){ return fract(sin(vec2(dot(p,vec2(127.1,311.7)), dot(p,vec2(269.5,183.3))))*43758.5453); }
float vn(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(h21(i),h21(i+vec2(1.0,0.0)),f.x), mix(h21(i+vec2(0.0,1.0)),h21(i+vec2(1.0,1.0)),f.x), f.y); }
float segd(vec2 p, vec4 s){ vec2 pa=p-s.xy, ba=s.zw-s.xy; float h=clamp(dot(pa,ba)/max(dot(ba,ba),1e-3),0.0,1.0); return length(pa-ba*h); }
float boxm(vec2 p, vec2 c, vec2 hs, float soft){ vec2 d=abs(p-c)-hs; return 1.0-smoothstep(0.0, soft, max(d.x,d.y)); }
void main(){
  vec2 p = uCenter + (vUv-0.5)*uSize;
  // fields: jittered cells, each one a crop
  vec2 q = p/380.0, ci=floor(q), cf=fract(q);
  float d1=9.0, d2=9.0; vec2 id=vec2(0.0);
  for(int j=-1;j<=1;j++) for(int i=-1;i<=1;i++){ vec2 g=vec2(float(i),float(j)); vec2 r=g+h22(ci+g)-cf; float d=dot(r,r); if(d<d1){d2=d1;d1=d;id=ci+g;} else if(d<d2){d2=d;} }
  float edge=(sqrt(d2)-sqrt(d1))*380.0;
  float hc=h21(id*1.37+3.1);
  vec3 col;
  if(hc<0.28) col=vec3(0.36,0.52,0.22); else if(hc<0.46) col=vec3(0.74,0.66,0.28); else if(hc<0.58) col=vec3(0.62,0.62,0.30);
  else if(hc<0.72) col=vec3(0.47,0.37,0.26); else if(hc<0.86) col=vec3(0.22,0.41,0.18); else col=vec3(0.80,0.74,0.20);
  col *= (0.88+0.24*h21(id+7.7)) * (0.92+0.16*vn(p*0.004));
  float alpha = (hc>=0.28 && hc<0.86) ? max(h21(id+19.0),0.03) : 0.0;
  float hedge = (1.0-smoothstep(1.5,5.0+uRoadMul,edge))*0.85;
  col = mix(col, vec3(0.12,0.24,0.10), hedge);
  // woods
  for(int i=0;i<18;i++){ vec3 w=uWood[i]; if(w.z>1.0){ vec2 d=p-w.xy; float a=atan(d.y,d.x); float rr=w.z*(1.0+0.25*sin(3.0*a+w.x*0.01)+0.15*sin(5.0*a+w.y*0.013)); float m=1.0-smoothstep(0.82,1.0,length(d)/rr);
    vec3 wc=vec3(0.13,0.27,0.13)*(0.75+0.5*vn(p*0.06)); col=mix(col,wc,m); alpha*=1.0-m; } }
  // villages: roofs and gardens
  for(int i=0;i<10;i++){ vec3 v=uVill[i]; if(v.z>1.0){ vec2 d=p-v.xy; float a=atan(d.y,d.x); float rr=v.z*(1.0+0.2*sin(3.0*a+v.x*0.02)+0.12*sin(6.0*a+v.y*0.011)); float m=1.0-smoothstep(0.85,1.0,length(d)/rr);
    vec3 vc=vec3(0.50,0.52,0.40);
    if(uDetail>0.5){ vec2 hp=p/30.0; vec2 hi=floor(hp), hf=fract(hp); float house=step(0.3,h21(hi))*step(0.18,hf.x)*step(hf.x,0.82)*step(0.2,hf.y)*step(hf.y,0.8); vc=mix(vec3(0.36,0.5,0.28), vec3(0.58,0.34,0.27)*(0.8+0.4*h21(hi+3.0)), house); }
    else vc=vec3(0.52,0.46,0.42);
    if(v.z>1500.0) vc=vec3(0.48,0.47,0.47);
    col=mix(col,vc,m); alpha*=1.0-m; } }
  // river
  float rd=1e5; for(int i=0;i<12;i++) rd=min(rd, segd(p,uRiver[i]));
  float rw=uRoadMul*0.0+16.0*max(1.0,uRoadMul*0.5);
  col=mix(col, vec3(0.20,0.28,0.14), (1.0-smoothstep(rw*0.5,rw*0.5+14.0*uRoadMul,rd))*0.6);
  float water=1.0-smoothstep(rw*0.5-1.0,rw*0.5+1.5,rd); col=mix(col, vec3(0.22,0.38,0.52), water); alpha*=1.0-water;
  // roads
  float road=0.0, verge=0.0, cl=0.0;
  for(int i=0;i<28;i++){ float w=uRoadW[i]*uRoadMul; if(w>0.5){ float d=segd(p,uRoad[i]); road=max(road,1.0-smoothstep(w*0.5,w*0.5+1.2,d)); verge=max(verge,1.0-smoothstep(w*0.5,w*0.5+7.0,d)); if(uRoadW[i]>25.0) cl=max(cl,(1.0-smoothstep(0.4,1.0,abs(d-1.0)))*step(0.5,fract(dot(p,vec2(0.1,0.1))*0.2)))*0.0; } }
  col=mix(col, col*0.8+vec3(0.05), verge*0.5);
  col=mix(col, vec3(0.31,0.31,0.33), road); alpha*=1.0-road;
  // airfield
  vec2 rdir=uRw.xy, rperp=vec2(-rdir.y,rdir.x); float u=dot(p,rdir), v=dot(p,rperp), L=uRw.z*0.5;
  float ag=boxm(vec2(u,v), vec2(0.0,-60.0), vec2(L+140.0,330.0), 30.0);
  float stripe=step(mod(v,44.0),22.0); vec3 grass=vec3(0.42,0.60,0.28)*(0.96+0.06*stripe)*(0.95+0.1*vn(p*0.02));
  col=mix(col,grass,ag); alpha*=1.0-ag;
  float gr=boxm(vec2(u,v), vec2(0.0,125.0), vec2(650.0,24.0), 1.5); col=mix(col, vec3(0.50,0.68,0.32)*(0.94+0.1*step(mod(u,60.0),30.0)), gr);
  vec3 asph=vec3(0.19,0.20,0.22), conc=vec3(0.52,0.52,0.52);
  float taxi=boxm(vec2(u,v), vec2(0.0,-75.0), vec2(700.0,9.0), 1.5);
  for(int k=0;k<4;k++){ float u0=-600.0+350.0*float(k); taxi=max(taxi, boxm(vec2(u,v), vec2(u0,-48.0), vec2(9.0,28.0), 1.5)); }
  col=mix(col,asph,taxi);
  col=mix(col,conc,boxm(vec2(u,v), vec2(-90.0,-152.0), vec2(310.0,63.0), 2.0));
  float rwm=boxm(vec2(u,v), vec2(0.0,0.0), vec2(L+12.0,23.0), 1.2); col=mix(col,asph*1.05,rwm);
  float line=0.0;
  line=max(line, step(abs(v),0.7)*step(abs(u),L-20.0)*step(mod(u,36.0),18.0));
  line=max(line, step(abs(abs(v)-21.6),0.35)*step(abs(u),L+5.0));
  line=max(line, step(abs(abs(u)-(L-24.0)),11.0)*step(abs(v),20.0)*step(mod(v+0.8,3.2),1.6));
  col=mix(col, vec3(0.92), line*rwm);
  gl_FragColor=vec4(col, alpha);
}`;

class World {
  constructor(scene, renderer, opts) {
    this.scene = scene; this.renderer = renderer; this.opts = opts || {};
    this.q = this.opts.quality || 'medium';
    this.hm = new T.HeightMap();
    this.env = { height: (x, z) => this.hm.height(x, z), paved: T.paved, colliders: T.colliders, wind: [0, 0, 0] };
    this.rings = []; this.clouds = []; this.gateMeshes = []; this.assets = {};
  }
  heightAt(x, z) { return this.hm.height(x, z); }

  async init(progress) {
    const step = async (p, msg) => { if (progress) progress(p, msg); await new Promise((r) => setTimeout(r, 0)); };
    await step(0.05, 'Loading logos');
    const [logo, logoDark] = await Promise.all([loadImg('../assets/logo.png'), loadImg('../assets/logo-dark.png')]);
    this.assets = { logo, logoDark };
    try { await Promise.race([document.fonts.load('italic 800 60px "Barlow Semi Condensed"'), new Promise((r) => setTimeout(r, 2500))]); } catch (e) { /* ignore */ }
    this._lights(); this._sky();
    await step(0.15, 'Painting the countryside');
    this._bakeGround();
    await step(0.55, 'Building the terrain');
    this._terrain();
    await step(0.7, 'Building Duxford');
    this._airfield();
    await step(0.82, 'Planting woods and villages');
    this._scenery();
    await step(0.93, 'Hanging the signs');
    this._signs(); this._clouds(); this._blimp(); this._gates();
    this.setTimeOfDay(this.opts.tod || 'day');
    await step(1, 'Ready');
  }

  /* ---------- lighting and sky ---------- */
  _lights() {
    this.hemi = new THREE.HemisphereLight(0xffffff, 0x666666, 0.9); this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight(0xffffff, 0.95); this.scene.add(this.sun);
    this.scene.fog = new THREE.FogExp2(0xbcd0e6, 0.00005);
  }
  _sky() {
    const u = { uTop: { value: new THREE.Vector3() }, uHor: { value: new THREE.Vector3() }, uSunDir: { value: new THREE.Vector3(0, 1, 0) }, uSunCol: { value: new THREE.Vector3(1, 1, 1) } };
    const m = new THREE.ShaderMaterial({
      uniforms: u, side: THREE.BackSide, depthWrite: false, depthTest: false, fog: false,
      vertexShader: 'varying vec3 vDir; void main(){ vDir=position; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }',
      fragmentShader: `uniform vec3 uTop,uHor,uSunDir,uSunCol; varying vec3 vDir;
        void main(){ vec3 d=normalize(vDir); float t=clamp(d.y,0.0,1.0); vec3 col=mix(uHor,uTop,pow(t,0.5));
          if(d.y<0.0) col=mix(uHor,uHor*0.82,clamp(-d.y*5.0,0.0,1.0));
          float s=max(dot(d,uSunDir),0.0); col+=uSunCol*(pow(s,6.0)*0.14+pow(s,48.0)*0.3)+uSunCol*smoothstep(0.9993,0.9998,s)*2.5;
          gl_FragColor=vec4(col,1.0); }`,
    });
    this.sky = new THREE.Mesh(new THREE.SphereGeometry(18000, 24, 14), m); this.sky.renderOrder = -100; this.sky.frustumCulled = false;
    this.skyU = u; this.scene.add(this.sky);
  }
  setTimeOfDay(name) {
    const t = TOD[name] || TOD.day, sd = sunDir(t);
    this.tod = t; this.sunDirV = sd;
    this.skyU.uTop.value.set(...t.top); this.skyU.uHor.value.set(...t.hor); this.skyU.uSunDir.value.copy(sd); this.skyU.uSunCol.value.set(...t.sun);
    this.sun.position.copy(sd).multiplyScalar(1000); this.sun.color.setRGB(...t.sun); this.sun.intensity = t.sunI;
    this.hemi.color.setHex(t.hemiSky); this.hemi.groundColor.setHex(t.hemiGnd); this.hemi.intensity = t.hemiI;
    this.scene.fog.color.setRGB(...t.hor); this.scene.fog.density = t.fog;
    if (this.tMat) { this.tMat.uniforms.uSunDir.value.copy(sd); this.tMat.uniforms.uSunCol.value.set(...t.sun).multiplyScalar(0.55); this.tMat.uniforms.uAmb.value.set(...t.amb); }
    if (this.cloudMat) this.cloudMat.color.setRGB(Math.min(1, t.hor[0] + 0.15), Math.min(1, t.hor[1] + 0.12), Math.min(1, t.hor[2] + 0.1));
  }

  /* ---------- ground painting ---------- */
  _bakeGround() {
    const r = this.renderer, gl = r.capabilities;
    const sizes = { low: [1024, 512], medium: [2048, 1024], high: [4096, 2048] }[this.q] || [2048, 1024];
    const maxT = r.capabilities.maxTextureSize; const nearPx = Math.min(sizes[0], maxT), farPx = Math.min(sizes[1], maxT);
    const segs = (list, n) => { const a = []; for (let i = 0; i < n; i++) a.push(new THREE.Vector4(1e6, 1e6, 1e6, 1e6)); return a; };
    const roadSegs = segs([], 28), roadW = new Array(28).fill(0), riverSegs = segs([], 12); let ri = 0;
    for (const road of T.ROADS) for (let i = 0; i < road.pts.length - 1 && ri < 28; i++) { roadSegs[ri].set(road.pts[i][0], road.pts[i][1], road.pts[i + 1][0], road.pts[i + 1][1]); roadW[ri++] = road.w; }
    for (let i = 0; i < T.RIVER.pts.length - 1 && i < 12; i++) riverSegs[i].set(T.RIVER.pts[i][0], T.RIVER.pts[i][1], T.RIVER.pts[i + 1][0], T.RIVER.pts[i + 1][1]);
    const vill = Array.from({ length: 10 }, (_, i) => T.VILLAGES[i] ? new THREE.Vector3(T.VILLAGES[i].x, T.VILLAGES[i].z, T.VILLAGES[i].r) : new THREE.Vector3(0, 0, 0));
    const wood = Array.from({ length: 18 }, (_, i) => T.WOODS[i] ? new THREE.Vector3(T.WOODS[i][0], T.WOODS[i][1], T.WOODS[i][2]) : new THREE.Vector3(0, 0, 0));
    const mat = new THREE.ShaderMaterial({
      uniforms: { uCenter: { value: new THREE.Vector2() }, uSize: { value: 1 }, uRoadMul: { value: 1 }, uDetail: { value: 1 }, uRoad: { value: roadSegs }, uRoadW: { value: roadW }, uRiver: { value: riverSegs }, uVill: { value: vill }, uWood: { value: wood }, uRw: { value: new THREE.Vector4(T.RW.dir[0], T.RW.dir[1], T.RW.len, T.RW.width) } },
      vertexShader: 'varying vec2 vUv; void main(){ vUv=uv; gl_Position=vec4(position.xy,0.0,1.0); }', fragmentShader: BAKE_FRAG,
      blending: THREE.NoBlending, depthTest: false, depthWrite: false, transparent: false,
    });
    const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat), sc = new THREE.Scene(); quad.frustumCulled = false; sc.add(quad);
    const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    const aniso = Math.min(8, r.capabilities.getMaxAnisotropy());
    const make = (px, size, mul, detail, wrap) => {
      const rt = new THREE.WebGLRenderTarget(px, px, { minFilter: THREE.LinearMipmapLinearFilter, magFilter: THREE.LinearFilter, format: THREE.RGBAFormat, generateMipmaps: true });
      rt.texture.anisotropy = aniso; if (wrap) rt.texture.wrapS = rt.texture.wrapT = THREE.RepeatWrapping;
      mat.uniforms.uCenter.value.set(0, 0); mat.uniforms.uSize.value = size; mat.uniforms.uRoadMul.value = mul; mat.uniforms.uDetail.value = detail;
      const prev = r.getRenderTarget(), xr = r.xr.enabled; r.xr.enabled = false;
      r.setRenderTarget(rt); r.render(sc, cam); r.setRenderTarget(prev); r.xr.enabled = xr;
      return rt;
    };
    this.nearSize = nearPx * 10; this.farSize = farPx * 80;
    this.nearRT = make(nearPx, this.nearSize, 1, 1, false);
    this.farRT = make(farPx, this.farSize, 3, 0, true);
    mat.dispose(); quad.geometry.dispose();
    // tiny tileable detail texture
    const dc = document.createElement('canvas'); dc.width = dc.height = 128; const dx = dc.getContext('2d'), id = dx.createImageData(128, 128), R = rng(5);
    const grid = new Float32Array(16 * 16).map(() => R());
    for (let y = 0; y < 128; y++) for (let x = 0; x < 128; x++) {
      let v = 0, a = 0.5, f = 1; for (let o = 0; o < 4; o++) { const gx = (x / 128) * 16 * f, gy = (y / 128) * 16 * f, x0 = Math.floor(gx), y0 = Math.floor(gy), fx = gx - x0, fy = gy - y0, w = (i, j) => grid[((j % 16) * 16 + (i % 16))]; v += a * ((w(x0, y0) * (1 - fx) + w(x0 + 1, y0) * fx) * (1 - fy) + (w(x0, y0 + 1) * (1 - fx) + w(x0 + 1, y0 + 1) * fx) * fy); a *= 0.5; f *= 2; }
      const g = Math.max(0, Math.min(255, v * 255 * 1.1)); const k = (y * 128 + x) * 4; id.data[k] = id.data[k + 1] = id.data[k + 2] = g; id.data[k + 3] = 255;
    }
    dx.putImageData(id, 0, 0);
    this.detailTex = new THREE.CanvasTexture(dc); this.detailTex.wrapS = this.detailTex.wrapT = THREE.RepeatWrapping; this.detailTex.anisotropy = aniso;
  }

  /* ---------- terrain rings (a moving mesh that follows the aircraft) ---------- */
  _terrain() {
    const mat = new THREE.ShaderMaterial({
      uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
        uNear: { value: this.nearRT.texture }, uFar: { value: this.farRT.texture }, uDetail: { value: this.detailTex },
        uNearC: { value: new THREE.Vector2(0, 0) }, uFarC: { value: new THREE.Vector2(0, 0) }, uNearS: { value: this.nearSize }, uFarS: { value: this.farSize },
        uSunDir: { value: new THREE.Vector3(0, 1, 0) }, uSunCol: { value: new THREE.Vector3(0.6, 0.6, 0.55) }, uAmb: { value: new THREE.Vector3(0.5, 0.5, 0.5) },
      }]),
      fog: true, polygonOffset: false,
      vertexShader: `varying vec3 vWorld; varying vec3 vNormalW;
        #include <fog_pars_vertex>
        void main(){ vec4 wp=modelMatrix*vec4(position,1.0); vWorld=wp.xyz; vNormalW=normal; vec4 mvPosition=viewMatrix*wp; gl_Position=projectionMatrix*mvPosition;
        #include <fog_vertex>
        }`,
      fragmentShader: `uniform sampler2D uNear,uFar,uDetail; uniform vec2 uNearC,uFarC; uniform float uNearS,uFarS; uniform vec3 uSunDir,uSunCol,uAmb;
        varying vec3 vWorld; varying vec3 vNormalW;
        #include <fog_pars_fragment>
        void main(){
          vec2 nuv=(vWorld.xz-uNearC)/uNearS+0.5; vec2 fuv=(vWorld.xz-uFarC)/uFarS+0.5;
          vec4 nc=texture2D(uNear,nuv); vec4 fc=texture2D(uFar,fuv);
          float e=max(abs(nuv.x-0.5),abs(nuv.y-0.5))*2.0; float w=1.0-smoothstep(0.86,0.98,e);
          vec3 col=mix(fc.rgb,nc.rgb,w); float dist=length(vWorld-cameraPosition);
          float fade=1.0-smoothstep(150.0,1800.0,dist); float dn=texture2D(uDetail,vWorld.xz/11.0).r; col*=1.0+(dn-0.5)*0.5*fade;
          float a=nc.a*w; if(a>0.01 && dist<520.0){ float ang=a*6.2831; float s=sin(dot(vWorld.xz,vec2(cos(ang),sin(ang)))*6.2831/3.2); col*=1.0+0.08*s*(1.0-smoothstep(60.0,520.0,dist)); }
          vec3 n=normalize(vNormalW); float l=max(dot(n,uSunDir),0.0); col*=uAmb+uSunCol*l*1.5;
          gl_FragColor=vec4(col,1.0);
          #include <fog_fragment>
        }`,
    });
    // UniformsUtils.merge clones textures, which breaks render-target textures: point the uniforms at the real ones
    mat.uniforms.uNear.value = this.nearRT.texture; mat.uniforms.uFar.value = this.farRT.texture; mat.uniforms.uDetail.value = this.detailTex;
    this.tMat = mat;
    const N = 120, cells = [16, 64, 256, 1024];
    cells.forEach((cell, k) => {
      const n1 = N + 1, pos = new Float32Array(n1 * n1 * 3), nor = new Float32Array(n1 * n1 * 3), hole = k ? 12 : 0, idx = [];
      for (let j = 0; j < n1; j++) for (let i = 0; i < n1; i++) { const o = (j * n1 + i) * 3; pos[o] = (i - N / 2) * cell; pos[o + 2] = (j - N / 2) * cell; nor[o + 1] = 1; }
      for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
        if (hole && i >= N / 2 - hole && i < N / 2 + hole && j >= N / 2 - hole && j < N / 2 + hole) continue;
        const a = j * n1 + i, b = a + 1, c = a + n1, d = c + 1; idx.push(a, c, b, b, c, d);
      }
      const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.BufferAttribute(pos, 3)); g.setAttribute('normal', new THREE.BufferAttribute(nor, 3)); g.setIndex(idx);
      const m = new THREE.Mesh(g, mat.clone()); m.frustumCulled = false;
      m.material.uniforms = mat.uniforms;                         // share uniforms
      m.material.polygonOffset = k > 0; m.material.polygonOffsetFactor = 1 + k; m.material.polygonOffsetUnits = 2 + 2 * k;
      this.scene.add(m);
      this.rings.push({ mesh: m, cell, n1, snap: cell * 4, cx: 1e9, cz: 1e9, y: new Float32Array(n1 * n1) });
    });
  }
  _updateRings(x, z) {
    for (const r of this.rings) {
      const cx = Math.round(x / r.snap) * r.snap, cz = Math.round(z / r.snap) * r.snap;
      if (cx === r.cx && cz === r.cz) continue;
      r.cx = cx; r.cz = cz; r.mesh.position.set(cx, 0, cz);
      const { n1, cell, y } = r, N = n1 - 1, pos = r.mesh.geometry.attributes.position.array, nor = r.mesh.geometry.attributes.normal.array;
      for (let j = 0; j < n1; j++) for (let i = 0; i < n1; i++) { const h = this.hm.height(cx + (i - N / 2) * cell, cz + (j - N / 2) * cell); y[j * n1 + i] = h; pos[(j * n1 + i) * 3 + 1] = h; }
      for (let j = 0; j < n1; j++) for (let i = 0; i < n1; i++) {
        const l = y[j * n1 + Math.max(i - 1, 0)], rr = y[j * n1 + Math.min(i + 1, N)], u = y[Math.max(j - 1, 0) * n1 + i], d = y[Math.min(j + 1, N) * n1 + i];
        let nx = l - rr, nz = u - d, ny = 2 * cell; const L = Math.hypot(nx, ny, nz); const o = (j * n1 + i) * 3; nor[o] = nx / L; nor[o + 1] = ny / L; nor[o + 2] = nz / L;
      }
      r.mesh.geometry.attributes.position.needsUpdate = true; r.mesh.geometry.attributes.normal.needsUpdate = true;
    }
  }

  /* ---------- the airfield ---------- */
  _rw(u, v) { const [x, z] = T.fromRunway(u, v); return [x, z]; }
  _place(obj, u, v, dy, yawExtra) { const [x, z] = this._rw(u, v); obj.position.set(x, this.heightAt(x, z) + (dy || 0), z); obj.rotation.y = -T.RW.heading + (yawExtra || 0); this.scene.add(obj); return obj; }
  text(ctx, str, x, y, size, color, align) { ctx.font = `italic 800 ${size}px ${FONT}`; ctx.fillStyle = color; ctx.textAlign = align || 'left'; ctx.textBaseline = 'middle'; ctx.fillText(str, x, y); }
  signTexture(w, h, o) {
    o = o || {}; const px = o.px || 1024, c = document.createElement('canvas'); c.width = px; c.height = Math.round(px * h / w); const g = c.getContext('2d'), W = c.width, H = c.height;
    g.fillStyle = o.bg || '#ffffff'; g.fillRect(0, 0, W, H);
    const dark = o.bg === '#02022f', logo = dark ? this.assets.logoDark : this.assets.logo;
    if (o.frame !== false) { g.strokeStyle = dark ? '#ff4c00' : '#02022f'; g.lineWidth = H * 0.035; g.strokeRect(H * 0.04, H * 0.04, W - H * 0.08, H - H * 0.08); }
    if (o.band !== false) { g.fillStyle = '#ff4c00'; g.fillRect(H * 0.04, H * 0.82, W - H * 0.08, H * 0.14); }
    if (logo) { const lh = H * (o.tag ? 0.6 : 0.68), lw = lh * logo.width / logo.height; const lx = o.tag ? W * 0.05 : (W - lw) / 2; g.drawImage(logo, lx, H * 0.08, lw, lh); }
    if (o.tag) { const lines = o.tag.split('|'); lines.forEach((t, i) => this.text(g, t, W * 0.62, H * (0.22 + i * 0.23), H * 0.19, i === 1 ? '#ff4c00' : (dark ? '#ffffff' : '#02022f'))); }
    if (o.band !== false) this.text(g, o.bandText || 'SMARTMOTION.TECH', W / 2, H * 0.89, H * 0.1, '#ffffff', 'center');
    const t = new THREE.CanvasTexture(c); t.anisotropy = 8; return t;
  }
  _sign(x, z, w, h, nx, nz, postH, tex) {
    const g = new THREE.Group(), y = this.heightAt(x, z);
    const panel = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: tex, side: THREE.DoubleSide, fog: true }));
    panel.position.y = postH + h / 2; g.add(panel);
    const back = new THREE.Mesh(new THREE.BoxGeometry(w + 0.8, h + 0.8, 0.5), lam(0x02022f)); back.position.set(0, postH + h / 2, -0.32); g.add(back);
    for (const s of [-1, 1]) { const p = new THREE.Mesh(new THREE.BoxGeometry(0.7, postH + 1, 0.7), lam(0x3a3d4d)); p.position.set(s * w * 0.35, (postH + 1) / 2, -0.3); g.add(p); }
    g.position.set(x, y, z); g.rotation.y = Math.atan2(nx, nz); this.scene.add(g); return g;
  }
  _signs() {
    const tag = 'FLY IT.|DRIVE IT.|FEEL IT.';
    T.SIGNS.forEach((s, i) => {
      const [x, z] = this._rw(s.u, s.v), nu = Math.cos(s.face * D2R), nv = Math.sin(s.face * D2R);
      this._sign(x, z, s.w, s.h, T.RW.dir[0] * nu + T.RW.perp[0] * nv, T.RW.dir[1] * nu + T.RW.perp[1] * nv, s.post, this.signTexture(s.w, s.h, { tag, px: 1024 }));
    });
    // roadside billboard beside the M11, facing the airfield
    this._sign(3000, -220, 34, 11, -1, 0.1, 8, this.signTexture(34, 11, { tag, px: 1024, bg: '#02022f' }));
    // runway distance boards
    for (let k = -3; k <= 3; k++) { const [x, z] = this._rw(k * 220, 38); this._sign(x, z, 4.4, 1.8, T.RW.perp[0] * -1, T.RW.perp[1] * -1, 1.2, this.signTexture(4.4, 1.8, { px: 512, band: false })); }
    // logo painted on the grass
    const gt = this.signTexture(64, 24, { px: 1024, tag, bandText: 'DUXFORD · FLY IT. DRIVE IT. FEEL IT.' });
    const gm = new THREE.Mesh(new THREE.PlaneGeometry(64, 24), new THREE.MeshBasicMaterial({ map: gt, fog: true, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 }));
    const gg = new THREE.Group(); gm.rotation.x = -Math.PI / 2; gg.add(gm); this._place(gg, -140, 270, 0.12, 0);
    // windsock
    const ws = new THREE.Group(), pole = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.16, 9, 8), lam(0xdddddd)); pole.position.y = 4.5; ws.add(pole);
    const sock = new THREE.Mesh(new THREE.ConeGeometry(0.75, 3.6, 12, 1, true).rotateZ(Math.PI / 2).translate(1.9, 0, 0), new THREE.MeshLambertMaterial({ color: 0xff4c00, side: THREE.DoubleSide })); sock.position.y = 9; ws.add(sock);
    const ring = new THREE.Mesh(new THREE.CylinderGeometry(0.76, 0.76, 0.5, 12, 1, true).rotateZ(Math.PI / 2).translate(1.0, 0, 0), new THREE.MeshLambertMaterial({ color: 0xffffff, side: THREE.DoubleSide })); ring.position.y = 9; ws.add(ring);
    this.windsock = ws; this._place(ws, 250, 45, 0, 0);
  }
  _airfield() {
    // local frame of every building: x along the runway (u), z across it (v), +z faces the runway
    const texFront = (du, wallH, withLogo) => {
      const c = document.createElement('canvas'); c.width = 1024; c.height = Math.round(1024 * wallH / du); const g = c.getContext('2d');
      g.fillStyle = '#8a4f3a'; g.fillRect(0, 0, c.width, c.height);
      for (let y = 0; y < c.height; y += 12) { g.fillStyle = 'rgba(0,0,0,0.12)'; g.fillRect(0, y, c.width, 2); }
      g.fillStyle = '#3b3f4d'; g.fillRect(c.width * 0.06, c.height * 0.3, c.width * 0.88, c.height * 0.7);
      g.fillStyle = '#2d3040'; for (let i = 1; i < 6; i++) g.fillRect(c.width * (0.06 + 0.88 * i / 6) - 2, c.height * 0.3, 4, c.height * 0.7);
      g.fillStyle = '#ff4c00'; g.fillRect(c.width * 0.06, c.height * 0.24, c.width * 0.88, c.height * 0.05);
      if (withLogo && this.assets.logoDark) { const lh = c.height * 0.2, lw = lh * 2.5; g.drawImage(this.assets.logoDark, c.width * 0.5 - lw / 2, c.height * 0.02, lw, lh); }
      const t = new THREE.CanvasTexture(c); t.anisotropy = 4; return t;
    };
    const wallM = lam(0x9a8a7a);
    T.BUILDINGS.forEach((b, i) => {
      const g = new THREE.Group();
      if (b.kind === 'tower') {
        const base = new THREE.Mesh(new THREE.BoxGeometry(b.du, 9, b.dv), lam(0xe9e6df)); base.position.y = 4.5; g.add(base);
        const cab = new THREE.Mesh(new THREE.BoxGeometry(b.du + 3, 3.4, b.dv + 3), lam(0x7fa8cc, { transparent: true, opacity: 0.8 })); cab.position.y = 10.7; g.add(cab);
        const roof = new THREE.Mesh(new THREE.BoxGeometry(b.du + 4, 0.5, b.dv + 4), lam(0x2a2d38)); roof.position.y = 12.6; g.add(roof);
        const mast = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.1, 4, 6), lam(0xbbbbbb)); mast.position.y = 14.8; g.add(mast);
        const sg = new THREE.Mesh(new THREE.PlaneGeometry(b.du, 3), new THREE.MeshBasicMaterial({ map: this.signTexture(b.du, 3, { px: 512, band: false }) })); sg.position.set(0, 5.5, b.dv / 2 + 0.06); g.add(sg);
        this._place(g, b.u, b.v, 0, Math.PI / 2); return;
      }
      const wallH = b.kind === 'bighangar' ? 13 : 10.5, ridge = b.h - wallH, hw = b.dv / 2, du = b.du;
      const body = new THREE.Mesh(new THREE.BoxGeometry(du, wallH, b.dv), wallM); body.position.y = wallH / 2; g.add(body);
      const geo = new THREE.BufferGeometry();       // gabled roof: cross-section in z, long in x
      geo.setAttribute('position', new THREE.Float32BufferAttribute([-du / 2, 0, -hw, -du / 2, 0, hw, -du / 2, ridge, 0, du / 2, 0, -hw, du / 2, 0, hw, du / 2, ridge, 0], 3));
      geo.setIndex([0, 1, 2, 3, 5, 4, 0, 2, 5, 0, 5, 3, 1, 4, 5, 1, 5, 2]); geo.computeVertexNormals();
      const roof = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color: 0x6d717c, side: THREE.DoubleSide })); roof.position.y = wallH; g.add(roof);
      // big logo on the roof slope that faces the runway
      const s = Math.atan2(ridge, hw), sl = Math.hypot(hw, ridge), lw = du * 0.92, lh = Math.min(sl * 0.86, lw / 2.2);
      const flat = new THREE.Mesh(new THREE.PlaneGeometry(lw, lh), new THREE.MeshBasicMaterial({ map: this.signTexture(lw, lh, { px: 1024, tag: 'FLY IT.|DRIVE IT.|FEEL IT.', bandText: 'SMARTMOTION · DUXFORD' }), polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }));
      flat.rotation.x = s - Math.PI / 2; flat.position.set(0, wallH + ridge / 2 + 0.12, hw / 2); g.add(flat);
      const front = new THREE.Mesh(new THREE.PlaneGeometry(du, wallH), new THREE.MeshLambertMaterial({ map: texFront(du, wallH, true) })); front.position.set(0, wallH / 2, hw + 0.06); g.add(front);
      this._place(g, b.u, b.v, 0, Math.PI / 2);
    });
    this._runwayDecal();
    // parked aircraft on the apron
    const A = root.SMAircraft;
    if (A) [['trainer', -330, -140, 40], ['fighter', -250, -125, -20], ['trainer', -170, -145, 70], ['fighter', -80, -130, 15], ['trainer', 20, -150, -50], ['fighter', 140, -140, 95]].forEach(([k, u, v, yaw]) => {
      const m = A.build(k, this.assets); m.userData.setView(false); m.rotation.x = k === 'trainer' ? 0 : 0.085;
      const pivot = new THREE.Group(); pivot.add(m); this._place(pivot, u, v, k === 'trainer' ? 0.97 : 1.38, yaw * D2R);
    });
  }

  _runwayDecal() {
    // a sharp runway texture laid over the (flat) airfield: canvas x = across (v), canvas up = along the runway towards 06
    const L = T.RW.len, wM = 46, ppm = 4096 / L, W = 128, H = 4096, c = document.createElement('canvas'); c.width = W; c.height = H; const g = c.getContext('2d'), R = rng(3);
    g.fillStyle = '#34363c'; g.fillRect(0, 0, W, H);
    for (let i = 0; i < 900; i++) { g.fillStyle = `rgba(${R() < 0.5 ? '255,255,255' : '0,0,0'},${0.02 + R() * 0.04})`; g.fillRect(R() * W, R() * H, 1 + R() * 3, 6 + R() * 40); }
    const X = (v) => (v + wM / 2) * ppm, Y = (u) => (L / 2 - u) * ppm;
    for (const u0 of [-L / 2 + 330, L / 2 - 330]) for (const dv of [-3, 3]) { g.fillStyle = 'rgba(10,10,12,0.35)'; g.fillRect(X(dv - 0.8), Y(u0 + 160), 1.6 * ppm, 320 * ppm); }
    g.fillStyle = '#ecebe6';
    for (let u = -L / 2 + 70; u < L / 2 - 70; u += 50) g.fillRect(X(-0.45), Y(u + 30), 0.9 * ppm, 30 * ppm);            // centreline
    g.fillRect(X(-21.8), 0, 0.35 * ppm, H); g.fillRect(X(21.45), 0, 0.35 * ppm, H);                                     // edge lines
    for (const sgn of [-1, 1]) {                                                                                           // thresholds and aiming blocks
      const base = sgn * (L / 2);
      for (let k = -8; k <= 8; k++) { if (k === 0) continue; g.fillRect(X(k * 2.4 - 0.7), Y(base - sgn * 6 + (sgn > 0 ? 0 : 0) + (sgn > 0 ? 0 : 30)), 1.4 * ppm, 30 * ppm); }
      for (const d of [300, 450]) for (const dv of [-9, 9]) g.fillRect(X(dv - 1.5), Y(base - sgn * d + (sgn > 0 ? 0 : 22)), 3 * ppm, 22 * ppm);
    }
    g.fillStyle = '#ecebe6'; g.font = `700 ${Math.round(14 * ppm)}px Arial Narrow, Arial, sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.save(); g.translate(X(0), Y(-L / 2 + 55)); g.scale(1, 1.1); g.fillText('06', 0, 0); g.restore();                    // read from the south-west end
    g.save(); g.translate(X(0), Y(L / 2 - 55)); g.rotate(Math.PI); g.scale(1, 1.1); g.fillText('24', 0, 0); g.restore();  // read from the north-east end
    const tex = new THREE.CanvasTexture(c); tex.anisotropy = 8; tex.generateMipmaps = true; tex.minFilter = THREE.LinearMipmapLinearFilter;
    const m = new THREE.Mesh(new THREE.PlaneGeometry(wM + 0.97, L), new THREE.MeshLambertMaterial({ map: tex, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 }));
    m.rotation.x = -Math.PI / 2; const g2 = new THREE.Group(); g2.add(m); this._place(g2, 0, 0, 0.09, 0);
  }

  /* ---------- villages, woods, clouds, blimp, gates ---------- */
  _scenery() {
    const R = rng(77), q = { low: 0.4, medium: 0.8, high: 1 }[this.q] || 0.8;
    // houses
    const hg = (() => {
      const pos = [], nor = [], col = [];
      const quad = (a, b, c, d, n, k) => { for (const p of [a, b, c, a, c, d]) { pos.push(...p); nor.push(...n); col.push(...k); } };
      const W = [0.92, 0.88, 0.8], Rf = [0.55, 0.22, 0.16];
      quad([-0.5, 0, 0.5], [0.5, 0, 0.5], [0.5, 1, 0.5], [-0.5, 1, 0.5], [0, 0, 1], W); quad([0.5, 0, -0.5], [-0.5, 0, -0.5], [-0.5, 1, -0.5], [0.5, 1, -0.5], [0, 0, -1], W);
      quad([0.5, 0, 0.5], [0.5, 0, -0.5], [0.5, 1, -0.5], [0.5, 1, 0.5], [1, 0, 0], W); quad([-0.5, 0, -0.5], [-0.5, 0, 0.5], [-0.5, 1, 0.5], [-0.5, 1, -0.5], [-1, 0, 0], W);
      quad([-0.5, 1, 0.5], [0.5, 1, 0.5], [0.5, 1.6, 0], [-0.5, 1.6, 0], [0, 0.5, 1], Rf); quad([0.5, 1, -0.5], [-0.5, 1, -0.5], [-0.5, 1.6, 0], [0.5, 1.6, 0], [0, 0.5, -1], Rf);
      for (const p of [[0.5, 1, 0.5], [0.5, 1, -0.5], [0.5, 1.6, 0]]) { pos.push(...p); nor.push(1, 0, 0); col.push(...W); }
      for (const p of [[-0.5, 1, -0.5], [-0.5, 1, 0.5], [-0.5, 1.6, 0]]) { pos.push(...p); nor.push(-1, 0, 0); col.push(...W); }
      const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3)); g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3)); g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3)); return g;
    })();
    const inRoad = (x, z, pad) => { for (const r of T.ROADS) for (let i = 0; i < r.pts.length - 1; i++) if (T.distToSegment(x, z, r.pts[i][0], r.pts[i][1], r.pts[i + 1][0], r.pts[i + 1][1]) < r.w / 2 + pad) return true;
      for (let i = 0; i < T.RIVER.pts.length - 1; i++) if (T.distToSegment(x, z, T.RIVER.pts[i][0], T.RIVER.pts[i][1], T.RIVER.pts[i + 1][0], T.RIVER.pts[i + 1][1]) < T.RIVER.w / 2 + 6) return true; return false; };
    const houses = [], trees = [];
    T.VILLAGES.slice(0, 8).forEach((v, vi) => {
      const n = Math.floor(Math.PI * v.r * v.r / 2300 * q);
      for (let k = 0; k < n; k++) { const a = R() * Math.PI * 2, rr = Math.sqrt(R()) * v.r * 0.85, x = v.x + Math.cos(a) * rr, z = v.z + Math.sin(a) * rr; if (inRoad(x, z, 5)) continue; houses.push([x, z, 7 + R() * 7, 4 + R() * 2.5, 6 + R() * 5, R() * Math.PI]); }
    });
    T.WOODS.forEach(([wx, wz, wr]) => {
      if (Math.hypot(wx, wz) > 9000) return; const sp = 26 / Math.sqrt(q);
      for (let gx = -wr; gx <= wr; gx += sp) for (let gz = -wr; gz <= wr; gz += sp) { const x = wx + gx + (R() - 0.5) * sp * 0.8, z = wz + gz + (R() - 0.5) * sp * 0.8, d = Math.hypot(x - wx, z - wz); if (d > wr * 0.82 || inRoad(x, z, 8)) continue; trees.push([x, z, 3 + R() * 2.5, 8 + R() * 9]); }
    });
    const hm = new THREE.InstancedMesh(hg, new THREE.MeshLambertMaterial({ vertexColors: true }), Math.max(1, houses.length)); hm.frustumCulled = false;
    const d = new THREE.Object3D(), c = new THREE.Color();
    houses.forEach((h, i) => { d.position.set(h[0], this.heightAt(h[0], h[1]), h[1]); d.rotation.set(0, h[5], 0); d.scale.set(h[2], h[3], h[4]); d.updateMatrix(); hm.setMatrixAt(i, d.matrix); const s = 0.85 + R() * 0.3; hm.setColorAt(i, c.setRGB(s, s, s)); });
    hm.count = houses.length; hm.instanceMatrix.needsUpdate = true; if (hm.instanceColor) hm.instanceColor.needsUpdate = true; this.scene.add(hm);
    const tg = new THREE.ConeGeometry(0.5, 1, 6).translate(0, 0.5, 0);
    const tm = new THREE.InstancedMesh(tg, new THREE.MeshLambertMaterial({ color: 0xffffff }), Math.max(1, trees.length)); tm.frustumCulled = false;
    trees.forEach((t, i) => { d.position.set(t[0], this.heightAt(t[0], t[1]) - 0.5, t[1]); d.rotation.set(0, R() * 6, 0); d.scale.set(t[2], t[3], t[2]); d.updateMatrix(); tm.setMatrixAt(i, d.matrix); tm.setColorAt(i, c.setRGB(0.1 + R() * 0.1, 0.28 + R() * 0.18, 0.1 + R() * 0.08)); });
    tm.count = trees.length; tm.instanceMatrix.needsUpdate = true; if (tm.instanceColor) tm.instanceColor.needsUpdate = true; this.scene.add(tm);
    this.counts = { houses: houses.length, trees: trees.length };
  }
  _clouds() {
    const c = document.createElement('canvas'); c.width = c.height = 128; const g = c.getContext('2d'), R = rng(9);
    for (let i = 0; i < 9; i++) { const x = 40 + R() * 48, y = 50 + R() * 28, r = 18 + R() * 20, gr = g.createRadialGradient(x, y, 0, x, y, r); gr.addColorStop(0, 'rgba(255,255,255,0.55)'); gr.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128); }
    const tex = new THREE.CanvasTexture(c); this.cloudMat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false, fog: true, opacity: 0.95 });
    const R2 = rng(21), n = { low: 40, medium: 90, high: 140 }[this.q] || 90;
    for (let i = 0; i < n; i++) {
      const cx = (R2() - 0.5) * 30000, cz = (R2() - 0.5) * 30000, cy = 1100 + R2() * 700, k = 3 + Math.floor(R2() * 4);
      for (let j = 0; j < k; j++) { const s = new THREE.Sprite(this.cloudMat); const w = 350 + R2() * 550; s.scale.set(w, w * 0.55, 1); s.position.set(cx + (R2() - 0.5) * 700, cy + (R2() - 0.5) * 80, cz + (R2() - 0.5) * 700); this.scene.add(s); this.clouds.push(s); }
    }
  }
  _blimp() {
    const c = document.createElement('canvas'); c.width = 512; c.height = 1024; const g = c.getContext('2d');
    g.fillStyle = '#02022f'; g.fillRect(0, 0, 512, 1024); g.fillStyle = '#ff4c00'; g.fillRect(0, 0, 512, 60); g.fillRect(0, 964, 512, 60);
    if (this.assets.logoDark) for (const ux of [128, 384]) { g.save(); g.translate(ux, 512); g.rotate(-Math.PI / 2); const lh = 150, lw = lh * 2.5; g.drawImage(this.assets.logoDark, -lw / 2, -lh / 2, lw, lh); g.restore(); }
    const tex = new THREE.CanvasTexture(c); tex.anisotropy = 4;
    const bg = new THREE.SphereGeometry(1, 28, 18); bg.rotateX(Math.PI / 2);
    const blimp = new THREE.Group(), body = new THREE.Mesh(bg, new THREE.MeshLambertMaterial({ map: tex })); body.scale.set(8, 8, 26); blimp.add(body);
    const gon = new THREE.Mesh(new THREE.BoxGeometry(2.4, 2, 6), lam(0xdddddd)); gon.position.y = -8.8; blimp.add(gon);
    for (let k = 0; k < 4; k++) { const f = new THREE.Mesh(new THREE.BoxGeometry(0.4, 6, 7), lam(0xff4c00)); f.position.set(0, 0, 22); f.rotation.z = k * Math.PI / 2; f.position.x = Math.cos(k * Math.PI / 2) * 4; f.position.y = Math.sin(k * Math.PI / 2) * 4; blimp.add(f); }
    this.blimp = blimp; this.scene.add(blimp); this.blimpT = 0;
  }
  _gates() {
    this.gates = T.GATES.map((g, i) => ({ x: g[0], z: g[1], y: this.heightAt(g[0], g[1]) + g[2], nx: 0, nz: -1, r: 48 }));
    this.gates.forEach((g, i) => { const nx = this.gates[(i + 1) % this.gates.length]; const ref = i < this.gates.length - 1 ? nx : this.gates[i - 1]; let dx = ref.x - g.x, dz = ref.z - g.z; if (i === this.gates.length - 1) { dx = -dx; dz = -dz; } const L = Math.hypot(dx, dz); g.nx = dx / L; g.nz = dz / L; });
    this.gateGroup = new THREE.Group(); this.scene.add(this.gateGroup);
    this.gates.forEach((g, i) => {
      const grp = new THREE.Group();
      const ring = new THREE.Mesh(new THREE.TorusGeometry(g.r, 2.6, 8, 40), new THREE.MeshBasicMaterial({ color: 0xff4c00, fog: true })); grp.add(ring);
      const inner = new THREE.Mesh(new THREE.TorusGeometry(g.r - 4.5, 0.7, 6, 40), new THREE.MeshBasicMaterial({ color: 0xffffff, fog: true })); grp.add(inner);
      grp.position.set(g.x, g.y, g.z); grp.rotation.y = Math.atan2(g.nx, g.nz); this.gateGroup.add(grp); this.gateMeshes.push({ grp, ring, inner });
    });
    this.gateGroup.visible = false;
  }
  setGates(active, next) {
    this.gateGroup.visible = !!active;
    this.gateMeshes.forEach((m, i) => { const done = i < next, cur = i === next; m.ring.material.color.setHex(done ? 0x4cc283 : cur ? 0xff4c00 : 0x1b2a8a); m.grp.scale.setScalar(cur ? 1.08 : 1); m.grp.visible = !done || i >= next - 2; m.inner.visible = cur; });
  }

  /* ---------- per frame ---------- */
  update(dt, camPos) {
    this._updateRings(camPos.x, camPos.z);
    const u = this.tMat.uniforms; u.uNearC.value.set(0, 0); u.uFarC.value.set(0, 0);
    this.sky.position.copy(camPos);
    if (this.blimp) {
      this.blimpT += dt; const a = this.blimpT * 0.0125, cx = -300, cz = -900, R = 700;
      const x = cx + Math.cos(a) * R, z = cz + Math.sin(a) * R; this.blimp.position.set(x, this.heightAt(x, z) + 380 + Math.sin(this.blimpT * 0.2) * 6, z);
      this.blimp.rotation.y = Math.atan2(Math.sin(a), -Math.cos(a));       // nose (-z) along the direction of travel
    }
    if (this.windsock) { const w = this.env.wind; const ang = Math.atan2(-w[2], w[0]); if (w[0] || w[2]) this.windsock.rotation.y = ang; }
  }
}

root.SMWorld = { World, TOD };
})(window);
