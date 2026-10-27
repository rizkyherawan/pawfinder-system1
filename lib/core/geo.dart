import 'dart:math' as math;
import 'dart:ui' show Offset;

class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
  factory GeoPoint.fromJson(Map<String, dynamic> j) => GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
}

const _earth = 6371000.0;
double _rad(double d) => d * math.pi / 180;

double distanceMeters(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat), dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earth * math.asin(math.sqrt(h));
}

double bearingTo(GeoPoint a, GeoPoint b) {
  final y = math.sin(_rad(b.lng - a.lng)) * math.cos(_rad(b.lat));
  final x = math.cos(_rad(a.lat)) * math.sin(_rad(b.lat)) - math.sin(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.cos(_rad(b.lng - a.lng));
  return math.atan2(y, x);
}

GeoPoint movePoint(GeoPoint p, double bearingRad, double meters) {
  final d = meters / _earth, lat1 = _rad(p.lat), lng1 = _rad(p.lng);
  final lat2 = math.asin(math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(bearingRad));
  final lng2 = lng1 + math.atan2(math.sin(bearingRad) * math.sin(d) * math.cos(lat1), math.cos(d) - math.sin(lat1) * math.sin(lat2));
  return GeoPoint(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
}

/// Selisih posisi dalam meter dari [origin]: dx ke timur, dy ke selatan (searah sumbu layar).
Offset metersOffset(GeoPoint origin, GeoPoint p) {
  final dx = (p.lng - origin.lng) * 111320 * math.cos(_rad(origin.lat));
  final dy = -(p.lat - origin.lat) * 110540;
  return Offset(dx, dy);
}

/// Kebalikan [metersOffset]: titik geografis dari selisih meter (dx timur, dy selatan) terhadap [origin].
GeoPoint offsetToPoint(GeoPoint origin, Offset m) =>
    GeoPoint(origin.lat - m.dy / 110540, origin.lng + m.dx / (111320 * math.cos(_rad(origin.lat))));
