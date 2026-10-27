'use strict';
const fs = require('fs');
const path = require('path');
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
  '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon', '.webp': 'image/webp', '.woff2': 'font/woff2',
};

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization,x-device-key',
  'Access-Control-Max-Age': '86400',
};

class Router {
  constructor(store) {
    this.store = store;
    this.routes = [];
  }

  add(method, pattern, opts, handler) {
    if (typeof opts === 'function') { handler = opts; opts = {}; }
    const keys = [];
    const regex = new RegExp('^' + pattern.replace(/:([A-Za-z]+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '/?$');
    this.routes.push({ method, regex, keys, auth: opts.auth !== false, handler });
  }

  get(p, o, h) { this.add('GET', p, o, h); }
  post(p, o, h) { this.add('POST', p, o, h); }
  put(p, o, h) { this.add('PUT', p, o, h); }
  patch(p, o, h) { this.add('PATCH', p, o, h); }
  delete(p, o, h) { this.add('DELETE', p, o, h); }

  async readBody(req) {
    const chunks = [];
    let size = 0;
    for await (const c of req) {
      size += c.length;
      if (size > 1_000_000) throw new HttpError(413, 'Payload terlalu besar');
      chunks.push(c);
    }
    if (!chunks.length) return {};
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch (_) { throw new HttpError(400, 'Body harus berupa JSON yang valid'); }
  }

  json(res, status, body) {
    const payload = JSON.stringify(body);
    res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(payload), ...CORS });
    res.end(payload);
  }

  serveStatic(webDir, urlPath, res) {
    let rel;
    try { rel = decodeURIComponent(urlPath.split('?')[0]); }
    catch (_) { return this.json(res, 400, { error: 'URL tidak valid' }); }
    if (rel === '/' || rel === '') rel = '/index.html';
    const file = path.normalize(path.join(webDir, rel));
    if (file !== webDir && !file.startsWith(webDir + path.sep)) return this.json(res, 403, { error: 'Dilarang' });
    fs.stat(file, (err, st) => {
      const target = !err && st.isFile() ? file : path.join(webDir, 'index.html');
      fs.readFile(target, (e2, buf) => {
        if (e2) return this.json(res, 404, { error: 'Tidak ditemukan' });
        res.writeHead(200, { 'Content-Type': MIME[path.extname(target)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
        res.end(buf);
      });
    });
  }

  handler(webDir) {
    return async (req, res) => {
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'OPTIONS') { res.writeHead(204, CORS); return res.end(); }
      if (!url.pathname.startsWith('/api/')) {
        if (webDir && fs.existsSync(webDir)) return this.serveStatic(webDir, url.pathname, res);
        return this.json(res, 404, { error: 'Frontend web tidak ditemukan. Gunakan /api/*' });
      }
      try {
        for (const r of this.routes) {
          if (r.method !== req.method) continue;
          const m = r.regex.exec(url.pathname);
          if (!m) continue;
          const params = {};
          r.keys.forEach((k, i) => (params[k] = decodeURIComponent(m[i + 1])));
          const ctx = { req, res, params, query: Object.fromEntries(url.searchParams), store: this.store, user: null, body: {} };
          if (r.auth) {
            const header = req.headers.authorization || '';
            const token = header.startsWith('Bearer ') ? header.slice(7) : url.searchParams.get('token');
            const payload = token && verifyToken(token);
            if (!payload) throw new HttpError(401, 'Sesi berakhir. Silakan masuk kembali.');
            ctx.user = this.store.data.users.find((u) => u.id === payload.sub);
            if (!ctx.user) throw new HttpError(401, 'Akun tidak ditemukan.');
          }
          if (['POST', 'PUT', 'PATCH'].includes(req.method)) ctx.body = await this.readBody(req);
          const out = await r.handler(ctx);
          if (out === undefined || res.writableEnded || res.headersSent) return;
          return this.json(res, 200, out);
        }
        throw new HttpError(404, `Endpoint ${req.method} ${url.pathname} tidak ada`);
      } catch (e) {
        const status = e.status || 500;
        if (status === 500) console.error('[error]', e);
        this.json(res, status, { error: e.message || 'Kesalahan server', ...(e.extra || {}) });
      }
    };
  }
}

module.exports = { Router, HttpError };
