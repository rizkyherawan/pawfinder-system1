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
    this.cloud = null;
    this._pending = Promise.resolve();
    // Status sementara (tidak disimpan ke disk): paket terakhir tiap alat, antrean perintah, alat terdeteksi.
    this.runtime = { live: new Map(), commands: new Map(), discovered: new Map() };
  }

  static emptyDb() {
    return { users: [], pets: [], geofences: [], events: [], notifications: [], healthRecords: [], stats: {}, settings: {} };
  }

  load() {
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    if (fs.existsSync(this.file)) {
      try {
        const parsed = JSON.parse(fs.readFileSync(this.file, 'utf8'));
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('isi berkas bukan objek JSON');
        this.data = { ...Store.emptyDb(), ...parsed };
        return this;
      } catch (e) {
        // Jangan timpa berkas rusak: pindahkan sebagai cadangan agar data masih bisa diperiksa/dipulihkan.
        const backup = `${this.file}.rusak-${Date.now()}`;
        try { fs.renameSync(this.file, backup); } catch (_) { /* abaikan */ }
        console.warn(`[store] db.json rusak (${e.message}). Disalin ke ${backup}; membuat database baru.`);
      }
    }
    this.data = Store.emptyDb();
    return this;
  }

  async loadCloud(cloud) {
    const data = await cloud.load();
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new Error('Database Firebase belum tersedia atau tidak valid');
    }
    this.data = { ...Store.emptyDb(), ...data };
    this.attachCloud(cloud);
    return this;
  }

  attachCloud(cloud) {
    this.cloud = cloud;
    return this;
  }

  queueCloudSave() {
    if (!this.cloud) return Promise.resolve();
    const snapshot = JSON.parse(JSON.stringify(this.data));
    this._pending = this._pending.catch(() => {}).then(() => this.cloud.save(snapshot));
    return this._pending;
  }

  save() {
    clearTimeout(this._timer);
    this._timer = setTimeout(() => {
      try { Promise.resolve(this.saveNow()).catch(e => console.error('[store] Firebase gagal menyimpan:', e.message)); } catch (e) { console.error('[store] gagal menyimpan:', e.message); }
    }, 200);
  }

  saveNow() {
    clearTimeout(this._timer);
    if (this.cloud) return this.queueCloudSave();
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
