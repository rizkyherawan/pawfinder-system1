#!/usr/bin/env node
'use strict';
/**
 * Bridge USB -> server PawFinder.
 *
 * Dipakai bila Arduino dicolok ke komputer LAIN (mis. laptop/Raspberry Pi di lab) sedangkan backend
 * berjalan di komputer/server berbeda. Bridge membaca baris dari kabel USB lalu mengirimnya ke
 * POST /api/device/telemetry, dan menyampaikan perintah dari aplikasi (mis. "bunyikan") ke Arduino.
 *
 * Contoh:
 *   node tools/usb-bridge.js --server http://192.168.1.10:4000 --key KUNCI_DEVICE --port auto
 *   node tools/usb-bridge.js --server http://localhost:4000 --port COM3 --serial PF-ABC-123456
 *   node tools/emulate-arduino.js --serial PF-ABC-123456 | node tools/usb-bridge.js --stdin   (tanpa hardware)
 *
 * Opsi: --server --key --port(auto|COM3|/dev/ttyACM0) --baud(9600) --serial(ID bila firmware tidak mengirim)
 *       --lat --lng (koordinat tetap untuk prototipe tanpa modul GPS) --stdin --verbose
 */
const { EventEmitter } = require('events');
const { UsbLink } = require('../src/services/usb-link');
const { createOpener, listPorts } = require('../src/services/serial-io');
const { normalizeSerial } = require('../src/services/device-protocol');

const argv = process.argv.slice(2);
const opt = (name, def) => { const i = argv.indexOf(`--${name}`); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : def; };
const flag = (name) => argv.includes(`--${name}`);

if (flag('help') || flag('h')) {
  console.log(require('fs').readFileSync(__filename, 'utf8').split('*/')[0].replace(/^#!.*\n/, '').replace(/^\/\*\*?|^ \* ?/gm, ''));
  process.exit(0);
}

const server = String(opt('server', process.env.PAWFINDER_SERVER || 'http://localhost:4000')).replace(/\/+$/, '');
const key = opt('key', process.env.DEVICE_KEY || 'pawfinder-device-key');
const portSpec = opt('port', process.env.USB_PORT || 'auto');
const baud = Number(opt('baud', process.env.USB_BAUD || 9600));
const defaultSerial = opt('serial', process.env.USB_SERIAL || '').toUpperCase();
const fbLat = opt('lat', process.env.USB_FALLBACK_LAT);
const fbLng = opt('lng', process.env.USB_FALLBACK_LNG);
const verbose = flag('verbose');

if (defaultSerial && !normalizeSerial(defaultSerial)) {
  console.error(`ID alat "${defaultSerial}" tidak valid. Format: PF-XXX-000000 (contoh PF-ABC-123456)`);
  process.exit(1);
}
if (typeof fetch !== 'function') { console.error('Butuh Node.js 18 atau lebih baru.'); process.exit(1); }

/** Port palsu yang membaca stdin: untuk uji tanpa hardware. */
function stdinOpener() {
  const ee = new EventEmitter();
  process.nextTick(() => {
    process.stdin.on('data', (b) => ee.emit('data', b));
    process.stdin.on('end', () => { console.log('[bridge] stdin selesai.'); setTimeout(() => process.exit(0), 1500); });
    ee.emit('open');
  });
  ee.write = () => {};
  ee.close = () => {};
  return ee;
}

let lastNote = '';
const note = (s) => { if (s !== lastNote) { lastNote = s; console.log(s); } };
let sent = 0, accepted = 0;

function toBody(msg, meta) {
  const base = { serial: msg.serial || defaultSerial || undefined, via: 'usb', port: meta.port || undefined };
  if (fbLat !== undefined && fbLng !== undefined) { base.fallbackLat = Number(fbLat); base.fallbackLng = Number(fbLng); }
  if (msg.kind === 'hello') return { ...base, hello: base.serial || true, fw: msg.firmware };
  if (msg.kind === 'ack') return { ...base, ack: msg.command };
  const { kind, ...rest } = msg;
  return { ...base, ...rest };
}

async function post(msg, meta) {
  const body = toBody(msg, meta);
  sent++;
  const res = await fetch(`${server}/api/device/telemetry`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-device-key': key },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(8000),
  });
  let data = {};
  try { data = await res.json(); } catch (_) { /* abaikan */ }
  if (res.status === 401) { console.error('\n[bridge] DEVICE_KEY ditolak server (401). Samakan --key dengan DEVICE_KEY di backend/.env.\n'); process.exit(2); }
  if (!res.ok) {
    note(`[bridge] server menolak: ${res.status} ${data.code || ''} ${data.error || ''}`.trim() + (data.code === 'NO_SERIAL' ? '  -> tambahkan opsi --serial PF-XXX-000000 (sentence NMEA tidak membawa ID alat)' : ''));
    return { ok: false, code: data.code, error: data.error, commands: [] };
  }
  accepted++;
  note(`[bridge] server OK${data.fix === false ? ' · alat hidup, GPS belum fix (cari satelit)' : ''}${data.locationMode === 'tetap' ? ' · memakai koordinat tetap' : ''}`);
  if (verbose) console.log(`[bridge] #${sent} ${JSON.stringify(body)} -> ${res.status}`);
  return { ok: true, commands: data.commands || [] };
}

const opener = flag('stdin') ? stdinOpener : createOpener().opener;
if (!opener) {
  console.error('Driver serial tidak ditemukan. Jalankan:  npm install serialport   (di folder backend)');
  process.exit(1);
}

const link = new UsbLink({
  path: flag('stdin') ? 'stdin' : portSpec, baud, opener, lister: listPorts, defaultSerial, whoDelayMs: 1800,
  log: (m) => console.log(m),
  onMessage: (msg, meta) => post(msg, meta),
}).start();

// Saat alat diam, tetap ambil perintah dari server (mis. tombol "Bunyikan Kalung").
setInterval(async () => {
  for (const sn of link.serials) {
    try {
      const r = await fetch(`${server}/api/device/commands?serial=${encodeURIComponent(sn)}`, { headers: { 'x-device-key': key }, signal: AbortSignal.timeout(5000) });
      if (r.ok) { const d = await r.json(); if (d.commands && d.commands.length) link._sendCommands(d.commands); }
    } catch (_) { /* server sedang tidak terjangkau */ }
  }
}, 1500).unref();

setInterval(() => {
  const s = link.status();
  console.log(`[bridge] usb=${s.state}${s.path ? ` ${s.path}` : ''} baris=${s.lines} salah-format=${s.parseErrors} terkirim=${sent} diterima-server=${accepted}${s.lastError ? ` · ${s.lastError}` : ''}${s.lastUnknown ? ` · contoh baris tak dikenal: "${s.lastUnknown.line}"` : ''}`);
}, 10000).unref();

console.log(`[bridge] PawFinder USB bridge -> ${server}  (port: ${flag('stdin') ? 'stdin' : portSpec}, ${baud} baud)  Ctrl+C untuk berhenti.`);
const stop = () => { link.stop(); process.exit(0); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
