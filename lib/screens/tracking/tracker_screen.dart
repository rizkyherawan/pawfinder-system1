import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/data_source.dart';
import '../../state/app_state.dart';
import '../../widgets/cards.dart';
import '../../widgets/common.dart';
import '../../widgets/map_view.dart';
import '../../widgets/pair_sheet.dart';
import '../../widgets/paw_map.dart';
import '../../widgets/pet_picker.dart';
import 'device_detail_screen.dart';
import 'location_view_screen.dart';
import 'pet_sheet.dart';

/// Pelacak Perangkat GPS: peta penuh, pin hewan dengan pulse, bottom sheet sesuai status koneksi.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  final _map = PawMapController();
  GeoPoint? _center;
  String? _centerPetId;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _menu(AppState s) {
    final pet = s.selectedPet;
    if (pet == null) return;
    showPFSheet<void>(
      context,
      title: pet.name,
      builder: (ctx) => TileGroup(children: [
        MenuTile(icon: Icons.memory_rounded, label: 'Detail Perangkat', subtitle: 'Koneksi, baterai, sinyal, firmware', onTap: () {
          Navigator.of(ctx).pop();
          pushPage(context, const DeviceDetailScreen());
        }),
        if (!pet.device.paired)
          MenuTile(icon: Icons.link_rounded, label: 'Hubungkan GPS', subtitle: 'Pasangkan kalung dengan nomor seri', onTap: () {
            Navigator.of(ctx).pop();
            showPairSheet(context, pet);
          }),
        MenuTile(icon: Icons.location_on_outlined, label: 'Pengaturan Geofence', subtitle: 'Atur area aman', onTap: () {
          Navigator.of(ctx).pop();
          backToRoot(context);
          s.setTab(2);
        }),
        if (pet.device.online)
          MenuTile(icon: Icons.volume_up_outlined, label: 'Bunyikan Kalung', subtitle: 'Bantu menemukan hewan di dekatmu', onTap: () async {
            Navigator.of(ctx).pop();
            try {
              final msg = await s.pingDevice(pet.id);
              if (mounted) showToast(context, msg, kind: ToastKind.success);
            } catch (e) {
              if (mounted) showToast(context, errorText(e), kind: ToastKind.error);
            }
          }),
        if (s.pets.length > 1)
          MenuTile(icon: Icons.swap_horiz_rounded, label: 'Ganti Hewan', subtitle: 'Pilih hewan lain untuk dilacak', onTap: () {
            Navigator.of(ctx).pop();
            showPetPicker(context, s);
          }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pet = s.selectedPet;
    final p = context.pf;
    if (pet == null) {
      return const Scaffold(body: Column(children: [PFTopBar(title: 'Pelacak Perangkat GPS'), Expanded(child: Center(child: Text('Belum ada hewan.')))]));
    }
    final fence = s.cachedFence(pet.id);
    if (fence == null) s.ensureGeofence(pet.id);
    // Pusat peta mengikuti hewan yang dipilih; bila belum punya lokasi, pakai pusat geofence / rumah.
    if (_centerPetId != pet.id) {
      _centerPetId = pet.id;
      _center = pet.location ?? fence?.center ?? s.focusOf(null);
    }
    final top = context.topInset;
    final chip = switch (pet.device.connection) {
      'online' => MapChip(icon: Icons.sensors_rounded, label: 'GPS aktif · ${updatedAgo(pet.locationUpdatedAt)}'),
      'waiting' => const MapChip(icon: Icons.hourglass_top_rounded, label: 'Menunggu sinyal kalung…', color: PF.warning),
      'offline' => const MapChip(icon: Icons.signal_wifi_off_rounded, label: 'GPS terputus', color: PF.warning),
      _ => MapChip(icon: Icons.link_off_rounded, label: 'GPS belum terhubung', color: p.textSecondary),
    };
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PawMap(
              key: ValueKey('${pet.id}-${s.settings.mapProvider}'),
              controller: _map,
              center: _center!,
              initialZoom: 17,
              bottomPadding: 270,
              fence: fence,
              showHome: false,
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
              child: PFTopBar(title: 'Pelacak Perangkat GPS', onMore: () => _menu(s)),
            ),
          ),
          Positioned(top: top + 76, left: PF.margin, right: 90, child: Align(alignment: Alignment.centerLeft, child: chip)),
          Positioned(
            top: top + 76,
            right: PF.margin,
            child: MapZoomControls(controller: _map, onLocate: () => _map.moveTo(pet.location ?? fence?.center ?? _center!)),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + context.bottomInset,
            child: PetSheet(
              pet: pet,
              fence: fence,
              locationLabel: 'Lihat Lokasi',
              locationIcon: Icons.place_outlined,
              onLocation: () => pushPage(context, const LocationViewScreen()),
              onConnect: () => pet.device.paired ? pushPage(context, const DeviceDetailScreen()) : showPairSheet(context, pet),
              onBatteryTap: () => pushPage(context, const DeviceDetailScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
