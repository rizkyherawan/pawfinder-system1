#!/usr/bin/env node
'use strict';
/**
 * Simulator kalung GPS: mengirim telemetri ke POST /api/device/telemetry seperti perangkat IoT asli.
 *
 * Pasangkan nomor seri lebih dulu di aplikasi (Hubungkan GPS), lalu jalankan:
 * Contoh:
 *   node tools/simulate-device.js --serial PF-ABC-123456 --mode exit
 *   node tools/simulate-device.js --serial PF-DEF-654321 --mode circle --interval 1500
 *
 * Mode:
 *   circle : berputar di dalam area aman rumah
 *   exit   : berjalan menjauh dari rumah sampai keluar geofence (memicu notifikasi), lalu pulang
 */
const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, arr) => (v.startsWith('--') ? [...a, [v.slice(2), arr[i + 1]]] : a), []));
const base = (args.url || 'http://localhost:4000').replace(/\/$/, '');
const key = args.key || process.env.DEVICE_KEY || 'pawfinder-device-key';
const serial = args.serial;
const mode = args.mode || 'exit';
const interval = Number(args.interval || 2000);
const HOME = { lat: Number(args.lat || -7.71556), lng: Number(args.lng || 110.35547) };

if (!serial) {
  console.error('Wajib: --serial <nomor seri kalung>, contoh: --serial PF-ABC-123456');
  process.exit(1);
}

const M_PER_DEG = 111320;
let t = 0, battery = Number(args.battery || 80);

function position() {
  t += 1;
  if (mode === 'circle') {
    const r = 80;
    return { lat: HOME.lat + (r / M_PER_DEG) * Math.sin(t / 6), lng: HOME.lng + (r / M_PER_DEG) * Math.cos(t / 6) };
  }
  // exit: bolak-balik 0 -> 700 m -> 0 ke arah timur
  const cycle = 60, phase = t % cycle;
  const dist = phase < cycle / 2 ? (phase / (cycle / 2)) * 700 : ((cycle - phase) / (cycle / 2)) * 700;
  return { lat: HOME.lat, lng: HOME.lng + dist / M_PER_DEG };
}

async function send() {
  const p = position();
  if (t % 15 === 0) battery = Math.max(5, battery - 1);
  try {
    const res = await fetch(`${base}/api/device/telemetry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-device-key': key },
      body: JSON.stringify({ serial, lat: p.lat, lng: p.lng, battery, signal: 'Kuat' }),
    });
    const body = await res.json();
    console.log(`#${t} ${p.lat.toFixed(5)},${p.lng.toFixed(5)} bat=${battery}% -> ${res.status} ${body.error || (body.insideGeofence ? 'di dalam area aman' : 'DI LUAR area aman')}`);
  } catch (e) {
    console.error('Gagal terhubung:', e.message);
  }
}

console.log(`Simulator ${serial} (${mode}) -> ${base}, interval ${interval} ms. Ctrl+C untuk berhenti.`);
send();
setInterval(send, interval);
