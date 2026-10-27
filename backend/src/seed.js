'use strict';
const config = require('./config');
const { Store } = require('./store');
const { hashPassword } = require('./auth');

// Akun pengembangan. Ganti/hapus sebelum aplikasi dibagikan atau dipakai di produksi.
const DEMO = { name: 'Muhammad Rizky Herawan', email: 'muhammadrizkyherawan@gmail.com', password: '3Oktober2004' };

/** Seed hanya membuat akun. Tidak ada hewan, riwayat, maupun notifikasi bawaan. */
function seed(store) {
  const user = { id: store.id('usr'), name: DEMO.name, email: DEMO.email, passwordHash: hashPassword(DEMO.password), createdAt: new Date().toISOString() };
  store.data.users.push(user);
  store.data.settings[user.id] = { push: true, sound: true, powerSave: false, theme: 'terang' };
  store.saveNow();
  return user;
}

module.exports = { seed, DEMO };

if (require.main === module) {
  const store = new Store(config.dataFile).load();
  if (process.argv.includes('--reset') || store.data.users.length === 0) {
    store.reset();
    seed(store);
    console.log(`Database di-seed. Akun: ${DEMO.email} / ${DEMO.password}`);
  } else {
    console.log('Database sudah berisi data. Gunakan --reset untuk mengulang.');
  }
}
