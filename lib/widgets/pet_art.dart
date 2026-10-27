import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import 'common.dart';

const kAvatarBgsLight = [Color(0xFFFCEBD0), Color(0xFFFFE3D3), Color(0xFFE3ECFF), Color(0xFFE5F6E8), Color(0xFFF0E6FF), Color(0xFFFFE3EC)];
const kAvatarBgsDark = [Color(0xFF4A3A22), Color(0xFF4A2E22), Color(0xFF1E3260), Color(0xFF1F3F2A), Color(0xFF3A2C5E), Color(0xFF4F2A38)];

Color avatarBg(BuildContext context, int i) => (context.pf.isDark ? kAvatarBgsDark : kAvatarBgsLight)[i.abs() % 6];

void _oval(Canvas c, double cx, double cy, double w, double h, Color color, {double rotate = 0}) {
  c.save();
  c.translate(cx, cy);
  c.rotate(rotate);
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: w, height: h), Paint()..color = color);
  c.restore();
}

void _circle(Canvas c, double cx, double cy, double r, Color color) => c.drawCircle(Offset(cx, cy), r, Paint()..color = color);

void _stroke(Canvas c, Path p, Color color, double w) =>
    c.drawPath(p, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);

void _line(Canvas c, double x1, double y1, double x2, double y2, Color color, double w) =>
    _stroke(c, Path()..moveTo(x1, y1)..lineTo(x2, y2), color, w);

void _eye(Canvas c, double x, double y, double r, Color dark) {
  _circle(c, x, y, r, dark);
  _circle(c, x - r * 0.3, y - r * 0.35, r * 0.34, Colors.white);
}

void _collar(Canvas c) {
  final band = RRect.fromRectAndRadius(const Rect.fromLTWH(26, 79, 48, 9), const Radius.circular(4.5));
  c.drawRRect(band, Paint()..shader = const LinearGradient(colors: [Color(0xFF4C8DFF), PF.primaryDark], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(band.outerRect));
  _circle(c, 50, 90, 5.4, Colors.white);
  _circle(c, 50, 90, 5.4, Colors.transparent);
  c.drawCircle(const Offset(50, 90), 5.4, Paint()..color = PF.primary..style = PaintingStyle.stroke..strokeWidth = 1.8);
  _circle(c, 50, 90, 1.8, PF.primary);
}

class PetPainter extends CustomPainter {
  PetPainter(this.species, {this.collar = true});
  final Species species;
  final bool collar;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    switch (species) {
      case Species.anjing:
        _dog(canvas);
        break;
      case Species.kucing:
        _cat(canvas);
        break;
      case Species.kelinci:
        _rabbit(canvas);
        break;
    }
    if (collar) _collar(canvas);
    canvas.restore();
  }

  void _dog(Canvas c) {
    const fur = Color(0xFFE0A35A), dark = Color(0xFFB77A36), light = Color(0xFFF6DAA9), ink = Color(0xFF2B1B12);
    _oval(c, 50, 100, 66, 46, fur);
    _oval(c, 24, 48, 18, 36, dark, rotate: 0.3);
    _oval(c, 76, 48, 18, 36, dark, rotate: -0.3);
    _oval(c, 50, 52, 54, 52, fur);
    _oval(c, 50, 65, 30, 21, light);
    _eye(c, 39, 47, 3.6, ink);
    _eye(c, 61, 47, 3.6, ink);
    _oval(c, 50, 58.5, 11, 7.5, ink);
    _stroke(c, Path()..moveTo(50, 62)..lineTo(50, 67)..moveTo(50, 67)..quadraticBezierTo(46, 71, 43, 68)..moveTo(50, 67)..quadraticBezierTo(54, 71, 57, 68), ink, 1.6);
    _oval(c, 50, 72.5, 7, 5, const Color(0xFFF08A8A));
  }

  void _cat(Canvas c) {
    const fur = Color(0xFFEE9A3F), dark = Color(0xFFC9741F), cream = Color(0xFFFFF1DC), pink = Color(0xFFF6B8B0), ink = Color(0xFF2B2B2B);
    _oval(c, 50, 100, 60, 46, fur);
    c.drawPath(Path()..moveTo(24, 50)..lineTo(27, 14)..lineTo(47, 32)..close(), Paint()..color = fur);
    c.drawPath(Path()..moveTo(76, 50)..lineTo(73, 14)..lineTo(53, 32)..close(), Paint()..color = fur);
    c.drawPath(Path()..moveTo(30, 42)..lineTo(31, 23)..lineTo(42, 33)..close(), Paint()..color = pink);
    c.drawPath(Path()..moveTo(70, 42)..lineTo(69, 23)..lineTo(58, 33)..close(), Paint()..color = pink);
    _oval(c, 50, 55, 58, 48, fur);
    _line(c, 50, 33, 50, 41, dark, 2.2);
    _line(c, 42, 34, 43.5, 41, dark, 2.2);
    _line(c, 58, 34, 56.5, 41, dark, 2.2);
    _oval(c, 50, 66, 26, 17, cream);
    _oval(c, 39, 53, 6.5, 8.5, ink);
    _oval(c, 61, 53, 6.5, 8.5, ink);
    _circle(c, 40.5, 50.8, 1.6, Colors.white);
    _circle(c, 62.5, 50.8, 1.6, Colors.white);
    c.drawPath(Path()..moveTo(47, 60)..lineTo(53, 60)..lineTo(50, 64)..close(), Paint()..color = const Color(0xFFE88A8A));
    _stroke(c, Path()..moveTo(50, 64)..quadraticBezierTo(46, 69, 43, 66)..moveTo(50, 64)..quadraticBezierTo(54, 69, 57, 66), ink, 1.3);
    for (final s in [-1.0, 1.0]) {
      _line(c, 50 + s * 18, 63, 50 + s * 36, 59, ink.o(0.45), 1);
      _line(c, 50 + s * 18, 67, 50 + s * 36, 69, ink.o(0.45), 1);
    }
  }

  void _rabbit(Canvas c) {
    const fur = Color(0xFFFBF8F3), edge = Color(0xFFE4DCD0), pink = Color(0xFFF6BDC6), ink = Color(0xFF3A2B2B);
    _oval(c, 50, 100, 60, 46, fur);
    _oval(c, 37, 24, 17, 44, edge, rotate: -0.12);
    _oval(c, 63, 24, 17, 44, edge, rotate: 0.12);
    _oval(c, 37, 24, 15, 42, fur, rotate: -0.12);
    _oval(c, 63, 24, 15, 42, fur, rotate: 0.12);
    _oval(c, 37.5, 26, 7, 30, pink, rotate: -0.12);
    _oval(c, 62.5, 26, 7, 30, pink, rotate: 0.12);
    _oval(c, 50, 62, 54, 46, edge);
    _oval(c, 50, 61.4, 53, 45.2, fur);
    _eye(c, 39, 58, 3.4, ink);
    _eye(c, 61, 58, 3.4, ink);
    _circle(c, 32, 67, 5, pink.o(0.5));
    _circle(c, 68, 67, 5, pink.o(0.5));
    _oval(c, 50, 66, 8, 5.5, pink);
    _stroke(c, Path()..moveTo(50, 68.5)..lineTo(50, 72)..moveTo(50, 72)..quadraticBezierTo(46, 75, 43.5, 72.5)..moveTo(50, 72)..quadraticBezierTo(54, 75, 56.5, 72.5), ink.o(0.8), 1.3);
  }

  @override
  bool shouldRepaint(covariant PetPainter old) => old.species != species || old.collar != collar;
}

/// Avatar hewan bulat: ilustrasi digambar langsung (tanpa aset gambar).
class PetAvatar extends StatelessWidget {
  const PetAvatar({super.key, required this.species, this.size = 56, this.colorIndex = 0, this.ring = false, this.collar = true});
  final Species species;
  final double size;
  final int colorIndex;
  final bool ring, collar;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Semantics(
      image: true,
      label: species.label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: avatarBg(context, colorIndex),
          shape: BoxShape.circle,
          border: ring ? Border.all(color: PF.primary, width: size * 0.07) : Border.all(color: p.surface, width: size > 40 ? 2 : 1),
        ),
        child: ClipOval(child: CustomPaint(size: Size.square(size), painter: PetPainter(species, collar: collar))),
      ),
    );
  }
}

/// Ilustrasi hewan tanpa latar (untuk kartu hero).
class PetFigure extends StatelessWidget {
  const PetFigure({super.key, required this.species, this.size = 160});
  final Species species;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: PetPainter(species));
}

// ---------------------------------------------------------------------------
// Kalung GPS (render ala 3D lembut) dengan gelombang sinyal
// ---------------------------------------------------------------------------

class CollarPainter extends CustomPainter {
  CollarPainter({this.waves = true, this.t = 0});
  final bool waves;
  final double t; // 0..1 untuk animasi gelombang

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final center = Offset(w * 0.5, h * 0.52);
    final ring = Rect.fromCenter(center: center, width: w * 0.86, height: h * 0.5);

    final strapW = h * 0.13;
    final back = Paint()..color = const Color(0xFF3E6FD8)..style = PaintingStyle.stroke..strokeWidth = strapW..strokeCap = StrokeCap.round;
    final front = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF5A93FF), Color(0xFF2D63E8)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(ring)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strapW
      ..strokeCap = StrokeCap.round;
    canvas.drawShadow(Path()..addOval(ring.translate(0, h * 0.07)), Colors.black, 6, false);
    canvas.drawArc(ring, math.pi, math.pi, false, back);
    canvas.drawArc(ring, 0, math.pi, false, front);
    // stitching
    canvas.drawArc(ring.deflate(strapW * 0.28), 0.12, math.pi - 0.24, false, Paint()..color = Colors.white.o(0.35)..style = PaintingStyle.stroke..strokeWidth = 1.2);

    // perangkat
    final dev = Rect.fromCenter(center: Offset(w * 0.5, h * 0.66), width: w * 0.3, height: h * 0.3);
    final devR = RRect.fromRectAndRadius(dev, Radius.circular(h * 0.09));
    canvas.drawShadow(Path()..addRRect(devR.shift(Offset(0, h * 0.02))), Colors.black, 8, false);
    canvas.drawRRect(devR, Paint()..shader = const LinearGradient(colors: [Color(0xFF6BA2FF), Color(0xFF1E5FE0)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(dev));
    canvas.drawRRect(RRect.fromRectAndRadius(dev.deflate(3), Radius.circular(h * 0.08)), Paint()..color = Colors.white.o(0.22)..style = PaintingStyle.stroke..strokeWidth = 1.2);

    // jejak kaki
    final c = dev.center;
    final pad = Paint()..color = Colors.white.o(0.92);
    canvas.drawOval(Rect.fromCenter(center: c.translate(0, h * 0.025), width: w * 0.1, height: h * 0.075), pad);
    for (final d in [const Offset(-0.052, -0.035), const Offset(-0.018, -0.062), const Offset(0.018, -0.062), const Offset(0.052, -0.035)]) {
      canvas.drawOval(Rect.fromCenter(center: c.translate(d.dx * w, d.dy * h + h * 0.02), width: w * 0.034, height: h * 0.05), pad);
    }

    if (waves) {
      for (var i = 0; i < 3; i++) {
        final phase = ((t + i * 0.22) % 1.0);
        final r = w * (0.2 + 0.07 * i);
        final paint = Paint()..color = PF.primary.o(0.5 * (1 - phase * 0.7) * (1 - i * 0.22))..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round;
        final rect = Rect.fromCircle(center: dev.center, radius: r + h * 0.1);
        canvas.drawArc(rect, math.pi - 0.55, 1.1, false, paint);
        canvas.drawArc(rect, -0.55, 1.1, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CollarPainter old) => old.t != t || old.waves != waves;
}

/// Render kalung GPS dengan gelombang sinyal yang beranimasi lembut.
class CollarArt extends StatefulWidget {
  const CollarArt({super.key, this.height = 200, this.animate = true});
  final double height;
  final bool animate;

  @override
  State<CollarArt> createState() => _CollarArtState();
}

class _CollarArtState extends State<CollarArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(size: Size(widget.height * 1.5, widget.height), painter: CollarPainter(t: _c.value)),
    );
  }
}

// ---------------------------------------------------------------------------
// Pin lokasi 3D lembut & cakram geofence
// ---------------------------------------------------------------------------

class _Pin3DPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final shadow = Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.96), width: s.width * 0.5, height: s.height * 0.07);
    canvas.drawOval(shadow, Paint()..color = const Color(0x332A5FB0)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    final r = Rect.fromLTWH(s.width * 0.06, 0, s.width * 0.88, s.height * 0.94);
    final path = pinPath(r);
    canvas.drawPath(path, Paint()..shader = const LinearGradient(colors: [Color(0xFFA9CBF7), Color(0xFF5E97E6)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(r));
    final cx = r.center.dx, cy = r.top + r.width / 2;
    canvas.drawCircle(Offset(cx, cy), r.width * 0.2, Paint()..color = const Color(0xFFE9F2FF));
    canvas.drawCircle(Offset(cx, cy), r.width * 0.2, Paint()..color = Colors.white.o(0.7)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawArc(Rect.fromLTWH(r.left + 6, r.top + 6, r.width - 12, r.width - 12), math.pi * 1.05, math.pi * 0.5, false, Paint()..color = Colors.white.o(0.35)..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class Pin3D extends StatelessWidget {
  const Pin3D({super.key, this.size = 120});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size * 1.25), painter: _Pin3DPainter());
}

class _DiscPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final outer = Rect.fromCenter(center: Offset(s.width / 2, s.height / 2), width: s.width, height: s.height);
    canvas.drawOval(outer, Paint()..color = const Color(0x4D3FC1E8));
    canvas.drawOval(outer, Paint()..color = Colors.white.o(0.85)..style = PaintingStyle.stroke..strokeWidth = 2.2);
    canvas.drawOval(outer.deflate(s.width * 0.1), Paint()..color = Colors.white.o(0.3)..style = PaintingStyle.stroke..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Cakram area aman (geofence) berbentuk elips seperti pada ilustrasi onboarding.
class GeofenceDisc extends StatelessWidget {
  const GeofenceDisc({super.key, this.width = 220});
  final double width;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, width * 0.34), painter: _DiscPainter());
}

/// Latar kota mini (rumah-rumah kecil) untuk ilustrasi geofence.
class MiniCityPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..shader = const LinearGradient(colors: [Color(0xFFDDEBFB), Color(0xFFCFE0F2)], begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(Offset.zero & s));
    final rnd = math.Random(5);
    final roofs = [const Color(0xFF8FB4E8), const Color(0xFFB7CBE6), const Color(0xFF7FA3D6), const Color(0xFFE6B9A8)];
    for (var i = 0; i < 26; i++) {
      final x = rnd.nextDouble() * s.width, y = s.height * (0.18 + rnd.nextDouble() * 0.5);
      final k = 0.6 + (y / s.height);
      final bw = 22 * k, bh = 16 * k;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, bw, bh), const Radius.circular(2)), Paint()..color = Colors.white.o(0.9));
      canvas.drawPath(Path()..moveTo(x - 2, y)..lineTo(x + bw / 2, y - 10 * k)..lineTo(x + bw + 2, y)..close(), Paint()..color = roofs[i % roofs.length]);
    }
    for (var i = 0; i < 12; i++) {
      final x = rnd.nextDouble() * s.width, y = s.height * (0.3 + rnd.nextDouble() * 0.6);
      canvas.drawCircle(Offset(x, y), 7 + rnd.nextDouble() * 5, Paint()..color = const Color(0xFF9CC9A0).o(0.8));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
