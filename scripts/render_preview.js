// Renders a design preview PNG with three.js in headless Chromium.
// Usage: node scripts/render_preview.js <mesh.json> <out.png>
// mesh.json: {"parts":[{"name":..., "positions":[x,y,z, ...]}]}  (millimetres, Z up)
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const [inp, out] = process.argv.slice(2);
  const mesh = JSON.parse(fs.readFileSync(inp, 'utf8'));
  const b = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-webgl', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 900, height: 680 }, deviceScaleFactor: 1 });
  await p.setContent('<html><body style="margin:0;background:transparent"></body></html>');
  await p.addScriptTag({ path: path.join(__dirname, '..', 'dashboard', 'vendor', 'three.min.js') });
  await p.evaluate((mesh) => {
    const W = 900, H = 680;
    const r = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
    r.setSize(W, H); r.setClearColor(0x000000, 0); r.shadowMap.enabled = true; r.shadowMap.type = THREE.PCFSoftShadowMap;
    document.body.appendChild(r.domElement);
    const scene = new THREE.Scene();
    const group = new THREE.Group(); group.rotation.x = -Math.PI / 2; scene.add(group);
    let off = 0;
    for (const part of mesh.parts) {
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(part.positions, 3));
      g.computeBoundingBox();
      const bb = g.boundingBox;
      g.translate(off - bb.min.x, -(bb.min.y + bb.max.y) / 2, -bb.min.z);
      off += (bb.max.x - bb.min.x) + 18;
      g.computeVertexNormals();
      const m = new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color: 0xff4c00, roughness: 0.55, metalness: 0.05 }));
      m.castShadow = true; m.receiveShadow = true; group.add(m);
      const e = new THREE.LineSegments(new THREE.EdgesGeometry(g, 35), new THREE.LineBasicMaterial({ color: 0x5a1c00, transparent: true, opacity: 0.55 }));
      group.add(e);
    }
    const box = new THREE.Box3().setFromObject(group), size = box.getSize(new THREE.Vector3()), ctr = box.getCenter(new THREE.Vector3());
    group.position.sub(new THREE.Vector3(ctr.x, box.min.y, ctr.z));
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(4000, 4000), new THREE.ShadowMaterial({ opacity: 0.18 }));
    ground.rotation.x = -Math.PI / 2; ground.receiveShadow = true; scene.add(ground);
    scene.add(new THREE.HemisphereLight(0xffffff, 0x2a2f72, 0.75));
    const sun = new THREE.DirectionalLight(0xffffff, 0.85);
    const R = Math.max(size.x, size.y, size.z);
    sun.position.set(-R * 0.8, R * 2, R * 1.2); sun.castShadow = true;
    Object.assign(sun.shadow.camera, { left: -R * 1.5, right: R * 1.5, top: R * 1.5, bottom: -R * 1.5, near: 1, far: R * 8 });
    sun.shadow.mapSize.set(2048, 2048); scene.add(sun);
    const cam = new THREE.PerspectiveCamera(30, W / H, 1, R * 20);
    const dir = new THREE.Vector3(1.0, 0.85, 1.25).normalize();
    const radius = Math.sqrt(size.x * size.x + size.y * size.y + size.z * size.z) / 2;
    const dist = radius / Math.sin((30 * Math.PI / 180) / 2) * 1.02;
    const target = new THREE.Vector3(0, size.y * 0.45, 0);
    cam.position.copy(target).addScaledVector(dir, dist); cam.lookAt(target);
    r.render(scene, cam);
  }, mesh);
  await p.locator('canvas').screenshot({ path: out, omitBackground: true });
  await b.close();
})();
