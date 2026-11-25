'use strict';
// Uji end-to-end API: server asli di port acak dengan database sementara.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { prepareEnv, startServer, ok, count } = require('./helpers');

const dir = prepareEnv();
const DEVKEY = { 'x-device-key': 'pawfinder-device-key' };
const QA = { email: 'qa@pawfinder.test', password: 'Rahasia123' };

(async () => {
  const S = await startServer();
  const { call, store } = S;
  const { syncAllConnections } = require('../src/services/engine');
  let r;

  // =====================================================================
  console.log('\n[Sistem & keamanan dasar]');
  r = await call('GET', '/api/ping'); assert.equal(r.status, 200); assert.equal(r.body.version, '1.4.0'); ok('ping');
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff'); assert.equal(r.headers.get('cache-control'), 'no-store'); ok('header keamanan pada respons API');
  r = await call('GET', '/api/tidak-ada'); assert.equal(r.status, 404); ok('endpoint tidak ada -> 404');
  r = await call('DELETE', '/api/ping'); assert.equal(r.status, 405); ok('metode salah pada endpoint yang ada -> 405');
  r = await call('POST', '/api/auth/login', '{rusak'); assert.equal(r.status, 400); ok('JSON rusak -> 400');
  r = await call('POST', '/api/auth/login', 'null'); assert.equal(r.status, 400); ok('body "null" -> 400 (dulu 500)');
  r = await call('POST', '/api/auth/login', '[1,2]'); assert.equal(r.status, 400); ok('body array -> 400');
  r = await call('GET', '/api/pets/%E0%A4%A'); assert.ok(r.status === 400 || r.status === 401); ok('URL dengan % rusak tidak membuat server error');
  r = await call('GET', '/api/%E0%A4%A/x', undefined); assert.ok(r.status === 404 || r.status === 400); ok('path rusak ditangani');
  r = await call('POST', '/api/auth/register', 'x'.repeat(1_100_000)); assert.equal(r.status, 413); ok('body > 1 MB ditolak (413)');
  assert.ok(!fs.existsSync(path.join(dir, '..', 'jwt.secret')) || true); assert.ok(fs.existsSync(path.join(dir, 'jwt.secret'))); ok('rahasia JWT dibuat otomatis (bukan nilai bawaan di kode)');

  // =====================================================================
  console.log('\n[Daftar & masuk: pesan "wajib diisi"]');
  r = await call('POST', '/api/auth/login', {}); assert.equal(r.status, 422); assert.equal(r.body.error, 'Email wajib diisi'); assert.equal(r.body.field, 'email'); ok('login tanpa email -> "Email wajib diisi"');
  r = await call('POST', '/api/auth/login', { email: QA.email }); assert.equal(r.status, 422); assert.equal(r.body.error, 'Kata sandi wajib diisi'); assert.equal(r.body.field, 'password'); ok('login tanpa password -> "Kata sandi wajib diisi"');
  r = await call('POST', '/api/auth/login', { email: QA.email, password: '   ' }); assert.equal(r.status, 401); ok('password hanya spasi dianggap password (salah), bukan lolos');
  r = await call('POST', '/api/auth/login', { email: 'tidak@ada.com', password: 'apasaja123' }); assert.equal(r.status, 401); assert.equal(r.body.error, 'Email atau kata sandi salah'); ok('email tidak terdaftar -> pesan sama dengan password salah (tidak membocorkan akun)');
  r = await call('POST', '/api/auth/register', { email: 'a@b.co', password: 'Abcdefg1' }); assert.equal(r.body.error, 'Nama wajib diisi'); ok('daftar tanpa nama');
  r = await call('POST', '/api/auth/register', { name: 'A', email: 'a@b.co', password: 'Abcdefg1' }); assert.equal(r.body.error, 'Nama minimal 2 karakter'); ok('nama 1 huruf');
  r = await call('POST', '/api/auth/register', { name: 'Budi', password: 'Abcdefg1' }); assert.equal(r.body.error, 'Email wajib diisi'); ok('daftar tanpa email');
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'bukan-email', password: 'Abcdefg1' }); assert.equal(r.body.error, 'Format email tidak valid'); ok('format email salah');
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'budi@email.com' }); assert.equal(r.body.error, 'Kata sandi wajib diisi'); assert.equal(r.body.field, 'password'); ok('daftar tanpa password -> "Kata sandi wajib diisi"');
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'budi@email.com', password: 'abc1' }); assert.equal(r.body.error, 'Kata sandi minimal 8 karakter'); ok('password terlalu pendek');
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'budi@email.com', password: 'abcdefghij' }); assert.equal(r.body.error, 'Kata sandi harus mengandung huruf dan angka'); ok('password tanpa angka');
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'budi@email.com', password: '12345678' }); assert.equal(r.body.error, 'Kata sandi harus mengandung huruf dan angka'); ok('password tanpa huruf');
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'budi@email.com', password: 'a1'.repeat(80) }); assert.equal(r.status, 422); ok('password > 128 karakter ditolak');
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: QA.email.toUpperCase(), password: 'Abcdefg1' }); assert.equal(r.status, 409); ok('email ganda (beda huruf besar) -> 409');

  // Batas percobaan login (anti brute-force) memakai email khusus agar tidak mengganggu uji lain
  for (let i = 0; i < 5; i++) { r = await call('POST', '/api/auth/login', { email: 'brute@force.com', password: 'salah12345' }); assert.equal(r.status, 401); }
  r = await call('POST', '/api/auth/login', { email: 'brute@force.com', password: 'salah12345' }); assert.equal(r.status, 429); assert.ok(r.body.retryAfterSec > 0); ok('5 kali gagal login -> diblokir sementara (429)');
  r = await call('POST', '/api/auth/login', { email: 'brute@force.com', password: 'salah12345' }); assert.equal(r.status, 429); ok('tetap diblokir pada percobaan berikutnya');

  r = await call('POST', '/api/auth/login', { email: QA.email, password: 'salah12345' }); assert.equal(r.status, 401); ok('login password salah ditolak');
  r = await call('POST', '/api/auth/login', { email: `  ${QA.email.toUpperCase()}  `, password: QA.password }); assert.equal(r.status, 200); S.token = r.body.token; ok('login akun awal (email di-trim & tidak peka huruf besar)');
  r = await call('PUT', '/api/auth/me', { name: 'A' }); assert.equal(r.status, 422); ok('ubah nama < 2 karakter ditolak');
  r = await call('PUT', '/api/auth/me', { name: '   ' }); assert.equal(r.status, 422); assert.equal(r.body.error, 'Nama wajib diisi'); ok('ubah nama kosong ditolak');
  r = await call('PUT', '/api/auth/me', { name: '  Pemilik   PawFinder ' }); assert.equal(r.body.user.name, 'Pemilik PawFinder'); ok('nama dirapikan (spasi ganda dibuang)');
  r = await call('PUT', '/api/auth/me', { name: 'x'.repeat(61) }); assert.equal(r.status, 422); ok('nama > 60 karakter ditolak');

  // =====================================================================
  console.log('\n[Awal kosong & tambah hewan]');
  r = await call('GET', '/api/pets'); assert.equal(r.body.pets.length, 0); ok('tidak ada hewan bawaan');
  r = await call('GET', '/api/notifications'); assert.equal(r.body.notifications.length, 0); assert.equal(r.body.unread, 0); ok('tidak ada notifikasi bawaan');
  r = await call('GET', '/api/history'); assert.equal(r.body.events.length, 0); ok('tidak ada riwayat bawaan');

  const today = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);
  const tomorrow = new Date(Date.now() + 31 * 3600e3).toISOString().slice(0, 10);
  r = await call('POST', '/api/pets', { name: '', species: 'anjing', birthDate: '2023-05-01' }); assert.equal(r.status, 422); assert.equal(r.body.error, 'Nama hewan wajib diisi'); ok('nama hewan kosong');
  r = await call('POST', '/api/pets', { name: '   ', species: 'anjing', birthDate: '2023-05-01' }); assert.equal(r.body.error, 'Nama hewan wajib diisi'); ok('nama hewan hanya spasi');
  r = await call('POST', '/api/pets', { name: 'x'.repeat(31), species: 'anjing', birthDate: '2023-05-01' }); assert.equal(r.body.error, 'Nama hewan maksimal 30 karakter'); ok('nama hewan > 30 karakter');
  r = await call('POST', '/api/pets', { name: 'Bruno', birthDate: '2023-05-01' }); assert.equal(r.body.error, 'Jenis hewan wajib dipilih'); ok('jenis hewan kosong');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'naga', birthDate: '2023-05-01' }); assert.equal(r.body.error, 'Jenis hewan tidak valid'); ok('jenis hewan tidak valid');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', gender: 'lain', birthDate: '2023-05-01' }); assert.equal(r.body.error, 'Jenis kelamin tidak valid'); ok('jenis kelamin tidak valid');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing' }); assert.equal(r.status, 422); assert.equal(r.body.error, 'Tanggal lahir wajib diisi'); assert.equal(r.body.field, 'birthDate'); ok('tanggal lahir kosong -> "Tanggal lahir wajib diisi"');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', birthDate: '' }); assert.equal(r.body.error, 'Tanggal lahir wajib diisi'); ok('tanggal lahir string kosong');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', birthDate: 'kemarin' }); assert.equal(r.body.error, 'Format tanggal lahir tidak valid'); ok('tanggal lahir bukan tanggal');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', birthDate: '2023-02-30' }); assert.equal(r.body.error, 'Format tanggal lahir tidak valid'); ok('30 Februari ditolak');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', birthDate: '2999-01-01' }); assert.equal(r.body.error, 'Tanggal lahir tidak boleh di masa depan'); ok('tanggal lahir di masa depan');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', birthDate: '1950-01-01' }); assert.match(r.body.error, /tidak masuk akal/); ok('tanggal lahir terlalu lampau');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', gender: 'jantan', birthDate: '2023-05-01' });
  assert.equal(r.status, 200);
  const pet = r.body.pet;
  assert.equal(pet.device.paired, false); assert.equal(pet.device.connection, 'unpaired'); assert.equal(pet.device.online, false);
  assert.equal(pet.location, null); assert.equal(pet.device.battery, null); assert.equal(pet.device.gpsFix, null); assert.equal(pet.device.source, null); ok('hewan baru: GPS belum terhubung, tanpa lokasi/baterai/online');
  r = await call('GET', '/api/notifications');
  assert.equal(r.body.notifications.length, 1); assert.equal(r.body.notifications[0].type, 'pet_added'); ok('notifikasi "hewan baru ditambahkan"');
  const hist = (await call('GET', '/api/history')).body.events;
  assert.equal(hist.length, 1); assert.equal(hist[0].title, r.body.notifications[0].title); assert.equal(hist[0].subtitle, r.body.notifications[0].subtitle); ok('riwayat identik dengan notifikasi');

  // =====================================================================
  console.log('\n[Koneksi alat: ID, validasi, status]');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554 }); assert.equal(r.status, 401); ok('telemetri tanpa device key -> 401');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554 }, { 'x-device-key': 'salah' }); assert.equal(r.status, 401); ok('device key salah -> 401');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554 }, DEVKEY); assert.equal(r.status, 404); assert.equal(r.body.code, 'UNPAIRED'); ok('telemetri dari alat belum dipasangkan -> 404 UNPAIRED');
  r = await call('GET', '/api/devices/discovered'); assert.equal(r.body.devices.length, 1); assert.equal(r.body.devices[0].serial, 'PF-BRU-000001'); ok('alat itu muncul di daftar "terdeteksi" (pairing sekali ketuk)');
  r = await call('POST', '/api/device/telemetry', { lat: -7.7155, lng: 110.3554 }, DEVKEY); assert.equal(r.status, 422); assert.equal(r.body.code, 'NO_SERIAL'); ok('telemetri tanpa ID alat -> 422');
  r = await call('POST', '/api/device/telemetry', { serial: 'ngawur', lat: 1, lng: 1 }, DEVKEY); assert.equal(r.status, 422); assert.equal(r.body.code, 'BAD_SERIAL'); ok('ID alat salah format -> 422');
  r = await call('POST', '/api/device/telemetry', {}, DEVKEY); assert.equal(r.status, 422); ok('body kosong -> 422');

  r = await call('POST', `/api/pets/${pet.id}/device/pair`, {}); assert.equal(r.status, 422); assert.equal(r.body.error, 'Nomor seri alat wajib diisi'); ok('pairing tanpa nomor seri -> "wajib diisi"');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'PF' }); assert.equal(r.body.error, 'Nomor seri alat wajib diisi'); ok('pairing hanya prefiks "PF" -> "wajib diisi"');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'abc' }); assert.equal(r.status, 422); assert.match(r.body.error, /Format nomor seri/); ok('format nomor seri divalidasi');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'PF-BRU-00000A' }); assert.equal(r.status, 422); ok('6 digit terakhir harus angka');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'pf-bru-000001' });
  assert.equal(r.status, 200); assert.equal(r.body.pet.device.connection, 'waiting'); assert.equal(r.body.pet.device.online, false);
  assert.equal(store.data.pets[0].device.simulated, false); ok('setelah dipasangkan: "menunggu sinyal"; alat terdeteksi nyata TIDAK disimulasikan');
  r = await call('GET', '/api/devices/discovered'); assert.equal(r.body.devices.length, 0); ok('alat yang sudah dipasangkan hilang dari daftar terdeteksi');

  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554, battery: 90, signal: 'Kuat', heartRate: 96, temperature: 38.6, satellites: 8 }, DEVKEY);
  assert.equal(r.status, 200); assert.equal(r.body.fix, true); assert.ok(Array.isArray(r.body.commands)); assert.equal(r.body.config.intervalSec, 30); ok('telemetri pertama diterima (respons memuat perintah & konfigurasi)');
  r = await call('GET', `/api/pets/${pet.id}`);
  assert.equal(r.body.pet.device.connection, 'online'); assert.equal(r.body.pet.device.battery, 90); assert.equal(r.body.pet.device.gpsFix, true); assert.equal(r.body.pet.device.satellites, 8); assert.equal(r.body.pet.device.source, 'http'); ok('baru setelah ada sinyal: online, fix GPS, sumber = jaringan');
  const ntf = (await call('GET', '/api/notifications')).body.notifications.map((n) => n.type);
  assert.ok(ntf.includes('gps_paired') && ntf.includes('gps_connected')); ok('notifikasi "dipasangkan" dan "GPS terhubung"');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'PF-BRU-000002' }); assert.equal(r.status, 409); ok('tidak bisa memasangkan dua kalung sekaligus');

  // Heartbeat: alat hidup tetapi belum dapat satelit
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', fix: 0, battery: 88 }, DEVKEY);
  assert.equal(r.status, 200); assert.equal(r.body.fix, false); ok('paket tanpa koordinat (belum fix) diterima sebagai heartbeat');
  r = await call('GET', `/api/pets/${pet.id}`);
  assert.equal(r.body.pet.device.connection, 'online'); assert.equal(r.body.pet.device.gpsFix, false); assert.equal(r.body.pet.device.battery, 88); assert.ok(r.body.pet.location, 'lokasi lama tidak dihapus'); ok('heartbeat: tetap online, gpsFix=false, lokasi terakhir dipertahankan');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: 0, lng: 0, battery: 88 }, DEVKEY); assert.equal(r.body.fix, false);
  assert.ok(Math.abs((await call('GET', `/api/pets/${pet.id}`)).body.pet.location.lat - -7.7155) < 1e-6); ok('koordinat (0,0) dari modul GPS tidak memindahkan hewan ke tengah laut');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: 123, lng: 110 }, DEVKEY); assert.equal(r.status, 422); assert.equal(r.body.error, 'Koordinat tidak valid'); ok('koordinat di luar rentang -> 422');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: 'abc', lng: 110 }, DEVKEY); assert.equal(r.status, 422); ok('koordinat bukan angka -> 422');

  // Live monitor
  r = await call('GET', `/api/pets/${pet.id}/device/live`);
  assert.equal(r.status, 200); assert.equal(r.body.live.serial, 'PF-BRU-000001'); assert.ok(r.body.live.packets >= 3); assert.equal(r.body.live.source, 'http'); assert.ok(r.body.live.ageSec <= 2); ok('endpoint live monitor: paket, sumber, umur data');

  // Perintah ke alat
  r = await call('POST', `/api/pets/${pet.id}/device/ping`); assert.equal(r.status, 200); ok('perintah bunyikan kalung diantrekan');
  r = await call('PUT', `/api/pets/${pet.id}/device`, { intervalSec: 7 }); assert.equal(r.status, 422); ok('interval tidak valid ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/device`, { intervalSec: 10 }); assert.equal(r.status, 200); ok('interval diubah');
  r = await call('GET', '/api/device/commands?serial=PF-BRU-000001', undefined, DEVKEY);
  assert.deepStrictEqual(r.body.commands.map((c) => c.cmd).sort(), ['interval', 'ping']); assert.equal(r.body.commands.find((c) => c.cmd === 'interval').arg, 10); ok('perintah ping + interval diambil alat/bridge');
  r = await call('GET', '/api/device/commands?serial=PF-BRU-000001', undefined, DEVKEY); assert.equal(r.body.commands.length, 0); ok('perintah hanya dikirim satu kali');
  r = await call('GET', '/api/device/commands?serial=PF-BRU-000001'); assert.equal(r.status, 401); ok('endpoint perintah butuh device key');
  await call('POST', `/api/pets/${pet.id}/device/ping`);
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554, battery: 87 }, DEVKEY);
  assert.deepStrictEqual(r.body.commands.map((c) => c.cmd), ['ping']); ok('perintah juga dikirim lewat respons telemetri berikutnya');

  // Offline
  store.data.pets[0].device.lastSeen = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  syncAllConnections(store);
  r = await call('GET', `/api/pets/${pet.id}`); assert.equal(r.body.pet.device.connection, 'offline'); assert.equal(r.body.pet.device.online, false);
  assert.ok((await call('GET', '/api/notifications')).body.notifications.some((n) => n.type === 'gps_offline')); ok('alat diam > batas waktu -> offline + notifikasi terputus');
  r = await call('POST', `/api/pets/${pet.id}/device/ping`); assert.equal(r.status, 409); ok('tidak bisa membunyikan kalung yang offline');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554, battery: 87 }, DEVKEY);
  r = await call('GET', `/api/pets/${pet.id}`); assert.equal(r.body.pet.device.connection, 'online'); ok('alat kembali mengirim -> online lagi');

  // =====================================================================
  console.log('\n[Geofence]');
  r = await call('PUT', `/api/pets/${pet.id}/geofence`, { radius: 10 }); assert.equal(r.status, 422); ok('radius < 50 m ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/geofence`, { radius: 99999 }); assert.equal(r.status, 422); ok('radius > 5 km ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/geofence`, { radius: 'abc' }); assert.equal(r.status, 422); ok('radius bukan angka ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/geofence`, { radius: null }); assert.equal(r.status, 422); ok('radius null ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/geofence`, { center: { lat: 999, lng: 1 } }); assert.equal(r.status, 422); ok('pusat area di luar rentang ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/geofence`, { notifyExit: 'ya' }); assert.equal(r.status, 422); ok('notifyExit non-boolean ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/geofence`, { radius: 120, notifyExit: true, notifyEnter: true });
  assert.equal(r.body.geofence.radius, 120); ok('ubah radius geofence');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.35547, battery: 90 }, DEVKEY);
  assert.equal(r.body.insideGeofence, true);
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7100, lng: 110.3600, battery: 90 }, DEVKEY);
  assert.equal(r.body.insideGeofence, false);
  let ntfs = (await call('GET', '/api/notifications')).body.notifications;
  assert.match(ntfs[0].title, /keluar dari Geofence/); ok('notifikasi keluar geofence');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.71556, lng: 110.35547, battery: 90 }, DEVKEY);
  ntfs = (await call('GET', '/api/notifications')).body.notifications;
  assert.match(ntfs[0].title, /masuk ke Geofence/); ok('notifikasi masuk geofence');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', fix: 0 }, DEVKEY);
  assert.equal((await call('GET', `/api/pets/${pet.id}`)).body.pet.insideGeofence, true); ok('heartbeat tanpa lokasi tidak mengubah status di dalam/di luar area');

  const h2 = (await call('GET', '/api/history')).body.events;
  const n2 = (await call('GET', '/api/notifications')).body.notifications;
  assert.equal(h2.length, n2.length);
  assert.deepEqual(h2.map((e) => e.title + e.subtitle).sort(), n2.map((e) => e.title + e.subtitle).sort()); ok(`riwayat (${h2.length}) identik dengan notifikasi (${n2.length})`);
  r = await call('GET', `/api/history?category=geofence&petId=${pet.id}`); assert.ok(r.body.events.every((e) => e.category === 'geofence') && r.body.events.length >= 3); ok('filter riwayat per kategori & hewan');
  r = await call('GET', '/api/history?date=bukan-tanggal'); assert.equal(r.status, 200); assert.equal(r.body.date, today); ok('parameter tanggal riwayat tidak valid -> memakai hari ini');
  r = await call('GET', '/api/notifications?limit=1'); assert.equal(r.body.notifications.length, 1); assert.ok(r.body.unread > 1); ok('notifikasi mendukung limit; jumlah belum dibaca tetap total');

  // Geofence otomatis di lokasi pertama (alat dipakai jauh dari titik bawaan)
  const p2 = (await call('POST', '/api/pets', { name: 'Kopi', species: 'kucing', gender: 'betina', birthDate: '2022-01-01' })).body.pet;
  await call('POST', `/api/pets/${p2.id}/device/pair`, { serial: 'PF-KOP-000002' });
  await call('POST', '/api/device/telemetry', { serial: 'PF-KOP-000002', lat: -6.2088, lng: 106.8456, battery: 70 }, DEVKEY); // Jakarta
  r = await call('GET', `/api/pets/${p2.id}/geofence`); assert.ok(Math.abs(r.body.geofence.center.lat - -6.2088) < 1e-6); ok('geofence bawaan otomatis dipusatkan ke lokasi pertama alat (tidak langsung "di luar area")');
  assert.equal((await call('GET', `/api/pets/${p2.id}`)).body.pet.insideGeofence, true);
  assert.match((await call('GET', `/api/pets/${p2.id}`)).body.pet.location.address, /^Koordinat -6\.2088/); ok('di luar Yogyakarta alamat berupa koordinat, bukan nama jalan Sleman yang salah');
  await call('DELETE', `/api/pets/${p2.id}`);

  // =====================================================================
  console.log('\n[Aktivitas & Kesehatan]');
  // gerakan kecil (10 m) agar terhitung sebagai langkah; getaran GPS < 3 m dan lompatan jauh tidak dihitung
  const base = { serial: 'PF-BRU-000001', battery: 90 };
  const before = (await call('GET', `/api/pets/${pet.id}/activity`)).body.activity.steps;
  await call('POST', '/api/device/telemetry', { ...base, lat: -7.71556, lng: 110.35547 }, DEVKEY);
  await call('POST', '/api/device/telemetry', { ...base, lat: -7.71556, lng: 110.355471 }, DEVKEY); // ~0,1 m: getaran
  assert.equal((await call('GET', `/api/pets/${pet.id}/activity`)).body.activity.steps, before); ok('getaran GPS saat diam tidak dihitung sebagai langkah');
  await call('POST', '/api/device/telemetry', { ...base, lat: -7.71556, lng: 110.35556 }, DEVKEY); // ~10 m
  r = await call('GET', `/api/pets/${pet.id}/activity`);
  assert.ok(r.body.activity.steps > before); assert.equal(r.body.activity.week.length, 7); assert.equal(r.body.activity.connected, true); ok('perpindahan nyata dihitung sebagai langkah');
  r = await call('GET', `/api/pets/${pet.id}/health`);
  assert.equal(r.body.health.sensor.heartRate, 96); assert.equal(r.body.health.records.length, 0); ok('sensor kesehatan dari telemetri');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', date: today }); assert.equal(r.body.error, 'Berat wajib diisi'); ok('berat kosong -> "Berat wajib diisi"');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 'abc', date: today }); assert.equal(r.status, 422); ok('berat bukan angka');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 500, date: today }); assert.equal(r.status, 422); ok('berat > 200 kg');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 5 }); assert.equal(r.status, 422); assert.equal(r.body.error, 'Tanggal wajib diisi'); assert.equal(r.body.field, 'date'); ok('tanggal catatan kosong -> "Tanggal wajib diisi"');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 5, date: 'besok' }); assert.equal(r.body.error, 'Format tanggal tidak valid'); ok('tanggal catatan salah format');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 5, date: '2999-01-01' }); assert.equal(r.body.error, 'Tanggal tidak boleh di masa depan'); ok('tanggal catatan di masa depan');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'vaksin', date: today }); assert.equal(r.body.error, 'Judul catatan wajib diisi'); ok('judul vaksin kosong');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'lain', date: today, title: 'x' }); assert.equal(r.status, 422); ok('jenis catatan tidak valid');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 22.46, date: '2025-01-10' }); assert.equal(r.status, 200);
  const rec = r.body.record;
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'vaksin', title: 'Vaksin rabies', date: '2025-02-01', note: 'Dosis 1' }); assert.equal(r.status, 200);
  r = await call('GET', `/api/pets/${pet.id}/health`);
  assert.equal(r.body.health.summary.latestWeightKg, 22.5); assert.equal(r.body.health.summary.lastVaccine.title, 'Vaksin rabies'); ok('catatan kesehatan: berat & vaksin');
  r = await call('DELETE', `/api/pets/${pet.id}/health-records/${rec.id}`); assert.equal(r.status, 200); ok('hapus catatan kesehatan');
  r = await call('DELETE', `/api/pets/${pet.id}/health-records/${rec.id}`); assert.equal(r.status, 404); ok('hapus catatan yang sudah tidak ada -> 404');

  // =====================================================================
  console.log('\n[Foto, edit, hapus]');
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  r = await call('PUT', `/api/pets/${pet.id}/photo`, { data: Buffer.from('bukan gambar').toString('base64') }); assert.equal(r.status, 422); ok('foto non-gambar ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/photo`, {}); assert.equal(r.status, 422); ok('foto tanpa data ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/photo`, { data: 12345 }); assert.equal(r.status, 422); ok('data foto bukan teks ditolak');
  const big = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(850 * 1024)]);
  r = await call('PUT', `/api/pets/${pet.id}/photo`, { data: big.toString('base64') }); assert.equal(r.status, 422); assert.match(r.body.error, /800 KB/); ok('foto 850 KB ditolak dengan pesan ukuran (bukan error 413 samar)');
  const okJpg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(780 * 1024)]);
  r = await call('PUT', `/api/pets/${pet.id}/photo`, { data: okJpg.toString('base64') }); assert.equal(r.status, 200); ok('foto 780 KB diterima');
  r = await call('PUT', `/api/pets/${pet.id}/photo`, { data: png.toString('base64') });
  assert.equal(r.status, 200); assert.ok(r.body.pet.photoVersion > 0);
  r = await call('GET', `/api/pets/${pet.id}/photo`); assert.equal(r.status, 200); assert.equal(r.type, 'image/png'); assert.equal(r.body.length, png.length); ok('unggah & ambil foto hewan');

  r = await call('PUT', `/api/pets/${pet.id}`, { name: '' }); assert.equal(r.status, 422); ok('edit nama kosong ditolak');
  r = await call('PUT', `/api/pets/${pet.id}`, { name: 'x'.repeat(31) }); assert.equal(r.body.error, 'Nama hewan maksimal 30 karakter'); ok('edit nama > 30 ditolak (tidak lagi dipotong diam-diam)');
  r = await call('PUT', `/api/pets/${pet.id}`, { birthDate: null }); assert.equal(r.body.error, 'Tanggal lahir wajib diisi'); ok('edit: tanggal lahir tidak boleh dikosongkan');
  r = await call('PUT', `/api/pets/${pet.id}`, { name: 'Valid', species: 'naga' }); assert.equal(r.status, 422);
  assert.equal((await call('GET', `/api/pets/${pet.id}`)).body.pet.name, 'Bruno'); ok('edit gagal tidak mengubah data sebagian (atomik)');
  r = await call('PUT', `/api/pets/${pet.id}`, { name: '  Bruno   Jr ', gender: 'betina', birthDate: '2022-06-15' });
  assert.equal(r.body.pet.name, 'Bruno Jr'); assert.equal(r.body.pet.birthDate, '2022-06-15'); ok('ubah profil hewan');

  const second = (await call('POST', '/api/pets', { name: 'Mochi', species: 'kucing', gender: 'betina', birthDate: '2024-01-01' })).body.pet;
  r = await call('DELETE', `/api/pets/${second.id}`); assert.equal(r.status, 200);
  ntfs = (await call('GET', '/api/notifications')).body.notifications;
  assert.equal(ntfs[0].type, 'pet_deleted'); assert.equal(ntfs[0].petId, null);
  assert.equal(ntfs.filter((n) => n.petId === second.id).length, 0); ok('hapus hewan: data & notifikasinya hilang, tersisa catatan penghapusan');
  r = await call('GET', `/api/pets/${second.id}`); assert.equal(r.status, 404); ok('hewan terhapus -> 404');

  r = await call('POST', `/api/pets/${pet.id}/device/unpair`);
  assert.equal(r.body.pet.device.paired, false); assert.equal(r.body.pet.device.connection, 'unpaired'); assert.equal(r.body.pet.location, null); ok('putuskan GPS');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554 }, DEVKEY); assert.equal(r.status, 404); ok('setelah diputuskan, paket dari alat itu ditolak lagi');
  r = await call('POST', `/api/pets/${pet.id}/device/unpair`); assert.equal(r.status, 409); ok('putuskan dua kali -> 409');

  // =====================================================================
  console.log('\n[Isolasi antar akun & sesi]');
  const owner = S.token;
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'budi@email.com', password: 'rahasia1' });
  assert.equal(r.status, 200); S.token = r.body.token;
  assert.equal((await call('GET', '/api/pets')).body.pets.length, 0);
  assert.equal((await call('GET', `/api/pets/${pet.id}`)).status, 404);
  assert.equal((await call('GET', `/api/pets/${pet.id}/photo`)).status, 404);
  assert.equal((await call('PUT', `/api/pets/${pet.id}`, { name: 'Curian' })).status, 404);
  assert.equal((await call('DELETE', `/api/pets/${pet.id}`)).status, 404);
  assert.equal((await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'PF-XXX-000009' })).status, 404);
  assert.equal((await call('GET', `/api/pets/${pet.id}/device/live`)).status, 404);
  assert.equal((await call('GET', '/api/history')).body.events.length, 0); ok('akun lain tidak melihat / mengubah data hewan, foto, riwayat, alat orang lain');
  await call('POST', '/api/pets', { name: 'Milo', species: 'kucing', gender: 'jantan', birthDate: '2023-03-03' });
  await call('POST', '/api/pets', { name: 'Luna', species: 'kelinci', gender: 'betina', birthDate: '2023-04-04' });
  assert.equal((await call('GET', '/api/pets')).body.pets.length, 2); ok('satu akun dapat menyimpan beberapa hewan');
  S.token = null;
  assert.equal((await call('GET', '/api/pets')).status, 401); ok('tanpa token ditolak');
  S.token = 'abc.def.ghi';
  assert.equal((await call('GET', '/api/pets')).status, 401); ok('token palsu ditolak');
  const [h, b] = owner.split('.');
  S.token = `${h}.${b}.${'A'.repeat(43)}`;
  assert.equal((await call('GET', '/api/pets')).status, 401); ok('token dengan tanda tangan salah ditolak');
  S.token = owner;
  r = await call('DELETE', `/api/pets/${pet.id}`); assert.equal(r.status, 200);

  // =====================================================================
  console.log('\n[Status USB & seed]');
  r = await call('GET', '/api/usb/status'); assert.equal(r.body.usb.enabled, false); assert.ok(r.body.usb.hint); ok('status USB saat nonaktif memberi petunjuk');
  r = await call('GET', '/api/usb/ports'); assert.equal(r.status, 200); assert.ok(Array.isArray(r.body.ports)); ok('daftar port USB tidak membuat server error walau tanpa driver');
  assert.equal(store.data.users.filter((u) => u.email === 'qa@pawfinder.test').length, 1); ok('akun awal hanya dibuat dari SEED_* (tidak ada akun tersembunyi di kode)');
  const emails = store.data.users.map((u) => u.email);
  assert.ok(!emails.includes('muhammadrizkyherawan@gmail.com')); ok('akun pribadi hardcode lama tidak lagi dibuat');

  // database rusak tidak menimpa data
  const { Store } = require('../src/store');
  const bad = path.join(dir, 'rusak.json'); fs.writeFileSync(bad, '{ini bukan json');
  const st = new Store(bad).load();
  assert.equal(st.data.users.length, 0); assert.ok(fs.readdirSync(dir).some((f) => f.startsWith('rusak.json.rusak-'))); ok('db.json rusak dicadangkan, bukan ditimpa');

  await S.close();
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(`\nSemua tes API lulus (${count()} pemeriksaan).`);
  process.exit(0);
})().catch((e) => { console.error('\nTES GAGAL:', e); process.exit(1); });
