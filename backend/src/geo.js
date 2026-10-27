'use strict';
const R = 6371000;
const rad = (d) => (d * Math.PI) / 180;
const deg = (r) => (r * 180) / Math.PI;

function haversine(a, b) {
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function bearing(a, b) {
  const y = Math.sin(rad(b.lng - a.lng)) * Math.cos(rad(b.lat));
  const x = Math.cos(rad(a.lat)) * Math.sin(rad(b.lat)) - Math.sin(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.cos(rad(b.lng - a.lng));
  return Math.atan2(y, x);
}

function destination(p, bearingRad, meters) {
  const d = meters / R, lat1 = rad(p.lat), lng1 = rad(p.lng);
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(bearingRad));
  const lng2 = lng1 + Math.atan2(Math.sin(bearingRad) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2));
  return { lat: deg(lat2), lng: deg(lng2) };
}

// Landmark sekitar Sleman untuk "reverse geocoding" ringan (tanpa API eksternal)
const PLACES = [
  { name: 'Jl. Melati, Sleman', lat: -7.71556, lng: 110.35547 },
  { name: 'Taman Denggung, Sleman', lat: -7.7112, lng: 110.3471 },
  { name: 'Jl. Magelang, Sleman', lat: -7.7205, lng: 110.3598 },
  { name: 'Jl. Kaliurang, Sleman', lat: -7.7089, lng: 110.3632 },
  { name: 'Jl. Pemuda, Sleman', lat: -7.7231, lng: 110.3489 },
  { name: 'Jl. Tentara Pelajar, Sleman', lat: -7.7142, lng: 110.3417 },
];

function reverseGeocode(p, home) {
  if (home && haversine(p, home) <= 60) return home.address;
  let best = PLACES[0], bd = Infinity;
  for (const pl of PLACES) {
    const d = haversine(p, pl);
    if (d < bd) { bd = d; best = pl; }
  }
  return `${best.name}, Yogyakarta`;
}

/** Tanggal kalender WIB (UTC+7) dalam format YYYY-MM-DD */
function wibDateKey(date = new Date()) {
  const d = new Date(date.getTime() + 7 * 3600 * 1000);
  return d.toISOString().slice(0, 10);
}

/** Bangun Date UTC dari tanggal WIB (YYYY-MM-DD) + jam:menit WIB */
function wibToDate(dateKey, hour, minute) {
  const [y, m, d] = dateKey.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d, hour - 7, minute, 0));
}

function addDays(dateKey, n) {
  const [y, m, d] = dateKey.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

const DAY_LABELS = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
function dayLabel(dateKey) {
  const [y, m, d] = dateKey.split('-').map(Number);
  return DAY_LABELS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
}

module.exports = { haversine, bearing, destination, reverseGeocode, wibDateKey, wibToDate, addDays, dayLabel };
