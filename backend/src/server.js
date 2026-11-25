'use strict';
const http = require('http');
const os = require('os');
const config = require('./config');
const { Store } = require('./store');
const { Router } = require('./router');
const registerRoutes = require('./routes');
const simulator = require('./services/simulator');
const { seed } = require('./seed');
const { syncAllConnections } = require('./services/engine');
const { handleDeviceMessage, drainCommands, markLinkClosed } = require('./services/device-gateway');
const { UsbLink } = require('./services/usb-link');
const { createOpener, listPorts } = require('./services/serial-io');

/** Membuat tautan USB yang menyalurkan paket Arduino langsung ke gateway alat di proses ini. */
function createUsbLink(store, opts = {}) {
  const { opener } = opts.opener ? { opener: opts.opener } : createOpener();
  const fallback = Number.isFinite(config.usb.lat) && Number.isFinite(config.usb.lng) ? { lat: config.usb.lat, lng: config.usb.lng } : null;
  const link = new UsbLink({
    path: opts.path || config.usb.port || 'auto',
    baud: opts.baud || config.usb.baud,
    opener,
    lister: opts.lister || listPorts,
    defaultSerial: config.usb.serial,
    log: opts.log || ((m) => console.log(m)),
    onMessage: (msg, meta) => handleDeviceMessage(store, msg, { source: 'usb', port: meta.port, defaultSerial: config.usb.serial, fallback }),
    pullCommands: (serial) => drainCommands(store, serial),
    onClosed: (serials) => markLinkClosed(store, serials),
    ...(opts.link || {}),
  });
  store.runtime.usb = link;
  return link;
}

function createApp(existingStore = null) {
  const store = existingStore || new Store(config.dataFile).load();
  if (store.data.users.length === 0 && config.seed.email && config.seed.password) {
    try {
      const u = seed(store, config.seed);
      if (u) console.log(`[seed] Akun awal dibuat: ${u.email}`);
    } catch (e) {
      console.warn(`[seed] dilewati: ${e.message}`);
    }
  }
  const router = new Router(store);
  registerRoutes(router);
  const server = http.createServer(router.handler(config.webDir));
  server.requestTimeout = 30_000;
  server.headersTimeout = 20_000;
  server.keepAliveTimeout = 5_000;
  return { server, store, router };
}

function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list || []) if (i.family === 'IPv4' && !i.internal) out.push(i.address);
  }
  return out;
}

async function startServer() {
  if (config.isProd) {
    const problems = config.problems();
    if (problems.length) {
      console.error('\n[KEAMANAN] Server produksi tidak dijalankan karena konfigurasi belum aman:');
      problems.forEach((p) => console.error('  - ' + p));
      console.error('Perbaiki di backend/.env (lihat .env.example), lalu jalankan ulang.\n');
      process.exit(1);
    }
  } else {
    if (config.deviceKey === config.defaultDeviceKey) console.warn('[peringatan] DEVICE_KEY masih bawaan; aman untuk uji lokal, WAJIB diganti sebelum dipakai di jaringan umum.');
    if (config.corsOrigin === '*') console.warn('[peringatan] CORS_ORIGIN="*" (terbuka); batasi pada produksi.');
  }

  let existingStore = null;
  if (config.storageDriver === 'firebase') {
    const { connectFirebase, FirebaseStore } = require('./firebase-store');
    existingStore = await new Store(config.dataFile).loadCloud(new FirebaseStore(connectFirebase()));
    console.log('[store] Firebase Realtime Database aktif');
  }
  const { server, store } = createApp(existingStore);
  server.on('error', (e) => {
    if (e.code === 'EADDRINUSE') console.error(`\nPort ${config.port} sudah dipakai program lain (mungkin backend PawFinder yang masih berjalan). Tutup program itu atau ubah PORT di backend/.env.\n`);
    else if (e.code === 'EACCES') console.error(`\nTidak punya izin memakai port ${config.port}. Pakai port di atas 1024.\n`);
    else console.error('\nServer gagal berjalan:', e.message, '\n');
    process.exit(1);
  });
  server.listen(config.port, config.host, () => {
    console.log('\n  PawFinder backend berjalan');
    console.log(`  API           : http://localhost:${config.port}/api/ping`);
    console.log(`  Android emu   : http://10.0.2.2:${config.port}`);
    for (const ip of lanAddresses()) console.log(`  HP asli (WiFi): http://${ip}:${config.port}`);
    console.log(`  Simulator     : ${config.simulator ? 'AKTIF (data demo, bukan alat asli)' : 'mati (hanya alat asli)'}`);
    console.log(`  Kabel USB     : ${config.usb.port ? `aktif (${config.usb.port} @ ${config.usb.baud} baud)` : 'nonaktif (set USB_PORT=auto atau npm run start:usb)'}\n`);
  });

  let link = null;
  if (config.usb.port) {
    const { driver } = createOpener();
    if (!driver) console.error('[usb] Driver serial tidak ditemukan. Di Windows jalankan: npm install serialport  (di folder backend)');
    link = createUsbLink(store).start();
  }
  if (config.simulator) simulator.start(store);
  // Deteksi kalung yang berhenti mengirim data (Online -> Offline) walau tidak ada klien yang membuka aplikasi.
  setInterval(() => { try { syncAllConnections(store); } catch (e) { console.error('[sync]', e.message); } }, 10000).unref();

  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    console.log('[shutdown] Menyelesaikan penyimpanan data...');
    const timeout = setTimeout(() => {
      console.error('[shutdown] Waktu penyimpanan habis');
      process.exit(1);
    }, 15000);
    try {
      if (link) link.stop();
      await new Promise(resolve => server.close(resolve));
      await store.saveNow();
      clearTimeout(timeout);
      console.log('[shutdown] Data berhasil disimpan');
      process.exit(0);
    } catch (e) {
      clearTimeout(timeout);
      console.error('[shutdown]', e.message);
      process.exit(1);
    }
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  process.on('unhandledRejection', (e) => console.error('[unhandledRejection]', e));
  process.on('uncaughtException', (e) => {
    console.error('[uncaughtException]', e);
    try { store.saveNow(); } catch (_) { /* abaikan */ }
    process.exit(1); // biarkan pengelola proses (pm2/systemd/docker) menghidupkan ulang
  });
}

if (require.main === module) {
  startServer().catch(e => {
    console.error('[startup]', e.message);
    process.exit(1);
  });
}

module.exports = { createApp, createUsbLink };
