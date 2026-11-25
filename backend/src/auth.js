'use strict';

const crypto = require('crypto');
const config = require('./config');

const b64u = (buf) => Buffer.from(buf).toString('base64url');

const PASSWORD_MIN = 8;
const PASSWORD_MAX = 128;

function passwordProblem(password) {
  const p = String(password === undefined || password === null ? '' : password);

  if (p.length === 0) return 'Kata sandi wajib diisi';
  if (p.length < PASSWORD_MIN) return `Kata sandi minimal ${PASSWORD_MIN} karakter`;
  if (p.length > PASSWORD_MAX) return `Kata sandi maksimal ${PASSWORD_MAX} karakter`;

  if (!/[A-Za-z]/.test(p) || !/\d/.test(p)) {
    return 'Kata sandi harus mengandung huruf dan angka';
  }

  return null;
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');

  return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
  const [salt, hash] = String(stored || '').split(':');

  if (!salt || !hash) return false;

  const test = crypto.scryptSync(password, salt, 64);
  const known = Buffer.from(hash, 'hex');

  return known.length === test.length &&
    crypto.timingSafeEqual(known, test);
}

const DUMMY_HASH = hashPassword('pawfinder-dummy-password-1');

function burnPasswordTime(password) {
  try {
    verifyPassword(String(password || ''), DUMMY_HASH);
  } catch (_) {
    // Abaikan.
  }
}

function signToken(payload) {
  const header = b64u(JSON.stringify({
    alg: 'HS256',
    typ: 'JWT',
  }));

  const now = Math.floor(Date.now() / 1000);

  const body = b64u(JSON.stringify({
    ...payload,
    iat: now,
    exp: now + config.tokenTtlDays * 86400,
  }));

  const sig = crypto
    .createHmac('sha256', config.jwtSecret)
    .update(`${header}.${body}`)
    .digest('base64url');

  return `${header}.${body}.${sig}`;
}

function verifyToken(token) {
  try {
    const parts = String(token).split('.');

    if (parts.length !== 3) return null;

    const [h, b, s] = parts;

    if (!h || !b || !s) return null;

    const expect = crypto
      .createHmac('sha256', config.jwtSecret)
      .update(`${h}.${b}`)
      .digest('base64url');

    const a = Buffer.from(s);
    const e = Buffer.from(expect);

    if (
      a.length !== e.length ||
      !crypto.timingSafeEqual(a, e)
    ) {
      return null;
    }

    const payload = JSON.parse(
      Buffer.from(b, 'base64url').toString('utf8')
    );

    if (
      !payload ||
      typeof payload.exp !== 'number' ||
      payload.exp <= Date.now() / 1000
    ) {
      return null;
    }

    return payload;
  } catch (_) {
    return null;
  }
}

class RateLimiter {
  constructor({
    max,
    windowMs,
    storage = null,
    namespace = 'default',
  }) {
    this.max = max;
    this.windowMs = windowMs;
    this.storage = storage;
    this.namespace = namespace;

    const saved = storage
      ? storage[namespace]
      : null;

    this.hits = new Map(
      Object.entries(saved || {})
    );

    this.sweep();
  }

  storageKey(key) {
    return crypto
      .createHash('sha256')
      .update(String(key))
      .digest('hex');
  }

  persist() {
    if (!this.storage) return;

    this.storage[this.namespace] =
      Object.fromEntries(this.hits);
  }

  check(key) {
    const now = Date.now();
    const id = this.storageKey(key);
    const h = this.hits.get(id);

    if (!h) return 0;

    if (now - h.first >= this.windowMs) {
      this.hits.delete(id);
      this.persist();
      return 0;
    }

    return h.count >= this.max
      ? Math.ceil(
          (h.first + this.windowMs - now) / 1000
        )
      : 0;
  }

  fail(key) {
    const now = Date.now();
    const id = this.storageKey(key);
    const h = this.hits.get(id);

    if (!h || now - h.first >= this.windowMs) {
      this.hits.set(id, {
        first: now,
        count: 1,
      });
    } else {
      h.count++;
    }

    if (this.hits.size > 5000) {
      this.sweep();
    }

    this.persist();
  }

  reset(key) {
    this.hits.delete(this.storageKey(key));
    this.persist();
  }

  sweep() {
    const now = Date.now();
    let changed = false;

    for (const [key, h] of this.hits) {
      if (now - h.first >= this.windowMs) {
        this.hits.delete(key);
        changed = true;
      }
    }

    if (changed) {
      this.persist();
    }
  }
}

module.exports = {
  hashPassword,
  verifyPassword,
  burnPasswordTime,
  passwordProblem,
  signToken,
  verifyToken,
  RateLimiter,
  PASSWORD_MIN,
  PASSWORD_MAX,
};