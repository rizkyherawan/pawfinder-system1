#!/usr/bin/env node
'use strict';
/**
 * Emulator Arduino: mencetak baris protokol PawFinder ke stdout, persis seperti firmware di kalung.
 * Dipakai untuk menguji bridge/aplikasi TANPA hardware:
 *   node tools/emulate-arduino.js --serial PF-ABC-123456 --format json --mode circle | node tools/usb-bridge.js --stdin
 *
 * Opsi: --serial --format(json|csv|nmea) --mode(circle|exit|nofix) --interval ms --lat --lng --pure(NMEA tanpa pendamping)
 */
process.stdout.on('error', (e) => { if (e.code === 'EPIPE') process.exit(0); });
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(`--${n}`); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const serial = opt('serial', 'PF-EMU-000001');
const format = opt('format', 'json');
const mode = opt('mode', 'circle');
const interval = Number(opt('interval', 1000));
const pure = argv.includes('--pure'); // NMEA murni tanpa baris pendamping (seperti modul GPS yang dicolok langsung)
const HOME = { lat: Number(opt('lat', -7.71556)), lng: Number(opt('lng', 110.35547)) };
const M = 111320;
let t = 0, battery = 90;

const checksum = (b) => { let x = 0; for (const c of b) x ^= c.charCodeAt(0); return x.toString(16).toUpperCase().padStart(2, '0'); };
const nmeaCoord = (v, deg) => { const a = Math.abs(v), d = Math.floor(a), m = (a - d) * 60; return `${String(d).padStart(deg, '0')}${m.toFixed(4).padStart(7, '0')}`; };
const nmea = (b) => `$${b}*${checksum(b)}`;

function pos() {
  t++;
  if (mode === 'exit') { const phase = t % 60, d = phase < 30 ? (phase / 30) * 700 : ((60 - phase) / 30) * 700; return { lat: HOME.lat, lng: HOME.lng + d / M }; }
  return { lat: HOME.lat + (80 / M) * Math.sin(t / 6), lng: HOME.lng + (80 / M) * Math.cos(t / 6) };
}

if (format === 'json') console.log(JSON.stringify({ hello: serial, fw: 'emu-1.0' }));
else if (format === 'csv') console.log(`PF,HELLO,${serial},emu-1.0`);

setInterval(() => {
  const p = pos();
  if (t % 20 === 0) battery = Math.max(5, battery - 1);
  const fix = mode !== 'nofix';
  if (format === 'csv') console.log(`PF,${serial},${fix ? p.lat.toFixed(6) : 0},${fix ? p.lng.toFixed(6) : 0},${battery},${fix ? 1 : 0},${95 + (t % 5)},38.6,${fix ? 7 : 0}`);
  else if (format === 'nmea') {
    const ns = p.lat < 0 ? 'S' : 'N', ew = p.lng < 0 ? 'W' : 'E';
    console.log(fix ? nmea(`GPGGA,123519,${nmeaCoord(p.lat, 2)},${ns},${nmeaCoord(p.lng, 3)},${ew},1,07,0.9,50.0,M,0.0,M,,`) : nmea('GPGGA,123519,,,,,0,00,99.9,,M,,M,,'));
    if (!pure) console.log(`PF,${serial},,,${battery},${fix ? 1 : 0}`); // NMEA tidak membawa ID/baterai: baris CSV pendamping
  } else console.log(JSON.stringify({ serial, ...(fix ? { lat: +p.lat.toFixed(6), lng: +p.lng.toFixed(6) } : {}), fix: fix ? 1 : 0, bat: battery, sig: 'Kuat', hr: 95 + (t % 5), temp: 38.6, sat: fix ? 7 : 0 }));
}, interval);
