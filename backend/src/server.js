'use strict';
const http = require('http');
const config = require('./config');
const { Store } = require('./store');
const { Router } = require('./router');
const registerRoutes = require('./routes');
const simulator = require('./services/simulator');
const { seed, DEMO } = require('./seed');
const { syncAllConnections } = require('./services/engine');

function createApp() {
  const store = new Store(config.dataFile).load();
  if (store.data.users.length === 0) {
    seed(store);
    console.log(`[seed] Akun pengembangan dibuat: ${DEMO.email}`);
  }
  const router = new Router(store);
  registerRoutes(router);
  const server = http.createServer(router.handler(config.webDir));
  return { server, store, router };
}

if (require.main === module) {
  const { server, store } = createApp();
  server.listen(config.port, config.host, () => {
    console.log('\n  PawFinder backend berjalan');
    console.log(`  Web dashboard : http://localhost:${config.port}`);
    console.log(`  API           : http://localhost:${config.port}/api/ping`);
    console.log(`  Android emu   : http://10.0.2.2:${config.port}\n`);
  });
  if (config.simulator) simulator.start(store);
  // Deteksi kalung yang berhenti mengirim data (status Online -> Offline) walau tidak ada klien yang membuka aplikasi.
  setInterval(() => syncAllConnections(store), 10000).unref();
  const stop = () => { store.saveNow(); process.exit(0); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

module.exports = { createApp };
