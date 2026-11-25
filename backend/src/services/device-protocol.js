'use strict';
/**
 * Protokol komunikasi alat PawFinder (kalung GPS berbasis Arduino) — murni parsing, tanpa dependensi.
 *
 * Alat boleh mengirim SATU baris per paket lewat kabel USB (serial), format mana pun di bawah ini:
 *
 *  1) JSON (paling mudah dibaca)
 *     {"serial":"PF-ABC-123456","lat":-7.71556,"lng":110.35547,"fix":1,"bat":87,"sig":"Kuat","hr":96,"temp":38.6,"sat":7}
 *     Perkenalan:  {"hello":"PF-ABC-123456","fw":"1.0.0"}
 *
 *  2) CSV ringkas (hemat RAM Arduino Uno)
 *     PF,<serial>,<lat>,<lng>,<baterai>,<fix>[,<detak>,<suhu>,<satelit>]
 *     PF,PF-ABC-123456,-7.71556,110.35547,87,1,96,38.6,7
 *     PF,HELLO,PF-ABC-123456,1.0.0
 *     PF,ACK,PING
 *
 *  3) NMEA mentah dari modul GPS ($GPGGA / $GPRMC / $GNGGA / $GNRMC). ID alat diisi oleh sisi server/bridge.
 *
 * Arah sebaliknya (server -> alat), satu baris per perintah:  PING | INTERVAL <detik> | WHO
 */

const SERIAL_RE = /^PF-[A-Z0-9]{3}-\d{6}$/;
const MAX_LINE = 1024;

const isBlank = (v) => v === undefined || v === null || (typeof v === 'string' && v.trim() === '');

/** Angka dari number atau teks ("12,5" juga diterima). null bila tidak valid. */
function toNum(v) {
  if (isBlank(v) || typeof v === 'boolean') return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const n = Number(String(v).trim().replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

function normalizeSerial(v) {
  if (isBlank(v)) return null;
  const s = String(v).trim().toUpperCase();
  return SERIAL_RE.test(s) ? s : null;
}

/** Koordinat sah: dalam rentang bumi dan bukan (0,0) — nilai yang dikirim modul GPS sebelum mendapat sinyal. */
function validCoords(lat, lng) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return false;
  if (Math.abs(lat) < 1e-6 && Math.abs(lng) < 1e-6) return false;
  return true;
}

function toBool(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v === 'number') return v !== 0;
  if (typeof v === 'string') {
    const s = v.trim().toLowerCase();
    if (['1', 'true', 'a', 'y', 'ya', 'yes'].includes(s)) return true;
    if (['0', 'false', 'v', 'n', 'no', 'tidak', ''].includes(s)) return false;
  }
  return undefined;
}

/** Kekuatan sinyal: teks (Kuat/Sedang/Lemah, strong/medium/weak) atau jumlah batang 0-4. */
function normalizeSignal(v) {
  if (isBlank(v)) return undefined;
  const n = toNum(v);
  if (n !== null) {
    if (n >= 3) return 'Kuat';
    if (n >= 2) return 'Sedang';
    return 'Lemah';
  }
  const s = String(v).trim().toLowerCase();
  if (['kuat', 'strong', 'good', 'high', 'tinggi'].includes(s)) return 'Kuat';
  if (['sedang', 'medium', 'mid', 'fair'].includes(s)) return 'Sedang';
  if (['lemah', 'weak', 'poor', 'low', 'rendah'].includes(s)) return 'Lemah';
  return undefined;
}

/** Membersihkan dan membakukan SATU paket telemetri dari objek mentah (JSON, CSV, atau body HTTP). */
function normalizeTelemetry(o) {
  const out = { kind: 'telemetry' };
  const serial = normalizeSerial(o.serial ?? o.id ?? o.sn ?? o.device);
  if (serial) out.serial = serial;
  else if (!isBlank(o.serial ?? o.id ?? o.sn ?? o.device)) out.badSerial = String(o.serial ?? o.id ?? o.sn ?? o.device).slice(0, 40);

  const latRaw = o.lat ?? o.latitude;
  const lngRaw = o.lng ?? o.lon ?? o.long ?? o.longitude;
  const hasCoordFields = !isBlank(latRaw) || !isBlank(lngRaw);
  const lat = toNum(latRaw), lng = toNum(lngRaw);
  const fixFlag = toBool(o.fix ?? o.gpsFix ?? o.valid);

  if (hasCoordFields) {
    if (lat !== null && lng !== null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
      // (0,0) = belum ada sinyal GPS: bukan lokasi, tetapi alatnya tetap hidup.
      if (validCoords(lat, lng)) { out.lat = lat; out.lng = lng; }
    } else {
      out.badCoords = true; // diisi tetapi di luar rentang / bukan angka
    }
  }
  const located = out.lat !== undefined;
  out.fix = located && fixFlag !== false; // fix=0 membatalkan koordinat yang ikut terkirim
  if (!out.fix) { delete out.lat; delete out.lng; }

  const bat = toNum(o.bat ?? o.battery ?? o.batt);
  if (bat !== null) out.battery = Math.min(100, Math.max(0, Math.round(bat)));
  const sig = normalizeSignal(o.sig ?? o.signal);
  if (sig) out.signal = sig;
  const hr = toNum(o.hr ?? o.heartRate ?? o.bpm);
  if (hr !== null && hr >= 20 && hr <= 400) out.heartRate = Math.round(hr);
  const temp = toNum(o.temp ?? o.temperature);
  if (temp !== null && temp >= 20 && temp <= 50) out.temperature = Math.round(temp * 10) / 10;
  const sat = toNum(o.sat ?? o.sats ?? o.satellites);
  if (sat !== null && sat >= 0 && sat <= 64) out.satellites = Math.round(sat);
  const hdop = toNum(o.hdop);
  if (hdop !== null && hdop >= 0 && hdop < 100) out.hdop = hdop;
  const spd = toNum(o.spd ?? o.speed ?? o.speedKmh);
  if (spd !== null && spd >= 0 && spd < 400) out.speedKmh = Math.round(spd * 10) / 10;
  const fw = o.fw ?? o.firmware ?? o.v;
  if (!isBlank(fw)) out.firmware = String(fw).trim().slice(0, 20);
  return out;
}

const RECOGNIZED = ['serial', 'id', 'sn', 'device', 'lat', 'latitude', 'lng', 'lon', 'long', 'longitude', 'fix', 'gpsFix', 'valid', 'bat', 'battery', 'batt', 'sig', 'signal', 'hr', 'heartRate', 'bpm', 'temp', 'temperature', 'sat', 'sats', 'satellites', 'hdop', 'spd', 'speed', 'speedKmh'];

function parseJson(line) {
  let o;
  try { o = JSON.parse(line); } catch (_) { return { kind: 'unknown', reason: 'JSON tidak valid' }; }
  if (o === null || typeof o !== 'object' || Array.isArray(o)) return { kind: 'unknown', reason: 'JSON harus berupa objek' };
  const type = String(o.type ?? o.t ?? '').toLowerCase();
  if (o.hello !== undefined || type === 'hello') {
    return { kind: 'hello', serial: normalizeSerial(o.hello === true || o.hello === undefined ? (o.serial ?? o.id) : o.hello) || undefined, firmware: isBlank(o.fw ?? o.firmware) ? undefined : String(o.fw ?? o.firmware).trim().slice(0, 20) };
  }
  if (o.ack !== undefined || type === 'ack') return { kind: 'ack', command: String(o.ack ?? o.cmd ?? '').toUpperCase().slice(0, 20), serial: normalizeSerial(o.serial ?? o.id) || undefined };
  if (!RECOGNIZED.some((k) => k in o)) return { kind: 'unknown', reason: 'tidak ada field yang dikenali' };
  return normalizeTelemetry(o);
}

function parseCsv(line) {
  const f = line.split(',').map((s) => s.trim());
  if (f[0].toUpperCase() !== 'PF') return { kind: 'unknown', reason: 'CSV harus diawali "PF,"' };
  const head = (f[1] || '').toUpperCase();
  if (head === 'HELLO') return { kind: 'hello', serial: normalizeSerial(f[2]) || undefined, firmware: isBlank(f[3]) ? undefined : f[3].slice(0, 20) };
  if (head === 'ACK') return { kind: 'ack', command: String(f[2] || '').toUpperCase().slice(0, 20) };
  if (f.length < 5) return { kind: 'unknown', reason: 'CSV kurang kolom (minimal 5)' };
  return normalizeTelemetry({ serial: f[1], lat: f[2], lng: f[3], bat: f[4], fix: f[5], hr: f[6], temp: f[7], sat: f[8] });
}

/** Koordinat NMEA "ddmm.mmmm" + belahan bumi -> derajat desimal. null bila salah format. */
function nmeaCoord(value, hemi, degDigits) {
  if (isBlank(value) || isBlank(hemi) || !/^\d+(\.\d+)?$/.test(value)) return null;
  const intPart = value.split('.')[0];
  if (intPart.length < degDigits + 2) return null;
  const deg = Number(value.slice(0, degDigits));
  const min = Number(value.slice(degDigits));
  if (!Number.isFinite(deg) || !Number.isFinite(min) || min >= 60) return null;
  let dec = deg + min / 60;
  const h = String(hemi).toUpperCase();
  if (h === 'S' || h === 'W') dec = -dec;
  else if (h !== 'N' && h !== 'E') return null;
  return dec;
}

function nmeaChecksumOk(sentence) {
  const star = sentence.lastIndexOf('*');
  if (star < 0) return true; // checksum tidak wajib
  const body = sentence.slice(1, star);
  let x = 0;
  for (let i = 0; i < body.length; i++) x ^= body.charCodeAt(i);
  const given = parseInt(sentence.slice(star + 1, star + 3), 16);
  return Number.isFinite(given) && given === x;
}

function parseNmea(line) {
  if (!nmeaChecksumOk(line)) return { kind: 'unknown', reason: 'checksum NMEA salah' };
  const body = line.slice(1).split('*')[0];
  const f = body.split(',');
  const id = f[0] || '';
  const type = id.slice(-3).toUpperCase();
  if (type === 'GGA') {
    const quality = toNum(f[6]);
    const lat = nmeaCoord(f[2], f[3], 2), lng = nmeaCoord(f[4], f[5], 3);
    const fix = quality !== null && quality > 0 && lat !== null && lng !== null && validCoords(lat, lng);
    return normalizeTelemetry({ lat: fix ? lat : undefined, lng: fix ? lng : undefined, fix, sat: f[7], hdop: f[8] });
  }
  if (type === 'RMC') {
    const active = String(f[2] || '').toUpperCase() === 'A';
    const lat = nmeaCoord(f[3], f[4], 2), lng = nmeaCoord(f[5], f[6], 3);
    const fix = active && lat !== null && lng !== null && validCoords(lat, lng);
    const knots = toNum(f[7]);
    return normalizeTelemetry({ lat: fix ? lat : undefined, lng: fix ? lng : undefined, fix, spd: knots === null ? undefined : knots * 1.852 });
  }
  return { kind: 'log', text: id }; // kalimat NMEA lain (GSV, GSA, VTG, ...) diabaikan
}

/**
 * Menguraikan satu baris dari alat.
 * @returns null (baris kosong) | {kind:'telemetry'|'hello'|'ack'|'log'|'unknown', ...}
 */
function parseLine(raw) {
  const line = String(raw === undefined || raw === null ? '' : raw).replace(/[\u0000-\u0008\u000B-\u001F\u007F]/g, '').trim();
  if (!line) return null;
  if (line.length > MAX_LINE) return { kind: 'unknown', reason: 'baris terlalu panjang' };
  if (line.startsWith('#') || line.startsWith('//')) return { kind: 'log', text: line.slice(0, 120) }; // komentar/debug dari firmware
  const c = line[0];
  if (c === '{') return parseJson(line);
  if (c === '$') return parseNmea(line);
  if (/^pf\s*,/i.test(line)) return parseCsv(line);
  return { kind: 'unknown', reason: 'format tidak dikenali' };
}

/** Pemotong aliran byte menjadi baris (\n, \r\n, atau \r), tahan terhadap baris terpotong dan banjir data. */
class LineSplitter {
  constructor(maxLine = MAX_LINE) {
    this.maxLine = maxLine;
    this.buf = '';
    this.overflow = false;
    this.dropped = 0;
    const { StringDecoder } = require('string_decoder');
    this.decoder = new StringDecoder('utf8');
  }

  feed(chunk) {
    const text = typeof chunk === 'string' ? chunk : this.decoder.write(chunk);
    const lines = [];
    for (const ch of text) {
      if (ch === '\n' || ch === '\r') {
        if (this.overflow) { this.overflow = false; this.dropped++; }
        else if (this.buf.length) lines.push(this.buf);
        this.buf = '';
      } else if (!this.overflow) {
        this.buf += ch;
        if (this.buf.length > this.maxLine) { this.overflow = true; this.buf = ''; }
      }
    }
    return lines;
  }
}

/** Perintah server -> alat sebagai satu baris teks. null bila perintah tidak dikenal. */
function encodeCommand(cmd, arg) {
  switch (String(cmd).toLowerCase()) {
    case 'ping': return 'PING\n';
    case 'who': return 'WHO\n';
    case 'interval': {
      const n = Math.round(Number(arg));
      return Number.isFinite(n) && n >= 1 && n <= 3600 ? `INTERVAL ${n}\n` : null;
    }
    default: return null;
  }
}

module.exports = { SERIAL_RE, MAX_LINE, parseLine, normalizeTelemetry, normalizeSerial, validCoords, nmeaCoord, LineSplitter, encodeCommand, toNum };
