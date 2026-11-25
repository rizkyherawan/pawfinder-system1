#!/usr/bin/env node
'use strict';
// Menampilkan port serial/USB yang terdeteksi, dan port mana yang dikenali sebagai Arduino.
const { listPorts, pickArduino, createOpener } = require('../src/services/serial-io');

(async () => {
  const { driver } = createOpener();
  console.log(`Driver serial: ${driver || 'TIDAK ADA (jalankan: npm install serialport)'}`);
  let ports = [];
  try { ports = await listPorts(); } catch (e) { console.error('Gagal membaca daftar port:', e.message); }
  if (!ports.length) {
    console.log('\nTidak ada port serial. Periksa: (1) kabel USB harus kabel DATA (bukan kabel khusus charger), (2) driver CH340/FTDI terpasang bila memakai papan klon, (3) coba port USB lain.');
    return;
  }
  const best = pickArduino(ports);
  console.log('\nPort terdeteksi:');
  for (const p of ports) {
    const tag = best && best.path === p.path ? '   <-- kemungkinan Arduino (dipakai bila USB_PORT=auto)' : '';
    console.log(`  ${p.path}  ${[p.manufacturer, p.vendorId && `VID:${p.vendorId}`, p.productId && `PID:${p.productId}`].filter(Boolean).join(' · ')}${tag}`);
  }
  console.log('\nContoh backend/.env:  USB_PORT=' + (best ? best.path : 'COM3') + '\n');
})();
