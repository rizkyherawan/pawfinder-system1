import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/map_view.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/paw_map.dart';
import 'device_detail_screen.dart';
import 'pet_sheet.dart';

/// Lihat Lokasi di Peta: peta dengan pin + lingkaran geofence (skala nyata) dan tombol navigasi.
class LocationViewScreen extends StatefulWidget {
  const LocationViewScreen({super.key});

  @override
  State<LocationViewScreen> createState() => _LocationViewScreenState();
}

class _LocationViewScreenState extends State<LocationViewScreen> {
  final _map = PawMapController();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _navigate(GeoPoint? loc) async {
    if (loc == null) {
      showToast(context, 'Lokasi hewan belum tersedia', kind: ToastKind.error);
      return;
    }
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${loc.lat},${loc.lng}&travelmode=walking');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showToast(context, 'Tidak dapat membuka aplikasi peta', kind: ToastKind.error);
    } catch (_) {
      if (mounted) showToast(context, 'Tidak dapat membuka aplikasi peta', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pet = s.selectedPet;
    final p = context.pf;
    if (pet == null) return const Scaffold(body: Column(children: [PFTopBar(title: 'Lihat Lokasi di Peta'), Expanded(child: Center(child: Text('Belum ada hewan.')))]));
    final fence = s.cachedFence(pet.id);
    if (fence == null) s.ensureGeofence(pet.id);
    final center = fence?.center ?? pet.location ?? s.focusOf(null);
    final top = context.topInset;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PawMap(
              key: ValueKey('${pet.id}-${fence?.radius.round()}-${s.settings.mapProvider}'),
              controller: _map,
              center: center,
              fence: fence,
              fitRadius: fence == null ? null : fence.radius * 1.1,
              initialZoom: 16,
              bottomPadding: 270,
              pins: [if (pet.location != null && pet.device.paired) PawPin(pet: pet, point: pet.location!)],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.background.o(0.95), p.background.o(0)])),
              padding: const EdgeInsets.only(bottom: 14),
              child: PFTopBar(title: 'Lihat Lokasi di Peta', onMore: () => pushPage(context, const DeviceDetailScreen())),
            ),
          ),
          Positioned(
            top: top + 76,
            left: PF.margin,
            right: 90,
            child: Align(
              alignment: Alignment.centerLeft,
              child: MapChip(icon: Icons.home_outlined, label: fence == null ? pet.geofenceName : '${fence.name} · Radius ${fmtRadius(fence.radius)}'),
            ),
          ),
          Positioned(top: top + 76, right: PF.margin, child: MapZoomControls(controller: _map, onLocate: () => _map.moveTo(pet.location ?? center))),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + context.bottomInset,
            child: PetSheet(
              pet: pet,
              fence: fence,
              locationLabel: 'Navigasi ke Lokasi',
              locationIcon: Icons.navigation_outlined,
              onLocation: () => _navigate(pet.location),
              onConnect: () => pet.device.paired ? pushPage(context, const DeviceDetailScreen()) : showPairSheet(context, pet),
              onBatteryTap: () => pushPage(context, const DeviceDetailScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
