'use strict';
// Uji I/O byte nyata lewat pseudo-terminal (berperilaku seperti /dev/ttyACM0). Hanya Linux/macOS.
const assert = require('assert');
const fs = require('fs');
const { spawn, spawnSync } = require('child_process');
const { prepareEnv, startServer, ok, count } = require('./helpers');

if (process.platform === 'win32' || spawnSync('python3', ['-c', 'import pty']).status !== 0) {
  console.log('  (dilewati: butuh Linux/macOS dengan python3)');
  process.exit(0);
}
const dir = prepareEnv();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (fn, ms = 6000) => { const t = Date.now(); while (Date.now() - t < ms) { if (await fn()) return true; await sleep(25); } return false; };

const PY = `
import os, pty, sys, time, select
master, slave = pty.openpty()
print(os.ttyname(slave), flush=True)
sys.stdin.readline()
os.write(master, b'{"hello":"PF-TTY-000001","fw":"1.0"}\\r\\n')
time.sleep(0.3)
os.write(master, b'PF,PF-TTY-000001,-7.71556,110.35547,77,1,90,38.5,6\\r\\n')
buf = b''
end = time.time() + 5
while time.time() < end:
    r, _, _ = select.select([master], [], [], 0.2)
    if r:
        try: buf += os.read(master, 1024)
        except OSError: break
print('GOT:' + repr(buf), flush=True)
`;

(async () => {
  const S = await startServer();
  const { call, store } = S;
  const { createUsbLink } = require('../src/server');
  const { ttyOpener, listPorts } = require('../src/services/serial-io');
  S.token = (await call('POST', '/api/auth/login', { email: 'qa@pawfinder.test', password: 'Rahasia123' })).body.token;
  const pet = (await call('POST', '/api/pets', { name: 'Tty', species: 'anjing', gender: 'jantan', birthDate: '2023-01-01' })).body.pet;
  await call('POST', `/api/pets/${pet.id}/device/pair`, { serial: 'PF-TTY-000001' });

  const py = spawn('python3', ['-u', '-c', PY], { stdio: ['pipe', 'pipe', 'inherit'] });
  let out = '';
  py.stdout.on('data', (d) => { out += d.toString(); });
  assert.ok(await until(() => out.includes('\n')));
  const devPath = out.split('\n')[0].trim();
  assert.match(devPath, /^\/dev\/(pts\/\d+|ttys\d+)/); ok(`pseudo-terminal dibuat: ${devPath}`);

  const link = createUsbLink(store, { opener: ttyOpener, lister: listPorts, path: devPath, log: () => {}, link: { whoDelayMs: 100 } });
  link.start();
  assert.ok(await until(() => link.state === 'connected')); ok('port dibuka lewat jalur cadangan tanpa dependensi (stty + berkas perangkat)');
  py.stdin.write('go\n');
  assert.ok(await until(async () => (await call('GET', `/api/pets/${pet.id}`)).body.pet.device.connection === 'online')); ok('byte nyata dari "port" -> online lewat USB');
  assert.ok(await until(async () => (await call('GET', `/api/pets/${pet.id}`)).body.pet.location !== null));
  const v = (await call('GET', `/api/pets/${pet.id}`)).body.pet;
  assert.equal(v.device.battery, 77); assert.equal(v.device.source, 'usb'); assert.ok(Math.abs(v.location.lat - -7.71556) < 1e-6); ok('baris CSV dengan \\r\\n terbaca: baterai 77, lokasi benar');
  await call('POST', `/api/pets/${pet.id}/device/ping`);
  assert.ok(await until(() => /GOT:/.test(out), 9000));
  assert.match(out, /PING/); assert.match(out, /WHO/); ok('perintah PING & WHO benar-benar tertulis ke port (dibaca sisi "Arduino")');
  link.stop(); py.kill();
  await S.close();
  fs.rmSync(dir, { recursive: true, force: true });
  console.log(`  (${count()} pemeriksaan I/O nyata lulus)`);
  process.exit(0);
})().catch((e) => { console.error('\nTES GAGAL:', e); process.exit(1); });
