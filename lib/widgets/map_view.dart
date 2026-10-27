import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';
import 'pet_face.dart';

/// Pengendali zoom & geser peta (dipakai bersama tombol +/−).
class PFMapController extends ChangeNotifier {
  double zoom = 1;
  Offset pan = Offset.zero;

  void update({Offset panDelta = Offset.zero, double? zoom}) {
    pan += panDelta;
    if (zoom != null) this.zoom = zoom.clamp(0.35, 8.0).toDouble();
    notifyListeners();
  }

  void zoomBy(double factor) => update(zoom: zoom * factor);
  void reset() {
    zoom = 1;
    pan = Offset.zero;
    notifyListeners();
  }
}

class MapPinData {
  const MapPinData({required this.id, required this.point, required this.child, this.size = 80});
  final String id;
  final GeoPoint point;
  final Widget child;
  final double size;
}

/// Peta ilustratif (tanpa API eksternal): blok kota, jalan, sungai, taman, lingkaran
/// geofence dan pin hewan yang dapat digeser/di-zoom.
class IllustratedMap extends StatefulWidget {
  const IllustratedMap({
    super.key,
    required this.center,
    required this.controller,
    this.pins = const [],
    this.fence,
    this.baseMetersWide = 340,
    this.fitRadius,
    this.interactive = true,
    this.bottomPadding = 0,
    this.showHome = true,
    this.onLongPress,
  });

  final GeoPoint center;
  final PFMapController controller;
  final List<MapPinData> pins;
  final Geofence? fence;
  final double baseMetersWide;
  final double? fitRadius; // jika diisi, skala otomatis agar radius ini muat di layar
  final bool interactive, showHome;
  final double bottomPadding; // ruang yang tertutup bottom sheet
  final ValueChanged<GeoPoint>? onLongPress;

  @override
  State<IllustratedMap> createState() => _IllustratedMapState();
}

class _IllustratedMapState extends State<IllustratedMap> {
  bool _gesturing = false;
  double _startZoom = 1;

  @override
  Widget build(BuildContext context) {
    final dark = context.pf.isDark;
    return LayoutBuilder(builder: (context, bc) {
      final size = bc.biggest;
      return AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final base = widget.fitRadius != null ? (math.min(size.width, size.height - widget.bottomPadding) * 0.40) / widget.fitRadius! : size.width / widget.baseMetersWide;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: base * c.zoom),
            duration: _gesturing ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, scale, _) {
              final origin = Offset(size.width / 2, (size.height - widget.bottomPadding) / 2) + c.pan;
              final fence = widget.fence;
              final fencePx = fence == null ? null : origin + metersOffset(widget.center, fence.center) * scale;
              final stack = Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MapPainter(
                        scale: scale,
                        origin: origin,
                        worldShift: metersOffset(const GeoPoint(kHomeLat, kHomeLng), widget.center),
                        dark: dark,
                        fenceCenter: fencePx,
                        fenceRadius: fence == null ? 0 : fence.radius * scale,
                      ),
                    ),
                  ),
                  if (fence != null && widget.showHome && fencePx != null)
                    Positioned(left: fencePx.dx - 18, top: fencePx.dy - 18, child: const _HomeBadge()),
                  for (final pin in widget.pins)
                    TweenAnimationBuilder<Offset>(
                      key: ValueKey(pin.id),
                      tween: Tween<Offset>(end: metersOffset(widget.center, pin.point)),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeInOut,
                      builder: (_, m, child) => Positioned(left: origin.dx + m.dx * scale - pin.size / 2, top: origin.dy + m.dy * scale - pin.size / 2, width: pin.size, height: pin.size, child: child!),
                      child: pin.child,
                    ),
                ],
              );
              if (!widget.interactive) return stack;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _gesturing = true;
                  _startZoom = c.zoom;
                },
                onScaleUpdate: (d) => c.update(panDelta: d.focalPointDelta, zoom: d.scale != 1.0 ? _startZoom * d.scale : null),
                onScaleEnd: (_) => _gesturing = false,
                onLongPressStart: widget.onLongPress == null ? null : (d) => widget.onLongPress!(offsetToPoint(widget.center, (d.localPosition - origin) / scale)),
                child: stack,
              );
            },
          );
        },
      );
    });
  }
}

class _HomeBadge extends StatelessWidget {
  const _HomeBadge();
  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))]),
        child: const Icon(Icons.home_outlined, size: 20, color: PF.primary),
      );
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.scale, required this.origin, required this.worldShift, required this.dark, this.fenceCenter, this.fenceRadius = 0});

  final double scale;
  final Offset origin, worldShift;
  final bool dark;
  final Offset? fenceCenter;
  final double fenceRadius;

  static const double cell = 100, road = 20;

  int _hash(int i, int j) => ((i * 73856093) ^ (j * 19349663)) & 0x7fffffff;

  Offset _px(double wx, double wy) => Offset(origin.dx + (wx - worldShift.dx) * scale, origin.dy + (wy - worldShift.dy) * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final ground = dark ? const Color(0xFF1B2542) : const Color(0xFFF1F5F1);
    final block = dark ? const Color(0xFF243153) : const Color(0xFFDDE5DF);
    final park = dark ? const Color(0xFF1F3C36) : const Color(0xFFCDE4CF);
    final river = dark ? const Color(0xFF21457A) : const Color(0xFFC6DBF4);
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);

    double wx(double px) => worldShift.dx + (px - origin.dx) / scale;
    double wy(double py) => worldShift.dy + (py - origin.dy) / scale;
    final minX = wx(0), maxX = wx(size.width), minY = wy(0), maxY = wy(size.height);
    final cellPx = cell * scale;

    final i0 = (minX / cell).floor(), i1 = (maxX / cell).ceil(), j0 = (minY / cell).floor(), j1 = (maxY / cell).ceil();
    if (cellPx >= 5 && (i1 - i0) * (j1 - j0) < 7000) {
      final blockPaint = Paint()..color = block;
      final parkPaint = Paint()..color = park;
      final rad = Radius.circular(math.max(1.5, 9 * scale));
      for (var i = i0; i < i1; i++) {
        for (var j = j0; j < j1; j++) {
          final h = _hash(i, j);
          final isPark = h % 9 == 0;
          final x = i * cell + road / 2, y = j * cell + road / 2, b = cell - road;
          if (cellPx > 60 && !isPark) {
            const gap = 8.0;
            final s = (b - gap) / 2;
            for (var a = 0; a < 2; a++) {
              for (var k = 0; k < 2; k++) {
                final tl = _px(x + a * (s + gap), y + k * (s + gap));
                canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tl.dx, tl.dy, s * scale, s * scale), rad), blockPaint);
              }
            }
          } else {
            final tl = _px(x, y);
            canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tl.dx, tl.dy, b * scale, b * scale), rad), isPark ? parkPaint : blockPaint);
          }
        }
      }
    }

    // Jalan arteri diagonal
    final roadPaint = Paint()
      ..color = dark ? const Color(0xFF2E3B63) : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, 26 * scale)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(_px(-3000, 900), _px(3000, -1100), roadPaint);

    // Sungai
    final riverPath = Path();
    final step = math.max(20.0, (maxY - minY) / 60);
    var first = true;
    for (var y = minY - step; y <= maxY + step; y += step) {
      final x = 200 + 60 * math.sin(y / 190);
      final p = _px(x, y);
      if (first) {
        riverPath.moveTo(p.dx, p.dy);
        first = false;
      } else {
        riverPath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(riverPath, Paint()..color = river..style = PaintingStyle.stroke..strokeWidth = math.max(3, 46 * scale)..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);

    // Label
    if (scale > 0.18) {
      _label(canvas, 'Jl. Melati', _px(-130, 50), -0.0);
      _label(canvas, 'Sleman', _px(110, -170), 0);
      _label(canvas, 'Kali Code', _px(215, 150), 1.5708);
    }

    // Geofence
    if (fenceCenter != null && fenceRadius > 0) {
      canvas.drawCircle(fenceCenter!, fenceRadius, Paint()..color = PF.primary.o(0.20));
      canvas.drawCircle(fenceCenter!, fenceRadius, Paint()..color = PF.primary..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  void _label(Canvas canvas, String text, Offset at, double rotate) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: dark ? const Color(0xFF8FA0C8) : const Color(0xFF8A96A8))),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(rotate);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter o) =>
      o.scale != scale || o.origin != origin || o.worldShift != worldShift || o.dark != dark || o.fenceCenter != fenceCenter || o.fenceRadius != fenceRadius;
}

// ---------------------------------------------------------------------------
// Komponen pendukung peta
// ---------------------------------------------------------------------------

/// Pin hewan: avatar bulat dengan ring biru + pulse.
class MapPetPin extends StatelessWidget {
  const MapPetPin({super.key, required this.pet, this.size = 84});
  final Pet pet;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (pet.device.online) PulseRing(size: size),
        Container(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: PF.primary.o(0.35), blurRadius: 14, offset: const Offset(0, 4))]),
          child: PetFace(pet: pet, size: 46, ring: true),
        ),
      ],
    );
  }
}

/// Label status mengambang di atas peta (mis. "GPS aktif · Baru diperbarui").
class MapChip extends StatelessWidget {
  const MapChip({super.key, required this.icon, required this.label, this.color = PF.primary});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: p.surface.o(0.94), borderRadius: BorderRadius.circular(PF.rChip), boxShadow: softShadow(p)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color))),
      ]),
    );
  }
}

class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});
  @override
  Widget build(BuildContext context) => Text('PawFinder · Peta ilustratif', style: context.tx.micro.copyWith(fontSize: 10));
}
