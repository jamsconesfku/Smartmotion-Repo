#!/usr/bin/env node
// SmartMotion Flight telemetry bridge (no dependencies, Node 18+).
//   node tools/telemetry-bridge.mjs [--port 8765] [--udp 127.0.0.1:4123] [--log]
// The game (in the browser) connects here over WebSocket and sends one JSON frame about 60 times a second.
// This program prints a live readout and can forward each frame as UDP JSON to whatever drives the rig
// (for example a small plug-in or script feeding FlyPT Mover). See docs/games/smartmotion-flight.md.
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { createSocket } from "node:dgram";

const arg = (n, d) => { const i = process.argv.indexOf("--" + n); return i > -1 ? process.argv[i + 1] : d; };
const port = +arg("port", 8765), udp = arg("udp", ""), log = process.argv.includes("--log");
const sock = udp ? createSocket("udp4") : null; const [uh, up] = udp ? udp.split(":") : [];
let frames = 0, last = null, clients = 0;

const server = createServer((req, res) => { res.writeHead(200, { "content-type": "text/plain" }); res.end("SmartMotion Flight telemetry bridge: connect with a WebSocket (ws://this-address:" + port + ")\n"); });
server.on("upgrade", (req, socket) => {
  const key = req.headers["sec-websocket-key"]; if (!key) return socket.destroy();
  socket.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + createHash("sha1").update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64") + "\r\n\r\n");
  clients++; console.log("game connected (" + clients + " client" + (clients > 1 ? "s" : "") + ")");
  let buf = Buffer.alloc(0);
  socket.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      const op = buf[0] & 15, masked = (buf[1] & 128) !== 0; let len = buf[1] & 127, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; } else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (buf.length < off + (masked ? 4 : 0) + len) return;
      const mask = masked ? buf.subarray(off, off + 4) : null; off += masked ? 4 : 0;
      const data = Buffer.from(buf.subarray(off, off + len)); buf = buf.subarray(off + len);
      if (mask) for (let i = 0; i < data.length; i++) data[i] ^= mask[i & 3];
      if (op === 8) return socket.end(); if (op === 9) { socket.write(Buffer.from([0x8a, 0])); continue; } if (op !== 1) continue;
      frames++; const txt = data.toString("utf8"); try { last = JSON.parse(txt); } catch { continue; }
      if (sock) sock.send(txt, +up, uh); if (log) console.log(txt);
    }
  });
  socket.on("close", () => { clients--; console.log("game disconnected"); }); socket.on("error", () => {});
});
server.listen(port, () => console.log("Telemetry bridge listening on ws://localhost:" + port + (udp ? "  and forwarding UDP to " + udp : "") + "\nIn the game: Settings > Send flight data. Press Ctrl+C to stop."));
let prev = 0; setInterval(() => {
  if (!last) return; const f = last, n = frames - prev; prev = frames;
  process.stdout.write(`\r${String(n).padStart(3)} fps  pitch ${f.att.pitch_deg.toFixed(1).padStart(6)}  roll ${f.att.roll_deg.toFixed(1).padStart(6)}  yawrate ${f.rate.yaw_dps.toFixed(1).padStart(6)}  surge ${f.g_felt.surge.toFixed(2)}g sway ${f.g_felt.sway.toFixed(2)}g heave ${f.g_felt.heave.toFixed(2)}g  ias ${String(f.ias_kt).padStart(4)}kt   `);
}, 1000);
