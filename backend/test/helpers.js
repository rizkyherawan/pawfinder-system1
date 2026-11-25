'use strict';
const os = require('os');
const path = require('path');
const fs = require('fs');

/** Menyiapkan lingkungan uji: database sementara, simulator mati, akun awal untuk uji login. */
function prepareEnv() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pawfinder-test-'));
  process.env.DATA_FILE = path.join(dir, 'db.json');
  process.env.SIMULATOR = 'off';
  process.env.SEED_EMAIL = 'qa@pawfinder.test';
  process.env.SEED_PASSWORD = 'Rahasia123';
  process.env.SEED_NAME = 'Penguji QA';
  process.env.JWT_SECRET = '';
  process.env.DEVICE_KEY = 'pawfinder-device-key';
  process.env.STORAGE_DRIVER = 'json';
  process.env.NODE_ENV = 'test';
  process.env.USB_PORT = '';
  return dir;
}

async function startServer() {
  const { createApp } = require('../src/server');
  const app = createApp();
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const ctx = { ...app, base, token: null };
  ctx.call = async (method, url, body, headers = {}) => {
    const res = await fetch(base + url, {
      method,
      headers: { 'Content-Type': 'application/json', ...(ctx.token ? { Authorization: `Bearer ${ctx.token}` } : {}), ...headers },
      body: body === undefined ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)),
    });
    const type = res.headers.get('content-type') || '';
    return { status: res.status, headers: res.headers, body: type.includes('json') ? await res.json() : Buffer.from(await res.arrayBuffer()), type };
  };
  ctx.close = () => new Promise((r) => { app.server.close(r); app.store.saveNow(); });
  return ctx;
}

let passed = 0;
const ok = (name) => { passed++; console.log('  ✓', name); };
const count = () => passed;

module.exports = { prepareEnv, startServer, ok, count };
