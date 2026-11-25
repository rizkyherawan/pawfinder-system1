'use strict';
const assert = require('assert');
const { parseLine, LineSplitter, encodeCommand, nmeaCoord, validCoords, normalizeSerial } = require('../src/services/device-protocol');

const checksum = (b) => { let x = 0; for (const c of b) x ^= c.charCodeAt(0); return x.toString(16).toUpperCase().padStart(2, '0'); };
const nmea = (b) => `$${b}*${checksum(b)}`;
let n = 0;
const ok = (name) => { n++; console.log('  ✓', name); };

// ---- JSON
let m = parseLine('{"serial":"pf-abc-123456","lat":-7.71556,"lng":110.35547,"fix":1,"bat":87,"sig":"Kuat","hr":96,"temp":38.6,"sat":7}');
assert.deepStrictEqual([m.kind, m.serial, m.lat, m.lng, m.fix, m.battery, m.signal, m.heartRate, m.temperature, m.satellites], ['telemetry', 'PF-ABC-123456', -7.71556, 110.35547, true, 87, 'Kuat', 96, 38.6, 7]);
ok('JSON lengkap diuraikan, ID dibuat huruf besar');
m = parseLine('{"id":"PF-ABC-123456","latitude":"-7,71556","longitude":"110,35547","battery":"55"}');
assert.equal(m.lat, -7.71556); assert.equal(m.lng, 110.35547); assert.equal(m.battery, 55);
ok('alias field + angka bertanda koma desimal diterima');
m = parseLine('{"serial":"PF-ABC-123456","lat":0,"lng":0,"bat":50}');
assert.equal(m.fix, false); assert.equal(m.lat, undefined);
ok('koordinat (0,0) dari modul GPS tanpa sinyal BUKAN lokasi');
m = parseLine('{"serial":"PF-ABC-123456","lat":-7.7,"lng":110.3,"fix":0}');
assert.equal(m.fix, false); assert.equal(m.lat, undefined);
ok('fix=0 membatalkan koordinat yang ikut terkirim');
m = parseLine('{"serial":"PF-ABC-123456","lat":95,"lng":10}');
assert.equal(m.badCoords, true); assert.equal(m.fix, false);
ok('lintang di luar rentang ditandai koordinat salah');
m = parseLine('{"serial":"PF-ABC-123456","bat":150,"hr":9000,"temp":99,"sat":999}');
assert.equal(m.battery, 100); assert.equal(m.heartRate, undefined); assert.equal(m.temperature, undefined); assert.equal(m.satellites, undefined);
ok('nilai sensor mustahil dibuang / baterai dibatasi 0-100');
m = parseLine('{"serial":"ngawur","lat":-7.7,"lng":110.3}');
assert.ok(m.badSerial); assert.equal(m.serial, undefined);
ok('ID alat berformat salah ditandai');
m = parseLine('{"hello":"PF-ABC-123456","fw":"1.0.0"}');
assert.deepStrictEqual([m.kind, m.serial, m.firmware], ['hello', 'PF-ABC-123456', '1.0.0']);
ok('hello JSON');
assert.equal(parseLine('{"foo":1}').kind, 'unknown');
assert.equal(parseLine('{rusak').kind, 'unknown');
assert.equal(parseLine('[1,2]').kind, 'unknown');
assert.equal(parseLine('null').kind, 'unknown');
ok('JSON rusak / bukan objek / tanpa field dikenal -> unknown (tidak melempar)');

// ---- CSV
m = parseLine('PF,PF-ABC-123456,-7.71556,110.35547,87,1,96,38.6,7');
assert.deepStrictEqual([m.serial, m.lat, m.lng, m.battery, m.fix, m.heartRate, m.temperature, m.satellites], ['PF-ABC-123456', -7.71556, 110.35547, 87, true, 96, 38.6, 7]);
ok('CSV lengkap');
m = parseLine('PF,PF-ABC-123456,0,0,87,0');
assert.equal(m.fix, false); assert.equal(m.battery, 87);
ok('CSV tanpa fix = alat hidup, belum ada lokasi');
m = parseLine('pf,hello,PF-ABC-123456,2.1'); assert.equal(m.kind, 'hello'); assert.equal(m.firmware, '2.1');
m = parseLine('PF,ACK,ping'); assert.deepStrictEqual([m.kind, m.command], ['ack', 'PING']);
assert.equal(parseLine('PF,PF-ABC-123456').kind, 'unknown');
ok('CSV hello / ack / kolom kurang');

// ---- NMEA
m = parseLine(nmea('GPGGA,123519,0742.9336,S,11021.3282,E,1,08,0.9,545.4,M,46.9,M,,'));
assert.ok(Math.abs(m.lat - -7.71556) < 1e-5 && Math.abs(m.lng - 110.35547) < 1e-5); assert.equal(m.fix, true); assert.equal(m.satellites, 8);
ok('NMEA GGA: lintang selatan/bujur timur dikonversi benar');
m = parseLine(nmea('GPGGA,123519,,,,,0,00,99.9,,M,,M,,'));
assert.equal(m.fix, false); assert.equal(m.lat, undefined);
ok('NMEA GGA tanpa fix');
m = parseLine(nmea('GNRMC,123519,A,0742.9336,S,11021.3282,E,010.0,084.4,230394,,,A'));
assert.equal(m.fix, true); assert.ok(Math.abs(m.speedKmh - 18.5) < 0.1);
m = parseLine(nmea('GPRMC,123519,V,,,,,,,230394,,,N'));
assert.equal(m.fix, false);
ok('NMEA RMC aktif (A) dan void (V), kecepatan knot -> km/jam');
assert.equal(parseLine('$GPGGA,123519,0742.9336,S,11021.3282,E,1,08,0.9,545.4,M,46.9,M,,*00').kind, 'unknown');
assert.equal(parseLine(nmea('GPGSV,3,1,11,03,03,111,00')).kind, 'log');
ok('checksum NMEA salah ditolak; kalimat lain (GSV) diabaikan');
assert.equal(nmeaCoord('0760.0000', 'N', 2), null); assert.equal(nmeaCoord('abc', 'N', 2), null); assert.equal(nmeaCoord('0742.9', 'X', 2), null);
ok('nmeaCoord menolak menit >= 60, teks, dan belahan bumi salah');

// ---- Keluaran persis sketsa Arduino (firmware/*.ino): regresi agar firmware & server tidak pernah tidak cocok
m = parseLine('PF,PF-ABC-123456,-7.715560,110.355470,87,1,,36.5,8');
assert.deepStrictEqual([m.serial, m.lat, m.lng, m.battery, m.fix, m.heartRate, m.temperature, m.satellites], ['PF-ABC-123456', -7.71556, 110.35547, 87, true, undefined, 36.5, 8]);
m = parseLine('PF,PF-ABC-123456,,,,0,,,');
assert.deepStrictEqual([m.kind, m.serial, m.fix, m.battery], ['telemetry', 'PF-ABC-123456', false, undefined]);
m = parseLine('PF,PF-TST-000001,-7.715600,110.355500,100,1,,,7');
assert.deepStrictEqual([m.fix, m.battery, m.satellites], [true, 100, 7]);
assert.equal(parseLine('# PawFinder collar siap').kind, 'log');
assert.equal(parseLine('PF,HELLO,PF-ABC-123456,1.0.0').kind, 'hello');
ok('baris keluaran sketsa Arduino (kolom kosong saat belum fix / tanpa sensor) terbaca benar');

// ---- Baris umum
assert.equal(parseLine(''), null); assert.equal(parseLine('   \r\n'), null); assert.equal(parseLine(undefined), null);
assert.equal(parseLine('# debug: gps mencari satelit').kind, 'log');
assert.equal(parseLine('selamat datang').kind, 'unknown');
assert.equal(parseLine('x'.repeat(2000)).kind, 'unknown');
assert.equal(parseLine('PF,\u0000\u0001garbage').kind, 'unknown');
ok('baris kosong, komentar, sampah, dan baris kepanjangan ditangani tanpa error');
assert.equal(validCoords(0, 0), false); assert.equal(validCoords(-7.7, 110.3), true); assert.equal(validCoords(NaN, 1), false); assert.equal(normalizeSerial('PF-AB-123456'), null);
ok('validCoords / normalizeSerial');

// ---- Pemotong baris
const s = new LineSplitter();
assert.deepStrictEqual(s.feed('A\r\nB\nC'), ['A', 'B']);
assert.deepStrictEqual(s.feed('D\r'), ['CD']);
assert.deepStrictEqual(s.feed(Buffer.from('E\n')), ['E']);
const emoji = Buffer.from('é\n');
const s2 = new LineSplitter(); assert.deepStrictEqual([...s2.feed(emoji.subarray(0, 1)), ...s2.feed(emoji.subarray(1))], ['é']);
const big = new LineSplitter(20); assert.deepStrictEqual(big.feed('x'.repeat(100) + '\nok\n'), ['ok']); assert.equal(big.dropped, 1);
ok('LineSplitter: baris terpotong antar-chunk, \\r\\n, karakter multibyte, banjir tanpa newline');

assert.equal(encodeCommand('ping'), 'PING\n'); assert.equal(encodeCommand('interval', 60), 'INTERVAL 60\n');
assert.equal(encodeCommand('interval', 0), null); assert.equal(encodeCommand('interval', 'abc'), null); assert.equal(encodeCommand('format-disk'), null);
ok('encodeCommand hanya menghasilkan perintah yang dikenal & valid');

console.log(`  (${n} kelompok uji protokol lulus)`);
