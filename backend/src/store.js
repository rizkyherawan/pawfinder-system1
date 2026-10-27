'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/** Penyimpanan JSON sederhana: data di memori, ditulis ke disk secara atomik. */
class Store {
  constructor(file) {
    this.file = file;
    this.data = null;
    this._timer = null;
  }

  static emptyDb() {
    return { users: [], pets: [], geofences: [], events: [], notifications: [], healthRecords: [], stats: {}, settings: {} };
  }

  load() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    if (fs.existsSync(this.file)) {
      try {
        this.data = { ...Store.emptyDb(), ...JSON.parse(fs.readFileSync(this.file, 'utf8')) };
        return this;
      } catch (e) {
        console.warn('[store] db.json rusak, membuat database baru:', e.message);
      }
    }
    this.data = Store.emptyDb();
    return this;
  }

  save() {
    clearTimeout(this._timer);
    this._timer = setTimeout(() => this.saveNow(), 200);
  }

  saveNow() {
    clearTimeout(this._timer);
    const tmp = this.file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.data, null, 2));
    fs.renameSync(tmp, this.file);
  }

  reset() {
    this.data = Store.emptyDb();
    this.saveNow();
  }

  id(prefix) {
    return `${prefix}_${crypto.randomBytes(5).toString('hex')}`;
  }
}

module.exports = { Store };
