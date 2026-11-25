'use strict';

const fs = require('fs');
const path = require('path');
const config = require('../config');

function createPhotoStore(store) {
  // Penyimpanan serverless melalui Cloud Snapshot.
  if (store.photoStore) {
    return store.photoStore;
  }

  // Penyimpanan backend lokal dengan Firebase.
  const ref = id =>
    require('../firebase-store')
      .connectFirebase()
      .ref('pawfinder/photos')
      .child(id);

  const file = id => path.join(config.photosDir, id);
  const cloud = () => !!store.cloud;

  return {
    async save(id, buf) {
      if (cloud()) {
        return ref(id).set(buf.toString('base64'));
      }

      fs.mkdirSync(config.photosDir, {
        recursive: true,
      });

      fs.writeFileSync(file(id), buf);
    },

    async load(id) {
      if (cloud()) {
        const snap = await ref(id).once('value');

        return snap.exists()
          ? Buffer.from(snap.val(), 'base64')
          : null;
      }

      return fs.existsSync(file(id))
        ? fs.readFileSync(file(id))
        : null;
    },

    async remove(id) {
      if (cloud()) {
        return ref(id).remove();
      }

      fs.rmSync(file(id), { force: true });
    },
  };
}

module.exports = { createPhotoStore };