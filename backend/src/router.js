'use strict';
const fs = require('fs');
const path = require('path');
const config = require('./config');
const { verifyToken } = require('./auth');

class HttpError extends Error {
  constructor(status, message, extra) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.ico': 'image/x-icon', '.webp': 'image/webp', '.woff2': 'font/woff2',
  '.wasm': 'application/wasm', '.map': 'application/json; charset=utf-8',
};

const SECURITY = { 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'X-Frame-Options': 'SAMEORIGIN' };

const MAX_BODY = 1_000_000;

/** Header CORS untuk satu permintaan. '*' bila tidak dibatasi; selain itu hanya origin yang diizinkan. */
function corsHeaders(req) {
  const base = {
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization,x-device-key',
    'Access-Control-Max-Age': '86400',
  };
  if (config.corsOrigin === '*') return { ...base, 'Access-Control-Allow-Origin': '*' };
  const allowed = config.corsOrigin.split(',').map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.origin;
  if (origin && allowed.includes(origin)) return { ...base, 'Access-Control-Allow-Origin': origin, Vary: 'Origin' };
  return { ...base, Vary: 'Origin' };
}

class Router {
  constructor(store) {
    this.store = store;
    this.routes = [];
  }

  add(method, pattern, opts, handler) {
    if (typeof opts === 'function') { handler = opts; opts = {}; }
    const keys = [];
    const regex = new RegExp('^' + pattern.replace(/:([A-Za-z]+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '/?$');
    this.routes.push({ method, regex, keys, auth: opts.auth !== false, maxBody: opts.maxBody || MAX_BODY, handler });
  }

  get(p, o, h) { this.add('GET', p, o, h); }
  post(p, o, h) { this.add('POST', p, o, h); }
  put(p, o, h) { this.add('PUT', p, o, h); }
  patch(p, o, h) { this.add('PATCH', p, o, h); }
  delete(p, o, h) { this.add('DELETE', p, o, h); }

  /** IP klien (memakai X-Forwarded-For hanya bila TRUST_PROXY aktif). */
  clientIp(req) {
    if (config.trustProxy) {
      const fwd = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
      if (fwd) return fwd;
    }
    return (req.socket && req.socket.remoteAddress) || 'unknown';
  }

  async readBody(req, max = MAX_BODY) {
    const declared = Number(req.headers['content-length'] || 0);
    if (declared > max) throw new HttpError(413, 'Payload terlalu besar');
    const chunks = [];
    let size = 0;
    for await (const c of req) {
      size += c.length;
      if (size > max) throw new HttpError(413, 'Payload terlalu besar');
      chunks.push(c);
    }
    if (!chunks.length) return {};
    let parsed;
    try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch (_) { throw new HttpError(400, 'Body harus berupa JSON yang valid'); }
    // Semua handler mengharapkan objek: tolak null, array, angka, atau teks.
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new HttpError(400, 'Body harus berupa objek JSON');
    return parsed;
  }

  json(res, status, body, req) {
    if (res.headersSent || res.writableEnded) return;
    const payload = JSON.stringify(body);
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Length': Buffer.byteLength(payload),
      'Cache-Control': 'no-store',
      ...SECURITY,
      ...(req ? corsHeaders(req) : { 'Access-Control-Allow-Origin': config.corsOrigin === '*' ? '*' : 'null' }),
    });
    res.end(payload);
  }

  serveStatic(webDir, urlPath, res, req) {
    let rel;
    try { rel = decodeURIComponent(urlPath.split('?')[0]); }
    catch (_) { return this.json(res, 400, { error: 'URL tidak valid' }, req); }
    if (rel === '/' || rel === '') rel = '/index.html';
    const file = path.normalize(path.join(webDir, rel));
    if (file !== webDir && !file.startsWith(webDir + path.sep)) return this.json(res, 403, { error: 'Dilarang' }, req);
    fs.stat(file, (err, st) => {
      const target = !err && st.isFile() ? file : path.join(webDir, 'index.html');
      fs.readFile(target, (e2, buf) => {
        if (e2) return this.json(res, 404, { error: 'Tidak ditemukan' }, req);
        res.writeHead(200, { 'Content-Type': MIME[path.extname(target).toLowerCase()] || 'application/octet-stream', 'Cache-Control': 'no-cache', ...SECURITY });
        res.end(buf);
      });
    });
  }

  handler(webDir) {
    return async (req, res) => {
      try {
        let url;
        try { url = new URL(req.url, 'http://localhost'); }
        catch (_) { return this.json(res, 400, { error: 'URL tidak valid' }, req); }
        if (req.method === 'OPTIONS') { res.writeHead(204, corsHeaders(req)); return res.end(); }
        if (!url.pathname.startsWith('/api/')) {
          if (req.method !== 'GET' && req.method !== 'HEAD') return this.json(res, 405, { error: 'Metode tidak diizinkan' }, req);
          if (webDir && fs.existsSync(webDir)) return this.serveStatic(webDir, url.pathname, res, req);
          return this.json(res, 404, { error: 'Frontend web belum dibangun. Jalankan "flutter build web" atau gunakan /api/*' }, req);
        }

        let pathMatched = false;
        for (const r of this.routes) {
          const m = r.regex.exec(url.pathname);
          if (!m) continue;
          pathMatched = true;
          if (r.method !== req.method) continue;
          const params = {};
          try { r.keys.forEach((k, i) => (params[k] = decodeURIComponent(m[i + 1]))); }
          catch (_) { throw new HttpError(400, 'Parameter URL tidak valid'); }
          const ctx = { req, res, params, query: Object.fromEntries(url.searchParams), store: this.store, user: null, body: {}, ip: this.clientIp(req), router: this };
          if (r.auth) {
            const header = req.headers.authorization || '';
            const token = header.startsWith('Bearer ') ? header.slice(7) : url.searchParams.get('token');
            const payload = token && verifyToken(token);
            if (!payload) throw new HttpError(401, 'Sesi berakhir. Silakan masuk kembali.');
            ctx.user = this.store.data.users.find((u) => u.id === payload.sub);
            if (!ctx.user) throw new HttpError(401, 'Akun tidak ditemukan.');
          }
          if (['POST', 'PUT', 'PATCH'].includes(req.method)) ctx.body = await this.readBody(req, r.maxBody);
          const out = await r.handler(ctx);
          if (out === undefined || res.writableEnded || res.headersSent) return;
          return this.json(res, 200, out, req);
        }
        if (pathMatched) throw new HttpError(405, `Metode ${req.method} tidak diizinkan untuk ${url.pathname}`);
        throw new HttpError(404, `Endpoint ${req.method} ${url.pathname} tidak ada`);
      } catch (e) {
        const status = e.status || 500;
        if (status === 500) console.error('[error]', e);
        const message = status === 500 && config.isProd ? 'Terjadi kesalahan pada server' : (e.message || 'Kesalahan server');
        this.json(res, status, { error: message, ...(e.extra || {}) }, req);
      }
    };
  }
}

module.exports = { Router, HttpError, corsHeaders };
