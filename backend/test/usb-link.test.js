'use strict';
// Uji tautan USB memakai port serial PALSU (tanpa hardware): framing, cabut/colok kabel, perintah ke alat.
const assert = require('assert');
const fs = require('fs');
const { EventEmitter } = require('events');
const { prepareEnv, startServer, ok, count } = require('./helpers');

const dir = prepareEnv();
process.env.USB_SERIAL = 'PF-NMA-000007';       // ID bawaan untuk firmware/GPS yang tidak mengirim ID
process.env.USB_FALLBACK_LAT = '-7.77';         // koordinat tetap untuk prototipe tanpa modul GPS
process.env.USB_FALLBACK_LNG = '110.37';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (fn, ms = 3000) => { const t = Date.now(); while (Date.now() - t < ms) { if (await fn()) return true; await sleep(15); } return false; };
const checksum = (b) => { let x = 0; for (const c of b) x ^= c.charCodeAt(0); return x.toString(16).toUpperCase().padStart(2, '0'); };
const nmea = (b) => `$${b}*${checksum(b)}`;

/** Port serial palsu: test mengendalikan 'open'/'data'/'close' dan membaca semua yang ditulis server. */
class FakePort extends EventEmitter {
  constructor() { super(); this.written = []; this.closed = false; }
  write(s) { if (this.closed) throw new Error('port tertutup'); this.written.push(s); }
  close() { if (!this.closed) { this.closed = true; this.emit('close'); } }
  open() { setImmediate(() => this.emit('open')); return this; }
  say(text) { this.emit('data', Buffer.from(text)); }
}

(async () => {
  const S = await startServer();
  const { call, store } = S;
  const { createUsbLink } = require('../src/server');
  const login = await call('POST', '/api/auth/login', { email: 'qa@pawfinder.test', password: 'Rahasia123' });
  S.token = login.body.token;
  const mk = async (name, serial) => {
    const p = (await call('POST', '/api/pets', { name, species: 'anjing', gender: 'jantan', birthDate: '2023-01-01' })).body.pet;
    await call('POST', `/api/pets/${p.id}/device/pair`, { serial });
    return p;
  };
  const view = async (p) => (await call('GET', `/api/pets/${p.id}`)).body.pet;
  const bruno = await mk('Bruno', 'PF-USB-000001');
  const luna = await mk('Luna', 'PF-NMA-000007');

  const ports = [];
  let portsAvailable = false;
  const lister = async () => (portsAvailable ? [{ path: 'COM7', vendorId: '2341', manufacturer: 'Arduino LLC' }] : []);
  const opener = ({ path }) => { const p = new FakePort(); p.path = path; ports.push(p); return p.open(); };
  const logs = [];
  const link = createUsbLink(store, { opener, lister, path: 'auto', log: (m) => logs.push(m), link: { backoffMs: [30, 30, 30], whoDelayMs: 40 } });
  link.start();

  console.log('\n[Deteksi port otomatis]');
  assert.ok(await until(() => link.lastError && /belum terdeteksi/.test(link.lastError)));
  assert.equal(link.state, 'disconnected'); ok('tanpa Arduino: pesan jelas "belum terdeteksi", terus mencoba');
  assert.equal((await call('GET', '/api/usb/status')).body.usb.state, 'disconnected'); ok('status ini tampil di /api/usb/status');
  portsAvailable = true;
  assert.ok(await until(() => link.state === 'connected')); assert.equal(link.path, 'COM7'); ok('Arduino dicolok -> terdeteksi otomatis (VID 2341) dan tersambung');
  let port = ports[ports.length - 1];
  assert.ok(await until(() => port.written.includes('WHO\n'))); ok('server menanyakan identitas alat (WHO) setelah terhubung');

  console.log('\n[Aliran data JSON lewat kabel]');
  port.say('PawFinder collar v1.0 booting...\r\n');          // teks bebas dari firmware: tidak boleh merusak apa pun
  port.say('{"hello":"PF-USB-000001","fw":"1.0.3"}\r\n');
  assert.ok(await until(async () => (await view(bruno)).device.connection === 'online')); ok('"hello" dari Arduino -> alat langsung online');
  assert.equal((await view(bruno)).device.source, 'usb'); assert.equal((await view(bruno)).device.firmware, '1.0.3'); ok('sumber tercatat USB, versi firmware terbaca');
  assert.ok(await until(() => port.written.includes('INTERVAL 30\n'))); ok('interval dari aplikasi disinkronkan ke firmware (INTERVAL 30)');
  const half = '{"serial":"PF-USB-000001","lat":-7.71556,"lng":110.35547,"fix":1,"bat":81,"sig":"Kuat","hr":97,"temp":38.7,"sat":9}';
  port.say(half.slice(0, 40)); await sleep(10); port.say(half.slice(40) + '\n');       // baris terpotong antar-chunk
  assert.ok(await until(async () => (await view(bruno)).location !== null));
  let v = await view(bruno);
  assert.equal(v.device.battery, 81); assert.equal(v.device.gpsFix, true); assert.equal(v.device.satellites, 9); ok('baris yang terpotong di tengah tetap utuh dan terbaca');
  assert.equal((await call('GET', `/api/pets/${bruno.id}/health`)).body.health.sensor.heartRate, 97); ok('sensor detak jantung & suhu ikut masuk');
  const parseErrBefore = link.parseErrors;
  port.say('@@garbage@@\n{"serial":"PF-USB-000001","lat":}\n\n\n');
  await sleep(50);
  assert.equal(link.parseErrors, parseErrBefore + 2); assert.equal(link.state, 'connected'); assert.equal((await view(bruno)).device.connection, 'online'); ok('baris sampah/JSON rusak dihitung sebagai salah-format tanpa memutus koneksi');
  assert.ok(link.status().lastUnknown); ok('contoh baris tak dikenal tersedia untuk diagnosis');

  console.log('\n[Batas laju paket]');
  const pk = (lat) => `{"serial":"PF-USB-000001","lat":${lat},"lng":110.35547,"bat":80}\n`;
  await sleep(850);
  port.say(pk(-7.7150)); await sleep(30); port.say(pk(-7.7140)); port.say(pk(-7.7130)); await sleep(60);
  assert.ok(Math.abs((await view(bruno)).location.lat - -7.715) < 1e-6); ok('banjir paket cepat: hanya yang pertama diproses, sisanya dibatasi (server aman)');

  console.log('\n[Perintah server -> alat]');
  let r = await call('POST', `/api/pets/${bruno.id}/device/ping`); assert.equal(r.status, 200);
  assert.ok(await until(() => port.written.includes('PING\n'), 2000)); ok('tombol "Bunyikan Kalung" menulis PING ke kabel USB dalam < 1 detik');
  assert.equal(port.written.filter((x) => x === 'PING\n').length, 1); ok('perintah tidak terkirim dobel');
  await call('PUT', `/api/pets/${bruno.id}/device`, { intervalSec: 60 });
  assert.ok(await until(() => port.written.includes('INTERVAL 60\n'), 2000)); ok('ubah interval di aplikasi -> INTERVAL 60 terkirim ke Arduino');
  port.say('{"ack":"PING"}\n'); await sleep(20); assert.equal(link.state, 'connected'); ok('ACK dari alat diterima');

  console.log('\n[NMEA mentah dari modul GPS + ID bawaan]');
  await sleep(850);
  port.say(nmea('GPGGA,123519,0746.5000,S,11022.2000,E,1,07,1.1,50.0,M,0.0,M,,') + '\r\n');
  assert.ok(await until(async () => (await view(luna)).location !== null));
  v = await view(luna); assert.ok(Math.abs(v.location.lat - -7.775) < 1e-6 && Math.abs(v.location.lng - 110.37) < 1e-6); assert.equal(v.device.connection, 'online'); ok('NMEA tanpa ID: dikenali lewat USB_SERIAL, koordinat dikonversi benar');
  await sleep(850);
  port.say(nmea('GPGGA,123520,,,,,0,00,99.9,,M,,M,,') + '\r\n');
  assert.ok(await until(async () => (await view(luna)).device.gpsFix === true && (await call('GET', `/api/pets/${luna.id}/device/live`)).body.live.locationMode === 'tetap')); ok('prototipe tanpa fix GPS memakai koordinat tetap (USB_FALLBACK_LAT/LNG) dan ditandai "tetap"');
  port.say(nmea('GPGSV,3,1,11,03,03,111,00') + '\r\n' + '$GPGGA,1,2,3*00\r\n'); await sleep(30);
  assert.equal(link.state, 'connected'); ok('kalimat NMEA lain & checksum salah tidak merusak koneksi');

  console.log('\n[Kabel dicabut & dicolok]');
  const reopenCount = ports.length;
  port.close();
  assert.ok(await until(async () => (await view(bruno)).device.connection === 'offline', 1500)); ok('kabel dicabut -> alat LANGSUNG offline (tanpa menunggu batas waktu)');
  assert.ok((await call('GET', '/api/notifications')).body.notifications.some((n) => n.type === 'gps_offline')); ok('notifikasi "Koneksi GPS terputus" dibuat');
  assert.equal(link.state, 'disconnected');
  assert.ok(await until(() => link.state === 'connected' && ports.length > reopenCount)); ok('kabel dicolok lagi -> tersambung ulang otomatis');
  port = ports[ports.length - 1];
  await sleep(850);
  port.say(pk(-7.7155));
  assert.ok(await until(async () => (await view(bruno)).device.connection === 'online')); ok('data mengalir lagi -> online kembali');
  assert.ok((await call('GET', '/api/notifications')).body.notifications.some((n) => n.title.includes('tersambung kembali'))); ok('notifikasi "Koneksi GPS tersambung kembali"');

  port.emit('error', new Error('read EIO'));
  assert.ok(await until(() => link.state === 'disconnected')); assert.ok(await until(() => link.state === 'connected')); ok('error baca (EIO) saat kabel goyah -> pulih sendiri');
  port = ports[ports.length - 1];

  console.log('\n[Alat belum dipasangkan]');
  port.say('{"hello":"PF-NEW-123456","fw":"2.0"}\n'); await sleep(60);
  r = await call('GET', '/api/devices/discovered'); assert.ok(r.body.devices.some((d) => d.serial === 'PF-NEW-123456' && d.source === 'usb')); ok('alat baru yang dicolok muncul di daftar "terdeteksi" (untuk dipasangkan dari aplikasi)');
  assert.equal(link.status().lastReject.code, 'UNPAIRED'); ok('status USB menjelaskan penyebab: UNPAIRED');

  console.log('\n[Gangguan konfigurasi]');
  const { UsbLink } = require('../src/services/usb-link');
  const noDriver = new UsbLink({ path: 'COM3', opener: null, lister, onMessage: () => ({}), backoffMs: [20] }).start();
  assert.ok(await until(() => /serialport/.test(noDriver.lastError || ''))); noDriver.stop(); ok('driver serial tidak terpasang -> pesan "npm install serialport"');
  const badOpen = new UsbLink({ path: 'COM9', opener: () => { throw new Error('Access denied'); }, lister, onMessage: () => ({}), backoffMs: [20] }).start();
  assert.ok(await until(() => /Access denied/.test(badOpen.lastError || ''))); badOpen.stop(); ok('port dipakai program lain (Arduino IDE terbuka) -> pesan jelas, tidak crash');
  const multi = new UsbLink({ path: 'auto', opener, lister: async () => [{ path: 'COM1' }, { path: 'COM2' }], onMessage: () => ({}), backoffMs: [20] }).start();
  assert.ok(await until(() => /beberapa port/.test(multi.lastError || ''))); multi.stop(); ok('beberapa port non-Arduino -> minta USB_PORT eksplisit, tidak menebak');
  let slow = 0;
  const slowLink = new UsbLink({ path: 'COM5', opener: () => { const p = new FakePort(); ports.push(p); slow = ports.length - 1; return p.open(); }, lister, onMessage: () => new Promise((r) => setTimeout(r, 400)), backoffMs: [20] }).start();
  assert.ok(await until(() => slowLink.state === 'connected'));
  for (let i = 0; i < 60; i++) ports[slow].say(`{"serial":"PF-USB-000001","bat":${i}}\n`);
  await sleep(30); assert.ok(slowLink.dropped > 0); slowLink.stop(); ok('penerima lambat: paket berlebih dibuang, memori tidak menumpuk');

  link.stop();
  await S.close();
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(`\nSemua tes tautan USB lulus (${count()} pemeriksaan).`);
  process.exit(0);
})().catch((e) => { console.error('\nTES GAGAL:', e); process.exit(1); });
