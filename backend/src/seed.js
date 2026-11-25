'use strict';
const config = require('./config');
const { Store } = require('./store');
const { hashPassword, passwordProblem } = require('./auth');

/**
 * Membuat satu akun awal (opsional, untuk pengembangan). TIDAK ada akun bawaan di dalam kode:
 * isi SEED_EMAIL / SEED_PASSWORD di backend/.env, atau pakai opsi --email= --password= --name=.
 * Tidak membuat hewan, riwayat, maupun notifikasi apa pun.
 */
function seed(store, { name, email, password }) {
  const mail = String(email || '').trim().toLowerCase();
  if (!mail) throw new Error('Email akun awal belum diisi (SEED_EMAIL atau --email=).');
  const problem = passwordProblem(password);
  if (problem) throw new Error(`Kata sandi akun awal: ${problem}`);
  if (store.data.users.some((u) => u.email === mail)) return null; // sudah ada: jangan timpa
  const user = { id: store.id('usr'), name: String(name || 'Pemilik PawFinder').trim(), email: mail, passwordHash: hashPassword(password), createdAt: new Date().toISOString() };
  store.data.users.push(user);
  store.data.settings[user.id] = { push: true, sound: true, powerSave: false, theme: 'terang' };
  store.saveNow();
  return user;
}

module.exports = { seed };

if (require.main === module) {
  const arg = (n) => { const a = process.argv.find((x) => x.startsWith(`--${n}=`)); return a ? a.slice(n.length + 3) : undefined; };
  const has = (n) => process.argv.includes(`--${n}`);
  const store = new Store(config.dataFile).load();
  try {
    if (has('reset')) {
      if (!has('yes')) {
        console.error('PERINGATAN: --reset MENGHAPUS SEMUA DATA (akun, hewan, riwayat). Tambahkan --yes bila Anda yakin.');
        process.exit(1);
      }
      store.reset();
    }
    const creds = { name: arg('name') || config.seed.name, email: arg('email') || config.seed.email, password: arg('password') || config.seed.password };
    const user = seed(store, creds);
    console.log(user ? `Akun dibuat: ${user.email}` : 'Akun dengan email itu sudah ada; tidak ada perubahan.');
  } catch (e) {
    console.error(`Gagal: ${e.message}\nContoh: node src/seed.js --email=saya@email.com --password=Rahasia123 --name="Nama Saya"`);
    process.exit(1);
  }
}
