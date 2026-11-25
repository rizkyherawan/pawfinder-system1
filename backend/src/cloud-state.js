'use strict';

const { connectFirebase } = require('./firebase-store');

class CloudState {
  constructor(root = 'pawfinder_vercel_test') {
    this.root = root;
    this.ref = connectFirebase().ref(`${root}/state`);
  }

  async load() {
    const snapshot = await this.ref.once('value');

    if (!snapshot.exists()) {
      throw new Error('Database cloud tidak ditemukan');
    }

    const raw = snapshot.val();
    const data = JSON.parse(raw);

    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new Error('Format database tidak valid');
    }

    return { raw, data };
  }

  async commit(previousRaw, data) {
    const nextRaw = JSON.stringify(data);

    const result = await this.ref.transaction(
      current => {
        if (current === null) {
          return null;
        }

        if (current !== previousRaw) {
          return undefined;
        }

        return nextRaw;
      },
      undefined,
      false
    );

    if (!result.committed || result.snapshot.val() !== nextRaw) {
      const error = new Error(
        'Data telah berubah. Silakan ulangi permintaan.'
      );

      error.status = 409;
      error.code = 'STATE_CONFLICT';

      throw error;
    }

    return true;
  }
}

module.exports = { CloudState };