'use strict';
const config = require('../config');
const { haversine, bearing, destination } = require('../geo');
const { ingestTelemetry, clamp } = require('./engine');

const BASE = { anjing: { hr: 95, temp: 38.5 }, kucing: { hr: 140, temp: 38.6 }, kelinci: { hr: 180, temp: 39.0 } };

/**
 * Simulator kalung GPS (hanya untuk demo): hewan yang SUDAH dipasangkan ke kalung dan bertanda
 * device.simulated=true akan mengirim telemetri sendiri. Hewan yang belum dipasangkan tidak bergerak
 * dan tidak mengirim apa pun, sehingga statusnya tetap "belum terhubung".
 */
function start(store) {
  const state = new Map();
  let tick = 0;
  const timer = setInterval(() => {
    tick++;
    for (const pet of store.data.pets) {
      if (!pet.device || !pet.device.paired || !pet.device.simulated) continue;
      const fence = store.data.geofences.find((g) => g.petId === pet.id);
      const home = fence ? fence.center : config.home;
      let s = state.get(pet.id);
      if (!s) {
        s = { heading: Math.random() * Math.PI * 2, wander: 90 + Math.random() * 140, adventure: 0 };
        state.set(pet.id, s);
      }
      const cur = pet.location || destination(home, Math.random() * Math.PI * 2, 15 + Math.random() * 45);
      if (Math.random() < 0.004) s.adventure = 25; // petualangan singkat keluar area
      const limit = s.adventure > 0 ? Math.max((fence ? fence.radius : 300) * 1.4, s.wander * 2) : s.wander;
      if (s.adventure > 0) s.adventure--;
      s.heading += (Math.random() - 0.5) * 0.9;
      if (haversine(cur, home) > limit) s.heading = bearing(cur, home) + (Math.random() - 0.5) * 0.5;
      const next = destination(cur, s.heading, 3 + Math.random() * 9);
      let battery = typeof pet.device.battery === 'number' ? pet.device.battery : 100;
      if (tick % 25 === 0) battery = clamp(battery - 1, 3, 100);
      const b = BASE[pet.species] || BASE.anjing;
      ingestTelemetry(store, pet, {
        lat: next.lat, lng: next.lng, battery, signal: battery < 15 ? 'Sedang' : 'Kuat',
        heartRate: b.hr + (Math.random() - 0.5) * 14, temperature: b.temp + (Math.random() - 0.5) * 0.4,
      });
    }
  }, config.simulatorIntervalMs);
  timer.unref();
  console.log(`[simulator] aktif, interval ${config.simulatorIntervalMs} ms (hanya untuk hewan yang sudah dipasangkan)`);
  return timer;
}

module.exports = { start };
