'use strict';
const crypto = require('crypto');
const config = require('./config');

const b64u = (buf) => Buffer.from(buf).toString('base64url');

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
  return known.length === test.length && crypto.timingSafeEqual(known, test);
}

/** Token bergaya JWT (HS256) tanpa library. */
function signToken(payload) {
  const header = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const exp = Math.floor(Date.now() / 1000) + config.tokenTtlDays * 86400;
  const body = b64u(JSON.stringify({ ...payload, exp }));
  const sig = crypto.createHmac('sha256', config.jwtSecret).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${sig}`;
}

function verifyToken(token) {
  try {
    const [h, b, s] = String(token).split('.');
    const expect = crypto.createHmac('sha256', config.jwtSecret).update(`${h}.${b}`).digest('base64url');
    const a = Buffer.from(s || ''), e = Buffer.from(expect);
    if (a.length !== e.length || !crypto.timingSafeEqual(a, e)) return null;
    const payload = JSON.parse(Buffer.from(b, 'base64url').toString('utf8'));
    if (payload.exp < Date.now() / 1000) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

module.exports = { hashPassword, verifyPassword, signToken, verifyToken };
