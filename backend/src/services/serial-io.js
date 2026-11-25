'use strict';
/**
 * Lapisan I/O serial. Kontraknya sederhana agar mudah diuji dan diganti:
 *   opener({ path, baudRate }) -> EventEmitter dengan event 'open' | 'data'(Buffer) | 'error' | 'close'
 *                                 dan method write(string), close()
 *   lister() -> Promise<[{ path, vendorId?, productId?, manufacturer? }]>
 *
 * Jalur utama memakai paket npm "serialport" (Windows / macOS / Linux).
 * Bila tidak terpasang, di Linux/macOS dipakai cadangan tanpa dependensi (stty + berkas /dev/tty*).
 */
const fs = require('fs');
const path = require('path');
const { EventEmitter } = require('events');
const { execFileSync } = require('child_process');

function loadSerialPort() {
  try {
    const mod = require('serialport');
    return mod && mod.SerialPort ? mod.SerialPort : null;
  } catch (_) {
    return null;
  }
}

function serialportOpener(SerialPort) {
  return ({ path: p, baudRate }) => new SerialPort({ path: p, baudRate, autoOpen: true });
}

/** Cadangan tanpa dependensi (Linux/macOS/Raspberry Pi). */
function ttyOpener({ path: devPath, baudRate }) {
  const ee = new EventEmitter();
  let rs = null, wfd = null, closed = false;
  const finish = () => { if (closed) return; closed = true; try { if (wfd !== null) fs.closeSync(wfd); } catch (_) { /* abaikan */ } wfd = null; ee.emit('close'); };
  process.nextTick(() => {
    try {
      // -hupcl: jangan reset Arduino setiap port ditutup.
      execFileSync('stty', [process.platform === 'darwin' ? '-f' : '-F', devPath, String(baudRate), 'raw', '-echo', '-hupcl', 'cs8', '-cstopb', '-parenb'], { stdio: 'ignore' });
      wfd = fs.openSync(devPath, 'w');
      rs = fs.createReadStream(devPath, { flags: 'r' });
      rs.on('data', (b) => ee.emit('data', b));
      rs.on('error', (e) => { ee.emit('error', e); finish(); });
      rs.on('close', finish);
      ee.emit('open');
    } catch (e) {
      ee.emit('error', new Error(`Tidak dapat membuka ${devPath}: ${e.message}`));
      finish();
    }
  });
  ee.write = (s) => { if (wfd === null) throw new Error('port tertutup'); fs.writeSync(wfd, s); };
  ee.close = () => { if (rs) rs.destroy(); finish(); };
  return ee;
}

async function listPorts() {
  const SerialPort = loadSerialPort();
  if (SerialPort) {
    const list = await SerialPort.list();
    return list.map((p) => ({ path: p.path, vendorId: p.vendorId, productId: p.productId, manufacturer: p.manufacturer, serialNumber: p.serialNumber }));
  }
  // Tanpa serialport: pindai berkas perangkat umum Arduino (Linux/macOS).
  const out = [];
  const patterns = [/^ttyACM\d+$/, /^ttyUSB\d+$/, /^cu\.usbmodem/, /^cu\.usbserial/, /^cu\.wchusbserial/];
  try {
    for (const name of fs.readdirSync('/dev')) if (patterns.some((r) => r.test(name))) out.push({ path: path.join('/dev', name) });
  } catch (_) { /* /dev tidak ada (Windows) */ }
  return out;
}

/** Pilih port yang paling mungkin Arduino / adaptor USB-serial. null bila tidak ada kandidat. */
const ARDUINO_VIDS = ['2341', '2a03', '1a86', '0403', '10c4', '067b', '1b4f'];
function pickArduino(ports) {
  if (!ports || !ports.length) return null;
  const known = ports.filter((p) => p.vendorId && ARDUINO_VIDS.includes(String(p.vendorId).toLowerCase()));
  if (known.length) return known[0];
  return ports.length === 1 ? ports[0] : null; // satu-satunya port serial: kemungkinan besar alat kita
}

function createOpener() {
  const SerialPort = loadSerialPort();
  if (SerialPort) return { opener: serialportOpener(SerialPort), driver: 'serialport' };
  if (process.platform !== 'win32') return { opener: ttyOpener, driver: 'tty' };
  return { opener: null, driver: null };
}

module.exports = { createOpener, listPorts, pickArduino, ttyOpener, loadSerialPort };
