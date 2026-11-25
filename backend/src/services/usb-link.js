'use strict';
const { EventEmitter } = require('events');
const { parseLine, LineSplitter, encodeCommand } = require('./device-protocol');
const { pickArduino } = require('./serial-io');

const BACKOFF_MS = [1000, 2000, 4000, 8000, 10000];
const MAX_PENDING = 20;

/**
 * Tautan kabel USB ke Arduino: membuka port serial, memotong aliran byte menjadi baris, mem-parse,
 * lalu meneruskan ke `onMessage`. Port yang dicabut/dicolok kembali disambung ulang otomatis.
 *
 * Opsi: path ('auto' | nama port), baud, opener, lister, onMessage(msg, meta) -> hasil | Promise,
 *       pullCommands(serial) -> [{cmd,arg}], onClosed(serials), defaultSerial, log
 */
class UsbLink extends EventEmitter {
  constructor(opts) {
    super();
    this.pathSpec = opts.path || 'auto';
    this.baud = opts.baud || 9600;
    this.opener = opts.opener;
    this.lister = opts.lister;
    this.onMessage = opts.onMessage;
    this.pullCommands = opts.pullCommands || null;
    this.onClosed = opts.onClosed || null;
    this.defaultSerial = opts.defaultSerial || '';
    this.log = opts.log || (() => {});
    this.whoDelayMs = opts.whoDelayMs === undefined ? 1800 : opts.whoDelayMs;
    this.backoff = opts.backoffMs || BACKOFF_MS;

    this.stopped = true;
    this.state = 'idle'; // idle | connecting | connected | disconnected
    this.path = null;
    this.port = null;
    this.attempt = 0;
    this.openedAt = null;
    this.lastLineAt = null;
    this.lines = 0;
    this.bytes = 0;
    this.parseErrors = 0;
    this.errors = 0;
    this.dropped = 0;
    this.lastError = null;
    this.lastUnknown = null;
    this.lastReject = null;
    this.serials = new Set();
    this.splitter = new LineSplitter();
    this._timer = null;
    this._pump = null;
    this._chain = Promise.resolve();
    this._pending = 0;
  }

  start() {
    if (!this.stopped) return this;
    this.stopped = false;
    if (this.defaultSerial) this.serials.add(this.defaultSerial);
    this._pump = setInterval(() => this._pumpCommands(), 500);
    if (this._pump.unref) this._pump.unref();
    this._connect();
    return this;
  }

  stop() {
    this.stopped = true;
    clearTimeout(this._timer);
    clearInterval(this._pump);
    const port = this.port;
    this.port = null;
    this.state = 'idle';
    if (port) { try { port.close(); } catch (_) { /* abaikan */ } }
  }

  async _resolvePath() {
    if (this.pathSpec !== 'auto') return this.pathSpec;
    const ports = await this.lister();
    const pick = pickArduino(ports);
    if (!pick) throw new Error(ports && ports.length ? 'Ada beberapa port serial tetapi tidak ada yang dikenali sebagai Arduino. Isi USB_PORT dengan nama port (mis. COM3).' : 'Arduino belum terdeteksi. Colok kabel USB lalu tunggu beberapa detik.');
    return pick.path;
  }

  async _connect() {
    if (this.stopped) return;
    this.state = 'connecting';
    let devPath;
    try { devPath = await this._resolvePath(); }
    catch (e) { return this._failed(e.message); }
    if (this.stopped) return;
    if (!this.opener) return this._failed('Driver serial tidak tersedia. Jalankan "npm install serialport" di folder backend.');

    let port;
    try { port = this.opener({ path: devPath, baudRate: this.baud }); }
    catch (e) { return this._failed(`Gagal membuka ${devPath}: ${e.message}`); }
    this.port = port;
    this.path = devPath;
    this.splitter = new LineSplitter();
    let opened = false, handled = false;

    const lost = (reason) => {
      if (handled) return;
      handled = true;
      if (this.port === port) this.port = null;
      try { port.close(); } catch (_) { /* abaikan */ }
      if (reason) this.lastError = reason;
      this.state = 'disconnected';
      this.log(`[usb] ${devPath} terputus${reason ? `: ${reason}` : ''}`);
      if (this.onClosed && opened) { try { this.onClosed([...this.serials]); } catch (_) { /* abaikan */ } }
      this.emit('close', devPath);
      this._schedule();
    };

    port.on('open', () => {
      opened = true;
      this.state = 'connected';
      this.attempt = 0;
      this.openedAt = Date.now();
      this.lastError = null;
      this.log(`[usb] terhubung ke ${devPath} @ ${this.baud} baud`);
      this.emit('open', devPath);
      // Tanyakan identitas alat (papan tanpa auto-reset tidak mengirim "hello" sendiri).
      const t = setTimeout(() => { if (this.port === port) this.send('WHO\n'); }, this.whoDelayMs);
      if (t.unref) t.unref();
    });
    port.on('data', (chunk) => { try { this._onData(chunk); } catch (e) { this.errors++; this.lastError = e.message; } });
    port.on('error', (err) => { this.errors++; this.lastError = err && err.message ? err.message : String(err); lost(this.lastError); });
    port.on('close', () => lost(opened ? 'kabel dicabut atau port ditutup' : null));
  }

  _failed(msg) {
    this.lastError = msg;
    this.state = 'disconnected';
    this._schedule();
  }

  _schedule() {
    if (this.stopped) return;
    const delay = this.backoff[Math.min(this.attempt, this.backoff.length - 1)];
    this.attempt++;
    clearTimeout(this._timer);
    this._timer = setTimeout(() => this._connect(), delay);
    if (this._timer.unref) this._timer.unref();
  }

  _onData(chunk) {
    this.bytes += chunk.length;
    for (const line of this.splitter.feed(chunk)) this._onLine(line);
  }

  _onLine(line) {
    this.lines++;
    this.lastLineAt = Date.now();
    const msg = parseLine(line);
    if (!msg) return;
    if (msg.kind === 'log') return;
    if (msg.kind === 'unknown') {
      this.parseErrors++;
      this.lastUnknown = { line: line.slice(0, 80), reason: msg.reason, at: Date.now() };
      return;
    }
    const sn = msg.serial || this.defaultSerial;
    if (sn) this.serials.add(sn);
    if (this._pending >= MAX_PENDING) { this.dropped++; return; } // server lambat: buang paket lama, bukan menumpuk
    this._pending++;
    const meta = { port: this.path };
    // Rantai Promise menjaga urutan paket walau penerimanya asinkron (mis. HTTP).
    this._chain = this._chain
      .then(() => this.onMessage(msg, meta))
      .then((res) => this._after(res))
      .catch((e) => { this.errors++; this.lastError = e && e.message ? e.message : String(e); })
      .then(() => { this._pending--; });
  }

  _after(res) {
    if (!res) return;
    if (res.ok === false && res.code) this.lastReject = { code: res.code, error: res.error, at: Date.now() };
    else if (res.ok) this.lastReject = null;
    if (Array.isArray(res.commands)) this._sendCommands(res.commands);
  }

  _sendCommands(list) {
    for (const c of list) {
      const line = encodeCommand(c.cmd, c.arg);
      if (line) this.send(line);
    }
  }

  _pumpCommands() {
    if (this.state !== 'connected' || !this.pullCommands) return;
    for (const sn of this.serials) {
      let cmds = [];
      try { cmds = this.pullCommands(sn) || []; } catch (_) { cmds = []; }
      if (cmds.length) this._sendCommands(cmds);
    }
  }

  /** Mengirim satu baris ke alat. true bila tertulis. */
  send(line) {
    if (this.state !== 'connected' || !this.port) return false;
    try { this.port.write(line); return true; }
    catch (e) { this.errors++; this.lastError = e.message; return false; }
  }

  status() {
    return {
      enabled: true,
      state: this.state,
      path: this.path,
      baud: this.baud,
      auto: this.pathSpec === 'auto',
      attempt: this.attempt,
      openedAt: this.openedAt ? new Date(this.openedAt).toISOString() : null,
      lastLineAt: this.lastLineAt ? new Date(this.lastLineAt).toISOString() : null,
      lastLineAgeSec: this.lastLineAt ? Math.round((Date.now() - this.lastLineAt) / 1000) : null,
      lines: this.lines,
      bytes: this.bytes,
      parseErrors: this.parseErrors,
      errors: this.errors,
      dropped: this.dropped,
      lastError: this.lastError,
      lastUnknown: this.lastUnknown ? { line: this.lastUnknown.line, reason: this.lastUnknown.reason } : null,
      lastReject: this.lastReject ? { code: this.lastReject.code, error: this.lastReject.error } : null,
      serials: [...this.serials],
    };
  }
}

module.exports = { UsbLink };
