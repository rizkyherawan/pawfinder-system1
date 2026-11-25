'use strict';
const { isDeepStrictEqual } = require('node:util');
const { connectFirebase } = require('./firebase-store');
const { restoreRuntime, serializeRuntime } = require('./cloud-runtime');
function decodeObject(v) {
  if (typeof v === 'string') v = JSON.parse(v);
  if (v == null) return {};
  if (typeof v !== 'object' || Array.isArray(v)) throw new Error('Format cloud tidak valid');
  return v;
}
class CloudSnapshot {
  constructor(root = 'pawfinder_vercel_test') {
    this.ref = connectFirebase().ref(root);
  }
  async load() {
    const raw = (await this.ref.once('value')).val();
    if (!raw || typeof raw.state !== 'string') throw new Error('Database cloud tidak ditemukan');
    const data = JSON.parse(raw.state);
    if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('Format database tidak valid');
    return { raw, data, runtime: restoreRuntime(decodeObject(raw.runtime)), photos: { ...(raw.photos || {}) }, rateLimits: structuredClone(decodeObject(raw.rateLimits)) };
  }
  async commit(session) {
    const next = { ...session.raw, state: JSON.stringify(session.data), runtime: JSON.stringify(serializeRuntime(session.runtime)), rateLimits: JSON.stringify(session.rateLimits) };
    if (Object.keys(session.photos).length) next.photos = { ...session.photos };
    else delete next.photos;
    if (isDeepStrictEqual(session.raw, next)) return { changed: false };
    const result = await this.ref.transaction(current => {
      if (current === null) return null;
      if (!isDeepStrictEqual(current, session.raw)) return undefined;
      return next;
    }, undefined, false);
    if (!result.committed || !isDeepStrictEqual(result.snapshot.val(), next)) {
      const error = new Error('Konflik penyimpanan cloud');
      error.status = 409;
      error.code = 'STATE_CONFLICT';
      throw error;
    }
    return { changed: true };
  }
}
module.exports = { CloudSnapshot };