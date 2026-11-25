'use strict';

const { Store } = require('./store');

class ServerlessStore extends Store {
  constructor(session) {
    super(null);

    this.session = session;
    this.data = session.data;
    this.runtime = session.runtime;
    this.rateLimits = session.rateLimits;
    this.dirty = false;

    this.photoStore = {
      save: async (id, buffer) => {
        session.photos[id] = buffer.toString('base64');
        this.dirty = true;
      },

      load: async (id) => {
        const raw = session.photos[id];

        return raw
          ? Buffer.from(raw, 'base64')
          : null;
      },

      remove: async (id) => {
        delete session.photos[id];
        this.dirty = true;
      },
    };
  }

  save() {
    this.dirty = true;
  }

  async saveNow() {
    this.dirty = true;
  }
}

module.exports = { ServerlessStore };