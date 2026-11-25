import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/geo.dart';
import '../core/theme.dart';
import '../data/models.dart';
import 'paw_map.dart';
import 'map_view.dart';
import 'pet_face.dart';

class OSMMap extends StatefulWidget {
  const OSMMap({
    super.key,
    required this.controller,
    required this.center,
    this.pins = const [],
    this.initialZoom = 16,
    this.fence,
    this.fitRadius,
    this.onLongPress,
    this.showHome = true,
    this.interactive = true,
  });

  final PawMapController controller;
  final GeoPoint center;
  final List<PawPin> pins;
  final double initialZoom;
  final Geofence? fence;
  final double? fitRadius;
  final ValueChanged<GeoPoint>? onLongPress;
  final bool showHome;
  final bool interactive;

  @override
  State<OSMMap> createState() => _OSMMapState();
}

class _OSMMapState extends State<OSMMap> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  late final AnimationController _motion;

  final Map<String, GeoPoint> _from = {};
  final Map<String, GeoPoint> _to = {};

  // Filter warna khusus peta dalam dark mode.
  static const ColorFilter _darkFilter = ColorFilter.matrix([
    -0.70,
    0.00,
    0.00,
    0.00,
    190,
    0.00,
    -0.70,
    0.00,
    0.00,
    205,
    0.00,
    0.00,
    -0.65,
    0.00,
    220,
    0.00,
    0.00,
    0.00,
    1.00,
    0,
  ]);

  @override
  void initState() {
    super.initState();

    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 1,
    );

    for (final pin in widget.pins) {
      _from[pin.pet.id] = pin.point;
      _to[pin.pet.id] = pin.point;
    }
  }

  // Menghitung posisi avatar selama animasi.
  GeoPoint _position(PawPin pin) {
    if (!pin.pet.device.online) {
      return pin.point;
    }

    final from = _from[pin.pet.id] ?? pin.point;
    final to = _to[pin.pet.id] ?? pin.point;

    final t = Curves.easeInOut.transform(_motion.value);

    return GeoPoint(
      from.lat + (to.lat - from.lat) * t,
      from.lng + (to.lng - from.lng) * t,
    );
  }

  @override
  void didUpdateWidget(covariant OSMMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.controller, widget.controller)) {
      if (identical(oldWidget.controller.osm, _mapController)) {
        oldWidget.controller.osm = null;
        widget.controller.osm = _mapController;
      }
    }

    final ids = widget.pins.map((p) => p.pet.id).toSet();

    _from.removeWhere((id, _) => !ids.contains(id));
    _to.removeWhere((id, _) => !ids.contains(id));

    final changed = widget.pins.any((pin) {
      final target = _to[pin.pet.id];

      return target == null ||
          target.lat != pin.point.lat ||
          target.lng != pin.point.lng;
    });

    if (!changed) {
      for (final pin in widget.pins) {
        if (!pin.pet.device.online) {
          _from[pin.pet.id] = pin.point;
          _to[pin.pet.id] = pin.point;
        }
      }
      return;
    }

    final current = <String, GeoPoint>{
      for (final pin in widget.pins) pin.pet.id: _position(pin),
    };

    _from.clear();
    _to.clear();

    bool needsAnimation = false;

    for (final pin in widget.pins) {
      final start = pin.pet.device.online ? current[pin.pet.id]! : pin.point;

      _from[pin.pet.id] = start;
      _to[pin.pet.id] = pin.point;

      if (start.lat != pin.point.lat || start.lng != pin.point.lng) {
        needsAnimation = true;
      }
    }

    if (needsAnimation) {
      _motion.forward(from: 0);
    } else {
      _motion.stop();
      _motion.value = 1;
    }
  }

  @override
  void dispose() {
    if (identical(widget.controller.osm, _mapController)) {
      widget.controller.osm = null;
    }

    _motion.dispose();
    _mapController.dispose();

    super.dispose();
  }

  // Membuka halaman hak cipta OpenStreetMap.
  Future<void> _openAttribution() async {
    final uri = Uri.parse(
      'https://www.openstreetmap.org/copyright',
    );

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Peta tetap dapat digunakan.
    }
  }

  // Lapisan marker hewan dan rumah.
  Widget _buildMarkers(bool dark) {
    final fence = widget.fence;

    return MarkerLayer(
      markers: [
        if (fence != null && widget.showHome)
          Marker(
            point: LatLng(
              fence.center.lat,
              fence.center.lng,
            ),
            width: 42,
            height: 42,
            child: Container(
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1E293B) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF2979FF),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.home_rounded,
                color: Color(0xFF2979FF),
                size: 24,
              ),
            ),
          ),
        for (final pin in widget.pins)
          Marker(
            point: LatLng(
              _position(pin).lat,
              _position(pin).lng,
            ),
            width: pin.size,
            height: pin.size,
            child: Center(
              child: pin.compact
                  ? PetFace(
                      pet: pin.pet,
                      size: 36,
                      ring: true,
                    )
                  : MapPetPin(
                      pet: pin.pet,
                      size: pin.size - 8,
                    ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.pf.isDark;
    final fence = widget.fence;
    final radius = widget.fitRadius;
    final center = fence?.center ?? widget.center;

    final tileLayer = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.pawfinder.app',
    );

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(
          widget.center.lat,
          widget.center.lng,
        ),
        initialZoom: widget.initialZoom,
        backgroundColor:
            dark ? const Color(0xFF18232F) : const Color(0xFFE8E8E8),
        initialCameraFit: radius == null
            ? null
            : CameraFit.bounds(
                bounds: LatLngBounds.fromPoints([
                  for (final bearing in [
                    0.0,
                    90.0,
                    180.0,
                    270.0,
                  ])
                    const Distance().offset(
                      LatLng(center.lat, center.lng),
                      radius,
                      bearing,
                    ),
                ]),
                padding: const EdgeInsets.all(40),
              ),
        minZoom: 3,
        maxZoom: 19,
        onMapReady: () {
          widget.controller.osm = _mapController;
        },
        onLongPress: widget.onLongPress == null
            ? null
            : (_, point) {
                widget.onLongPress!(
                  GeoPoint(
                    point.latitude,
                    point.longitude,
                  ),
                );
              },
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        // Peta mengikuti tema aplikasi.
        ColorFiltered(
          colorFilter: dark
              ? _darkFilter
              : const ColorFilter.mode(
                  Colors.transparent,
                  BlendMode.dst,
                ),
          child: tileLayer,
        ),

        // Lingkaran geofence.
        if (fence != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(
                  fence.center.lat,
                  fence.center.lng,
                ),
                radius: fence.radius,
                useRadiusInMeter: true,
                color: dark ? const Color(0x4034C759) : const Color(0x2634C759),
                borderColor:
                    dark ? const Color(0xFF4ADE80) : const Color(0xFF34C759),
                borderStrokeWidth: 2,
              ),
            ],
          ),

        // Hanya marker yang diperbarui selama animasi.
        AnimatedBuilder(
          animation: _motion,
          builder: (context, child) {
            return _buildMarkers(dark);
          },
        ),

        // Atribusi OpenStreetMap.
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: RotatedBox(
              quarterTurns: 3,
              child: Material(
                color: dark ? const Color(0xDD1E293B) : const Color(0xDDFFFFFF),
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  onTap: _openAttribution,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(
                        fontSize: 10,
                        color: dark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
