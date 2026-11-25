'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Pemuat .env sederhana (tanpa dependensi dotenv)
(function loadEnv() {
  const file = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
    }
  }
})();

const env = process.env;
const argv = process.argv.slice(2);
/** --nama atau --nama=nilai pada baris perintah. */
const hasFlag = (name) => argv.some((a) => a === `--${name}` || a.startsWith(`--${name}=`));
const flagValue = (name) => {
  const a = argv.find((x) => x.startsWith(`--${name}=`));
  return a ? a.slice(name.length + 3) : undefined;
};
const num = (v, def, min, max) => {
  const n = Number(v);
  if (v === undefined || v === '' || !Number.isFinite(n)) return def;
  return Math.min(max === undefined ? n : max, Math.max(min === undefined ? n : min, n));
};
const optNum = (v) => (v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));

const isProd = String(env.NODE_ENV || '').toLowerCase() === 'production';
const DEFAULT_DEVICE_KEY = 'pawfinder-device-key';
const dataFile = path.resolve(env.DATA_FILE || path.join(__dirname, '..', 'data', 'db.json'));
const dataDir = path.dirname(dataFile);

/**
 * Rahasia penandatangan token. Prioritas: JWT_SECRET di .env; jika tidak ada, dibuat acak sekali
 * lalu disimpan di folder data (sesi login tetap berlaku setelah server dihidupkan ulang).
 */
function resolveJwtSecret() {
  if (env.JWT_SECRET && env.JWT_SECRET.length >= 16) return env.JWT_SECRET;
  const file = path.join(dataDir, 'jwt.secret');
  try {
    fs.mkdirSync(dataDir, { recursive: true });
    if (fs.existsSync(file)) {
      const s = fs.readFileSync(file, 'utf8').trim();
      if (s.length >= 32) return s;
    }
    const s = crypto.randomBytes(48).toString('hex');
    fs.writeFileSync(file, s, { mode: 0o600 });
    return s;
  } catch (_) {
    return crypto.randomBytes(48).toString('hex'); // folder tidak bisa ditulis: berlaku selama proses berjalan
  }
}

const usbFlag = hasFlag('usb');
const usbPort = String(flagValue('usb') || env.USB_PORT || (usbFlag ? 'auto' : '')).trim();

module.exports = {
  isProd,
  port: num(env.PORT, 4000, 1, 65535),
  host: env.HOST || '0.0.0.0',
  jwtSecret: resolveJwtSecret(),
  tokenTtlDays: 30,
  dataFile,
  storageDriver: env.STORAGE_DRIVER || 'json',
  firebase: {
    databaseURL: env.FIREBASE_DATABASE_URL || '',
    keyPath: env.FIREBASE_KEY_PATH || '',
  },
  // Hasil `flutter build web` disajikan oleh server (opsional).
  webDir: path.resolve(env.WEB_DIR || path.join(__dirname, '..', '..', 'build', 'web')),
  // Kunci yang dikirim alat/bridge lewat header x-device-key. Wajib diganti pada produksi.
  deviceKey: env.DEVICE_KEY || DEFAULT_DEVICE_KEY,
  defaultDeviceKey: DEFAULT_DEVICE_KEY,
  // CORS: '*' hanya cocok untuk pengembangan. Produksi: daftar origin dipisah koma.
  corsOrigin: env.CORS_ORIGIN || '*',
  // Percayai header X-Forwarded-For (hanya bila di belakang reverse proxy tepercaya).
  trustProxy: ['1', 'true', 'on'].includes(String(env.TRUST_PROXY || '').toLowerCase()),
  // Simulator dimatikan secara bawaan agar data palsu tidak pernah tampil untuk alat asli.
  simulator: hasFlag('simulator') || ['on', '1', 'true'].includes(String(env.SIMULATOR || 'off').toLowerCase()),
  simulatorIntervalMs: num(env.SIM_INTERVAL_MS, 4000, 500, 60000),
  // Titik rumah bawaan geofence: Sleman, Yogyakarta
  home: { lat: -7.71556, lng: 110.35547, address: 'Jl. Melati No. 12, Sleman, Yogyakarta' },
  dailyStepGoal: 10000,
  photosDir: path.join(dataDir, 'photos'),
  // Akun awal (opsional). Tanpa nilai ini server TIDAK membuat akun apa pun.
  seed: {
    name: env.SEED_NAME || 'Pemilik PawFinder',
    email: String(env.SEED_EMAIL || '').trim().toLowerCase(),
    password: env.SEED_PASSWORD || '',
  },
  // Koneksi kabel USB (Arduino) langsung ke server ini.
  usb: {
    port: usbPort, // '' = nonaktif, 'auto' = deteksi Arduino, atau nama port (COM3, /dev/ttyACM0)
    baud: num(env.USB_BAUD, 9600, 1200, 921600),
    serial: String(env.USB_SERIAL || '').trim().toUpperCase(), // ID alat bawaan bila firmware tidak mengirim ID
    lat: optNum(env.USB_FALLBACK_LAT), // koordinat tetap bila alat tidak punya modul GPS
    lng: optNum(env.USB_FALLBACK_LNG),
  },
  // Batas waktu minimal tanpa data sebelum alat dianggap offline (detik).
  offlineAfterSec: num(env.OFFLINE_AFTER_SEC, 90, 15, 3600),
  // Pemeriksaan keamanan sebelum server menerima lalu lintas di produksi.
  problems() {
    const list = [];
    if (!env.JWT_SECRET || env.JWT_SECRET.length < 32) list.push('JWT_SECRET belum diisi (minimal 32 karakter acak).');
    if (this.deviceKey === DEFAULT_DEVICE_KEY || this.deviceKey.length < 16) list.push('DEVICE_KEY masih bawaan atau terlalu pendek (minimal 16 karakter).');
    if (this.corsOrigin === '*') list.push('CORS_ORIGIN masih "*" (isi dengan alamat aplikasi web Anda).');
    if (this.simulator) list.push('SIMULATOR aktif; matikan di produksi agar tidak ada data palsu.');
    return list;
  },
};
