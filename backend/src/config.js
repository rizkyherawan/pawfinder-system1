'use strict';
const fs = require('fs');
const path = require('path');

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

module.exports = {
  port: Number(process.env.PORT || 4000),
  host: process.env.HOST || '0.0.0.0',
  jwtSecret: process.env.JWT_SECRET || 'pawfinder-dev-secret-change-me',
  tokenTtlDays: 30,
  dataFile: path.resolve(process.env.DATA_FILE || path.join(__dirname, '..', 'data', 'db.json')),
  webDir: path.resolve(process.env.WEB_DIR || path.join(__dirname, '..', '..', 'web')),
  deviceKey: process.env.DEVICE_KEY || 'pawfinder-device-key',
  simulator: String(process.env.SIMULATOR || 'on').toLowerCase() !== 'off',
  simulatorIntervalMs: Number(process.env.SIM_INTERVAL_MS || 4000),
  // Titik rumah demo: Sleman, Yogyakarta
  home: { lat: -7.71556, lng: 110.35547, address: 'Jl. Melati No. 12, Sleman, Yogyakarta' },
  dailyStepGoal: 10000,
  photosDir: path.join(path.dirname(path.resolve(process.env.DATA_FILE || path.join(__dirname, '..', 'data', 'db.json'))), 'photos'),
};
