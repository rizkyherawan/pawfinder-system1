'use strict';
const { EventEmitter } = require('events');
const config = require('../config');
const { haversine, reverseGeocode, wibDateKey, addDays, dayLabel } = require('../geo');

/** Bus event untuk live stream (SSE) ke web dashboard. */
const bus = new EventEmitter();
bus.setMaxListeners(200);

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

// Kategori setiap jenis kejadian. Satu log kejadian dipakai bersama oleh Riwayat dan Notifikasi.
const CATEGORY = {
  exit: 'geofence', enter: 'geofence', geofence_updated: 'geofence',
  battery: 'sistem', gps_paired: 'sistem', gps_connected: 'sistem', gps_offline: 'sistem', gps_unpaired: 'sistem',
  pet_added: 'hewan', pet_updated: 'hewan', pet_deleted: 'hewan',
  health_record: 'kesehatan',
};

/** Status koneksi GPS: unpaired | waiting | online | offline (berdasarkan telemetri nyata terakhir). */
function connectionOf(pet) {
  const d = pet.device;
  if (!d || !d.paired) return 'unpaired';
  if (!d.lastSeen) return 'waiting';
  const limitMs = Math.max(90, (d.intervalSec || 30) * 3) * 1000;
  return Date.now() - new Date(d.lastSeen).getTime() <= limitMs ? 'online' : 'offline';
}

/** Tampilan publik hewan (tanpa field internal). */
function petView(store, pet) {
  const fence = store.data.geofences.find((g) => g.petId === pet.id);
  const d = pet.device;
  const connection = connectionOf(pet);
  return {
    id: pet.id,
    name: pet.name,
    species: pet.species,
    gender: pet.gender,
    birthDate: pet.birthDate || null,
    avatarColor: pet.avatarColor || 0,
    photoVersion: pet.photo ? pet.photo.version : 0,
    device: {
      paired: !!d.paired,
      serial: d.serial || null,
      firmware: d.firmware || '1.2.0',
      battery: typeof d.battery === 'number' ? d.battery : null,
      signal: d.signal || null,
      connection,
      online: connection === 'online',
      lastSeen: d.lastSeen || null,
      intervalSec: d.intervalSec || 30,
    },
    location: pet.location || null,
    insideGeofence: pet.insideGeofence === undefined ? null : pet.insideGeofence,
    geofenceName: fence ? fence.name : null,
    geofenceRadius: fence ? fence.radius : null,
  };
}

/**
 * Mencatat satu kejadian. Kejadian masuk ke Riwayat; bila notify=true juga masuk ke Notifikasi
 * dengan isi yang sama persis, sehingga keduanya selalu konsisten.
 */
function logEvent(store, e) {
  const base = {
    userId: e.userId,
    petId: e.petId || null,
    category: CATEGORY[e.type] || 'sistem',
    type: e.type,
    title: e.title,
    subtitle: e.subtitle || '',
    time: (e.time || new Date()).toISOString(),
  };
  const evt = { id: store.id('evt'), ...base };
  store.data.events.unshift(evt);
  if (store.data.events.length > 3000) store.data.events.length = 3000;
  if (e.notify !== false) {
    const ntf = { id: store.id('ntf'), ...base, read: false };
    store.data.notifications.unshift(ntf);
    if (store.data.notifications.length > 1000) store.data.notifications.length = 1000;
    bus.emit('notification', { userId: e.userId, notification: ntf });
  }
  return evt;
}

function addStats(store, petId, movedMeters, seconds) {
  const key = `${petId}:${wibDateKey()}`;
  const s = store.data.stats[key] || (store.data.stats[key] = { steps: 0, distanceKm: 0, activeSec: 0 });
  if (movedMeters > 2) {
    s.steps += Math.round(movedMeters / 0.6);
    s.distanceKm = Math.round((s.distanceKm + movedMeters / 1000) * 1000) / 1000;
    s.activeSec += clamp(seconds || 5, 1, 120);
  }
}

const shortAddr = (address) => String(address).split(',')[0].trim();

/** Menyinkronkan status koneksi dan mencatat kejadian saat berubah (terhubung / terputus). */
function syncConnection(store, pet) {
  const d = pet.device;
  if (!d.paired) return false;
  const now = connectionOf(pet);
  const prev = d.connState || 'waiting';
  if (now === prev) return false;
  d.connState = now;
  if (now === 'online') {
    const first = !d.everConnected;
    d.everConnected = true;
    logEvent(store, {
      userId: pet.userId, petId: pet.id, type: 'gps_connected',
      title: first ? 'GPS terhubung' : 'Koneksi GPS tersambung kembali',
      subtitle: `${pet.name} kini dilacak secara real-time`,
    });
  } else if (now === 'offline' && prev === 'online') {
    logEvent(store, { userId: pet.userId, petId: pet.id, type: 'gps_offline', title: 'Koneksi GPS terputus', subtitle: `Tidak ada sinyal dari kalung ${pet.name}` });
  }
  store.save();
  bus.emit('pet', { userId: pet.userId, pet: petView(store, pet) });
  return true;
}

function syncAllConnections(store) {
  for (const pet of store.data.pets) syncConnection(store, pet);
}

/**
 * Titik masuk semua data lokasi: dipakai oleh endpoint telemetri perangkat nyata maupun simulator.
 */
function ingestTelemetry(store, pet, t) {
  const now = new Date();
  const prev = pet.location;
  const point = { lat: Number(t.lat), lng: Number(t.lng) };
  const moved = prev ? haversine(prev, point) : 0;
  const seconds = prev ? (now - new Date(prev.updatedAt)) / 1000 : 0;

  pet.location = { lat: point.lat, lng: point.lng, address: reverseGeocode(point, config.home), updatedAt: now.toISOString() };
  if (typeof t.battery === 'number') pet.device.battery = clamp(Math.round(t.battery), 0, 100);
  if (t.signal) pet.device.signal = t.signal;
  if (Number.isFinite(t.heartRate) || Number.isFinite(t.temperature)) {
    pet.vitals = {
      heartRate: Number.isFinite(t.heartRate) ? Math.round(t.heartRate) : (pet.vitals && pet.vitals.heartRate) || null,
      temperature: Number.isFinite(t.temperature) ? Math.round(t.temperature * 10) / 10 : (pet.vitals && pet.vitals.temperature) || null,
      updatedAt: now.toISOString(),
    };
  }
  pet.device.lastSeen = now.toISOString();
  addStats(store, pet.id, moved, seconds);
  syncConnection(store, pet);

  // Geofence
  const fence = store.data.geofences.find((g) => g.petId === pet.id);
  if (fence) {
    const inside = haversine(fence.center, point) <= fence.radius;
    const was = pet.insideGeofence;
    pet.insideGeofence = inside;
    if (was !== undefined && was !== inside) {
      const where = shortAddr(pet.location.address);
      if (!inside) {
        logEvent(store, { userId: pet.userId, petId: pet.id, type: 'exit', title: `${pet.name} keluar dari Geofence`, subtitle: `${where} · Di luar area ${fence.name}`, notify: fence.notifyExit });
      } else {
        logEvent(store, { userId: pet.userId, petId: pet.id, type: 'enter', title: `${pet.name} masuk ke Geofence`, subtitle: `${where} · Area ${fence.name}`, notify: fence.notifyEnter });
      }
    }
  }

  // Baterai rendah (sekali per siklus pengisian)
  if (typeof pet.device.battery === 'number') {
    if (pet.device.battery <= 20 && !pet.device.lowNotified) {
      pet.device.lowNotified = true;
      logEvent(store, { userId: pet.userId, petId: pet.id, type: 'battery', title: 'Baterai perangkat rendah', subtitle: `${pet.name} · Baterai ${pet.device.battery}% · Segera isi daya` });
    }
    if (pet.device.battery > 30) pet.device.lowNotified = false;
  }

  store.save();
  bus.emit('pet', { userId: pet.userId, pet: petView(store, pet) });
  return pet;
}

/** Ringkasan aktivitas (langkah, jarak, waktu aktif, kalori, 7 hari). */
function activitySummary(store, pet) {
  const today = wibDateKey();
  const get = (k) => store.data.stats[`${pet.id}:${k}`] || { steps: 0, distanceKm: 0, activeSec: 0 };
  const t = get(today);
  const week = [];
  for (let i = 6; i >= 0; i--) {
    const k = addDays(today, -i);
    week.push({ date: k, label: dayLabel(k), minutes: Math.round(get(k).activeSec / 60) });
  }
  return {
    connected: connectionOf(pet) !== 'unpaired',
    steps: t.steps,
    goal: config.dailyStepGoal,
    distanceKm: Math.round(t.distanceKm * 10) / 10,
    activeMinutes: Math.round(t.activeSec / 60),
    calories: Math.round(t.steps * 0.051),
    week,
  };
}

/** Ringkasan kesehatan: tanda vital dari sensor kalung + catatan kesehatan buatan pengguna. */
function healthSummary(store, pet) {
  const records = store.data.healthRecords.filter((r) => r.petId === pet.id).sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : b.createdAt.localeCompare(a.createdAt)));
  const weight = records.find((r) => r.type === 'berat');
  const vaccine = records.find((r) => r.type === 'vaksin');
  const connected = connectionOf(pet) === 'online';
  return {
    sensor: { available: !!pet.vitals, live: connected, heartRate: pet.vitals ? pet.vitals.heartRate : null, temperature: pet.vitals ? pet.vitals.temperature : null, updatedAt: pet.vitals ? pet.vitals.updatedAt : null },
    summary: { latestWeightKg: weight ? weight.value : null, latestWeightDate: weight ? weight.date : null, lastVaccine: vaccine ? { title: vaccine.title, date: vaccine.date } : null, total: records.length },
    records,
  };
}

module.exports = { bus, CATEGORY, connectionOf, petView, logEvent, ingestTelemetry, syncConnection, syncAllConnections, activitySummary, healthSummary, clamp };
