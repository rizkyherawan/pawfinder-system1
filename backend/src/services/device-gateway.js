'use strict';
/**
 * Gateway alat: SATU pintu masuk untuk semua paket dari kalung GPS, apa pun jalurnya
 * (kabel USB langsung ke server, bridge USB lewat HTTP, atau alat jaringan). Hasilnya selalu sama.
 */
const config = require('../config');
const { ingestTelemetry, ingestHeartbeat } = require('./engine');
const { validCoords } = require('./device-protocol');

const COMMAND_TTL_MS = 60_000;      // perintah yang tidak diambil alat dalam 60 detik dibuang
const USB_MIN_INTERVAL_MS = 800;    // batas laju paket USB agar aliran cepat tidak membebani server
const DISCOVERED_TTL_MS = 120_000;  // alat dianggap "terdeteksi" bila mengirim paket dalam 2 menit terakhir
const MAX_QUEUE = 10;

// ---------- Antrean perintah server -> alat ----------
function enqueueCommand(store, serial, cmd, arg) {
  if (!serial) return false;
  const q = store.runtime.commands.get(serial) || [];
  // Perintah sejenis hanya disimpan satu (yang terbaru), kecuali ping yang boleh diulang.
  const filtered = cmd === 'ping' ? q : q.filter((c) => c.cmd !== cmd);
  filtered.push({ cmd, arg, at: Date.now() });
  while (filtered.length > MAX_QUEUE) filtered.shift();
  store.runtime.commands.set(serial, filtered);
  return true;
}

function drainCommands(store, serial) {
  const q = store.runtime.commands.get(serial);
  if (!q || !q.length) return [];
  store.runtime.commands.delete(serial);
  const now = Date.now();
  return q.filter((c) => now - c.at <= COMMAND_TTL_MS).map((c) => ({ cmd: c.cmd, arg: c.arg }));
}

function pendingCommands(store, serial) {
  const q = store.runtime.commands.get(serial) || [];
  const now = Date.now();
  return q.filter((c) => now - c.at <= COMMAND_TTL_MS).length;
}

// ---------- Status langsung ----------
function recordLive(store, serial, msg, source, ctx, nowMs) {
  const live = store.runtime.live.get(serial) || { serial, firstAt: nowMs, packets: 0, rejected: 0 };
  live.source = source;
  live.port = ctx.port || null;
  live.lastAt = nowMs;
  live.packets++;
  live.kind = msg.kind;
  if (msg.kind === 'telemetry') {
    const { kind, serial: _s, ...rest } = msg;
    live.lastPacket = rest;
  }
  store.runtime.live.set(serial, live);
  return live;
}

function liveView(store, pet, petViewObj) {
  const d = pet.device;
  const live = (d.serial && store.runtime.live.get(d.serial)) || null;
  const pk = (live && live.lastPacket) || {};
  const now = Date.now();
  return {
    paired: !!d.paired,
    serial: d.serial || null,
    connection: petViewObj.device.connection,
    source: petViewObj.device.source,
    port: live ? live.port : null,
    packets: live ? live.packets : 0,
    lastPacketAt: live ? new Date(live.lastAt).toISOString() : null,
    ageSec: live ? Math.max(0, Math.round((now - live.lastAt) / 1000)) : null,
    gpsFix: petViewObj.device.gpsFix,
    locationMode: live && live.locationMode ? live.locationMode : (petViewObj.device.gpsFix ? 'gps' : null),
    satellites: pk.satellites === undefined ? petViewObj.device.satellites : pk.satellites,
    hdop: pk.hdop === undefined ? null : pk.hdop,
    speedKmh: pk.speedKmh === undefined ? null : pk.speedKmh,
    lat: pet.location ? pet.location.lat : null,
    lng: pet.location ? pet.location.lng : null,
    address: pet.location ? pet.location.address : null,
    battery: petViewObj.device.battery,
    signal: petViewObj.device.signal,
    heartRate: pet.vitals ? pet.vitals.heartRate : null,
    temperature: pet.vitals ? pet.vitals.temperature : null,
    firmware: petViewObj.device.firmware,
    pendingCommands: d.serial ? pendingCommands(store, d.serial) : 0,
  };
}

/** Alat yang mengirim paket tetapi belum dipasangkan ke hewan mana pun (untuk pairing sekali ketuk). */
function discoveredDevices(store) {
  const now = Date.now();
  const paired = new Set(store.data.pets.filter((p) => p.device && p.device.paired).map((p) => p.device.serial));
  const out = [];
  for (const [serial, d] of store.runtime.discovered) {
    if (now - d.lastAt > DISCOVERED_TTL_MS) { store.runtime.discovered.delete(serial); continue; }
    if (paired.has(serial)) continue;
    out.push({ serial, source: d.source, port: d.port || null, firmware: d.firmware || null, battery: d.battery === undefined ? null : d.battery, lastSeenSec: Math.round((now - d.lastAt) / 1000) });
  }
  return out.sort((a, b) => a.lastSeenSec - b.lastSeenSec);
}

/** Tautan USB terputus: alat yang lewat tautan itu langsung ditandai offline (tidak menunggu batas waktu). */
function markLinkClosed(store, serials) {
  const { syncConnection } = require('./engine');
  const set = new Set(serials);
  for (const pet of store.data.pets) {
    if (pet.device && pet.device.paired && set.has(pet.device.serial) && pet.device.lastSeen) {
      pet.device.forceOffline = true;
      syncConnection(store, pet);
    }
  }
}

const reject = (status, code, error, extra) => ({ ok: false, status, code, error, ...(extra || {}) });

/**
 * Memproses satu pesan alat yang sudah di-parse (lihat device-protocol.js).
 * ctx: { source: 'usb'|'http', port?, defaultSerial?, fallback?: {lat,lng} }
 * Mengembalikan { ok, status, ... } — selalu objek, tidak pernah melempar untuk input alat yang salah.
 */
function handleDeviceMessage(store, msg, ctx = {}) {
  const source = ctx.source === 'usb' ? 'usb' : 'http';
  const nowMs = Date.now();
  if (!msg || msg.kind === 'log') return { ok: true, status: 200, ignored: true };
  if (msg.kind === 'unknown') return reject(422, 'UNPARSEABLE', `Paket tidak dapat dibaca (${msg.reason || 'format tidak dikenali'})`);
  if (msg.badSerial) return reject(422, 'BAD_SERIAL', `Format ID alat tidak valid: "${msg.badSerial}". Contoh benar: PF-ABC-123456`);

  const serial = msg.serial || ctx.defaultSerial || '';
  if (!serial) return reject(422, 'NO_SERIAL', 'ID alat tidak diketahui. Kirim field "serial" (PF-XXX-000000) atau isi USB_SERIAL di server.');
  if (msg.badCoords) return reject(422, 'BAD_COORDS', 'Koordinat tidak valid');

  const live = recordLive(store, serial, msg, source, ctx, nowMs);
  const pet = store.data.pets.find((p) => p.device && p.device.paired && p.device.serial === serial);
  if (!pet) {
    live.rejected++;
    store.runtime.discovered.set(serial, { serial, source, port: ctx.port || null, firmware: msg.firmware, battery: msg.battery, lastAt: nowMs });
    return reject(404, 'UNPAIRED', `Perangkat ${serial} belum dipasangkan ke hewan. Pasangkan lewat aplikasi lebih dulu.`);
  }
  store.runtime.discovered.delete(serial);

  const d = pet.device;
  const reply = (extra) => ({ ok: true, status: 200, serial, commands: drainCommands(store, serial), config: { intervalSec: d.intervalSec || 30 }, ...extra });

  if (msg.kind === 'ack') { live.lastAck = msg.command || ''; return reply({}); }

  d.simulated = false; // perangkat nyata mengambil alih dari simulator
  if (msg.kind === 'hello') {
    ingestHeartbeat(store, pet, { firmware: msg.firmware, source, keepFix: true });
    // Sinkronkan interval dari aplikasi ke firmware begitu alat memperkenalkan diri.
    enqueueCommand(store, serial, 'interval', d.intervalSec || 30);
    return reply({ hello: true });
  }

  // kind === 'telemetry'
  if (source === 'usb') {
    if (nowMs - (d.lastIngestMs || 0) < USB_MIN_INTERVAL_MS) return reply({ throttled: true });
    d.lastIngestMs = nowMs;
  }
  const t = { battery: msg.battery, signal: msg.signal, heartRate: msg.heartRate, temperature: msg.temperature, satellites: msg.satellites, firmware: msg.firmware, source };

  let lat = msg.lat, lng = msg.lng;
  let mode = 'gps';
  if (!(msg.fix && lat !== undefined) && ctx.fallback && validCoords(ctx.fallback.lat, ctx.fallback.lng)) {
    // Prototipe tanpa modul GPS: pakai koordinat tetap yang diatur eksplisit oleh pengembang.
    lat = ctx.fallback.lat; lng = ctx.fallback.lng; mode = 'tetap';
  }
  live.locationMode = lat !== undefined ? mode : null;

  if (lat !== undefined && lng !== undefined) {
    ingestTelemetry(store, pet, { ...t, lat, lng });
    return reply({ fix: true, locationMode: mode, insideGeofence: pet.insideGeofence, address: pet.location.address });
  }
  ingestHeartbeat(store, pet, t);
  return reply({ fix: false, locationMode: null, insideGeofence: pet.insideGeofence === undefined ? null : pet.insideGeofence, address: pet.location ? pet.location.address : null });
}

module.exports = { handleDeviceMessage, enqueueCommand, drainCommands, pendingCommands, liveView, discoveredDevices, markLinkClosed, USB_MIN_INTERVAL_MS };
