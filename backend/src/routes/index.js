'use strict';
const { createPhotoStore } = require('../services/photo-store');
const crypto = require('crypto');
const config = require('../config');
const { HttpError, corsHeaders } = require('../router');
const { hashPassword, verifyPassword, burnPasswordTime, passwordProblem, signToken, RateLimiter } = require('../auth');
const { bus, petView, logEvent, syncAllConnections, activitySummary, healthSummary, clamp } = require('../services/engine');
const { handleDeviceMessage, enqueueCommand, drainCommands, liveView, discoveredDevices } = require('../services/device-gateway');
const { parseLine, normalizeSerial, toNum, validCoords } = require('../services/device-protocol');
const { createOpener, listPorts } = require('../services/serial-io');
const { haversine, wibDateKey, wibToDate, addDays } = require('../geo');

const VERSION = '1.4.0';
const SPECIES = ['anjing', 'kucing', 'kelinci'];
const SPECIES_LABEL = { anjing: 'Anjing', kucing: 'Kucing', kelinci: 'Kelinci' };
const GENDERS = ['jantan', 'betina'];
const RECORD_TYPES = ['berat', 'vaksin', 'obat', 'catatan'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_PETS_PER_USER = 30;
const PHOTO_MAX_BYTES = 800 * 1024;

const userView = (u) => ({ id: u.id, name: u.name, email: u.email });
const fmtRadius = (m) => (m >= 1000 ? `${(m / 1000).toFixed(1).replace('.', ',')} km` : `${Math.round(m)} m`);
const clean = (v) => String(v === undefined || v === null ? '' : v).replace(/\s+/g, ' ').trim();
const isFiniteNum = (v) => typeof v === 'number' && Number.isFinite(v);

module.exports = function register(router) {
  const store = router.store;
  const photos = createPhotoStore(store);
  const loginLimiter = new RateLimiter({ max: 5, windowMs: 10 * 60 * 1000 });   // gagal login per IP+email
  const registerLimiter = new RateLimiter({ max: 20, windowMs: 60 * 60 * 1000 }); // pendaftaran per IP

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
  const newFence = (petId) => ({ id: store.id('geo'), petId, name: 'Rumah', center: { lat: config.home.lat, lng: config.home.lng }, radius: 500, notifyExit: true, notifyEnter: true, auto: true });

  /** Tanggal lahir: wajib, format YYYY-MM-DD, tidak di masa depan, tidak lebih dari 40 tahun lalu. */
  const birthDateOf = (raw) => {
    if (raw === undefined || raw === null || clean(raw) === '') throw new HttpError(422, 'Tanggal lahir wajib diisi', { field: 'birthDate' });
    let v = String(raw).trim();
    if (v.length > 10 && v[10] === 'T') v = v.slice(0, 10);
    if (!validDate(v)) throw new HttpError(422, 'Format tanggal lahir tidak valid', { field: 'birthDate' });
    const today = wibDateKey();
    if (v > addDays(today, 1)) throw new HttpError(422, 'Tanggal lahir tidak boleh di masa depan', { field: 'birthDate' });
    if (v < addDays(today, -365 * 40)) throw new HttpError(422, 'Tanggal lahir tidak masuk akal (maksimal 40 tahun lalu)', { field: 'birthDate' });
    return v;
  };
  const petNameOf = (raw) => {
    const n = clean(raw);
    if (!n) throw new HttpError(422, 'Nama hewan wajib diisi', { field: 'name' });
    if (n.length > 30) throw new HttpError(422, 'Nama hewan maksimal 30 karakter', { field: 'name' });
    return n;
  };
  const userNameOf = (raw) => {
    const n = clean(raw);
    if (!n) throw new HttpError(422, 'Nama wajib diisi', { field: 'name' });
    if (n.length < 2) throw new HttpError(422, 'Nama minimal 2 karakter', { field: 'name' });
    if (n.length > 60) throw new HttpError(422, 'Nama maksimal 60 karakter', { field: 'name' });
    return n;
  };
  const deviceKeyOk = (req) => {
    const given = Buffer.from(String(req.headers['x-device-key'] || ''));
    const want = Buffer.from(config.deviceKey);
    return given.length === want.length && crypto.timingSafeEqual(given, want);
  };
  const requireDeviceKey = (req) => { if (!deviceKeyOk(req)) throw new HttpError(401, 'Device key tidak valid'); };

  // ---------- Sistem ----------
  router.get('/api/ping', { auth: false }, () => ({
    status: 'ok', app: 'PawFinder', version: VERSION, time: new Date().toISOString(),
    features: { usb: !!store.runtime.usb, simulator: config.simulator },
  }));

  // ---------- Auth ----------
  router.post('/api/auth/register', { auth: false }, ({ body, ip }) => {
    const wait = registerLimiter.check(ip);
    if (wait) throw new HttpError(429, `Terlalu banyak pendaftaran. Coba lagi dalam ${Math.ceil(wait / 60)} menit.`, { retryAfterSec: wait });
    const name = userNameOf(body.name);
    const email = clean(body.email).toLowerCase();
    if (!email) throw new HttpError(422, 'Email wajib diisi', { field: 'email' });
    if (email.length > 254 || !EMAIL_RE.test(email)) throw new HttpError(422, 'Format email tidak valid', { field: 'email' });
    const pwProblem = passwordProblem(body.password);
    if (pwProblem) throw new HttpError(422, pwProblem, { field: 'password' });
    if (store.data.users.some((u) => u.email === email)) throw new HttpError(409, 'Email sudah terdaftar', { field: 'email' });
    registerLimiter.fail(ip);
    const user = { id: store.id('usr'), name, email, passwordHash: hashPassword(String(body.password)), createdAt: new Date().toISOString() };
    store.data.users.push(user);
    store.save();
    return { token: signToken({ sub: user.id }), user: userView(user) };
  });

  router.post('/api/auth/login', { auth: false }, ({ body, ip }) => {
    const email = clean(body.email).toLowerCase();
    const password = body.password === undefined || body.password === null ? '' : String(body.password);
    if (!email) throw new HttpError(422, 'Email wajib diisi', { field: 'email' });
    if (!password) throw new HttpError(422, 'Kata sandi wajib diisi', { field: 'password' });
    const key = `${ip}|${email}`;
    const wait = loginLimiter.check(key);
    if (wait) throw new HttpError(429, `Terlalu banyak percobaan masuk. Coba lagi dalam ${Math.ceil(wait / 60)} menit.`, { retryAfterSec: wait });
    const user = store.data.users.find((u) => u.email === email);
    if (!user) burnPasswordTime(password); // waktu respons sama dengan email terdaftar
    if (!user || !verifyPassword(password, user.passwordHash)) {
      loginLimiter.fail(key);
      throw new HttpError(401, 'Email atau kata sandi salah');
    }
    loginLimiter.reset(key);
    return { token: signToken({ sub: user.id }), user: userView(user) };
  });

  router.get('/api/auth/me', ({ user }) => ({ user: userView(user) }));

  router.put('/api/auth/me', ({ user, body }) => {
    if (body.name !== undefined) user.name = userNameOf(body.name);
    store.save();
    return { user: userView(user) };
  });

  // ---------- Hewan ----------
  router.get('/api/pets', ({ user }) => {
    syncAllConnections(store);
    return { pets: store.data.pets.filter((p) => p.userId === user.id).map((p) => petView(store, p)) };
  });

  router.post('/api/pets', ({ user, body }) => {
    const name = petNameOf(body.name);
    const species = clean(body.species).toLowerCase();
    const gender = clean(body.gender || 'jantan').toLowerCase();
    if (!species) throw new HttpError(422, 'Jenis hewan wajib dipilih', { field: 'species' });
    if (!SPECIES.includes(species)) throw new HttpError(422, 'Jenis hewan tidak valid', { field: 'species' });
    if (!GENDERS.includes(gender)) throw new HttpError(422, 'Jenis kelamin tidak valid', { field: 'gender' });
    const birthDate = birthDateOf(body.birthDate);
    const mine = store.data.pets.filter((p) => p.userId === user.id);
    if (mine.length >= MAX_PETS_PER_USER) throw new HttpError(422, `Maksimal ${MAX_PETS_PER_USER} hewan per akun`);
    // Hewan baru BELUM terhubung ke kalung GPS: tanpa lokasi, tanpa baterai, tanpa status online.
    const pet = {
      id: store.id('pet'), userId: user.id, name, species, gender, birthDate,
      avatarColor: Number.isInteger(body.avatarColor) ? clamp(body.avatarColor, 0, 5) : mine.length % 6,
      device: { paired: false, serial: null, firmware: '1.2.0', battery: null, signal: null, lastSeen: null, intervalSec: 30, simulated: false, lowNotified: false },
      location: null,
    };
    store.data.pets.push(pet);
    store.data.geofences.push(newFence(pet.id));
    logEvent(store, { userId: user.id, petId: pet.id, type: 'pet_added', title: 'Hewan baru ditambahkan', subtitle: `${name} (${SPECIES_LABEL[species]}) berhasil didaftarkan · Hubungkan kalung GPS untuk mulai melacak` });
    store.save();
    return { pet: petView(store, pet) };
  });

  router.get('/api/pets/:id', (ctx) => ({ pet: petView(store, ownPet(ctx)) }));

  router.put('/api/pets/:id', (ctx) => {
    const pet = ownPet(ctx);
    const b = ctx.body;
    // Validasi semua dulu, baru ubah data: kegagalan di tengah tidak boleh meninggalkan data setengah berubah.
    const next = {};
    if (b.name !== undefined) next.name = petNameOf(b.name);
    if (b.species !== undefined) {
      const sp = clean(b.species).toLowerCase();
      if (!SPECIES.includes(sp)) throw new HttpError(422, 'Jenis hewan tidak valid', { field: 'species' });
      next.species = sp;
    }
    if (b.gender !== undefined) {
      const g = clean(b.gender).toLowerCase();
      if (!GENDERS.includes(g)) throw new HttpError(422, 'Jenis kelamin tidak valid', { field: 'gender' });
      next.gender = g;
    }
    if (b.birthDate !== undefined) next.birthDate = birthDateOf(b.birthDate);
    if (Number.isInteger(b.avatarColor)) next.avatarColor = clamp(b.avatarColor, 0, 5);
    Object.assign(pet, next);
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'pet_updated', title: 'Profil hewan diperbarui', subtitle: `Data ${pet.name} berhasil disimpan` });
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  const forgetDevice = (serial) => {
    if (!serial) return;
    store.runtime.live.delete(serial);
    store.runtime.commands.delete(serial);
    store.runtime.discovered.delete(serial);
  };

  router.delete('/api/pets/:id', async (ctx) => {
    const pet = ownPet(ctx);
    await photos.remove(pet.id);
    const d = store.data;
    d.pets = d.pets.filter((p) => p.id !== pet.id);
    d.geofences = d.geofences.filter((g) => g.petId !== pet.id);
    d.events = d.events.filter((e) => e.petId !== pet.id);
    d.notifications = d.notifications.filter((n) => n.petId !== pet.id);
    d.healthRecords = d.healthRecords.filter((r) => r.petId !== pet.id);
    Object.keys(d.stats).forEach((k) => { if (k.startsWith(`${pet.id}:`)) delete d.stats[k]; });
    forgetDevice(pet.device && pet.device.serial);
    // Kejadian penghapusan tetap tercatat di Riwayat & Notifikasi (tanpa petId karena hewan sudah tiada).
    logEvent(store, { userId: ctx.user.id, petId: null, type: 'pet_deleted', title: 'Data hewan dihapus', subtitle: `${pet.name} telah dihapus dari akunmu` });
    store.save();
    return { ok: true };
  });

  // ---------- Foto hewan ----------
  router.put('/api/pets/:id/photo', { maxBody: 1_300_000 }, async (ctx) => {
    const pet = ownPet(ctx);
    if (typeof ctx.body.data !== 'string') throw new HttpError(422, 'Data foto kosong');
    const raw = ctx.body.data.replace(/^data:[^;]+;base64,/, '');
    const buf = Buffer.from(raw, 'base64');
    if (!buf.length) throw new HttpError(422, 'Data foto kosong');
    if (buf.length > PHOTO_MAX_BYTES) throw new HttpError(422, 'Ukuran foto maksimal 800 KB');
    const jpg = buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
    const png = buf.length > 8 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47;
    if (!jpg && !png) throw new HttpError(422, 'Format foto harus JPG atau PNG');
    await photos.save(pet.id, buf);
    pet.photo = { version: Date.now(), type: png ? 'image/png' : 'image/jpeg' };
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'pet_updated', title: 'Foto profil diperbarui', subtitle: `Foto ${pet.name} berhasil disimpan` });
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  router.get('/api/pets/:id/photo', async (ctx) => {
    const pet = ownPet(ctx);
    if (!pet.photo) throw new HttpError(404, 'Foto belum ada');
    const buf = await photos.load(pet.id);
    if (!buf) throw new HttpError(404, 'Foto belum ada');
    ctx.res.writeHead(200, { 'Content-Type': pet.photo.type, 'Content-Length': buf.length, 'Cache-Control': 'private, max-age=31536000', 'X-Content-Type-Options': 'nosniff', ...corsHeaders(ctx.req) });
    ctx.res.end(buf);
  });

  router.delete('/api/pets/:id/photo', async (ctx) => {
    const pet = ownPet(ctx);
    await photos.remove(pet.id);
    delete pet.photo;
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  // ---------- Koneksi kalung GPS ----------
  router.post('/api/pets/:id/device/pair', (ctx) => {
    const pet = ownPet(ctx);
    const rawSerial = clean(ctx.body.serial).toUpperCase();
    if (!rawSerial || rawSerial === 'PF') throw new HttpError(422, 'Nomor seri alat wajib diisi', { field: 'serial' });
    const serial = normalizeSerial(rawSerial);
    if (!serial) throw new HttpError(422, 'Format nomor seri tidak valid. Contoh: PF-ABC-123456', { field: 'serial' });
    const other = store.data.pets.find((p) => p.device.paired && p.device.serial === serial && p.id !== pet.id);
    if (other) throw new HttpError(409, 'Nomor seri ini sudah dipakai oleh hewan lain', { field: 'serial' });
    if (pet.device.paired) throw new HttpError(409, 'Hewan ini sudah terhubung ke kalung. Putuskan dulu untuk mengganti.');
    // Alat yang baru saja terlihat mengirim paket adalah alat NYATA: simulator tidak boleh mengambil alih.
    const seen = store.runtime.discovered.get(serial);
    const realDevice = !!seen && Date.now() - seen.lastAt < 120_000;
    Object.assign(pet.device, {
      paired: true, serial, firmware: '1.2.0', battery: null, signal: null, lastSeen: null, connState: 'waiting', everConnected: false, lowNotified: false,
      gpsFix: undefined, satellites: undefined, source: realDevice ? seen.source : null, forceOffline: false, lastIngestMs: 0,
      simulated: config.simulator && !realDevice, // tanpa kalung asli, simulator (bila diaktifkan) mengirim telemetri agar fitur dapat didemokan
    });
    pet.insideGeofence = undefined;
    forgetDevice(serial);
    logEvent(store, { userId: ctx.user.id, petId: pet.id, type: 'gps_paired', title: 'Kalung GPS dipasangkan', subtitle: `${serial} · Menunggu sinyal dari kalung ${pet.name}` });
    store.save();
    emit(pet);
    return { pet: petView(store, pet) };
  });

  router.post('/api/pets/:id/device/unpair', (ctx) => {
    const pet = ownPet(ctx);
    if (!pet.device.paired) throw new HttpError(409, 'Hewan ini belum terhubung ke kalung');
    const serial = pet.device.serial;
    Object.assign(pet.device, { paired: false, serial: null, battery: null, signal: null, lastSeen: null, connState: undefined, everConnected: false, simulated: false, gpsFix: undefined, satellites: undefined, source: null, forceOffline: false });
    pet.location = null;
    pet.insideGeofence = undefined;
    forgetDevice(serial);
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
    if (pet.device.paired) enqueueCommand(store, pet.device.serial, 'interval', sec); // diteruskan ke firmware
    store.save();
    return { pet: petView(store, pet) };
  });

  router.post('/api/pets/:id/device/ping', (ctx) => {
    const pet = ownPet(ctx);
    if (!pet.device.paired) throw new HttpError(409, 'Kalung belum terhubung');
    if (petView(store, pet).device.connection !== 'online') throw new HttpError(409, 'Kalung sedang offline, tidak dapat dibunyikan');
    enqueueCommand(store, pet.device.serial, 'ping');
    return { ok: true, message: `Perintah bunyi dikirim ke kalung ${pet.name}` };
  });

  /** Data langsung dari alat: paket terakhir, sumber (USB/jaringan), fix GPS, sensor. Untuk layar "Koneksi Alat". */
  router.get('/api/pets/:id/device/live', (ctx) => {
    const pet = ownPet(ctx);
    return { live: liveView(store, pet, petView(store, pet)) };
  });

  /** Alat yang terdeteksi mengirim paket tetapi belum dipasangkan (pairing sekali ketuk). */
  router.get('/api/devices/discovered', () => ({ devices: discoveredDevices(store) }));

  // ---------- Status kabel USB ----------
  router.get('/api/usb/status', async () => {
    const link = store.runtime.usb;
    const { driver } = createOpener();
    if (!link) return { usb: { enabled: false, driver, hint: 'Aktifkan dengan USB_PORT=auto di backend/.env lalu jalankan ulang server (atau npm run start:usb).' } };
    return { usb: { ...link.status(), driver } };
  });

  router.get('/api/usb/ports', async () => {
    try { return { ports: await listPorts() }; }
    catch (e) { return { ports: [], error: e.message }; }
  });

  // ---------- Geofence ----------
  const fenceView = (g) => ({ petId: g.petId, name: g.name, center: g.center, radius: g.radius, notifyExit: g.notifyExit, notifyEnter: g.notifyEnter });

  router.get('/api/pets/:id/geofence', (ctx) => {
    const pet = ownPet(ctx);
    let g = store.data.geofences.find((x) => x.petId === pet.id);
    if (!g) {
      g = newFence(pet.id);
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
    const next = {};
    if (b.radius !== undefined) {
      const r = Number(b.radius);
      if (b.radius === null || b.radius === '' || !(r >= 50 && r <= 5000)) throw new HttpError(422, 'Radius harus antara 50 m dan 5 km', { field: 'radius' });
      next.radius = Math.round(r);
    }
    if (b.notifyExit !== undefined && typeof b.notifyExit !== 'boolean') throw new HttpError(422, 'notifyExit harus true/false', { field: 'notifyExit' });
    if (b.notifyEnter !== undefined && typeof b.notifyEnter !== 'boolean') throw new HttpError(422, 'notifyEnter harus true/false', { field: 'notifyEnter' });
    if (b.center !== undefined) {
      const c = b.center;
      if (!c || !isFiniteNum(c.lat) || !isFiniteNum(c.lng) || Math.abs(c.lat) > 90 || Math.abs(c.lng) > 180) throw new HttpError(422, 'Koordinat pusat area tidak valid', { field: 'center' });
      next.center = { lat: c.lat, lng: c.lng };
    }
    if (b.name !== undefined) {
      const n = clean(b.name);
      if (!n) throw new HttpError(422, 'Nama area wajib diisi', { field: 'name' });
      next.name = n.slice(0, 24);
    }
    Object.assign(g, next);
    if (typeof b.notifyExit === 'boolean') g.notifyExit = b.notifyExit;
    if (typeof b.notifyEnter === 'boolean') g.notifyEnter = b.notifyEnter;
    g.auto = false; // sudah diatur pengguna: tidak lagi dipindah otomatis
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
    const type = clean(b.type).toLowerCase();
    if (!type) throw new HttpError(422, 'Jenis catatan wajib dipilih', { field: 'type' });
    if (!RECORD_TYPES.includes(type)) throw new HttpError(422, 'Jenis catatan tidak valid', { field: 'type' });
    if (b.date === undefined || b.date === null || clean(b.date) === '') throw new HttpError(422, 'Tanggal wajib diisi', { field: 'date' });
    if (!validDate(b.date)) throw new HttpError(422, 'Format tanggal tidak valid', { field: 'date' });
    if (b.date > addDays(wibDateKey(), 1)) throw new HttpError(422, 'Tanggal tidak boleh di masa depan', { field: 'date' });
    const date = b.date;
    let title = clean(b.title);
    if (title.length > 60) throw new HttpError(422, 'Judul maksimal 60 karakter', { field: 'title' });
    let value = null;
    if (type === 'berat') {
      if (b.value === undefined || b.value === null || clean(b.value) === '') throw new HttpError(422, 'Berat wajib diisi', { field: 'value' });
      value = Number(b.value);
      if (!(value > 0 && value <= 200)) throw new HttpError(422, 'Berat harus antara 0,1 dan 200 kg', { field: 'value' });
      value = Math.round(value * 10) / 10;
      title = title || 'Berat badan';
    } else if (!title) throw new HttpError(422, 'Judul catatan wajib diisi', { field: 'title' });
    const note = clean(b.note);
    if (note.length > 300) throw new HttpError(422, 'Keterangan maksimal 300 karakter', { field: 'note' });
    const rec = { id: store.id('rec'), userId: ctx.user.id, petId: pet.id, type, title, value, date, note, createdAt: new Date().toISOString() };
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
    const mine = store.data.notifications.filter((n) => n.userId === user.id);
    let list = mine;
    if (query.category && query.category !== 'semua') list = list.filter((n) => n.category === query.category);
    const limit = clamp(Math.floor(Number(query.limit)) || 200, 1, 500);
    list = [...list].sort((a, b) => new Date(b.time) - new Date(a.time)).slice(0, limit);
    return { notifications: list, unread: mine.filter((n) => !n.read).length };
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

  // ---------- IoT: telemetri dari kalung GPS (jaringan atau bridge USB) ----------
  router.post('/api/device/telemetry', { auth: false }, (ctx) => {
    requireDeviceKey(ctx.req);
    const b = ctx.body;
    // Body JSON diperlakukan seperti satu baris protokol alat: field, alias, dan validasinya sama persis dengan jalur USB.
    const msg = parseLine(JSON.stringify(b));
    const fLat = toNum(b.fallbackLat), fLng = toNum(b.fallbackLng);
    const fallback = fLat !== null && fLng !== null && validCoords(fLat, fLng) ? { lat: fLat, lng: fLng } : null;
    const res = handleDeviceMessage(store, msg, { source: b.via === 'usb' ? 'usb' : 'http', port: b.port ? String(b.port).slice(0, 60) : undefined, fallback });
    if (!res.ok) throw new HttpError(res.status, res.error, { code: res.code });
    const { ok, status, ...rest } = res;
    return { ok: true, ...rest };
  });

  /** Bridge USB mengambil perintah (mis. "bunyikan") saat alat sedang diam. */
  router.get('/api/device/commands', { auth: false }, (ctx) => {
    requireDeviceKey(ctx.req);
    const serial = normalizeSerial(ctx.query.serial);
    if (!serial) throw new HttpError(422, 'Parameter serial tidak valid');
    return { commands: drainCommands(store, serial) };
  });

  // ---------- Live stream (Server-Sent Events) ----------
  router.get('/api/stream', (ctx) => {
    const { req, res, user } = ctx;
    res.writeHead(200, {
      'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive', 'X-Accel-Buffering': 'no',
      ...corsHeaders(req),
    });
    res.write('retry: 3000\n\n');
    const send = (event, data) => { if (!res.writableEnded) res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`); };
    const onPet = (e) => e.userId === user.id && send('pet', e.pet);
    const onNtf = (e) => e.userId === user.id && send('notification', e.notification);
    bus.on('pet', onPet);
    bus.on('notification', onNtf);
    const hb = setInterval(() => { if (!res.writableEnded) res.write(': ping\n\n'); }, 20000);
    req.on('close', () => { clearInterval(hb); bus.off('pet', onPet); bus.off('notification', onNtf); });
    send('hello', { user: userView(user) });
  });
};
