'use strict';
// Uji end-to-end: jalankan server di port acak dengan DB sementara.
const os = require('os');
const path = require('path');
process.env.DATA_FILE = path.join(os.tmpdir(), `pawfinder-test-${Date.now()}.json`);
process.env.SIMULATOR = 'off';
const assert = require('assert');
const { createApp } = require('../src/server');
const { DEMO } = require('../src/seed');
const { syncAllConnections } = require('../src/services/engine');

(async () => {
  const { server, store } = createApp();
  await new Promise((r) => server.listen(0, r));
  const base = `http://127.0.0.1:${server.address().port}`;
  let token = null;
  const call = async (method, url, body, headers = {}) => {
    const res = await fetch(base + url, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
      body: body ? JSON.stringify(body) : undefined,
    });
    const type = res.headers.get('content-type') || '';
    return { status: res.status, body: type.includes('json') ? await res.json() : Buffer.from(await res.arrayBuffer()), type };
  };
  const ok = (name) => console.log('  ✓', name);
  const DEVKEY = { 'x-device-key': 'pawfinder-device-key' };

  let r = await call('GET', '/api/ping'); assert.equal(r.status, 200); ok('ping');

  r = await call('POST', '/api/auth/login', { email: DEMO.email, password: 'salah' });
  assert.equal(r.status, 401); ok('login salah ditolak');
  r = await call('POST', '/api/auth/login', { email: DEMO.email, password: DEMO.password });
  assert.equal(r.status, 200); token = r.body.token; ok('login akun pengembangan');
  r = await call('PUT', '/api/auth/me', { name: 'Pemilik PawFinder' });
  assert.equal(r.status, 200); assert.equal(r.body.user.name, 'Pemilik PawFinder'); ok('ubah profil pemilik akun');

  // ---- Awal kosong: tidak ada hewan, notifikasi, maupun riwayat bawaan
  r = await call('GET', '/api/pets'); assert.equal(r.body.pets.length, 0); ok('awal: tidak ada hewan bawaan');
  r = await call('GET', '/api/notifications'); assert.equal(r.body.notifications.length, 0); assert.equal(r.body.unread, 0); ok('awal: tidak ada notifikasi bawaan');
  r = await call('GET', '/api/history'); assert.equal(r.body.events.length, 0); ok('awal: tidak ada riwayat bawaan');

  // ---- Tambah hewan -> notifikasi + riwayat identik
  r = await call('POST', '/api/pets', { name: '', species: 'anjing' }); assert.equal(r.status, 422); ok('validasi nama wajib');
  r = await call('POST', '/api/pets', { name: 'Bruno', species: 'anjing', gender: 'jantan', birthDate: '2023-05-01' });
  assert.equal(r.status, 200);
  const pet = r.body.pet;
  assert.equal(pet.device.paired, false); assert.equal(pet.device.connection, 'unpaired'); assert.equal(pet.device.online, false);
  assert.equal(pet.location, null); assert.equal(pet.device.battery, null); ok('hewan baru: GPS belum terhubung, tanpa lokasi/baterai/online');
  r = await call('GET', '/api/notifications');
  assert.equal(r.body.notifications.length, 1); assert.equal(r.body.notifications[0].type, 'pet_added'); assert.match(r.body.notifications[0].subtitle, /Bruno/); ok('notifikasi "hewan baru ditambahkan"');
  const hist = (await call('GET', '/api/history')).body.events;
  assert.equal(hist.length, 1); assert.equal(hist[0].title, r.body.notifications[0].title); assert.equal(hist[0].subtitle, r.body.notifications[0].subtitle); ok('riwayat identik dengan notifikasi');

  // ---- Koneksi GPS: harus dipasangkan dulu, baru online setelah sinyal nyata
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554 }, DEVKEY);
  assert.equal(r.status, 404); ok('telemetri dari kalung yang belum dipasangkan ditolak');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'abc' }); assert.equal(r.status, 422); ok('format nomor seri divalidasi');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'pf-bru-000001' });
  assert.equal(r.status, 200); assert.equal(r.body.pet.device.connection, 'waiting'); assert.equal(r.body.pet.device.online, false); ok('setelah dipasangkan: status "menunggu sinyal", belum online');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554, battery: 90, signal: 'Kuat', heartRate: 96, temperature: 38.6 }, { 'x-device-key': 'salah' });
  assert.equal(r.status, 401); ok('device key salah ditolak');
  r = await call('POST', '/api/device/telemetry', { serial: 'PF-BRU-000001', lat: -7.7155, lng: 110.3554, battery: 90, signal: 'Kuat', heartRate: 96, temperature: 38.6 }, DEVKEY);
  assert.equal(r.status, 200); ok('telemetri pertama diterima');
  r = await call('GET', `/api/pets/${pet.id}`);
  assert.equal(r.body.pet.device.connection, 'online'); assert.equal(r.body.pet.device.online, true); assert.equal(r.body.pet.device.battery, 90); ok('baru setelah ada sinyal: status online (hijau)');
  const ntf = (await call('GET', '/api/notifications')).body.notifications.map((n) => n.type);
  assert.ok(ntf.includes('gps_paired') && ntf.includes('gps_connected')); ok('notifikasi "dipasangkan" dan "GPS terhubung"');
  r = await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'PF-BRU-000002' }); assert.equal(r.status, 409); ok('tidak bisa memasangkan dua kalung sekaligus');

  // ---- Kalung berhenti mengirim -> offline + notifikasi
  store.data.pets[0].device.lastSeen = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  syncAllConnections(store);
  r = await call('GET', `/api/pets/${pet.id}`); assert.equal(r.body.pet.device.connection, 'offline'); assert.equal(r.body.pet.device.online, false);
  assert.ok((await call('GET', '/api/notifications')).body.notifications.some((n) => n.type === 'gps_offline')); ok('kalung diam > batas waktu -> offline + notifikasi terputus');

  // ---- Geofence: radius + notifikasi keluar/masuk
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

  // Riwayat == Notifikasi (isi sama)
  const h2 = (await call('GET', '/api/history')).body.events;
  const n2 = (await call('GET', '/api/notifications')).body.notifications;
  assert.equal(h2.length, n2.length);
  assert.deepEqual(h2.map((e) => e.title + e.subtitle).sort(), n2.map((e) => e.title + e.subtitle).sort()); ok(`riwayat (${h2.length}) identik dengan notifikasi (${n2.length})`);
  r = await call('GET', `/api/history?category=geofence&petId=${pet.id}`); assert.ok(r.body.events.every((e) => e.category === 'geofence') && r.body.events.length >= 3); ok('filter riwayat per kategori & hewan');

  // ---- Aktivitas dan Kesehatan terpisah
  r = await call('GET', `/api/pets/${pet.id}/activity`);
  assert.ok(r.body.activity.steps > 0); assert.equal(r.body.activity.week.length, 7); assert.equal(r.body.activity.connected, true); ok('endpoint aktivitas (langkah dari telemetri nyata)');
  r = await call('GET', `/api/pets/${pet.id}/health`);
  assert.equal(r.body.health.sensor.heartRate, 96); assert.equal(r.body.health.records.length, 0); ok('endpoint kesehatan (sensor dari telemetri, belum ada catatan)');
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 'abc' }); assert.equal(r.status, 422);
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'berat', value: 22.46, date: '2025-01-10' }); assert.equal(r.status, 200);
  const rec = r.body.record;
  r = await call('POST', `/api/pets/${pet.id}/health-records`, { type: 'vaksin', title: 'Vaksin rabies', date: '2025-02-01', note: 'Dosis 1' }); assert.equal(r.status, 200);
  r = await call('GET', `/api/pets/${pet.id}/health`);
  assert.equal(r.body.health.summary.latestWeightKg, 22.5); assert.equal(r.body.health.summary.lastVaccine.title, 'Vaksin rabies'); ok('catatan kesehatan: berat & vaksin');
  r = await call('DELETE', `/api/pets/${pet.id}/health-records/${rec.id}`); assert.equal(r.status, 200); ok('hapus catatan kesehatan');

  // ---- Foto hewan
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  r = await call('PUT', `/api/pets/${pet.id}/photo`, { data: Buffer.from('bukan gambar').toString('base64') }); assert.equal(r.status, 422); ok('foto non-gambar ditolak');
  r = await call('PUT', `/api/pets/${pet.id}/photo`, { data: png.toString('base64') });
  assert.equal(r.status, 200); assert.ok(r.body.pet.photoVersion > 0);
  r = await call('GET', `/api/pets/${pet.id}/photo`); assert.equal(r.status, 200); assert.equal(r.type, 'image/png'); assert.equal(r.body.length, png.length); ok('unggah & ambil foto hewan');

  // ---- Edit & hapus hewan
  r = await call('PUT', `/api/pets/${pet.id}`, { name: 'Bruno Jr', gender: 'betina' });
  assert.equal(r.body.pet.name, 'Bruno Jr'); ok('ubah profil hewan');
  const second = (await call('POST', '/api/pets', { name: 'Mochi', species: 'kucing', gender: 'betina' })).body.pet;
  r = await call('DELETE', `/api/pets/${second.id}`); assert.equal(r.status, 200);
  ntfs = (await call('GET', '/api/notifications')).body.notifications;
  assert.equal(ntfs[0].type, 'pet_deleted'); assert.equal(ntfs[0].petId, null);
  assert.equal(ntfs.filter((n) => n.petId === second.id).length, 0); ok('hapus hewan: data & notifikasinya hilang, tersisa catatan penghapusan');
  r = await call('POST', `/api/pets/${pet.id}/device/unpair`);
  assert.equal(r.body.pet.device.paired, false); assert.equal(r.body.pet.device.connection, 'unpaired'); assert.equal(r.body.pet.location, null); ok('putuskan GPS');

  // ---- Akun lain & isolasi
  const owner = token;
  r = await call('POST', '/api/auth/register', { name: 'Budi', email: 'budi@email.com', password: 'rahasia1' });
  assert.equal(r.status, 200); token = r.body.token;
  assert.equal((await call('GET', '/api/pets')).body.pets.length, 0);
  assert.equal((await call('GET', `/api/pets/${pet.id}`)).status, 404);
  assert.equal((await call('GET', `/api/pets/${pet.id}/photo`)).status, 404);
  assert.equal((await call('GET', '/api/history')).body.events.length, 0); ok('akun lain tidak melihat data/riwayat/foto orang lain');
  await call('POST', '/api/pets', { name: 'Milo', species: 'kucing', gender: 'jantan' });
  await call('POST', '/api/pets', { name: 'Luna', species: 'kelinci', gender: 'betina' });
  assert.equal((await call('GET', '/api/pets')).body.pets.length, 2); ok('satu akun dapat menyimpan beberapa hewan');
  token = null;
  assert.equal((await call('GET', '/api/pets')).status, 401); ok('tanpa token ditolak');
  token = owner;
  r = await call('DELETE', `/api/pets/${pet.id}`); assert.equal(r.status, 200);

  server.close(); store.saveNow();
  require('fs').rmSync(process.env.DATA_FILE, { force: true });
  require('fs').rmSync(path.join(path.dirname(process.env.DATA_FILE), 'photos'), { recursive: true, force: true });
  console.log('\nSemua tes lulus.');
  process.exit(0);
})().catch((e) => { console.error('\nTES GAGAL:', e); process.exit(1); });
