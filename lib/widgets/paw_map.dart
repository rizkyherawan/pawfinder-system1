import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/geo.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'buttons.dart';
import 'map_view.dart';
import 'pet_art.dart';
import 'pet_face.dart';

/// Penanda hewan pada peta.
class PawPin {
  const PawPin({required this.pet, required this.point, this.size = 88, this.compact = false});
  final Pet pet;
  final GeoPoint point;
  final double size;
  final bool compact; // ikon lebih kecil (mis. pada peta geofence)
}

/// Pengendali peta: sama untuk Google Maps maupun peta ilustratif (cadangan).
class PawMapController {
  final PFMapController ill = PFMapController();
  gm.GoogleMapController? _g;
  double baseMetersWide = 340; // dipakai peta ilustratif
  Size size = Size.zero;

  void attach(gm.GoogleMapController c) => _g = c;
  void detach() => _g = null;

  Future<void> zoomIn() async {
    final g = _g;
    if (g == null) {
      ill.zoomBy(1.4);
      return;
    }
    try {
      await g.animateCamera(gm.CameraUpdate.zoomIn());
    } catch (_) {}
  }

  Future<void> zoomOut() async {
    final g = _g;
    if (g == null) {
      ill.zoomBy(1 / 1.4);
      return;
    }
    try {
      await g.animateCamera(gm.CameraUpdate.zoomOut());
    } catch (_) {}
  }

  Future<void> moveTo(GeoPoint p) async {
    final g = _g;
    if (g == null) {
      ill.reset();
      return;
    }
    try {
      await g.animateCamera(gm.CameraUpdate.newLatLng(gm.LatLng(p.lat, p.lng)));
    } catch (_) {}
  }

  /// Dipanggil setelah slider radius dilepas: zoom keluar HANYA bila lingkaran tidak lagi muat di layar.
  /// Selama slider digeser kamera tidak berubah, sehingga lingkaran terlihat membesar/mengecil sesuai radius.
  Future<void> ensureCircleVisible(GeoPoint c, double radius) async {
    final g = _g;
    if (g != null) {
      try {
        final vis = await g.getVisibleRegion();
        final n = movePoint(c, 0, radius), e = movePoint(c, math.pi / 2, radius), s = movePoint(c, math.pi, radius), w = movePoint(c, 3 * math.pi / 2, radius);
        bool inside(GeoPoint p) => vis.contains(gm.LatLng(p.lat, p.lng));
        if (!(inside(n) && inside(e) && inside(s) && inside(w))) {
          await g.animateCamera(gm.CameraUpdate.newLatLngBounds(gm.LatLngBounds(southwest: gm.LatLng(s.lat, w.lng), northeast: gm.LatLng(n.lat, e.lng)), 48));
        }
      } catch (_) {}
    } else if (size != Size.zero) {
      final scale = size.width / baseMetersWide * ill.zoom;
      final dia = 2 * radius * scale;
      final side = math.min(size.width, size.height);
      if (dia > side * 0.92) ill.update(zoom: ill.zoom * (side * 0.8) / dia);
    }
  }

  void dispose() => ill.dispose();
}

/// Peta utama aplikasi. Memakai Google Maps; bila pengguna memilih "Ilustratif" di Pengaturan
/// (mis. API key belum dipasang), dipakai peta ilustratif bawaan.
class PawMap extends StatefulWidget {
  const PawMap({
    super.key,
    required this.controller,
    required this.center,
    this.pins = const [],
    this.fence,
    this.initialZoom = 17,
    this.fitRadius,
    this.bottomPadding = 0,
    this.onLongPress,
    this.showHome = true,
    this.interactive = true,
  });

  final PawMapController controller;
  final GeoPoint center;
  final List<PawPin> pins;
  final Geofence? fence;
  final double initialZoom;
  final double? fitRadius; // jika diisi: zoom awal diatur agar lingkaran dengan radius ini muat
  final double bottomPadding;
  final ValueChanged<GeoPoint>? onLongPress;
  final bool showHome, interactive;

  @override
  State<PawMap> createState() => _PawMapState();
}

class _PawMapState extends State<PawMap> {
  double? _base;

  @override
  Widget build(BuildContext context) {
    final provider = context.select<AppState, String>((s) => s.settings.mapProvider);
    return LayoutBuilder(builder: (context, bc) {
      widget.controller.size = bc.biggest;
      if (provider == 'google' && AppConfig.googleMapsSupported) {
        return _GoogleMapView(map: widget, size: bc.biggest);
      }
      _base ??= widget.fitRadius != null ? widget.fitRadius! * 2 / 0.62 : 340;
      widget.controller.baseMetersWide = _base!;
      return IllustratedMap(
        center: widget.center,
        controller: widget.controller.ill,
        fence: widget.fence,
        baseMetersWide: _base!,
        bottomPadding: widget.bottomPadding,
        showHome: widget.showHome,
        interactive: widget.interactive,
        onLongPress: widget.onLongPress,
        pins: [
          for (final pin in widget.pins)
            MapPinData(
              id: pin.pet.id,
              point: pin.point,
              size: pin.size,
              child: Center(child: pin.compact ? PetFace(pet: pin.pet, size: 36, ring: true) : MapPetPin(pet: pin.pet, size: pin.size - 8)),
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Google Maps
// ---------------------------------------------------------------------------

class _Track {
  _Track(this.from, this.to, this.start) : cur = from;
  GeoPoint from, to, cur;
  DateTime start;
}

class _GoogleMapView extends StatefulWidget {
  const _GoogleMapView({required this.map, required this.size});
  final PawMap map;
  final Size size;

  @override
  State<_GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<_GoogleMapView> {
  final Map<String, gm.BitmapDescriptor> _icons = {};
  final Set<String> _building = {};
  final Map<String, _Track> _tracks = {};
  Timer? _timer;
  double _phase = 0;
  late final gm.CameraPosition _initial;

  PawMap get m => widget.map;

  static const _darkStyle =
      '[{"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},'
      '{"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},'
      '{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},'
      '{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#023e58"}]}]';

  @override
  void initState() {
    super.initState();
    var zoom = m.initialZoom;
    if (m.fitRadius != null) {
      final side = math.min(widget.size.width, math.max(120.0, widget.size.height - m.bottomPadding));
      final mpp = (2 * m.fitRadius! * 1.5) / side; // meter per piksel yang diinginkan
      zoom = (math.log(156543.03392 * math.cos(m.center.lat * math.pi / 180) / mpp) / math.ln2).clamp(3.0, 19.0).toDouble();
    }
    _initial = gm.CameraPosition(target: gm.LatLng(m.center.lat, m.center.lng), zoom: zoom);
    _syncTracks();
    _ensureTimer();
  }

  @override
  void didUpdateWidget(covariant _GoogleMapView old) {
    super.didUpdateWidget(old);
    _syncTracks();
    _ensureTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    m.controller.detach();
    super.dispose();
  }

  // ---- animasi gerak pin & denyut ----
  void _syncTracks() {
    final now = DateTime.now();
    final ids = <String>{};
    for (final pin in m.pins) {
      ids.add(pin.pet.id);
      final t = _tracks[pin.pet.id];
      if (t == null) {
        _tracks[pin.pet.id] = _Track(pin.point, pin.point, now);
      } else if (distanceMeters(t.to, pin.point) > 0.3) {
        t.from = t.cur;
        t.to = pin.point;
        t.start = now;
      }
    }
    _tracks.removeWhere((k, _) => !ids.contains(k));
  }

  void _ensureTimer() {
    final need = m.pins.any((p) => p.pet.device.online);
    if (need && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final now = DateTime.now();
        for (final t in _tracks.values) {
          final p = (now.difference(t.start).inMilliseconds / 900).clamp(0.0, 1.0).toDouble();
          final e = Curves.easeInOut.transform(p);
          t.cur = GeoPoint(t.from.lat + (t.to.lat - t.from.lat) * e, t.from.lng + (t.to.lng - t.from.lng) * e);
        }
        _phase = (now.millisecondsSinceEpoch % 2000) / 2000;
        if (mounted) setState(() {});
      });
    } else if (!need && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  // ---- ikon marker ----
  String _petKey(PawPin pin, Uint8List? photo, bool dark) => '${pin.pet.species.name}|${pin.pet.avatarColor}|${pin.pet.photoVersion}|${photo != null}|${pin.compact}|${pin.pet.device.online}|$dark';

  void _prepareIcons(AppState app, bool dark) {
    final jobs = <String, Future<gm.BitmapDescriptor>>{};
    for (final pin in m.pins) {
      final photo = app.photoBytes(pin.pet);
      final key = _petKey(pin, photo, dark);
      if (_icons.containsKey(key) || _building.contains(key)) continue;
      jobs[key] = _MarkerIcons.pet(pin.pet, photo, size: pin.compact ? 40 : 56, dim: !pin.pet.device.online, dark: dark);
    }
    final homeKey = 'home|$dark';
    if (m.fence != null && m.showHome && !_icons.containsKey(homeKey) && !_building.contains(homeKey)) jobs[homeKey] = _MarkerIcons.home(dark: dark);
    if (jobs.isEmpty) return;
    _building.addAll(jobs.keys);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final e in jobs.entries) {
        try {
          _icons[e.key] = await e.value;
        } catch (_) {}
        _building.remove(e.key);
      }
      if (mounted) setState(() {});
    });
  }

  Set<gm.Marker> _markers(AppState app, bool dark) {
    final out = <gm.Marker>{};
    for (final pin in m.pins) {
      final p = _tracks[pin.pet.id]?.cur ?? pin.point;
      out.add(gm.Marker(
        markerId: gm.MarkerId('pet-${pin.pet.id}'),
        position: gm.LatLng(p.lat, p.lng),
        anchor: const Offset(0.5, 0.5),
        icon: _icons[_petKey(pin, app.photoBytes(pin.pet), dark)] ?? gm.BitmapDescriptor.defaultMarker,
        infoWindow: gm.InfoWindow(title: pin.pet.name),
      ));
    }
    final f = m.fence;
    if (f != null && m.showHome) {
      final icon = _icons['home|$dark'];
      if (icon != null) out.add(gm.Marker(markerId: const gm.MarkerId('home'), position: gm.LatLng(f.center.lat, f.center.lng), anchor: const Offset(0.5, 0.5), icon: icon, consumeTapEvents: true));
    }
    return out;
  }

  Set<gm.Circle> _circles() {
    final out = <gm.Circle>{};
    final f = m.fence;
    if (f != null) {
      out.add(gm.Circle(
        circleId: const gm.CircleId('fence'),
        center: gm.LatLng(f.center.lat, f.center.lng),
        radius: f.radius,
        fillColor: PF.primary.o(0.20),
        strokeColor: PF.primary,
        strokeWidth: 2,
      ));
    }
    for (final pin in m.pins) {
      if (!pin.pet.device.online) continue;
      final p = _tracks[pin.pet.id]?.cur ?? pin.point;
      out.add(gm.Circle(
        circleId: gm.CircleId('pulse-${pin.pet.id}'),
        center: gm.LatLng(p.lat, p.lng),
        radius: 4 + 26 * _phase,
        fillColor: PF.primary.o(0.30 * (1 - _phase)),
        strokeWidth: 0,
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = context.pf.isDark;
    _prepareIcons(app, dark);
    return gm.GoogleMap(
      initialCameraPosition: _initial,
      onMapCreated: (c) => m.controller.attach(c),
      markers: _markers(app, dark),
      circles: _circles(),
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: m.interactive,
      zoomGesturesEnabled: m.interactive,
      padding: EdgeInsets.only(bottom: m.bottomPadding),
      style: dark ? _darkStyle : null,
      onLongPress: m.onLongPress == null ? null : (p) => m.onLongPress!(GeoPoint(p.latitude, p.longitude)),
      // Peta di dalam ListView harus menerima gestur geser lebih dulu.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
    );
  }
}

class _MarkerIcons {
  static const double ratio = 3.0;

  /// Marker avatar bulat (foto atau ilustrasi) dengan cincin biru, digambar langsung ke bitmap.
  static Future<gm.BitmapDescriptor> pet(Pet pet, Uint8List? photo, {required double size, required bool dim, required bool dark}) async {
    final px = size * ratio;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, px, px));
    final r = px / 2;
    final accent = dim ? const Color(0xFF9AA8C7) : PF.primary;
    c.drawCircle(Offset(r, r), r, Paint()..color = accent.o(0.22));
    final ro = r * 0.80;
    c.drawCircle(Offset(r, r), ro, Paint()..color = Colors.white);
    c.drawCircle(Offset(r, r), ro, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = px * 0.05);
    final ra = ro - px * 0.05;
    final rect = Rect.fromCircle(center: Offset(r, r), radius: ra);
    c.save();
    c.clipPath(Path()..addOval(rect));
    if (photo != null) {
      final codec = await ui.instantiateImageCodec(photo, targetWidth: (ra * 2).round());
      final img = (await codec.getNextFrame()).image;
      final side = math.min(img.width, img.height).toDouble();
      final src = Rect.fromCenter(center: Offset(img.width / 2, img.height / 2), width: side, height: side);
      c.drawImageRect(img, src, rect, Paint()..filterQuality = FilterQuality.medium);
    } else {
      c.drawRect(rect, Paint()..color = (dark ? kAvatarBgsDark : kAvatarBgsLight)[pet.avatarColor.abs() % 6]);
      c.translate(rect.left, rect.top);
      PetPainter(pet.species).paint(c, Size(ra * 2, ra * 2));
    }
    c.restore();
    final image = await rec.endRecording().toImage(px.round(), px.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return gm.BitmapDescriptor.bytes(data!.buffer.asUint8List(), imagePixelRatio: ratio);
  }

  /// Penanda pusat geofence (ikon rumah).
  static Future<gm.BitmapDescriptor> home({required bool dark}) async {
    final px = 40 * ratio;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, px, px));
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(px * 0.08, px * 0.08, px * 0.84, px * 0.84), Radius.circular(px * 0.26));
    c.drawShadow(Path()..addRRect(rr), Colors.black, 3, false);
    c.drawRRect(rr, Paint()..color = dark ? const Color(0xFF131C36) : Colors.white);
    const icon = Icons.home_outlined;
    final tp = TextPainter(
      text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: px * 0.52, fontFamily: icon.fontFamily, package: icon.fontPackage, color: PF.primary)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset((px - tp.width) / 2, (px - tp.height) / 2));
    final image = await rec.endRecording().toImage(px.round(), px.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return gm.BitmapDescriptor.bytes(data!.buffer.asUint8List(), imagePixelRatio: ratio);
  }
}

/// Kontrol zoom + / − (dan tombol pusatkan) untuk kedua jenis peta.
class MapZoomControls extends StatelessWidget {
  const MapZoomControls({super.key, required this.controller, this.onLocate, this.showLocate = true});
  final PawMapController controller;
  final VoidCallback? onLocate;
  final bool showLocate;

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), boxShadow: softShadow(p), border: Border.all(color: p.border)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        PFIconButton(icon: Icons.add_rounded, label: 'Perbesar peta', border: false, background: Colors.transparent, onTap: controller.zoomIn),
        Container(width: 24, height: 1, color: p.border),
        PFIconButton(icon: Icons.remove_rounded, label: 'Perkecil peta', border: false, background: Colors.transparent, onTap: controller.zoomOut),
        if (showLocate) ...[
          Container(width: 24, height: 1, color: p.border),
          PFIconButton(icon: Icons.my_location_rounded, label: 'Pusatkan peta', border: false, background: Colors.transparent, color: PF.primary, onTap: onLocate),
        ],
      ]),
    );
  }
}
