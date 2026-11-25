'use strict';

const {
  initializeApp,
  cert,
  getApps,
} = require('firebase-admin/app');

const { getDatabase } = require('firebase-admin/database');
const fs = require('fs');
const config = require('./config');

function loadFirebaseCredential() {
  // Metode 1: Environment variable untuk cloud hosting.
  const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;

  if (json && json.trim()) {
    try {
      return JSON.parse(json);
    } catch (_) {
      throw new Error(
        'FIREBASE_SERVICE_ACCOUNT_JSON tidak valid.'
      );
    }
  }

  // Metode 2: File kredensial untuk server lokal.
  const keyPath = config.firebase.keyPath;

  if (keyPath && fs.existsSync(keyPath)) {
    try {
      return JSON.parse(
        fs.readFileSync(keyPath, 'utf8')
      );
    } catch (_) {
      throw new Error(
        'File kredensial Firebase tidak valid.'
      );
    }
  }

  throw new Error(
    'Kredensial Firebase belum dikonfigurasi.'
  );
}

function connectFirebase() {
  if (!config.firebase.databaseURL) {
    throw new Error(
      'Firebase Database URL belum tersedia.'
    );
  }

  let app = getApps().find(
    (a) => a.name === 'pawfinder'
  );

  if (!app) {
    const key = loadFirebaseCredential();

    app = initializeApp(
      {
        credential: cert(key),
        databaseURL: config.firebase.databaseURL,
      },
      'pawfinder'
    );
  }

  return getDatabase(app);
}

class FirebaseStore {
  constructor(db) {
    this.ref = db.ref('pawfinder/state');
  }

  async load() {
    const snapshot = await this.ref.once('value');

    if (!snapshot.exists()) {
      return null;
    }

    return JSON.parse(snapshot.val());
  }

  async save(data) {
    await this.ref.set(JSON.stringify(data));
  }
}

module.exports = {
  connectFirebase,
  FirebaseStore,
};