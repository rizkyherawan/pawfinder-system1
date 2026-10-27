'use strict';
const fs = require('fs');
const path = require('path');
const config = require('../config');
const { HttpError } = require('../router');
const { hashPassword, verifyPassword, signToken } = require('../auth');
const { bus, petView, logEvent, ingestTelemetry, syncAllConnections, activitySummary, healthSummary, clamp } = require('../services/engine');
const { haversine, wibDateKey, wibToDate } = require('../geo');

const SPECIES = ['anjing', 'kucing', 'kelinci'];
const SPECIES_LABEL = { anjing: 'Anjing', kucing: 'Kucing', kelinci: 'Kelinci' };
const GENDERS = ['jantan', 'betina'];
const RECORD_TYPES = ['berat', 'vaksin', 'obat', 'catatan'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const SERIAL_RE = /^PF-[A-Z0-9]{3}-\d{6}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const userView = (u) => ({ id: u.id, name: u.name, email: u.email });
const fmtRadius = (m) => (m >= 1000 ? `${(m / 1000).toFixed(1).replace('.', ',')} km` : `${Math.round(m)} m`);

module.exports = function register(router) {
  const store = router.store;

  const ownPet = (ctx) => {
    const pet = store.data.pets.find((p) => p.id === ctx.params.id && p.userId === ctx.user.id);
    if (!pet) throw new HttpError(404, 'Hewan tidak ditemukan');
    return pet;
  };
  const settingsOf = (user) => store.data.settings[user.id] || (store.data.settings[user.id] = { push: true, sound: true, powerSave: false, theme: 'terang' });
  const emit = (pet) => bus.emit('pet', { userId: pet.userId, pet: petView(store, pet) });
  const validDate = (v) => {
    if (!DATE_RE.test(String(v || ''))) return false;
    const d = new Date(`${v}T00:00:00Z`);
    return !isNaN(d) && d.toISOString().slice(0, 10) === v;
  };

  // ---------- Sistem ----------
  router.get('/api/ping', { auth: false }, () => ({ status: 'ok', app: 'PawFinder', version: '1.3.0', time: new Date().toISOString() }));

  // ---------- Auth ----------
  router.post('/api/auth/register', { auth: false }, ({ body }) => {
    const name = String(body.name || '').trim();
    const email = String(body.email || '').trim().toLowerCase();
    const password = String(body.password || '');
    if (name.length < 2) throw new HttpError(422, 'Nama minimal 2 karakter', { field: 'name' });
    if (!EMAIL_RE.test(email)) throw new HttpError(422, 'Format email tidak valid', { field: 'email' });
    if (password.length < 6) throw new HttpError(422, 'Kata sandi minimal 6 karakter', { field: 'password' });
    if (store.data.users.some((u) => u.email === email)) throw new HttpError(409, 'Email sudah terdaftar', { field: 'email' });
    const user = { id: store.id('usr'), name, email, passwordHash: hashPassword(password), createdAt: new Date().toISOString() };
    store.data.users.push(user);
    store.save();
    return { token: signToken({ sub: user.id }), user: userView(user) };
  });

  router.post('/api/auth/login', { auth: false }, ({ body }) => {
    const email = String(body.email || '').trim().toLowerCase();
    const user = store.data.users.find((u) => u.email === email);
    if (!user || !verifyPassword(String(body.password || ''), user.passwordHash)) throw new HttpError(401, 'Email atau kata sandi salah');
    return { token: signToken({ sub: user.id }), user: userView(user) };
  });

  router.get('/api/auth/me', ({ user }) => ({ user: userView(user) }));

  router.put('/api/auth/me', ({ user, body }) => {
    if (body.name !== undefined) {
      const n = String(body.name).trim();
      if (n.length < 2) throw new HttpError(422, 'Nama minimal 2 karakter', { field: 'name' });
      user.name = n;
    }
    store.save();
    return { user: userView(user) };
  });

  // ---------- Hewan ----------
  router.get('/api/pets', ({ user }) => {
    syncAllConnections(store);
    return { pets: store.data.pets.filter((p) => p.userId === user.id).map((p) => petView(store, p)) };
  });

  router.post('/api/pets', ({ user, body }) => {
    const name = String(body.name || '').trim();
    const species = String(body.species || '').toLowerCase();
    const gender = String(body.gender || 'jantan').toLowerCase();
    if (!name) throw new HttpError(422, 'Nama hewan wajib diisi', { field: 'name' });
    if (name.length > 30) throw new HttpError(422, 'Nama maksimal 30 karakter', { field: 'name' });
    if (!SPECIES.includes(species)) throw new HttpError(422, 'Jenis hewan tidak valid', { field: 'species' });
    if (!GENDERS.includes(gender)) throw new HttpError(422, 'Jenis kelamin tidak valid', { field: 'gender' });
    let birthDate = null;
    if (body.birthDate) {
      const d = new Date(body.birthDate);
      if (isNaN(d) || d > new Date()) throw new HttpError(422, 'Tanggal lahir tidak valid', { field: 'birthDate' });
      birthDate = d.toISOString().slice(0, 10);
    }
    // Hewan baru BELUM terhubung ke kalung GPS: tanpa lokasi, tanpa baterai, tanpa status online.
    const pet = {
      id: store.id('pet'), userId: user.id, name, species, gender, birthDate,
      avatarColor: Number.isInteger(body.avatarColor) ? clamp(body.avatarColor, 0, 5) : store.data.pets.filter((p) => p.userId === user.id).length % 6,
      device: { paired: false, serial: null, firmware: '1.2.0', battery: null, signal: null, lastSeen: null, intervalSec: 30, simulated: false, lowNotified: false },
      location: null,
    };
    store.data.pets.push(pet);
    store.data.geofences.push({ id: store.id('geo'), petId: pet.id, name: 'Rumah', center: { lat: config.home.lat, lng: config.home.lng }, radius: 500, notifyExit: true, notifyEnter: true });
    logEvent(store, { userId: user.id, petId: pet.id, type: 'pet_added', title: 'Hewan baru ditambahkan', subtitle: `${name} (${SPECIES_LABEL[species]}) berhasil didaftarkan · Hubungkan kalung GPS untuk mulai melacak` });
    store.save();
    return { pet: petView(store, pet) };
  });

  router.get('/api/pets/:id', (ctx) => ({ pet: petView(store, ownPet(ctx)) }));

  router.put('/api/pets/:id', (ctx) => {
    const pet = ownPet(ctx);
    const b = ctx.body;
    if (b.name !== undefined) {
      const n = String(b.name).trim();
      if (!n) throw new HttpError(422, 'Nama hewan wajib diisi', { field: 'name' });
      pet.name = n.slice(0, 30);
    }
    if (b.species !== undefined) {
      if (!SPECIES.includes(String(b.species).toLowerCase())) throw new HttpError(422, 'Jenis hewan tidak valid', { field: 'species' });
      pet.species = String(b.species).toLowerCase();
    }
    if (b.gender !== undefined) {
      if (!GENDERS.includes(String(b.gender).toLowerCase())) throw new HttpError(422, 'Jenis kelamin tidak valid', { field: 'gender' });
      pet.gender = String(b.gender).toLowerCase();
    }
    if (b.birthDate !== undefined) {
      if (b.birthDate === null || b.birthDate === '') pet.birthDate = null;
      else {
        const d = new Date(b.birthDate);
        if (isNaN(d) || d > new Date()) throw new HttpError(422, 'Tanggal lahir tidak valid', { field: 'birthDate' });
        pet.birthDate = d.toISOString().slice(0, 10);
      }
    }
    if (Number.isInteger(b.avatarColor)) pet.avatarColor = clamp(b.avatarColor, 0, 5);
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'pet_updated', title: 'Profil hewan diperbarui', subtitle: `Data ${pet.name} berhasil disimpan` });
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  router.delete('/api/pets/:id', (ctx) => {
    const pet = ownPet(ctx);
    const d = store.data;
    d.pets = d.pets.filter((p) => p.id !== pet.id);
    d.geofences = d.geofences.filter((g) => g.petId !== pet.id);
    d.events = d.events.filter((e) => e.petId !== pet.id);
    d.notifications = d.notifications.filter((n) => n.petId !== pet.id);
    d.healthRecords = d.healthRecords.filter((r) => r.petId !== pet.id);
    Object.keys(d.stats).forEach((k) => { if (k.startsWith(`${pet.id}:`)) delete d.stats[k]; });
    try { fs.rmSync(path.join(config.photosDir, pet.id), { force: true }); } catch (_) { /* abaikan */ }
    // Kejadian penghapusan tetap tercatat di Riwayat & Notifikasi (tanpa petId karena hewan sudah tiada).
    logEvent(store, { userId: ctx.user.id, petId: null, type: 'pet_deleted', title: 'Data hewan dihapus', subtitle: `${pet.name} telah dihapus dari akunmu` });
    store.save();
    return { ok: true };
  });

  // ---------- Foto hewan ----------
  router.put('/api/pets/:id/photo', (ctx) => {
    const pet = ownPet(ctx);
    const raw = String(ctx.body.data || '').replace(/^data:[^;]+;base64,/, '');
    const buf = Buffer.from(raw, 'base64');
    if (!buf.length) throw new HttpError(422, 'Data foto kosong');
    if (buf.length > 800 * 1024) throw new HttpError(422, 'Ukuran foto maksimal 800 KB');
    const jpg = buf[0] === 0xff && buf[1] === 0xd8, png = buf[0] === 0x89 && buf[1] === 0x50;
    if (!jpg && !png) throw new HttpError(422, 'Format foto harus JPG atau PNG');
    fs.mkdirSync(config.photosDir, { recursive: true });
    fs.writeFileSync(path.join(config.photosDir, pet.id), buf);
    pet.photo = { version: Date.now(), type: png ? 'image/png' : 'image/jpeg' };
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'pet_updated', title: 'Foto profil diperbarui', subtitle: `Foto ${pet.name} berhasil disimpan` });
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  router.get('/api/pets/:id/photo', (ctx) => {
    const pet = ownPet(ctx);
    const file = path.join(config.photosDir, pet.id);
    if (!pet.photo || !fs.existsSync(file)) throw new HttpError(404, 'Foto belum ada');
    const buf = fs.readFileSync(file);
    ctx.res.writeHead(200, { 'Content-Type': pet.photo.type, 'Content-Length': buf.length, 'Cache-Control': 'private, max-age=31536000' });
    ctx.res.end(buf);
  });

  router.delete('/api/pets/:id/photo', (ctx) => {
    const pet = ownPet(ctx);
    try { fs.rmSync(path.join(config.photosDir, pet.id), { force: true }); } catch (_) { /* abaikan */ }
    delete pet.photo;
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  // ---------- Koneksi kalung GPS ----------
  router.post('/api/pets/:id/device/pair', (ctx) => {
    const pet = ownPet(ctx);
    const serial = String(ctx.body.serial || '').trim().toUpperCase();
    if (!SERIAL_RE.test(serial)) throw new HttpError(422, 'Format nomor seri tidak valid. Contoh: PF-ABC-123456', { field: 'serial' });
    const other = store.data.pets.find((p) => p.device.paired && p.device.serial === serial && p.id !== pet.id);
    if (other) throw new HttpError(409, 'Nomor seri ini sudah dipakai oleh hewan lain', { field: 'serial' });
    if (pet.device.paired) throw new HttpError(409, 'Hewan ini sudah terhubung ke kalung. Putuskan dulu untuk mengganti.');
    Object.assign(pet.device, {
      paired: true, serial, firmware: '1.2.0', battery: null, signal: null, lastSeen: null, connState: 'waiting', everConnected: false, lowNotified: false,
      simulated: config.simulator, // tanpa kalung asli, simulator mengirim telemetri agar fitur dapat didemokan
    });
    pet.insideGeofence = undefined;
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'gps_paired', title: 'Kalung GPS dipasangkan', subtitle: `${serial} · Menunggu sinyal dari kalung ${pet.name}` });
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  router.post('/api/pets/:id/device/unpair', (ctx) => {
    const pet = ownPet(ctx);
    if (!pet.device.paired) throw new HttpError(409, 'Hewan ini belum terhubung ke kalung');
    const serial = pet.device.serial;
    Object.assign(pet.device, { paired: false, serial: null, battery: null, signal: null, lastSeen: null, connState: undefined, everConnected: false, simulated: false });
    pet.location = null;
    pet.insideGeofence = undefined;
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'gps_unpaired', title: 'GPS diputuskan', subtitle: `Kalung ${serial} dilepas dari ${pet.name}` });
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  router.put('/api/pets/:id/device', (ctx) => {
    const pet = ownPet(ctx);
    const sec = Number(ctx.body.intervalSec);
    if (![10, 30, 60, 300].includes(sec)) throw new HttpError(422, 'Interval harus 10, 30, 60, atau 300 detik');
    pet.device.intervalSec = sec;
    store.save();
    return { pet: petView(store, pet) };
  });

  router.post('/api/pets/:id/device/ping', (ctx) => {
    const pet = ownPet(ctx);
    if (!pet.device.paired) throw new HttpError(409, 'Kalung belum terhubung');
    bus.emit('ping', { userId: ctx.user.id, petId: pet.id });
    return { ok: true, message: `Kalung ${pet.name} berbunyi selama 10 detik` };
  });

  // ---------- Geofence ----------
  const fenceView = (g) => ({ petId: g.petId, name: g.name, center: g.center, radius: g.radius, notifyExit: g.notifyExit, notifyEnter: g.notifyEnter });

  router.get('/api/pets/:id/geofence', (ctx) => {
    const pet = ownPet(ctx);
    let g = store.data.geofences.find((x) => x.petId === pet.id);
    if (!g) {
      g = { id: store.id('geo'), petId: pet.id, name: 'Rumah', center: { lat: config.home.lat, lng: config.home.lng }, radius: 500, notifyExit: true, notifyEnter: true };
      store.data.geofences.push(g);
      store.save();
    }
    return { geofence: fenceView(g) };
  });

  router.put('/api/pets/:id/geofence', (ctx) => {
    const pet = ownPet(ctx);
    const g = store.data.geofences.find((x) => x.petId === pet.id);
    if (!g) throw new HttpError(404, 'Geofence belum dibuat');
    const b = ctx.body;
    if (b.radius !== undefined) {
      const r = Number(b.radius);
      if (!(r >= 50 && r <= 5000)) throw new HttpError(422, 'Radius harus antara 50 m dan 5 km', { field: 'radius' });
      g.radius = Math.round(r);
    }
    if (typeof b.notifyExit === 'boolean') g.notifyExit = b.notifyExit;
    if (typeof b.notifyEnter === 'boolean') g.notifyEnter = b.notifyEnter;
    if (b.name) g.name = String(b.name).slice(0, 24);
    if (b.center && Number.isFinite(b.center.lat) && Number.isFinite(b.center.lng)) g.center = { lat: b.center.lat, lng: b.center.lng };
    if (pet.location) pet.insideGeofence = haversine(g.center, pet.location) <= g.radius;
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'geofence_updated', title: 'Geofence diperbarui', subtitle: `${pet.name} · Radius ${fmtRadius(g.radius)} · Notifikasi keluar area ${g.notifyExit ? 'aktif' : 'nonaktif'}` });
    store.save();
    emit(pet);
    return { geofence: fenceView(g) };
  });

  // ---------- Riwayat (log kejadian yang sama dengan Notifikasi) ----------
  router.get('/api/history', ({ user, query }) => {
    const date = validDate(query.date) ? query.date : wibDateKey();
    const from = wibToDate(date, 0, 0).getTime(), to = from + 86400000;
    let events = store.data.events.filter((e) => e.userId === user.id && new Date(e.time).getTime() >= from && new Date(e.time).getTime() < to);
    if (query.petId) events = events.filter((e) => e.petId === query.petId);
    if (query.category && query.category !== 'semua') events = events.filter((e) => e.category === query.category);
    events.sort((a, b) => new Date(b.time) - new Date(a.time));
    return { date, events };
  });

  // ---------- Aktivitas & Kesehatan (dua fitur terpisah) ----------
  router.get('/api/pets/:id/activity', (ctx) => ({ activity: activitySummary(store, ownPet(ctx)) }));

  router.get('/api/pets/:id/health', (ctx) => ({ health: healthSummary(store, ownPet(ctx)) }));

  router.post('/api/pets/:id/health-records', (ctx) => {
    const pet = ownPet(ctx);
    const b = ctx.body;
    const type = String(b.type || '').toLowerCase();
    if (!RECORD_TYPES.includes(type)) throw new HttpError(422, 'Jenis catatan tidak valid', { field: 'type' });
    const date = validDate(b.date) ? b.date : wibDateKey();
    if (date > wibDateKey()) throw new HttpError(422, 'Tanggal tidak boleh di masa depan', { field: 'date' });
    let title = String(b.title || '').trim().slice(0, 60);
    let value = null;
    if (type === 'berat') {
      value = Number(b.value);
      if (!(value > 0 && value <= 200)) throw new HttpError(422, 'Berat harus antara 0,1 dan 200 kg', { field: 'value' });
      value = Math.round(value * 10) / 10;
      title = title || 'Berat badan';
    } else if (!title) throw new HttpError(422, 'Judul catatan wajib diisi', { field: 'title' });
    const rec = { id: store.id('rec'), userId: ctx.user.id, petId: pet.id, type, title, value, date, note: String(b.note || '').trim().slice(0, 300), createdAt: new Date().toISOString() };
    store.data.healthRecords.push(rec);
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'health_record', title: 'Catatan kesehatan ditambahkan', subtitle: `${pet.name} · ${type === 'berat' ? `Berat ${value} kg` : title}` });
    store.save();
    return { record: rec };
  });

  router.delete('/api/pets/:id/health-records/:rid', (ctx) => {
    const pet = ownPet(ctx);
    const before = store.data.healthRecords.length;
    store.data.healthRecords = store.data.healthRecords.filter((r) => !(r.id === ctx.params.rid && r.petId === pet.id));
    if (store.data.healthRecords.length === before) throw new HttpError(404, 'Catatan tidak ditemukan');
    store.save();
    return { ok: true };
  });

  // ---------- Notifikasi ----------
  router.get('/api/notifications', ({ user, query }) => {
    let list = store.data.notifications.filter((n) => n.userId === user.id);
    if (query.category && query.category !== 'semua') list = list.filter((n) => n.category === query.category);
    list.sort((a, b) => new Date(b.time) - new Date(a.time));
    return { notifications: list, unread: store.data.notifications.filter((n) => n.userId === user.id && !n.read).length };
  });
  router.post('/api/notifications/read-all', ({ user }) => {
    store.data.notifications.forEach((n) => { if (n.userId === user.id) n.read = true; });
    store.save();
    return { ok: true };
  });
  router.patch('/api/notifications/:id/read', ({ user, params }) => {
    const n = store.data.notifications.find((x) => x.id === params.id && x.userId === user.id);
    if (!n) throw new HttpError(404, 'Notifikasi tidak ditemukan');
    n.read = true;
    store.save();
    return { notification: n };
  });
  router.delete('/api/notifications/:id', ({ user, params }) => {
    store.data.notifications = store.data.notifications.filter((x) => !(x.id === params.id && x.userId === user.id));
    store.save();
    return { ok: true };
  });
  router.delete('/api/notifications', ({ user }) => {
    store.data.notifications = store.data.notifications.filter((x) => x.userId !== user.id);
    store.save();
    return { ok: true };
  });

  // ---------- Pengaturan ----------
  router.get('/api/settings', ({ user }) => ({ settings: settingsOf(user) }));
  router.put('/api/settings', ({ user, body }) => {
    const s = settingsOf(user);
    for (const k of ['push', 'sound', 'powerSave']) if (typeof body[k] === 'boolean') s[k] = body[k];
    if (['terang', 'gelap', 'sistem'].includes(body.theme)) s.theme = body.theme;
    store.save();
    return { settings: s };
  });

  // ---------- IoT: telemetri dari kalung GPS ----------
  router.post('/api/device/telemetry', { auth: false }, (ctx) => {
    if (ctx.req.headers['x-device-key'] !== config.deviceKey) throw new HttpError(401, 'Device key tidak valid');
    const b = ctx.body;
    const serial = String(b.serial || '').trim().toUpperCase();
    const pet = store.data.pets.find((p) => p.device.paired && p.device.serial === serial);
    if (!pet) throw new HttpError(404, `Perangkat ${serial || '(tanpa nomor seri)'} belum dipasangkan ke hewan. Pasangkan lewat aplikasi lebih dulu.`);
    if (!Number.isFinite(b.lat) || !Number.isFinite(b.lng) || Math.abs(b.lat) > 90 || Math.abs(b.lng) > 180) throw new HttpError(422, 'Koordinat tidak valid');
    pet.device.simulated = false; // perangkat nyata mengambil alih
    ingestTelemetry(store, pet, { lat: b.lat, lng: b.lng, battery: b.battery, signal: b.signal, heartRate: b.heartRate, temperature: b.temperature });
    return { ok: true, insideGeofence: pet.insideGeofence, address: pet.location.address };
  });

  // ---------- Live stream (Server-Sent Events) ----------
  router.get('/api/stream', (ctx) => {
    const { req, res, user } = ctx;
    res.writeHead(200, {
      'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive',
      'Access-Control-Allow-Origin': '*', 'X-Accel-Buffering': 'no',
    });
    res.write('retry: 3000\n\n');
    const send = (event, data) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    const onPet = (e) => e.userId === user.id && send('pet', e.pet);
    const onNtf = (e) => e.userId === user.id && send('notification', e.notification);
    bus.on('pet', onPet);
    bus.on('notification', onNtf);
    const hb = setInterval(() => res.write(': ping\n\n'), 20000);
    req.on('close', () => { clearInterval(hb); bus.off('pet', onPet); bus.off('notification', onNtf); });
    send('hello', { user: userView(user) });
  });
};
